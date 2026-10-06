package api

import (
	"net/http"
	"os"
	"path/filepath"
	"strings"
)

// adminStaticHandler 以 /admin 前缀托管 React 管理后台构建产物；
// 未匹配到文件的路径回退 index.html，实现 SPA 前端路由（admin.md 2.4）。
func (s *Server) adminStaticHandler() http.Handler {
	raw := s.deps.Config.AdminDir
	if raw == "" {
		return http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
			http.Error(w, "管理后台未启用", http.StatusNotFound)
		})
	}
	dir := filepath.Clean(raw)
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		rel := strings.TrimPrefix(r.URL.Path, "/admin")
		rel = strings.TrimPrefix(rel, "/")
		if rel == "" {
			rel = "index.html"
		}
		full := filepath.Clean(filepath.Join(dir, filepath.FromSlash(rel)))
		if full != dir && !strings.HasPrefix(full, dir+string(os.PathSeparator)) {
			http.NotFound(w, r)
			return
		}
		if info, err := os.Stat(full); err == nil && !info.IsDir() {
			setAdminCache(w, rel)
			http.ServeFile(w, r, full)
			return
		}
		index := filepath.Join(dir, "index.html")
		if _, err := os.Stat(index); err != nil {
			http.Error(w, "管理后台未构建：缺少 "+index, http.StatusNotFound)
			return
		}
		w.Header().Set("Cache-Control", "no-cache")
		http.ServeFile(w, r, index)
	})
}

// setAdminCache 带哈希指纹的资源长缓存，index.html 不缓存。
func setAdminCache(w http.ResponseWriter, rel string) {
	if strings.HasPrefix(rel, "assets/") {
		w.Header().Set("Cache-Control", "public, max-age=31536000, immutable")
		return
	}
	w.Header().Set("Cache-Control", "no-cache")
}
