package admin

import (
	"context"
	"encoding/json"
	"errors"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// PGStore 是 PostgreSQL 版 Store 实现。
type PGStore struct {
	pool *pgxpool.Pool
}

var _ Store = (*PGStore)(nil)

// NewPGStore 构造后台存储。
func NewPGStore(pool *pgxpool.Pool) *PGStore {
	return &PGStore{pool: pool}
}

func (s *PGStore) AppendAudit(ctx context.Context, e AuditEntry) error {
	before, _ := json.Marshal(orEmptyMap(e.Before))
	after, _ := json.Marshal(orEmptyMap(e.After))
	_, err := s.pool.Exec(ctx,
		`INSERT INTO admin_audit_logs
		 (id, actor_account_id, action, target_type, target_id, before, after, result, ip, user_agent, created_at)
		 VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)`,
		e.ID, e.ActorAccountID, e.Action, e.TargetType, e.TargetID,
		before, after, e.Result, e.IP, e.UserAgent, e.CreatedAt)
	return err
}

func (s *PGStore) Audits(ctx context.Context, action, actor, target string, limit int) ([]AuditEntry, error) {
	if limit <= 0 {
		limit = 50
	}
	rows, err := s.pool.Query(ctx,
		`SELECT id, actor_account_id, action, target_type, target_id, before, after, result, ip, user_agent, created_at
		 FROM admin_audit_logs
		 WHERE ($1 = '' OR action = $1) AND ($2 = '' OR actor_account_id = $2) AND ($3 = '' OR target_id = $3)
		 ORDER BY created_at DESC LIMIT $4`,
		action, actor, target, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []AuditEntry
	for rows.Next() {
		var e AuditEntry
		var before, after []byte
		if err := rows.Scan(&e.ID, &e.ActorAccountID, &e.Action, &e.TargetType, &e.TargetID,
			&before, &after, &e.Result, &e.IP, &e.UserAgent, &e.CreatedAt); err != nil {
			return out, err
		}
		_ = json.Unmarshal(before, &e.Before)
		_ = json.Unmarshal(after, &e.After)
		out = append(out, e)
	}
	return out, rows.Err()
}

func (s *PGStore) CreateRelease(ctx context.Context, r Release) error {
	accounts, _ := json.Marshal(orEmptyList(r.AccountList))
	_, err := s.pool.Exec(ctx,
		`INSERT INTO content_releases
		 (id, pack_name, pack_version, strategy, rollout_percent, account_list, status, manifest_version, created_at, updated_at)
		 VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)`,
		r.ID, r.PackName, r.PackVersion, r.Strategy, r.RolloutPercent, accounts,
		r.Status, r.ManifestVersion, r.CreatedAt, r.UpdatedAt)
	return err
}

func (s *PGStore) UpdateRelease(ctx context.Context, r Release) error {
	accounts, _ := json.Marshal(orEmptyList(r.AccountList))
	_, err := s.pool.Exec(ctx,
		`UPDATE content_releases SET strategy=$2, rollout_percent=$3, account_list=$4, status=$5, manifest_version=$6, updated_at=$7
		 WHERE id=$1`,
		r.ID, r.Strategy, r.RolloutPercent, accounts, r.Status, r.ManifestVersion, r.UpdatedAt)
	return err
}

func (s *PGStore) ReleaseByID(ctx context.Context, rid string) (Release, bool) {
	row := s.pool.QueryRow(ctx,
		`SELECT id, pack_name, pack_version, strategy, rollout_percent, account_list, status, manifest_version, created_at, updated_at
		 FROM content_releases WHERE id=$1`, rid)
	r, ok, _ := scanRelease(row)
	return r, ok
}

func (s *PGStore) Releases(ctx context.Context) ([]Release, error) {
	rows, err := s.pool.Query(ctx,
		`SELECT id, pack_name, pack_version, strategy, rollout_percent, account_list, status, manifest_version, created_at, updated_at
		 FROM content_releases ORDER BY created_at DESC`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []Release
	for rows.Next() {
		r, _, err := scanRelease(rows)
		if err != nil {
			return out, err
		}
		out = append(out, r)
	}
	return out, rows.Err()
}

func (s *PGStore) SaveConfig(ctx context.Context, v ConfigVersion) error {
	values, _ := json.Marshal(orEmptyMap(v.Values))
	_, err := s.pool.Exec(ctx,
		`INSERT INTO config_versions (id, version, values, revision, created_by, created_at)
		 VALUES ($1,$2,$3,$4,$5,$6)`,
		v.ID, v.Version, values, v.Revision, v.CreatedBy, v.CreatedAt)
	return err
}

func (s *PGStore) CurrentConfig(ctx context.Context) (ConfigVersion, bool) {
	row := s.pool.QueryRow(ctx,
		`SELECT id, version, values, revision, created_by, created_at FROM config_versions ORDER BY version DESC LIMIT 1`)
	return scanConfig(row)
}

func (s *PGStore) ConfigVersions(ctx context.Context) ([]ConfigVersion, error) {
	rows, err := s.pool.Query(ctx,
		`SELECT id, version, values, revision, created_by, created_at FROM config_versions ORDER BY version DESC`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []ConfigVersion
	for rows.Next() {
		v, ok := scanConfig(rows)
		if !ok {
			return out, rows.Err()
		}
		out = append(out, v)
	}
	return out, rows.Err()
}

func (s *PGStore) ConfigByVersion(ctx context.Context, version int) (ConfigVersion, bool) {
	row := s.pool.QueryRow(ctx,
		`SELECT id, version, values, revision, created_by, created_at FROM config_versions WHERE version=$1`, version)
	return scanConfig(row)
}

func (s *PGStore) CreateAnnouncement(ctx context.Context, a Announcement) error {
	accounts, _ := json.Marshal(orEmptyList(a.AccountList))
	_, err := s.pool.Exec(ctx,
		`INSERT INTO announcements (id, title, body, audience, account_list, start_at, end_at, status, created_at, updated_at)
		 VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)`,
		a.ID, a.Title, a.Body, a.Audience, accounts, a.StartAt, a.EndAt, a.Status, a.CreatedAt, a.UpdatedAt)
	return err
}

func (s *PGStore) UpdateAnnouncement(ctx context.Context, a Announcement) error {
	accounts, _ := json.Marshal(orEmptyList(a.AccountList))
	_, err := s.pool.Exec(ctx,
		`UPDATE announcements SET title=$2, body=$3, audience=$4, account_list=$5, start_at=$6, end_at=$7, status=$8, updated_at=$9
		 WHERE id=$1`,
		a.ID, a.Title, a.Body, a.Audience, accounts, a.StartAt, a.EndAt, a.Status, a.UpdatedAt)
	return err
}

func (s *PGStore) DeleteAnnouncement(ctx context.Context, aid string) error {
	_, err := s.pool.Exec(ctx, `DELETE FROM announcements WHERE id=$1`, aid)
	return err
}

func (s *PGStore) AnnouncementByID(ctx context.Context, aid string) (Announcement, bool) {
	row := s.pool.QueryRow(ctx,
		`SELECT id, title, body, audience, account_list, start_at, end_at, status, created_at, updated_at
		 FROM announcements WHERE id=$1`, aid)
	a, ok, _ := scanAnnouncement(row)
	return a, ok
}

func (s *PGStore) Announcements(ctx context.Context) ([]Announcement, error) {
	rows, err := s.pool.Query(ctx,
		`SELECT id, title, body, audience, account_list, start_at, end_at, status, created_at, updated_at
		 FROM announcements ORDER BY created_at DESC`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []Announcement
	for rows.Next() {
		a, _, err := scanAnnouncement(rows)
		if err != nil {
			return out, err
		}
		out = append(out, a)
	}
	return out, rows.Err()
}

// scanner 抽象 pgx.Row 与 pgx.Rows 的 Scan。
type scanner interface {
	Scan(dest ...any) error
}

func scanRelease(row scanner) (Release, bool, error) {
	var r Release
	var accounts []byte
	err := row.Scan(&r.ID, &r.PackName, &r.PackVersion, &r.Strategy, &r.RolloutPercent,
		&accounts, &r.Status, &r.ManifestVersion, &r.CreatedAt, &r.UpdatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return Release{}, false, nil
	}
	if err != nil {
		return Release{}, false, err
	}
	_ = json.Unmarshal(accounts, &r.AccountList)
	return r, true, nil
}

func scanConfig(row scanner) (ConfigVersion, bool) {
	var v ConfigVersion
	var values []byte
	err := row.Scan(&v.ID, &v.Version, &values, &v.Revision, &v.CreatedBy, &v.CreatedAt)
	if err != nil {
		return ConfigVersion{}, false
	}
	_ = json.Unmarshal(values, &v.Values)
	return v, true
}

func scanAnnouncement(row scanner) (Announcement, bool, error) {
	var a Announcement
	var accounts []byte
	err := row.Scan(&a.ID, &a.Title, &a.Body, &a.Audience, &accounts, &a.StartAt, &a.EndAt, &a.Status, &a.CreatedAt, &a.UpdatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return Announcement{}, false, nil
	}
	if err != nil {
		return Announcement{}, false, err
	}
	_ = json.Unmarshal(accounts, &a.AccountList)
	return a, true, nil
}

func orEmptyMap(m map[string]any) map[string]any {
	if m == nil {
		return map[string]any{}
	}
	return m
}

func orEmptyList(l []string) []string {
	if l == nil {
		return []string{}
	}
	return l
}
