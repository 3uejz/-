class_name MacroSimulator
extends RefCounted
## 宏观季度模拟（客户端离线近似）。与后端 server/internal/worldsim/macro.go 保持确定性一致，
## 测试向量见 shared/consistency/vectors/worldsim.json。
##
## 权威边界（design 混合权威）：全球人口与宏观指标后端权威；客户端离线用同一模型近似推进，
## 记录 server_tick（=服务端 absolute_minutes）锚点；上线后宏观以服务端为准，本地精细区域变更保留。

const BaselineScript = preload("res://sim/baseline.gd")

const QUARTERS_PER_YEAR: int = BaselineScript.MACRO_QUARTERS_PER_YEAR

const BASE_INFLATION: float = BaselineScript.MACRO_BASE_INFLATION
const BASE_RATE: float = BaselineScript.MACRO_BASE_RATE
const UNEMPLOYMENT: float = BaselineScript.MACRO_UNEMPLOYMENT_BASE
const GDP_GROWTH_BASE: float = BaselineScript.MACRO_GDP_GROWTH_BASE
const INFLATION_MIN: float = BaselineScript.MACRO_INFLATION_MIN
const INFLATION_MAX: float = BaselineScript.MACRO_INFLATION_MAX
const UNEMPLOYMENT_LO: float = BaselineScript.MACRO_UNEMPLOYMENT_MIN
const UNEMPLOYMENT_HI: float = BaselineScript.MACRO_UNEMPLOYMENT_MAX
const RATE_MIN: float = BaselineScript.MACRO_RATE_MIN
const RATE_MAX: float = BaselineScript.MACRO_RATE_MAX
const PMI_MIN: float = BaselineScript.MACRO_PMI_MIN
const PMI_MAX: float = BaselineScript.MACRO_PMI_MAX
const PMI_BASE: float = BaselineScript.MACRO_PMI_BASE

const RATE_UNEMPLOYMENT_SENSITIVITY: float = BaselineScript.MACRO_RATE_UNEMPLOYMENT_SENSITIVITY
const INFLATION_TRADEOFF: float = BaselineScript.MACRO_INFLATION_UNEMPLOYMENT_TRADEOFF

const CYCLE_MIN_QUARTERS: int = BaselineScript.MACRO_CYCLE_MIN_QUARTERS
const CYCLE_MAX_QUARTERS: int = BaselineScript.MACRO_CYCLE_MAX_QUARTERS

const BIRTH_RATE: float = BaselineScript.MACRO_BIRTH_RATE
const DEATH_RATE: float = BaselineScript.MACRO_DEATH_RATE
const MIGRATION_RATE: float = BaselineScript.MACRO_MIGRATION_RATE

const CYCLE_PHASES: Array[String] = ["recession", "recovery", "boom", "slowdown"]
const CYCLE_GDP_EFFECT: Dictionary = {
	"recession": -0.04, "recovery": 0.02, "boom": 0.05, "slowdown": 0.01,
}

const MINUTES_PER_YEAR: float = 1440.0 * 365.25
const MINUTES_PER_QUARTER: float = MINUTES_PER_YEAR / QUARTERS_PER_YEAR

var version: int = 1
var population: int = 0
var gdp_est: float = 100.0
var gdp: float = 100.0
var inflation: float = BASE_INFLATION
var unemployment: float = UNEMPLOYMENT
var base_rate: float = BASE_RATE
var price_index: float = 1.0
var pmi: float = PMI_BASE
var phase: String = "recovery"
var quarters_left: int = 8
var money_supply: float = 1.0
var absolute_minute: int = 0

## server_tick 锚点：最近一次服务端下发的 absolute_minutes。
var server_tick: int = 0

var _population_f: float = 0.0
var _quarter_printed: float = 0.0
var _rng: SplitMix64

func _init(seed: int, initial_population: int) -> void:
	population = initial_population
	_population_f = float(initial_population)
	_rng = SplitMix64.new(seed)

## 推进一个季度并返回全球指标字典（字段与 worldsim.schema.json#global_indicators 对齐）。
func tick() -> Dictionary:
	_advance_cycle()

	var effect: float = float(CYCLE_GDP_EFFECT.get(phase, 0.0))
	var growth: float = GDP_GROWTH_BASE + effect
	gdp *= 1.0 + growth / float(QUARTERS_PER_YEAR)
	if gdp < 0.0 or is_nan(gdp):
		gdp = 0.0

	var money_growth: float = _quarter_printed / maxf(1.0, money_supply)
	var cycle_pressure: float = -0.01
	if phase == "boom" or phase == "recovery":
		cycle_pressure = 0.01
	var target_inflation: float = BASE_INFLATION \
		+ 0.8 * money_growth \
		- 0.3 * (base_rate - BASE_RATE) \
		+ cycle_pressure
	inflation = clampf(_move_toward(inflation, target_inflation, 0.01), INFLATION_MIN, INFLATION_MAX)

	var rate_target: float = BASE_RATE + 0.5 * (inflation - BASE_INFLATION)
	base_rate = clampf(base_rate + 0.5 * (rate_target - base_rate), RATE_MIN, RATE_MAX)

	var unemployment_target: float = UNEMPLOYMENT \
		- INFLATION_TRADEOFF * (inflation - BASE_INFLATION) \
		+ RATE_UNEMPLOYMENT_SENSITIVITY * (base_rate - BASE_RATE)
	unemployment = clampf(_move_toward(unemployment, unemployment_target, 0.01), UNEMPLOYMENT_LO, UNEMPLOYMENT_HI)

	price_index *= 1.0 + inflation / float(QUARTERS_PER_YEAR)
	pmi = clampf(PMI_BASE + 50.0 * (inflation - BASE_INFLATION) - 100.0 * (unemployment - UNEMPLOYMENT), PMI_MIN, PMI_MAX)

	_population_f = Population.cohort_next(_population_f, BIRTH_RATE, DEATH_RATE, MIGRATION_RATE, MINUTES_PER_QUARTER)
	population = int(round(_population_f))
	absolute_minute += int(round(MINUTES_PER_QUARTER))
	_quarter_printed = 0.0
	return global_indicators()

## 全球指标快照。
func global_indicators() -> Dictionary:
	return {
		"absolute_minutes": absolute_minute,
		"population": population,
		"gdp_est": gdp,
		"inflation_rate": inflation,
		"unemployment_rate": unemployment,
	}

## 记录服务端下发的人口（用于与本地近似对齐）。
func set_server_population(value: int) -> void:
	population = value
	_population_f = float(value)

## 记录服务端 tick 锚点，并把本地宏观时钟对齐到该点。
func set_server_anchor(absolute_minutes: int) -> void:
	server_tick = absolute_minutes
	absolute_minute = absolute_minutes

## 从锚点离线推进到目标分钟（上限保护）；返回推进的季度数。
func advance_to(target_minutes: int, cap: int = 4000) -> int:
	var ticks: int = 0
	while absolute_minute + int(round(MINUTES_PER_QUARTER)) <= target_minutes and ticks < cap:
		tick()
		ticks += 1
	return ticks

## 上线合并：全球宏观以服务端为准，记录锚点；本地区域/玩家变更由调用方保留。
func merge_from_server(server: Dictionary) -> Dictionary:
	if server.has("population"):
		set_server_population(int(server["population"]))
	if server.has("inflation_rate"):
		inflation = float(server["inflation_rate"])
	if server.has("unemployment_rate"):
		unemployment = float(server["unemployment_rate"])
	if server.has("gdp_est"):
		gdp = float(server["gdp_est"])
	if server.has("absolute_minutes"):
		set_server_anchor(int(server["absolute_minutes"]))
	version += 1
	return global_indicators()

func issue(amount: float) -> void:
	if amount <= 0.0:
		return
	_quarter_printed += amount
	money_supply += amount

func _advance_cycle() -> void:
	quarters_left -= 1
	if quarters_left > 0:
		return
	var idx: int = 0
	for i in CYCLE_PHASES.size():
		if CYCLE_PHASES[i] == phase:
			idx = i
			break
	phase = CYCLE_PHASES[(idx + 1) % CYCLE_PHASES.size()]
	var span: int = CYCLE_MAX_QUARTERS - CYCLE_MIN_QUARTERS
	quarters_left = CYCLE_MIN_QUARTERS + int(_rng.next_float() * float(span + 1))

func _move_toward(value: float, target: float, step: float) -> float:
	if value < target:
		return minf(value + step, target)
	return maxf(value - step, target)
