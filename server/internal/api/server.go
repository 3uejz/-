// Package api 组装后端 HTTP 路由与处理器，对应 shared/openapi/openapi.yaml。
package api

import (
	"log/slog"
	"net/http"
	"sync"

	"lifetextsandbox/server/internal/auth"
	"lifetextsandbox/server/internal/config"
	"lifetextsandbox/server/internal/content"
	"lifetextsandbox/server/internal/httpx"
	"lifetextsandbox/server/internal/legacy"
	"lifetextsandbox/server/internal/saves"
	"lifetextsandbox/server/internal/telemetry"
	"lifetextsandbox/server/internal/worldsim"
)

// Deps 是组装 API 所需的依赖，便于测试注入内存实现。
type Deps struct {
	Config    config.Config
	Logger    *slog.Logger
	Auth      *auth.Service
	Saves     *saves.Service
	Content   *content.Service
	Legacy    *legacy.Service
	Telemetry *telemetry.Service
	World     *worldsim.Simulator
	// Limiter 为可选限流后端；为 nil 时使用进程内默认实现。
	Limiter httpx.Limiter
}

// Server 持有依赖并提供路由。
type Server struct {
	deps    Deps
	limiter httpx.Limiter
	world   *worldsim.Simulator

	worldMu    sync.Mutex
	worldBytes []byte
	worldTag   string
}

// New 构造 API 服务器。World 为 nil 时创建默认模拟器。
func New(deps Deps) *Server {
	if deps.Logger == nil {
		deps.Logger = slog.Default()
	}
	world := deps.World
	if world == nil {
		world = worldsim.NewSimulator(1, 8_000_000_000)
	}
	limiter := deps.Limiter
	if limiter == nil {
		limiter = httpx.NewRateLimiter(deps.Config.RateLimitRPS * 60)
	}
	return &Server{
		deps:    deps,
		limiter: limiter,
		world:   world,
	}
}

// Router 返回带中间件的根 handler。
func (s *Server) Router() http.Handler {
	mux := http.NewServeMux()

	// 公开：健康检查与认证。
	mux.HandleFunc("GET /api/v1/health", s.handleHealth)
	mux.HandleFunc("GET /metrics", s.handleMetrics)
	mux.HandleFunc("POST /api/v1/auth/register", s.handleRegister)
	mux.HandleFunc("POST /api/v1/auth/login", s.handleLogin)
	mux.HandleFunc("POST /api/v1/auth/refresh", s.handleRefresh)
	mux.HandleFunc("POST /api/v1/auth/logout", s.handleLogout)

	// 需登录。
	mux.Handle("GET /api/v1/saves", s.requireAuth(s.handleListSaves))
	mux.Handle("GET /api/v1/saves/{slot}", s.requireAuth(s.handleGetSave))
	mux.Handle("PUT /api/v1/saves/{slot}", s.requireAuth(s.handlePutSave))
	mux.Handle("GET /api/v1/saves/{slot}/versions", s.requireAuth(s.handleSaveVersions))
	mux.Handle("POST /api/v1/saves/{slot}/rollback", s.requireAuth(s.handleRollback))
	mux.Handle("POST /api/v1/saves/{slot}/resolve", s.requireAuth(s.handleResolve))

	mux.HandleFunc("GET /api/v1/content/manifest", s.handleContentManifest)
	mux.HandleFunc("GET /api/v1/config", s.handleRemoteConfig)
	mux.HandleFunc("GET /api/v1/announcements", s.handleAnnouncements)

	mux.Handle("GET /api/v1/legacy", s.requireAuth(s.handleGetLegacy))
	mux.Handle("PUT /api/v1/legacy", s.requireAuth(s.handlePutLegacy))

	mux.Handle("POST /api/v1/telemetry/events", s.requireAuth(s.handleTelemetry))

	mux.HandleFunc("GET /api/v1/world/summary", s.handleWorldSummary)
	mux.HandleFunc("POST /api/v1/world/sync", s.handleWorldSync)

	// 管理端。
	mux.Handle("GET /api/v1/admin/accounts", s.requireAdmin(s.handleAdminAccounts))
	mux.Handle("POST /api/v1/admin/content/publish", s.requireAdmin(s.handleAdminPublish))
	mux.Handle("PUT /api/v1/admin/config", s.requireAdmin(s.handleAdminPutConfig))

	var h http.Handler = mux
	h = httpx.MaxBody(s.deps.Config.SaveMaxBytes, h)
	h = httpx.Limit(s.limiter, h)
	h = httpx.AccessLog(s.deps.Logger, h)
	h = httpx.Recover(s.deps.Logger, h)
	h = httpx.RequestID(h)
	return h
}
