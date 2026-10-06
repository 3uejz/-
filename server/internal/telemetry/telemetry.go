package telemetry

import (
	"context"
	"encoding/json"
	"sync"
	"time"
)

// Event 是遥测事件的存储形态（原样保留 JSON 字段）。
type Event struct {
	EventID    string
	EventType  string
	OccurredAt time.Time
	AccountID  string
	Raw        json.RawMessage
}

// Store 抽象遥测持久化；内存实现用于测试。
type Store interface {
	// Append 写入事件，event_id 已存在时返回 false 且不重复写。
	Append(ctx context.Context, e Event) (bool, error)
	// Purge 删除 occurred_at 早于 before 的事件，返回删除条数。
	Purge(ctx context.Context, before time.Time) int
	// ByAccount 返回账号的事件（用于导出）。
	ByAccount(ctx context.Context, accountID string) []Event
	// List 返回最近事件（eventType 为空时不过滤），按发生时间倒序，最多 limit 条。
	List(ctx context.Context, eventType string, limit int) []Event
	// DeleteAccount 删除账号的全部事件，返回条数。
	DeleteAccount(ctx context.Context, accountID string) int
}

// Service 编排遥测逻辑。
type Service struct {
	store     Store
	retention time.Duration
	now       func() time.Time
}

// NewService 构造遥测服务；retentionDays<=0 时默认 90 天。
func NewService(store Store, retentionDays int) *Service {
	if retentionDays <= 0 {
		retentionDays = 90
	}
	return &Service{
		store:     store,
		retention: time.Duration(retentionDays) * 24 * time.Hour,
		now:       time.Now,
	}
}

// Reject 描述被拒绝的事件。
type Reject struct {
	EventID string `json:"event_id"`
	Code    string `json:"code"`
}

// Ingest 批量接收事件并逐条判定（去重、必填、类型）。
func (s *Service) Ingest(ctx context.Context, raws []json.RawMessage) ([]string, []Reject) {
	accepted := make([]string, 0, len(raws))
	rejected := make([]Reject, 0)
	for _, raw := range raws {
		ev, err := parse(raw)
		if err != nil {
			id := ""
			var probe struct {
				EventID string `json:"event_id"`
			}
			_ = json.Unmarshal(raw, &probe)
			id = probe.EventID
			rejected = append(rejected, Reject{EventID: id, Code: "VALIDATION_FAILED"})
			continue
		}
		ok, err := s.store.Append(ctx, ev)
		if err != nil {
			rejected = append(rejected, Reject{EventID: ev.EventID, Code: "INTERNAL"})
			continue
		}
		if !ok {
			rejected = append(rejected, Reject{EventID: ev.EventID, Code: "CONFLICT"})
			continue
		}
		accepted = append(accepted, ev.EventID)
	}
	s.store.Purge(ctx, s.now().Add(-s.retention))
	return accepted, rejected
}

// Export 导出账号事件（匿名视图：不含 account_id 字段）。
func (s *Service) Export(ctx context.Context, accountID string) []json.RawMessage {
	events := s.store.ByAccount(ctx, accountID)
	out := make([]json.RawMessage, 0, len(events))
	for _, e := range events {
		out = append(out, anonymize(e.Raw))
	}
	return out
}

// Delete 删除账号遥测（R37.13 数据删除权）。
func (s *Service) Delete(ctx context.Context, accountID string) int {
	return s.store.DeleteAccount(ctx, accountID)
}

// List 返回最近事件（admin）。
func (s *Service) List(ctx context.Context, eventType string, limit int) []Event {
	if limit <= 0 {
		limit = 100
	}
	return s.store.List(ctx, eventType, limit)
}

// PurgeBefore 删除 before 之前的事件（admin），返回条数。
func (s *Service) PurgeBefore(ctx context.Context, before time.Time) int {
	return s.store.Purge(ctx, before)
}

// Retention 返回明细保留时长。
func (s *Service) Retention() time.Duration {
	return s.retention
}

// AggregateByType 按事件类型聚合计费，用于人生统计看板（R39.3）。
func (s *Service) AggregateByType(events []Event) map[string]int {
	out := map[string]int{}
	for _, e := range events {
		out[e.EventType]++
	}
	return out
}

func parse(raw json.RawMessage) (Event, error) {
	var probe struct {
		EventID       string          `json:"event_id"`
		EventType     string          `json:"event_type"`
		OccurredAt    string          `json:"occurred_at"`
		SchemaVersion int             `json:"schema_version"`
		AccountID     string          `json:"account_id"`
		Payload       json.RawMessage `json:"payload"`
	}
	if err := json.Unmarshal(raw, &probe); err != nil {
		return Event{}, err
	}
	if probe.EventID == "" || probe.EventType == "" || probe.OccurredAt == "" || probe.SchemaVersion < 1 {
		return Event{}, errValidation
	}
	ts, err := time.Parse(time.RFC3339, probe.OccurredAt)
	if err != nil {
		return Event{}, errValidation
	}
	return Event{
		EventID:    probe.EventID,
		EventType:  probe.EventType,
		OccurredAt: ts.UTC(),
		AccountID:  probe.AccountID,
		Raw:        raw,
	}, nil
}

// anonymize 去掉可识别个人字段（account_id/playthrough_id/session_id）。
func anonymize(raw json.RawMessage) json.RawMessage {
	var m map[string]any
	if err := json.Unmarshal(raw, &m); err != nil {
		return raw
	}
	delete(m, "account_id")
	delete(m, "playthrough_id")
	delete(m, "session_id")
	out, err := json.Marshal(m)
	if err != nil {
		return raw
	}
	return out
}

var errValidation = &validationError{}

type validationError struct{}

func (*validationError) Error() string { return "telemetry validation failed" }

// MemoryStore 是进程内 Store 实现。
type MemoryStore struct {
	mu    sync.Mutex
	seen  map[string]bool
	order []Event
}

// NewMemoryStore 创建内存遥测存储。
func NewMemoryStore() *MemoryStore {
	return &MemoryStore{seen: map[string]bool{}}
}

func (m *MemoryStore) Append(_ context.Context, e Event) (bool, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.seen[e.EventID] {
		return false, nil
	}
	m.seen[e.EventID] = true
	m.order = append(m.order, e)
	return true, nil
}

func (m *MemoryStore) Purge(_ context.Context, before time.Time) int {
	m.mu.Lock()
	defer m.mu.Unlock()
	kept := m.order[:0]
	removed := 0
	for _, e := range m.order {
		if e.OccurredAt.Before(before) {
			delete(m.seen, e.EventID)
			removed++
			continue
		}
		kept = append(kept, e)
	}
	m.order = kept
	return removed
}

func (m *MemoryStore) ByAccount(_ context.Context, accountID string) []Event {
	m.mu.Lock()
	defer m.mu.Unlock()
	var out []Event
	for _, e := range m.order {
		if e.AccountID == accountID {
			out = append(out, e)
		}
	}
	return out
}

func (m *MemoryStore) List(_ context.Context, eventType string, limit int) []Event {
	m.mu.Lock()
	defer m.mu.Unlock()
	if limit <= 0 {
		limit = 100
	}
	out := make([]Event, 0, limit)
	for i := len(m.order) - 1; i >= 0 && len(out) < limit; i-- {
		e := m.order[i]
		if eventType != "" && e.EventType != eventType {
			continue
		}
		out = append(out, e)
	}
	return out
}

func (m *MemoryStore) DeleteAccount(_ context.Context, accountID string) int {
	m.mu.Lock()
	defer m.mu.Unlock()
	kept := m.order[:0]
	removed := 0
	for _, e := range m.order {
		if e.AccountID == accountID {
			delete(m.seen, e.EventID)
			removed++
			continue
		}
		kept = append(kept, e)
	}
	m.order = kept
	return removed
}

// All 返回全部事件（测试与聚合用）。
func (m *MemoryStore) All() []Event {
	m.mu.Lock()
	defer m.mu.Unlock()
	return append([]Event(nil), m.order...)
}
