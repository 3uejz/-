package api

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"lifetextsandbox/server/internal/auth"
	"lifetextsandbox/server/internal/config"
	"lifetextsandbox/server/internal/content"
	"lifetextsandbox/server/internal/legacy"
	"lifetextsandbox/server/internal/saves"
	"lifetextsandbox/server/internal/telemetry"
	"lifetextsandbox/server/internal/worldsim"
)

func newTestServer(t *testing.T) (*Server, http.Handler) {
	t.Helper()
	authSvc := auth.NewService(auth.NewMemoryStore(), "test-secret-at-least-32-bytes-long!!", 15*time.Minute, 24*time.Hour)
	deps := Deps{
		Config:    config.Config{RateLimitRPS: 0, SaveMaxBytes: 10 << 20},
		Logger:    slog.New(slog.NewTextHandler(io.Discard, nil)),
		Auth:      authSvc,
		Saves:     saves.NewService(saves.NewMemoryStore()),
		Content:   content.NewService(),
		Legacy:    legacy.NewService(legacy.NewMemoryStore()),
		Telemetry: telemetry.NewService(telemetry.NewMemoryStore(), 90),
		World:     worldsim.NewSimulator(7, 8_000_000_000),
	}
	srv := New(deps)
	return srv, srv.Router()
}

func doJSON(t *testing.T, h http.Handler, method, path, token string, body any, headers map[string]string) *httptest.ResponseRecorder {
	t.Helper()
	var reader io.Reader
	if body != nil {
		switch b := body.(type) {
		case string:
			reader = strings.NewReader(b)
		case []byte:
			reader = bytes.NewReader(b)
		default:
			data, err := json.Marshal(b)
			if err != nil {
				t.Fatal(err)
			}
			reader = bytes.NewReader(data)
		}
	}
	req := httptest.NewRequest(method, path, reader)
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	for k, v := range headers {
		req.Header.Set(k, v)
	}
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	return rec
}

func registerAndLogin(t *testing.T, h http.Handler, username string) string {
	t.Helper()
	rec := doJSON(t, h, http.MethodPost, "/api/v1/auth/register", "", map[string]string{
		"username": username, "password": "password123",
	}, nil)
	if rec.Code != http.StatusCreated {
		t.Fatalf("注册失败: %d %s", rec.Code, rec.Body.String())
	}
	var tokens auth.Tokens
	_ = json.Unmarshal(rec.Body.Bytes(), &tokens)
	return tokens.AccessToken
}

func saveDoc(playthrough string, marker int) string {
	return fmt.Sprintf(`{"meta":{"schema_version":1,"game_version":"0.1.0","playthrough_id":%q,"seed":7},"clock":{"absolute_minutes":0},"player":{},"world_delta":{},"rng":{},"marker":%d}`, playthrough, marker)
}

func TestAuthFlow(t *testing.T) {
	_, h := newTestServer(t)
	rec := doJSON(t, h, http.MethodPost, "/api/v1/auth/register", "", map[string]string{"username": "bob", "password": "password123"}, nil)
	if rec.Code != http.StatusCreated {
		t.Fatalf("注册期望 201，得到 %d", rec.Code)
	}
	if rec := doJSON(t, h, http.MethodPost, "/api/v1/auth/login", "", map[string]string{"username": "bob", "password": "wrong"}, nil); rec.Code != http.StatusUnauthorized {
		t.Fatalf("错误口令期望 401，得到 %d", rec.Code)
	}
	if rec := doJSON(t, h, http.MethodGet, "/api/v1/saves", "", nil, nil); rec.Code != http.StatusUnauthorized {
		t.Fatalf("无令牌期望 401，得到 %d", rec.Code)
	}
}

func TestSaveOptimisticLock(t *testing.T) {
	_, h := newTestServer(t)
	token := registerAndLogin(t, h, "carol")
	pt := "018f0000-0000-7000-8000-000000000000"

	rec := doJSON(t, h, http.MethodPut, "/api/v1/saves/1", token, saveDoc(pt, 1), nil)
	if rec.Code != http.StatusCreated {
		t.Fatalf("首次上传期望 201，得到 %d %s", rec.Code, rec.Body.String())
	}
	etag := rec.Header().Get("ETag")
	if etag == "" {
		t.Fatal("缺少 ETag")
	}

	rec = doJSON(t, h, http.MethodPut, "/api/v1/saves/1", token, saveDoc(pt, 2), map[string]string{"If-Match": etag})
	if rec.Code != http.StatusOK {
		t.Fatalf("匹配 ETag 覆盖期望 200，得到 %d %s", rec.Code, rec.Body.String())
	}

	rec = doJSON(t, h, http.MethodPut, "/api/v1/saves/1", token, saveDoc(pt, 3), map[string]string{"If-Match": etag})
	if rec.Code != http.StatusConflict {
		t.Fatalf("陈旧 ETag 期望 409，得到 %d", rec.Code)
	}

	rec = doJSON(t, h, http.MethodGet, "/api/v1/saves/1", token, nil, nil)
	if rec.Code != http.StatusOK || rec.Header().Get("ETag") == "" {
		t.Fatalf("读取存档异常: %d", rec.Code)
	}
	var doc map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &doc); err != nil {
		t.Fatalf("存档不是 JSON 对象: %v", err)
	}
}

func TestTelemetryAndAdmin(t *testing.T) {
	srv, h := newTestServer(t)
	token := registerAndLogin(t, h, "dave")

	events := map[string]any{"events": []any{
		map[string]any{"event_id": "018f0000-0000-7000-8000-000000000001", "event_type": "life.birth", "occurred_at": "2026-01-01T00:00:00Z", "schema_version": 1},
		map[string]any{"event_id": "bad", "event_type": "x"},
	}}
	rec := doJSON(t, h, http.MethodPost, "/api/v1/telemetry/events", token, events, nil)
	if rec.Code != http.StatusAccepted {
		t.Fatalf("遥测期望 202，得到 %d %s", rec.Code, rec.Body.String())
	}
	var resp struct {
		Accepted []string `json:"accepted"`
		Rejected []struct {
			Code string `json:"code"`
		} `json:"rejected"`
	}
	_ = json.Unmarshal(rec.Body.Bytes(), &resp)
	if len(resp.Accepted) != 1 || len(resp.Rejected) != 1 {
		t.Fatalf("遥测逐条结果异常: %+v", resp)
	}

	// 非管理员访问 403。
	if rec := doJSON(t, h, http.MethodGet, "/api/v1/admin/accounts", token, nil, nil); rec.Code != http.StatusForbidden {
		t.Fatalf("非管理员期望 403，得到 %d", rec.Code)
	}
	// 创建管理员并访问。
	if err := srv.deps.Auth.EnsureAdmin(t.Context(), "root", "admin-password"); err != nil {
		t.Fatal(err)
	}
	rec = doJSON(t, h, http.MethodPost, "/api/v1/auth/login", "", map[string]string{"username": "root", "password": "admin-password"}, nil)
	var adminTokens auth.Tokens
	_ = json.Unmarshal(rec.Body.Bytes(), &adminTokens)
	rec = doJSON(t, h, http.MethodGet, "/api/v1/admin/accounts", adminTokens.AccessToken, nil, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("管理员期望 200，得到 %d %s", rec.Code, rec.Body.String())
	}
}

func TestContentConfigLegacyWorld(t *testing.T) {
	_, h := newTestServer(t)
	token := registerAndLogin(t, h, "erin")

	rec := doJSON(t, h, http.MethodGet, "/api/v1/content/manifest", "", nil, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("清单期望 200，得到 %d", rec.Code)
	}
	tag := rec.Header().Get("ETag")
	if rec := doJSON(t, h, http.MethodGet, "/api/v1/content/manifest", "", nil, map[string]string{"If-None-Match": tag}); rec.Code != http.StatusNotModified {
		t.Fatalf("条件请求期望 304，得到 %d", rec.Code)
	}

	if rec := doJSON(t, h, http.MethodPut, "/api/v1/legacy", token, map[string]any{"generation": 1}, nil); rec.Code != http.StatusOK {
		t.Fatalf("写传承期望 200，得到 %d %s", rec.Code, rec.Body.String())
	}
	if rec := doJSON(t, h, http.MethodGet, "/api/v1/legacy", token, nil, nil); rec.Code != http.StatusOK {
		t.Fatalf("读传承期望 200，得到 %d", rec.Code)
	}

	if rec := doJSON(t, h, http.MethodGet, "/api/v1/world/summary", "", nil, nil); rec.Code != http.StatusOK {
		t.Fatalf("世界摘要期望 200，得到 %d", rec.Code)
	}
	summary := map[string]any{"version": 1, "computed_at": "2026-01-01T00:00:00Z", "global": map[string]any{"population": 100}}
	if rec := doJSON(t, h, http.MethodPost, "/api/v1/world/sync", "", summary, nil); rec.Code != http.StatusOK {
		t.Fatalf("世界同步期望 200，得到 %d %s", rec.Code, rec.Body.String())
	}
}
