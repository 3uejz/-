extends "res://tests/test_base.gd"
## 消费者保护与产品质量测试（任务 35；R84；design D40）。
## 覆盖：退换货/三包/保修、举证责任、投诉渠道与平台推诿、维权路径与集体维权、
##       食安质量事故处罚与召回、商家声誉销量影响、职业打假与恶意索赔等边界。

const ConsumerScript = preload("res://sim/consumer_protection.gd")


func _suite_name() -> String:
	return "consumer_protection"


func run_tests() -> void:
	_test_tables()
	_test_return_three_guarantee_warranty()
	_test_complaint_and_burden()
	_test_dispute_resolution()
	_test_regulation_and_recall()
	_test_effects_and_boundaries()


func _test_tables() -> void:
	var sys = ConsumerScript.new()
	check_eq(sys.channel_keys().size(), 6, "六类维权渠道")
	check_eq(sys.incident_kinds().size(), 2, "两类质量事故")
	check_eq(str(sys.channel_names()["hotline_12315"]), "12315 投诉", "12315 渠道名")


func _test_return_three_guarantee_warranty() -> void:
	var sys = ConsumerScript.new()
	# 质量原因不受七日限制。
	var bad: Dictionary = sys.new_order("o1", "m1", 10000, {"defective": true})
	var r1: Dictionary = sys.request_return(bad, 30, "no_reason", {})
	check(bool(r1["accepted"]) and bool(r1["quality"]), "缺陷商品可退货")
	check_eq(int(r1["refund"]), 10000, "全额退款")
	# 无理由超期被拒。
	var normal: Dictionary = sys.new_order("o2", "m1", 5000)
	check(not bool(sys.request_return(normal, 30, "no_reason", {})["accepted"]), "超七日无理由被拒")
	var fresh: Dictionary = sys.new_order("o3", "m1", 5000)
	check(bool(sys.request_return(fresh, 3, "no_reason", {})["accepted"]), "七日内可退")
	# 三包。
	var tg: Dictionary = sys.three_guarantee(sys.new_order("o4", "m1", 8000), 2, {})
	check(bool(tg["eligible"]), "两次维修仍故障可退换")
	check(not bool(sys.three_guarantee(sys.new_order("o5", "m1", 8000), 1, {})["eligible"]), "维修次数不足不可退换")
	# 保修。
	var p: Dictionary = sys.new_product("冰箱", {"warranty_days": 365, "price": 12000})
	var w1: Dictionary = sys.warranty_claim(p, 100, {})
	check(bool(w1["covered"]) and int(w1["fee"]) == 0, "质保期内免费维修")
	var w2: Dictionary = sys.warranty_claim(p, 400, {})
	check(not bool(w2["covered"]) and int(w2["fee"]) > 0, "超保收费维修")


func _test_complaint_and_burden() -> void:
	var sys = ConsumerScript.new()
	# 举证责任倒置：耐用商品短期瑕疵由商家举证。
	var durable: Dictionary = sys.new_order("d1", "m1", 20000, {"category": "electronics", "defective": true})
	var b1: Dictionary = sys.burden_of_proof(durable, 30, {})
	check(bool(b1["reversed"]) and str(b1["bearer"]) == "merchant", "耐用商品举证责任在商家")
	var general: Dictionary = sys.new_order("g1", "m1", 20000, {"category": "general"})
	check(str(sys.burden_of_proof(general, 30, {})["bearer"]) == "consumer", "一般商品由消费者举证")
	# 平台推诿。
	var cp: Dictionary = sys.file_complaint(general, "platform", {"platform_roll": 0.0, "platform_evade_risk": 0.5})
	check(bool(cp["platform_evade"]), "平台推诿")
	check(not bool(sys.file_complaint(general, "bogus", {})["ok"]), "未知渠道被拒")


func _test_dispute_resolution() -> void:
	var sys = ConsumerScript.new()
	var fake: Dictionary = sys.new_order("f1", "m1", 10000, {"fake": true})
	var merchant: Dictionary = {"reputation": 0.5, "sales": 1.0}
	var win: Dictionary = sys.resolve_dispute(fake, merchant, {"channel": "hotline_12315", "evidence": 0.9, "resolution_roll": 0.0})
	check(bool(win["success"]), "假货维权成功")
	check_eq(int(win["compensation"]), 30000, "假货三倍惩罚性赔偿")
	check(float(merchant["reputation"]) < 0.5, "胜诉拉低商家声誉")
	check_eq(int(merchant["compensation_paid"]), 30000, "商家赔付入账")
	var lose: Dictionary = sys.resolve_dispute(fake, merchant, {"channel": "negotiate", "evidence": 0.1, "resolution_roll": 0.999})
	check(not bool(lose["success"]), "高 roll 维权失败")
	# 集体维权。
	var orders: Array = []
	for i in 5:
		orders.append(sys.new_order("c%d" % i, "m1", 1000, {"defective": true}))
	var ca: Dictionary = sys.class_action(orders, merchant, {"resolution_roll": 0.0})
	check(bool(ca["success"]) and int(ca["compensation"]) > 0, "集体维权胜诉")


func _test_regulation_and_recall() -> void:
	var sys = ConsumerScript.new()
	var merchant: Dictionary = {"reputation": 0.8, "sales": 1.0}
	var inc: Dictionary = sys.regulate_incident(merchant, "food_safety", {"severity": 0.8, "victims": 3})
	check(int(inc["fine"]) > 0, "食安事故罚款")
	check(int(inc["compensation"]) > 0, "食安事故赔偿")
	check(bool(inc["delisted"]), "严重食安事故下架")
	check(float(merchant["reputation"]) < 0.8, "事故拉低声誉")
	var mild: Dictionary = sys.regulate_incident({"reputation": 0.8, "sales": 1.0}, "quality", {"severity": 0.1, "victims": 1})
	check(not bool(mild["delisted"]), "轻微质量事故不下架")
	var prod: Dictionary = sys.new_product("奶粉", {"price": 20000})
	var rec: Dictionary = sys.recall(prod, 1000, {"unit_cost": 5000})
	check(bool(rec["recalled"]) and int(rec["cost"]) == 5000000, "召回成本结算")


func _test_effects_and_boundaries() -> void:
	var sys = ConsumerScript.new()
	# 职业打假：合理维权受支持，批量索赔视为滥用。
	var fake: Dictionary = sys.new_order("f2", "m1", 10000, {"fake": true})
	var pf_ok: Dictionary = sys.professional_fraud(fake, {"claim_count": 1, "defect_confirmed": true})
	check(bool(pf_ok["success"]) and not bool(pf_ok["abusive"]), "合理职业打假受支持")
	var pf_bad: Dictionary = sys.professional_fraud(fake, {"claim_count": 50})
	check(bool(pf_bad["abusive"]) and not bool(pf_bad["success"]), "批量索赔判为滥用")
	# 恶意索赔。
	var clean: Dictionary = sys.new_order("c9", "m1", 5000)
	var merchant: Dictionary = {"reputation": 0.5}
	var mal: Dictionary = sys.malicious_claim(clean, merchant, {"detect_roll": 0.0, "detect_risk": 0.5})
	check(bool(mal["malicious"]) and bool(mal["detected"]), "恶意索赔被识别")
	# 平台推诿升级。
	var ev: Dictionary = sys.platform_buck_pass({"roll": 0.0, "evade_risk": 0.5})
	check(bool(ev["evaded"]) and str(ev["escalate_to"]) == "hotline_12315", "推诿升级 12315")
	# 商家影响。
	var m2: Dictionary = {"reputation": 0.5, "sales": 1.0}
	var e1: Dictionary = sys.merchant_effects(m2, "resolved", {})
	check(float(e1["reputation"]) < 0.5, "败诉降低商家声誉")
	var m3: Dictionary = {"reputation": 0.5, "sales": 1.0}
	var e2: Dictionary = sys.merchant_effects(m3, "rejected", {})
	check(float(e2["reputation"]) > 0.5, "商家胜诉声誉回升")
