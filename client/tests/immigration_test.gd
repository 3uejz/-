extends "res://tests/test_base.gd"
## 移民与国籍测试（任务 20；R53.6–R53.8、R25.3；design D13）。

const ImmScript = preload("res://sim/immigration.gd")


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
	return "immigration"


func run_tests() -> void:
	_test_catalog()
	_test_visa()
	_test_migrate_integrate()
	_test_naturalize_deport()
	_test_military()


func _test_catalog() -> void:
	var sys = ImmScript.new()
	check_eq(sys.countries().size(), 9, "九国档案")
	check_eq(sys.visa_types().size(), 5, "五类签证")
	check_eq((sys.country_info("US")["legal_system"] as String), "common_law", "普通法域")


func _test_visa() -> void:
	var sys = ImmScript.new()
	var s: Dictionary = sys.new_status("CN")
	check_eq(str(s["residence"]), "CN", "初始居留地")
	var f: Dictionary = sys.apply_visa(s, "work", {"funds": 0, "language": 10, "points": 0, "target": "US"})
	check(not bool(f["ok"]), "资金不足拒签")
	var l: Dictionary = sys.apply_visa(s, "work", {"funds": 1000000, "language": 10, "points": 0, "target": "US"})
	check_eq(str(l["reason"]), "language_below_requirement", "语言不足")
	var a: Dictionary = sys.apply_visa(s, "asylum", {"funds": 0, "language": 0, "points": 0, "persecution": false, "target": "US"})
	check_eq(str(a["reason"]), "no_persecution_claim", "庇护需受迫害")
	var ok: Dictionary = sys.apply_visa(s, "work", {"funds": 1000000, "language": 50, "points": 60, "target": "US"}, FixedRng.new([0.0]))
	check(bool(ok["granted"]), "符合条件获签")


func _test_migrate_integrate() -> void:
	var sys = ImmScript.new()
	var s: Dictionary = sys.new_status("CN")
	var m: Dictionary = sys.migrate(s, "US")
	check_eq(str(s["residence"]), "US", "迁居美国")
	check(float(m["language_barrier"]) > 0.0, "语言障碍")
	check_eq(str((m["jurisdiction"] as Dictionary)["legal_system"]), "common_law", "切换法域")
	s["language"] = {"en-US": 50.0}
	var m2: Dictionary = sys.migrate(s, "US")
	check_near(float(s["integration"]), 25.0, 0.001, "语言半通融入 25")
	sys.integrate(s, 100.0)
	check(float(s["integration"]) > 60.0, "融入提升")


func _test_naturalize_deport() -> void:
	var sys = ImmScript.new()
	var s: Dictionary = sys.new_status("CN")
	sys.migrate(s, "US")
	check(not bool(sys.naturalize(s)["ok"]), "年限不足不可入籍")
	sys.advance(s, 5.0)
	s["integration"] = 80.0
	var n: Dictionary = sys.naturalize(s)
	check(bool(n["ok"]), "满足条件入籍")
	check_eq(str(s["nationality"]), "US", "国籍变更")
	var s2: Dictionary = sys.new_status("CN")
	var d: Dictionary = sys.deportation_risk(s2, true)
	check(float(d["risk"]) > 0.3, "非法居留遣返风险")
	check(bool(d["at_risk"]), "高风险标记")


func _test_military() -> void:
	var sys = ImmScript.new()
	var s: Dictionary = sys.new_status("CN")
	sys.migrate(s, "DE")
	# 双重国籍 + 两国兵役 + 适龄男性。
	var c: Dictionary = sys.military_conflict(s, 20, "male")
	check(bool(c["conflict"]), "双重国籍兵役冲突")
	check(not bool(sys.military_conflict(s, 20, "female")["conflict"]), "女性无强制兵役")
