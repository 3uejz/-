package api

import (
	"encoding/json"
	"net/http"

	"lifetextsandbox/server/internal/auth"
	"lifetextsandbox/server/internal/httpx"
	"lifetextsandbox/server/internal/telemetry"
)

type telemetryRequest struct {
	Events []json.RawMessage `json:"events"`
}

type telemetryResponse struct {
	Accepted []string           `json:"accepted"`
	Rejected []telemetry.Reject `json:"rejected"`
}

func (s *Server) handleTelemetry(w http.ResponseWriter, r *http.Request, _ auth.Account) {
	var req telemetryRequest
	if err := httpx.DecodeJSON(r, &req); err != nil || len(req.Events) > 500 {
		httpx.WriteError(w, r, http.StatusBadRequest, httpx.CodeValidationFailed, "遥测请求非法")
		return
	}
	accepted, rejected := s.deps.Telemetry.Ingest(r.Context(), req.Events)
	if accepted == nil {
		accepted = []string{}
	}
	if rejected == nil {
		rejected = []telemetry.Reject{}
	}
	httpx.WriteJSON(w, http.StatusAccepted, telemetryResponse{Accepted: accepted, Rejected: rejected})
}
