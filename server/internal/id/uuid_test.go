package id

import (
	"testing"
	"time"
)

func TestNewUUIDv7Format(t *testing.T) {
	seen := map[string]bool{}
	for i := 0; i < 1000; i++ {
		u := NewUUIDv7()
		if !IsValid(u) {
			t.Fatalf("生成非法 UUIDv7: %q", u)
		}
		if seen[u] {
			t.Fatalf("UUID 重复: %q", u)
		}
		seen[u] = true
	}
}

func TestUUIDv7TimeOrdered(t *testing.T) {
	earlier := UUIDv7At(time.UnixMilli(1_700_000_000_000))
	later := UUIDv7At(time.UnixMilli(1_700_000_001_000))
	if earlier >= later {
		t.Fatalf("UUIDv7 应随时间有序: %q >= %q", earlier, later)
	}
}

func TestIsValidRejects(t *testing.T) {
	cases := []string{
		"",
		"not-a-uuid",
		"018f0000-0000-6000-8000-000000000000", // 版本 6
		"018f0000-0000-7000-0000-000000000000", // 变体 0
		"018F0000-0000-7000-8000-000000000000", // 大写
	}
	for _, c := range cases {
		if IsValid(c) {
			t.Errorf("应判为非法: %q", c)
		}
	}
}
