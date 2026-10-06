package worldsim_test

import (
	"encoding/json"
	"math"
	"os"
	"path/filepath"
	"testing"

	"lifetextsandbox/server/internal/testutil"
	"lifetextsandbox/server/internal/worldsim"
)

// 世界宏观一致性向量：客户端 client/sim/macro.gd 必须复现同一序列。
// 选取 6 个季度（< 初始 QuartersLeft=8），此区间不触发周期切换，故完全不依赖 RNG，
// 两端结果应逐位一致。
const (
	vectorSeed       = 12345
	vectorPopulation = 1_000_000
	vectorQuarters   = 6
)

type macroVectorCase struct {
	Quarter          int     `json:"quarter"`
	Population       int64   `json:"population"`
	InflationRate    float64 `json:"inflation_rate"`
	UnemploymentRate float64 `json:"unemployment_rate"`
	BaseRate         float64 `json:"base_rate"`
	PriceIndex       float64 `json:"price_index"`
	PMI              float64 `json:"pmi"`
	Phase            string  `json:"phase"`
	AbsoluteMinutes  int64   `json:"absolute_minutes"`
}

type macroVector struct {
	Spec       string            `json:"spec"`
	Version    int               `json:"version"`
	Seed       uint64            `json:"seed"`
	Population int64             `json:"population"`
	Quarters   int               `json:"quarters"`
	Cases      []macroVectorCase `json:"cases"`
}

func buildMacroVector() macroVector {
	s := worldsim.NewSimulator(vectorSeed, vectorPopulation)
	v := macroVector{
		Spec:       "macro_quarterly",
		Version:    1,
		Seed:       vectorSeed,
		Population: vectorPopulation,
		Quarters:   vectorQuarters,
	}
	for i := 0; i < vectorQuarters; i++ {
		ga := s.Tick()
		v.Cases = append(v.Cases, macroVectorCase{
			Quarter:          i + 1,
			Population:       ga.Population,
			InflationRate:    ga.InflationRate,
			UnemploymentRate: ga.UnemploymentRate,
			BaseRate:         s.BaseRate,
			PriceIndex:       s.PriceIndex,
			PMI:              s.PMI,
			Phase:            s.Phase,
			AbsoluteMinutes:  ga.AbsoluteMinutes,
		})
	}
	return v
}

func TestWorldSimVectorConsistency(t *testing.T) {
	dir := testutil.VectorsDir()
	if dir == "" {
		t.Fatal("未找到 shared/consistency/vectors 目录")
	}
	path := filepath.Join(dir, "worldsim.json")
	want := buildMacroVector()

	if os.Getenv("LIFETEXT_UPDATE_VECTORS") == "1" {
		data, err := json.MarshalIndent(want, "", "  ")
		if err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, append(data, '\n'), 0o644); err != nil {
			t.Fatal(err)
		}
		return
	}

	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("读取 worldsim.json 失败（可用 LIFETEXT_UPDATE_VECTORS=1 生成）: %v", err)
	}
	var got macroVector
	if err := json.Unmarshal(raw, &got); err != nil {
		t.Fatal(err)
	}
	if len(got.Cases) != len(want.Cases) {
		t.Fatalf("用例数不符: got=%d want=%d", len(got.Cases), len(want.Cases))
	}
	const tol = 1e-9
	for i := range want.Cases {
		w, g := want.Cases[i], got.Cases[i]
		if w.Population != g.Population || w.AbsoluteMinutes != g.AbsoluteMinutes || w.Phase != g.Phase {
			t.Errorf("quarter %d 离散字段不符: got=%+v want=%+v", i+1, g, w)
		}
		for name, pair := range map[string][2]float64{
			"inflation_rate":    {g.InflationRate, w.InflationRate},
			"unemployment_rate": {g.UnemploymentRate, w.UnemploymentRate},
			"base_rate":         {g.BaseRate, w.BaseRate},
			"price_index":       {g.PriceIndex, w.PriceIndex},
			"pmi":               {g.PMI, w.PMI},
		} {
			if math.Abs(pair[0]-pair[1]) > tol {
				t.Errorf("quarter %d %s: got=%.12f want=%.12f", i+1, name, pair[0], pair[1])
			}
		}
	}
}
