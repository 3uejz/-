// Package backup 提供基于 pg_dump/pg_restore 的每日备份、历史版本保留与恢复（R37）。
package backup

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

// Runner 执行数据库与对象存储备份。
type Runner struct {
	DBURL  string
	Dir    string
	Keep   int
	Now    func() time.Time
	RunCmd func(ctx context.Context, name string, args ...string) error
}

// New 创建备份 Runner；keep<=0 时默认保留 7 份。
func New(dbURL, dir string, keep int) *Runner {
	if keep <= 0 {
		keep = 7
	}
	return &Runner{
		DBURL: dbURL,
		Dir:   dir,
		Keep:  keep,
		Now:   time.Now,
		RunCmd: func(ctx context.Context, name string, args ...string) error {
			cmd := exec.CommandContext(ctx, name, args...)
			out, err := cmd.CombinedOutput()
			if err != nil {
				return fmt.Errorf("%s 失败: %w: %s", name, err, strings.TrimSpace(string(out)))
			}
			return nil
		},
	}
}

const dumpPrefix = "lifetext-"

// DumpName 依据时间生成备份文件名，如 lifetext-20260102-030405.dump。
func DumpName(t time.Time) string {
	return dumpPrefix + t.UTC().Format("20060102-150405") + ".dump"
}

// Backup 执行一次 pg_dump，随后按保留策略清理旧备份，返回新备份路径。
func (r *Runner) Backup(ctx context.Context) (string, error) {
	if r.DBURL == "" {
		return "", fmt.Errorf("缺少 DATABASE_URL，无法备份")
	}
	if err := os.MkdirAll(r.Dir, 0o755); err != nil {
		return "", err
	}
	now := time.Now
	if r.Now != nil {
		now = r.Now
	}
	path := filepath.Join(r.Dir, DumpName(now()))
	if err := r.RunCmd(ctx, "pg_dump",
		"--format=custom", "--no-owner", "--file", path, r.DBURL); err != nil {
		return "", err
	}
	if _, err := Prune(r.Dir, r.Keep); err != nil {
		return path, err
	}
	return path, nil
}

// Restore 从备份文件恢复数据库（--clean 覆盖现有对象）。
func (r *Runner) Restore(ctx context.Context, path string) error {
	if r.DBURL == "" {
		return fmt.Errorf("缺少 DATABASE_URL，无法恢复")
	}
	return r.RunCmd(ctx, "pg_restore",
		"--clean", "--if-exists", "--no-owner", "--dbname", r.DBURL, path)
}

// Prune 保留 dir 下最新的 keep 份备份，返回被删除的路径列表。
func Prune(dir string, keep int) ([]string, error) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil, err
	}
	var dumps []string
	for _, e := range entries {
		if !e.IsDir() && strings.HasPrefix(e.Name(), dumpPrefix) && strings.HasSuffix(e.Name(), ".dump") {
			dumps = append(dumps, e.Name())
		}
	}
	sort.Strings(dumps)
	if keep < 0 {
		keep = 0
	}
	var removed []string
	if len(dumps) > keep {
		for _, name := range dumps[:len(dumps)-keep] {
			p := filepath.Join(dir, name)
			if err := os.Remove(p); err != nil {
				return removed, err
			}
			removed = append(removed, p)
		}
	}
	return removed, nil
}
