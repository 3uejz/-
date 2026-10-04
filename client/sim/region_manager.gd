class_name RegionManager
extends RefCounted
## 分区休眠与唤醒（R5、R50）。
##
## 活动区域执行分钟级模拟；休眠区域只保存快照与上次模拟时间，不参与逐帧循环。
## 玩家进入休眠区域时调用 wake()，按统计模型批量补算个体生命周期、关系衰减、经济与事件，
## 补算成本与休眠时长近似线性（wake_cost ~= c * elapsed_minutes），并满足：
##   - 时间守恒：wake 补算的分钟总量等于休眠时长，且不重复结算已算时段；
##   - 幂等：对同一区域连续两次 wake，第二次不改变区域状态。
##
## 与 WorldClock / TickScheduler 的衔接：本类是被 Autoload 调用的纯模型，不直接依赖 Autoload。
## 可注入 clock（鸭子类型，提供 total_minutes）取当前世界分钟；未注入时使用内部时钟，
## 由 advance_now() 推进，便于 headless 测试与离线近似。
##
## 数值默认见 client/sim/baseline.gd（可被远程配置覆盖）。

const RngScript = preload("res://sim/rng.gd")
const BaselineScript = preload("res://sim/baseline.gd")
const GregorianScript = preload("res://sim/gregorian.gd")


## 单个区域的状态与休眠快照（design.md Data Models: RegionState）。
class RegionState:
	extends RefCounted

	const DORMANT: int = 0
	const ACTIVE: int = 1
	const MAX_AGE: int = 120  # 年龄结构统计上限（结构边界，非玩法数值）

	var id: String = ""
	var level: String = "city"
	var population: int = 0
	var economy: float = 0.0
	var price_index: float = 1.0
	var safety: float = 50.0
	var climate: String = ""
	var locations: Array = []
	var npcs: Array = []
	var last_simulated_minute: int = 0
	var state: int = DORMANT
	var snapshot: Dictionary = {}

	func _init(region_id: String = "") -> void:
		id = region_id

	func is_active() -> bool:
		return state == ACTIVE

	func activate() -> void:
		state = ACTIVE

	func dormant() -> void:
		state = DORMANT

	func apply_options(opts: Dictionary) -> void:
		level = str(opts.get("level", level))
		population = int(opts.get("population", population))
		economy = float(opts.get("economy", economy))
		price_index = float(opts.get("price_index", price_index))
		safety = float(opts.get("safety", safety))
		climate = str(opts.get("climate", climate))
		if opts.has("locations") and opts["locations"] is Array:
			locations = (opts["locations"] as Array).duplicate()
		last_simulated_minute = int(opts.get("last_simulated_minute", last_simulated_minute))

	## 初次登记时建立人口快照：年龄结构按均匀分布占位，精细分布由任务 12 接入。
	func init_snapshot() -> void:
		economy = maxf(0.0, economy)
		price_index = maxf(0.0, price_index)
		snapshot = {
			"population": population,
			"age_bands": _uniform_age_bands(population),
			"occupation_mix": {},
			"economy": economy,
			"price_index": price_index,
			"safety": safety,
			"relation_strength": 50.0,  # 聚合平均关系强度 0..100，中性起点
			"event_count": 0,
			"births": 0,
			"deaths": 0,
			"net_migration": 0,
			"wake_minutes_total": 0,
			"active_minutes_total": 0,
			"last_simulated_minute": last_simulated_minute,
		}

	func to_dict() -> Dictionary:
		return {
			"region_key": id,
			"level": level,
			"population": population,
			"economy": economy,
			"price_index": price_index,
			"safety": safety,
			"climate": climate,
			"locations": locations.duplicate(),
			"npcs": npcs.duplicate(),
			"last_simulated_minute": last_simulated_minute,
			"state": state,
			"snapshot": snapshot.duplicate(true),
		}

	static func from_dict(data: Dictionary) -> RegionState:
		var r := RegionState.new(str(data.get("region_key", "")))
		r.level = str(data.get("level", "city"))
		r.population = int(data.get("population", 0))
		r.economy = float(data.get("economy", 0.0))
		r.price_index = float(data.get("price_index", 1.0))
		r.safety = float(data.get("safety", 50.0))
		r.climate = str(data.get("climate", ""))
		r.locations = (data.get("locations", []) as Array).duplicate()
		r.npcs = (data.get("npcs", []) as Array).duplicate()
		r.last_simulated_minute = int(data.get("last_simulated_minute", 0))
		r.state = int(data.get("state", DORMANT))
		var snap: Variant = data.get("snapshot", {})
		r.snapshot = (snap as Dictionary).duplicate(true) if snap is Dictionary else {}
		r._coerce_snapshot()
		return r

	## 把 JSON 载入后的 float 数值规整为 int（JSON 数字一律为 float）。
	func _coerce_snapshot() -> void:
		if snapshot.has("population"):
			snapshot["population"] = int(snapshot["population"])
		for key in ["event_count", "births", "deaths", "net_migration", "wake_minutes_total", "active_minutes_total", "last_simulated_minute"]:
			if snapshot.has(key):
				snapshot[key] = int(snapshot[key])
		if snapshot.has("age_bands") and snapshot["age_bands"] is Array:
			var ages: Array = snapshot["age_bands"]
			for i in ages.size():
				ages[i] = int(ages[i])
		for key in ["economy", "price_index", "safety", "relation_strength"]:
			if snapshot.has(key):
				snapshot[key] = float(snapshot[key])

	static func _uniform_age_bands(pop: int) -> Array:
		var bands: Array = []
		bands.resize(MAX_AGE + 1)
		bands.fill(0)
		if pop <= 0:
			return bands
		var per: int = pop / (MAX_AGE + 1)
		var rem: int = pop % (MAX_AGE + 1)
		for i in range(MAX_AGE + 1):
			bands[i] = per
		var idx: int = 0
		while rem > 0 and idx <= MAX_AGE:
			bands[idx] += 1
			rem -= 1
			idx += 1
		return bands


var _regions: Dictionary = {}   # region_id -> RegionState
var _active: Dictionary = {}    # region_id -> true
var _clock = null               # 鸭子类型：提供 total_minutes 的时钟对象（可选）
var _now_minute: int = 0
var _rng = null                 # SplitMix64，确定性事件采样

func _init(clock: Object = null, seed: int = 0) -> void:
	_clock = clock
	_rng = RngScript.new(seed)


# --- 时钟 ---

## 当前世界分钟：优先取注入 clock 的 total_minutes，否则用内部时钟。
func now_minute() -> int:
	if _clock != null:
		return int(_clock.total_minutes)
	return _now_minute

## 无注入 clock 时推进内部时钟（离线近似与测试用）。
func advance_now(minutes: int) -> void:
	_now_minute += maxi(0, minutes)


# --- 区域登记与查询 ---

func register_region(region_id: String, opts: Dictionary = {}) -> RegionState:
	var is_new: bool = not _regions.has(region_id)
	var region := _ensure_region(region_id, opts)
	if not is_new and not opts.is_empty():
		region.apply_options(opts)
		region.init_snapshot()
	return region

func _ensure_region(region_id: String, opts: Dictionary = {}) -> RegionState:
	if _regions.has(region_id):
		return _regions[region_id]
	var region := RegionState.new(region_id)
	region.apply_options(opts)
	region.init_snapshot()
	_regions[region_id] = region
	return region

func has_region(region_id: String) -> bool:
	return _regions.has(region_id)

func get_region(region_id: String) -> RegionState:
	return _regions.get(region_id)

func region_ids() -> Array:
	return _regions.keys()

func active_ids() -> Array:
	return _active.keys()

func is_active(region_id: String) -> bool:
	return _active.has(region_id)

func snapshot(region_id: String) -> Dictionary:
	var region: RegionState = _regions.get(region_id)
	if region == null:
		return {}
	return region.snapshot.duplicate(true)


# --- 激活 / 休眠 ---

## 玩家进入区域：若为休眠则统计快进补算到当前时刻，然后置为活动。
func enter(region_id: String, at_minute: int = -1) -> Dictionary:
	var region := _ensure_region(region_id)
	var now: int = at_minute if at_minute >= 0 else now_minute()
	if region.is_active():
		var advanced: int = _advance_active_to(region, now)
		_active[region_id] = true
		return {
			"region_id": region_id, "state": "active", "already_active": true,
			"advanced_minutes": advanced,
			"last_simulated_minute": region.last_simulated_minute,
		}
	var elapsed: int = maxi(0, now - region.last_simulated_minute)
	var summary := wake(region_id, elapsed)
	region.activate()
	_active[region_id] = true
	summary["state"] = "active"
	summary["already_active"] = false
	return summary

## 玩家离开区域：结算活动时段并写休眠快照。
func leave(region_id: String, at_minute: int = -1) -> Dictionary:
	var region := _ensure_region(region_id)
	var now: int = at_minute if at_minute >= 0 else now_minute()
	if region.is_active():
		_advance_active_to(region, now)
	region.dormant()
	_active.erase(region_id)
	_write_snapshot(region)
	return {
		"region_id": region_id, "state": "dormant",
		"last_simulated_minute": region.last_simulated_minute,
		"snapshot": region.snapshot.duplicate(true),
	}


# --- 唤醒统计快进 ---

## 对休眠区域执行统计快进。elapsed_minutes < 0 时按当前世界分钟减去上次模拟时刻推算。
## 返回补算摘要；advanced_minutes 为本次实际结算的分钟数（时间守恒的可观测口径）。
func wake(region_id: String, elapsed_minutes: int = -1) -> Dictionary:
	var region := _ensure_region(region_id)
	if region.is_active():
		return _idempotent_result(region)
	var elapsed: int = elapsed_minutes
	if elapsed < 0:
		elapsed = maxi(0, now_minute() - region.last_simulated_minute)
	elapsed = maxi(0, elapsed)
	if elapsed <= 0:
		region.activate()
		return {
			"region_id": region_id, "advanced_minutes": 0, "advanced_days": 0.0,
			"advanced_years": 0.0, "births": 0, "deaths": 0, "net_migration": 0,
			"events": 0, "population": region.population, "idempotent": false,
			"last_simulated_minute": region.last_simulated_minute,
		}
	var summary := _fast_forward(region, elapsed)
	# 时间守恒：已模拟时刻恰前移 elapsed，不重复结算。
	region.last_simulated_minute += elapsed
	region.activate()
	summary["last_simulated_minute"] = region.last_simulated_minute
	return summary

func _idempotent_result(region: RegionState) -> Dictionary:
	return {
		"region_id": region.id, "advanced_minutes": 0, "advanced_days": 0.0,
		"advanced_years": 0.0, "births": 0, "deaths": 0, "net_migration": 0,
		"events": 0, "population": region.population, "idempotent": true,
		"last_simulated_minute": region.last_simulated_minute,
	}

## 统计快进：按休眠时长批量补算生命周期、关系、经济与事件。
func _fast_forward(region: RegionState, elapsed_minutes: int) -> Dictionary:
	var snap: Dictionary = region.snapshot
	var days: float = float(elapsed_minutes) / float(GregorianScript.MINUTES_PER_DAY)
	var years: float = days / BaselineScript.REGION_DAYS_PER_YEAR

	var pop: int = region.population
	var birth_rate: float = BaselineScript.effective_region_param("region_birth_rate_annual", BaselineScript.REGION_BIRTH_RATE_ANNUAL)
	var death_rate: float = BaselineScript.effective_region_param("region_death_rate_annual", BaselineScript.REGION_DEATH_RATE_ANNUAL)
	var migration_rate: float = BaselineScript.effective_region_param("region_migration_rate_annual", BaselineScript.REGION_MIGRATION_RATE_ANNUAL)
	var births: int = int(round(float(pop) * birth_rate * years))
	var deaths: int = int(round(float(pop) * death_rate * years))
	var net_migration: int = int(round(float(pop) * migration_rate * years))
	var new_pop: int = maxi(0, pop + births - deaths + net_migration)

	# 个体生命周期：年龄结构前移并纳入出生、死亡与迁移。
	var ages: Array = snap.get("age_bands", [])
	var shift: int = mini(int(floor(years)), RegionState.MAX_AGE)
	snap["age_bands"] = _advance_age_bands(ages, shift, births, deaths, net_migration, new_pop)

	# 关系衰减：未互动关系按年指数衰减（复用 R18 基线系数）。
	var rel: float = float(snap.get("relation_strength", 50.0))
	snap["relation_strength"] = BaselineScript.apply_relation_decay(rel, years)

	# 经济更新：区域经济复合增长，物价按通胀累积。
	var economy: float = float(region.economy)
	var economy_growth: float = BaselineScript.effective_region_param("region_economy_growth_annual", BaselineScript.REGION_ECONOMY_GROWTH_ANNUAL)
	var inflation: float = BaselineScript.effective_region_param("region_inflation_rate_annual", BaselineScript.REGION_INFLATION_RATE_ANNUAL)
	var grew: float = economy * pow(1.0 + economy_growth, years)
	if is_finite(grew):
		region.economy = grew
	var inflated: float = region.price_index * pow(1.0 + inflation, years)
	if is_finite(inflated):
		region.price_index = inflated

	# 事件结算：按泊松模型采样休眠期间发生的事件数。
	var event_rate: float = BaselineScript.effective_region_param("region_event_rate_annual", BaselineScript.REGION_EVENT_RATE_ANNUAL)
	var events: int = _poisson(event_rate * years)

	region.population = new_pop
	snap["births"] = int(snap.get("births", 0)) + births
	snap["deaths"] = int(snap.get("deaths", 0)) + deaths
	snap["net_migration"] = int(snap.get("net_migration", 0)) + net_migration
	snap["event_count"] = int(snap.get("event_count", 0)) + events
	snap["wake_minutes_total"] = int(snap.get("wake_minutes_total", 0)) + elapsed_minutes
	_write_snapshot(region)

	return {
		"region_id": region.id,
		"advanced_minutes": elapsed_minutes,
		"advanced_days": days,
		"advanced_years": years,
		"births": births,
		"deaths": deaths,
		"net_migration": net_migration,
		"events": events,
		"population": new_pop,
		"idempotent": false,
	}

## 年龄结构按整年前移：死亡按比例削减，出生进入 0 岁，净迁移分摊到劳动年龄，最后归一到新人口。
func _advance_age_bands(ages: Array, shift: int, births: int, deaths: int, net_migration: int, pop_after: int) -> Array:
	var n: int = RegionState.MAX_AGE + 1
	var source: Array = ages if ages.size() == n else RegionState._uniform_age_bands(pop_after)
	var new_ages: Array = []
	new_ages.resize(n)
	new_ages.fill(0)

	var pop_before: int = _sum_int(source)
	var survivor_scale: float = 1.0
	if pop_before > 0 and deaths > 0:
		survivor_scale = maxf(0.0, float(pop_before - deaths) / float(pop_before))
	for age in range(n):
		var target: int = age + shift
		if target < n:
			new_ages[target] += int(round(float(source[age]) * survivor_scale))
	new_ages[0] += births

	if net_migration != 0:
		var lo: int = 15
		var hi: int = mini(64, n - 1)
		var slots: int = hi - lo + 1
		var base: int = net_migration / slots
		var rem: int = net_migration - base * slots
		for a in range(lo, hi + 1):
			new_ages[a] = maxi(0, new_ages[a] + base)
		var idx: int = lo
		var r: int = absi(rem)
		while r > 0 and idx <= hi:
			new_ages[idx] = maxi(0, new_ages[idx] + (1 if rem > 0 else -1))
			r -= 1
			idx += 1

	var total: int = _sum_int(new_ages)
	if total > 0 and pop_after > 0:
		var factor: float = float(pop_after) / float(total)
		for a in range(n):
			new_ages[a] = int(round(float(new_ages[a]) * factor))
	return new_ages


# --- 活动区域分钟级模拟 ---

## 供 TickScheduler 的 MINUTE 层注册调用。
func tick_minute(total_minutes: int) -> void:
	for region_id in _active.keys():
		var region: RegionState = _regions.get(region_id)
		if region != null:
			_advance_active_to(region, total_minutes)

## 活动区域推进到 target_minute：精细系统由任务 12 接入，这里推进时间与日级轻量结算。
func _advance_active_to(region: RegionState, target_minute: int) -> int:
	var minutes: int = target_minute - region.last_simulated_minute
	if minutes <= 0:
		return 0
	region.last_simulated_minute = target_minute
	_simulate_activity(region, minutes)
	return minutes

func _simulate_activity(region: RegionState, minutes: int) -> void:
	var snap: Dictionary = region.snapshot
	snap["active_minutes_total"] = int(snap.get("active_minutes_total", 0)) + minutes
	var start: int = region.last_simulated_minute - minutes
	var before_day: int = start / GregorianScript.MINUTES_PER_DAY
	var after_day: int = region.last_simulated_minute / GregorianScript.MINUTES_PER_DAY
	var day_count: int = after_day - before_day
	if day_count > 0:
		var annual: float = BaselineScript.effective_region_param("region_economy_growth_annual", BaselineScript.REGION_ECONOMY_GROWTH_ANNUAL)
		var daily: float = annual / BaselineScript.REGION_DAYS_PER_YEAR
		var grew: float = region.economy * pow(1.0 + daily, float(day_count))
		if is_finite(grew):
			region.economy = grew
	_write_snapshot(region)

func _write_snapshot(region: RegionState) -> void:
	var snap: Dictionary = region.snapshot
	snap["population"] = region.population
	snap["economy"] = region.economy
	snap["price_index"] = region.price_index
	snap["safety"] = region.safety
	snap["last_simulated_minute"] = region.last_simulated_minute


# --- 序列化（world_delta.regions，见 save.schema.json region_delta）---

func to_delta(region_id: String) -> Dictionary:
	var region: RegionState = _regions.get(region_id)
	if region == null:
		return {}
	return {
		"region_key": region.id,
		"population": region.population,
		"price_index": region.price_index,
		"safety": region.safety,
		"last_simulated_minute": region.last_simulated_minute,
		"snapshot": region.snapshot.duplicate(true),
	}

func dump_deltas() -> Array:
	var out: Array = []
	for region_id in _regions.keys():
		out.append(to_delta(region_id))
	return out

## 从 world_delta.regions 载入区域增量，载入后一律视为休眠。
func load_delta(data: Dictionary) -> RegionState:
	var region := RegionState.from_dict(data)
	region.dormant()
	_regions[region.id] = region
	_active.erase(region.id)
	return region

func load_deltas(items: Array) -> void:
	for item in items:
		if item is Dictionary and str(item.get("region_key", "")) != "":
			load_delta(item)


# --- 统计与工具 ---

## 所有区域累计补算分钟数（时间守恒的可观测口径）。
func total_advanced_minutes() -> int:
	var total: int = 0
	for region_id in _regions.keys():
		var region: RegionState = _regions[region_id]
		total += int(region.snapshot.get("wake_minutes_total", 0))
	return total

## 泊松采样（确定性，使用注入种子的 SplitMix64）。
func _poisson(lambda: float) -> int:
	if lambda <= 0.0:
		return 0
	if lambda > 30.0:
		# 大 lambda 用正态近似，避免与时长成正比的长循环。
		var u1: float = maxf(1e-12, _rng.next_float())
		var u2: float = _rng.next_float()
		var z: float = sqrt(-2.0 * log(u1)) * cos(TAU * u2)
		return maxi(0, int(round(lambda + sqrt(lambda) * z)))
	var limit: float = exp(-lambda)
	var k: int = 0
	var p: float = 1.0
	for _i in range(1000):
		k += 1
		p *= maxf(1e-12, _rng.next_float())
		if p <= limit:
			return k - 1
	return k

static func _sum_int(values: Array) -> int:
	var total: int = 0
	for v in values:
		total += int(v)
	return total
