package auth

import (
	"context"
	"errors"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

// PGStore 是 PostgreSQL 版 Store 实现。
type PGStore struct {
	pool *pgxpool.Pool
}

var _ Store = (*PGStore)(nil)

// NewPGStore 构造 PostgreSQL 账号存储。
func NewPGStore(pool *pgxpool.Pool) *PGStore {
	return &PGStore{pool: pool}
}

func (s *PGStore) CreateAccount(ctx context.Context, a Account) error {
	_, err := s.pool.Exec(ctx,
		`INSERT INTO accounts (id, username, password_hash, role, disabled, created_at) VALUES ($1,$2,$3,$4,$5,$6)`,
		a.ID, a.Username, a.PasswordHash, a.Role, a.Disabled, a.CreatedAt)
	if isUniqueViolation(err) {
		return ErrUsernameTaken
	}
	return err
}

func (s *PGStore) AccountByUsername(ctx context.Context, username string) (Account, bool) {
	return s.scanAccount(ctx, `SELECT id, username, password_hash, role, disabled, created_at FROM accounts WHERE username=$1`, username)
}

func (s *PGStore) AccountByID(ctx context.Context, accountID string) (Account, bool) {
	return s.scanAccount(ctx, `SELECT id, username, password_hash, role, disabled, created_at FROM accounts WHERE id=$1`, accountID)
}

func (s *PGStore) scanAccount(ctx context.Context, query string, arg any) (Account, bool) {
	var a Account
	err := s.pool.QueryRow(ctx, query, arg).Scan(&a.ID, &a.Username, &a.PasswordHash, &a.Role, &a.Disabled, &a.CreatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return Account{}, false
	}
	if err != nil {
		return Account{}, false
	}
	return a, true
}

func (s *PGStore) SetDisabled(ctx context.Context, accountID string, disabled bool) error {
	tag, err := s.pool.Exec(ctx, `UPDATE accounts SET disabled=$2 WHERE id=$1`, accountID, disabled)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrInvalidToken
	}
	return nil
}

func (s *PGStore) SaveRefresh(ctx context.Context, r RefreshRecord) error {
	_, err := s.pool.Exec(ctx,
		`INSERT INTO refresh_tokens (token_hash, account_id, device_id, expires_at, created_at)
		 VALUES ($1,$2,$3,$4,$5)
		 ON CONFLICT (token_hash) DO UPDATE SET expires_at=EXCLUDED.expires_at`,
		r.Hash, r.AccountID, r.DeviceID, r.ExpiresAt, r.CreatedAt)
	return err
}

func (s *PGStore) RefreshByHash(ctx context.Context, hash string) (RefreshRecord, bool) {
	var r RefreshRecord
	err := s.pool.QueryRow(ctx,
		`SELECT token_hash, account_id, device_id, expires_at, created_at FROM refresh_tokens WHERE token_hash=$1`, hash).
		Scan(&r.Hash, &r.AccountID, &r.DeviceID, &r.ExpiresAt, &r.CreatedAt)
	if err != nil {
		return RefreshRecord{}, false
	}
	return r, true
}

func (s *PGStore) DeleteRefresh(ctx context.Context, hash string) error {
	_, err := s.pool.Exec(ctx, `DELETE FROM refresh_tokens WHERE token_hash=$1`, hash)
	return err
}

func (s *PGStore) ListAccounts(ctx context.Context, limit int, afterID string) ([]Account, string) {
	if limit <= 0 {
		limit = 50
	}
	rows, err := s.pool.Query(ctx,
		`SELECT id, username, password_hash, role, disabled, created_at FROM accounts
		 WHERE $1 = '' OR (created_at, id) < (SELECT created_at, id FROM accounts WHERE id=$1)
		 ORDER BY created_at DESC, id DESC LIMIT $2`, afterID, limit)
	if err != nil {
		return nil, ""
	}
	defer rows.Close()
	var out []Account
	for rows.Next() {
		var a Account
		if err := rows.Scan(&a.ID, &a.Username, &a.PasswordHash, &a.Role, &a.Disabled, &a.CreatedAt); err != nil {
			return out, ""
		}
		out = append(out, a)
	}
	next := ""
	if len(out) == limit {
		next = out[len(out)-1].ID
	}
	return out, next
}

func (s *PGStore) Devices(ctx context.Context, accountID string) []RefreshRecord {
	rows, err := s.pool.Query(ctx,
		`SELECT token_hash, account_id, device_id, expires_at, created_at FROM refresh_tokens
		 WHERE account_id=$1 ORDER BY created_at DESC`, accountID)
	if err != nil {
		return nil
	}
	defer rows.Close()
	var out []RefreshRecord
	for rows.Next() {
		var r RefreshRecord
		if err := rows.Scan(&r.Hash, &r.AccountID, &r.DeviceID, &r.ExpiresAt, &r.CreatedAt); err != nil {
			return out
		}
		out = append(out, r)
	}
	return out
}

func (s *PGStore) RevokeDevice(ctx context.Context, accountID, deviceID string) error {
	_, err := s.pool.Exec(ctx, `DELETE FROM refresh_tokens WHERE account_id=$1 AND device_id=$2`, accountID, deviceID)
	return err
}

func (s *PGStore) RevokeAllDevices(ctx context.Context, accountID string) error {
	_, err := s.pool.Exec(ctx, `DELETE FROM refresh_tokens WHERE account_id=$1`, accountID)
	return err
}

func (s *PGStore) Count(ctx context.Context) (int, int) {
	var total, disabled int
	_ = s.pool.QueryRow(ctx, `SELECT count(*) FROM accounts`).Scan(&total)
	_ = s.pool.QueryRow(ctx, `SELECT count(*) FROM accounts WHERE disabled`).Scan(&disabled)
	return total, disabled
}

func isUniqueViolation(err error) bool {
	var pgErr *pgconn.PgError
	if errors.As(err, &pgErr) {
		return pgErr.Code == "23505"
	}
	return false
}
