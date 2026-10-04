package sim_test

import (
	"encoding/json"
	"math"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"

	"lifetextsandbox/server/internal/sim"
	"lifetextsandbox/server/internal/testutil"
)

type rngVectors struct {
	IntegerCases []struct {
		Seed  string   `json:"seed"`
		Next3 []string `json:"next3"`
	} `json:"integer_cases"`
	FloatCases []struct {
		Seed int       `json:"seed"`
		F64  []float64 `json:"f64"`
	} `json:"float_cases"`
}

func loadRNGVectors(t *testing.T) rngVectors {
	t.Helper()
	dir := testutil.VectorsDir()
	if dir == "" {
		t.Fatal("未找到 shared/consistency/vectors 目录")
	}
	raw, err := os.ReadFile(filepath.Join(dir, "rng.json"))
	if err != nil {
		t.Fatalf("读取 rng.json 失败: %v", err)
	}
	var v rngVectors
	if err := json.Unmarshal(raw, &v); err != nil {
		t.Fatalf("解析 rng.json 失败: %v", err)
	}
	return v
}

func parseU64(t *testing.T, s string) uint64 {
	t.Helper()
	clean := strings.TrimPrefix(strings.ToLower(strings.TrimSpace(s)), "0x")
	v, err := strconv.ParseUint(clean, 16, 64)
	if err != nil {
		t.Fatalf("解析无符号 64 位失败 %q: %v", s, err)
	}
	return v
}

func TestRNGIntegerConsistency(t *testing.T) {
	v := loadRNGVectors(t)
	for _, c := range v.IntegerCases {
		rng := sim.NewSplitMix64(parseU64(t, c.Seed))
		for i, wantHex := range c.Next3 {
			got := rng.Next()
			want := parseU64(t, wantHex)
			if got != want {
				t.Errorf("seed=%s idx=%d: got=0x%016x want=0x%016x", c.Seed, i, got, want)
			}
		}
	}
}

func TestRNGFloatConsistency(t *testing.T) {
	v := loadRNGVectors(t)
	const tolerance = 1e-6
	for _, c := range v.FloatCases {
		rng := sim.NewSplitMix64(uint64(c.Seed))
		for i, want := range c.F64 {
			got := rng.NextFloat()
			if math.Abs(got-want) > tolerance {
				t.Errorf("seed=%d idx=%d: got=%.12f want=%.12f", c.Seed, i, got, want)
			}
		}
	}
}
