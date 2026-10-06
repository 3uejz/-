package content

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"sort"
	"sync"
	"time"

	"lifetextsandbox/server/internal/id"
)

// ErrValidation 表示提交的内容/配置不合法。
var ErrValidation = errors.New("content validation failed")

// Announcement 对应 openapi 的 Announcement。
type Announcement struct {
	ID      string `json:"id"`
	Title   string `json:"title"`
	Body    string `json:"body"`
	StartAt string `json:"start_at,omitempty"`
	EndAt   string `json:"end_at,omitempty"`
}

// Service 管理内容清单、远程配置与公告（单实例，内存权威，后续可落 PG/MinIO）。
type Service struct {
	mu            sync.Mutex
	manifest      []byte
	manifestTag   string
	config        []byte
	configTag     string
	announcements []Announcement
	now           func() time.Time
}

// NewService 创建内容服务，带默认空清单与空配置。
func NewService() *Service {
	manifest := []byte(`{"packs":[]}`)
	cfg := []byte(`{}`)
	return &Service{
		manifest:    manifest,
		manifestTag: etag(manifest),
		config:      cfg,
		configTag:   etag(cfg),
		now:         time.Now,
	}
}

// Manifest 返回当前内容清单与 ETag。
func (s *Service) Manifest() ([]byte, string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.manifest, s.manifestTag
}

// PublishManifest 发布新内容清单（admin），返回 ETag。
func (s *Service) PublishManifest(doc []byte) (string, error) {
	if !json.Valid(doc) {
		return "", ErrValidation
	}
	var probe struct {
		Packs []json.RawMessage `json:"packs"`
	}
	if err := json.Unmarshal(doc, &probe); err != nil {
		return "", ErrValidation
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	s.manifest = append([]byte(nil), doc...)
	s.manifestTag = etag(doc)
	return s.manifestTag, nil
}

// Config 返回远程配置与 ETag。
func (s *Service) Config() ([]byte, string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.config, s.configTag
}

// PutConfig 更新远程配置（admin），返回 ETag。
func (s *Service) PutConfig(doc []byte) (string, error) {
	if !json.Valid(doc) {
		return "", ErrValidation
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	s.config = append([]byte(nil), doc...)
	s.configTag = etag(doc)
	return s.configTag, nil
}

// Announcements 返回当前生效的公告（按开始时间升序）。
func (s *Service) Announcements() []Announcement {
	s.mu.Lock()
	defer s.mu.Unlock()
	now := s.now().UTC()
	out := make([]Announcement, 0, len(s.announcements))
	for _, a := range s.announcements {
		if a.StartAt != "" {
			if t, err := time.Parse(time.RFC3339, a.StartAt); err == nil && now.Before(t) {
				continue
			}
		}
		if a.EndAt != "" {
			if t, err := time.Parse(time.RFC3339, a.EndAt); err == nil && now.After(t) {
				continue
			}
		}
		out = append(out, a)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].StartAt < out[j].StartAt })
	return out
}

// AddAnnouncement 新增公告；ID 为空时自动生成 UUIDv7。
func (s *Service) AddAnnouncement(a Announcement) Announcement {
	if a.ID == "" {
		a.ID = id.NewUUIDv7()
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	s.announcements = append(s.announcements, a)
	return a
}

// ReplaceAnnouncements 用给定列表替换当前公告（admin 发布/下线时同步面向玩家的视图）。
func (s *Service) ReplaceAnnouncements(list []Announcement) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.announcements = append([]Announcement(nil), list...)
}

func etag(doc []byte) string {
	sum := sha256.Sum256(doc)
	return `"` + hex.EncodeToString(sum[:8]) + `"`
}
