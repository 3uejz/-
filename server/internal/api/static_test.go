package api

import (
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// 管理后台构建产物由 Go 同源托管于 /admin，含 SPA fallback 与缓存策略。
func TestAdminStaticServing(t *testing.T) {
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "index.html"), []byte("<html>admin-shell</html>"), 0o644); err != nil {
		t.Fatal(err)
	}
	assets := filepath.Join(dir, "assets")
	if err := os.MkdirAll(assets, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(assets, "app-abc123.js"), []byte("console.log(1)"), 0o644); err != nil {
		t.Fatal(err)
	}

	srv, _ := newTestServer(t)
	srv.deps.Config.AdminDir = dir
	h := srv.Router()

	// 根路径返回 index.html。
	rec := doJSON(t, h, http.MethodGet, "/admin/", "", nil, nil)
	if rec.Code != http.StatusOK || !strings.Contains(rec.Body.String(), "admin-shell") {
		t.Fatalf("/admin/ 期望返回 index，得到 %d %s", rec.Code, rec.Body.String())
	}
	// 前端深链接回退 index.html（SPA）。
	rec = doJSON(t, h, http.MethodGet, "/admin/accounts/123", "", nil, nil)
	if rec.Code != http.StatusOK || !strings.Contains(rec.Body.String(), "admin-shell") {
		t.Fatalf("SPA fallback 失败: %d %s", rec.Code, rec.Body.String())
	}
	// 带哈希指纹资源长缓存。
	rec = doJSON(t, h, http.MethodGet, "/admin/assets/app-abc123.js", "", nil, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("静态资源期望 200，得到 %d", rec.Code)
	}
	if cc := rec.Header().Get("Cache-Control"); cc != "public, max-age=31536000, immutable" {
		t.Fatalf("静态资源缓存头错误: %q", cc)
	}
	// index.html 不缓存。
	rec = doJSON(t, h, http.MethodGet, "/admin/", "", nil, nil)
	if cc := rec.Header().Get("Cache-Control"); cc != "no-cache" {
		t.Fatalf("index 缓存头错误: %q", cc)
	}
	// 站点根路径重定向到管理后台，避免预览入口 404。
	rec = doJSON(t, h, http.MethodGet, "/", "", nil, nil)
	if rec.Code != http.StatusFound || rec.Header().Get("Location") != "/admin/" {
		t.Fatalf("根路径期望 302 -> /admin/，得到 %d %q", rec.Code, rec.Header().Get("Location"))
	}
}

// 未启用管理后台时站点根路径返回 404，不产生误导性重定向。
func TestAdminRootRedirectDisabled(t *testing.T) {
	srv, _ := newTestServer(t)
	srv.deps.Config.AdminDir = ""
	h := srv.Router()
	rec := doJSON(t, h, http.MethodGet, "/", "", nil, nil)
	if rec.Code != http.StatusNotFound {
		t.Fatalf("未启用管理后台时根路径期望 404，得到 %d", rec.Code)
	}
}
