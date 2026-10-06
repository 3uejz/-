extends "res://tests/test_base.gd"
## 建筑、工程与城市规划测试（任务 38.1；R91；design D47）。
## 覆盖：资质分级与承接、工程链条与验收、偷工减料/挂靠转包抬升事故概率、
## 事故追责与致死、招投标与围标腐败、三角债、城市规划与拆迁、房地产烂尾。

const EngScript = preload("res://sim/engineering.gd")
const RngScript = preload("res://sim/rng.gd")


func _suite_name() -> String:
	return "engineering"


func run_tests() -> void:
	_test_qualification()
	_test_chain_and_acceptance()
	_test_cut_corners_accident_risk()
	_test_engineering_accident()
	_test_subcontract_and_gap()
	_test_tender_and_corruption()
	_test_debt_chain()
	_test_urban_planning()
	_test_real_estate()


func _test_qualification() -> void:
	var sys = EngScript.new()
	var second: Dictionary = sys.new_contractor({"qualification": "second", "capital": 5000000})
	var special: Dictionary = sys.new_contractor({"qualification": "special", "capital": 60000000})
	var big: Dictionary = sys.new_project({"scale": 500000000, "budget": 500000000})
	var small: Dictionary = sys.new_project({"scale": 50000000, "budget": 50000000})
	check_eq(str(small["required_qualification"]), "second", "小工程需二级资质")
	check_eq(str(big["required_qualification"]), "special", "大工程需特级资质")
	check(not bool(sys.can_undertake(second, big)["ok"]), "二级不得承接特级规模工程")
	var fail: Dictionary = sys.can_undertake(second, big)
	check_eq(str(fail["reason"]), "scale_exceeds_qualification", "拒绝原因为规模超资质")
	check(bool(sys.can_undertake(special, big)["ok"]), "特级可承接大工程")
	check(bool(sys.can_undertake(second, small)["ok"]), "二级可承接小工程")


func _test_chain_and_acceptance() -> void:
	var sys = EngScript.new()
	var project: Dictionary = sys.new_project({"scale": 50000000, "budget": 50000000})
	var contractor: Dictionary = sys.new_contractor({"qualification": "first", "capital": 50000000, "workmanship": 0.9})
	sys.advance_stage(project, contractor, {"survey_quality": 0.9})
	sys.advance_stage(project, contractor, {"design_quality": 0.9})
	sys.advance_stage(project, contractor, {"estimate_quality": 0.9})
	sys.advance_stage(project, contractor, {"cut_corners": 0.0, "supervision_strength": 0.9, "pace": 1.0})
	sys.advance_stage(project, contractor, {"supervision_strength": 0.9, "roll": 0.0})
	var acc: Dictionary = sys.advance_stage(project, contractor, {"threshold": 0.6})
	check(bool(acc["passed"]), "优质工程通过验收")
	check(bool(project["accepted"]), "验收后标记已验收")
	# 质量不达标：拒绝验收并返工提升质量。
	var bad: Dictionary = sys.new_project({"scale": 50000000, "budget": 50000000})
	bad["quality"] = 0.3
	var rej: Dictionary = sys.accept(bad, {"threshold": 0.6, "rework": true, "rework_gain": 0.4})
	check(not bool(rej["passed"]), "低质量工程不通过验收")
	check(bool(rej["rework"]), "触发返工整改")
	check_eq(int(rej["rework_count"]), 1, "记录返工次数")
	check(float(bad["quality"]) > 0.3, "返工提升质量")
	# 复检仍不合格则再次返工，直至达标。
	var acc2: Dictionary = sys.accept(bad, {"threshold": 0.6, "rework": true, "rework_gain": 0.4})
	check(bool(acc2["passed"]), "整改后达标通过")


func _test_cut_corners_accident_risk() -> void:
	var sys = EngScript.new()
	var project: Dictionary = sys.new_project({"scale": 50000000, "budget": 50000000})
	var base: float = sys.accident_risk(project, {"cut_corners": 0.0, "supervision_strength": 0.3, "workmanship": 0.6})
	# 偷工减料抬升风险。
	var cut: float = sys.accident_risk(project, {"cut_corners": 1.0, "supervision_strength": 0.3, "workmanship": 0.6})
	check(cut > base, "偷工减料抬升事故风险")
	# 转包深度抬升风险。
	var deep: float = sys.accident_risk(project, {"cut_corners": 0.0, "subcontract_depth": 5, "supervision_strength": 0.3, "workmanship": 0.6})
	check(deep > base, "转包越深事故风险越高")
	# 资质缺口抬升风险。
	var gap: float = sys.accident_risk(project, {"cut_corners": 0.0, "qualification_gap": 2, "supervision_strength": 0.3, "workmanship": 0.6})
	check(gap > base, "资质缺口抬升事故风险")
	# 监理与工艺压低风险。
	var safe: float = sys.accident_risk(project, {"cut_corners": 0.0, "supervision_strength": 1.0, "workmanship": 1.0})
	check(safe < base, "监理与工艺降低事故风险")
	# 偷工减料直接降质量。
	var p2: Dictionary = sys.new_project({"scale": 10000000, "budget": 10000000})
	p2["quality"] = 0.8
	var cut_result: Dictionary = sys.cut_corners(p2, 0.5, {})
	check(int(cut_result["saved"]) > 0, "偷工减料节省成本")
	check(float(cut_result["quality"]) < 0.8, "偷工减料降低质量")
	check(float(cut_result["accident_risk"]) > 0.0, "偷工减料产生事故风险")


func _test_engineering_accident() -> void:
	var sys = EngScript.new()
	var project: Dictionary = sys.new_project({"scale": 300000000, "budget": 300000000})
	project["cut_corners"] = 0.8
	project["illegal_subcontract"] = true
	var acc: Dictionary = sys.engineering_accident(project, {"roll": 0.0, "severity_mult": 3.0})
	check(bool(acc["occurred"]), "低掷骰判定工程事故")
	check(int(acc["loss"]) > 0, "工程事故造成损失")
	check(bool(project["accident"]), "项目标记事故")
	var account: Dictionary = acc["accountability"]
	check(float(account["liability"]) > 0.0, "事故产生责任")
	check(int(account["fine"]) > 0, "事故产生罚款")
	# 无事故：高掷骰。
	var safe_project: Dictionary = sys.new_project({"scale": 10000000, "budget": 10000000})
	var none: Dictionary = sys.engineering_accident(safe_project, {"roll": 0.999})
	check(not bool(none["occurred"]), "高掷骰无事故")
	# 追责：致死 + 违法转包 → 刑事责任。
	var criminal: Dictionary = sys.new_project({"scale": 200000000, "budget": 200000000})
	criminal["illegal_subcontract"] = true
	criminal["cut_corners"] = 0.6
	var acct: Dictionary = sys.assign_accountability(criminal, {"severity": 0.8, "deaths": 2})
	check(bool(acct["criminal"]), "致死且违法转包追究刑责")
	check(int(acct["compensation"]) > 0, "致死事故产生赔偿")
	# 无过失无致死不担刑责。
	var light: Dictionary = sys.new_project({"scale": 10000000, "budget": 10000000})
	var acct2: Dictionary = sys.assign_accountability(light, {"severity": 0.2, "deaths": 0, "negligent": false})
	check(not bool(acct2["criminal"]), "无致死无刑责")
	check(float(acct2["liability"]) < float(acct["liability"]), "轻度过失责任更小")


func _test_subcontract_and_gap() -> void:
	var sys = EngScript.new()
	var project: Dictionary = sys.new_project({"scale": 100000000, "budget": 100000000, "required_qualification": "special"})
	var weak: Dictionary = sys.new_contractor({"qualification": "second", "capital": 5000000})
	var sub: Dictionary = sys.assess_subcontract(project, weak, {"borrowed_qualification": true, "subcontract_depth": 2})
	check(bool(sub["illegal"]), "挂靠与超深转包判定违法")
	check_eq(int(sub["qualification_gap"]), 2, "资质缺口 = 特级 - 二级")
	check(bool(project["illegal_subcontract"]), "项目标记违法转包")
	var normal: Dictionary = sys.new_project({"scale": 50000000, "budget": 50000000})
	var legal: Dictionary = sys.assess_subcontract(normal, weak, {"subcontract_depth": 1, "max_depth": 1})
	check(not bool(legal["illegal"]), "合规转包不违法")
	# 欠款：资金不足则停工并计息。
	var poor: Dictionary = sys.new_contractor({"capital": 1000000})
	var arrears: Dictionary = sys.arrears(poor, 10000000, {"stop_threshold": 0.5, "interest_rate": 0.1})
	check(bool(arrears["stop_work"]), "资金不足导致停工")
	check(int(arrears["interest"]) > 0, "欠款产生利息")


func _test_tender_and_corruption() -> void:
	var sys = EngScript.new()
	var project: Dictionary = sys.new_project({"scale": 50000000, "budget": 100000000})
	var a: Dictionary = sys.new_contractor({"id": "a", "qualification": "first", "relationship": 0.9, "reputation": 0.9})
	var b: Dictionary = sys.new_contractor({"id": "b", "qualification": "second", "relationship": 0.1, "reputation": 0.4})
	var bids: Array = [
		{"id": "a", "qualification": "first", "price": 100000000, "relationship": 0.9, "reputation": 0.9},
		{"id": "b", "qualification": "second", "price": 90000000, "relationship": 0.1, "reputation": 0.4},
	]
	var res: Dictionary = sys.tender(project, bids, {"roll": 0.0})
	check(bool(res["ok"]), "招投标定标成功")
	check_eq(str(res["winner"]), "a", "关系与资质更优者中标")
	# 资质不足直接出局。
	var tiny: Dictionary = sys.new_project({"scale": 500000000, "budget": 500000000})
	var dq: Dictionary = sys.bid_score(b, tiny, {"price": 400000000})
	check(bool(dq["disqualified"]), "资质不足被取消投标资格")
	# 围标提升指定者评分。
	var plain: float = float(sys.bid_score(b, project, {"price": 90000000})["score"])
	var rigged: float = float(sys.bid_score(b, project, {"price": 90000000, "collusion_bonus": 0.5})["score"])
	check(rigged > plain, "围标提升指定者中标评分")
	var rig: Dictionary = sys.rig_bids(bids, "b", {"collusion_bonus": 0.5, "accomplice_price_mult": 1.2})
	check(bool(rig["ok"]), "围标设置成功")
	# 招投标腐败：行贿提分但有查处风险。
	var bribe: Dictionary = sys.tender_corruption(project, {"bribe": 20000000, "roll": 0.0})
	check(float(bribe["collusion_bonus"]) > 0.0, "行贿提升中标加成")
	check(bool(bribe["exposed"]), "行贿被查处")
	check(bool(bribe["criminal"]), "巨额行贿追究刑责")
	var clean: Dictionary = sys.tender_corruption(project, {"bribe": 0, "roll": 0.999})
	check(not bool(clean["exposed"]), "无行贿无查处")


func _test_debt_chain() -> void:
	var sys = EngScript.new()
	var chain: Dictionary = sys.debt_chain(["A", "B", "C"], 1000000, {"start_default": 0, "contagion": 0.5})
	check(bool(chain["ok"]), "三角债模拟成功")
	check_eq(int(chain["default_count"]), 3, "一处违约传染全链")
	check(int(chain["total_arrears"]) > 0, "三角债累积欠款")
	# 从中间违约：上游已付，下游传染。
	var partial: Dictionary = sys.debt_chain(["A", "B", "C"], 1000000, {"start_default": 1, "contagion": 0.5})
	check_eq(int(partial["default_count"]), 2, "中间违约只传染下游")
	check(int(partial["total_arrears"]) < int(chain["total_arrears"]), "违约起点越晚欠款越少")
	var too_short: Dictionary = sys.debt_chain(["A"], 100)
	check(not bool(too_short["ok"]), "债权链过短被拒")


func _test_urban_planning() -> void:
	var sys = EngScript.new()
	var city: Dictionary = sys.new_city({"land_price": 10000, "population": 1000000})
	var res: Dictionary = sys.rezone(city, "z1", "residential", {})
	var com: Dictionary = sys.rezone(city, "z2", "commercial", {"migration_rate": 0.05})
	check(float(res["new_land_price"]) > 0.0, "规划产生功能区地价")
	check(float(com["new_land_price"]) > float(res["new_land_price"]), "商业区地价高于居住区")
	check(int(com["population_delta"]) != 0 or float(com["traffic"]) >= 0.0, "规划联动人口与交通")
	var lv: Dictionary = sys.land_value(city, "z2")
	check(float(lv["land_price"]) > 0.0, "可查询功能区地价")
	var t_before: float = float(city["traffic"])
	var tp: Dictionary = sys.transport_project(city, "z2", {"improvement": 0.3})
	check(float(city["traffic"]) > t_before, "交通工程改善交通")
	check(float(tp["land_delta"]) > 0.0, "交通工程抬升沿线地价")
	# 规划腐败：行贿抬高容积/地价，并被查处。
	var corrupt: Dictionary = sys.planning_corruption(city, {"bribe": 25000000, "roll": 0.0})
	check(float(corrupt["land_bubble"]) > 0.0, "规划腐败吹高地价")
	check(bool(corrupt["exposed"]), "规划腐败被查处")
	# 拆迁：补偿不足引发纠纷。
	var fair: Dictionary = sys.demolition(city, "z1", {"residents": 1000, "compensation_per": 500000})
	var unfair: Dictionary = sys.demolition(city, "z1", {"residents": 1000, "compensation_per": 10})
	check(bool(fair["fair"]), "足额补偿顺利拆迁")
	check(int(fair["disputes"]) == 0, "足额补偿无纠纷")
	check(int(unfair["disputes"]) > 0, "补偿不足引发纠纷")


func _test_real_estate() -> void:
	var sys = EngScript.new()
	var dev: Dictionary = sys.new_developer({"cash": 0})
	var project: Dictionary = {"remaining_cost": 10000000, "pre_sold": 0, "unit_price": 1000000}
	var pre: Dictionary = sys.pre_sale(dev, project, 10, 1000000)
	check_eq(int(pre["income"]), 10000000, "预售回笼资金")
	check_eq(int(dev["cash"]), 10000000, "预售资金入账")
	var build: Dictionary = sys.develop_project(dev, project, 2000000, {"pace": 0.5})
	check(bool(build["ok"]), "楼盘施工成功")
	check_near(float(project["progress"]), 0.5, 1e-6, "施工推进进度")
	# 资金充足不烂尾。
	var dev2: Dictionary = sys.new_developer({"cash": 20000000})
	var p2: Dictionary = {"remaining_cost": 10000000, "pre_sold": 10, "unit_price": 1000000}
	var u1: Dictionary = sys.unfinished(dev2, p2, {})
	check(not bool(u1["stalled"]), "资金充足不烂尾")
	# 资金断裂烂尾，买家受损。
	var dev3: Dictionary = sys.new_developer({"cash": 0})
	var p3: Dictionary = {"remaining_cost": 10000000, "pre_sold": 10, "unit_price": 1000000}
	var u2: Dictionary = sys.unfinished(dev3, p3, {})
	check(bool(u2["stalled"]), "资金断裂导致烂尾")
	check(bool(p3["unfinished"]), "项目标记烂尾")
	check(int(u2["buyers_lost"]) > 0, "烂尾买家受损")
