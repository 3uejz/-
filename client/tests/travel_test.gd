extends "res://tests/test_base.gd"
## 旅行系统测试（任务 21；R54.4–R54.6、R28.4；design D14）。

const TravelScript = preload("res://sim/travel.gd")


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
	return "travel"


func run_tests() -> void:
	_test_catalog()
	_test_plan_booking()
	_test_daily_events()
	_test_finish()


func _test_catalog() -> void:
	var sys = TravelScript.new()
	check_eq(sys.destinations().size(), 12, "十二个目的地")
	check_eq(sys.transport_modes().size(), 5, "五种交通")
	check_eq(sys.lodging_options().size(), 4, "四档住宿")
	check(bool(sys.destination_info("paris")["visa_required"]), "出国需签证")
	check(not bool(sys.destination_info("ancient_town")["visa_required"]), "国内游免签")


func _test_plan_booking() -> void:
	var sys = TravelScript.new()
	var t: Dictionary = sys.plan_trip("tokyo", "flight", "hotel", 6, true)
	check(bool(t["ok"]), "规划成功")
	check_eq(int(t["nights"]), 6, "住宿夜数")
	check(bool(t["insured"]), "含保险")
	check(not bool(sys.plan_trip("bogus", "flight", "hotel", 3)["ok"]), "无效目的地")
	var b: Dictionary = sys.booking_cost("paris", "flight", 6)
	check_eq(int(b["transport_cost"]), 5700000, "往返机票成本")
	check(int(b["total_estimate"]) > int(b["transport_cost"]), "总预算含住宿开销")


func _test_daily_events() -> void:
	var sys = TravelScript.new()
	var t: Dictionary = sys.plan_trip("paris", "flight", "hotel", 6, false)
	var d: Dictionary = sys.daily_settlement(t, 1000000, FixedRng.new([0.0]))
	check_eq(str(d["event"]), "delay", "触发延误")
	check(int(d["extra_cost"]) > 0, "意外产生额外花费")
	check(not bool(d["covered_by_insurance"]), "未保险自担")
	var ti: Dictionary = sys.plan_trip("paris", "flight", "hotel", 6, true)
	var di: Dictionary = sys.daily_settlement(ti, 1000000, FixedRng.new([0.0]))
	check(int(di["extra_cost"]) < int(d["extra_cost"]), "保险降低损失")
	var normal: Dictionary = sys.daily_settlement(t, 1000000, FixedRng.new([0.9]))
	check_eq(str(normal["event"]), "", "无意外")


func _test_finish() -> void:
	var sys = TravelScript.new()
	var t: Dictionary = sys.plan_trip("paris", "flight", "hotel", 7, true)
	var f: Dictionary = sys.finish_trip(t)
	check(float(f["mood"]) > 0.0, "旅行提升心情")
	check(float(f["insight"]) > 0.0, "提升见识")
	check_eq((f["codex_entries"] as Array).size(), 3, "图鉴见闻条目")
