package api

import (
	"errors"
	"net/http"
	"strings"

	"lifetextsandbox/server/internal/auth"
	"lifetextsandbox/server/internal/httpx"
)

type authedHandler func(http.ResponseWriter, *http.Request, auth.Account)

func (s *Server) requireAuth(next authedHandler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		token := bearerToken(r)
		if token == "" {
			httpx.WriteError(w, r, http.StatusUnauthorized, httpx.CodeUnauthenticated, "缺少访问令牌")
			return
		}
		account, err := s.deps.Auth.Authenticate(r.Context(), token)
		if err != nil {
			code := httpx.CodeUnauthenticated
			if errors.Is(err, auth.ErrTokenExpired) {
				code = httpx.CodeTokenExpired
			}
			httpx.WriteError(w, r, http.StatusUnauthorized, code, "令牌无效或已过期")
			return
		}
		next(w, r, account)
	})
}

func (s *Server) requireAdmin(next authedHandler) http.Handler {
	return s.requireAuth(func(w http.ResponseWriter, r *http.Request, account auth.Account) {
		if account.Role != "admin" {
			httpx.WriteError(w, r, http.StatusForbidden, httpx.CodeForbidden, "需要管理员权限")
			return
		}
		next(w, r, account)
	})
}

func bearerToken(r *http.Request) string {
	h := r.Header.Get("Authorization")
	const prefix = "Bearer "
	if len(h) > len(prefix) && strings.EqualFold(h[:len(prefix)], prefix) {
		return strings.TrimSpace(h[len(prefix):])
	}
	return ""
}
