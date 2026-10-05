package api

import (
	"fmt"
	"net/http"
	"time"

	"lifetextsandbox/server/internal/httpx"
)

// Version 是后端版本，用于健康检查与指标。
const Version = "0.1.0"

var startedAt = time.Now()

func (s *Server) handleHealth(w http.ResponseWriter, _ *http.Request) {
	httpx.WriteJSON(w, http.StatusOK, map[string]any{
		"status":  "ok",
		"time":    time.Now().UTC().Format(time.RFC3339),
		"version": Version,
	})
}

func (s *Server) handleMetrics(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "text/plain; version=0.0.4; charset=utf-8")
	uptime := time.Since(startedAt).Seconds()
	fmt.Fprintf(w, "# HELP life_server_up 服务存活\n# TYPE life_server_up gauge\nlife_server_up 1\n")
	fmt.Fprintf(w, "# HELP life_server_uptime_seconds 运行时长\n# TYPE life_server_uptime_seconds gauge\nlife_server_uptime_seconds %.0f\n", uptime)
}
