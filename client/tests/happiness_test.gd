extends "res://tests/test_base.gd"
## 幸福与意义感测试（任务 16；R44.7、R44.8；design D4）。

const HappinessScript = preload("res://sim/happiness.gd")


func _suite_name() -> String:
	return "happiness"


func run_tests() -> void:
	_test_formula()
	_test_meaning()
	_test_risk()
	_test_crisis()


func _test_formula() -> void:
	var sys = HappinessScript.new()
	check_near(sys.happiness({"relations": 100, "career": 100, "health": 100, "faith": 100, "meaning": 100}), 100.0, 1e-6, "满分")
	check_near(sys.happiness({"relations": 0, "career": 0, "health": 0, "faith": 0, "meaning": 0}), 0.0, 1e-6, "零分")
	var h: float = sys.happiness({"relations": 80, "career": 60, "health": 70, "faith": 50, "meaning": 40})
	check_near(h, 61.5, 1e-6, "加权公式")


func _test_meaning() -> void:
	var sys = HappinessScript.new()
	var m: float = sys.meaning_score({"pursuit": 80, "family": 60, "achievement": 40, "values_consistency": 100})
	check_near(m, 69.0, 1e-6, "意义感加权")
	# 未提供 meaning 时由四项推导。
	var r: Dictionary = sys.compute({"relations": 50, "career": 50, "health": 50, "faith": 50, "pursuit": 80, "family": 60, "achievement": 40, "values_consistency": 100})
	check_near(float(r["meaning"]), 69.0, 1e-6, "推导意义感")
	check(float(r["happiness"]) > 0.0, "推导幸福")
	# 写入 player。
	var player: Dictionary = {"attrs": {"psychological": {"happiness": 0.0, "meaning": 0.0}}}
	sys.update(player, {"relations": 100, "career": 100, "health": 100, "faith": 100, "meaning": 100})
	check_near(float(player["attrs"]["psychological"]["happiness"]), 100.0, 1e-6, "写回幸福")


func _test_risk() -> void:
	var sys = HappinessScript.new()
	check(not sys.is_long_term_low(20.0, 50.0, 10), "未达天数不算长期")
	check(sys.is_long_term_low(20.0, 50.0, 30), "长期低值")
	check(sys.disorder_risk_multiplier(20.0, 50.0, 30) > 1.0, "长期低值提升疾病权重")
	check_near(sys.disorder_risk_multiplier(60.0, 60.0, 0), 1.0, 1e-6, "正常无额外权重")
	check(sys.midlife_crisis_weight(45.0, 10.0, 10.0) > 0.0, "中年危机权重")
	check_near(sys.midlife_crisis_weight(30.0, 10.0, 10.0), 0.0, 1e-6, "非中年窗口无权重")


func _test_crisis() -> void:
	var sys = HappinessScript.new()
	check_eq(sys.crisis_event(10.0, 10.0), "existential_crisis", "双重极端触发存在危机")
	check_eq(sys.crisis_event(10.0, 50.0), "despair_crisis", "极端低幸福触发绝望危机")
	check_eq(sys.crisis_event(50.0, 10.0), "meaning_crisis", "极端低意义触发意义危机")
	check_eq(sys.crisis_event(50.0, 50.0), "", "正常无危机")
