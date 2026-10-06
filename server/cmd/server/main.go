// Command server 是浮生录的模块化单体后端入口。
//
// 提供 /api/v1 下的认证、云存档、内容、传承、遥测与世界摘要接口；
// 配置了 DATABASE_URL 时使用 PostgreSQL + 对象存储，否则回退进程内内存实现。
package main

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"lifetextsandbox/server/internal/api"
	"lifetextsandbox/server/internal/auth"
	"lifetextsandbox/server/internal/backup"
	"lifetextsandbox/server/internal/config"
	"lifetextsandbox/server/internal/content"
	"lifetextsandbox/server/internal/legacy"
	"lifetextsandbox/server/internal/saves"
	"lifetextsandbox/server/internal/store"
	"lifetextsandbox/server/internal/telemetry"
	"lifetextsandbox/server/internal/worldsim"
)

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	slog.SetDefault(logger)

	cfg, err := config.Load(os.Getenv)
	if err != nil {
		logger.Error("配置加载失败", "error", err)
		os.Exit(1)
	}

	ctx := context.Background()
	stores, err := store.Build(ctx, cfg, logger)
	if err != nil {
		logger.Error("存储初始化失败", "error", err)
		os.Exit(1)
	}
	defer stores.Close()

	authSvc := auth.NewService(stores.Auth, cfg.JWTSecret, cfg.AccessTTL, cfg.RefreshTTL)
	if err := authSvc.EnsureAdmin(ctx, cfg.AdminUsername, cfg.AdminPassword); err != nil {
		logger.Error("管理员初始化失败", "error", err)
		os.Exit(1)
	}

	backupCtx, stopBackup := context.WithCancel(context.Background())
	defer stopBackup()
	go runBackupLoop(backupCtx, cfg, logger)

	srv := api.New(api.Deps{
		Config:    cfg,
		Logger:    logger,
		Auth:      authSvc,
		Saves:     saves.NewService(stores.Saves),
		Content:   content.NewService(),
		Legacy:    legacy.NewService(stores.Legacy),
		Telemetry: telemetry.NewService(stores.Telemetry, cfg.TelemetryDays),
		World:     worldsim.NewSimulator(1, 8_000_000_000),
		Limiter:   stores.Limiter,
	})

	httpServer := &http.Server{
		Addr:              cfg.Addr,
		Handler:           srv.Router(),
		ReadHeaderTimeout: 10 * time.Second,
	}

	go func() {
		logger.Info("服务启动", "addr", cfg.Addr, "version", api.Version)
		if err := httpServer.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			logger.Error("服务异常退出", "error", err)
			os.Exit(1)
		}
	}()

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)
	<-stop

	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := httpServer.Shutdown(shutdownCtx); err != nil {
		logger.Error("优雅关闭失败", "error", err)
	}
	logger.Info("服务已停止")
}

// runBackupLoop 每日执行一次数据库备份；未配置 DATABASE_URL 时为空操作。
func runBackupLoop(ctx context.Context, cfg config.Config, logger *slog.Logger) {
	if cfg.DatabaseURL == "" {
		return
	}
	runner := backup.New(cfg.DatabaseURL, cfg.BackupDir, 7)
	ticker := time.NewTicker(24 * time.Hour)
	defer ticker.Stop()
	for {
		path, err := runner.Backup(ctx)
		if err != nil {
			logger.Error("每日备份失败", "error", err)
		} else {
			logger.Info("每日备份完成", "path", path)
		}
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
		}
	}
}
