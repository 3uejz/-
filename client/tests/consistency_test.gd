extends "res://tests/test_base.gd"
## 跨语言一致性测试（GDScript 端）。读取 shared/consistency/vectors/，与 Go 端逐位比对。

const TOLERANCE: float = 1e-6

func _suite_name() -> String:
	return "consistency"

func run_tests() -> void:
	_test_rng_integer()
	_test_rng_float()
	_test_time()

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
