// Package admin 提供管理后台领域逻辑：审计日志、内容灰度发布、远程配置版本与公告。
//
// 管理端为 React + Ant Design；接口与数据模型见 shared/openapi/openapi.yaml
// 与 .monkeycode/specs/life-text-sandbox/admin.md。
package admin

import (
	"context"
	"errors"
	"hash/crc32"
	"sort"
	"time"

	"lifetextsandbox/server/internal/id"
)

var (
	// ErrNotFound 目标不存在。
	ErrNotFound = errors.New("admin resource not found")
	// ErrConflict 乐观锁冲突（配置 revision 过期）。
	ErrConflict = errors.New("admin version conflict")
	// ErrValidation 参数非法。
	ErrValidation = errors.New("admin validation failed")
)

// AuditEntry 对应 admin.md 6.1 admin_audit_logs。
type AuditEntry struct {
	ID             string         `json:"id"`
	ActorAccountID string         `json:"actor_account_id"`
	Action         string         `json:"action"`
	TargetType     string         `json:"target_type"`
	TargetID       string         `json:"target_id"`
	Before         map[string]any `json:"before,omitempty"`
	After          map[string]any `json:"after,omitempty"`
	Result         string         `json:"result"`
	IP             string         `json:"ip,omitempty"`
	UserAgent      string         `json:"user_agent,omitempty"`
	CreatedAt      time.Time      `json:"created_at"`
}

// Release 对应 admin.md 6.2 content_releases。
type Release struct {
	ID              string    `json:"id"`
	PackName        string    `json:"pack_name"`
	PackVersion     string    `json:"pack_version"`
	Strategy        string    `json:"strategy"`
	RolloutPercent  int       `json:"rollout_percent"`
	AccountList     []string  `json:"account_list,omitempty"`
	Status          string    `json:"status"`
	ManifestVersion int       `json:"manifest_version"`
	CreatedAt       time.Time `json:"created_at"`
	UpdatedAt       time.Time `json:"updated_at"`
}

// ConfigVersion 对应 admin.md 6.4 config_versions。
type ConfigVersion struct {
	ID        string         `json:"id"`
	Version   int            `json:"version"`
	Values    map[string]any `json:"values"`
	Revision  int            `json:"revision"`
	CreatedBy string         `json:"created_by"`
	CreatedAt time.Time      `json:"created_at"`
}

// Announcement 对应 admin.md 6.3 announcements。
type Announcement struct {
	ID          string     `json:"id"`
	Title       string     `json:"title"`
	Body        string     `json:"body"`
	Audience    string     `json:"audience"`
	AccountList []string   `json:"account_list,omitempty"`
	StartAt     *time.Time `json:"start_at,omitempty"`
	EndAt       *time.Time `json:"end_at,omitempty"`
	Status      string     `json:"status"`
	CreatedAt   time.Time  `json:"created_at"`
	UpdatedAt   time.Time  `json:"updated_at"`
}

// Store 抽象后台领域持久化。
type Store interface {
	AppendAudit(ctx context.Context, e AuditEntry) error
	Audits(ctx context.Context, action, actor, target string, limit int) ([]AuditEntry, error)

	CreateRelease(ctx context.Context, r Release) error
	UpdateRelease(ctx context.Context, r Release) error
	ReleaseByID(ctx context.Context, id string) (Release, bool)
	Releases(ctx context.Context) ([]Release, error)

	SaveConfig(ctx context.Context, v ConfigVersion) error
	CurrentConfig(ctx context.Context) (ConfigVersion, bool)
	ConfigVersions(ctx context.Context) ([]ConfigVersion, error)
	ConfigByVersion(ctx context.Context, version int) (ConfigVersion, bool)

	CreateAnnouncement(ctx context.Context, a Announcement) error
	UpdateAnnouncement(ctx context.Context, a Announcement) error
	DeleteAnnouncement(ctx context.Context, id string) error
	AnnouncementByID(ctx context.Context, id string) (Announcement, bool)
	Announcements(ctx context.Context) ([]Announcement, error)
}

// Service 编排后台领域逻辑。
type Service struct {
	store Store
	now   func() time.Time
}

// NewService 构造后台服务。
func NewService(store Store) *Service {
	return &Service{store: store, now: time.Now}
}

// ---- 审计 ----

// Audit 追加一条审计记录。
func (s *Service) Audit(ctx context.Context, e AuditEntry) error {
	if e.ActorAccountID == "" || e.Action == "" {
		return ErrValidation
	}
	if e.ID == "" {
		e.ID = id.NewUUIDv7()
	}
	if e.Result == "" {
		e.Result = "ok"
	}
	if e.CreatedAt.IsZero() {
		e.CreatedAt = s.now().UTC()
	}
	if e.Before == nil {
		e.Before = map[string]any{}
	}
	if e.After == nil {
		e.After = map[string]any{}
	}
	return s.store.AppendAudit(ctx, e)
}

// Audits 返回审计列表（按时间倒序，最多 limit 条）。
func (s *Service) Audits(ctx context.Context, action, actor, target string, limit int) ([]AuditEntry, error) {
	if limit <= 0 {
		limit = 50
	}
	return s.store.Audits(ctx, action, actor, target, limit)
}

// ---- 内容灰度发布 ----

// CreateRelease 创建发布批次并置为 rolling。
func (s *Service) CreateRelease(ctx context.Context, r Release) (Release, error) {
	if r.PackName == "" || r.PackVersion == "" {
		return Release{}, ErrValidation
	}
	if r.Strategy == "" {
		r.Strategy = "all"
	}
	switch r.Strategy {
	case "all":
		r.RolloutPercent = 100
	case "percent":
		if r.RolloutPercent < 0 || r.RolloutPercent > 100 {
			return Release{}, ErrValidation
		}
	case "accounts":
		if len(r.AccountList) == 0 {
			return Release{}, ErrValidation
		}
	default:
		return Release{}, ErrValidation
	}
	r.ID = id.NewUUIDv7()
	r.Status = "rolling"
	r.CreatedAt = s.now().UTC()
	r.UpdatedAt = r.CreatedAt
	if err := s.store.CreateRelease(ctx, r); err != nil {
		return Release{}, err
	}
	return r, nil
}

// Releases 返回全部发布批次。
func (s *Service) Releases(ctx context.Context) ([]Release, error) {
	return s.store.Releases(ctx)
}

// SetReleaseStatus 驱动发布状态机：rolling/paused/completed/rolled_back。
func (s *Service) SetReleaseStatus(ctx context.Context, releaseID, action string) (Release, error) {
	r, ok := s.store.ReleaseByID(ctx, releaseID)
	if !ok {
		return Release{}, ErrNotFound
	}
	switch action {
	case "pause":
		if r.Status != "rolling" {
			return Release{}, ErrValidation
		}
		r.Status = "paused"
	case "resume":
		if r.Status != "paused" {
			return Release{}, ErrValidation
		}
		r.Status = "rolling"
	case "complete":
		if r.Status != "rolling" && r.Status != "paused" {
			return Release{}, ErrValidation
		}
		r.Status = "completed"
	case "rollback":
		if r.Status == "rolled_back" {
			return Release{}, ErrValidation
		}
		r.Status = "rolled_back"
	default:
		return Release{}, ErrValidation
	}
	r.UpdatedAt = s.now().UTC()
	if err := s.store.UpdateRelease(ctx, r); err != nil {
		return Release{}, err
	}
	return r, nil
}

// Delivers 判定某账号是否命中该发布批次（灰度确定性分桶）。
func Delivers(r Release, accountID string) bool {
	switch r.Strategy {
	case "all":
		return true
	case "accounts":
		for _, a := range r.AccountList {
			if a == accountID {
				return true
			}
		}
		return false
	case "percent":
		return int(crc32.ChecksumIEEE([]byte(accountID))%100) < r.RolloutPercent
	default:
		return false
	}
}

// ---- 远程配置 ----

// SaveConfig 发布新配置版本；expectedRevision 用于乐观锁（0 表示首次创建）。
func (s *Service) SaveConfig(ctx context.Context, values map[string]any, actor string, expectedRevision int) (ConfigVersion, error) {
	if values == nil {
		return ConfigVersion{}, ErrValidation
	}
	current, ok := s.store.CurrentConfig(ctx)
	nextVersion := 1
	nextRevision := 1
	if ok {
		if expectedRevision != current.Revision {
			return ConfigVersion{}, ErrConflict
		}
		nextVersion = current.Version + 1
		nextRevision = current.Revision + 1
	} else if expectedRevision != 0 {
		return ConfigVersion{}, ErrConflict
	}
	v := ConfigVersion{
		ID:        id.NewUUIDv7(),
		Version:   nextVersion,
		Values:    values,
		Revision:  nextRevision,
		CreatedBy: actor,
		CreatedAt: s.now().UTC(),
	}
	if err := s.store.SaveConfig(ctx, v); err != nil {
		return ConfigVersion{}, err
	}
	return v, nil
}

// CurrentConfig 返回当前配置版本。
func (s *Service) CurrentConfig(ctx context.Context) (ConfigVersion, bool) {
	return s.store.CurrentConfig(ctx)
}

// ConfigVersions 返回配置历史（倒序）。
func (s *Service) ConfigVersions(ctx context.Context) ([]ConfigVersion, error) {
	return s.store.ConfigVersions(ctx)
}

// RollbackConfig 以历史版本内容创建新的当前版本（版本号单调递增）。
func (s *Service) RollbackConfig(ctx context.Context, version int, actor string) (ConfigVersion, error) {
	target, ok := s.store.ConfigByVersion(ctx, version)
	if !ok {
		return ConfigVersion{}, ErrNotFound
	}
	current, ok := s.store.CurrentConfig(ctx)
	if !ok {
		return ConfigVersion{}, ErrNotFound
	}
	v := ConfigVersion{
		ID:        id.NewUUIDv7(),
		Version:   current.Version + 1,
		Values:    target.Values,
		Revision:  current.Revision + 1,
		CreatedBy: actor,
		CreatedAt: s.now().UTC(),
	}
	if err := s.store.SaveConfig(ctx, v); err != nil {
		return ConfigVersion{}, err
	}
	return v, nil
}

// ---- 公告 ----

// CreateAnnouncement 新建公告（默认草稿）。
func (s *Service) CreateAnnouncement(ctx context.Context, a Announcement) (Announcement, error) {
	if a.Title == "" {
		return Announcement{}, ErrValidation
	}
	if a.Audience == "" {
		a.Audience = "all"
	}
	if a.Status == "" {
		a.Status = "draft"
	}
	a.ID = id.NewUUIDv7()
	a.CreatedAt = s.now().UTC()
	a.UpdatedAt = a.CreatedAt
	if err := s.store.CreateAnnouncement(ctx, a); err != nil {
		return Announcement{}, err
	}
	return a, nil
}

// UpdateAnnouncement 更新公告。
func (s *Service) UpdateAnnouncement(ctx context.Context, a Announcement) (Announcement, error) {
	existing, ok := s.store.AnnouncementByID(ctx, a.ID)
	if !ok {
		return Announcement{}, ErrNotFound
	}
	if a.Title != "" {
		existing.Title = a.Title
	}
	if a.Body != "" {
		existing.Body = a.Body
	}
	if a.Audience != "" {
		existing.Audience = a.Audience
	}
	if a.AccountList != nil {
		existing.AccountList = a.AccountList
	}
	if a.StartAt != nil {
		existing.StartAt = a.StartAt
	}
	if a.EndAt != nil {
		existing.EndAt = a.EndAt
	}
	if a.Status != "" {
		existing.Status = a.Status
	}
	existing.UpdatedAt = s.now().UTC()
	if err := s.store.UpdateAnnouncement(ctx, existing); err != nil {
		return Announcement{}, err
	}
	return existing, nil
}

// DeleteAnnouncement 删除公告。
func (s *Service) DeleteAnnouncement(ctx context.Context, announcementID string) error {
	if _, ok := s.store.AnnouncementByID(ctx, announcementID); !ok {
		return ErrNotFound
	}
	return s.store.DeleteAnnouncement(ctx, announcementID)
}

// Announcements 返回公告列表（按创建时间倒序）。
func (s *Service) Announcements(ctx context.Context) ([]Announcement, error) {
	return s.store.Announcements(ctx)
}

// sortByCreatedDesc 供内存实现复用。
func sortByCreatedDesc[T any](items []T, at func(T) time.Time) {
	sort.Slice(items, func(i, j int) bool { return at(items[i]).After(at(items[j])) })
}
