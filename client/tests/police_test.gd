extends "res://tests/test_base.gd"
## 安保、警务与刑侦测试（任务 34、34.1；R79；design D35）。
## 覆盖：数据表、案件状态机推进、证据强度影响侦破概率、程序合法性约束与证据瑕疵、
##       冤假错案边界、线人与卧底、民营安保履约与失职担责。

const PoliceScript = preload("res://sim/police.gd")


func _suite_name() -> String:
	return "police"


func run_tests() -> void:
	_test_tables()
	_test_case_state_machine()
	_test_evidence_affects_solve()
	_test_legality_constraints()
	_test_misjudgment_boundary()
	_test_undercover_informant()
	_test_private_security()


func _test_tables() -> void:
	var sys = PoliceScript.new()
	check_eq(sys.role_keys().size(), 5, "五类公职")
	check_eq(sys.evidence_kinds().size(), 6, "六类证据")
	check_eq(sys.security_service_keys().size(), 4, "四类安保业务")
	check_eq(str(PoliceScript.STAGES[0]), "survey", "状态机起点为勘查")
	check_eq(str(PoliceScript.STAGES[2]), "trace", "第三阶段为追查")
	for key in sys.role_keys():
		check(not (sys.role_def(key) as Dictionary).is_empty(), "角色定义: " + str(key))
	for key in sys.security_service_keys():
		check(not (sys.security_service_def(key) as Dictionary).is_empty(), "安保业务定义: " + str(key))


func _test_case_state_machine() -> void:
	var sys = PoliceScript.new()
	var case: Dictionary = sys.new_case("robbery", "r1", {"officer_skill": 12.0})
	check_eq(str(case["stage"]), "survey", "初始为勘查")
	sys.survey(case)
	check(float(case["leads"]) > 0.0, "勘查获得线索")
	var s1: Dictionary = sys.advance(case)
	check_eq(str(s1["stage"]), "forensics", "推进到取证")
	var s2: Dictionary = sys.advance(case)
	check_eq(str(s2["stage"]), "trace", "推进到追查")
	var s3: Dictionary = sys.advance(case, {"roll": 0.0})
	check(bool(s3["solved"]), "低 roll 必破")
	check_eq(str(case["stage"]), "solved", "阶段为侦破")
	check(not bool(sys.advance(case)["ok"]), "终态拒绝推进")
	# 高 roll 未破转冷案。
	var case2: Dictionary = sys.new_case("theft", "r1")
	sys.advance(case2)
	sys.advance(case2)
	var s4: Dictionary = sys.attempt_solve(case2, {"roll": 0.999})
	check(not bool(s4["solved"]), "高 roll 未破")
	check_eq(str(case2["stage"]), "cold", "未破转冷案")


func _test_evidence_affects_solve() -> void:
	var sys = PoliceScript.new()
	var weak: Dictionary = sys.new_case("fraud", "r1")
	var strong: Dictionary = sys.new_case("fraud", "r1")
	sys.add_evidence(strong, "physical", 1.0)
	sys.add_evidence(strong, "forensic", 1.0)
	sys.add_evidence(strong, "witness", 1.0)
	check(sys.solve_probability(strong) > sys.solve_probability(weak), "证据越强侦破概率越高")
	# 证据累积时侦破概率单调不降。
	var c: Dictionary = sys.new_case("fraud", "r1")
	var prev: float = sys.solve_probability(c)
	for i in 5:
		sys.add_evidence(c, "physical", 0.2)
		var now: float = sys.solve_probability(c)
		check(now >= prev - 1e-9, "证据累积概率单调不降")
		prev = now
	# 证据强度直接影响结算概率值。
	var probe: Dictionary = sys.new_case("fraud", "r1")
	var p0: float = sys.solve_probability(probe)
	sys.add_evidence(probe, "digital", 1.0)
	check(sys.solve_probability(probe) > p0, "单类证据提升侦破概率")


func _test_legality_constraints() -> void:
	var sys = PoliceScript.new()
	var case: Dictionary = sys.new_case("narcotics", "r1")
	# 监控属需令证据：无令采集非法且不入链。
	var bad: Dictionary = sys.collect(case, "surveillance", 0.5, {})
	check(not bool(bad["ok"]) and bool(bad["illegal"]), "无搜查令非法取证被拒")
	check_near(sys.evidence_score(case), 0.0, 1e-9, "非法证据不入链")
	check(float(sys.legality_score(case)) < 1.0, "程序违法降低合法性")
	check_eq(int((case["legal"] as Dictionary)["violations"]), 1, "记录违法次数")
	# 取得搜查令后合法。
	sys.request_warrant(case, {})
	check(bool((case["legal"] as Dictionary)["warrant"]), "取得搜查令")
	var good: Dictionary = sys.collect(case, "surveillance", 0.5, {})
	check(bool(good["ok"]), "有令合法取证")
	check(sys.evidence_score(case) > 0.0, "合法证据入链")
	# 技术侦查无令被拒。
	var case2: Dictionary = sys.new_case("fraud", "r1")
	check(not bool(sys.tech_surveillance(case2)["ok"]), "无令技术侦查被拒")
	# 滥用职权降低合法性并抬高误判风险。
	var before: float = sys.legality_score(case2)
	sys.abuse_power(case2)
	check(sys.legality_score(case2) < before, "滥用职权降低合法性")
	check(float(case2["misjudgment_risk"]) > 0.0, "滥用职权抬高误判风险")


func _test_misjudgment_boundary() -> void:
	var sys = PoliceScript.new()
	# 弱证据 + 逼供 => 冤假错案。
	var case: Dictionary = sys.new_case("assault", "r1")
	sys.interrogate(case, 0.9, {"roll": 0.0})
	check(bool(case["coerced"]), "高压审讯标记逼供")
	var r: Dictionary = sys.attempt_solve(case, {"roll": 0.0})
	check(bool(r["solved"]), "弱证据下仍判侦破")
	check(bool(r["wrongful"]), "弱证据加逼供构成冤案")
	check(float(r["misjudgment_risk"]) > 0.0, "误判风险为正")
	# 证据充分且无逼供 => 不冤。
	var ok: Dictionary = sys.new_case("robbery", "r1")
	for k in sys.evidence_kinds():
		sys.add_evidence(ok, k, 1.0)
	var r2: Dictionary = sys.attempt_solve(ok, {"roll": 0.0})
	check(bool(r2["solved"]) and not bool(r2["wrongful"]), "证据充分不构成冤案")
	# 腐败串通隐匿证据、可能暴露。
	var corrupt: Dictionary = sys.new_case("smuggling", "r1")
	sys.add_evidence(corrupt, "physical", 0.8)
	var col: Dictionary = sys.collude(corrupt, {"roll": 0.0})
	check(bool(col["suppressed"]), "串通隐匿证据")
	check(float(sys.evidence_score(corrupt)) < 0.8 * float(PoliceScript.EVIDENCE_WEIGHTS["physical"]) + 1e-9, "串通后证据强度下降")
	check(bool(col["exposed"]), "低 roll 串通暴露")


func _test_undercover_informant() -> void:
	var sys = PoliceScript.new()
	var case: Dictionary = sys.new_case("narcotics", "r1")
	var inf: Dictionary = sys.use_informant(case, {"roll": 0.0})
	check(bool(inf["reliable"]), "线人可靠")
	check(float(case["leads"]) > 0.0, "线人补充线索")
	var uc: Dictionary = sys.deploy_undercover(case, {"roll": 0.0, "exposure_risk": 0.5})
	check(bool(uc["exposed"]), "低 roll 卧底暴露")
	check(bool((case["undercover"] as Dictionary)["exposed"]), "卧底暴露标记")
	var case2: Dictionary = sys.new_case("narcotics", "r1")
	var uc2: Dictionary = sys.deploy_undercover(case2, {"roll": 0.9, "exposure_risk": 0.5})
	check(not bool(uc2["exposed"]), "高 roll 卧底安全")
	check(sys.evidence_score(case2) > 0.0, "卧底取得证据")


func _test_private_security() -> void:
	var sys = PoliceScript.new()
	var firm: Dictionary = sys.new_security_firm("护卫公司", {"staff": 2, "funds": 1000000})
	var c: Dictionary = sys.take_contract(firm, "vip_protection", {})
	check(bool(c["ok"]) and bool(c["understaffed"]), "人手不足标记")
	var res: Dictionary = sys.resolve_contract(firm, c["contract"], {"roll": 0.0})
	check(bool(res["failure"]) and int(res["liability"]) > 0, "安保失职承担赔偿")
	# 人手充足、声誉良好：顺利履约。
	var firm2: Dictionary = sys.new_security_firm("大安保", {"staff": 20, "funds": 1000000, "reputation": 1.0})
	var c2: Dictionary = sys.take_contract(firm2, "escort", {})
	var funds0: int = int(firm2["funds"])
	var res2: Dictionary = sys.resolve_contract(firm2, c2["contract"], {"roll": 0.9})
	check(bool(res2["success"]) and int(res2["liability"]) == 0, "顺利履约无赔偿")
	check(int(firm2["funds"]) > funds0, "履约入账")
	check(not bool(sys.take_contract(firm2, "bogus")["ok"]), "未知安保业务被拒")
	sys.assign_staff(firm2, 5)
	check_eq(int(firm2["staff"]), 25, "补充人手")
