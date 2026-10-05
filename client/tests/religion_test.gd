extends "res://tests/test_base.gd"
## 宗教系统测试（任务 20；R53.4–R53.5；design D13）。

const ReligionScript = preload("res://sim/religion.gd")


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
	return "religion"


func run_tests() -> void:
	_test_catalog()
	_test_join_ritual()
	_test_doctrine()
	_test_waver_convert()
	_test_clergy_tension()


func _test_catalog() -> void:
	var sys = ReligionScript.new()
	check_eq(sys.religions().size(), 8, "八类宗教/信仰")
	check((sys.info("islam")["dietary"] as Array).has("halal"), "伊斯兰清真饮食")


func _test_join_ritual() -> void:
	var sys = ReligionScript.new()
	var s: Dictionary = sys.new_membership()
	check_eq(str(s["religion"]), "none", "初始无宗教")
	check(not bool(sys.ritual(s, 1.0)["ok"]), "无宗教不可礼拜")
	check(bool(sys.join(s, "buddhism")["ok"]), "加入佛教")
	var r: Dictionary = sys.ritual(s, 1.0)
	check(bool(r["ok"]), "礼拜成功")
	check_near(float(s["devotion"]), 2.0, 0.001, "虔诚信度")
	check(float(r["stress"]) < 0.0, "降低压力")
	var c: Dictionary = sys.community_effect(s)
	check_eq(str(c["social_circle"]), "religious", "宗教社交圈")


func _test_doctrine() -> void:
	var sys = ReligionScript.new()
	var s: Dictionary = sys.new_membership()
	sys.join(s, "islam")
	check(not bool(sys.check_diet(s, "pork")["allowed"]), "穆斯林禁猪肉")
	check(bool(sys.check_diet(s, "chicken")["allowed"]), "允许鸡肉")
	var b: Dictionary = sys.new_membership()
	sys.join(b, "buddhism")
	check(not bool(sys.check_diet(b, "meat")["allowed"]), "佛教素食")
	var f: Dictionary = sys.observe_festival(b, 1, 1)
	check(bool(f["observing"]), "守节")


func _test_waver_convert() -> void:
	var sys = ReligionScript.new()
	var s: Dictionary = sys.new_membership()
	sys.join(s, "buddhism")
	var w: Dictionary = sys.waver(s, 60.0, FixedRng.new([0.0]))
	check(float(s["doubt"]) >= 60.0, "信仰动摇累积")
	check(bool(w["crisis"]), "触发信仰危机")
	var conv: Dictionary = sys.convert(s, "taoism")
	check(bool(conv["ok"]), "改宗")
	check_eq(str(s["religion"]), "taoism", "新信仰")
	check_eq(str(s["converted_from"]), "buddhism", "记录旧信仰")


func _test_clergy_tension() -> void:
	var sys = ReligionScript.new()
	var s: Dictionary = sys.new_membership()
	sys.join(s, "christianity")
	s["devotion"] = 150.0
	var p: Dictionary = sys.clergy_promote(s, FixedRng.new([0.0]))
	check(bool(p["promoted"]), "神职晋升")
	check_eq(int(s["clergy_rank"]), 1, "晋升执事")
	var folk: Dictionary = sys.new_membership()
	sys.join(folk, "folk")
	check(not bool(sys.clergy_promote(folk, FixedRng.new([0.0]))["ok"]), "民间信仰无神职")
	var t: Dictionary = sys.work_tension(s, 0.0)
	check(float(t["tension"]) > 0.0, "职场张力")
