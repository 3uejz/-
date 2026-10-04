class_name WeatherSystem
extends RefCounted
## 天气生态（R2、R41；design D1）。
##
## 职责：
##   - 为每个区域绑定气候带（10 类），由种子确定性演化天气状态（20 类一阶马尔可夫链）；
##   - 由气候带 + 季节 + 昼夜 + 随机扰动按温度公式生成连续气象变量
##     （气温/湿度/气压/风速/能见度/降水），并统一 clamp 到 design D1 的区间；
##   - 提供未来 7 日天气预报，准确率随预报天数下降、随时代阶段提升；
##   - 低频触发 10 类灾害，并在触发前 1–3 日提供预警。
##
## 确定性：所有随机量由 world_seed、区域标识、日序与用途盐值共同派生，同种子完全可复现。
## 休眠区域不做逐日回放：调用方只需查询当前时刻，本类按查询时刻锚定并按需向前演化。
## 数值默认集中在 client/sim/baseline.gd，均可由远程配置覆盖。

const RngScript = preload("res://sim/rng.gd")
const BaselineScript = preload("res://sim/baseline.gd")
const GregorianScript = preload("res://sim/gregorian.gd")

# 随机流盐值：不同用途相互独立，避免同一日各量相关。
const _SALT_INITIAL: int = 1011
const _SALT_MARKOV: int = 2027
const _SALT_TEMP: int = 3037
const _SALT_HUMIDITY: int = 4051
const _SALT_PRESSURE: int = 5059
const _SALT_WIND: int = 6067
const _SALT_VISIBILITY: int = 7079
const _SALT_PRECIP: int = 8089
const _SALT_FORECAST: int = 9103
const _SALT_DISASTER: int = 10009

const MINUTES_PER_DAY: int = 1440


## 单个时刻的天气快照（design.md Data Models 的 WeatherState）。
class WeatherState:
	extends RefCounted

	var region_id: String = ""
	var zone: String = ""
	var day_index: int = 0
	var minute_of_day: int = 0
	var condition: String = "clear"
	var condition_name: String = "晴"
	var temperature_c: float = 0.0
	var humidity_pct: float = 0.0
	var pressure_hpa: float = 1013.0
	var wind_ms: float = 0.0
	var visibility_km: float = 10.0
	var precipitation_mm: float = 0.0

	func to_dict() -> Dictionary:
		return {
			"region_id": region_id,
			"zone": zone,
			"day_index": day_index,
			"minute_of_day": minute_of_day,
			"condition": condition,
			"condition_name": condition_name,
			"temperature_c": temperature_c,
			"humidity_pct": humidity_pct,
			"pressure_hpa": pressure_hpa,
			"wind_ms": wind_ms,
			"visibility_km": visibility_km,
			"precipitation_mm": precipitation_mm,
		}

	static func from_dict(data: Dictionary) -> WeatherState:
		var s := WeatherState.new()
		s.region_id = str(data.get("region_id", ""))
		s.zone = str(data.get("zone", ""))
		s.day_index = int(data.get("day_index", 0))
		s.minute_of_day = int(data.get("minute_of_day", 0))
		s.condition = str(data.get("condition", "clear"))
		s.condition_name = str(data.get("condition_name", ""))
		s.temperature_c = float(data.get("temperature_c", 0.0))
		s.humidity_pct = float(data.get("humidity_pct", 0.0))
		s.pressure_hpa = float(data.get("pressure_hpa", 1013.0))
		s.wind_ms = float(data.get("wind_ms", 0.0))
		s.visibility_km = float(data.get("visibility_km", 10.0))
		s.precipitation_mm = float(data.get("precipitation_mm", 0.0))
		return s


## 区域天气演化状态（内部缓存，不写入存档；快照按查询时刻可重算）。
class RegionWeather:
	extends RefCounted

	var region_id: String = ""
	var zone: String = ""
	var initialized: bool = false
	var last_day: int = 0
	var last_condition: String = ""
	var history: Dictionary = {}  # day_index(int) -> condition(String)

	func _init(rid: String = "", zkey: String = "") -> void:
		region_id = rid
		zone = zkey


var _world_seed: int = 0
var _regions: Dictionary = {}  # region_id -> RegionWeather


func _init(world_seed: int = 0) -> void:
	_world_seed = world_seed


# --- 区域登记与查询 ---

## 登记区域并绑定气候带；若已登记且气候带不同则重置演化链。
func register_region(region_id: String, zone_key: String) -> RegionWeather:
	if _regions.has(region_id):
		var existing: RegionWeather = _regions[region_id]
		if existing.zone != zone_key:
			set_zone(region_id, zone_key)
		return existing
	var rw := RegionWeather.new(region_id, zone_key)
	_regions[region_id] = rw
	return rw

func set_zone(region_id: String, zone_key: String) -> void:
	var rw: RegionWeather = _regions.get(region_id)
	if rw == null:
		register_region(region_id, zone_key)
		return
	if rw.zone == zone_key:
		return
	rw.zone = zone_key
	rw.initialized = false
	rw.history.clear()
	rw.last_condition = ""

func has_region(region_id: String) -> bool:
	return _regions.has(region_id)

func region_ids() -> Array:
	return _regions.keys()

func zone_of(region_id: String) -> String:
	var rw: RegionWeather = _regions.get(region_id)
	return rw.zone if rw != null else ""

func climate_zone_name(zone_key: String) -> String:
	var z: Dictionary = BaselineScript.effective_zone(zone_key)
	return str(z.get("name", zone_key))

func weather_state_name(condition: String) -> String:
	var st: Dictionary = BaselineScript.effective_weather_state(condition)
	return str(st.get("name", condition))

static func day_of_minute(absolute_minute: int) -> int:
	return int(floor(float(absolute_minute) / float(MINUTES_PER_DAY)))

static func minute_of_day(absolute_minute: int) -> int:
	return posmod(absolute_minute, MINUTES_PER_DAY)


# --- 天气演化 ---

## 取某区域某日（绝对日序）的天气状态；同种子、同输入完全确定。
func condition_for_day(region_id: String, day: int) -> String:
	var rw: RegionWeather = _regions.get(region_id)
	if rw == null:
		return ""
	if rw.history.has(day):
		return str(rw.history[day])
	if not rw.initialized:
		_anchor(rw, day)
		return rw.last_condition
	if day < rw.last_day:
		# 回溯到历史窗口之外：以该日重新锚定，保证确定性但不保证与旧链一致。
		_anchor(rw, day)
		return rw.last_condition
	var d: int = rw.last_day
	while d < day:
		d += 1
		rw.last_condition = _next_condition(rw.zone, d, rw.last_condition)
		rw.history[d] = rw.last_condition
		rw.last_day = d
	_trim_history(rw)
	return rw.last_condition

## 取某区域某一绝对分钟时刻的完整气象快照。
func state_at(region_id: String, absolute_minute: int) -> WeatherState:
	var st := WeatherState.new()
	var rw: RegionWeather = _regions.get(region_id)
	if rw == null:
		return st
	var day: int = day_of_minute(absolute_minute)
	var minute: int = minute_of_day(absolute_minute)
	var condition: String = condition_for_day(region_id, day)
	return build_state(region_id, day, minute, condition)

## 由区域、日序、日内分钟与天气状态构造连续气象变量（供测试与派生系统复用）。
func build_state(region_id: String, day: int, minute: int, condition: String) -> WeatherState:
	var st := WeatherState.new()
	st.region_id = region_id
	st.day_index = day
	st.minute_of_day = minute
	st.condition = condition
	st.condition_name = weather_state_name(condition)
	var rw: RegionWeather = _regions.get(region_id)
	st.zone = rw.zone if rw != null else ""
	var zone: Dictionary = BaselineScript.effective_zone(st.zone)
	if zone.is_empty():
		return st
	var meta: Dictionary = BaselineScript.effective_weather_state(condition)

	var cal: Dictionary = GregorianScript.from_absolute_minutes(day * MINUTES_PER_DAY)
	var doy: int = _day_of_year(int(cal["year"]), int(cal["month"]), int(cal["day"]))
	var hour: float = float(minute) / 60.0
	var seasonal: float = sin(TAU * float(doy) / 365.25 + float(zone["phase"]))
	var diurnal: float = sin(TAU * hour / 24.0)

	var temp: float = float(zone["base_temp"]) \
		+ float(zone["amp_temp"]) * seasonal \
		+ float(zone["amp_diurnal"]) * diurnal \
		+ _noise(region_id, day, _SALT_TEMP, BaselineScript.WEATHER_TEMP_NOISE_SIGMA) \
		+ float(meta.get("temp_delta", 0.0))
	st.temperature_c = clampf(temp, BaselineScript.WEATHER_TEMP_MIN, BaselineScript.WEATHER_TEMP_MAX)

	var sigma: float = BaselineScript.WEATHER_DERIVED_NOISE_SIGMA
	st.humidity_pct = clampf(
		float(zone["humidity"]) + float(meta.get("humidity_mod", 0.0)) + _noise(region_id, day, _SALT_HUMIDITY, sigma),
		BaselineScript.WEATHER_HUMIDITY_MIN, BaselineScript.WEATHER_HUMIDITY_MAX)
	st.pressure_hpa = clampf(
		float(zone["pressure"]) + float(meta.get("pressure_delta", 0.0)) + _noise(region_id, day, _SALT_PRESSURE, sigma),
		BaselineScript.WEATHER_PRESSURE_MIN, BaselineScript.WEATHER_PRESSURE_MAX)
	st.wind_ms = clampf(
		float(zone["wind"]) + float(meta.get("wind_mod", 0.0)) + _noise(region_id, day, _SALT_WIND, sigma),
		BaselineScript.WEATHER_WIND_MIN, BaselineScript.WEATHER_WIND_MAX)
	st.visibility_km = clampf(
		float(zone["visibility"]) + float(meta.get("visibility_mod", 0.0)) + _noise(region_id, day, _SALT_VISIBILITY, sigma),
		BaselineScript.WEATHER_VISIBILITY_MIN, BaselineScript.WEATHER_VISIBILITY_MAX)
	st.precipitation_mm = clampf(
		float(meta.get("precip_mm", 0.0)) * float(zone["precip_scale"]) + _noise(region_id, day, _SALT_PRECIP, sigma),
		BaselineScript.WEATHER_PRECIP_MIN, BaselineScript.WEATHER_PRECIP_MAX)
	return st


# --- 天气预报 ---

## 未来 N 日预报（默认 7 日）。era_index 决定预报基准准确率（见 baseline ERA_DEFINITIONS）。
## 返回逐日字典：day/lead/condition/condition_name/temperature_high_c/temperature_low_c/
## precipitation_mm/accuracy。lead=0 表示当日实况，准确率恒为 1。
func forecast(region_id: String, from_minute: int, era_index: int = 0, days: int = -1) -> Array:
	var span: int = BaselineScript.WEATHER_FORECAST_DAYS if days < 0 else maxi(0, days)
	var start_day: int = day_of_minute(from_minute)
	var out: Array = []
	for lead in range(span):
		var day: int = start_day + lead
		var truth: String = condition_for_day(region_id, day)
		var accuracy: float = forecast_accuracy(era_index, lead)
		var shown: String = truth
		if lead > 0 and accuracy < 1.0:
			var roll: float = _rng_for(region_id, day, _SALT_FORECAST).next_float()
			if roll > accuracy:
				shown = _alternative_condition(region_id, day, truth)
		var noon := build_state(region_id, day, 720, truth)
		var midnight := build_state(region_id, day, 0, truth)
		out.append({
			"day": day,
			"lead": lead,
			"condition": shown,
			"condition_name": weather_state_name(shown),
			"temperature_high_c": maxf(noon.temperature_c, midnight.temperature_c),
			"temperature_low_c": minf(noon.temperature_c, midnight.temperature_c),
			"precipitation_mm": noon.precipitation_mm,
			"accuracy": accuracy,
		})
	return out

## 第 lead 日预报准确率：lead=0 为 1；随后按时代基准与逐日衰减下降。
func forecast_accuracy(era_index: int, lead: int) -> float:
	if lead <= 0:
		return 1.0
	var era: Dictionary = BaselineScript.effective_era(era_index)
	var base: float = float(era.get("forecast_accuracy", 0.5))
	var acc: float = base * pow(BaselineScript.WEATHER_FORECAST_ACCURACY_DECAY, float(lead - 1))
	return clampf(acc, BaselineScript.WEATHER_FORECAST_ACCURACY_MIN, 1.0)


# --- 灾害 ---

## 某日发生的灾害列表（低频偶发）。返回 [{key,name,day}]。
func disasters_on(region_id: String, day: int) -> Array:
	var out: Array = []
	if not _regions.has(region_id):
		return out
	for key in BaselineScript.WEATHER_DISASTER_ORDER:
		if _disaster_triggers(region_id, key, day):
			var d: Dictionary = BaselineScript.effective_disaster(key)
			out.append({"key": key, "name": str(d.get("name", key)), "day": day})
	return out

## 某日发布的灾害预警（覆盖未来 1–3 日内将触发的灾害）。
## 返回 [{key,name,event_day,days_until,message}]。
func disaster_warnings(region_id: String, day: int) -> Array:
	var out: Array = []
	if not _regions.has(region_id):
		return out
	for key in BaselineScript.WEATHER_DISASTER_ORDER:
		var d: Dictionary = BaselineScript.effective_disaster(key)
		var lo: int = int(d.get("warning_min_days", BaselineScript.WEATHER_DISASTER_WARNING_MIN_DAYS))
		var hi: int = int(d.get("warning_max_days", BaselineScript.WEATHER_DISASTER_WARNING_MAX_DAYS))
		for offset in range(lo, hi + 1):
			var event_day: int = day + offset
			if _disaster_triggers(region_id, key, event_day):
				out.append({
					"key": key,
					"name": str(d.get("name", key)),
					"event_day": event_day,
					"days_until": offset,
					"message": "预警：未来 %d 日可能发生%s。" % [offset, str(d.get("name", key))],
				})
				break
	return out

func _disaster_triggers(region_id: String, disaster_key: String, day: int) -> bool:
	var d: Dictionary = BaselineScript.effective_disaster(disaster_key)
	if d.is_empty():
		return false
	var annual: float = float(d.get("annual_rate", 0.0))
	if annual <= 0.0:
		return false
	var zone: String = zone_of(region_id)
	var zones: Array = d.get("zones", [])
	if zones.size() > 0 and not zones.has(zone):
		return false
	var seasons: Array = d.get("seasons", [])
	if seasons.size() > 0:
		var season: String = _season_key(day)
		if not seasons.has(season):
			return false
	var p_day: float = annual / BaselineScript.WEATHER_DAYS_PER_YEAR
	var roll: float = _rng_for(region_id + ":" + disaster_key, day, _SALT_DISASTER).next_float()
	return roll < p_day


# --- 内部：马尔可夫链与权重 ---

func _anchor(rw: RegionWeather, day: int) -> void:
	rw.initialized = true
	rw.last_day = day
	rw.last_condition = _sample_initial(rw.zone, day)
	rw.history[day] = rw.last_condition

func _sample_initial(zone_key: String, day: int) -> String:
	var rng = RngScript.new(_seed_for(zone_key, day, _SALT_INITIAL))
	return _pick_weighted(_season_weights(zone_key, day), rng)

func _next_condition(zone_key: String, day: int, current: String) -> String:
	var weights: Array = _season_weights(zone_key, day)
	var cur_idx: int = BaselineScript.WEATHER_STATE_ORDER.find(current)
	if cur_idx < 0:
		cur_idx = 0
	var rng = RngScript.new(_seed_for(zone_key, day, _SALT_MARKOV))
	# 一阶马尔可夫链：转移概率正比于下一状态权重 × 延续因子（自持 > 同族 > 其他）。
	var total: float = 0.0
	var row: Array = []
	for j in range(weights.size()):
		var w: float = float(weights[j])
		if j == cur_idx:
			w *= BaselineScript.WEATHER_MARKOV_PERSISTENCE
		elif _same_family(BaselineScript.WEATHER_STATE_ORDER[cur_idx], BaselineScript.WEATHER_STATE_ORDER[j]):
			w *= BaselineScript.WEATHER_MARKOV_FAMILY_CONTINUITY
		row.append(w)
		total += w
	if total <= 0.0:
		return current
	var target: float = rng.next_float() * total
	var acc: float = 0.0
	for j in range(row.size()):
		acc += float(row[j])
		if target <= acc:
			return str(BaselineScript.WEATHER_STATE_ORDER[j])
	return str(BaselineScript.WEATHER_STATE_ORDER[row.size() - 1])

## 按气候带与季节为 20 个天气状态打分。
func _season_weights(zone_key: String, day: int) -> Array:
	var zone: Dictionary = BaselineScript.effective_zone(zone_key)
	var cal: Dictionary = GregorianScript.from_absolute_minutes(day * MINUTES_PER_DAY)
	var doy: int = _day_of_year(int(cal["year"]), int(cal["month"]), int(cal["day"]))
	var seasonal: float = sin(TAU * float(doy) / 365.25 + float(zone.get("phase", 0.0)))
	var warmth: float = float(zone.get("base_temp", 10.0)) + float(zone.get("amp_temp", 10.0)) * seasonal
	var wet_season: float = seasonal if bool(zone.get("monsoon", false)) else 0.0
	var wetness: float = clampf(float(zone.get("precip_scale", 2.0)) / 10.0 + wet_season * 0.2, 0.0, 1.5)
	var aridity: float = clampf(float(zone.get("arid", 0.0)), 0.0, 1.0)
	var factors: Dictionary = {
		"dry": clampf(1.0 - wetness, 0.0, 1.5) + aridity,
		"wet": wetness,
		"hot": clampf((warmth - 20.0) / 12.0, 0.0, 1.5),
		"cold": clampf((4.0 - warmth) / 14.0, 0.0, 1.5),
		"cloud": wetness,
		"wind": clampf(float(zone.get("wind", 3.0)) / 6.0, 0.0, 1.5),
	}
	var can_snow: bool = bool(zone.get("can_snow", false))
	var weights: Array = []
	for key in BaselineScript.WEATHER_STATE_ORDER:
		var st: Dictionary = BaselineScript.effective_weather_state(key)
		var w: float = 1.0
		var affinity: Dictionary = st.get("affinity", {})
		for fk in affinity.keys():
			w += float(affinity[fk]) * float(factors.get(fk, 0.0))
		if bool(st.get("snow", false)) and (not can_snow or warmth > BaselineScript.WEATHER_SNOW_TEMP_THRESHOLD):
			w *= 0.02
		if bool(st.get("freezing", false)) and warmth > BaselineScript.WEATHER_SNOW_TEMP_THRESHOLD:
			w *= 0.05
		if bool(st.get("dust", false)) and aridity < 0.4:
			w *= 0.1
		if bool(st.get("hot_gate", false)) and warmth < 15.0:
			w *= 0.05
		if bool(st.get("cold_gate", false)) and warmth > 10.0:
			w *= 0.05
		weights.append(maxf(w, BaselineScript.WEATHER_MIN_STATE_WEIGHT))
	return weights

func _pick_weighted(weights: Array, rng) -> String:
	var total: float = 0.0
	for w in weights:
		total += float(w)
	if total <= 0.0:
		return str(BaselineScript.WEATHER_STATE_ORDER[0])
	var target: float = rng.next_float() * total
	var acc: float = 0.0
	for i in range(weights.size()):
		acc += float(weights[i])
		if target <= acc:
			return str(BaselineScript.WEATHER_STATE_ORDER[i])
	return str(BaselineScript.WEATHER_STATE_ORDER[weights.size() - 1])

func _alternative_condition(region_id: String, day: int, truth: String) -> String:
	var weights: Array = _season_weights(zone_of(region_id), day)
	var truth_idx: int = BaselineScript.WEATHER_STATE_ORDER.find(truth)
	if truth_idx >= 0:
		weights[truth_idx] = 0.0
	return _pick_weighted(weights, _rng_for(region_id, day, _SALT_FORECAST))

func _same_family(a: String, b: String) -> bool:
	var sa: Dictionary = BaselineScript.effective_weather_state(a)
	var sb: Dictionary = BaselineScript.effective_weather_state(b)
	return str(sa.get("family", "")) == str(sb.get("family", ""))


# --- 内部：工具 ---

func _trim_history(rw: RegionWeather) -> void:
	if rw.history.size() <= BaselineScript.WEATHER_MAX_HISTORY_DAYS:
		return
	var days: Array = rw.history.keys()
	days.sort()
	var remove_count: int = days.size() - BaselineScript.WEATHER_MAX_HISTORY_DAYS
	for i in range(remove_count):
		rw.history.erase(days[i])

func _season_key(day: int) -> String:
	var cal: Dictionary = GregorianScript.from_absolute_minutes(day * MINUTES_PER_DAY)
	return _month_to_season(int(cal["month"]))

static func _month_to_season(month: int) -> String:
	if month >= 3 and month <= 5:
		return "spring"
	if month >= 6 and month <= 8:
		return "summer"
	if month >= 9 and month <= 11:
		return "autumn"
	return "winter"

static func _is_leap(year: int) -> bool:
	return (year % 4 == 0 and year % 100 != 0) or (year % 400 == 0)

static func _day_of_year(year: int, month: int, day: int) -> int:
	var cumulative: Array = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334]
	var doy: int = int(cumulative[clampi(month - 1, 0, 11)]) + day
	if month > 2 and _is_leap(year):
		doy += 1
	return doy

## 由区域标识派生随机种子：SplitMix64 使用有符号 64 位位模式，乘法溢出按补码回绕。
func _seed_for(key: String, day: int, salt: int) -> int:
	var h: int = _hash32(key)
	return (h << 32) ^ (day * 2654435761) ^ (salt * 2246822507) ^ _world_seed

func _rng_for(key: String, day: int, salt: int):
	return RngScript.new(_seed_for(key, day, salt))

## FNV-1a 32 位字符串散列，避免十六进制字面量超过 INT64_MAX。
static func _hash32(key: String) -> int:
	var h: int = 2166136261
	for i in range(key.length()):
		h = (h ^ key.unicode_at(i)) & 4294967295
		h = (h * 16777619) & 4294967295
	return h

## 确定性高斯扰动 N(0,σ)：Box-Muller 由日种子派生。
func _noise(key: String, day: int, salt: int, sigma: float) -> float:
	if sigma <= 0.0:
		return 0.0
	var rng = _rng_for(key, day, salt)
	var u1: float = maxf(1e-12, rng.next_float())
	var u2: float = rng.next_float()
	return sqrt(-2.0 * log(u1)) * cos(TAU * u2) * sigma
