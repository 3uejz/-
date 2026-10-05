package api

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"net/http"
	"time"

	"lifetextsandbox/server/internal/httpx"
	"lifetextsandbox/server/internal/worldsim"
)

func (s *Server) currentWorld() ([]byte, string) {
	s.worldMu.Lock()
	defer s.worldMu.Unlock()
	if s.worldBytes == nil {
		summary := s.world.Summary(time.Now().UTC().Format(time.RFC3339), nil)
		data, _ := json.Marshal(summary)
		s.worldBytes = data
		sum := sha256.Sum256(data)
		s.worldTag = `"` + hex.EncodeToString(sum[:8]) + `"`
	}
	return s.worldBytes, s.worldTag
}

func (s *Server) handleWorldSummary(w http.ResponseWriter, r *http.Request) {
	data, tag := s.currentWorld()
	if matchTag(r, tag) {
		w.WriteHeader(http.StatusNotModified)
		return
	}
	w.Header().Set("ETag", tag)
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write(data)
}

func (s *Server) handleWorldSync(w http.ResponseWriter, r *http.Request) {
	var local worldsim.WorldSummary
	if err := httpx.DecodeJSON(r, &local); err != nil {
		httpx.WriteError(w, r, http.StatusBadRequest, httpx.CodeValidationFailed, "世界摘要非法")
		return
	}
	merged := s.world.Merge(local)
	merged.ComputedAt = time.Now().UTC().Format(time.RFC3339)
	httpx.WriteJSON(w, http.StatusOK, merged)
}
