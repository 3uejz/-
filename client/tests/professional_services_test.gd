extends "res://tests/test_base.gd"
## 专业服务业测试（任务 39.1；R92；design D48）。
## 覆盖：资质考取与接单能力、客户开发与项目、尽职调查与并购顾问、
## 审计独立性冲突、虚假报告/内幕交易/商业贿赂的法律与声誉后果、
## 合伙人分裂带走客户、竞业限制违约、客户流失、序列化往返。

const ProScript = preload("res://sim/professional_services.gd")


func _suite_name() -> String:
	return "professional_services"


func run_tests() -> void:
	_test_qualification()
	_test_gatekeep_capacity()
	_test_independence_conflict()
	_test_false_report()
	_test_insider_trading()
	_test_commercial_bribery()
	_test_partner_split()
	_test_client_acquisition_and_churn()
	_test_non_compete()
	_test_projects()
	_test_serialization()


func _test_qualification() -> void:
	var sys = ProScript.new()
	check_eq(sys.practice_type_name("accounting_audit"), "会计审计", "执业类型中文名")
	check_eq(sys.qualification_name("cpa"), "注册会计师", "资质中文名")
	var firm: Dictionary = sys.new_firm({"money": 1000000, "reputation": 0.5})
	var res: Dictionary = sys.acquire_qualification(firm, "cpa", {"skill": 0.9, "roll": 0.0})
	check(bool(res["passed"]), "高技能低掷骰通过考试")
	check((firm["qualifications"] as Dictionary).has("cpa"), "通过后持证")
	check(float(firm["reputation"]) > 0.5, "持证提升声誉")
	check_eq(int(firm["money"]), 1000000 - 50000, "扣除考试费")
	var again: Dictionary = sys.acquire_qualification(firm, "cpa", {"skill": 0.9, "roll": 0.0})
	check(not bool(again["ok"]), "重复考取被拒")
	check_eq(str(again["reason"]), "already_qualified", "重复原因正确")
	# 低技能高掷骰落榜。
	var firm2: Dictionary = sys.new_firm({"money": 1000000})
	var fail: Dictionary = sys.acquire_qualification(firm2, "cfa", {"skill": 0.0, "roll": 0.99})
	check(not bool(fail["passed"]), "低技能高掷骰落榜")
	check(not (firm2["qualifications"] as Dictionary).has("cfa"), "落榜不持证")
	# 资金不足。
	var poor: Dictionary = sys.new_firm({"money": 0})
	var no: Dictionary = sys.acquire_qualification(poor, "cpa", {"skill": 0.9, "roll": 0.0})
	check_eq(str(no["reason"]), "insufficient_funds", "资金不足拒绝报考")
	# 未知资质。
	var unk: Dictionary = sys.acquire_qualification(firm, "phd", {})
	check_eq(str(unk["reason"]), "unknown_cert", "未知资质被拒")


func _test_gatekeep_capacity() -> void:
	var sys = ProScript.new()
	var firm: Dictionary = sys.new_firm({"reputation": 0.5})
	var before: Dictionary = sys.gatekeep_capacity(firm, "accounting_audit")
	check(not bool(before["qualified"]), "无证不具审计资质")
	check_eq(str(before["required_cert"]), "cpa", "审计需注册会计师")
	sys.acquire_qualification(firm, "cpa", {"skill": 0.9, "roll": 0.0})
	var after: Dictionary = sys.gatekeep_capacity(firm, "accounting_audit")
	check(bool(after["qualified"]), "持证具备审计资质")
	check(float(after["capacity"]) > float(before["capacity"]), "持证提升接单能力")
	# 无需资质的执业类型默认可接单。
	var consulting: Dictionary = sys.gatekeep_capacity(firm, "consulting")
	check(bool(consulting["qualified"]), "咨询无需资质")
	check_eq(str(sys.gatekeep_capacity(firm, "nope")["reason"]), "unknown_practice", "未知执业被拒")


func _test_independence_conflict() -> void:
	var sys = ProScript.new()
	var pure_audit: Dictionary = {"roles": ["audit"]}
	check(not bool(sys.independence_conflict(pure_audit)["conflict"]), "仅审计无冲突")
	var mixed: Dictionary = {"roles": ["audit", "consulting"]}
	check(bool(sys.independence_conflict(mixed)["conflict"]), "审计兼咨询构成独立性冲突")
	var advisory: Dictionary = {"roles": ["audit", "advisory"]}
	check(bool(sys.independence_conflict(advisory)["conflict"]), "审计兼并购顾问构成冲突")
	var only_consult: Dictionary = {"roles": ["consulting", "tax"]}
	check(not bool(sys.independence_conflict(only_consult)["conflict"]), "非审计业务无独立性冲突")


func _test_false_report() -> void:
	var sys = ProScript.new()
	var firm: Dictionary = sys.new_firm({"reputation": 0.5})
	var project: Dictionary = {"id": "p1"}
	var rep0: float = float(firm["reputation"])
	var exposed: Dictionary = sys.false_report(firm, project, {"severity": 0.8, "detection": 0.5, "roll": 0.0})
	check(bool(exposed["exposed"]), "低掷骰被查处")
	check(bool(exposed["legal"]), "虚假报告追究法律责任")
	check(int(exposed["fine"]) > 0, "被查处产生罚款")
	check(float(firm["reputation"]) < rep0, "虚假报告打击声誉")
	check_eq((firm["violations"] as Array).size(), 1, "记录违规")
	var not_exposed: Dictionary = sys.false_report(sys.new_firm({"reputation": 0.5}), project, {"severity": 0.8, "detection": 0.5, "roll": 0.99})
	check(not bool(not_exposed["exposed"]), "高掷骰未被查处")
	check_eq(int(not_exposed["fine"]), 0, "未被查处无罚款")


func _test_insider_trading() -> void:
	var sys = ProScript.new()
	var firm: Dictionary = sys.new_firm({"reputation": 0.5})
	var big: Dictionary = sys.insider_trading(firm, {"profit": 1000000, "detection": 0.5, "roll": 0.0})
	check(bool(big["exposed"]), "内幕交易被查处")
	check(bool(big["legal"]), "巨额内幕交易触刑")
	check_eq(int(big["fine"]), 2000000, "罚款按获利倍数")
	var small: Dictionary = sys.insider_trading(sys.new_firm({"reputation": 0.5}), {"profit": 100000, "detection": 0.5, "roll": 0.0})
	check(bool(small["exposed"]), "小额也被查处")
	check(not bool(small["legal"]), "小额未达刑责门槛")
	var safe: Dictionary = sys.insider_trading(sys.new_firm({"reputation": 0.5}), {"profit": 1000000, "detection": 0.5, "roll": 0.99})
	check(not bool(safe["exposed"]), "高掷骰未被查处")
	check(not bool(safe["legal"]), "未查处无刑责")


func _test_commercial_bribery() -> void:
	var sys = ProScript.new()
	var firm: Dictionary = sys.new_firm({"reputation": 0.5})
	var hit: Dictionary = sys.commercial_bribery(firm, {"amount": 500000, "detection": 0.5, "roll": 0.0})
	check(bool(hit["exposed"]), "商业贿赂被查处")
	check(bool(hit["legal"]), "巨额贿赂触刑")
	check_eq(int(hit["fine"]), 750000, "罚款按金额倍数")
	var minor: Dictionary = sys.commercial_bribery(sys.new_firm({"reputation": 0.5}), {"amount": 50000, "detection": 0.5, "roll": 0.0})
	check(bool(minor["exposed"]), "小额也被查处")
	check(not bool(minor["legal"]), "小额未达刑责门槛")
	var clean: Dictionary = sys.commercial_bribery(sys.new_firm({"reputation": 0.5}), {"amount": 500000, "detection": 0.5, "roll": 0.99})
	check(not bool(clean["exposed"]), "无查处")


func _test_partner_split() -> void:
	var sys = ProScript.new()
	var firm: Dictionary = sys.new_firm({"reputation": 0.8})
	sys.add_partner(firm, "p1", {"share": 0.3, "clients": 3})
	sys.add_partner(firm, "p2", {"share": 0.2, "clients": 2})
	check_eq((firm["clients"] as Dictionary).size(), 5, "合伙人带入客户")
	check(not bool(sys.add_partner(firm, "p1", {})["ok"]), "重复吸收合伙人被拒")
	var rep0: float = float(firm["reputation"])
	var split: Dictionary = sys.partner_split(firm, "p1", {"poach_rate": 0.0, "roll": 0.0})
	check_eq(int(split["clients_carried"]), 3, "分裂带走自有客户")
	check_eq((firm["clients"] as Dictionary).size(), 2, "其余客户留在事务所")
	check(float(firm["reputation"]) < rep0, "合伙人分裂打击声誉")
	check(not (firm["partners"] as Dictionary).has("p1"), "合伙人已退出")
	check_eq(str(sys.partner_split(firm, "ghost", {})["reason"]), "not_partner", "非合伙人拒绝分裂")


func _test_client_acquisition_and_churn() -> void:
	var sys = ProScript.new()
	var firm: Dictionary = sys.new_firm({"reputation": 0.9})
	var got: Dictionary = sys.client_acquisition(firm, {"roll": 0.0})
	check(bool(got["success"]), "高声望开发客户成功")
	check((firm["clients"] as Dictionary).has(str(got["client"])), "客户入册")
	check(int(got["size"]) >= 1, "客户规模非负")
	var miss: Dictionary = sys.client_acquisition(sys.new_firm({"reputation": 0.9}), {"roll": 0.99})
	check(not bool(miss["success"]), "高掷骰开发失败")
	# 客户流失：低声誉流失率更高。
	var churn_firm: Dictionary = sys.new_firm({"reputation": 0.0})
	for i in range(10):
		(churn_firm["clients"] as Dictionary)["c%d" % i] = {"size": 1, "satisfaction": 0.6}
	var churn: Dictionary = sys.client_churn(churn_firm, {})
	check_eq(int(churn["lost"]), 3, "低声誉按比例流失客户")
	check_eq((churn_firm["clients"] as Dictionary).size(), 7, "剩余客户正确")


func _test_non_compete() -> void:
	var sys = ProScript.new()
	var v: Dictionary = sys.non_compete_violation({"has_clause": true, "moved_to_competitor": true})
	check(bool(v["violation"]), "有竞业且跳槽竞争对手构成违约")
	check_eq(int(v["damages"]), 500000, "违约赔偿")
	check(not bool(sys.non_compete_violation({"has_clause": false, "moved_to_competitor": true})["violation"]), "无竞业条款不算违约")
	check(not bool(sys.non_compete_violation({"has_clause": true, "moved_to_competitor": false})["violation"]), "未跳槽不算违约")


func _test_projects() -> void:
	var sys = ProScript.new()
	var firm: Dictionary = sys.new_firm({})
	var proj: Dictionary = sys.new_project(firm, "c1", "investment_banking", {})
	check(bool(proj["ok"]), "立项成功")
	var project: Dictionary = proj["project"]
	check_eq(int(project["fee"]), 1500000, "投行项目默认费用")
	check_eq(str(project["client"]), "c1", "项目关联客户")
	check_eq(str(sys.new_project(firm, "c1", "nope", {})["reason"]), "unknown_practice", "未知执业立项被拒")
	# 尽职调查。
	var dd: Dictionary = sys.due_diligence(project, {"depth": 1.0, "roll": 0.0})
	check_eq((dd["findings"] as Array).size(), 1, "深度核查发现问题")
	check_eq((project["findings"] as Array).size(), 1, "问题写入项目")
	var dd2: Dictionary = sys.due_diligence(project, {"depth": 0.1, "roll": 0.99})
	check_eq((dd2["findings"] as Array).size(), 0, "浅度高掷骰无发现")
	# 并购顾问。
	var ma: Dictionary = sys.ma_advisory(project, {"deal_size": 100000000, "fee_rate": 0.02, "success_prob": 0.6, "roll": 0.0})
	check(bool(ma["success"]), "并购顾问成交")
	check_eq(int(ma["fee"]), 2000000, "并购顾问抽佣")
	check_eq(str(project["status"]), "closed", "项目结案")
	var miss: Dictionary = sys.ma_advisory(sys.new_project(firm, "c2", "consulting", {})["project"], {"deal_size": 100000000, "success_prob": 0.6, "roll": 0.99})
	check(not bool(miss["success"]), "并购顾问未成交")
	check_eq(int(miss["fee"]), 0, "未成交无佣金")


func _test_serialization() -> void:
	var sys = ProScript.new()
	var firm: Dictionary = sys.new_firm({"money": 123, "reputation": 0.4})
	var clone: Dictionary = sys.from_dict(sys.to_dict(firm))
	check_eq(int(clone["money"]), 123, "序列化资金往返")
	check_near(float(clone["reputation"]), 0.4, 1e-9, "序列化声誉往返")
	check_eq((clone["clients"] as Dictionary).size(), 0, "序列化客户往返")
