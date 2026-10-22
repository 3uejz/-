package blob

import (
	"context"
	"errors"
	"io"
	"testing"
)

func TestLocalStoreRoundTrip(t *testing.T) {
	store, err := NewLocalStore(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	ctx := context.Background()
	key := "saves/acc1/1/1"
	if err := store.Put(ctx, key, []byte("hello")); err != nil {
		t.Fatal(err)
	}
	got, err := store.Get(ctx, key)
	if err != nil || string(got) != "hello" {
		t.Fatalf("读取失败: %q err=%v", got, err)
	}
	if err := store.Delete(ctx, key); err != nil {
		t.Fatal(err)
	}
	if _, err := store.Get(ctx, key); !errors.Is(err, ErrNotFound) {
		t.Fatalf("删除后应 ErrNotFound，得到 %v", err)
	}
}

func TestLocalStoreOpenSupportsSeek(t *testing.T) {
	store, err := NewLocalStore(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	ctx := context.Background()
	key := "packs/jobs/v1.ltpack"
	if err := store.Put(ctx, key, []byte("abcdef")); err != nil {
		t.Fatal(err)
	}
	r, size, err := store.Open(ctx, key)
	if err != nil || size != 6 {
		t.Fatalf("Open 失败: size=%d err=%v", size, err)
	}
	defer r.Close()
	if _, err := r.Seek(2, io.SeekStart); err != nil {
		t.Fatal(err)
	}
	buf := make([]byte, 3)
	if _, err := io.ReadFull(r, buf); err != nil || string(buf) != "cde" {
		t.Fatalf("Seek 后读取错误: %q err=%v", buf, err)
	}
}

func TestLocalStoreRejectsTraversal(t *testing.T) {
	store, _ := NewLocalStore(t.TempDir())
	ctx := context.Background()
	if err := store.Put(ctx, "../escape", []byte("x")); err == nil {
		t.Fatal("路径穿越应被拒绝")
	}
	if _, err := store.Get(ctx, "/abs"); err == nil {
		t.Fatal("绝对路径应被拒绝")
	}
}
