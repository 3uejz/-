package worldsim

// 宏观经济权威模型骨架（R17、R48；design D8）。
//
// 权威边界：本模块权威全球人口与宏观经济统计，按季度 tick 计算；
// 客户端订阅只读快照并在本地用近似公式离线推进（见 client/sim/economy.gd），
// 上线后经 /world/sync 合并，不逐笔回放。
//
// 结构字段与 shared/schemas/worldsim.schema.json 对齐；
// 数值默认与客户端 client/sim/baseline.gd 的经济段保持一致，防止两端漂移。

import (
	"math"

	"lifetextsandbox/server/internal/sim"
)

// 宏观默认参数（与客户端 baseline.gd 经济段一致）。
const (
	MacroQuartersPerYear = 4

	MacroBaseInflation  = 0.02
	MacroBaseRate       = 0.03
	MacroUnemployment   = 0.05
	MacroGDPGrowthBase  = 0.03
	MacroInflationMin   = -0.05
	MacroInflationMax   = 3.0
	MacroUnemploymentLo = 0.0
	MacroUnemploymentHi = 1.0
	MacroRateMin        = 0.0
	MacroRateMax        = 0.5
	MacroPMIMin         = 0.0
	MacroPMIMax         = 100.0
	MacroPMIBase        = 50.0

	MacroRateUnemploymentSensitivity = 0.8
	MacroInflationTradeoff           = 0.4

	MacroCycleMinQuarters = 4
	MacroCycleMaxQuarters = 16
)

// CyclePhases 产业周期阶段：萧条/复苏/繁荣/放缓。
var CyclePhases = []string{"recession", "recovery", "boom", "slowdown"}

// CycleGDPEffect 各周期阶段的季度 GDP 增长修正。
var CycleGDPEffect = map[string]float64{
	"recession": -0.04, "recovery": 0.02, "boom": 0.05, "slowdown": 0.01,
}

// GlobalIndicators 全球宏观指标（worldsim.schema.json#/$defs/global_indicators）。
type GlobalIndicators struct {
	AbsoluteMinutes  int64   `json:"absolute_minutes,omitempty"`
	Population       int64   `json:"population"`
	GdpEst           float64 `json:"gdp_est"`
	InflationRate    float64 `json:"inflation_rate"`
	UnemploymentRate float64 `json:"unemployment_rate"`
}

// RegionCohort 区域队列统计（worldsim.schema.json#/$defs/region_cohort）。
type RegionCohort struct {
	RegionKey     string             `json:"region_key"`
	Level         string             `json:"level"`
	Population    int64              `json:"population,omitempty"`
	AgeBands      map[string]int64   `json:"age_bands,omitempty"`
	SexRatio      float64            `json:"sex_ratio,omitempty"`
	OccupationMix map[string]float64 `json:"occupation_mix,omitempty"`
	BirthRate     float64            `json:"birth_rate,omitempty"`
	DeathRate     float64            `json:"death_rate,omitempty"`
	MigrationRate float64            `json:"migration_rate,omitempty"`
	PriceIndex    float64            `json:"price_index,omitempty"`
	Authority     string             `json:"authority,omitempty"`
}

// WorldSummary 全球摘要（worldsim.schema.json）。
type WorldSummary struct {
	Version    int              `json:"version"`
	ComputedAt string           `json:"computed_at"`
	Global     GlobalIndicators `json:"global"`
	Regions    []RegionCohort   `json:"regions,omitempty"`
}

// Simulator 宏观权威模拟器：确定性季度推进。
type Simulator struct {
	Version      int
	Global       GlobalIndicators
	Regions      []RegionCohort
	PriceIndex   float64
	BaseRate     float64
	Inflation    float64
	Unemployment float64
	GDP          float64
	PMI          float64
	Phase        string
	QuartersLeft int
	MoneySupply  float64

	rng            *sim.SplitMix64
	quarterPrinted float64
}

// NewSimulator 以种子创建模拟器，指标从基准值出发。
func NewSimulator(seed uint64, population int64) *Simulator {
	return &Simulator{
		Version:      1,
		Global:       GlobalIndicators{Population: population, GdpEst: 100.0},
		PriceIndex:   1.0,
		BaseRate:     MacroBaseRate,
		Inflation:    MacroBaseInflation,
		Unemployment: MacroUnemployment,
		GDP:          100.0,
		PMI:          MacroPMIBase,
		Phase:        "recovery",
		QuartersLeft: 8,
		MoneySupply:  1.0,
		rng:          sim.NewSplitMix64(seed),
	}
}

// Tick 推进一个季度并返回最新全球指标。
func (s *Simulator) Tick() GlobalIndicators {
	s.advanceCycle()

	effect := CycleGDPEffect[s.Phase]
	growth := MacroGDPGrowthBase + effect
	s.GDP *= 1.0 + growth/float64(MacroQuartersPerYear)
	if s.GDP < 0 || math.IsNaN(s.GDP) {
		s.GDP = 0
	}

	moneyGrowth := s.quarterPrinted / math.Max(1.0, s.MoneySupply)
	cyclePressure := -0.01
	if s.Phase == "boom" || s.Phase == "recovery" {
		cyclePressure = 0.01
	}
	targetInflation := MacroBaseInflation +
		0.8*moneyGrowth -
		0.3*(s.BaseRate-MacroBaseRate) +
		cyclePressure
	s.Inflation = clamp(moveToward(s.Inflation, targetInflation, 0.01), MacroInflationMin, MacroInflationMax)

	rateTarget := MacroBaseRate + 0.5*(s.Inflation-MacroBaseInflation)
	s.BaseRate = clamp(s.BaseRate+0.5*(rateTarget-s.BaseRate), MacroRateMin, MacroRateMax)

	unemploymentTarget := MacroUnemployment -
		MacroInflationTradeoff*(s.Inflation-MacroBaseInflation) +
		MacroRateUnemploymentSensitivity*(s.BaseRate-MacroBaseRate)
	s.Unemployment = clamp(moveToward(s.Unemployment, unemploymentTarget, 0.01), MacroUnemploymentLo, MacroUnemploymentHi)

	s.PriceIndex *= 1.0 + s.Inflation/float64(MacroQuartersPerYear)
	s.PMI = clamp(MacroPMIBase+50.0*(s.Inflation-MacroBaseInflation)-100.0*(s.Unemployment-MacroUnemployment), MacroPMIMin, MacroPMIMax)

	s.Global.GdpEst = s.GDP
	s.Global.InflationRate = s.Inflation
	s.Global.UnemploymentRate = s.Unemployment
	s.quarterPrinted = 0
	return s.Global
}

func (s *Simulator) advanceCycle() {
	s.QuartersLeft--
	if s.QuartersLeft > 0 {
		return
	}
	idx := 0
	for i, p := range CyclePhases {
		if p == s.Phase {
			idx = i
			break
		}
	}
	s.Phase = CyclePhases[(idx+1)%len(CyclePhases)]
	span := MacroCycleMaxQuarters - MacroCycleMinQuarters
	s.QuartersLeft = MacroCycleMinQuarters + int(s.rng.NextFloat()*float64(span+1))
}

// Issue 记录本季货币投放，参与下季通胀传导。
func (s *Simulator) Issue(amount float64) {
	if amount <= 0 {
		return
	}
	s.quarterPrinted += amount
	s.MoneySupply += amount
}

// Summary 组装为世界摘要（区域队列原样附带，权威标记 server）。
func (s *Simulator) Summary(computedAt string, regions []RegionCohort) WorldSummary {
	for i := range regions {
		regions[i].Authority = "server"
	}
	s.Regions = regions
	return WorldSummary{Version: s.Version, ComputedAt: computedAt, Global: s.Global, Regions: regions}
}

// Merge 合并客户端本地近似：全球指标以服务端为准，区域价格指数取较大修正，
// 体现「宏观后端权威、微观客户端」的混合权威边界。
func (s *Simulator) Merge(local WorldSummary) WorldSummary {
	merged := local
	merged.Global = s.Global
	if merged.Version < s.Version {
		merged.Version = s.Version
	}
	for i := range merged.Regions {
		if merged.Regions[i].PriceIndex < s.PriceIndex {
			merged.Regions[i].PriceIndex = s.PriceIndex
		}
		merged.Regions[i].Authority = "server"
	}
	return merged
}

func clamp(v, lo, hi float64) float64 {
	if v < lo {
		return lo
	}
	if v > hi {
		return hi
	}
	return v
}

func moveToward(v, target, step float64) float64 {
	if v < target {
		return math.Min(v+step, target)
	}
	return math.Max(v-step, target)
}
