package sim_test

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"

	"lifetextsandbox/server/internal/sim"
	"lifetextsandbox/server/internal/testutil"
)

type baselineVectors struct {
	Ranges   map[string][2]int `json:"ranges"`
	Defaults struct {
		MinutesPerDay        int     `json:"minutes_per_day"`
		RelationAnnualDecayK float64 `json:"relation_annual_decay_k"`
	} `json:"defaults"`
	SpeedLevels []int `json:"speed_levels"`
}

func TestBaselineConsistency(t *testing.T) {
	dir := testutil.VectorsDir()
	if dir == "" {
		t.Fatal("未找到 shared/consistency/vectors 目录")
	}
	raw, err := os.ReadFile(filepath.Join(dir, "baseline.json"))
	if err != nil {
		t.Fatalf("读取 baseline.json 失败: %v", err)
	}
	var v baselineVectors
	if err := json.Unmarshal(raw, &v); err != nil {
		t.Fatalf("解析 baseline.json 失败: %v", err)
	}

	code := sim.Ranges()
	for key, want := range v.Ranges {
		got, ok := code[key]
		if !ok {
			t.Errorf("代码缺少区间 %q", key)
			continue
		}
		if got != want {
			t.Errorf("区间 %q: got=%v want=%v", key, got, want)
		}
	}

	if v.Defaults.MinutesPerDay != sim.MinutesPerDay {
		t.Errorf("minutes_per_day: got=%d want=%d", sim.MinutesPerDay, v.Defaults.MinutesPerDay)
	}
	if diff := sim.RelationAnnualDecayK - v.Defaults.RelationAnnualDecayK; diff > 1e-12 || diff < -1e-12 {
		t.Errorf("relation_annual_decay_k: got=%v want=%v", sim.RelationAnnualDecayK, v.Defaults.RelationAnnualDecayK)
	}

	if got, want := sim.ClampAttribute(150), 100; got != want {
		t.Errorf("ClampAttribute(150)=%d want=%d", got, want)
	}
	if got, want := sim.ClampAttribute(-5), 0; got != want {
		t.Errorf("ClampAttribute(-5)=%d want=%d", got, want)
	}
	if got, want := sim.ClampSkill(99), 20; got != want {
		t.Errorf("ClampSkill(99)=%d want=%d", got, want)
	}
	if got, want := sim.ClampFavor(-999), -100; got != want {
		t.Errorf("ClampFavor(-999)=%d want=%d", got, want)
	}
	if got, want := sim.ClampGrudge(999), 100; got != want {
		t.Errorf("ClampGrudge(999)=%d want=%d", got, want)
	}
}
