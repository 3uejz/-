extends "res://tests/test_base.gd"
## 基础设施测试（任务 28.1；R62；design D18）。
## 覆盖：设施清单、账单逾期停用与缴费复通、中断抢修优先级、依赖行为、投资升级与老化维护。

const InfraScript = preload("res://sim/infrastructure.gd")


func _suite_name() -> String:
	return "infrastructure"


func run_tests() -> void:
	_test_facilities()
	_test_billing_suspend_restore()
	_test_incident_repair_priority()
	_test_dependency_effects()
	_test_invest_and_aging()


func _test_facilities() -> void:
	var sys = InfraScript.new()
	var warm: Dictionary = sys.new_city(1000000)
	check_eq((warm["facilities"] as Dictionary).size(), 6, "温带六类设施（无供暖）")
	var cold: Dictionary = sys.new_city(1000000, {"cold_zone": true})
	check_eq((cold["facilities"] as Dictionary).size(), 7, "寒带含供暖共七类")
	for t in InfraScript.FACILITY_TYPES:
		var f: Dictionary = (cold["facilities"] as Dictionary)[t]
		check(float(f["coverage"]) > 0.0, "覆盖为正: " + t)
		check(int(f["price"]) > 0, "价格为正: " + t)
		check(bool(f["active"]), "初始在线: " + t)


func _test_billing_suspend_restore() -> void:
	var sys = InfraScript.new()
	var city: Dictionary = sys.new_city(1000000)
	var b: Dictionary = sys.bill(city, "power", 6000)
	check_eq(int(b["due"]), 6000, "账单累计")
	# 宽限期内不停用。
	sys.tick_bills(city, 10.0)
	check(bool((city["accounts"] as Dictionary)["power"]["active"]), "宽限期内仍在线")
	# 超宽限期停用。
	sys.tick_bills(city, 25.0)
	check(not bool((city["accounts"] as Dictionary)["power"]["active"]), "逾期停用")
	check(not bool((city["facilities"] as Dictionary)["power"]["active"]), "设施停机")
	# 交付部分欠款不复通。
	var p1: Dictionary = sys.pay(city, "power", 3000)
	check(not bool(p1["restored"]), "未结清不复通")
	# 结清复通，收取手续费并扣信用。
	var credit0: float = float(city["credit"])
	var p2: Dictionary = sys.pay(city, "power", 3000)
	check(bool(p2["restored"]), "结清复通")
	check(int(p2["fee"]) > 0, "复通手续费")
	check(float(city["credit"]) < credit0, "复通扣信用")
	check(bool((city["facilities"] as Dictionary)["power"]["active"]), "设施恢复在线")


func _test_incident_repair_priority() -> void:
	var sys = InfraScript.new()
	var city: Dictionary = sys.new_city(1000000)
	var i1: Dictionary = sys.report_incident(city, "sanitation", "aging", 1.0, {"base_work": 10.0})
	var i2: Dictionary = sys.report_incident(city, "power", "disaster", 1.0, {"base_work": 10.0})
	check(bool(i1["ok"]) and bool(i2["ok"]), "中断事件建立")
	check(not bool((city["facilities"] as Dictionary)["power"]["active"]), "中断即停机")
	check(not bool(sys.report_incident(city, "power", "bogus", 1.0)["ok"]), "未知原因被拒")
	# 工日只够完成一项：电力优先（医院/工厂依赖）。
	var r: Dictionary = sys.repair(city, 10.5)
	check((r["completed"] as Array).has("power"), "电力优先抢修")
	check(not (r["completed"] as Array).has("sanitation"), "低优先级未完成")
	check(bool((city["facilities"] as Dictionary)["power"]["active"]), "抢修完成恢复在线")
	# 追加工日完成剩余。
	var r2: Dictionary = sys.repair(city, 100.0)
	check((r2["completed"] as Array).has("sanitation"), "补足工日完成剩余")
	check_eq(int(r2["pending"]), 0, "无未决事件")


func _test_dependency_effects() -> void:
	var sys = InfraScript.new()
	var city: Dictionary = sys.new_city(1000000)
	var full: Dictionary = sys.dependency_effects(city)
	check(bool(full["lighting"]) and bool(full["cooking"]), "全在线时依赖正常")
	# 停水断电断网停运。
	sys.suspend(city, "power", "test")
	sys.suspend(city, "water", "test")
	sys.suspend(city, "telecom", "test")
	sys.suspend(city, "transit", "test")
	var eff: Dictionary = sys.dependency_effects(city)
	check(not bool(eff["lighting"]), "停电失去照明")
	check(not bool(eff["cold_storage"]), "停电失去冷藏")
	check(float(eff["production"]) < 1.0, "停电影响生产")
	check(not bool(eff["cooking"]), "停水失去烹饪")
	check(not bool(eff["network"]), "断网失去网络")
	check(not bool(eff["commute"]), "公交中断影响通勤")


func _test_invest_and_aging() -> void:
	var sys = InfraScript.new()
	var city: Dictionary = sys.new_city(1000000)
	var c0: float = float((city["facilities"] as Dictionary)["power"]["coverage"])
	var inv: Dictionary = sys.invest(city, "power", 1000000)
	check(float(inv["coverage"]) > c0, "投资提升覆盖")
	check(float(inv["population_attraction"]) > 1.0, "投资提升人口吸引力")
	var rel0: float = float((city["facilities"] as Dictionary)["power"]["reliability"])
	var ag: Dictionary = sys.age_maintenance(city, 20.0)
	check(float((city["facilities"] as Dictionary)["power"]["reliability"]) < rel0, "老化降低可靠性")
	check(float(ag["maintenance_pressure"]) > 0.0, "老化累积维护压力")
