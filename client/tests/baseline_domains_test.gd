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
		"epidemic": {
			"SEIR_BETA_REDUCTION_CAP": Baseline.SEIR_BETA_REDUCTION_CAP,
			"SEIR_SURGE_EXTRA_SLOPE": Baseline.SEIR_SURGE_EXTRA_SLOPE,
			"SEIR_BEDS_DIVISOR": Baseline.SEIR_BEDS_DIVISOR,
			"SEIR_DEFAULT_VACCINE_HESITANCY": Baseline.SEIR_DEFAULT_VACCINE_HESITANCY,
			"SEIR_POLICY_TRUST_PENALTY": Baseline.SEIR_POLICY_TRUST_PENALTY,
			"SEIR_IMMUNITY_WANE_RATE": Baseline.SEIR_IMMUNITY_WANE_RATE,
			"SEIR_ALERT_WATCH_PREVALENCE": Baseline.SEIR_ALERT_WATCH_PREVALENCE,
			"SEIR_ALERT_ALERT_OCCUPANCY": Baseline.SEIR_ALERT_ALERT_OCCUPANCY,
			"SEIR_ALERT_EMERGENCY_OCCUPANCY": Baseline.SEIR_ALERT_EMERGENCY_OCCUPANCY,
			"SEIR_DEFAULT_PARAMS": Baseline.SEIR_DEFAULT_PARAMS,
			"SEIR_POLICY_BETA_REDUCTION": Baseline.SEIR_POLICY_BETA_REDUCTION,
		},
		"environment": {
			"ENV_DEFAULT_CARBON_PRICE": Baseline.ENV_DEFAULT_CARBON_PRICE,
			"ENV_CARBON_FINE_MULTIPLIER": Baseline.ENV_CARBON_FINE_MULTIPLIER,
			"ENV_FOOTPRINT_SCOPE1": Baseline.ENV_FOOTPRINT_SCOPE1,
			"ENV_FOOTPRINT_SCOPE2": Baseline.ENV_FOOTPRINT_SCOPE2,
			"ENV_FOOTPRINT_SCOPE3": Baseline.ENV_FOOTPRINT_SCOPE3,
			"ENV_ESG_SCORE_MAX": Baseline.ENV_ESG_SCORE_MAX,
			"ENV_ESG_GRADE_A": Baseline.ENV_ESG_GRADE_A,
			"ENV_ESG_GRADE_B": Baseline.ENV_ESG_GRADE_B,
			"ENV_ESG_GRADE_C": Baseline.ENV_ESG_GRADE_C,
		},
		"engineering": {
			"ENGINEERING_ACCEPTANCE_QUALITY_THRESHOLD": Baseline.ENGINEERING_ACCEPTANCE_QUALITY_THRESHOLD,
			"ENGINEERING_CHAIN": Baseline.ENGINEERING_CHAIN,
			"ENGINEERING_ZONE_TYPES": Baseline.ENGINEERING_ZONE_TYPES,
		},
		"medical": {
			"MEDICAL_UNTREATED_FREE_DAYS": Baseline.MEDICAL_UNTREATED_FREE_DAYS,
			"MEDICAL_UNTREATED_HEALTH_DECAY_PER_DAY": Baseline.MEDICAL_UNTREATED_HEALTH_DECAY_PER_DAY,
			"MEDICAL_MISDIAGNOSIS_CHANCE": Baseline.MEDICAL_MISDIAGNOSIS_CHANCE,
			"MEDICAL_SERVICE_COST": Baseline.MEDICAL_SERVICE_COST,
		},
		"sports": {
			"SPORTS_PEAK_MIN_AGE": Baseline.SPORTS_PEAK_MIN_AGE,
			"SPORTS_PEAK_MAX_AGE": Baseline.SPORTS_PEAK_MAX_AGE,
			"SPORTS_AGE_DECLINE_RATE": Baseline.SPORTS_AGE_DECLINE_RATE,
			"SPORTS_AGE_FLOOR": Baseline.SPORTS_AGE_FLOOR,
			"SPORTS_TRAIN_RATE": Baseline.SPORTS_TRAIN_RATE,
			"SPORTS_INJURY_PENALTY": Baseline.SPORTS_INJURY_PENALTY,
			"SPORTS_INJURY_BASE_RISK": Baseline.SPORTS_INJURY_BASE_RISK,
			"SPORTS_DOPING_BOOST": Baseline.SPORTS_DOPING_BOOST,
			"SPORTS_DOPING_BAN_CHANCE": Baseline.SPORTS_DOPING_BAN_CHANCE,
		},
		"aesthetics": {
			"AESTHETICS_OVER_MEDICALIZATION_THRESHOLD": Baseline.AESTHETICS_OVER_MEDICALIZATION_THRESHOLD,
			"AESTHETICS_STIFFNESS_PER_PROCEDURE": Baseline.AESTHETICS_STIFFNESS_PER_PROCEDURE,
			"AESTHETICS_ILLEGAL_SUCCESS_MULT": Baseline.AESTHETICS_ILLEGAL_SUCCESS_MULT,
			"AESTHETICS_ILLEGAL_COMPLICATION_MULT": Baseline.AESTHETICS_ILLEGAL_COMPLICATION_MULT,
			"AESTHETICS_MALPRACTICE_COMPENSATION": Baseline.AESTHETICS_MALPRACTICE_COMPENSATION,
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
	elif want is Dictionary:
		check(got is Dictionary, "%s 应为字典" % label)
		if not (got is Dictionary):
			return
		var gd: Dictionary = got
		for key in (want as Dictionary).keys():
			check(gd.has(key), "%s.%s 存在" % [label, key])
			if gd.has(key):
				_match(gd[key], (want as Dictionary)[key], "%s.%s" % [label, key])
	elif got is int:
		check_eq(int(got), int(want), label)
	elif got is float:
		check_near(float(got), float(want), TOLERANCE, label)
	else:
		check_eq(got, want, label)
