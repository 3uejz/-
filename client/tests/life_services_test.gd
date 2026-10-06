extends "res://tests/test_base.gd"
## 家庭与生活服务业测试（任务 39.1；R93；design D49）。
## 覆盖：背景核查与信任、相亲婚介配对、婚礼策划事故、家政/月嫂失职与盗窃、
## 宠物服务全链、服务纠纷与赔偿/法律后果、平台抽成、服务标准化、序列化往返。

const LifeScript = preload("res://sim/life_services.gd")


func _suite_name() -> String:
	return "life_services"


func run_tests() -> void:
	_test_background_check()
	_test_matchmaking()
	_test_wedding()
	_test_housekeeping()
	_test_pet_service()
	_test_incident_and_dispute()
	_test_platform_and_standardization()
	_test_serialization()


func _test_background_check() -> void:
	var sys = LifeScript.new()
	check_eq(sys.category_name("wedding"), "婚礼策划", "类别中文名")
	var p: Dictionary = sys.new_provider({"category": "maternity", "trust": 0.7})
	var flagged: Dictionary = sys.background_check(p, {"record_rate": 0.15, "roll": 0.0})
	check(bool(flagged["flagged"]), "低掷骰核查出记录")
	check(bool(flagged["criminal_record"]), "标记有案底")
	check_eq(str(p["background"]), "flagged", "背景状态标记")
	check(float(p["trust"]) < 0.7, "有案底降低信任")
	var clean: Dictionary = sys.background_check(sys.new_provider({"trust": 0.7}), {"record_rate": 0.15, "roll": 0.99})
	check(not bool(clean["flagged"]), "高掷骰背景清白")
	check_eq(str(clean["status"]), "clean", "背景清白状态")


func _test_matchmaking() -> void:
	var sys = LifeScript.new()
	var p: Dictionary = sys.new_provider({"category": "matchmaking"})
	var candidates: Array = [
		{"id": "a", "compatibility": 0.9, "wealth": 0.5},
		{"id": "b", "compatibility": 0.3},
	]
	var res: Dictionary = sys.matchmaking(p, candidates, {"threshold": 0.5, "roll": 0.0})
	check(bool(res["matched"]), "高兼容候选配对成功")
	check_eq(str((res["match"] as Dictionary)["id"]), "a", "选择最优候选")
	check_near(float(res["score"]), 1.0, 1e-6, "最优评分")
	var no: Dictionary = sys.matchmaking(sys.new_provider({}), [], {})
	check(not bool(no["ok"]), "空候选池被拒")
	var low: Dictionary = sys.matchmaking(sys.new_provider({}), [{"id": "c", "compatibility": 0.2}], {"threshold": 0.5, "roll": 0.0})
	check(not bool(low["matched"]), "低兼容候选配对失败")


func _test_wedding() -> void:
	var sys = LifeScript.new()
	var p: Dictionary = sys.new_provider({"category": "wedding", "rating": 0.9, "trust": 0.9})
	var order: Dictionary = sys.new_order(p, {})["order"]
	var ok: Dictionary = sys.wedding_plan(p, order, {"budget": 100000, "roll": 0.999})
	check(not bool(ok["accident"]), "高评分高掷骰无事故")
	check_eq(int(ok["cost"]), 116000, "品质抬升成本")
	check_eq(str(order["status"]), "done", "婚礼完成")
	var bad_p: Dictionary = sys.new_provider({"category": "wedding", "rating": 0.0, "trust": 0.0})
	var bad_order: Dictionary = sys.new_order(bad_p, {})["order"]
	var bad: Dictionary = sys.wedding_plan(bad_p, bad_order, {"quality": 0.0, "roll": 0.0})
	check(bool(bad["accident"]), "低品质低信任触发婚礼事故")
	check(bool(bad_order["accident"]), "订单标记事故")


func _test_housekeeping() -> void:
	var sys = LifeScript.new()
	var good: Dictionary = sys.new_provider({"category": "housekeeping", "rating": 0.9, "trust": 0.9})
	var good_order: Dictionary = sys.new_order(good, {})["order"]
	var ok: Dictionary = sys.housekeeping_order(good, good_order, {"roll": 0.99})
	check_eq(str(ok["incident"]), "", "高信任服务无事故")
	var thief: Dictionary = sys.new_provider({"category": "housekeeping", "rating": 0.0, "trust": 0.0})
	var t_order: Dictionary = sys.new_order(thief, {})["order"]
	var theft: Dictionary = sys.housekeeping_order(thief, t_order, {"roll": 0.0})
	check_eq(str(theft["incident"]), "theft", "低信任触发家政盗窃")
	var bad: Dictionary = sys.new_provider({"category": "maternity", "rating": 0.0, "trust": 0.9})
	var b_order: Dictionary = sys.new_order(bad, {})["order"]
	var neg: Dictionary = sys.housekeeping_order(bad, b_order, {"roll": 0.35})
	check_eq(str(neg["incident"]), "negligence", "低评分触发月嫂失职")


func _test_pet_service() -> void:
	var sys = LifeScript.new()
	var p: Dictionary = sys.new_provider({"category": "pet", "rating": 0.9})
	var order: Dictionary = sys.new_order(p, {"service": "boarding"})["order"]
	var res: Dictionary = sys.pet_service_order(p, order, {"roll": 0.99})
	check(bool(res["completed"]), "宠物寄养完成")
	check(not bool(res["incident"]), "高评分无事故")
	var funeral: Dictionary = sys.new_order(p, {"service": "funeral"})["order"]
	check(bool(sys.pet_service_order(p, funeral, {"roll": 0.99})["completed"]), "宠物殡葬服务可用")
	var bad: Dictionary = sys.new_order(p, {"service": "nope"})["order"]
	check(not bool(sys.pet_service_order(p, bad, {"roll": 0.0})["ok"]), "未知宠物服务被拒")


func _test_incident_and_dispute() -> void:
	var sys = LifeScript.new()
	var p: Dictionary = sys.new_provider({"category": "wedding", "rating": 0.8, "trust": 0.8})
	var order: Dictionary = sys.new_order(p, {})["order"]
	var hit: Dictionary = sys.service_incident(p, order, {"severity": 0.8, "roll": 0.0})
	check(bool(hit["occurred"]), "低掷骰发生服务事故")
	check_eq((p["disputes"] as Array).size(), 1, "纠纷入册")
	check(float(p["rating"]) < 0.8, "事故打击评分")
	var none: Dictionary = sys.service_incident(p, order, {"roll": 0.99})
	check(not bool(none["occurred"]), "高掷骰无事故")
	# 纠纷处理：高严重度上升法律后果。
	var legal: Dictionary = sys.resolve_dispute(p, order, {"severity": 0.8, "claim": 10000})
	check(bool(legal["complaint"]), "产生投诉")
	check_eq(int(legal["compensation"]), 9000, "按严重度裁赔偿")
	check(bool(legal["legal"]), "严重纠纷上升法律")
	check_eq(str(order["status"]), "disputed", "订单转入纠纷")
	var light: Dictionary = sys.resolve_dispute(p, order, {"severity": 0.2, "claim": 10000})
	check(not bool(light["legal"]), "轻微纠纷不上升法律")
	check_eq(int(light["compensation"]), 6000, "轻微纠纷赔偿更少")


func _test_platform_and_standardization() -> void:
	var sys = LifeScript.new()
	var c: Dictionary = sys.platform_commission(1000, "delivery", {})
	check_eq(int(c["commission"]), 300, "代驾平台抽成 30%")
	check_eq(int(c["provider_received"]), 700, "服务者实收")
	var c2: Dictionary = sys.platform_commission(1000, "wedding", {"cut": 0.1})
	check_eq(int(c2["commission"]), 100, "显式抽成覆盖默认")
	var std: Dictionary = sys.standardization("pet", {"level": 0.5, "invest": 200000})
	check_near(float(std["risk_reduction"]), 0.15, 1e-6, "标准化降低风险")
	check(not bool(sys.standardization("nope", {})["ok"]), "未知类别标准化被拒")


func _test_serialization() -> void:
	var sys = LifeScript.new()
	var p: Dictionary = sys.new_provider({"category": "repair", "rating": 0.4})
	sys.new_order(p, {"price": 500})
	var clone: Dictionary = sys.from_dict(sys.to_dict(p))
	check_eq(str(clone["category"]), "repair", "序列化类别往返")
	check_near(float(clone["rating"]), 0.4, 1e-9, "序列化评分往返")
	check_eq((clone["orders"] as Array).size(), 1, "序列化订单往返")
