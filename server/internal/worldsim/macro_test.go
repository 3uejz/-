package worldsim_test

import (
	"math"
	"testing"

	"lifetextsandbox/server/internal/worldsim"
)

// 宏观指标始终落在 design D8 的区间内，且物价指数在正通胀下单调不减。
func TestMacroIndicatorsBoundedAndDeterministic(t *testing.T) {
	a := worldsim.NewSimulator(42, 7000000000)
	b := worldsim.NewSimulator(42, 7000000000)
	prev := 1.0
	for i := 0; i < 40; i++ {
		ga := a.Tick()
		gb := b.Tick()
		if ga != gb {
			t.Fatalf("同种子第 %d 季指标不一致: %+v vs %+v", i, ga, gb)
		}
		if ga.InflationRate < worldsim.MacroInflationMin || ga.InflationRate > worldsim.MacroInflationMax {
			t.Fatalf("通胀越界: %v", ga.InflationRate)
		}
		if ga.UnemploymentRate < worldsim.MacroUnemploymentLo || ga.UnemploymentRate > worldsim.MacroUnemploymentHi {
			t.Fatalf("失业率越界: %v", ga.UnemploymentRate)
		}
		if a.PriceIndex <= prev {
			t.Fatalf("物价指数未单调上升: %v -> %v", prev, a.PriceIndex)
		}
		prev = a.PriceIndex
		if a.PMI < worldsim.MacroPMIMin || a.PMI > worldsim.MacroPMIMax {
			t.Fatalf("PMI 越界: %v", a.PMI)
		}
	}
	if math.Abs(a.BaseRate-worldsim.MacroBaseRate) > worldsim.MacroRateMax {
		t.Fatalf("基准利率越界: %v", a.BaseRate)
	}
}

// 合并时全球指标以服务端权威为准，区域权威标记为 server。
func TestMergeServerAuthority(t *testing.T) {
	s := worldsim.NewSimulator(7, 1000)
	s.Tick()
	local := worldsim.WorldSummary{
		Version: 1,
		Global:  worldsim.GlobalIndicators{Population: 1, InflationRate: 99},
		Regions: []worldsim.RegionCohort{{RegionKey: "city.a", Level: "city", PriceIndex: 0.01, Authority: "client_approx"}},
	}
	merged := s.Merge(local)
	if merged.Global.InflationRate == 99 {
		t.Fatal("全球指标应取服务端权威")
	}
	if merged.Regions[0].Authority != "server" {
		t.Fatalf("区域权威应标记 server: %q", merged.Regions[0].Authority)
	}
	if merged.Regions[0].PriceIndex <= 0.01 {
		t.Fatalf("区域价格指数应被服务端修正: %v", merged.Regions[0].PriceIndex)
	}
}

// 货币投放经通胀传导推高通胀。
func TestIssueTransmitsToInflation(t *testing.T) {
	s := worldsim.NewSimulator(1, 1000)
	base := s.Inflation
	for i := 0; i < 12; i++ {
		s.Issue(1.0)
		s.Tick()
	}
	if s.Inflation <= base {
		t.Fatalf("货币投放未推高通胀: %v -> %v", base, s.Inflation)
	}
}
