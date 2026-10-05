extends "res://tests/test_base.gd"
## 民事纠纷与诉讼测试（任务 19；R52；design D12）。

const CivilScript = preload("res://sim/civil.gd")


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
	return "civil"


func run_tests() -> void:
	_test_catalog()
	_test_settle()
	_test_litigate()
	_test_enforce()


func _test_catalog() -> void:
	var sys = CivilScript.new()
	check_eq(sys.types_count(), 9, "九类民事纠纷")
	for key in ["contract", "debt", "tort", "marital_property", "neighbor", "labor", "consumer", "property", "ip"]:
		check(CivilScript.DISPUTE_TYPES.has(key), "覆盖纠纷 %s" % key)
	check_eq(CivilScript.STAGES.size(), 4, "四阶段处理链")


func _test_settle() -> void:
	var sys = CivilScript.new()
	var claim: Dictionary = sys.new_claim("contract", 1000000, "p1", "d1")
	var n: Dictionary = sys.negotiate(claim, 3, FixedRng.new([0.0]))
	check(bool(n["settled"]), "协商达成和解")
	check(int(n["lawyer_cost"]) > 0, "律师费")
	var c2: Dictionary = sys.new_claim("debt", 500000, "p1", "d1")
	var m: Dictionary = sys.mediate(c2, 0, FixedRng.new([0.99]))
	check(not bool(m["settled"]), "调解未成")


func _test_litigate() -> void:
	var sys = CivilScript.new()
	var claim: Dictionary = sys.new_claim("tort", 1000000, "p1", "d1")
	var j: Dictionary = sys.litigate(claim, 0.9, 4, 1, FixedRng.new([0.0]))
	check(bool(j["won"]), "证据与律师优势胜诉")
	check(int(j["award"]) > 0, "获得判赔")
	check(int(j["cost"]) > 0, "律师成本")
	# 上诉翻案。
	var claim2: Dictionary = sys.new_claim("labor", 800000, "p1", "d1")
	var j2: Dictionary = {"won": false, "award": 0}
	var a: Dictionary = sys.appeal(claim2, j2, 5, FixedRng.new([0.0]))
	check(bool(a["overturned"]), "上诉翻案")


func _test_enforce() -> void:
	var sys = CivilScript.new()
	var j: Dictionary = {"won": true, "award": 1000000}
	var r: Dictionary = sys.enforce(j, 300000)
	check_eq(int(r["recovered"]), 300000, "执行回收")
	check(bool(r["execution_failure"]), "执行不能")
	check_eq(int(r["outstanding"]), 700000, "未执行余额")
	var d: Dictionary = sys.dishonest_restrictions({}, int(r["outstanding"]))
	check(bool(d["restricted"]), "失信限高限消")
	# 查封拍卖。
	var s: Dictionary = sys.seize_auction(500000, 700000)
	check_eq(int(s["seized"]), 500000, "查封拍卖回收")
