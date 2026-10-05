package api

import (
	"net/http"

	"lifetextsandbox/server/internal/auth"
	"lifetextsandbox/server/internal/httpx"
)

type accountView struct {
	ID        string `json:"id"`
	Username  string `json:"username"`
	Role      string `json:"role"`
	CreatedAt string `json:"created_at"`
}

func (s *Server) handleAdminAccounts(w http.ResponseWriter, r *http.Request, _ auth.Account) {
	limit := queryInt(r, "limit", 50, 1, 200)
	cursor := r.URL.Query().Get("cursor")
	accounts, next := s.deps.Auth.ListAccounts(r.Context(), limit, cursor)
	items := make([]accountView, 0, len(accounts))
	for _, a := range accounts {
		items = append(items, accountView{
			ID:        a.ID,
			Username:  a.Username,
			Role:      a.Role,
			CreatedAt: a.CreatedAt.UTC().Format("2006-01-02T15:04:05Z07:00"),
		})
	}
	httpx.WriteJSON(w, http.StatusOK, map[string]any{
		"items":       items,
		"next_cursor": nullIfEmpty(next),
	})
}
