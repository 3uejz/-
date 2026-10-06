package api

import (
	"encoding/json"
	"net/http"
	"testing"

	"lifetextsandbox/server/internal/auth"
)

// adminToken 幂等创建管理员并登录，返回访问令牌。
func adminToken(t *testing.T, srv *Server, h http.Handler) string {
	t.Helper()
	if err := srv.deps.Auth.EnsureAdmin(t.Context(), "root", "admin-password"); err != nil {
		t.Fatal(err)
	}
	rec := doJSON(t, h, http.MethodPost, "/api/v1/auth/login", "", map[string]string{
		"username": "root", "password": "admin-password",
	}, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("管理员登录失败: %d %s", rec.Code, rec.Body.String())
	}
	var tokens auth.Tokens
	_ = json.Unmarshal(rec.Body.Bytes(), &tokens)
	return tokens.AccessToken
}

func accountIDByUsername(t *testing.T, srv *Server, username string) string {
	t.Helper()
	accounts, _ := srv.deps.Auth.ListAccounts(t.Context(), 100, "")
	for _, a := range accounts {
		if a.Username == username {
			return a.ID
		}
	}
	t.Fatalf("未找到账号 %s", username)
	return ""
}

// 任务 25.1：权限（未登录 401、非 admin 403）与写操作审计。
func TestAdminPermissionAndAudit(t *testing.T) {
	srv, h := newTestServer(t)
	player := registerAndLogin(t, h, "player1")
	admin := adminToken(t, srv, h)

	// 未登录 401。
	if rec := doJSON(t, h, http.MethodGet, "/api/v1/admin/me", "", nil, nil); rec.Code != http.StatusUnauthorized {
		t.Fatalf("未登录期望 401，得到 %d", rec.Code)
	}
	// 非 admin 403：读与写都拒绝。
	for _, tc := range []struct {
		method, path string
	}{
		{http.MethodGet, "/api/v1/admin/me"},
		{http.MethodGet, "/api/v1/admin/accounts"},
		{http.MethodPost, "/api/v1/admin/content/releases"},
		{http.MethodPut, "/api/v1/admin/config"},
		{http.MethodPost, "/api/v1/admin/system/backup"},
	} {
		if rec := doJSON(t, h, tc.method, tc.path, player, map[string]any{}, nil); rec.Code != http.StatusForbidden {
			t.Fatalf("非管理员 %s %s 期望 403，得到 %d", tc.method, tc.path, rec.Code)
		}
	}

	// 管理员 /me 返回自身。
	rec := doJSON(t, h, http.MethodGet, "/api/v1/admin/me", admin, nil, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("/admin/me 期望 200，得到 %d", rec.Code)
	}
	var me accountView
	_ = json.Unmarshal(rec.Body.Bytes(), &me)
	if me.Role != "admin" {
		t.Fatalf("管理员角色错误: %+v", me)
	}

	// 写操作落审计。
	rec = doJSON(t, h, http.MethodPost, "/api/v1/admin/content/releases", admin, map[string]any{
		"pack_name": "core", "pack_version": "1.0.0", "strategy": "all",
	}, nil)
	if rec.Code != http.StatusCreated {
		t.Fatalf("创建发布期望 201，得到 %d %s", rec.Code, rec.Body.String())
	}
	rec = doJSON(t, h, http.MethodGet, "/api/v1/admin/audit-logs?action=content.release.create", admin, nil, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("审计列表期望 200，得到 %d", rec.Code)
	}
	var audits struct {
		Items []struct {
			ActorAccountID string `json:"actor_account_id"`
			Action         string `json:"action"`
			Result         string `json:"result"`
		} `json:"items"`
	}
	_ = json.Unmarshal(rec.Body.Bytes(), &audits)
	if len(audits.Items) == 0 || audits.Items[0].Action != "content.release.create" || audits.Items[0].Result != "ok" {
		t.Fatalf("审计未写入: %+v", audits)
	}
	if audits.Items[0].ActorAccountID != me.ID {
		t.Fatalf("审计操作者错误: %+v", audits.Items[0])
	}
}

// 任务 25.2：内容灰度发布/暂停/继续/回滚状态机。
func TestAdminContentReleaseLifecycle(t *testing.T) {
	srv, h := newTestServer(t)
	player := registerAndLogin(t, h, "player2")
	admin := adminToken(t, srv, h)
	pid := accountIDByUsername(t, srv, "player2")

	rec := doJSON(t, h, http.MethodPost, "/api/v1/admin/content/releases", admin, map[string]any{
		"pack_name": "core", "pack_version": "2.0.0", "strategy": "accounts",
		"account_list": []string{pid}, "manifest_version": 2,
	}, nil)
	if rec.Code != http.StatusCreated {
		t.Fatalf("创建灰度发布期望 201，得到 %d %s", rec.Code, rec.Body.String())
	}
	var rel struct {
		ID     string `json:"id"`
		Status string `json:"status"`
	}
	_ = json.Unmarshal(rec.Body.Bytes(), &rel)
	if rel.Status != "rolling" {
		t.Fatalf("新建应为 rolling: %s", rel.Status)
	}
	_ = player

	if rec := doJSON(t, h, http.MethodPost, "/api/v1/admin/content/releases/"+rel.ID+"/pause", admin, nil, nil); rec.Code != http.StatusOK {
		t.Fatalf("暂停期望 200，得到 %d", rec.Code)
	}
	// 重复暂停应冲突。
	if rec := doJSON(t, h, http.MethodPost, "/api/v1/admin/content/releases/"+rel.ID+"/pause", admin, nil, nil); rec.Code != http.StatusConflict {
		t.Fatalf("重复暂停期望 409，得到 %d", rec.Code)
	}
	if rec := doJSON(t, h, http.MethodPost, "/api/v1/admin/content/releases/"+rel.ID+"/resume", admin, nil, nil); rec.Code != http.StatusOK {
		t.Fatalf("继续期望 200，得到 %d", rec.Code)
	}
	rec = doJSON(t, h, http.MethodPost, "/api/v1/admin/content/releases/"+rel.ID+"/rollback", admin, nil, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("回滚期望 200，得到 %d", rec.Code)
	}
	var rolled struct {
		Status string `json:"status"`
	}
	_ = json.Unmarshal(rec.Body.Bytes(), &rolled)
	if rolled.Status != "rolled_back" {
		t.Fatalf("回滚后应为 rolled_back: %s", rolled.Status)
	}
	// 不存在的批次 404。
	if rec := doJSON(t, h, http.MethodPost, "/api/v1/admin/content/releases/missing/pause", admin, nil, nil); rec.Code != http.StatusNotFound {
		t.Fatalf("不存在批次期望 404，得到 %d", rec.Code)
	}
}

// 任务 25.2：配置版本递增、乐观锁冲突与回滚，并同步到玩家端。
func TestAdminConfigVersioningAndRollback(t *testing.T) {
	srv, h := newTestServer(t)
	admin := adminToken(t, srv, h)

	rec := doJSON(t, h, http.MethodGet, "/api/v1/admin/config", admin, nil, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("读取配置期望 200，得到 %d", rec.Code)
	}

	rec = doJSON(t, h, http.MethodPut, "/api/v1/admin/config", admin, map[string]any{
		"revision": 0, "values": map[string]any{"economy.inflation_rate": 0.03},
	}, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("首次发布配置期望 200，得到 %d %s", rec.Code, rec.Body.String())
	}
	var v1 struct {
		Version  int `json:"version"`
		Revision int `json:"revision"`
	}
	_ = json.Unmarshal(rec.Body.Bytes(), &v1)
	if v1.Version != 1 || v1.Revision != 1 {
		t.Fatalf("首版应为 1/1: %+v", v1)
	}

	// 过期 revision 应 409。
	if rec := doJSON(t, h, http.MethodPut, "/api/v1/admin/config", admin, map[string]any{
		"revision": 0, "values": map[string]any{"x": 1},
	}, nil); rec.Code != http.StatusConflict {
		t.Fatalf("过期 revision 期望 409，得到 %d", rec.Code)
	}

	rec = doJSON(t, h, http.MethodPut, "/api/v1/admin/config", admin, map[string]any{
		"revision": 1, "values": map[string]any{"economy.inflation_rate": 0.05},
	}, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("第二版期望 200，得到 %d", rec.Code)
	}

	rec = doJSON(t, h, http.MethodGet, "/api/v1/admin/config/versions", admin, nil, nil)
	var versions struct {
		Items []struct {
			Version int `json:"version"`
		} `json:"items"`
	}
	_ = json.Unmarshal(rec.Body.Bytes(), &versions)
	if len(versions.Items) != 2 || versions.Items[0].Version != 2 {
		t.Fatalf("版本历史应为倒序 2 条: %+v", versions.Items)
	}

	// 回滚到 v1，生成新版本 v3。
	rec = doJSON(t, h, http.MethodPost, "/api/v1/admin/config/rollback", admin, map[string]any{"version": 1}, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("配置回滚期望 200，得到 %d %s", rec.Code, rec.Body.String())
	}
	var v3 struct {
		Version int            `json:"version"`
		Values  map[string]any `json:"values"`
	}
	_ = json.Unmarshal(rec.Body.Bytes(), &v3)
	if v3.Version != 3 || v3.Values["economy.inflation_rate"] != 0.03 {
		t.Fatalf("回滚应生成 v3 且恢复旧值: %+v", v3)
	}

	// 玩家端配置应同步。
	rec = doJSON(t, h, http.MethodGet, "/api/v1/config", "", nil, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("玩家配置期望 200，得到 %d", rec.Code)
	}
}

// 公告发布后玩家可见，删除后下线。
func TestAdminAnnouncementsVisibleToPlayers(t *testing.T) {
	srv, h := newTestServer(t)
	admin := adminToken(t, srv, h)

	rec := doJSON(t, h, http.MethodPost, "/api/v1/admin/announcements", admin, map[string]any{
		"title": "维护公告", "body": "今晚 2 点维护", "status": "published",
	}, nil)
	if rec.Code != http.StatusCreated {
		t.Fatalf("创建公告期望 201，得到 %d %s", rec.Code, rec.Body.String())
	}
	var a struct {
		ID string `json:"id"`
	}
	_ = json.Unmarshal(rec.Body.Bytes(), &a)

	rec = doJSON(t, h, http.MethodGet, "/api/v1/announcements", "", nil, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("玩家公告期望 200，得到 %d", rec.Code)
	}
	var list []contentAnnouncement
	_ = json.Unmarshal(rec.Body.Bytes(), &list)
	if len(list) != 1 || list[0].Title != "维护公告" {
		t.Fatalf("发布公告应对玩家可见: %+v", list)
	}

	if rec := doJSON(t, h, http.MethodDelete, "/api/v1/admin/announcements/"+a.ID, admin, nil, nil); rec.Code != http.StatusNoContent {
		t.Fatalf("删除公告期望 204，得到 %d", rec.Code)
	}
	rec = doJSON(t, h, http.MethodGet, "/api/v1/announcements", "", nil, nil)
	_ = json.Unmarshal(rec.Body.Bytes(), &list)
	if len(list) != 0 {
		t.Fatalf("删除后玩家不应看到公告: %+v", list)
	}
}

type contentAnnouncement struct {
	ID    string `json:"id"`
	Title string `json:"title"`
	Body  string `json:"body"`
}

// 封禁账号后无法登录，解封恢复；设备列表可读。
func TestAdminDisableAccount(t *testing.T) {
	srv, h := newTestServer(t)
	_ = registerAndLogin(t, h, "player3")
	admin := adminToken(t, srv, h)
	id := accountIDByUsername(t, srv, "player3")

	if rec := doJSON(t, h, http.MethodPost, "/api/v1/admin/accounts/"+id+"/disable", admin, nil, nil); rec.Code != http.StatusOK {
		t.Fatalf("封禁期望 200，得到 %d %s", rec.Code, rec.Body.String())
	}
	if rec := doJSON(t, h, http.MethodPost, "/api/v1/auth/login", "", map[string]string{
		"username": "player3", "password": "password123",
	}, nil); rec.Code != http.StatusUnauthorized {
		t.Fatalf("封禁后登录期望 401，得到 %d", rec.Code)
	}
	if rec := doJSON(t, h, http.MethodGet, "/api/v1/admin/accounts/"+id+"/devices", admin, nil, nil); rec.Code != http.StatusOK {
		t.Fatalf("设备列表期望 200，得到 %d", rec.Code)
	}
	if rec := doJSON(t, h, http.MethodPost, "/api/v1/admin/accounts/"+id+"/enable", admin, nil, nil); rec.Code != http.StatusOK {
		t.Fatalf("解封期望 200，得到 %d", rec.Code)
	}
	if rec := doJSON(t, h, http.MethodPost, "/api/v1/auth/login", "", map[string]string{
		"username": "player3", "password": "password123",
	}, nil); rec.Code != http.StatusOK {
		t.Fatalf("解封后登录期望 200，得到 %d", rec.Code)
	}
}

// 仪表盘、遥测、系统状态与助手预留接口可访问。
func TestAdminDashboardAndSystem(t *testing.T) {
	srv, h := newTestServer(t)
	admin := adminToken(t, srv, h)

	for _, path := range []string{
		"/api/v1/admin/dashboard/summary",
		"/api/v1/admin/saves",
		"/api/v1/admin/storage/usage",
		"/api/v1/admin/content/packs",
		"/api/v1/admin/telemetry/events",
		"/api/v1/admin/telemetry/aggregates",
		"/api/v1/admin/telemetry/life-stats",
		"/api/v1/admin/system/status",
		"/api/v1/admin/system/backups",
		"/api/v1/admin/system/migrations",
		"/api/v1/admin/assistant/status",
	} {
		if rec := doJSON(t, h, http.MethodGet, path, admin, nil, nil); rec.Code != http.StatusOK {
			t.Fatalf("GET %s 期望 200，得到 %d %s", path, rec.Code, rec.Body.String())
		}
	}
	// 助手未启用时查询返回 503。
	if rec := doJSON(t, h, http.MethodPost, "/api/v1/admin/assistant/query", admin, map[string]any{"q": "hi"}, nil); rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("助手查询期望 503，得到 %d", rec.Code)
	}
	// 备份未配置 DATABASE_URL 时返回 503。
	if rec := doJSON(t, h, http.MethodPost, "/api/v1/admin/system/backup", admin, nil, nil); rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("未配置备份期望 503，得到 %d", rec.Code)
	}
	// 迁移端点返回内置迁移。
	rec := doJSON(t, h, http.MethodGet, "/api/v1/admin/system/migrations", admin, nil, nil)
	var migrations struct {
		Available []string `json:"available"`
	}
	_ = json.Unmarshal(rec.Body.Bytes(), &migrations)
	if len(migrations.Available) == 0 {
		t.Fatal("迁移列表不应为空")
	}
}
