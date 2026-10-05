package api

import (
	"encoding/json"
	"errors"
	"io"
	"net/http"

	"lifetextsandbox/server/internal/auth"
	"lifetextsandbox/server/internal/httpx"
	"lifetextsandbox/server/internal/legacy"
)

func (s *Server) handleGetLegacy(w http.ResponseWriter, r *http.Request, account auth.Account) {
	doc, tag, ok := s.deps.Legacy.Get(r.Context(), account.ID)
	if !ok {
		httpx.WriteError(w, r, http.StatusNotFound, httpx.CodeNotFound, "尚未有传承档案")
		return
	}
	if matchTag(r, tag) {
		w.WriteHeader(http.StatusNotModified)
		return
	}
	w.Header().Set("ETag", tag)
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write(doc)
}

func (s *Server) handlePutLegacy(w http.ResponseWriter, r *http.Request, account auth.Account) {
	doc, err := io.ReadAll(r.Body)
	if err != nil {
		httpx.WriteError(w, r, http.StatusBadRequest, httpx.CodeValidationFailed, "读取请求体失败")
		return
	}
	tag, err := s.deps.Legacy.Put(r.Context(), account.ID, doc, r.Header.Get("If-Match"))
	if errors.Is(err, legacy.ErrConflict) {
		httpx.WriteError(w, r, http.StatusConflict, httpx.CodeConflict, "传承档案版本冲突")
		return
	}
	if errors.Is(err, legacy.ErrValidation) {
		httpx.WriteError(w, r, http.StatusBadRequest, httpx.CodeValidationFailed, "传承档案非法")
		return
	}
	if err != nil {
		httpx.WriteError(w, r, http.StatusInternalServerError, httpx.CodeInternal, "写入传承失败")
		return
	}
	w.Header().Set("ETag", tag)
	var anyDoc any
	_ = json.Unmarshal(doc, &anyDoc)
	httpx.WriteJSON(w, http.StatusOK, anyDoc)
}
