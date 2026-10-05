extends "res://tests/test_base.gd"
## 监狱生活与社会融入测试（任务 19；R23.4–R23.6、R52.4–R52.7；design D12）。

const PrisonScript = preload("res://sim/prison.gd")


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
	return "prison"


func run_tests() -> void:
	_test_inmate()
	_test_life()
	_test_reduction_parole()
	_test_escape_release()


func _test_inmate() -> void:
	var sys = PrisonScript.new()
	var imm: Dictionary = sys.new_inmate("老王", "theft", 365)
	check_eq(int(imm["days_remaining"]), 365, "刑期")
	check_eq(str(imm["gang"]), "none", "初始中立")
	check(not bool(imm["released"]), "初始未释放")


func _test_life() -> void:
	var sys = PrisonScript.new()
	var imm: Dictionary = sys.new_inmate("老王", "theft", 365)
	var lab: Dictionary = sys.labor(imm, 10.0)
	check_eq(int(lab["income"]), 5000, "劳动报酬")
	check(float(imm["behavior"]) > 50.0, "劳动提升表现")
	sys.visit(imm, "家人")
	check(float(imm["behavior"]) > 51.0, "探视提升表现")
	var fri: Dictionary = sys.interact(imm, {"name": "狱友"}, FixedRng.new([0.0]))
	check_eq(str(fri["event"]), "befriend", "结交狱友")
	check(bool(sys.join_gang(imm, "order")["ok"]), "加入帮派")
	check(not bool(sys.join_gang(imm, "bogus")["ok"]), "未知帮派")
	var v: Dictionary = sys.violation(imm)
	check_eq(int(v["violations"]), 1, "违纪记录")


func _test_reduction_parole() -> void:
	var sys = PrisonScript.new()
	var imm: Dictionary = sys.new_inmate("老王", "theft", 365)
	check(not bool(sys.reduce_sentence(imm, 10)["ok"]), "表现不足不减刑")
	imm["behavior"] = 80.0
	var r: Dictionary = sys.reduce_sentence(imm, 30)
	check(bool(r["ok"]), "表现良好减刑")
	check_eq(int(imm["days_remaining"]), 335, "刑期扣减")
	var p: Dictionary = sys.parole(imm, 0.6, FixedRng.new([0.0]))
	check(bool(p["granted"]), "假释获批")
	check(bool(imm["released"]), "假释即释放")


func _test_escape_release() -> void:
	var sys = PrisonScript.new()
	var imm: Dictionary = sys.new_inmate("老王", "theft", 100)
	var e: Dictionary = sys.attempt_escape(imm, 20.0, FixedRng.new([0.0]))
	check(bool(e["escaped"]), "越狱成功")
	check(not bool(sys.advance(imm, 10)["ok"]), "越狱后不推进")
	var imm2: Dictionary = sys.new_inmate("小李", "fraud", 10)
	var rel: Dictionary = sys.advance(imm2, 10)
	check(bool(rel["released"]), "刑满释放")
	check(not bool(sys.advance(imm2, 1)["ok"]), "释放后不推进")
	var re: Dictionary = sys.reintegrate(imm2, 0.0, FixedRng.new([0.99]))
	check(float(re["employment_discrimination"]) > 0.0, "就业歧视")
	check(float(re["recidivism_risk"]) > 0.0, "再犯风险")
