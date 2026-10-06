extends "res://tests/test_base.gd"
## 新增迁移域数值基线跨语言对齐测试（任务 48.2）。
## 读取 shared/consistency/vectors/baseline_domains.json 的共享期望值，与生成常量逐值比对。

const TOLERANCE: float = 1e-9


func _suite_name() -> String:
	return "baseline_domains"


func run_tests() -> void:
	var data: Dictionary = load_json(vectors_path("baseline_domains.json"))
	if data.is_empty():
		return
	var domains: Dictionary = data.get("domains", {})
	var code: Dictionary = _code_values()
	for domain in domains.keys():
		check(code.has(domain), "代码可见域 %s" % domain)
		if not code.has(domain):
			continue
		var expected: Dictionary = domains[domain]
		for key in expected.keys():
			check((code[domain] as Dictionary).has(key), "%s.%s 常量存在" % [domain, key])
			if (code[domain] as Dictionary).has(key):
				_match((code[domain] as Dictionary)[key], expected[key], "%s.%s" % [domain, key])


func _code_values() -> Dictionary:
	return {
		"survival": {
			"HUNGER_DECAY_PER_MIN": Baseline.HUNGER_DECAY_PER_MIN,
			"THIRST_DECAY_PER_MIN": Baseline.THIRST_DECAY_PER_MIN,
			"CLEANLINESS_DECAY_PER_MIN": Baseline.CLEANLINESS_DECAY_PER_MIN,
			"SLEEP_DEBT_THRESHOLD": Baseline.SLEEP_DEBT_THRESHOLD,
			"MOOD_RECOVER_PER_HOUR": Baseline.MOOD_RECOVER_PER_HOUR,
			"LIFESPAN_BASE_YEARS": Baseline.LIFESPAN_BASE_YEARS,
			"DYING_HEALTH_THRESHOLD": Baseline.DYING_HEALTH_THRESHOLD,
			"ADDICTION_DEPENDENT_MIN": Baseline.ADDICTION_DEPENDENT_MIN,
			"NUTRITION_LIGHT_THRESHOLD": Baseline.NUTRITION_LIGHT_THRESHOLD,
		},
		"region": {
			"REGION_BIRTH_RATE_ANNUAL": Baseline.REGION_BIRTH_RATE_ANNUAL,
			"REGION_DEATH_RATE_ANNUAL": Baseline.REGION_DEATH_RATE_ANNUAL,
			"REGION_MIGRATION_RATE_ANNUAL": Baseline.REGION_MIGRATION_RATE_ANNUAL,
			"REGION_ECONOMY_GROWTH_ANNUAL": Baseline.REGION_ECONOMY_GROWTH_ANNUAL,
			"REGION_DAYS_PER_YEAR": Baseline.REGION_DAYS_PER_YEAR,
		},
		"geo_transport": {
			"EARTH_RADIUS_KM": Baseline.EARTH_RADIUS_KM,
			"GEO_MIN_TOTAL_LOCATIONS": Baseline.GEO_MIN_TOTAL_LOCATIONS,
			"TRANSPORT_CONGESTION_PEAK_FACTOR": Baseline.TRANSPORT_CONGESTION_PEAK_FACTOR,
			"TRANSPORT_TRANSFER_MINUTES_DEFAULT": Baseline.TRANSPORT_TRANSFER_MINUTES_DEFAULT,
			"TRANSPORT_MODE_ORDER": Baseline.TRANSPORT_MODE_ORDER,
		},
		"climate_weather": {
			"WEATHER_TEMP_MIN": Baseline.WEATHER_TEMP_MIN,
			"WEATHER_TEMP_MAX": Baseline.WEATHER_TEMP_MAX,
			"WEATHER_HUMIDITY_MAX": Baseline.WEATHER_HUMIDITY_MAX,
			"WEATHER_FORECAST_DAYS": Baseline.WEATHER_FORECAST_DAYS,
			"WEATHER_MARKOV_PERSISTENCE": Baseline.WEATHER_MARKOV_PERSISTENCE,
			"WEATHER_DAYS_PER_YEAR": Baseline.WEATHER_DAYS_PER_YEAR,
			"CLIMATE_ZONE_ORDER": Baseline.CLIMATE_ZONE_ORDER,
		},
		"era": {
			"ERA_COUNT": Baseline.ERA_COUNT,
		},
		"economy": {
			"MONEY_MINOR_SCALE": Baseline.MONEY_MINOR_SCALE,
			"FX_ANNUAL_VOLATILITY": Baseline.FX_ANNUAL_VOLATILITY,
			"PRICE_FLOOR_RATIO": Baseline.PRICE_FLOOR_RATIO,
			"PRICE_CEIL_RATIO": Baseline.PRICE_CEIL_RATIO,
			"TAX_CORPORATE_RATE": Baseline.TAX_CORPORATE_RATE,
			"TAX_VAT_RATE": Baseline.TAX_VAT_RATE,
			"LOTTERY_WIN_CHANCE": Baseline.LOTTERY_WIN_CHANCE,
			"MACRO_BASE_INFLATION": Baseline.MACRO_BASE_INFLATION,
			"GBM_DRIFT_DEFAULT": Baseline.GBM_DRIFT_DEFAULT,
			"BANK_CREDIT_START": Baseline.BANK_CREDIT_START,
		},
	}


func _match(got: Variant, want: Variant, label: String) -> void:
	if want is Array:
		check(got is Array, "%s 应为数组" % label)
		if not (got is Array):
			return
		check_eq((got as Array).size(), (want as Array).size(), "%s 数组长度" % label)
		for i in mini((got as Array).size(), (want as Array).size()):
			_match((got as Array)[i], (want as Array)[i], "%s[%d]" % [label, i])
	elif got is int:
		check_eq(int(got), int(want), label)
	elif got is float:
		check_near(float(got), float(want), TOLERANCE, label)
	else:
		check_eq(got, want, label)
