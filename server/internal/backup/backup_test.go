package backup

import (
	"context"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestDumpName(t *testing.T) {
	got := DumpName(time.Date(2026, 1, 2, 3, 4, 5, 0, time.UTC))
	if got != "lifetext-20260102-030405.dump" {
		t.Fatalf("命名不符: %s", got)
	}
}

func TestPruneKeepsNewest(t *testing.T) {
	dir := t.TempDir()
	names := []string{
		"lifetext-20260101-000000.dump",
		"lifetext-20260102-000000.dump",
		"lifetext-20260103-000000.dump",
		"lifetext-20260104-000000.dump",
	}
	for _, n := range names {
		if err := os.WriteFile(filepath.Join(dir, n), []byte("x"), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	// 无关文件不应被清理。
	other := filepath.Join(dir, "notes.txt")
	_ = os.WriteFile(other, []byte("keep"), 0o600)

	removed, err := Prune(dir, 2)
	if err != nil {
		t.Fatal(err)
	}
	if len(removed) != 2 {
		t.Fatalf("应删除 2 份，实际 %d: %v", len(removed), removed)
	}
	remaining, _ := os.ReadDir(dir)
	var dumps int
	for _, e := range remaining {
		if filepath.Ext(e.Name()) == ".dump" {
			dumps++
		}
	}
	if dumps != 2 {
		t.Fatalf("应保留 2 份，实际 %d", dumps)
	}
	if _, err := os.Stat(other); err != nil {
		t.Fatalf("无关文件被误删: %v", err)
	}
}

func TestBackupUsesRunnerAndPrunes(t *testing.T) {
	dir := t.TempDir()
	var calls [][]string
	r := New("postgres://x", dir, 1)
	r.Now = func() time.Time { return time.Date(2026, 2, 3, 4, 5, 6, 0, time.UTC) }
	r.RunCmd = func(_ context.Context, name string, args ...string) error {
		calls = append(calls, append([]string{name}, args...))
		// 模拟 pg_dump 生成文件。
		for i, a := range args {
			if a == "--file" && i+1 < len(args) {
				_ = os.WriteFile(args[i+1], []byte("dump"), 0o600)
			}
		}
		return nil
	}
	// 预置一份旧备份，验证会被清理。
	old := filepath.Join(dir, "lifetext-20260101-000000.dump")
	_ = os.WriteFile(old, []byte("old"), 0o600)

	path, err := r.Backup(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if filepath.Base(path) != "lifetext-20260203-040506.dump" {
		t.Fatalf("备份文件名不符: %s", path)
	}
	if len(calls) != 1 || calls[0][0] != "pg_dump" {
		t.Fatalf("应调用一次 pg_dump: %v", calls)
	}
	if _, err := os.Stat(old); !os.IsNotExist(err) {
		t.Fatalf("旧备份应被清理")
	}
}
