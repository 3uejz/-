package admin

import (
	"context"
	"sync"
	"time"
)

// MemoryStore 是进程内 Store 实现。
type MemoryStore struct {
	mu            sync.Mutex
	audits        []AuditEntry
	releases      map[string]Release
	configs       []ConfigVersion
	announcements map[string]Announcement
}

// NewMemoryStore 创建内存后台存储。
func NewMemoryStore() *MemoryStore {
	return &MemoryStore{
		releases:      map[string]Release{},
		announcements: map[string]Announcement{},
	}
}

func (m *MemoryStore) AppendAudit(_ context.Context, e AuditEntry) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.audits = append(m.audits, e)
	return nil
}

func (m *MemoryStore) Audits(_ context.Context, action, actor, target string, limit int) ([]AuditEntry, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	out := make([]AuditEntry, 0, len(m.audits))
	for i := len(m.audits) - 1; i >= 0; i-- {
		e := m.audits[i]
		if action != "" && e.Action != action {
			continue
		}
		if actor != "" && e.ActorAccountID != actor {
			continue
		}
		if target != "" && e.TargetID != target {
			continue
		}
		out = append(out, e)
		if len(out) >= limit {
			break
		}
	}
	return out, nil
}

func (m *MemoryStore) CreateRelease(_ context.Context, r Release) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.releases[r.ID] = r
	return nil
}

func (m *MemoryStore) UpdateRelease(_ context.Context, r Release) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.releases[r.ID] = r
	return nil
}

func (m *MemoryStore) ReleaseByID(_ context.Context, rid string) (Release, bool) {
	m.mu.Lock()
	defer m.mu.Unlock()
	r, ok := m.releases[rid]
	return r, ok
}

func (m *MemoryStore) Releases(_ context.Context) ([]Release, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	out := make([]Release, 0, len(m.releases))
	for _, r := range m.releases {
		out = append(out, r)
	}
	sortByCreatedDesc(out, func(r Release) time.Time { return r.CreatedAt })
	return out, nil
}

func (m *MemoryStore) SaveConfig(_ context.Context, v ConfigVersion) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.configs = append(m.configs, v)
	return nil
}

func (m *MemoryStore) CurrentConfig(_ context.Context) (ConfigVersion, bool) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if len(m.configs) == 0 {
		return ConfigVersion{}, false
	}
	return m.configs[len(m.configs)-1], true
}

func (m *MemoryStore) ConfigVersions(_ context.Context) ([]ConfigVersion, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	out := make([]ConfigVersion, 0, len(m.configs))
	for i := len(m.configs) - 1; i >= 0; i-- {
		out = append(out, m.configs[i])
	}
	return out, nil
}

func (m *MemoryStore) ConfigByVersion(_ context.Context, version int) (ConfigVersion, bool) {
	m.mu.Lock()
	defer m.mu.Unlock()
	for _, v := range m.configs {
		if v.Version == version {
			return v, true
		}
	}
	return ConfigVersion{}, false
}

func (m *MemoryStore) CreateAnnouncement(_ context.Context, a Announcement) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.announcements[a.ID] = a
	return nil
}

func (m *MemoryStore) UpdateAnnouncement(_ context.Context, a Announcement) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.announcements[a.ID] = a
	return nil
}

func (m *MemoryStore) DeleteAnnouncement(_ context.Context, aid string) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	delete(m.announcements, aid)
	return nil
}

func (m *MemoryStore) AnnouncementByID(_ context.Context, aid string) (Announcement, bool) {
	m.mu.Lock()
	defer m.mu.Unlock()
	a, ok := m.announcements[aid]
	return a, ok
}

func (m *MemoryStore) Announcements(_ context.Context) ([]Announcement, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	out := make([]Announcement, 0, len(m.announcements))
	for _, a := range m.announcements {
		out = append(out, a)
	}
	sortByCreatedDesc(out, func(a Announcement) time.Time { return a.CreatedAt })
	return out, nil
}
