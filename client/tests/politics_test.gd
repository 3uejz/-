extends "res://tests/test_base.gd"
## 从政路径测试（任务 20；R53.1–R53.3、R25；design D13）。

const PoliticsScript = preload("res://sim/politics.gd")


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
	return "politics"


func run_tests() -> void:
	_test_catalog()
	_test_enter_campaign()
	_test_promote()
	_test_policy_game()
	_test_corruption()


func _test_catalog() -> void:
	var sys = PoliticsScript.new()
	check_eq(sys.tier_count(), 5, "五级职级")
	check_eq(PoliticsScript.FACTIONS.size(), 3, "三派系")
	check_eq(sys.tier_name(0), "村/社区", "基层名称")
	check_eq(sys.tier_name(99), "平民", "越界为平民")


func _test_enter_campaign() -> void:
	var sys = PoliticsScript.new()
	var c: Dictionary = sys.new_career()
	check_eq(int(c["tier"]), -1, "初始未从政")
	check(not bool(sys.enter(c, 0.0, 0.0, 10)["ok"]), "未成年不可从政")
	check(bool(sys.enter(c, 0.0, 0.0, 18)["ok"]), "成年入基层")
	check(bool(c["in_office"]), "在任")
	c["reputation"] = 80.0
	c["network"] = 60.0
	var win: Dictionary = sys.campaign(c, FixedRng.new([0.0]))
	check(bool(win["won"]), "高声望当选")


func _test_promote() -> void:
	var sys = PoliticsScript.new()
	var c: Dictionary = sys.new_career()
	sys.enter(c, 30.0, 25.0, 30)
	c["achievements"] = 50.0
	check(not bool(sys.promote(c, 20, FixedRng.new([0.0]))["ok"]), "年龄不足不晋升")
	var p: Dictionary = sys.promote(c, 30, FixedRng.new([0.0]))
	check(bool(p["promoted"]), "满足条件晋升")
	check_eq(int(c["tier"]), 1, "升至街道/区")


func _test_policy_game() -> void:
	var sys = PoliticsScript.new()
	var c: Dictionary = sys.new_career()
	sys.enter(c, 30.0, 30.0, 30)
	var r: Dictionary = sys.policy_game(c, "propose", 0.8, 0.1, FixedRng.new([0.0]))
	check(bool(r["passed"]), "提案通过")
	check(float(c["achievements"]) > 0.0, "累积政绩")
	check(not bool(sys.policy_game(c, "bogus", 1.0, 0.0)["ok"]), "未知政策动作")
	var empty: Dictionary = sys.new_career()
	check(not bool(sys.policy_game(empty, "vote", 1.0, 0.0)["ok"]), "非在任不可博弈")


func _test_corruption() -> void:
	var sys = PoliticsScript.new()
	var c: Dictionary = sys.new_career()
	sys.enter(c, 30.0, 30.0, 30)
	c["corruption"] = 100.0
	var s: Dictionary = sys.check_scandal(c, FixedRng.new([0.0]))
	check(bool(s["caught"]), "腐败被查处")
	check(bool(s["criminal"]), "接入刑事系统")
	c["faction"] = "reform"
	var m: Dictionary = sys.policy_modifiers(c)
	check(float(m["tax"]) < 0.0, "改革派减税")
	check(bool(sys.retire(c)["ok"]), "卸任")
	check(not bool(c["in_office"]), "已卸任")
