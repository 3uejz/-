package api

import (
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strconv"

	"lifetextsandbox/server/internal/auth"
	"lifetextsandbox/server/internal/httpx"
	"lifetextsandbox/server/internal/saves"
)

func parseSlot(r *http.Request) (int, bool) {
	slot, err := strconv.Atoi(r.PathValue("slot"))
	if err != nil || slot < 1 || slot > 99 {
		return 0, false
	}
	return slot, true
}

func (s *Server) handleListSaves(w http.ResponseWriter, r *http.Request, account auth.Account) {
	limit := queryInt(r, "limit", 50, 1, 200)
	after := queryInt(r, "cursor", 0, 0, 99)
	items, next := s.deps.Saves.List(r.Context(), account.ID, limit, after)
	httpx.WriteJSON(w, http.StatusOK, map[string]any{"items": items, "next_cursor": nullIfEmpty(next)})
}

func (s *Server) handleGetSave(w http.ResponseWriter, r *http.Request, account auth.Account) {
	slot, ok := parseSlot(r)
	if !ok {
		httpx.WriteError(w, r, http.StatusBadRequest, httpx.CodeValidationFailed, "slot 非法")
		return
	}
	rec, err := s.deps.Saves.Get(r.Context(), account.ID, slot)
	if errors.Is(err, saves.ErrNotFound) {
		httpx.WriteError(w, r, http.StatusNotFound, httpx.CodeNotFound, "存档不存在")
		return
	}
	if err != nil {
		httpx.WriteError(w, r, http.StatusInternalServerError, httpx.CodeInternal, "读取存档失败")
		return
	}
	w.Header().Set("ETag", saves.ETag(rec))
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write(rec.Doc)
}

func (s *Server) handlePutSave(w http.ResponseWriter, r *http.Request, account auth.Account) {
	slot, ok := parseSlot(r)
	if !ok {
		httpx.WriteError(w, r, http.StatusBadRequest, httpx.CodeValidationFailed, "slot 非法")
		return
	}
	doc, err := io.ReadAll(r.Body)
	if err != nil {
		httpx.WriteError(w, r, http.StatusBadRequest, httpx.CodeValidationFailed, "读取请求体失败")
		return
	}
	rec, created, err := s.deps.Saves.Put(r.Context(), account.ID, slot, doc, r.Header.Get("Idempotency-Key"), r.Header.Get("If-Match"))
	if errors.Is(err, saves.ErrValidation) {
		httpx.WriteError(w, r, http.StatusBadRequest, httpx.CodeValidationFailed, "存档结构非法")
		return
	}
	if errors.Is(err, saves.ErrConflict) {
		httpx.WriteError(w, r, http.StatusConflict, httpx.CodeSaveConflict, "存档版本冲突")
		return
	}
	if err != nil {
		httpx.WriteError(w, r, http.StatusInternalServerError, httpx.CodeInternal, "写入存档失败")
		return
	}
	w.Header().Set("ETag", saves.ETag(rec))
	status := http.StatusOK
	if created {
		status = http.StatusCreated
	}
	httpx.WriteJSON(w, status, slotView(rec))
}

func (s *Server) handleSaveVersions(w http.ResponseWriter, r *http.Request, account auth.Account) {
	slot, ok := parseSlot(r)
	if !ok {
		httpx.WriteError(w, r, http.StatusBadRequest, httpx.CodeValidationFailed, "slot 非法")
		return
	}
	versions, err := s.deps.Saves.Versions(r.Context(), account.ID, slot)
	if err != nil {
		httpx.WriteError(w, r, http.StatusInternalServerError, httpx.CodeInternal, "读取版本失败")
		return
	}
	if versions == nil {
		versions = []saves.Version{}
	}
	httpx.WriteJSON(w, http.StatusOK, versions)
}

type rollbackRequest struct {
	Version int `json:"version"`
}

func (s *Server) handleRollback(w http.ResponseWriter, r *http.Request, account auth.Account) {
	slot, ok := parseSlot(r)
	if !ok {
		httpx.WriteError(w, r, http.StatusBadRequest, httpx.CodeValidationFailed, "slot 非法")
		return
	}
	var req rollbackRequest
	if err := httpx.DecodeJSON(r, &req); err != nil || req.Version < 1 {
		httpx.WriteError(w, r, http.StatusBadRequest, httpx.CodeValidationFailed, "version 非法")
		return
	}
	rec, err := s.deps.Saves.Rollback(r.Context(), account.ID, slot, req.Version)
	if errors.Is(err, saves.ErrNotFound) {
		httpx.WriteError(w, r, http.StatusConflict, httpx.CodeConflict, "目标版本不存在")
		return
	}
	if err != nil {
		httpx.WriteError(w, r, http.StatusInternalServerError, httpx.CodeInternal, "回滚失败")
		return
	}
	w.Header().Set("ETag", saves.ETag(rec))
	httpx.WriteJSON(w, http.StatusOK, slotView(rec))
}

type resolveRequest struct {
	Resolution   string          `json:"resolution"`
	CloudVersion int             `json:"cloud_version"`
	LocalBlob    json.RawMessage `json:"local_blob"`
}

func (s *Server) handleResolve(w http.ResponseWriter, r *http.Request, account auth.Account) {
	slot, ok := parseSlot(r)
	if !ok {
		httpx.WriteError(w, r, http.StatusBadRequest, httpx.CodeValidationFailed, "slot 非法")
		return
	}
	var req resolveRequest
	if err := httpx.DecodeJSON(r, &req); err != nil {
		httpx.WriteError(w, r, http.StatusBadRequest, httpx.CodeValidationFailed, "请求体非法")
		return
	}
	rec, err := s.deps.Saves.Resolve(r.Context(), account.ID, slot, req.Resolution, req.CloudVersion, []byte(req.LocalBlob))
	if errors.Is(err, saves.ErrValidation) {
		httpx.WriteError(w, r, http.StatusConflict, httpx.CodeConflict, "冲突解决参数非法")
		return
	}
	if errors.Is(err, saves.ErrNotFound) {
		httpx.WriteError(w, r, http.StatusConflict, httpx.CodeConflict, "云端槽不存在")
		return
	}
	if err != nil {
		httpx.WriteError(w, r, http.StatusInternalServerError, httpx.CodeInternal, "冲突解决失败")
		return
	}
	w.Header().Set("ETag", saves.ETag(rec))
	httpx.WriteJSON(w, http.StatusOK, slotView(rec))
}

func slotView(rec saves.Record) saves.Slot {
	return saves.Slot{
		Slot:          rec.Slot,
		Version:       rec.Version,
		Hash:          rec.Hash,
		PlaythroughID: rec.PlaythroughID,
		UpdatedAt:     rec.CreatedAt,
	}
}

func queryInt(r *http.Request, key string, def, lo, hi int) int {
	v := r.URL.Query().Get(key)
	if v == "" {
		return def
	}
	n, err := strconv.Atoi(v)
	if err != nil || n < lo || n > hi {
		return def
	}
	return n
}

func nullIfEmpty(s string) any {
	if s == "" {
		return nil
	}
	return s
}
