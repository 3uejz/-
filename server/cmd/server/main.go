// Command server 是浮生录的模块化单体后端入口。
//
// 提供 /api/v1 下的认证、云存档、内容、传承、遥测与世界摘要接口；
// 当前使用进程内存储实现（PG/Redis/MinIO 适配后续替换 Store 接口实现即可）。
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
	"lifetextsandbox/server/internal/config"
	"lifetextsandbox/server/internal/content"
	"lifetextsandbox/server/internal/legacy"
	"lifetextsandbox/server/internal/saves"
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
	authSvc := auth.NewService(auth.NewMemoryStore(), cfg.JWTSecret, cfg.AccessTTL, cfg.RefreshTTL)
	if err := authSvc.EnsureAdmin(ctx, cfg.AdminUsername, cfg.AdminPassword); err != nil {
		logger.Error("管理员初始化失败", "error", err)
		os.Exit(1)
	}

	srv := api.New(api.Deps{
		Config:    cfg,
		Logger:    logger,
		Auth:      authSvc,
		Saves:     saves.NewService(saves.NewMemoryStore()),
		Content:   content.NewService(),
		Legacy:    legacy.NewService(legacy.NewMemoryStore()),
		Telemetry: telemetry.NewService(telemetry.NewMemoryStore(), cfg.TelemetryDays),
		World:     worldsim.NewSimulator(1, 8_000_000_000),
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
