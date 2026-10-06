extends "res://tests/test_base.gd"
## 国际贸易、海关与物流测试（任务 32；R71；design D27）。
## 覆盖：数据表、关税/增值税结算（关键点二）、汇率换算可复现、
##       运输方式、Incoterms/结算、贸易壁垒与风险事件、跨境服务、边界损失。

const TradeScript = preload("res://sim/trade.gd")


func _suite_name() -> String:
	return "trade"


func run_tests() -> void:
	_test_tables()
	_test_duty_settlement()
	_test_fx_reproducible()
	_test_transport_modes()
	_test_incoterms_and_settlement()
	_test_barriers_and_risks()
	_test_services_and_edges()


func _test_tables() -> void:
	var sys = TradeScript.new()
	check_eq(TradeScript.STAGES.size(), 7, "七步贸易流程")
	check_eq(sys.transport_modes().size(), 5, "五种运输方式")
	check_eq(TradeScript.INCOTERMS.size(), 6, "六种贸易术语")
	check_eq(TradeScript.SETTLEMENTS.size(), 4, "四种结算方式")
	check_eq(str(TradeScript.STAGE_NAMES["clearance"]), "清关", "清关阶段名称")


# 任务 32.1 关键点二：关税结算。
func _test_duty_settlement() -> void:
	var sys = TradeScript.new()
	var s: Dictionary = sys.new_shipment({
		"goods_value": 100000, "freight": 5000, "insurance": 1000,
		"tariff_rate": 0.08, "vat_rate": 0.13,
	})
	var d: Dictionary = sys.calculate_duties(s)
	# 完税价格 = 货值 + 运费 + 保险 + 其他费用。
	check_eq(int(d["dutiable_value"]), 106000, "完税价格 = 货值+运费+保险")
	check_eq(int(d["tariff"]), 8480, "关税 = 完税价 × 关税率")
	check_eq(int(d["vat"]), 14882, "增值税 = (完税价+关税) × 增值税率")
	check_eq(int(d["total_tax"]), 23362, "税费合计")
	check_eq(int(d["landed_cost"]), 129362, "落地成本可核对")
	# 金额为非负整数（最小货币单位）。
	check(float(d["tariff"]) == float(int(d["tariff"])), "关税为整数分")
	check(d["tariff"] >= 0 and d["vat"] >= 0 and d["landed_cost"] >= 0, "金额非负")
	check(bool(d["non_negative"]), "非负标记")
	# 总额可核对：落地成本 = 完税价 + 关税 + 增值税。
	check_eq(int(d["landed_cost"]), int(d["dutiable_value"]) + int(d["tariff"]) + int(d["vat"]), "落地成本恒等式")
	# 税率越高税费越高。
	var high: Dictionary = sys.calculate_duties(s, {"tariff_rate": 0.25})
	check(int(high["tariff"]) > int(d["tariff"]), "提高税率增加关税")
	# 零税率时只有增值税。
	var zero: Dictionary = sys.calculate_duties(s, {"tariff_rate": 0.0})
	check_eq(int(zero["tariff"]), 0, "零关税")
	check(int(zero["vat"]) > 0, "仍计增值税")
	# 报关落税写回单据。
	var declared: Dictionary = sys.declare_customs(s)
	check(bool(declared["ok"]) and str(s["stage"]) == "declaration", "报关写入阶段")
	check((s["duties"] as Dictionary).has("landed_cost"), "税单附于单据")


# 汇率换算可复现：同输入同输出。
func _test_fx_reproducible() -> void:
	var sys = TradeScript.new()
	var a: Dictionary = sys.convert(100000, "CNY", "USD")
	var b: Dictionary = sys.convert(100000, "CNY", "USD")
	check_eq(int(a["amount_out"]), int(b["amount_out"]), "汇率换算可复现")
	check_eq(int(a["amount_out"]), 14286, "CNY→USD 折算结果确定")
	check_near(float(a["rate"]), 1.0 / 7.0, 1e-9, "换算比率")
	var back: Dictionary = sys.convert(int(a["amount_out"]), "USD", "CNY")
	check(int(back["amount_out"]) > 0, "反向换汇成功")
	check(not bool(sys.convert(100, "CNY", "XXX")["ok"]), "未知币种被拒")
	# 汇率波动损益与对冲。
	var s: Dictionary = sys.new_shipment({"goods_value": 100000, "currency": "CNY"})
	var unhedged: Dictionary = sys.fx_loss(s, 8.0)
	check(int(unhedged["pnl"]) != 0, "未对冲承受汇率损益")
	sys.hedge_fx(s, 7.0)
	var hedged: Dictionary = sys.fx_loss(s, 8.0)
	check_eq(int(hedged["pnl"]), 0, "对冲后无汇率损失")
	var fee: Dictionary = sys.settlement_fee(100000, "letter_of_credit")
	check(int(fee["fee"]) > 0 and int(fee["net"]) < 100000, "信用证结算手续费")


func _test_transport_modes() -> void:
	var sys = TradeScript.new()
	var sea: Dictionary = sys.estimate_freight("sea", 100.0)
	check_eq(int(sea["freight"]), 200000, "海运 100 吨费用")
	check_near(float(sea["days"]), 30.0, 1e-9, "海运时效")
	check(not bool(sea["over_capacity"]), "未超容量")
	var air: Dictionary = sys.estimate_freight("air", 100.0)
	check(int(air["freight"]) > int(sea["freight"]), "空运更贵")
	check(float(air["days"]) < float(sea["days"]), "空运更快")
	var over: Dictionary = sys.estimate_freight("express", 100.0)
	check(bool(over["over_capacity"]) and not bool(over["ok"]), "快递超容量")
	check(not bool(sys.estimate_freight("bogus", 1.0)["ok"]), "未知运输方式被拒")


func _test_incoterms_and_settlement() -> void:
	var sys = TradeScript.new()
	var ddp: Dictionary = sys.incoterm_duties("DDP")
	check(bool(ddp["freight"]) and bool(ddp["insurance"]) and bool(ddp["duty"]), "DDP 卖方全责")
	var exw: Dictionary = sys.incoterm_duties("EXW")
	check(not bool(exw["duty"]), "EXW 买方清关")
	check(not sys.settlement_def("bogus").has("fee_rate"), "未知结算方式无定义")
	check(float((sys.settlement_def("letter_of_credit") as Dictionary)["risk"]) < float((sys.settlement_def("open_account") as Dictionary)["risk"]), "信用证风险低于赊销")


func _test_barriers_and_risks() -> void:
	var sys = TradeScript.new()
	var s: Dictionary = sys.new_shipment({"goods_value": 100000, "quantity_ton": 100.0, "tariff_rate": 0.08})
	var t: Dictionary = sys.apply_barrier(s, "tariff", {"add_rate": 0.1})
	check(float(s["tariff_rate"]) > 0.08, "关税壁垒加税")
	check(bool(t["ok"]), "壁垒施加成功")
	var quota: Dictionary = sys.apply_barrier(s, "quota", {"limit": 50.0})
	check(bool(quota["exceeds_quota"]), "超配额判定")
	sys.apply_barrier(s, "anti_dumping", {"add_rate": 0.3})
	check(float(s["anti_dumping_rate"]) > 0.0, "反倾销税率")
	var origin: Dictionary = sys.apply_barrier(s, "origin", {"certificate": false})
	check(not bool(origin["certificate_ok"]), "缺原产地证")
	check(not bool(sys.apply_barrier(s, "bogus")["ok"]), "未知壁垒被拒")
	var war: Dictionary = sys.risk_event(s, "trade_war")
	check(float(war["delay_days"]) > 0.0 and int(war["extra_cost"]) > 0, "贸易战加税滞留")
	check(float(s["tariff_rate"]) > 0.18, "贸易战进一步加税")
	var sanction: Dictionary = sys.risk_event(s, "sanction")
	check(bool(sanction["detained"]), "制裁导致滞留")
	var battle: Dictionary = sys.risk_event(s, "war")
	check(bool(battle["rerouted"]), "战争改航线")
	check(not bool(sys.risk_event(s, "bogus")["ok"]), "未知风险事件被拒")


func _test_services_and_edges() -> void:
	var sys = TradeScript.new()
	var s: Dictionary = sys.new_shipment({"goods_value": 100000, "freight": 10000})
	var svc: Dictionary = sys.add_service(s, "customs_broker")
	check(int(svc["cost"]) > 0, "报关行服务费")
	check(int(s["other_fees"]) > 0, "服务费计入其他费用")
	check_eq((s["services"] as Array).size(), 1, "服务登记")
	check(not bool(sys.add_service(s, "bogus")["ok"]), "未知服务被拒")
	sys.advance_stage(s)
	check_eq(str(s["stage"]), "contract", "流程推进到签约")
	check(int(sys.settle_demurrage(3.0, 10000)) == 30000, "滞港费按日累计")
	var loss: Dictionary = sys.damage_loss(s, 0.1)
	check_eq(int(loss["loss"]), 10000, "损毁折损 10%")
	var ret: Dictionary = sys.return_shipment(s, "rejected")
	check(bool(ret["returned"]) and int(ret["return_cost"]) > 0, "退运结算")
	sys.quarantine_inspect(s, {"passed": false})
	check_eq(str(s["stage"]), "inspection", "检验检疫阶段")
	check(bool(sys.to_dict(s).has("goods_value")), "序列化快照")
