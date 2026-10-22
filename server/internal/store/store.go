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
	Blobs     blob.Store
	Limiter   httpx.Limiter
	Close     func()
}

// Build 依据配置构建存储。
func Build(ctx context.Context, cfg config.Config, logger *slog.Logger) (Deps, error) {
	limiter, closeCache := buildLimiter(ctx, cfg, logger)
	blobs, err := buildBlobs(ctx, cfg, logger)
	if err != nil {
		closeCache()
		return Deps{}, err
	}

	if cfg.DatabaseURL == "" {
		return Deps{
			Auth:      auth.NewMemoryStore(),
			Saves:     saves.NewMemoryStore(),
			Legacy:    legacy.NewMemoryStore(),
			Telemetry: telemetry.NewMemoryStore(),
			Admin:     admin.NewMemoryStore(),
			Blobs:     blobs,
			Limiter:   limiter,
			Close:     closeCache,
		}, nil
	}

	database, err := db.Open(ctx, cfg.DatabaseURL)
	if err != nil {
		closeCache()
		return Deps{}, err
	}
	if err := database.Migrate(ctx); err != nil {
		database.Close()
		closeCache()
		return Deps{}, err
	}

	logger.Info("持久化: PostgreSQL")
	return Deps{
		Auth:      auth.NewPGStore(database.Pool),
		Saves:     saves.NewPGStore(database.Pool, blobs),
		Legacy:    legacy.NewPGStore(database.Pool),
		Telemetry: telemetry.NewPGStore(database.Pool),
		Admin:     admin.NewPGStore(database.Pool),
		Blobs:     blobs,
		Limiter:   limiter,
		Close: func() {
			closeCache()
			database.Close()
		},
	}, nil
}

// buildBlobs 优先使用 S3 兼容对象存储；未配置时回退本地目录。
func buildBlobs(ctx context.Context, cfg config.Config, logger *slog.Logger) (blob.Store, error) {
	if cfg.HasObjectStore() {
		m, err := blob.NewMinIOStore(ctx, blob.MinIOOptions{
			Endpoint:     cfg.ObjectEndpoint,
			AccessKey:    cfg.ObjectKey,
			SecretKey:    cfg.ObjectSecret,
			Bucket:       cfg.ObjectBucket,
			Region:       cfg.ObjectRegion,
			UseSSL:       cfg.ObjectUseSSL,
			CreateBucket: cfg.ObjectCreate,
		})
		if err != nil {
			return nil, err
		}
		logger.Info("对象存储: S3 兼容", "endpoint", cfg.ObjectEndpoint, "bucket", cfg.ObjectBucket, "region", cfg.ObjectRegion)
		return m, nil
	}
	local, err := blob.NewLocalStore(filepath.Join(cfg.DataDir, "objects"))
	if err != nil {
		return nil, err
	}
	logger.Info("对象存储: 本地目录", "dir", filepath.Join(cfg.DataDir, "objects"))
	return local, nil
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
