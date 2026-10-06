extends "res://tests/test_base.gd"
## 交通基建与航运测试（任务 39.1；R94；design D50）。
## 覆盖：立项缩放、招投标定标、施工超支延期、运营收入/准点率、
## 区域可达性/地价/GDP/人口影响、网络效应、政府补贴、结算、重大事故、
## 垄断定价监管、国际局势中断、序列化往返。

const InfraScript = preload("res://sim/transport_infra.gd")


func _suite_name() -> String:
	return "transport_infra"


func run_tests() -> void:
	_test_new_project()
	_test_tender()
	_test_build_overrun_delay()
	_test_operate()
	_test_regional_impact()
	_test_network_effect()
	_test_subsidy_and_settle()
	_test_accident()
	_test_monopoly_and_disruption()
	_test_serialization()


func _test_new_project() -> void:
	var sys = InfraScript.new()
	check_eq(sys.infra_type_name("highspeed_rail"), "高铁", "基建类型中文名")
	var p: Dictionary = sys.new_infra_project({"type": "highway", "scale": 1.0})
	check_eq(int(p["cost_estimate"]), 50000000, "公路基准成本")
	check_near(float(p["days_total"]), 180.0, 1e-6, "公路基准工期")
	check_near(float(p["capacity"]), 1.0, 1e-6, "公路基准运力")
	var big: Dictionary = sys.new_infra_project({"type": "airport", "scale": 2.0})
	check_eq(int(big["cost_estimate"]), 2400000000, "机场双倍规模成本")
	check_eq(str(p["status"]), "planned", "初始为规划状态")
	var unknown: Dictionary = sys.new_infra_project({"type": "nope", "scale": 1.0})
	check_eq(str(unknown["type"]), "nope", "保留类型键")
	check_eq(int(unknown["cost_estimate"]), 50000000, "未知类型回退公路")


func _test_tender() -> void:
	var sys = InfraScript.new()
	var project: Dictionary = sys.new_infra_project({"type": "railway"})
	var bids: Array = [
		{"id": "a", "price": 100000000, "qualification_score": 0.9, "relationship": 0.9},
		{"id": "b", "price": 90000000, "qualification_score": 0.5, "relationship": 0.1},
	]
	var res: Dictionary = sys.tender_infra(project, bids, {})
	check(bool(res["ok"]), "招投标定标")
	check_eq(str(res["winner"]), "a", "综合评分高者中标")
	check_eq(str(project["status"]), "awarded", "项目进入已授标")
	check_eq(str(project["operator"]), "a", "记录承包方")
	check(not bool(sys.tender_infra(project, [])["ok"]), "无投标被拒")


func _test_build_overrun_delay() -> void:
	var sys = InfraScript.new()
	var project: Dictionary = sys.new_infra_project({"type": "highway"})
	var s1: Dictionary = sys.build(project, {"pace": 0.5, "roll": 0.0})
	check_near(float(s1["progress"]), 0.5, 1e-6, "施工推进进度")
	check_eq(int(s1["overrun"]), 0, "无掷骰不超支")
	check_eq(str(s1["status"]), "planned", "未完工状态")
	var s2: Dictionary = sys.build(project, {"pace": 0.5, "roll": 0.0})
	check_near(float(s2["progress"]), 1.0, 1e-6, "进度推满")
	check_eq(str(s2["status"]), "built", "完工标记")
	# 低质量高掷骰：超支与延期。
	var bad: Dictionary = sys.new_infra_project({"type": "bridge", "quality": 0.0})
	var over: Dictionary = sys.build(bad, {"pace": 0.2, "roll": 1.0})
	check(int(over["overrun"]) > 0, "低质量超支")
	check(float(over["delay_days"]) > 0.0, "工期延长")
	check(int(bad["spent"]) > 0, "超支计入已花费")


func _test_operate() -> void:
	var sys = InfraScript.new()
	var project: Dictionary = sys.new_infra_project({"type": "highway"})
	var res: Dictionary = sys.operate(project, {"mode": "logistics", "fare": 100.0, "demand": 1.0, "supply": 1.0, "riders": 1000.0, "roll": 0.0})
	check_eq(int(res["revenue"]), 100000, "运营收入")
	check_eq(int(res["cost"]), 80000, "物流成本比 80%")
	check_eq(int(res["profit"]), 20000, "运营盈余")
	check_near(float(res["on_time_rate"]), 0.78, 1e-6, "准点率随质量下降")


func _test_regional_impact() -> void:
	var sys = InfraScript.new()
	var project: Dictionary = sys.new_infra_project({"type": "railway"})
	project["capacity"] = 2.0
	var region: Dictionary = {"accessibility": 0.5, "land_price": 10000.0, "gdp": 1000000.0, "population": 100000.0}
	var res: Dictionary = sys.regional_impact(project, region, {"migration": 1.0})
	check_near(float(res["accessibility"]), 0.7, 1e-6, "投用提升可达性")
	check_near(float(res["land_delta"]), 0.16, 1e-6, "地价涨幅")
	check_near(float(region["land_price"]), 11600.0, 1e-3, "地价抬升")
	check_near(float(region["gdp"]), 1240000.0, 1e-3, "GDP 抬升")
	check_near(float(res["population_delta"]), 4000.0, 1e-3, "人口流入")


func _test_network_effect() -> void:
	var sys = InfraScript.new()
	var nodes: Array = [{"id": "a", "hub": true}, {"id": "b", "hub": false}, {"id": "c", "hub": false}]
	var routes: Array = [{"from": "a", "to": "b"}, {"from": "b", "to": "c"}]
	var res: Dictionary = sys.network_effect(nodes, routes, {})
	check_eq(int(res["hub_count"]), 1, "统计枢纽数")
	check_near(float(res["connectivity"]), 2.0 / 3.0, 1e-6, "连通度")
	check(float(res["transfer_efficiency"]) > 0.0, "换乘效率为正")
	check_near(float(res["logistics_gain"]), 0.55, 1e-6, "物流增益")
	var empty: Dictionary = sys.network_effect([], [], {})
	check_near(float(empty["connectivity"]), 0.0, 1e-6, "无节点连通度为 0")


func _test_subsidy_and_settle() -> void:
	var sys = InfraScript.new()
	var rail: Dictionary = sys.new_infra_project({"type": "railway"})
	var sub: Dictionary = sys.subsidy(rail, {})
	check(bool(sub["public_good"]), "铁路属公益性")
	check(int(sub["granted"]) > 0, "公益性线路获补贴")
	check_eq(int(rail["subsidy"]), int(sub["granted"]), "补贴计入项目")
	var port: Dictionary = sys.new_infra_project({"type": "port"})
	check_eq(int(sys.subsidy(port, {})["granted"]), 0, "非公益性无默认补贴")
	# 结算。
	rail["days_total"] = 365.0
	rail["delayed_days"] = 36.0
	rail["spent"] = 1000000
	rail["quality"] = 0.8
	var st: Dictionary = sys.settle(rail, {"operating_profit": 500000})
	check_near(float(st["construction_days"]), 401.0, 1e-6, "结算建设周期")
	check_eq(int(st["cost"]), 1000000, "结算成本")
	check_near(float(st["safety"]), 0.8, 1e-6, "结算安全度")
	check_eq(int(st["operating_profit"]), 500000, "结算运营盈亏")
	rail["accident"] = true
	check_near(float(sys.settle(rail, {})["safety"]), 0.5, 1e-6, "事故降低安全度")


func _test_accident() -> void:
	var sys = InfraScript.new()
	var project: Dictionary = sys.new_infra_project({"type": "tunnel"})
	project["cost_estimate"] = 100000000
	project["quality"] = 0.6
	var hit: Dictionary = sys.infra_accident(project, {"cut_corners": 1.0, "base_prob": 0.05, "severity": 0.6, "roll": 0.0})
	check(bool(hit["occurred"]), "低掷骰发生重大事故")
	check(bool(project["accident"]), "项目标记事故")
	check(int(hit["loss"]) > 0, "事故产生损失")
	check(int(hit["deaths"]) > 0, "偷工减料致死")
	check(float(project["quality"]) < 0.6, "事故降低质量")
	var safe: Dictionary = sys.infra_accident(sys.new_infra_project({"type": "tunnel"}), {"cut_corners": 0.0, "base_prob": 0.05, "roll": 0.999})
	check(not bool(safe["occurred"]), "高掷骰无事故")
	check_eq(int(safe["deaths"]), 0, "无事故无死亡")


func _test_monopoly_and_disruption() -> void:
	var sys = InfraScript.new()
	var reg: Dictionary = sys.monopoly_regulation({"market_share": 0.8, "price": 100.0, "threshold": 0.7, "revenue": 1000000})
	check_eq(str(reg["action"]), "price_cap", "垄断触发限价")
	check_near(float(reg["price_cap"]), 80.0, 1e-6, "限价 80%")
	check_eq(int(reg["fine"]), 50000, "反垄断罚款")
	var free: Dictionary = sys.monopoly_regulation({"market_share": 0.5, "threshold": 0.7})
	check_eq(str(free["action"]), "none", "未垄断不限价")
	# 国际局势中断。
	var route: Dictionary = {"id": "r1", "on_time_rate": 0.9}
	var dis: Dictionary = sys.international_disruption(route, {"sensitivity": 0.5, "roll": 0.0})
	check(bool(dis["disrupted"]), "低掷骰航线中断")
	check(bool(route["suspended"]), "航线路由标记停飞")
	check(int(dis["loss"]) > 0, "中断产生损失")
	check(float(route["on_time_rate"]) < 0.9, "准点率下降")
	var calm: Dictionary = sys.international_disruption({"id": "r2"}, {"sensitivity": 0.1, "roll": 0.99})
	check(not bool(calm["disrupted"]), "高掷骰航线正常")


func _test_serialization() -> void:
	var sys = InfraScript.new()
	var project: Dictionary = sys.new_infra_project({"type": "port", "scale": 1.5})
	var clone: Dictionary = sys.from_dict(sys.to_dict(project))
	check_eq(str(clone["type"]), "port", "序列化类型往返")
	check_eq(int(clone["cost_estimate"]), int(project["cost_estimate"]), "序列化成本往返")
	check_near(float(clone["capacity"]), float(project["capacity"]), 1e-9, "序列化运力往返")
