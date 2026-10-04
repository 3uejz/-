class_name Baseline
extends BaselineGenerated
## 全局数值基线的运行时访问层。
##
## 数值真源位于 shared/consistency/baseline/*.json；常量由 tools/genbaseline 生成到
## baseline_generated.gd，本类继承之，因此 Baseline.XXX 与 BaselineGenerated.XXX 等价。
## 本文件只保留远程配置覆盖逻辑与派生访问器；所有变量可由远程配置覆盖，
## 属性统一 clamp 到定义区间（见 .monkeycode/specs/life-text-sandbox/design.md 的 Numeric Models）。
##
## 修改默认数值请改 shared/consistency/baseline/*.json 后运行：
##   go run ./tools/genbaseline

static var _overrides: Dictionary = {}

## 应用远程配置覆盖（design.md：所有公式由远程配置覆盖默认值）。
## config 形如 {"ranges": {"skill": [0, 30]}, "relation_annual_decay_k": 0.04}。
static func apply_remote_config(config: Dictionary) -> void:
	_overrides = config.duplicate(true)

static func clear_overrides() -> void:
	_overrides = {}

## 取某属性的有效区间（远程覆盖优先）。
static func effective_range(key: String) -> Array:
	var override_ranges: Variant = _overrides.get("ranges", {})
	if override_ranges is Dictionary and override_ranges.has(key):
		return override_ranges[key]
	return ranges()[key]

static func effective_relation_decay_k() -> float:
	return float(_overrides.get("relation_annual_decay_k", RELATION_ANNUAL_DECAY_K))

## 取区域统计快进参数的有效值（远程覆盖优先）。
static func effective_region_param(key: String, default_value: float) -> float:
	return float(_overrides.get(key, default_value))

## 通用标量/字典参数覆盖（数值默认集中在 baseline，可被远程配置覆盖）。
static func effective_param(key: String, default_value: Variant) -> Variant:
	return _overrides.get(key, default_value)

## 与 shared/consistency/vectors/baseline.json 的 ranges 一一对应。
static func ranges() -> Dictionary:
	return RANGES.duplicate(true)

static func clamp_attribute(value: int) -> int:
	var r := effective_range("attribute")
	return clampi(value, int(r[0]), int(r[1]))

static func clamp_skill(value: int) -> int:
	var r := effective_range("skill")
	return clampi(value, int(r[0]), int(r[1]))

static func clamp_favor(value: int) -> int:
	var r := effective_range("favor")
	return clampi(value, int(r[0]), int(r[1]))

static func clamp_grudge(value: int) -> int:
	var r := effective_range("grudge")
	return clampi(value, int(r[0]), int(r[1]))

static func clamp_intimacy(value: int) -> int:
	var r := effective_range("intimacy")
	return clampi(value, int(r[0]), int(r[1]))

## 关系强度按闲置年数指数衰减：dim *= exp(-k * idle_years)。
static func apply_relation_decay(value: float, idle_years: float) -> float:
	return value * exp(-effective_relation_decay_k() * idle_years)

## 取某交通方式的有效定义（远程配置可覆盖单个字段，如 transport.walk.speed_kmh）。
static func effective_transport_mode(mode_key: String) -> Dictionary:
	var base: Dictionary = (TRANSPORT_MODES.get(mode_key, {}) as Dictionary).duplicate(true)
	if base.is_empty():
		return {}
	var override: Variant = _overrides.get("transport." + mode_key, null)
	if override is Dictionary:
		for key in (override as Dictionary).keys():
			base[key] = (override as Dictionary)[key]
	return base

## 取某交通方式的有效标量字段（远程覆盖优先）。
static func effective_transport_field(mode_key: String, field: String, default_value: Variant) -> Variant:
	var mode := effective_transport_mode(mode_key)
	return mode.get(field, default_value)

static func effective_earth_radius_km() -> float:
	return float(_overrides.get("earth_radius_km", EARTH_RADIUS_KM))

## 取某气候带的有效定义（远程配置可覆盖单字段，如 climate_zone.mediterranean.base_temp）。
static func effective_zone(zone_key: String) -> Dictionary:
	var base: Dictionary = (CLIMATE_ZONES.get(zone_key, {}) as Dictionary).duplicate(true)
	if base.is_empty():
		return {}
	_merge_override(base, "climate_zone." + zone_key)
	return base

## 取某天气状态的有效定义（远程配置可覆盖单字段，如 weather_state.fog.precip_mm）。
static func effective_weather_state(state_key: String) -> Dictionary:
	var base: Dictionary = (WEATHER_STATES.get(state_key, {}) as Dictionary).duplicate(true)
	if base.is_empty():
		return {}
	_merge_override(base, "weather_state." + state_key)
	return base

## 取某灾害的有效定义（远程配置可覆盖单字段，如 disaster.flood.annual_rate）。
static func effective_disaster(disaster_key: String) -> Dictionary:
	var base: Dictionary = (WEATHER_DISASTERS.get(disaster_key, {}) as Dictionary).duplicate(true)
	if base.is_empty():
		return {}
	_merge_override(base, "disaster." + disaster_key)
	return base

## 取某时代阶段的有效定义（整体可覆盖 era_definitions，单条可覆盖 era.<key>）。
static func effective_era(index: int) -> Dictionary:
	var defs: Variant = _overrides.get("era_definitions", ERA_DEFINITIONS)
	var list: Array = defs if defs is Array else ERA_DEFINITIONS
	if list.is_empty():
		return {}
	var i: int = clampi(index, 0, list.size() - 1)
	var base: Dictionary = (list[i] as Dictionary).duplicate(true)
	_merge_override(base, "era." + str(base.get("key", "")))
	return base

## 取完整的时代阶段列表（含远程覆盖：整体 era_definitions 优先，否则逐条合并 era.<key>）。
static func effective_era_definitions() -> Array:
	var defs: Variant = _overrides.get("era_definitions", null)
	if defs is Array and not (defs as Array).is_empty():
		return (defs as Array).duplicate(true)
	var out: Array = []
	for i in ERA_DEFINITIONS.size():
		out.append(effective_era(i))
	return out

## 把远程覆盖合并进目标字典。支持两种写法（见 remote-config.schema.json 点分键约定）：
##   1) 嵌套对象：{"climate_zone.mediterranean": {"base_temp": 18.0}}
##   2) 点分标量：{"climate_zone.mediterranean.base_temp": 18.0}
static func _merge_override(base: Dictionary, override_key: String) -> void:
	var override: Variant = _overrides.get(override_key, null)
	if override is Dictionary:
		for key in (override as Dictionary).keys():
			base[key] = (override as Dictionary)[key]
	var prefix: String = override_key + "."
	for k in _overrides.keys():
		var sk := str(k)
		if sk.begins_with(prefix):
			var field := sk.substr(prefix.length())
			if not field.contains("."):
				base[field] = _overrides[k]

# --- 经济辅助（远程覆盖优先）---

## 取经济标量参数：先查 "economy.<key>"，再退回跨域键，最后用默认值。
static func effective_economy_param(key: String, default_value: Variant) -> Variant:
	if _overrides.has("economy." + key):
		return _overrides["economy." + key]
	if _overrides.has(key):
		return _overrides[key]
	return default_value

## 取某货币的有效定义（远程可覆盖 currency.<code> 整体或点分字段）。
static func effective_currency(code: String) -> Dictionary:
	var base: Dictionary = (CURRENCIES.get(code, {}) as Dictionary).duplicate(true)
	if base.is_empty():
		return {}
	_merge_override(base, "currency." + code)
	return base

## 取某品类的价格弹性（支持点分键与技术/嵌套覆盖）。
static func effective_elasticity(category: String) -> float:
	for key in ["economy.elasticity." + category, "elasticity." + category]:
		if _overrides.has(key):
			return float(_overrides[key])
	for dict_key in ["economy", ""]:
		var block: Variant = _overrides.get(dict_key, null)
		if block is Dictionary and (block as Dictionary).has("elasticity"):
			var table: Variant = (block as Dictionary)["elasticity"]
			if table is Dictionary and (table as Dictionary).has(category):
				return float((table as Dictionary)[category])
	var key2: String = category if PRICE_ELASTICITY.has(category) else "daily"
	return float(PRICE_ELASTICITY.get(key2, 0.35))

## 取累进税表（整体可覆盖，支持 economy.tax_*_brackets 与扁平键）。
static func _effective_brackets(key: String, nested_key: String, defaults: Array) -> Array:
	for k in ["economy." + key, key]:
		if _overrides.has(k):
			var v: Variant = _overrides[k]
			if v is Array and not (v as Array).is_empty():
				return (v as Array).duplicate(true)
	var block: Variant = _overrides.get("economy", null)
	if block is Dictionary and (block as Dictionary).has(nested_key):
		var nv: Variant = (block as Dictionary)[nested_key]
		if nv is Array and not (nv as Array).is_empty():
			return (nv as Array).duplicate(true)
	return defaults.duplicate(true)

## 取个人所得税累进税表。
static func effective_income_brackets() -> Array:
	return _effective_brackets("tax_income_brackets", "tax_income_brackets", TAX_INCOME_BRACKETS)

## 取遗产税累进税表。
static func effective_inheritance_brackets() -> Array:
	return _effective_brackets("tax_inheritance_brackets", "tax_inheritance_brackets", TAX_INHERITANCE_BRACKETS)
