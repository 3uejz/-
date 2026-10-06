package api

import (
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"net/http"
	"os"
	"runtime"
	"sort"
	"strconv"
	"strings"
	"time"

	"lifetextsandbox/server/internal/admin"
	"lifetextsandbox/server/internal/auth"
	"lifetextsandbox/server/internal/content"
	"lifetextsandbox/server/internal/db"
	"lifetextsandbox/server/internal/httpx"
	"lifetextsandbox/server/internal/saves"
)

// ---- 通用视图与辅助 ----

type accountView struct {
	ID        string `json:"id"`
	Username  string `json:"username"`
	Role      string `json:"role"`
	Disabled  bool   `json:"disabled"`
	CreatedAt string `json:"created_at"`
}

func toAccountView(a auth.Account) accountView {
	return accountView{
		ID:        a.ID,
		Username:  a.Username,
		Role:      a.Role,
		Disabled:  a.Disabled,
		CreatedAt: a.CreatedAt.UTC().Format(time.RFC3339),
	}
}

// recordAudit 写一条审计记录；审计失败不影响主流程。
func (s *Server) recordAudit(r *http.Request, actor auth.Account, action, targetType, targetID string, before, after map[string]any, result string) {
	if s.deps.Admin == nil {
		return
	}
	ip := ""
	if host, _, err := net.SplitHostPort(r.RemoteAddr); err == nil {
		ip = host
	}
	_ = s.deps.Admin.Audit(r.Context(), admin.AuditEntry{
		ActorAccountID: actor.ID,
		Action:         action,
		TargetType:     targetType,
		TargetID:       targetID,
		Before:         before,
		After:          after,
		Result:         result,
		IP:             ip,
		UserAgent:      r.UserAgent(),
	})
}

func (s *Server) syncConfig(v admin.ConfigVersion) {
	updated, _ := v.CreatedAt.UTC().MarshalText()
	doc, err := json.Marshal(map[string]any{
		"version":    v.Version,
		"updated_at": string(updated),
		"values":     v.Values,
	})
	if err != nil {
		return
	}
	_, _ = s.deps.Content.PutConfig(doc)
}

func (s *Server) syncAnnouncements(r *http.Request) {
	if s.deps.Admin == nil {
		return
	}
	list, err := s.deps.Admin.Announcements(r.Context())
	if err != nil {
		return
	}
	pub := make([]content.Announcement, 0, len(list))
	for _, a := range list {
		if a.Status != "published" {
			continue
		}
		ca := content.Announcement{ID: a.ID, Title: a.Title, Body: a.Body}
		if a.StartAt != nil {
			ca.StartAt = a.StartAt.UTC().Format(time.RFC3339)
		}
		if a.EndAt != nil {
			ca.EndAt = a.EndAt.UTC().Format(time.RFC3339)
		}
		pub = append(pub, ca)
	}
	s.deps.Content.ReplaceAnnouncements(pub)
}

func splitSaveID(id string) (string, int, bool) {
	account, slotStr, ok := strings.Cut(id, ":")
	if !ok {
		return "", 0, false
	}
	slot, err := strconv.Atoi(slotStr)
	if err != nil {
		return "", 0, false
	}
	return account, slot, true
}

// jsonMap 把任意可序列化对象转为审计快照用的 map。
func jsonMap(v any) map[string]any {
	if v == nil {
		return nil
	}
	data, err := json.Marshal(v)
	if err != nil {
		return nil
	}
	var m map[string]any
	if json.Unmarshal(data, &m) != nil {
		return nil
	}
	return m
}

// ---- 登录与仪表盘 ----

func (s *Server) handleAdminMe(w http.ResponseWriter, _ *http.Request, account auth.Account) {
	httpx.WriteJSON(w, http.StatusOK, toAccountView(account))
}

func (s *Server) handleAdminDashboard(w http.ResponseWriter, r *http.Request, _ auth.Account) {
	total, disabled := s.deps.Auth.Count(r.Context())
	slots, versions, bytes := s.deps.Saves.AdminStats(r.Context())

	events := s.deps.Telemetry.List(r.Context(), "", 100000)
	since7 := time.Now().Add(-7 * 24 * time.Hour)
	since30 := time.Now().Add(-30 * 24 * time.Hour)
	var last7, last30 int
	for _, e := range events {
		if e.OccurredAt.After(since7) {
			last7++
		}
		if e.OccurredAt.After(since30) {
			last30++
		}
	}

	summary := s.world.Summary(time.Now().UTC().Format(time.RFC3339), nil)
	backups := s.listBackups()

	httpx.WriteJSON(w, http.StatusOK, map[string]any{
		"accounts": map[string]any{"total": total, "disabled": disabled},
		"saves":    map[string]any{"slots": slots, "versions": versions, "bytes": bytes},
		"world":    summary.Global,
		"telemetry": map[string]any{
			"total":    len(events),
			"last_7d":  last7,
			"last_30d": last30,
		},
		"backups": map[string]any{"count": len(backups), "latest": firstOrNil(backups)},
		"health":  map[string]any{"status": "ok"},
	})
}

func firstOrNil(items []map[string]any) any {
	if len(items) == 0 {
		return nil
	}
	return items[0]
}

// ---- 账号与设备 ----

func (s *Server) handleAdminAccounts(w http.ResponseWriter, r *http.Request, _ auth.Account) {
	limit := queryInt(r, "limit", 50, 1, 200)
	cursor := r.URL.Query().Get("cursor")
	q := strings.ToLower(strings.TrimSpace(r.URL.Query().Get("q")))
	status := r.URL.Query().Get("status")

	accounts, next := s.deps.Auth.ListAccounts(r.Context(), limit*4, cursor)
	items := make([]accountView, 0, len(accounts))
	for _, a := range accounts {
		if q != "" && !strings.Contains(strings.ToLower(a.Username), q) {
			continue
		}
		if status == "disabled" && !a.Disabled {
			continue
		}
		if status == "active" && a.Disabled {
			continue
		}
		items = append(items, toAccountView(a))
		if len(items) >= limit {
			break
		}
	}
	httpx.WriteJSON(w, http.StatusOK, map[string]any{
		"items":       items,
		"next_cursor": nullIfEmpty(next),
	})
}

func (s *Server) handleAdminAccount(w http.ResponseWriter, r *http.Request, _ auth.Account) {
	account, ok := s.deps.Auth.Account(r.Context(), r.PathValue("id"))
	if !ok {
		httpx.WriteError(w, r, http.StatusNotFound, httpx.CodeNotFound, "账号不存在")
		return
	}
	slots := s.deps.Saves.AdminSlots(r.Context(), 1000)
	saveCount := 0
	for _, sc := range slots {
		if sc.AccountID == account.ID {
			saveCount++
		}
	}
	devices := s.deps.Auth.Devices(r.Context(), account.ID)
	httpx.WriteJSON(w, http.StatusOK, map[string]any{
		"account":      toAccountView(account),
		"save_count":   saveCount,
		"device_count": len(devices),
	})
}

func (s *Server) handleAdminDisable(w http.ResponseWriter, r *http.Request, actor auth.Account) {
	s.setDisabled(w, r, actor, true)
}

func (s *Server) handleAdminEnable(w http.ResponseWriter, r *http.Request, actor auth.Account) {
	s.setDisabled(w, r, actor, false)
}

func (s *Server) setDisabled(w http.ResponseWriter, r *http.Request, actor auth.Account, disabled bool) {
	id := r.PathValue("id")
	account, err := s.deps.Auth.SetDisabled(r.Context(), id, disabled)
	if err != nil {
		httpx.WriteError(w, r, http.StatusNotFound, httpx.CodeNotFound, "账号不存在")
		return
	}
	action := "account.disable"
	if !disabled {
		action = "account.enable"
	}
	s.recordAudit(r, actor, action, "account", id,
		map[string]any{"disabled": !disabled}, map[string]any{"disabled": disabled}, "ok")
	httpx.WriteJSON(w, http.StatusOK, toAccountView(account))
}

func (s *Server) handleAdminDevices(w http.ResponseWriter, r *http.Request, _ auth.Account) {
	id := r.PathValue("id")
	devices := s.deps.Auth.Devices(r.Context(), id)
	items := make([]map[string]any, 0, len(devices))
	for _, d := range devices {
		items = append(items, map[string]any{
			"device_id":  d.DeviceID,
			"created_at": d.CreatedAt.UTC().Format(time.RFC3339),
			"expires_at": d.ExpiresAt.UTC().Format(time.RFC3339),
		})
	}
	httpx.WriteJSON(w, http.StatusOK, map[string]any{"items": items})
}

func (s *Server) handleAdminRevokeDevice(w http.ResponseWriter, r *http.Request, actor auth.Account) {
	id := r.PathValue("id")
	deviceID := r.PathValue("device_id")
	if err := s.deps.Auth.RevokeDevice(r.Context(), id, deviceID); err != nil {
		httpx.WriteError(w, r, http.StatusInternalServerError, httpx.CodeInternal, "吊销设备失败")
		return
	}
	s.recordAudit(r, actor, "account.revoke_device", "device", deviceID,
		map[string]any{"account_id": id}, map[string]any{"revoked": true}, "ok")
	w.WriteHeader(http.StatusNoContent)
}

// ---- 存档运维 ----

func (s *Server) handleAdminSaves(w http.ResponseWriter, r *http.Request, _ auth.Account) {
	limit := queryInt(r, "limit", 50, 1, 500)
	slots := s.deps.Saves.AdminSlots(r.Context(), limit)
	httpx.WriteJSON(w, http.StatusOK, map[string]any{
		"items":   slots,
		"id_hint": "存档 id 形如 <account_id>:<slot>",
	})
}

func (s *Server) handleAdminSave(w http.ResponseWriter, r *http.Request, _ auth.Account) {
	account, slot, ok := splitSaveID(r.PathValue("id"))
	if !ok {
		httpx.WriteError(w, r, http.StatusBadRequest, httpx.CodeValidationFailed, "存档 id 非法")
		return
	}
	rec, err := s.deps.Saves.Get(r.Context(), account, slot)
	if err != nil {
		httpx.WriteError(w, r, http.StatusNotFound, httpx.CodeNotFound, "存档不存在")
		return
	}
	httpx.WriteJSON(w, http.StatusOK, map[string]any{
		"account_id":     account,
		"slot":           rec.Slot,
		"version":        rec.Version,
		"hash":           rec.Hash,
		"playthrough_id": rec.PlaythroughID,
		"size":           len(rec.Doc),
		"created_at":     rec.CreatedAt.UTC().Format(time.RFC3339),
	})
}

func (s *Server) handleAdminSaveVersions(w http.ResponseWriter, r *http.Request, _ auth.Account) {
	account, slot, ok := splitSaveID(r.PathValue("id"))
	if !ok {
		httpx.WriteError(w, r, http.StatusBadRequest, httpx.CodeValidationFailed, "存档 id 非法")
		return
	}
	versions, err := s.deps.Saves.Versions(r.Context(), account, slot)
	if err != nil {
		httpx.WriteError(w, r, http.StatusInternalServerError, httpx.CodeInternal, "读取版本失败")
		return
	}
	if versions == nil {
		versions = []saves.Version{}
	}
	httpx.WriteJSON(w, http.StatusOK, map[string]any{"items": versions})
}

func (s *Server) handleAdminSaveRollback(w http.ResponseWriter, r *http.Request, actor auth.Account) {
	account, slot, ok := splitSaveID(r.PathValue("id"))
	if !ok {
		httpx.WriteError(w, r, http.StatusBadRequest, httpx.CodeValidationFailed, "存档 id 非法")
		return
	}
	var body struct {
		Version int `json:"version"`
	}
	if err := httpx.DecodeJSON(r, &body); err != nil || body.Version < 1 {
		httpx.WriteError(w, r, http.StatusBadRequest, httpx.CodeValidationFailed, "缺少 version")
		return
	}
	rec, err := s.deps.Saves.Rollback(r.Context(), account, slot, body.Version)
	if err != nil {
		httpx.WriteError(w, r, http.StatusNotFound, httpx.CodeNotFound, "目标版本不存在")
		return
	}
	s.recordAudit(r, actor, "save.rollback", "save", r.PathValue("id"),
		map[string]any{"version": body.Version}, map[string]any{"new_version": rec.Version}, "ok")
	httpx.WriteJSON(w, http.StatusOK, map[string]any{"version": rec.Version, "hash": rec.Hash})
}

func (s *Server) handleAdminStorageUsage(w http.ResponseWriter, r *http.Request, _ auth.Account) {
	slots, versions, bytes := s.deps.Saves.AdminStats(r.Context())
	httpx.WriteJSON(w, http.StatusOK, map[string]any{
		"slots":    slots,
		"versions": versions,
		"bytes":    bytes,
	})
}

func (s *Server) handleAdminStorageGC(w http.ResponseWriter, r *http.Request, actor auth.Account) {
	s.recordAudit(r, actor, "storage.gc", "storage", "", nil, map[string]any{"scanned": 0, "removed": 0}, "ok")
	httpx.WriteJSON(w, http.StatusAccepted, map[string]any{
		"scanned": 0,
		"removed": 0,
		"message": "孤立对象清理将在对象存储提供列举能力后启用",
	})
}

// ---- 内容管理 ----

type packView struct {
	Name    string `json:"name"`
	Kind    string `json:"kind"`
	Version string `json:"version"`
	Hash    string `json:"hash"`
	Size    int64  `json:"size"`
	URL     string `json:"url"`
	Status  string `json:"status"`
}

func (s *Server) manifestPacks() []packView {
	doc, _ := s.deps.Content.Manifest()
	var manifest struct {
		Packs []packView `json:"packs"`
	}
	if err := json.Unmarshal(doc, &manifest); err != nil {
		return nil
	}
	for i := range manifest.Packs {
		if manifest.Packs[i].Status == "" {
			manifest.Packs[i].Status = "published"
		}
	}
	return manifest.Packs
}

func (s *Server) handleAdminContentPacks(w http.ResponseWriter, r *http.Request, _ auth.Account) {
	packs := s.manifestPacks()
	if packs == nil {
		packs = []packView{}
	}
	httpx.WriteJSON(w, http.StatusOK, map[string]any{"items": packs})
}

func (s *Server) handleAdminContentPackUpload(w http.ResponseWriter, r *http.Request, actor auth.Account) {
	var pack packView
	if err := httpx.DecodeJSON(r, &pack); err != nil {
		httpx.WriteError(w, r, http.StatusBadRequest, httpx.CodeValidationFailed, "内容包非法")
		return
	}
	if pack.Name == "" || pack.Kind == "" || pack.Version == "" || pack.Hash == "" || pack.URL == "" {
		httpx.WriteError(w, r, http.StatusBadRequest, httpx.CodeValidationFailed, "内容包必填字段缺失")
		return
	}
	doc, _ := s.deps.Content.Manifest()
	var manifest map[string]any
	if err := json.Unmarshal(doc, &manifest); err != nil {
		manifest = map[string]any{}
	}
	var packs []any
	if existing, ok := manifest["packs"].([]any); ok {
		packs = existing
	}
	replaced := false
	for i := range packs {
		if m, ok := packs[i].(map[string]any); ok && m["name"] == pack.Name {
			packs[i] = pack
			replaced = true
			break
		}
	}
	if !replaced {
		packs = append(packs, pack)
	}
	manifest["packs"] = packs
	if _, ok := manifest["manifest_version"]; !ok {
		manifest["manifest_version"] = 1
	}
	if _, ok := manifest["generated_at"]; !ok {
		manifest["generated_at"] = time.Now().UTC().Format(time.RFC3339)
	}
	out, _ := json.Marshal(manifest)
	if _, err := s.deps.Content.PublishManifest(out); err != nil {
		httpx.WriteError(w, r, http.StatusBadRequest, httpx.CodeValidationFailed, "清单非法")
		return
	}
	s.recordAudit(r, actor, "content.pack.upload", "content_pack", pack.Name, nil, jsonMap(pack), "ok")
	httpx.WriteJSON(w, http.StatusCreated, pack)
}

func (s *Server) handleAdminContentValidate(w http.ResponseWriter, r *http.Request, _ auth.Account) {
	name := r.PathValue("name")
	issues := []string{}
	found := false
	for _, p := range s.manifestPacks() {
		if p.Name == name {
			found = true
			if p.Hash == "" || !strings.HasPrefix(p.Hash, "sha256:") {
				issues = append(issues, "hash 缺失或未使用 sha256 前缀")
			}
			if p.Size < 0 {
				issues = append(issues, "size 非法")
			}
		}
	}
	if !found {
		issues = append(issues, "清单中不存在该内容包")
	}
	httpx.WriteJSON(w, http.StatusOK, map[string]any{"name": name, "valid": len(issues) == 0, "issues": issues})
}

func (s *Server) handleAdminReleases(w http.ResponseWriter, r *http.Request, _ auth.Account) {
	list, err := s.deps.Admin.Releases(r.Context())
	if err != nil {
		httpx.WriteError(w, r, http.StatusInternalServerError, httpx.CodeInternal, "读取发布批次失败")
		return
	}
	if list == nil {
		list = []admin.Release{}
	}
	httpx.WriteJSON(w, http.StatusOK, map[string]any{"items": list})
}

func (s *Server) handleAdminCreateRelease(w http.ResponseWriter, r *http.Request, actor auth.Account) {
	var rel admin.Release
	if err := httpx.DecodeJSON(r, &rel); err != nil {
		httpx.WriteError(w, r, http.StatusBadRequest, httpx.CodeValidationFailed, "发布批次非法")
		return
	}
	created, err := s.deps.Admin.CreateRelease(r.Context(), rel)
	if err != nil {
		if errors.Is(err, admin.ErrValidation) {
			httpx.WriteError(w, r, http.StatusBadRequest, httpx.CodeValidationFailed, "发布参数非法")
			return
		}
		httpx.WriteError(w, r, http.StatusInternalServerError, httpx.CodeInternal, "创建发布失败")
		return
	}
	s.recordAudit(r, actor, "content.release.create", "release", created.ID, nil, jsonMap(created), "ok")
	httpx.WriteJSON(w, http.StatusCreated, created)
}

func (s *Server) handleAdminReleaseAction(action string) authedHandler {
	return func(w http.ResponseWriter, r *http.Request, actor auth.Account) {
		id := r.PathValue("id")
		updated, err := s.deps.Admin.SetReleaseStatus(r.Context(), id, action)
		if err != nil {
			switch {
			case errors.Is(err, admin.ErrNotFound):
				httpx.WriteError(w, r, http.StatusNotFound, httpx.CodeNotFound, "发布批次不存在")
			case errors.Is(err, admin.ErrValidation):
				httpx.WriteError(w, r, http.StatusConflict, httpx.CodeConflict, "发布状态不允许该操作")
			default:
				httpx.WriteError(w, r, http.StatusInternalServerError, httpx.CodeInternal, "发布操作失败")
			}
			return
		}
		s.recordAudit(r, actor, "content.release."+action, "release", id, nil, map[string]any{"status": updated.Status}, "ok")
		httpx.WriteJSON(w, http.StatusOK, updated)
	}
}

// ---- 远程配置 ----

func (s *Server) handleAdminGetConfig(w http.ResponseWriter, r *http.Request, _ auth.Account) {
	current, ok := s.deps.Admin.CurrentConfig(r.Context())
	if !ok {
		httpx.WriteJSON(w, http.StatusOK, map[string]any{"version": 0, "revision": 0, "values": map[string]any{}})
		return
	}
	httpx.WriteJSON(w, http.StatusOK, current)
}

func (s *Server) handleAdminPutConfig(w http.ResponseWriter, r *http.Request, actor auth.Account) {
	var body struct {
		Revision int            `json:"revision"`
		Values   map[string]any `json:"values"`
	}
	if err := httpx.DecodeJSON(r, &body); err != nil || body.Values == nil {
		httpx.WriteError(w, r, http.StatusBadRequest, httpx.CodeValidationFailed, "配置非法")
		return
	}
	v, err := s.deps.Admin.SaveConfig(r.Context(), body.Values, actor.ID, body.Revision)
	if err != nil {
		if errors.Is(err, admin.ErrConflict) {
			httpx.WriteError(w, r, http.StatusConflict, httpx.CodeConflict, "配置已被他人修改，请刷新后重试")
			return
		}
		httpx.WriteError(w, r, http.StatusBadRequest, httpx.CodeValidationFailed, "配置非法")
		return
	}
	s.syncConfig(v)
	s.recordAudit(r, actor, "config.publish", "config", strconv.Itoa(v.Version), nil, map[string]any{"version": v.Version, "revision": v.Revision}, "ok")
	httpx.WriteJSON(w, http.StatusOK, v)
}

func (s *Server) handleAdminConfigVersions(w http.ResponseWriter, r *http.Request, _ auth.Account) {
	list, err := s.deps.Admin.ConfigVersions(r.Context())
	if err != nil {
		httpx.WriteError(w, r, http.StatusInternalServerError, httpx.CodeInternal, "读取配置版本失败")
		return
	}
	if list == nil {
		list = []admin.ConfigVersion{}
	}
	httpx.WriteJSON(w, http.StatusOK, map[string]any{"items": list})
}

func (s *Server) handleAdminConfigRollback(w http.ResponseWriter, r *http.Request, actor auth.Account) {
	var body struct {
		Version int `json:"version"`
	}
	if err := httpx.DecodeJSON(r, &body); err != nil || body.Version < 1 {
		httpx.WriteError(w, r, http.StatusBadRequest, httpx.CodeValidationFailed, "缺少 version")
		return
	}
	v, err := s.deps.Admin.RollbackConfig(r.Context(), body.Version, actor.ID)
	if err != nil {
		if errors.Is(err, admin.ErrNotFound) {
			httpx.WriteError(w, r, http.StatusNotFound, httpx.CodeNotFound, "目标版本不存在")
			return
		}
		httpx.WriteError(w, r, http.StatusInternalServerError, httpx.CodeInternal, "回滚失败")
		return
	}
	s.syncConfig(v)
	s.recordAudit(r, actor, "config.rollback", "config", strconv.Itoa(body.Version), nil, map[string]any{"new_version": v.Version}, "ok")
	httpx.WriteJSON(w, http.StatusOK, v)
}

// ---- 公告 ----

func (s *Server) handleAdminAnnouncements(w http.ResponseWriter, r *http.Request, _ auth.Account) {
	list, err := s.deps.Admin.Announcements(r.Context())
	if err != nil {
		httpx.WriteError(w, r, http.StatusInternalServerError, httpx.CodeInternal, "读取公告失败")
		return
	}
	if list == nil {
		list = []admin.Announcement{}
	}
	httpx.WriteJSON(w, http.StatusOK, map[string]any{"items": list})
}

func (s *Server) handleAdminCreateAnnouncement(w http.ResponseWriter, r *http.Request, actor auth.Account) {
	var a admin.Announcement
	if err := httpx.DecodeJSON(r, &a); err != nil {
		httpx.WriteError(w, r, http.StatusBadRequest, httpx.CodeValidationFailed, "公告非法")
		return
	}
	created, err := s.deps.Admin.CreateAnnouncement(r.Context(), a)
	if err != nil {
		httpx.WriteError(w, r, http.StatusBadRequest, httpx.CodeValidationFailed, "公告非法")
		return
	}
	s.syncAnnouncements(r)
	s.recordAudit(r, actor, "announcement.create", "announcement", created.ID, nil, jsonMap(created), "ok")
	httpx.WriteJSON(w, http.StatusCreated, created)
}

func (s *Server) handleAdminUpdateAnnouncement(w http.ResponseWriter, r *http.Request, actor auth.Account) {
	var a admin.Announcement
	if err := httpx.DecodeJSON(r, &a); err != nil {
		httpx.WriteError(w, r, http.StatusBadRequest, httpx.CodeValidationFailed, "公告非法")
		return
	}
	a.ID = r.PathValue("id")
	before, _ := s.deps.Admin.Announcements(r.Context())
	updated, err := s.deps.Admin.UpdateAnnouncement(r.Context(), a)
	if err != nil {
		httpx.WriteError(w, r, http.StatusNotFound, httpx.CodeNotFound, "公告不存在")
		return
	}
	s.syncAnnouncements(r)
	s.recordAudit(r, actor, "announcement.update", "announcement", a.ID, findAnnouncement(before, a.ID), jsonMap(updated), "ok")
	httpx.WriteJSON(w, http.StatusOK, updated)
}

func (s *Server) handleAdminDeleteAnnouncement(w http.ResponseWriter, r *http.Request, actor auth.Account) {
	id := r.PathValue("id")
	if err := s.deps.Admin.DeleteAnnouncement(r.Context(), id); err != nil {
		httpx.WriteError(w, r, http.StatusNotFound, httpx.CodeNotFound, "公告不存在")
		return
	}
	s.syncAnnouncements(r)
	s.recordAudit(r, actor, "announcement.delete", "announcement", id, nil, nil, "ok")
	w.WriteHeader(http.StatusNoContent)
}

func findAnnouncement(list []admin.Announcement, id string) map[string]any {
	for _, a := range list {
		if a.ID == id {
			return map[string]any{"title": a.Title, "status": a.Status}
		}
	}
	return nil
}

// ---- 遥测与统计 ----

func (s *Server) handleAdminTelemetryEvents(w http.ResponseWriter, r *http.Request, _ auth.Account) {
	limit := queryInt(r, "limit", 100, 1, 1000)
	eventType := r.URL.Query().Get("event_type")
	events := s.deps.Telemetry.List(r.Context(), eventType, limit)
	items := make([]map[string]any, 0, len(events))
	for _, e := range events {
		items = append(items, map[string]any{
			"event_id":    e.EventID,
			"event_type":  e.EventType,
			"occurred_at": e.OccurredAt.UTC().Format(time.RFC3339),
			"account_id":  e.AccountID,
			"payload":     json.RawMessage(e.Raw),
		})
	}
	httpx.WriteJSON(w, http.StatusOK, map[string]any{"items": items})
}

func (s *Server) handleAdminTelemetryAggregates(w http.ResponseWriter, r *http.Request, _ auth.Account) {
	events := s.deps.Telemetry.List(r.Context(), "", 100000)
	byType := map[string]int{}
	byDay := map[string]int{}
	for _, e := range events {
		byType[e.EventType]++
		byDay[e.OccurredAt.UTC().Format("2006-01-02")]++
	}
	httpx.WriteJSON(w, http.StatusOK, map[string]any{
		"total":   len(events),
		"by_type": byType,
		"by_day":  byDay,
	})
}

func (s *Server) handleAdminTelemetryLifeStats(w http.ResponseWriter, r *http.Request, _ auth.Account) {
	events := s.deps.Telemetry.List(r.Context(), "", 100000)
	byType := map[string]int{}
	total := 0
	for _, e := range events {
		if strings.HasPrefix(e.EventType, "life.") {
			byType[e.EventType]++
			total++
		}
	}
	httpx.WriteJSON(w, http.StatusOK, map[string]any{"total": total, "by_type": byType})
}

func (s *Server) handleAdminTelemetryExport(w http.ResponseWriter, r *http.Request, actor auth.Account) {
	format := r.URL.Query().Get("format")
	if format == "" {
		format = "json"
	}
	accountID := r.URL.Query().Get("account_id")
	var events []map[string]any
	if accountID != "" {
		for _, raw := range s.deps.Telemetry.Export(r.Context(), accountID) {
			var m map[string]any
			if json.Unmarshal(raw, &m) == nil {
				events = append(events, m)
			}
		}
	} else {
		for _, e := range s.deps.Telemetry.List(r.Context(), "", 100000) {
			var m map[string]any
			if json.Unmarshal(e.Raw, &m) == nil {
				events = append(events, m)
			}
		}
	}
	s.recordAudit(r, actor, "telemetry.export", "telemetry", accountID, nil, map[string]any{"count": len(events), "format": format}, "ok")

	if format == "csv" {
		w.Header().Set("Content-Type", "text/csv; charset=utf-8")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(toCSV(events)))
		return
	}
	httpx.WriteJSON(w, http.StatusOK, map[string]any{"items": events})
}

func toCSV(events []map[string]any) string {
	keys := map[string]bool{"event_id": true, "event_type": true, "occurred_at": true, "schema_version": true}
	for _, e := range events {
		for k := range e {
			keys[k] = true
		}
	}
	cols := make([]string, 0, len(keys))
	for k := range keys {
		cols = append(cols, k)
	}
	sort.Strings(cols)
	var b strings.Builder
	b.WriteString(strings.Join(cols, ","))
	b.WriteString("\n")
	for _, e := range events {
		row := make([]string, len(cols))
		for i, c := range cols {
			row[i] = csvEscape(fmt.Sprint(e[c]))
		}
		b.WriteString(strings.Join(row, ","))
		b.WriteString("\n")
	}
	return b.String()
}

func csvEscape(s string) string {
	if strings.ContainsAny(s, ",\"\n") {
		return `"` + strings.ReplaceAll(s, `"`, `""`) + `"`
	}
	return s
}

func (s *Server) handleAdminTelemetryPurge(w http.ResponseWriter, r *http.Request, actor auth.Account) {
	var body struct {
		AccountID string `json:"account_id"`
		Before    string `json:"before"`
	}
	_ = httpx.DecodeJSON(r, &body)
	var removed int
	target := body.AccountID
	if body.AccountID != "" {
		removed = s.deps.Telemetry.Delete(r.Context(), body.AccountID)
	} else {
		before := time.Now().Add(-s.deps.Telemetry.Retention())
		if body.Before != "" {
			if t, err := time.Parse(time.RFC3339, body.Before); err == nil {
				before = t
			}
		}
		removed = s.deps.Telemetry.PurgeBefore(r.Context(), before)
		target = before.UTC().Format(time.RFC3339)
	}
	s.recordAudit(r, actor, "telemetry.purge", "telemetry", target, nil, map[string]any{"removed": removed}, "ok")
	httpx.WriteJSON(w, http.StatusOK, map[string]any{"removed": removed})
}

// ---- 审计日志 ----

func (s *Server) handleAdminAuditLogs(w http.ResponseWriter, r *http.Request, _ auth.Account) {
	limit := queryInt(r, "limit", 50, 1, 500)
	action := r.URL.Query().Get("action")
	actor := r.URL.Query().Get("actor")
	target := r.URL.Query().Get("target")
	list, err := s.deps.Admin.Audits(r.Context(), action, actor, target, limit)
	if err != nil {
		httpx.WriteError(w, r, http.StatusInternalServerError, httpx.CodeInternal, "读取审计日志失败")
		return
	}
	if list == nil {
		list = []admin.AuditEntry{}
	}
	httpx.WriteJSON(w, http.StatusOK, map[string]any{"items": list})
}

// ---- 运营助手（预留，默认关闭） ----

func (s *Server) handleAdminAssistantStatus(w http.ResponseWriter, _ *http.Request, _ auth.Account) {
	httpx.WriteJSON(w, http.StatusOK, map[string]any{
		"enabled": false,
		"ready":   false,
		"message": "运营助手默认关闭，需在部署时启用本地模型",
	})
}

func (s *Server) handleAdminAssistantUnavailable(w http.ResponseWriter, r *http.Request, _ auth.Account) {
	httpx.WriteError(w, r, http.StatusServiceUnavailable, httpx.CodeUpstreamUnavailable, "运营助手未启用")
}

// ---- 系统运维 ----

func (s *Server) handleAdminSystemStatus(w http.ResponseWriter, r *http.Request, _ auth.Account) {
	cfg := s.deps.Config
	secrets := map[string]bool{
		"JWT_SECRET":        cfg.JWTSecret != "",
		"ADMIN_PASSWORD":    cfg.AdminPassword != "",
		"OBJECT_ACCESS_KEY": cfg.ObjectKey != "",
		"OBJECT_SECRET_KEY": cfg.ObjectSecret != "",
	}
	missing := []string{}
	for k, ok := range secrets {
		if !ok {
			missing = append(missing, k)
		}
	}
	sort.Strings(missing)
	httpx.WriteJSON(w, http.StatusOK, map[string]any{
		"go":       runtime.Version(),
		"uptime_s": int(time.Since(s.startedAt).Seconds()),
		"postgres": tern(cfg.DatabaseURL != "", "configured", "memory"),
		"redis":    tern(cfg.RedisURL != "", "configured", "in-process"),
		"storage":  tern(cfg.HasObjectStore(), "minio", "local"),
		"secrets":  secrets,
		"alerts":   missing,
	})
}

func (s *Server) handleAdminSystemBackups(w http.ResponseWriter, r *http.Request, _ auth.Account) {
	httpx.WriteJSON(w, http.StatusOK, map[string]any{"items": s.listBackups()})
}

func (s *Server) listBackups() []map[string]any {
	entries, err := os.ReadDir(s.deps.Config.BackupDir)
	if err != nil {
		return []map[string]any{}
	}
	items := make([]map[string]any, 0, len(entries))
	for _, e := range entries {
		if e.IsDir() || !strings.HasPrefix(e.Name(), "lifetext-") {
			continue
		}
		info, err := e.Info()
		if err != nil {
			continue
		}
		items = append(items, map[string]any{
			"name":       e.Name(),
			"size":       info.Size(),
			"created_at": info.ModTime().UTC().Format(time.RFC3339),
		})
	}
	sort.Slice(items, func(i, j int) bool {
		return fmt.Sprint(items[i]["created_at"]) > fmt.Sprint(items[j]["created_at"])
	})
	return items
}

func (s *Server) handleAdminSystemBackup(w http.ResponseWriter, r *http.Request, actor auth.Account) {
	if s.deps.Backup == nil {
		httpx.WriteError(w, r, http.StatusServiceUnavailable, httpx.CodeUpstreamUnavailable, "备份未启用（未配置 DATABASE_URL）")
		return
	}
	path, err := s.deps.Backup.Backup(r.Context())
	if err != nil {
		s.recordAudit(r, actor, "system.backup", "system", "", nil, map[string]any{"error": err.Error()}, "error")
		httpx.WriteError(w, r, http.StatusInternalServerError, httpx.CodeInternal, "备份失败")
		return
	}
	s.recordAudit(r, actor, "system.backup", "system", path, nil, map[string]any{"path": path}, "ok")
	httpx.WriteJSON(w, http.StatusAccepted, map[string]any{"path": path})
}

func (s *Server) handleAdminSystemMigrations(w http.ResponseWriter, _ *http.Request, _ auth.Account) {
	names := db.MigrationNames()
	httpx.WriteJSON(w, http.StatusOK, map[string]any{"available": names, "current": lastOrEmpty(names)})
}

func lastOrEmpty(names []string) string {
	if len(names) == 0 {
		return ""
	}
	return names[len(names)-1]
}

func tern(cond bool, a, b string) string {
	if cond {
		return a
	}
	return b
}
