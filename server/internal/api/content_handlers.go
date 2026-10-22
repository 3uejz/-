package api

import (
	"errors"
	"io"
	"net/http"
	"time"

	"lifetextsandbox/server/internal/auth"
	"lifetextsandbox/server/internal/blob"
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

// handleContentPackDownload 从对象存储流式返回内容包，支持 HTTP Range 与断点续传。
// 对象键固定为 packs/<name>/<version>.ltpack，构建机按同一约定上传。
func (s *Server) handleContentPackDownload(w http.ResponseWriter, r *http.Request) {
	name := r.PathValue("name")
	if !content.ValidPackName(name) {
		httpx.WriteError(w, r, http.StatusNotFound, httpx.CodeNotFound, "内容包不存在")
		return
	}
	pack, ok := s.deps.Content.Pack(name)
	if !ok || !content.ValidPackName(pack.Version) {
		httpx.WriteError(w, r, http.StatusNotFound, httpx.CodeNotFound, "内容包不存在")
		return
	}
	if s.deps.Blobs == nil {
		httpx.WriteError(w, r, http.StatusServiceUnavailable, httpx.CodeInternal, "对象存储未启用")
		return
	}
	reader, _, err := s.deps.Blobs.Open(r.Context(), contentPackObjectKey(pack))
	if errors.Is(err, blob.ErrNotFound) {
		httpx.WriteError(w, r, http.StatusNotFound, httpx.CodeNotFound, "内容包文件不存在")
		return
	}
	if err != nil {
		s.deps.Logger.Error("内容包读取失败", "name", name, "error", err)
		httpx.WriteError(w, r, http.StatusInternalServerError, httpx.CodeInternal, "内容包读取失败")
		return
	}
	defer reader.Close()

	w.Header().Set("ETag", pack.Hash)
	w.Header().Set("Cache-Control", "public, max-age=300")
	w.Header().Set("Content-Type", "application/octet-stream")
	http.ServeContent(w, r, name+".ltpack", time.Time{}, reader)
}

func contentPackObjectKey(pack content.Pack) string {
	return "packs/" + pack.Name + "/" + pack.Version + ".ltpack"
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

func (s *Server) handleAdminPublish(w http.ResponseWriter, r *http.Request, actor auth.Account) {
	doc, err := io.ReadAll(r.Body)
	if err != nil {
		httpx.WriteError(w, r, http.StatusBadRequest, httpx.CodeValidationFailed, "读取请求体失败")
		return
	}
	tag, err := s.deps.Content.PublishManifest(doc)
	if err != nil {
		s.recordAudit(r, actor, "content.publish", "content_manifest", "", nil, nil, "error")
		httpx.WriteError(w, r, http.StatusBadRequest, httpx.CodeValidationFailed, "内容清单非法")
		return
	}
	s.recordAudit(r, actor, "content.publish", "content_manifest", tag, nil, map[string]any{"etag": tag}, "ok")
	w.Header().Set("ETag", tag)
	w.WriteHeader(http.StatusAccepted)
}

func matchTag(r *http.Request, tag string) bool {
	return tag != "" && r.Header.Get("If-None-Match") == tag
}
