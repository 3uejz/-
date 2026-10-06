// Package api 组装后端 HTTP 路由与处理器，对应 shared/openapi/openapi.yaml。
package api

import (
	"log/slog"
	"net/http"
	"sync"
	"time"

	"lifetextsandbox/server/internal/admin"
	"lifetextsandbox/server/internal/auth"
	"lifetextsandbox/server/internal/backup"
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
	Admin     *admin.Service
	// Backup 为可选的备份执行器；为 nil 时后台备份接口返回未启用。
	Backup *backup.Runner
	// Limiter 为可选限流后端；为 nil 时使用进程内默认实现。
	Limiter httpx.Limiter
}

// Server 持有依赖并提供路由。
type Server struct {
	deps      Deps
	limiter   httpx.Limiter
	world     *worldsim.Simulator
	startedAt time.Time

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
	if deps.Admin == nil {
		deps.Admin = admin.NewService(admin.NewMemoryStore())
	}
	return &Server{
		deps:      deps,
		limiter:   limiter,
		world:     world,
		startedAt: time.Now(),
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

	// 管理端（全部经 requireAdmin 校验 is_admin，写操作落审计）。
	mux.Handle("GET /api/v1/admin/me", s.requireAdmin(s.handleAdminMe))
	mux.Handle("GET /api/v1/admin/dashboard/summary", s.requireAdmin(s.handleAdminDashboard))

	mux.Handle("GET /api/v1/admin/accounts", s.requireAdmin(s.handleAdminAccounts))
	mux.Handle("GET /api/v1/admin/accounts/{id}", s.requireAdmin(s.handleAdminAccount))
	mux.Handle("POST /api/v1/admin/accounts/{id}/disable", s.requireAdmin(s.handleAdminDisable))
	mux.Handle("POST /api/v1/admin/accounts/{id}/enable", s.requireAdmin(s.handleAdminEnable))
	mux.Handle("GET /api/v1/admin/accounts/{id}/devices", s.requireAdmin(s.handleAdminDevices))
	mux.Handle("POST /api/v1/admin/accounts/{id}/devices/{device_id}/revoke", s.requireAdmin(s.handleAdminRevokeDevice))

	mux.Handle("GET /api/v1/admin/saves", s.requireAdmin(s.handleAdminSaves))
	mux.Handle("GET /api/v1/admin/saves/{id}", s.requireAdmin(s.handleAdminSave))
	mux.Handle("GET /api/v1/admin/saves/{id}/versions", s.requireAdmin(s.handleAdminSaveVersions))
	mux.Handle("POST /api/v1/admin/saves/{id}/rollback", s.requireAdmin(s.handleAdminSaveRollback))
	mux.Handle("GET /api/v1/admin/storage/usage", s.requireAdmin(s.handleAdminStorageUsage))
	mux.Handle("POST /api/v1/admin/storage/gc", s.requireAdmin(s.handleAdminStorageGC))

	mux.Handle("GET /api/v1/admin/content/packs", s.requireAdmin(s.handleAdminContentPacks))
	mux.Handle("POST /api/v1/admin/content/packs", s.requireAdmin(s.handleAdminContentPackUpload))
	mux.Handle("POST /api/v1/admin/content/packs/{name}/validate", s.requireAdmin(s.handleAdminContentValidate))
	mux.Handle("POST /api/v1/admin/content/publish", s.requireAdmin(s.handleAdminPublish))
	mux.Handle("GET /api/v1/admin/content/releases", s.requireAdmin(s.handleAdminReleases))
	mux.Handle("POST /api/v1/admin/content/releases", s.requireAdmin(s.handleAdminCreateRelease))
	mux.Handle("POST /api/v1/admin/content/releases/{id}/pause", s.requireAdmin(s.handleAdminReleaseAction("pause")))
	mux.Handle("POST /api/v1/admin/content/releases/{id}/resume", s.requireAdmin(s.handleAdminReleaseAction("resume")))
	mux.Handle("POST /api/v1/admin/content/releases/{id}/rollback", s.requireAdmin(s.handleAdminReleaseAction("rollback")))

	mux.Handle("GET /api/v1/admin/config", s.requireAdmin(s.handleAdminGetConfig))
	mux.Handle("PUT /api/v1/admin/config", s.requireAdmin(s.handleAdminPutConfig))
	mux.Handle("GET /api/v1/admin/config/versions", s.requireAdmin(s.handleAdminConfigVersions))
	mux.Handle("POST /api/v1/admin/config/rollback", s.requireAdmin(s.handleAdminConfigRollback))

	mux.Handle("GET /api/v1/admin/announcements", s.requireAdmin(s.handleAdminAnnouncements))
	mux.Handle("POST /api/v1/admin/announcements", s.requireAdmin(s.handleAdminCreateAnnouncement))
	mux.Handle("PUT /api/v1/admin/announcements/{id}", s.requireAdmin(s.handleAdminUpdateAnnouncement))
	mux.Handle("DELETE /api/v1/admin/announcements/{id}", s.requireAdmin(s.handleAdminDeleteAnnouncement))

	mux.Handle("GET /api/v1/admin/telemetry/events", s.requireAdmin(s.handleAdminTelemetryEvents))
	mux.Handle("GET /api/v1/admin/telemetry/aggregates", s.requireAdmin(s.handleAdminTelemetryAggregates))
	mux.Handle("GET /api/v1/admin/telemetry/life-stats", s.requireAdmin(s.handleAdminTelemetryLifeStats))
	mux.Handle("POST /api/v1/admin/telemetry/export", s.requireAdmin(s.handleAdminTelemetryExport))
	mux.Handle("POST /api/v1/admin/telemetry/purge", s.requireAdmin(s.handleAdminTelemetryPurge))

	mux.Handle("GET /api/v1/admin/audit-logs", s.requireAdmin(s.handleAdminAuditLogs))

	mux.Handle("GET /api/v1/admin/assistant/status", s.requireAdmin(s.handleAdminAssistantStatus))
	mux.Handle("POST /api/v1/admin/assistant/query", s.requireAdmin(s.handleAdminAssistantUnavailable))
	mux.Handle("POST /api/v1/admin/assistant/draft", s.requireAdmin(s.handleAdminAssistantUnavailable))

	mux.Handle("GET /api/v1/admin/system/status", s.requireAdmin(s.handleAdminSystemStatus))
	mux.Handle("GET /api/v1/admin/system/backups", s.requireAdmin(s.handleAdminSystemBackups))
	mux.Handle("POST /api/v1/admin/system/backup", s.requireAdmin(s.handleAdminSystemBackup))
	mux.Handle("GET /api/v1/admin/system/migrations", s.requireAdmin(s.handleAdminSystemMigrations))

	// 管理后台静态资源（React 构建产物，SPA fallback）。
	mux.Handle("GET /admin", s.adminStaticHandler())
	mux.Handle("GET /admin/", s.adminStaticHandler())

	var h http.Handler = mux
	h = httpx.MaxBody(s.deps.Config.SaveMaxBytes, h)
	h = httpx.Limit(s.limiter, h)
	h = httpx.AccessLog(s.deps.Logger, h)
	h = httpx.Recover(s.deps.Logger, h)
	h = httpx.RequestID(h)
	return h
}
