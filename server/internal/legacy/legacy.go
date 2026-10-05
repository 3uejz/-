package legacy

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"sync"
	"time"
)

// ErrValidation 表示传承档案非法。
var ErrValidation = errors.New("legacy validation failed")

// ErrConflict 表示 If-Match 乐观锁冲突。
var ErrConflict = errors.New("legacy conflict")

// Record 是某账号的传承档案版本。
type Record struct {
	Doc       []byte
	Version   int
	UpdatedAt time.Time
}

// Store 抽象传承持久化；内存实现用于测试。
type Store interface {
	Get(ctx context.Context, accountID string) (Record, bool)
	Put(ctx context.Context, accountID string, rec Record) error
}

// Service 编排传承读写。
type Service struct {
	store Store
	now   func() time.Time
}

// NewService 构造传承服务。
func NewService(store Store) *Service {
	return &Service{store: store, now: time.Now}
}

// Get 返回档案内容、ETag 与是否存在。
func (s *Service) Get(ctx context.Context, accountID string) ([]byte, string, bool) {
	rec, ok := s.store.Get(ctx, accountID)
	if !ok {
		return nil, "", false
	}
	return rec.Doc, etag(rec), true
}

// Put 写入档案：ifMatch 非空时须匹配当前 ETag。
func (s *Service) Put(ctx context.Context, accountID string, doc []byte, ifMatch string) (string, error) {
	if !json.Valid(doc) {
		return "", ErrValidation
	}
	current, ok := s.store.Get(ctx, accountID)
	if ifMatch != "" {
		if !ok || ifMatch != etag(current) {
			return "", ErrConflict
		}
	}
	version := 1
	if ok {
		version = current.Version + 1
	}
	rec := Record{Doc: append([]byte(nil), doc...), Version: version, UpdatedAt: s.now().UTC()}
	if err := s.store.Put(ctx, accountID, rec); err != nil {
		return "", err
	}
	return etag(rec), nil
}

func etag(rec Record) string {
	sum := sha256.Sum256(rec.Doc)
	return fmt.Sprintf(`"v%d-%s"`, rec.Version, hex.EncodeToString(sum[:8]))
}

// MemoryStore 是进程内 Store 实现。
type MemoryStore struct {
	mu      sync.Mutex
	records map[string]Record
}

// NewMemoryStore 创建内存传承存储。
func NewMemoryStore() *MemoryStore {
	return &MemoryStore{records: map[string]Record{}}
}

func (m *MemoryStore) Get(_ context.Context, accountID string) (Record, bool) {
	m.mu.Lock()
	defer m.mu.Unlock()
	r, ok := m.records[accountID]
	return r, ok
}

func (m *MemoryStore) Put(_ context.Context, accountID string, rec Record) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.records[accountID] = rec
	return nil
}
