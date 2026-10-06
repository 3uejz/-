package telemetry

import (
	"context"
	"encoding/json"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

// PGStore 是 PostgreSQL 版 Store 实现。
type PGStore struct {
	pool *pgxpool.Pool
}

var _ Store = (*PGStore)(nil)

// NewPGStore 构造 PostgreSQL 遥测存储。
func NewPGStore(pool *pgxpool.Pool) *PGStore {
	return &PGStore{pool: pool}
}

func (s *PGStore) Append(ctx context.Context, e Event) (bool, error) {
	raw := e.Raw
	if len(raw) == 0 {
		raw = json.RawMessage(`{}`)
	}
	tag, err := s.pool.Exec(ctx,
		`INSERT INTO telemetry_events (event_id, account_id, event_type, occurred_at, payload)
		 VALUES ($1,$2,$3,$4,$5) ON CONFLICT (event_id) DO NOTHING`,
		e.EventID, e.AccountID, e.EventType, e.OccurredAt, raw)
	if err != nil {
		return false, err
	}
	return tag.RowsAffected() > 0, nil
}

func (s *PGStore) Purge(ctx context.Context, before time.Time) int {
	tag, err := s.pool.Exec(ctx, `DELETE FROM telemetry_events WHERE occurred_at < $1`, before)
	if err != nil {
		return 0
	}
	return int(tag.RowsAffected())
}

func (s *PGStore) ByAccount(ctx context.Context, accountID string) []Event {
	rows, err := s.pool.Query(ctx,
		`SELECT event_id, event_type, occurred_at, account_id, payload
		 FROM telemetry_events WHERE account_id=$1 ORDER BY occurred_at`, accountID)
	if err != nil {
		return nil
	}
	defer rows.Close()
	var out []Event
	for rows.Next() {
		var e Event
		var raw []byte
		if err := rows.Scan(&e.EventID, &e.EventType, &e.OccurredAt, &e.AccountID, &raw); err != nil {
			return out
		}
		e.Raw = json.RawMessage(raw)
		out = append(out, e)
	}
	return out
}

func (s *PGStore) DeleteAccount(ctx context.Context, accountID string) int {
	tag, err := s.pool.Exec(ctx, `DELETE FROM telemetry_events WHERE account_id=$1`, accountID)
	if err != nil {
		return 0
	}
	return int(tag.RowsAffected())
}
