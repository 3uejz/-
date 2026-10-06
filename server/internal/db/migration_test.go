package db

import (
	"sort"
	"testing"
)

func TestMigrationFilesSorted(t *testing.T) {
	files, err := migrationFiles()
	if err != nil {
		t.Fatal(err)
	}
	if len(files) < 10 {
		t.Fatalf("迁移文件过少: %v", files)
	}
	if !sort.StringsAreSorted(files) {
		t.Fatalf("迁移文件未排序: %v", files)
	}
	for _, f := range files {
		if f == "" || f[len(f)-4:] != ".sql" {
			t.Fatalf("非法迁移文件名: %q", f)
		}
	}
}
