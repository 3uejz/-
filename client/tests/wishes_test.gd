extends "res://tests/test_base.gd"
## 人生愿望测试（任务 22；R30）。

const WishScript = preload("res://sim/wishes.gd")


func _suite_name() -> String:
	return "wishes"


func run_tests() -> void:
	_test_limit()
	_test_track_complete()
	_test_replace()


func _test_limit() -> void:
	var sys = WishScript.new()
	var s: Dictionary = sys.new_state()
	check_eq(sys.available_slots(s), 3, "初始三槽")
	check(bool(sys.set_wish(s, "w1", "wealth", "赚到 100 万", 100000000.0)["ok"]), "第一个愿望")
	check(bool(sys.set_wish(s, "w2", "career", "当上经理", 3.0)["ok"]), "第二个愿望")
	check(bool(sys.set_wish(s, "w3", "travel", "环游世界", 5.0)["ok"]), "第三个愿望")
	var fourth: Dictionary = sys.set_wish(s, "w4", "custom", "长命百岁", 100.0)
	check_eq(str(fourth["reason"]), "wish_limit_reached", "最多三个")
	check(not bool(sys.set_wish(s, "bad", "bogus", "x", 1.0)["ok"]), "未知类型")


func _test_track_complete() -> void:
	var sys = WishScript.new()
	var s: Dictionary = sys.new_state()
	sys.set_wish(s, "w1", "wealth", "赚到 100 万", 100000000.0)
	var p: Dictionary = sys.update_progress(s, "wealth", 50000000.0)
	check((p["completed"] as Array).is_empty(), "未达标不完成")
	var p2: Dictionary = sys.update_progress(s, "wealth", 100000000.0)
	check((p2["completed"] as Array).has("w1"), "达标完成")
	check((sys.celebrations(s) as Array).size() == 1, "达成庆祝")


func _test_replace() -> void:
	var sys = WishScript.new()
	var s: Dictionary = sys.new_state()
	sys.set_wish(s, "w1", "wealth", "赚到 100 万", 100000000.0)
	sys.set_wish(s, "w2", "career", "当上经理", 3.0)
	sys.set_wish(s, "w3", "travel", "环游世界", 5.0)
	sys.update_progress(s, "wealth", 100000000.0)
	check_eq(sys.available_slots(s), 1, "完成后释放槽位")
	var r: Dictionary = sys.set_wish(s, "w4", "custom", "长命百岁", 100.0)
	check(bool(r["ok"]), "设定新愿望")
	check_eq(sys.available_slots(s), 0, "新愿望占槽")
	var back: Dictionary = sys.from_dict(sys.to_dict(s))
	check_eq((back["wishes"] as Array).size(), 4, "序列化保留")
