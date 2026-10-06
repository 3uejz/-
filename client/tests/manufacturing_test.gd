extends "res://tests/test_base.gd"
## 制造业、工业与供应链测试（任务 32；R70；design D26）。
## 覆盖：数据表、生产链质量守恒、产能瓶颈、良品率区间、供应链断料/单一供应商、
##       中断停线、订单交付与次品退货、安全工伤、经营模式升级、扩张资金链。

const MfgScript = preload("res://sim/manufacturing.gd")


func _suite_name() -> String:
	return "manufacturing"


func run_tests() -> void:
	_test_tables()
	_test_conservation()
	_test_capacity_bottleneck()
	_test_quality_yield_range()
	_test_supply_chain()
	_test_disruptions()
	_test_orders_and_returns()
	_test_safety_and_modes()
	_test_expansion_funding()


func _test_tables() -> void:
	var sys = MfgScript.new()
	check_eq(sys.role_keys().size(), 7, "七类岗位")
	check_eq(sys.mode_keys().size(), 4, "四种经营模式")
	check_eq(sys.recipe_keys().size(), 3, "三种配方")
	for r in sys.role_keys():
		check(not (sys.role_def(r) as Dictionary).is_empty(), "岗位定义: " + str(r))
	check_eq(str((MfgScript.MODES["oem"] as Dictionary)["name"]), "代工", "OEM 代工")


# 任务 32.1 关键点一：生产链守恒（原料投入 = 良品 + 次品 + 边角损耗）。
func _test_conservation() -> void:
	var sys = MfgScript.new()
	var f: Dictionary = sys.new_factory(10000000)
	sys.hire(f, "unskilled", 20)
	sys.hire(f, "qc", 5)
	sys.add_material(f, "steel", 1000.0, 1000)
	var out: Dictionary = sys.produce(f, "steel_part", 10.0)
	check(bool(out["ok"]), "生产成功")
	check_near(float(out["material_input"]), 10.0, 1e-9, "单耗归一：10 单位原料")
	var total: float = float(out["good_output"]) + float(out["defect_output"]) + float(out["scrap_output"])
	check_near(total, float(out["material_input"]), 1e-9, "守恒：良品+次品+边角=投入")
	check(float(out["good_output"]) > 0.0 and float(out["defect_output"]) >= 0.0 and float(out["scrap_output"]) >= 0.0, "三分量非负")
	check_eq(float((f["products"] as Dictionary)["steel_part"]), float(out["good_output"]), "良品入库")
	# 原料按产出扣减，剩余 = 1000 - material_input。
	check_near(sys.material_qty(f, "steel"), 1000.0 - float(out["material_input"]), 1e-9, "原料扣减守恒")
	# 多原料配方同样守恒：consumed 之和 == material_input。
	var f2: Dictionary = sys.new_factory(10000000)
	sys.hire(f2, "unskilled", 20)
	sys.add_material(f2, "copper", 100.0, 2000)
	sys.add_material(f2, "resin", 100.0, 1500)
	var out2: Dictionary = sys.produce(f2, "circuit_board", 10.0)
	var consumed_sum: float = 0.0
	for mat in (out2["consumed"] as Dictionary).keys():
		consumed_sum += float((out2["consumed"] as Dictionary)[mat])
	check_near(consumed_sum, float(out2["material_input"]), 1e-9, "多原料投入 = 各料消耗之和")
	var total2: float = float(out2["good_output"]) + float(out2["defect_output"]) + float(out2["scrap_output"])
	check_near(total2, float(out2["material_input"]), 1e-9, "多原料配方守恒")


# 产能 = 设备 × 人力 × 效率，受最短板约束。
func _test_capacity_bottleneck() -> void:
	var sys = MfgScript.new()
	# 无人：人力短板，产出为 0。
	var no_labor: Dictionary = sys.new_factory(10000000)
	sys.add_material(no_labor, "steel", 1000.0, 1000)
	var out_labor: Dictionary = sys.produce(no_labor, "steel_part", 10.0)
	check_eq(str(out_labor["bottleneck"]), "labor", "无人工时人力瓶颈")
	check_near(float(out_labor["output_units"]), 0.0, 1e-9, "无人工产出为零")
	# 有人无料：原料短板，产出为 0。
	var no_mat: Dictionary = sys.new_factory(10000000)
	sys.hire(no_mat, "unskilled", 40)
	var out_mat: Dictionary = sys.produce(no_mat, "steel_part", 10.0)
	check_eq(str(out_mat["bottleneck"]), "material", "无原料时原料瓶颈")
	check_near(float(out_mat["output_units"]), 0.0, 1e-9, "无原料产出为零")
	# 人料充足、设备偏低：设备为瓶颈，产能被压低。
	var low_equip: Dictionary = sys.new_factory(10000000, {"equipment": 0.5})
	sys.hire(low_equip, "unskilled", 40)
	sys.add_material(low_equip, "steel", 1000.0, 1000)
	var cap: Dictionary = sys.capacity(low_equip, "steel_part")
	check_eq(str(cap["bottleneck"]), "equipment", "设备为瓶颈")
	check_near(float(cap["effective_capacity"]), 50.0, 1e-9, "有效产能 = 基础×设备")
	var out_eq: Dictionary = sys.produce(low_equip, "steel_part", 100.0)
	check(float(out_eq["output_units"]) <= float(cap["effective_capacity"]) + 1e-9, "产出不超过瓶颈产能")


# 良品率落在合理区间，且品控提升良品率。
func _test_quality_yield_range() -> void:
	var sys = MfgScript.new()
	var f: Dictionary = sys.new_factory(10000000)
	sys.hire(f, "unskilled", 20)
	var q0: float = sys.quality_yield(f, "steel_part")
	check(q0 >= 0.5 and q0 <= 1.0, "良品率在 [0.5, 1.0]")
	sys.hire(f, "qc", 8)
	var q1: float = sys.quality_yield(f, "steel_part")
	check(q1 > q0, "增加品控提升良品率")
	check(q1 <= 0.995 + 1e-9, "良品率不超过上限")
	var out: Dictionary = sys.produce(f, "steel_part", 5.0)
	check(float(out["quality_yield"]) >= 0.5 and float(out["quality_yield"]) <= 1.0, "生产良品率区间正确")


func _test_supply_chain() -> void:
	var sys = MfgScript.new()
	var f: Dictionary = sys.new_factory(10000000)
	# 无供应商：断料。
	var miss: Dictionary = sys.purchase(f, "steel", 100.0)
	check(not bool(miss["ok"]) and str(miss["reason"]) == "no_supplier", "无供应商断料")
	sys.add_supplier(f, {"id": "sup_a", "materials": ["steel"], "price_factor": 1.2, "reliability": 1.0})
	var buy: Dictionary = sys.purchase(f, "steel", 100.0, {"base_unit_cost": 1000})
	check(bool(buy["ok"]), "采购成功")
	check_eq(int(buy["unit_cost"]), 1200, "涨价：单位成本 × 供应商价格系数")
	check_near(float(buy["delivered"]), 100.0, 1e-9, "足量供货")
	# 低可靠性导致部分断料。
	sys.add_supplier(f, {"id": "sup_b", "materials": ["resin"], "price_factor": 1.0, "reliability": 0.5})
	var partial: Dictionary = sys.purchase(f, "resin", 100.0, {"base_unit_cost": 1000})
	check(bool(partial["ok"]) and float(partial["shortfall"]) > 0.0, "低可靠性部分断料")
	# 单一供应商风险。
	var risk: Dictionary = sys.supply_risk(f)
	check((risk["single_source"] as Array).has("steel"), "识别钢铁单一供应商风险")
	check(float(risk["risk"]) > 0.0, "单一供应商风险为正")


func _test_disruptions() -> void:
	var sys = MfgScript.new()
	var f: Dictionary = sys.new_factory(10000000)
	sys.hire(f, "unskilled", 20)
	sys.add_material(f, "steel", 1000.0, 1000)
	sys.set_disruption(f, "power_outage", true)
	check(sys.production_blocked(f), "断电停线")
	var blocked: Dictionary = sys.produce(f, "steel_part", 10.0)
	check(not bool(blocked["ok"]) and str(blocked["reason"]) == "disrupted", "停线拒绝生产")
	sys.set_disruption(f, "power_outage", false)
	check(not sys.production_blocked(f), "恢复供电")
	# 缺勤降低产能但仍可生产。
	sys.set_disruption(f, "absenteeism", true)
	var out: Dictionary = sys.produce(f, "steel_part", 10.0)
	check(bool(out["ok"]), "缺勤仍可生产")
	check(float(out["requested"]) <= 7.0 + 1e-9, "缺勤削减排产")
	check(not bool(sys.set_disruption(f, "bogus", true)["ok"]), "未知中断被拒")


func _test_orders_and_returns() -> void:
	var sys = MfgScript.new()
	var f: Dictionary = sys.new_factory(10000000, {"mode": "oem"})
	sys.hire(f, "unskilled", 20)
	sys.add_material(f, "steel", 1000.0, 1000)
	sys.produce(f, "steel_part", 20.0)
	sys.accept_order(f, "steel_part", 10.0, 5000)
	var money0: int = int(f["money"])
	var del: Dictionary = sys.deliver_order(f, 0)
	check(bool(del["ok"]), "交付成功")
	check(float(del["delivered"]) > 0.0, "交付数量为正")
	check(int(f["money"]) > money0, "交付回款")
	check(bool(del["fulfilled"]), "订单完成")
	# 次品退货：退款并回补部分库存。
	var ret: Dictionary = sys.handle_return(f, "steel_part", 2.0, {"refund_rate": 5000, "restock_ratio": 1.0})
	check(int(ret["refund"]) > 0, "退货退款")
	check(float(ret["restocked"]) > 0.0, "退回良品回补")


func _test_safety_and_modes() -> void:
	var sys = MfgScript.new()
	var f: Dictionary = sys.new_factory(10000000)
	sys.hire(f, "unskilled", 50)
	var risk0: float = float(sys.injury_check(f, {"base_risk": 0.2, "roll": 1.0})["risk"])
	sys.safety_invest(f, 1000000)
	var risk1: float = float(sys.injury_check(f, {"base_risk": 0.2, "roll": 1.0})["risk"])
	check(risk1 < risk0, "安全投入降低工伤风险")
	var hurt: Dictionary = sys.injury_check(f, {"base_risk": 0.9, "roll": 0.0})
	check(int(hurt["injured"]) > 0, "工伤发生")
	# 自动化提升效率。
	var eff0: float = sys.effective_efficiency(f)
	sys.upgrade_automation(f, 1.0)
	check(sys.effective_efficiency(f) > eff0, "自动化提升效率")
	# 环保限产压低效率。
	sys.set_environment_limit(f, 0.5)
	check(sys.effective_efficiency(f) < eff0, "环保限产压低产能")
	# 经营模式：资质与资本门槛、升级路径。
	var g: Dictionary = sys.new_factory(20000000)
	check(not sys.can_enter_mode(g, "obm"), "缺资质不能进入自建品牌")
	sys.grant_qualification(g, "business_license")
	sys.set_mode(g, "oem")
	sys.grant_qualification(g, "brand_registration")
	var up: Dictionary = sys.upgrade_mode(g, "obm")
	check(bool(up["ok"]) and str(g["mode"]) == "obm", "代工升级为自建品牌")
	check(not bool(sys.upgrade_mode(g, "own_factory")["ok"]), "非法升级路径被拒")


func _test_expansion_funding() -> void:
	var sys = MfgScript.new()
	var f: Dictionary = sys.new_factory(100000)
	var risk: Dictionary = sys.funding_risk(f, 5000000)
	check(bool(risk["at_risk"]) and int(risk["shortfall"]) > 0, "识别资金链风险")
	var bad: Dictionary = sys.expand_capacity(f, 5000000)
	check(not bool(bad["ok"]) and str(bad["reason"]) == "funding_chain_broken", "资金不足拒绝扩张")
	var cap0: float = float(f["base_capacity"])
	var goods: Dictionary = sys.new_factory(10000000)
	var ok: Dictionary = sys.expand_capacity(goods, 1000000)
	check(bool(ok["ok"]) and float(goods["base_capacity"]) > cap0, "资金充足扩张成功")
