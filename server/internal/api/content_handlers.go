package api

import (
	"io"
	"net/http"

	"lifetextsandbox/server/internal/auth"
	"lifetextsandbox/server/internal/content"
	"lifetextsandbox/server/internal/httpx"
)

func (s *Server) handleContentManifest(w http.ResponseWriter, r *http.Request) {
	doc, tag := s.deps.Content.Manifest()
	if matchTag(r, tag) {
		w.WriteHeader(http.StatusNotModified)
		return
	}
	w.Header().Set("ETag", tag)
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write(doc)
}

func (s *Server) handleRemoteConfig(w http.ResponseWriter, r *http.Request) {
	doc, tag := s.deps.Content.Config()
	if matchTag(r, tag) {
		w.WriteHeader(http.StatusNotModified)
		return
	}
	w.Header().Set("ETag", tag)
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write(doc)
}

func (s *Server) handleAnnouncements(w http.ResponseWriter, _ *http.Request) {
	list := s.deps.Content.Announcements()
	if list == nil {
		list = []content.Announcement{}
	}
	httpx.WriteJSON(w, http.StatusOK, list)
}

func (s *Server) handleAdminPublish(w http.ResponseWriter, r *http.Request, _ auth.Account) {
	doc, err := io.ReadAll(r.Body)
	if err != nil {
		httpx.WriteError(w, r, http.StatusBadRequest, httpx.CodeValidationFailed, "读取请求体失败")
		return
	}
	if _, err := s.deps.Content.PublishManifest(doc); err != nil {
		httpx.WriteError(w, r, http.StatusBadRequest, httpx.CodeValidationFailed, "内容清单非法")
		return
	}
	w.WriteHeader(http.StatusAccepted)
}

func (s *Server) handleAdminPutConfig(w http.ResponseWriter, r *http.Request, _ auth.Account) {
	doc, err := io.ReadAll(r.Body)
	if err != nil {
		httpx.WriteError(w, r, http.StatusBadRequest, httpx.CodeValidationFailed, "读取请求体失败")
		return
	}
	tag, err := s.deps.Content.PutConfig(doc)
	if err != nil {
		httpx.WriteError(w, r, http.StatusBadRequest, httpx.CodeValidationFailed, "配置非法")
		return
	}
	w.Header().Set("ETag", tag)
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write(doc)
}

func matchTag(r *http.Request, tag string) bool {
	return tag != "" && r.Header.Get("If-None-Match") == tag
}
