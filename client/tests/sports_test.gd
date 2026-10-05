extends "res://tests/test_base.gd"
## 体育生涯测试（任务 14；R45.7；design D5、D32）。
## 覆盖：运动员状态、年龄窗口、训练提升与伤病、赛事名次与奖金、兴奋剂与药检禁赛。

const SportsScript = preload("res://sim/sports.gd")
const RngScript = preload("res://sim/rng.gd")
const BaselineScript = preload("res://sim/baseline.gd")


func _suite_name() -> String:
	return "sports"


func run_tests() -> void:
	BaselineScript.clear_overrides()
	_test_athlete_and_age()
	_test_training()
	_test_compete()
	_test_doping()
	BaselineScript.clear_overrides()


func _test_athlete_and_age() -> void:
	var sys = SportsScript.new()
	check_eq(SportsScript.SPORTS.size(), 5, "五个体育项目")
	var a: Dictionary = sys.new_athlete("track")
	check_eq(str(a["sport"]), "track", "项目写入")
	check_near(float(a["physique"]), 50.0, 1e-6, "初始体能")
	check_near(sys.age_factor(25.0), 1.0, 1e-6, "25 岁巅峰")
	check_near(sys.age_factor(28.0), 1.0, 1e-6, "28 岁前仍巅峰")
	check(sys.age_factor(30.0) < 1.0, "超龄衰减")
	check(sys.age_factor(16.0) < 1.0, "未达巅峰")
	check(sys.age_factor(60.0) >= SportsScript.AGE_FLOOR, "衰减有下限")


func _test_training() -> void:
	var sys = SportsScript.new()
	var a: Dictionary = sys.new_athlete("swimming")
	var r: Dictionary = sys.train(a, 10.0, 25.0, null, {"intensity": 0.0})
	check(bool(r["ok"]), "训练成功")
	check_near(float(a["physique"]), 50.0 + 10.0 * SportsScript.TRAIN_RATE * 1.0 * 0.5, 1e-6, "体能提升")
	check_near(float(a["technique"]), 50.0 + 10.0 * SportsScript.TRAIN_RATE * 1.0 * 0.5, 1e-6, "技术提升")
	check(not bool(r["injured"]), "零强度不受伤")
	# 伤病风险随强度与年龄上升。
	var young: Dictionary = sys.new_athlete("combat")
	check(sys.injury_risk(young, 25.0, 10.0) > sys.injury_risk(young, 25.0, 0.5), "强度提升风险")
	check(sys.injury_risk(young, 40.0, 1.0) > sys.injury_risk(young, 25.0, 1.0), "超龄提升风险")
	# 高强训练最终受伤（确定性遍历种子）。
	var rng = RngScript.new(0)
	var risky: Dictionary = sys.new_athlete("combat")
	var injured: bool = false
	for i in 30:
		if bool(sys.train(risky, 1.0, 40.0, rng, {"intensity": 100.0})["injured"]):
			injured = true
			break
	check(injured, "高强训练会受伤")
	check(int(risky["injuries"]) >= 1, "伤病计数")


func _test_compete() -> void:
	var sys = SportsScript.new()
	var strong: Dictionary = sys.new_athlete("track")
	strong["physique"] = 100.0
	strong["technique"] = 100.0
	var r: Dictionary = sys.compete(strong, null, {"age": 25})
	check(bool(r["ok"]), "参赛成功")
	check(int(r["rank"]) <= 3, "满实力名列前茅")
	check(int(r["prize"]) > 0, "获得奖金")
	check_eq(int(strong["prize_total"]), int(r["prize"]), "奖金累加")
	var weak: Dictionary = sys.new_athlete("ball")
	weak["physique"] = 10.0
	weak["technique"] = 10.0
	var rw: Dictionary = sys.compete(weak, null, {"age": 40})
	check(int(rw["rank"]) > int(r["rank"]), "弱选手名次靠后")


func _test_doping() -> void:
	var sys = SportsScript.new()
	var a: Dictionary = sys.new_athlete("combat")
	check(not bool(sys.doping_test(a, null)["positive"]), "未用药药检阴性")
	sys.take_doping(a)
	check(bool(a["doping"]), "用药标记")
	var rng = RngScript.new(1)
	var positive: bool = false
	for i in 30:
		if bool(sys.doping_test(a, rng)["positive"]):
			positive = true
			break
	check(positive, "药检最终阳性")
	check(bool(a["banned"]), "阳性禁赛")
	check_eq(str(sys.train(a, 1.0, 25.0, null)["reason"]), "banned", "禁赛不可训练")
