package admin

import (
	"context"
	"errors"
	"testing"
)

func newSvc() *Service { return NewService(NewMemoryStore()) }

func TestAuditAppendAndFilter(t *testing.T) {
	ctx := context.Background()
	s := newSvc()
	if err := s.Audit(ctx, AuditEntry{ActorAccountID: "a1", Action: "account.disable", TargetType: "account", TargetID: "x1"}); err != nil {
		t.Fatal(err)
	}
	if err := s.Audit(ctx, AuditEntry{ActorAccountID: "a2", Action: "config.put", TargetType: "config", TargetID: "c"}); err != nil {
		t.Fatal(err)
	}
	if err := s.Audit(ctx, AuditEntry{Action: "x"}); !errors.Is(err, ErrValidation) {
		t.Fatalf("缺少 actor 应校验失败: %v", err)
	}
	all, _ := s.Audits(ctx, "", "", "", 10)
	if len(all) != 2 {
		t.Fatalf("应有 2 条审计，实际 %d", len(all))
	}
	if all[0].CreatedAt.IsZero() || all[0].Result != "ok" {
		t.Fatalf("审计字段未补全: %+v", all[0])
	}
	filtered, _ := s.Audits(ctx, "account.disable", "", "", 10)
	if len(filtered) != 1 || filtered[0].TargetID != "x1" {
		t.Fatalf("按 action 过滤失败: %+v", filtered)
	}
}

func TestReleaseStateMachine(t *testing.T) {
	ctx := context.Background()
	s := newSvc()
	r, err := s.CreateRelease(ctx, Release{PackName: "core", PackVersion: "1.2.0", Strategy: "percent", RolloutPercent: 30, ManifestVersion: 3})
	if err != nil {
		t.Fatal(err)
	}
	if r.Status != "rolling" {
		t.Fatalf("新建应为 rolling: %s", r.Status)
	}
	// 确定性灰度分桶。
	if !Delivers(r, "account-in-list") {
		// 30% 命中率下不保证某账号命中，但应稳定：重复调用结果一致。
		if Delivers(r, "account-in-list") != Delivers(r, "account-in-list") {
			t.Fatal("灰度分桶应确定")
		}
	}
	if _, err := s.SetReleaseStatus(ctx, r.ID, "pause"); err != nil {
		t.Fatal(err)
	}
	paused, _ := s.store.ReleaseByID(ctx, r.ID)
	if paused.Status != "paused" {
		t.Fatalf("应为 paused: %s", paused.Status)
	}
	if _, err := s.SetReleaseStatus(ctx, r.ID, "pause"); !errors.Is(err, ErrValidation) {
		t.Fatalf("重复暂停应拒绝: %v", err)
	}
	if _, err := s.SetReleaseStatus(ctx, r.ID, "resume"); err != nil {
		t.Fatal(err)
	}
	if _, err := s.SetReleaseStatus(ctx, r.ID, "rollback"); err != nil {
		t.Fatal(err)
	}
	done, _ := s.store.ReleaseByID(ctx, r.ID)
	if done.Status != "rolled_back" {
		t.Fatalf("应为 rolled_back: %s", done.Status)
	}
	if _, err := s.SetReleaseStatus(ctx, "missing", "pause"); !errors.Is(err, ErrNotFound) {
		t.Fatalf("不存在应 ErrNotFound: %v", err)
	}
}

func TestReleaseAllStrategy(t *testing.T) {
	ctx := context.Background()
	s := newSvc()
	r, err := s.CreateRelease(ctx, Release{PackName: "core", PackVersion: "1.0.0", Strategy: "all"})
	if err != nil {
		t.Fatal(err)
	}
	if r.RolloutPercent != 100 || !Delivers(r, "anyone") {
		t.Fatal("all 策略应全量命中")
	}
	if _, err := s.CreateRelease(ctx, Release{PackName: "core", PackVersion: "1", Strategy: "accounts"}); !errors.Is(err, ErrValidation) {
		t.Fatalf("accounts 策略缺少名单应校验失败: %v", err)
	}
}

func TestConfigVersioningAndConflict(t *testing.T) {
	ctx := context.Background()
	s := newSvc()
	v1, err := s.SaveConfig(ctx, map[string]any{"economy.rate": 0.03}, "admin", 0)
	if err != nil {
		t.Fatal(err)
	}
	if v1.Version != 1 || v1.Revision != 1 {
		t.Fatalf("首个版本应为 1/1: %+v", v1)
	}
	v2, err := s.SaveConfig(ctx, map[string]any{"economy.rate": 0.04}, "admin", v1.Revision)
	if err != nil {
		t.Fatal(err)
	}
	if v2.Version != 2 {
		t.Fatalf("版本号应递增: %+v", v2)
	}
	if _, err := s.SaveConfig(ctx, map[string]any{"x": 1}, "admin", v1.Revision); !errors.Is(err, ErrConflict) {
		t.Fatalf("过期 revision 应 409 冲突: %v", err)
	}
	if _, err := s.SaveConfig(ctx, map[string]any{"x": 1}, "admin", 99); !errors.Is(err, ErrConflict) {
		t.Fatalf("revision 不匹配应冲突: %v", err)
	}
	v3, err := s.RollbackConfig(ctx, v1.Version, "admin")
	if err != nil {
		t.Fatal(err)
	}
	if v3.Version != 3 || v3.Values["economy.rate"] != 0.03 {
		t.Fatalf("回滚应生成新版本且恢复旧值: %+v", v3)
	}
	versions, _ := s.ConfigVersions(ctx)
	if len(versions) != 3 || versions[0].Version != 3 {
		t.Fatalf("历史应为倒序 3 条: %+v", versions)
	}
	if _, err := s.RollbackConfig(ctx, 99, "admin"); !errors.Is(err, ErrNotFound) {
		t.Fatalf("回滚不存在版本应 ErrNotFound: %v", err)
	}
}

func TestAnnouncementCRUD(t *testing.T) {
	ctx := context.Background()
	s := newSvc()
	a, err := s.CreateAnnouncement(ctx, Announcement{Title: "维护", Body: "今晚维护"})
	if err != nil {
		t.Fatal(err)
	}
	if a.Status != "draft" || a.Audience != "all" {
		t.Fatalf("默认草稿/全部人群: %+v", a)
	}
	a.Status = "published"
	updated, err := s.UpdateAnnouncement(ctx, a)
	if err != nil {
		t.Fatal(err)
	}
	if updated.Status != "published" {
		t.Fatal("状态未更新")
	}
	if err := s.DeleteAnnouncement(ctx, a.ID); err != nil {
		t.Fatal(err)
	}
	if err := s.DeleteAnnouncement(ctx, a.ID); !errors.Is(err, ErrNotFound) {
		t.Fatalf("重复删除应 ErrNotFound: %v", err)
	}
	list, _ := s.Announcements(ctx)
	if len(list) != 0 {
		t.Fatalf("删除后应为空: %+v", list)
	}
	if _, err := s.CreateAnnouncement(ctx, Announcement{}); !errors.Is(err, ErrValidation) {
		t.Fatalf("缺标题应校验失败: %v", err)
	}
}
