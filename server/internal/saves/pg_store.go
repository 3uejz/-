package saves

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5/pgxpool"

	"lifetextsandbox/server/internal/blob"
)

// PGStore 是 PostgreSQL（元数据）+ 对象存储（文档体）版 Store 实现（R37.8）。
type PGStore struct {
	pool  *pgxpool.Pool
	blobs blob.Store
}

var _ Store = (*PGStore)(nil)

// NewPGStore 构造云存档存储。
func NewPGStore(pool *pgxpool.Pool, blobs blob.Store) *PGStore {
	return &PGStore{pool: pool, blobs: blobs}
}

func objectKey(accountID string, slot, version int) string {
	return fmt.Sprintf("saves/%s/%d/%d", accountID, slot, version)
}

func (s *PGStore) Append(ctx context.Context, accountID string, rec Record) error {
	key := objectKey(accountID, rec.Slot, rec.Version)
	if err := s.blobs.Put(ctx, key, rec.Doc); err != nil {
		return err
	}
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback(ctx) }()

	if _, err := tx.Exec(ctx,
		`INSERT INTO save_versions (account_id, slot, version, hash, playthrough_id, object_key, created_at)
		 VALUES ($1,$2,$3,$4,$5,$6,$7)`,
		accountID, rec.Slot, rec.Version, rec.Hash, rec.PlaythroughID, key, rec.CreatedAt); err != nil {
		_ = s.blobs.Delete(ctx, key)
		return err
	}
	if _, err := tx.Exec(ctx,
		`INSERT INTO save_slots (account_id, slot, latest_version, hash, playthrough_id, idem_key, updated_at)
		 VALUES ($1,$2,$3,$4,$5,$6,$7)
		 ON CONFLICT (account_id, slot) DO UPDATE SET
		   latest_version=EXCLUDED.latest_version, hash=EXCLUDED.hash,
		   playthrough_id=EXCLUDED.playthrough_id, idem_key=EXCLUDED.idem_key,
		   updated_at=EXCLUDED.updated_at
		 WHERE EXCLUDED.latest_version >= save_slots.latest_version`,
		accountID, rec.Slot, rec.Version, rec.Hash, rec.PlaythroughID, rec.IdemKey, rec.CreatedAt); err != nil {
		_ = s.blobs.Delete(ctx, key)
		return err
	}
	return tx.Commit(ctx)
}

func (s *PGStore) Latest(ctx context.Context, accountID string, slot int) (Record, bool) {
	var rec Record
	rec.Slot = slot
	err := s.pool.QueryRow(ctx,
		`SELECT latest_version, hash, playthrough_id, idem_key, updated_at
		 FROM save_slots WHERE account_id=$1 AND slot=$2`, accountID, slot).
		Scan(&rec.Version, &rec.Hash, &rec.PlaythroughID, &rec.IdemKey, &rec.CreatedAt)
	if err != nil {
		return Record{}, false
	}
	doc, err := s.blobs.Get(ctx, objectKey(accountID, slot, rec.Version))
	if err != nil {
		return Record{}, false
	}
	rec.Doc = doc
	return rec, true
}

func (s *PGStore) Version(ctx context.Context, accountID string, slot, version int) (Record, bool) {
	var rec Record
	rec.Slot, rec.Version = slot, version
	var key string
	err := s.pool.QueryRow(ctx,
		`SELECT hash, playthrough_id, object_key, created_at
		 FROM save_versions WHERE account_id=$1 AND slot=$2 AND version=$3`, accountID, slot, version).
		Scan(&rec.Hash, &rec.PlaythroughID, &key, &rec.CreatedAt)
	if err != nil {
		return Record{}, false
	}
	doc, err := s.blobs.Get(ctx, key)
	if err != nil {
		return Record{}, false
	}
	rec.Doc = doc
	return rec, true
}

func (s *PGStore) Versions(ctx context.Context, accountID string, slot int) ([]Version, error) {
	rows, err := s.pool.Query(ctx,
		`SELECT version, hash, created_at FROM save_versions
		 WHERE account_id=$1 AND slot=$2 ORDER BY version DESC`, accountID, slot)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []Version
	for rows.Next() {
		var v Version
		if err := rows.Scan(&v.Version, &v.Hash, &v.CreatedAt); err != nil {
			return out, err
		}
		out = append(out, v)
	}
	return out, rows.Err()
}

func (s *PGStore) Slots(ctx context.Context, accountID string) []int {
	rows, err := s.pool.Query(ctx,
		`SELECT slot FROM save_slots WHERE account_id=$1 ORDER BY slot`, accountID)
	if err != nil {
		return nil
	}
	defer rows.Close()
	var out []int
	for rows.Next() {
		var sl int
		if err := rows.Scan(&sl); err != nil {
			return out
		}
		out = append(out, sl)
	}
	return out
}

func (s *PGStore) AdminSlots(ctx context.Context, limit int) []ScopedSlot {
	if limit <= 0 {
		limit = 100
	}
	rows, err := s.pool.Query(ctx,
		`SELECT account_id, slot, latest_version, hash, playthrough_id, updated_at
		 FROM save_slots ORDER BY updated_at DESC LIMIT $1`, limit)
	if err != nil {
		return nil
	}
	defer rows.Close()
	var out []ScopedSlot
	for rows.Next() {
		var sc ScopedSlot
		if err := rows.Scan(&sc.AccountID, &sc.Slot, &sc.Version, &sc.Hash, &sc.PlaythroughID, &sc.UpdatedAt); err != nil {
			return out
		}
		out = append(out, sc)
	}
	return out
}

func (s *PGStore) AdminStats(ctx context.Context) (int, int, int64) {
	var slots, versions int
	_ = s.pool.QueryRow(ctx, `SELECT count(*) FROM save_slots`).Scan(&slots)
	_ = s.pool.QueryRow(ctx, `SELECT count(*) FROM save_versions`).Scan(&versions)
	// 文档体存放于对象存储，PG 不持有字节数；字节数由对象存储统计补充。
	return slots, versions, 0
}
