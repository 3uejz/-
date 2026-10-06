// Package store 根据配置构建各领域的持久化实现：
// 配置了 DATABASE_URL 时使用 PostgreSQL（元数据）+ 对象存储（文档体），
// 否则使用进程内内存实现，便于本地开发与测试。
package store

import (
	"context"
	"log/slog"
	"path/filepath"

	"lifetextsandbox/server/internal/admin"
	"lifetextsandbox/server/internal/auth"
	"lifetextsandbox/server/internal/blob"
	"lifetextsandbox/server/internal/config"
	"lifetextsandbox/server/internal/db"
	"lifetextsandbox/server/internal/httpx"
	"lifetextsandbox/server/internal/legacy"
	"lifetextsandbox/server/internal/rediscache"
	"lifetextsandbox/server/internal/saves"
	"lifetextsandbox/server/internal/telemetry"
)

// Deps 汇总各领域的存储实现。
type Deps struct {
	Auth      auth.Store
	Saves     saves.Store
	Legacy    legacy.Store
	Telemetry telemetry.Store
	Admin     admin.Store
	Limiter   httpx.Limiter
	Close     func()
}

// Build 依据配置构建存储。
func Build(ctx context.Context, cfg config.Config, logger *slog.Logger) (Deps, error) {
	limiter, closeCache := buildLimiter(ctx, cfg, logger)

	if cfg.DatabaseURL == "" {
		return Deps{
			Auth:      auth.NewMemoryStore(),
			Saves:     saves.NewMemoryStore(),
			Legacy:    legacy.NewMemoryStore(),
			Telemetry: telemetry.NewMemoryStore(),
			Admin:     admin.NewMemoryStore(),
			Limiter:   limiter,
			Close:     closeCache,
		}, nil
	}

	database, err := db.Open(ctx, cfg.DatabaseURL)
	if err != nil {
		return Deps{}, err
	}
	if err := database.Migrate(ctx); err != nil {
		database.Close()
		return Deps{}, err
	}

	var blobs blob.Store
	if cfg.HasObjectStore() {
		m, err := blob.NewMinIOStore(ctx, cfg.ObjectEndpoint, cfg.ObjectKey, cfg.ObjectSecret, cfg.ObjectBucket, false)
		if err != nil {
			database.Close()
			return Deps{}, err
		}
		blobs = m
		logger.Info("对象存储: MinIO", "endpoint", cfg.ObjectEndpoint, "bucket", cfg.ObjectBucket)
	} else {
		local, err := blob.NewLocalStore(filepath.Join(cfg.DataDir, "objects"))
		if err != nil {
			database.Close()
			return Deps{}, err
		}
		blobs = local
		logger.Info("对象存储: 本地目录", "dir", filepath.Join(cfg.DataDir, "objects"))
	}

	logger.Info("持久化: PostgreSQL")
	return Deps{
		Auth:      auth.NewPGStore(database.Pool),
		Saves:     saves.NewPGStore(database.Pool, blobs),
		Legacy:    legacy.NewPGStore(database.Pool),
		Telemetry: telemetry.NewPGStore(database.Pool),
		Admin:     admin.NewPGStore(database.Pool),
		Limiter:   limiter,
		Close: func() {
			closeCache()
			database.Close()
		},
	}, nil
}

// buildLimiter 优先使用 Redis 共享限流；未配置或连接失败时回退进程内限流。
func buildLimiter(ctx context.Context, cfg config.Config, logger *slog.Logger) (httpx.Limiter, func()) {
	if cfg.RedisURL == "" {
		return httpx.NewRateLimiter(cfg.RateLimitRPS * 60), func() {}
	}
	client, err := rediscache.Open(ctx, cfg.RedisURL)
	if err != nil {
		logger.Warn("Redis 不可用，回退进程内限流", "error", err)
		return httpx.NewRateLimiter(cfg.RateLimitRPS * 60), func() {}
	}
	logger.Info("限流: Redis", "url", cfg.RedisURL)
	return rediscache.NewRateLimiter(client, cfg.RateLimitRPS*60), func() { _ = client.Close() }
}
