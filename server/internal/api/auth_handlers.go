package api

import (
	"errors"
	"net/http"

	"lifetextsandbox/server/internal/auth"
	"lifetextsandbox/server/internal/httpx"
)

type credentialsRequest struct {
	Username string `json:"username"`
	Password string `json:"password"`
}

type refreshRequest struct {
	RefreshToken string `json:"refresh_token"`
}

func (s *Server) handleRegister(w http.ResponseWriter, r *http.Request) {
	var req credentialsRequest
	if err := httpx.DecodeJSON(r, &req); err != nil {
		httpx.WriteError(w, r, http.StatusBadRequest, httpx.CodeValidationFailed, "请求体非法")
		return
	}
	tokens, err := s.deps.Auth.Register(r.Context(), req.Username, req.Password, deviceID(r))
	if errors.Is(err, auth.ErrValidation) {
		httpx.WriteError(w, r, http.StatusBadRequest, httpx.CodeValidationFailed, "用户名或口令不符合要求")
		return
	}
	if errors.Is(err, auth.ErrUsernameTaken) {
		httpx.WriteError(w, r, http.StatusConflict, httpx.CodeConflict, "用户名已存在")
		return
	}
	if err != nil {
		httpx.WriteError(w, r, http.StatusInternalServerError, httpx.CodeInternal, "注册失败")
		return
	}
	httpx.WriteJSON(w, http.StatusCreated, tokens)
}

func (s *Server) handleLogin(w http.ResponseWriter, r *http.Request) {
	var req credentialsRequest
	if err := httpx.DecodeJSON(r, &req); err != nil {
		httpx.WriteError(w, r, http.StatusBadRequest, httpx.CodeValidationFailed, "请求体非法")
		return
	}
	tokens, err := s.deps.Auth.Login(r.Context(), req.Username, req.Password, deviceID(r))
	if errors.Is(err, auth.ErrInvalidCredential) {
		httpx.WriteError(w, r, http.StatusUnauthorized, httpx.CodeUnauthenticated, "用户名或口令错误")
		return
	}
	if err != nil {
		httpx.WriteError(w, r, http.StatusInternalServerError, httpx.CodeInternal, "登录失败")
		return
	}
	httpx.WriteJSON(w, http.StatusOK, tokens)
}

func (s *Server) handleRefresh(w http.ResponseWriter, r *http.Request) {
	var req refreshRequest
	if err := httpx.DecodeJSON(r, &req); err != nil || req.RefreshToken == "" {
		httpx.WriteError(w, r, http.StatusBadRequest, httpx.CodeValidationFailed, "缺少 refresh_token")
		return
	}
	tokens, err := s.deps.Auth.Refresh(r.Context(), req.RefreshToken, deviceID(r))
	if err != nil {
		httpx.WriteError(w, r, http.StatusUnauthorized, httpx.CodeUnauthenticated, "refresh 令牌无效")
		return
	}
	httpx.WriteJSON(w, http.StatusOK, tokens)
}

func (s *Server) handleLogout(w http.ResponseWriter, r *http.Request) {
	var req refreshRequest
	if err := httpx.DecodeJSON(r, &req); err != nil || req.RefreshToken == "" {
		httpx.WriteError(w, r, http.StatusBadRequest, httpx.CodeValidationFailed, "缺少 refresh_token")
		return
	}
	_ = s.deps.Auth.Logout(r.Context(), req.RefreshToken)
	w.WriteHeader(http.StatusNoContent)
}

func deviceID(r *http.Request) string {
	return r.Header.Get("X-Device-Id")
}
