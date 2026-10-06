package blob

import (
	"context"
	"errors"
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
