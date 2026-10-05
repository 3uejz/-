package saves

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"sort"
	"sync"
	"time"

	"lifetextsandbox/server/internal/id"
)

var (
	// ErrValidation 表示存档文档不符合最小结构。
	ErrValidation = errors.New("save validation failed")
	// ErrConflict 表示乐观锁冲突（SAVE_CONFLICT）。
	ErrConflict = errors.New("save conflict")
	// ErrNotFound 表示槽或版本不存在。
	ErrNotFound = errors.New("save not found")
)

// Slot 对应 openapi 的 SaveSlot。
type Slot struct {
	Slot          int       `json:"slot"`
	Version       int       `json:"version"`
	Hash          string    `json:"hash"`
	PlaythroughID string    `json:"playthrough_id,omitempty"`
	UpdatedAt     time.Time `json:"updated_at"`
}

// Version 对应 openapi 的 SaveVersion。
type Version struct {
	Version   int       `json:"version"`
	Hash      string    `json:"hash"`
	CreatedAt time.Time `json:"created_at"`
}

// Record 是槽内某版本的完整数据（doc 为加密后或明文 JSON 字节）。
type Record struct {
	Slot          int
	Version       int
	Hash          string
	PlaythroughID string
	CreatedAt     time.Time
	Doc           []byte
	IdemKey       string
}

// Store 抽象存档持久化；内存实现用于测试，PG/MinIO 实现后续接入。
type Store interface {
	Latest(ctx context.Context, accountID string, slot int) (Record, bool)
	Version(ctx context.Context, accountID string, slot, version int) (Record, bool)
	Versions(ctx context.Context, accountID string, slot int) ([]Version, error)
	Slots(ctx context.Context, accountID string) []int
	Append(ctx context.Context, accountID string, rec Record) error
}

// Service 编排存档逻辑。
type Service struct {
	store Store
	now   func() time.Time
}

// NewService 构造存档服务。
func NewService(store Store) *Service {
	return &Service{store: store, now: time.Now}
}

// List 返回账号下所有槽的最新摘要（游标分页，按 slot 升序）。
func (s *Service) List(ctx context.Context, accountID string, limit int, afterSlot int) ([]Slot, string) {
	slots := s.store.Slots(ctx, accountID)
	out := make([]Slot, 0, len(slots))
	for _, sl := range slots {
		if sl <= afterSlot {
			continue
		}
		rec, _ := s.store.Latest(ctx, accountID, sl)
		out = append(out, toSlot(rec))
		if limit > 0 && len(out) >= limit {
			break
		}
	}
	next := ""
	if limit > 0 && len(out) == limit && len(slots) > len(out) {
		next = fmt.Sprintf("%d", out[len(out)-1].Slot)
	}
	return out, next
}

// Get 返回指定槽最新版本。
func (s *Service) Get(ctx context.Context, accountID string, slot int) (Record, error) {
	rec, ok := s.store.Latest(ctx, accountID, slot)
	if !ok {
		return Record{}, ErrNotFound
	}
	return rec, nil
}

// GetVersion 返回指定版本。
func (s *Service) GetVersion(ctx context.Context, accountID string, slot, version int) (Record, error) {
	rec, ok := s.store.Version(ctx, accountID, slot, version)
	if !ok {
		return Record{}, ErrNotFound
	}
	return rec, nil
}

// Versions 返回历史版本列表（倒序）。
func (s *Service) Versions(ctx context.Context, accountID string, slot int) ([]Version, error) {
	return s.store.Versions(ctx, accountID, slot)
}

// Put 写入新版本：If-Match 命中当前 ETag 才允许覆盖；Idempotency-Key 重放返回原结果。
func (s *Service) Put(ctx context.Context, accountID string, slot int, doc []byte, idemKey, ifMatch string) (Record, bool, error) {
	if slot < 1 || slot > 99 {
		return Record{}, false, fmt.Errorf("%w: slot 越界", ErrValidation)
	}
	meta, err := ValidateSave(doc)
	if err != nil {
		return Record{}, false, err
	}
	current, hasCurrent := s.store.Latest(ctx, accountID, slot)
	if idemKey != "" && hasCurrent && current.IdemKey == idemKey {
		return current, false, nil
	}
	if ifMatch != "" {
		if !hasCurrent || ifMatch != ETag(current) {
			return Record{}, false, ErrConflict
		}
	}
	version := 1
	if hasCurrent {
		version = current.Version + 1
	}
	rec := Record{
		Slot:          slot,
		Version:       version,
		Hash:          HashBytes(doc),
		PlaythroughID: meta.PlaythroughID,
		CreatedAt:     s.now().UTC(),
		Doc:           doc,
		IdemKey:       idemKey,
	}
	if err := s.store.Append(ctx, accountID, rec); err != nil {
		return Record{}, false, err
	}
	return rec, !hasCurrent, nil
}

// Rollback 以历史版本内容创建新版本（版本号单调递增，历史可回溯）。
func (s *Service) Rollback(ctx context.Context, accountID string, slot, version int) (Record, error) {
	target, ok := s.store.Version(ctx, accountID, slot, version)
	if !ok {
		return Record{}, ErrNotFound
	}
	return s.putRecord(ctx, accountID, target)
}

func (s *Service) putRecord(ctx context.Context, accountID string, target Record) (Record, error) {
	current, ok := s.store.Latest(ctx, accountID, target.Slot)
	if !ok {
		return Record{}, ErrNotFound
	}
	rec := Record{
		Slot:          target.Slot,
		Version:       current.Version + 1,
		Hash:          target.Hash,
		PlaythroughID: target.PlaythroughID,
		CreatedAt:     s.now().UTC(),
		Doc:           target.Doc,
	}
	if err := s.store.Append(ctx, accountID, rec); err != nil {
		return Record{}, err
	}
	return rec, nil
}

// Resolve 处理本地/云端冲突。keep_cloud 返回云端现状；keep_local/merge 用本地上传内容覆盖。
func (s *Service) Resolve(ctx context.Context, accountID string, slot int, resolution string, cloudVersion int, localBlob []byte) (Record, error) {
	switch resolution {
	case "keep_cloud":
		return s.Get(ctx, accountID, slot)
	case "keep_local", "merge":
		if len(localBlob) == 0 {
			return Record{}, fmt.Errorf("%w: 缺少 local_blob", ErrValidation)
		}
		rec, _, err := s.Put(ctx, accountID, slot, localBlob, "", "")
		return rec, err
	default:
		return Record{}, fmt.Errorf("%w: 未知 resolution", ErrValidation)
	}
}

// SaveMeta 是存档最小结构元数据。
type SaveMeta struct {
	SchemaVersion int    `json:"schema_version"`
	GameVersion   string `json:"game_version"`
	PlaythroughID string `json:"playthrough_id"`
	Seed          int64  `json:"seed"`
}

type saveDoc struct {
	Meta *SaveMeta `json:"meta"`
}

// ValidateSave 做最小结构校验：meta 必填字段与 playthrough_id 格式。
func ValidateSave(doc []byte) (SaveMeta, error) {
	var d saveDoc
	if err := json.Unmarshal(doc, &d); err != nil {
		return SaveMeta{}, fmt.Errorf("%w: 非合法 JSON 对象", ErrValidation)
	}
	if d.Meta == nil {
		return SaveMeta{}, fmt.Errorf("%w: 缺少 meta", ErrValidation)
	}
	if d.Meta.SchemaVersion < 1 || d.Meta.GameVersion == "" || d.Meta.PlaythroughID == "" {
		return SaveMeta{}, fmt.Errorf("%w: meta 字段不完整", ErrValidation)
	}
	if !id.IsValid(d.Meta.PlaythroughID) {
		return SaveMeta{}, fmt.Errorf("%w: playthrough_id 非法", ErrValidation)
	}
	return *d.Meta, nil
}

// HashBytes 返回内容 sha256 的十六进制。
func HashBytes(doc []byte) string {
	sum := sha256.Sum256(doc)
	return hex.EncodeToString(sum[:])
}

// ETag 返回带引号的版本标签，用作 If-Match / ETag。
func ETag(rec Record) string {
	return fmt.Sprintf("\"v%d-%s\"", rec.Version, rec.Hash[:16])
}

func toSlot(rec Record) Slot {
	return Slot{
		Slot:          rec.Slot,
		Version:       rec.Version,
		Hash:          rec.Hash,
		PlaythroughID: rec.PlaythroughID,
		UpdatedAt:     rec.CreatedAt,
	}
}

// MemoryStore 是进程内 Store 实现。
type MemoryStore struct {
	mu      sync.Mutex
	records map[string][]Record // key: accountID
}

// NewMemoryStore 创建空的内存存档存储。
func NewMemoryStore() *MemoryStore {
	return &MemoryStore{records: map[string][]Record{}}
}

func (m *MemoryStore) Append(_ context.Context, accountID string, rec Record) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.records[accountID] = append(m.records[accountID], rec)
	return nil
}

func (m *MemoryStore) Latest(_ context.Context, accountID string, slot int) (Record, bool) {
	m.mu.Lock()
	defer m.mu.Unlock()
	list := m.records[accountID]
	for i := len(list) - 1; i >= 0; i-- {
		if list[i].Slot == slot {
			return list[i], true
		}
	}
	return Record{}, false
}

func (m *MemoryStore) Version(_ context.Context, accountID string, slot, version int) (Record, bool) {
	m.mu.Lock()
	defer m.mu.Unlock()
	for _, r := range m.records[accountID] {
		if r.Slot == slot && r.Version == version {
			return r, true
		}
	}
	return Record{}, false
}

func (m *MemoryStore) Versions(_ context.Context, accountID string, slot int) ([]Version, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	var out []Version
	for _, r := range m.records[accountID] {
		if r.Slot == slot {
			out = append(out, Version{Version: r.Version, Hash: r.Hash, CreatedAt: r.CreatedAt})
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Version > out[j].Version })
	return out, nil
}

func (m *MemoryStore) Slots(_ context.Context, accountID string) []int {
	m.mu.Lock()
	defer m.mu.Unlock()
	set := map[int]bool{}
	for _, r := range m.records[accountID] {
		set[r.Slot] = true
	}
	slots := make([]int, 0, len(set))
	for s := range set {
		slots = append(slots, s)
	}
	sort.Ints(slots)
	return slots
}
