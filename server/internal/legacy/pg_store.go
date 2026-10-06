package legacy

import (
	"context"

	"github.com/jackc/pgx/v5/pgxpool"
)

// PGStore 是 PostgreSQL 版 Store 实现。
type PGStore struct {
	pool *pgxpool.Pool
}

var _ Store = (*PGStore)(nil)

// NewPGStore 构造 PostgreSQL 传承存储。
func NewPGStore(pool *pgxpool.Pool) *PGStore {
	return &PGStore{pool: pool}
}

func (s *PGStore) Get(ctx context.Context, accountID string) (Record, bool) {
	var rec Record
	err := s.pool.QueryRow(ctx,
		`SELECT doc, version, updated_at FROM legacy_docs WHERE account_id=$1`, accountID).
		Scan(&rec.Doc, &rec.Version, &rec.UpdatedAt)
	if err != nil {
		return Record{}, false
	}
	return rec, true
}

func (s *PGStore) Put(ctx context.Context, accountID string, rec Record) error {
	_, err := s.pool.Exec(ctx,
		`INSERT INTO legacy_docs (account_id, doc, version, updated_at) VALUES ($1,$2,$3,$4)
		 ON CONFLICT (account_id) DO UPDATE SET doc=EXCLUDED.doc, version=EXCLUDED.version, updated_at=EXCLUDED.updated_at`,
		accountID, rec.Doc, rec.Version, rec.UpdatedAt)
	return err
}
