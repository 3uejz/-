extends "res://tests/test_base.gd"
## 跨语言一致性测试（GDScript 端）。读取 shared/consistency/vectors/，与 Go 端逐位比对。

const TOLERANCE: float = 1e-6

func _suite_name() -> String:
	return "consistency"

func run_tests() -> void:
	_test_rng_integer()
	_test_rng_float()
	_test_time()
	_test_population()
	_test_economy()
	_test_worldsim()

func _test_rng_integer() -> void:
	var data: Dictionary = load_json(vectors_path("rng.json"))
	if data.is_empty():
		return
	for case in data.get("integer_cases", []):
		var rng := SplitMix64.new(parse_u64(case["seed"]))
		for i in case["next3"].size():
			var got: int = rng.next_u64()
			var want: int = parse_u64(case["next3"][i])
			if got != want:
				_fail("rng int seed=%s idx=%d: got=%s want=%s" % [case["seed"], i, String.num_uint64(got), String.num_uint64(want)])

func _test_rng_float() -> void:
	var data: Dictionary = load_json(vectors_path("rng.json"))
	if data.is_empty():
		return
	for case in data.get("float_cases", []):
		var rng := SplitMix64.new(int(case["seed"]))
		for i in case["f64"].size():
			check_near(rng.next_float(), float(case["f64"][i]), TOLERANCE, "rng float seed=%s idx=%d" % [case["seed"], i])

func _test_time() -> void:
	var data: Dictionary = load_json(vectors_path("time.json"))
	if data.is_empty():
		return
	for case in data.get("cases", []):
		var got: Dictionary = Gregorian.from_absolute_minutes(int(case["absolute_minutes"]))
		var want: Dictionary = case["expected"]
		for key in want.keys():
			check_eq(got.get(key), want[key], "time %d.%s" % [case["absolute_minutes"], key])

func _test_population() -> void:
	var data: Dictionary = load_json(vectors_path("population.json"))
	if data.is_empty():
		return
	for case in data.get("cases", []):
		var got: float = Population.cohort_next(
			float(case["population"]), float(case["birth_rate"]),
			float(case["death_rate"]), float(case["migration_rate"]), float(case["minutes"]))
		check_near(got, float(case["expected_next"]), 0.001, "population minutes=%s" % case["minutes"])

func _test_economy() -> void:
	var data: Dictionary = load_json(vectors_path("economy.json"))
	if data.is_empty():
		return
	for case in data.get("cases", []):
		var got: float = PriceModel.gbm_next(
			float(case["S"]), float(case["mu"]), float(case["sigma"]), float(case["dt"]), float(case["Z"]))
		check_near(got, float(case["expected_next"]), 1e-4, "economy S=%s" % case["S"])

func _test_worldsim() -> void:
	var data: Dictionary = load_json(vectors_path("worldsim.json"))
	if data.is_empty():
		return
	var m := MacroSimulator.new(int(data["seed"]), int(data["population"]))
	var cases: Array = data.get("cases", [])
	for i in cases.size():
		var got: Dictionary = m.tick()
		var want: Dictionary = cases[i]
		check_eq(int(got["population"]), int(want["population"]), "worldsim q%d population" % (i + 1))
		check_eq(int(got["absolute_minutes"]), int(want["absolute_minutes"]), "worldsim q%d absolute_minutes" % (i + 1))
		check_eq(m.phase, String(want["phase"]), "worldsim q%d phase" % (i + 1))
		check_near(m.inflation, float(want["inflation_rate"]), 1e-9, "worldsim q%d inflation" % (i + 1))
		check_near(m.unemployment, float(want["unemployment_rate"]), 1e-9, "worldsim q%d unemployment" % (i + 1))
		check_near(m.base_rate, float(want["base_rate"]), 1e-9, "worldsim q%d base_rate" % (i + 1))
		check_near(m.price_index, float(want["price_index"]), 1e-9, "worldsim q%d price_index" % (i + 1))
		check_near(m.pmi, float(want["pmi"]), 1e-9, "worldsim q%d pmi" % (i + 1))
