extends "res://tests/test_base.gd"
## 娱乐与兴趣测试（任务 21；R54.1–R54.3、R54.7；design D14）。

const EntScript = preload("res://sim/entertainment.gd")


func _suite_name() -> String:
	return "entertainment"


func run_tests() -> void:
	_test_catalog()
	_test_do_activity()
	_test_addiction_circle()
	_test_overspend()


func _test_catalog() -> void:
	var sys = EntScript.new()
	check(sys.activities_count() >= 100, "不少于 100 种娱乐")
	check_eq(EntScript.CATEGORIES.size(), 7, "七大类")
	for cat in EntScript.CATEGORIES:
		check(sys.by_category(cat).size() > 0, "类别 %s 非空" % cat)
	check_eq(sys.activities_count(), 123, "活动总数 123")


func _test_do_activity() -> void:
	var sys = EntScript.new()
	var r: Dictionary = sys.do_activity("video_game", 0, 0)
	check(bool(r["ok"]), "免费娱乐可执行")
	check_near(float(r["mood"]), 6.0, 0.001, "首次心情 +6")
	var r2: Dictionary = sys.do_activity("video_game", 1, 0)
	check(float(r2["mood"]) < 6.0, "重复衰减")
	check(float(r2["tolerance"]) < 1.0, "耐受下降")
	var poor: Dictionary = sys.do_activity("antique", 0, 0)
	check(not bool(poor["ok"]), "缺钱不可执行")
	check_eq(str(poor["reason"]), "insufficient_funds", "缺钱原因")


func _test_addiction_circle() -> void:
	var sys = EntScript.new()
	var a: Dictionary = sys.update_addiction(55.0, 0.1)
	check(bool(a["addicted"]), "累积上瘾")
	var c: Dictionary = sys.interest_circle("hiking")
	check(bool(c["social"]), "形成同好圈层")
	var s: Dictionary = sys.side_business("photography", 80.0)
	check(bool(s["available"]), "专精可转副业")
	check(int(s["monthly_income"]) > 0, "副业收入")


func _test_overspend() -> void:
	var sys = EntScript.new()
	check(bool(sys.overspend_risk(1000, 70.0)["problem"]), "负债或上瘾即风险")
	check(not bool(sys.overspend_risk(0, 0.0)["problem"]), "无风险")
