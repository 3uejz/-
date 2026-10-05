extends "res://tests/test_base.gd"
## 犯罪指令、案底与通缉测试（任务 19；R22；design D12）。

const CrimeScript = preload("res://sim/crime.gd")


class FixedRng:
	var seq: Array
	var i: int = 0
	func _init(s: Array) -> void:
		seq = s
	func next_float() -> float:
		var v: float = float(seq[i % seq.size()])
		i += 1
		return v


func _suite_name() -> String:
	return "crime"


func run_tests() -> void:
	_test_catalog()
	_test_attempt()
	_test_record()
	_test_wanted_and_evade()


func _test_catalog() -> void:
	var sys = CrimeScript.new()
	check_eq(CrimeScript.CATEGORIES.size(), 3, "三类违法行为")
	check(sys.crimes_count() >= 10, "至少 10 种犯罪指令")
	for key in ["theft", "robbery", "fraud", "assault", "injury", "smuggling", "tax_evasion"]:
		check(CrimeScript.CRIMES.has(key), "覆盖犯罪 %s" % key)
	var c: Dictionary = CrimeScript.CRIMES["theft"]
	check(c.has("category") and c.has("penalty") and c.has("statute_years"), "犯罪字段齐全")


func _test_attempt() -> void:
	var sys = CrimeScript.new()
	var good: Dictionary = sys.attempt("theft", 20.0, FixedRng.new([0.0]))
	check(bool(good["success"]), "高技能成功")
	check(float(good["probability"]) > 0.5, "高成功率")
	var bad: Dictionary = sys.attempt("robbery", 0.0, FixedRng.new([0.99, 0.0]))
	check(not bool(bad["success"]), "低技能失败")
	check(bool(bad["detected"]), "失败常被察觉")


func _test_record() -> void:
	var sys = CrimeScript.new()
	var state: Dictionary = {}
	check(not sys.has_record(state), "初始无案底")
	sys.add_record(state, "theft", "r1", 0)
	sys.add_record(state, "fraud", "r1", 100)
	check(sys.has_record(state), "有案底")
	var e: Dictionary = sys.record_effects(state)
	check(float(e["employment_penalty"]) > 0.0, "就业惩罚")
	check(float(e["social_penalty"]) > 0.0, "社会惩罚")
	# 追诉期。
	check(not sys.statute_expired({"crime": "theft", "minute": 0}, 1440), "未过追诉期")
	check(sys.statute_expired({"crime": "theft", "minute": 0}, int(365.25 * 1440 * 10)), "已过追诉期")


func _test_wanted_and_evade() -> void:
	var sys = CrimeScript.new()
	var state: Dictionary = {}
	sys.add_wanted(state, "robbery", "r1", 2)
	check(bool(sys.is_wanted(state)), "被通缉")
	check_eq(sys.wanted_level(state, "r1"), 2, "通缉等级")
	# 潜逃。
	sys.flee(state, "r1", "r2")
	check_eq(sys.wanted_level(state, "r2"), 2, "潜逃转移通缉")
	# 改名降级。
	sys.change_name(state)
	check(sys.wanted_level(state, "r2") < 2, "改名降低追缉")
	# 自首。
	var s: Dictionary = sys.self_surrender(state, "r2")
	check(bool(s["ok"]), "自首成功")
	check(float(s["discount"]) > 0.0, "自首减刑")
	# 行贿。
	var b: Dictionary = sys.bribe(0.9, 5000000, FixedRng.new([0.0, 0.5]))
	check(bool(b["success"]), "行贿成功")
