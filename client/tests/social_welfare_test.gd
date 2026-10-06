extends "res://tests/test_base.gd"
## 收养寄养与社会救助测试（任务 35；R85；design D41）。
## 覆盖：收养/寄养/低保/医疗/临时/流浪救助的资格审核、家庭匹配与安置、
##       家庭变故路由、慈善基金与善款挪用、社工个案、虐待举报与救助依赖等边界。

const WelfareScript = preload("res://sim/social_welfare.gd")


func _suite_name() -> String:
	return "social_welfare"


func run_tests() -> void:
	_test_tables()
	_test_adoption_review()
	_test_foster_and_aid_review()
	_test_home_match_and_placement()
	_test_assistance_disbursement()
	_test_child_crisis()
	_test_charity_fund()
	_test_social_worker_and_cases()
	_test_boundaries()


func _test_tables() -> void:
	var sys = WelfareScript.new()
	check_eq(sys.application_kinds().size(), 6, "六类救助/收养申请")
	check_eq(str(sys.application_name("dibao")), "低保", "低保名称")
	check_eq(sys.crisis_kinds().size(), 3, "三类家庭变故")
	check_eq(sys.social_worker_ranks().size(), 4, "社工四级职业路径")


func _test_adoption_review() -> void:
	var sys = WelfareScript.new()
	var good: Dictionary = sys.new_application("adoption", {"id": "a1", "age": 40, "income": 100000, "assets": 100000})
	var ok: Dictionary = sys.review_qualification(good, {"age": 40, "income": 100000, "assets": 100000})
	check(bool(ok["approved"]), "符合条件可收养")
	check_eq(str(good["status"]), "approved", "申请状态转为通过")
	# 多项不合格，原因逐条可查。
	var bad_app: Dictionary = sys.new_application("adoption", {"id": "a2"})
	var bad: Dictionary = sys.review_qualification(bad_app, {"age": 20, "income": 10000, "assets": 9000000, "criminal_record": true})
	check(not bool(bad["approved"]), "不合格被拒")
	var reasons: Array = bad["reasons"]
	check(reasons.has("too_young"), "记录年龄不足")
	check(reasons.has("income_too_low"), "记录收入不足")
	check(reasons.has("assets_too_high"), "记录资产过高")
	check(reasons.has("criminal_record"), "记录犯罪记录")


func _test_foster_and_aid_review() -> void:
	var sys = WelfareScript.new()
	# 寄养：收入、抚养能力、无犯罪无虐待。
	var foster_ok: Dictionary = sys.review_qualification(
		sys.new_application("foster", {}),
		{"income": 60000, "capacity": 3})
	check(bool(foster_ok["approved"]), "合格寄养家庭")
	var foster_bad: Dictionary = sys.review_qualification(
		sys.new_application("foster", {}),
		{"income": 1000, "capacity": 0, "abuse_history": true})
	check(not bool(foster_bad["approved"]), "不合格寄养家庭被拒")
	check((foster_bad["reasons"] as Array).has("abuse_history"), "记录虐待史")
	# 低保：人均收入低于线。
	var dibao_ok: Dictionary = sys.review_qualification(
		sys.new_application("dibao", {}),
		{"income": 24000, "household_size": 4, "assets": 0})
	check(bool(dibao_ok["approved"]), "低保符合条件")
	var dibao_bad: Dictionary = sys.review_qualification(
		sys.new_application("dibao", {}),
		{"income": 24000, "household_size": 1, "assets": 500000})
	check(not bool(dibao_bad["approved"]), "低保超线被拒")
	# 医疗/临时/流浪需对应情形。
	check(not bool(sys.review_qualification(sys.new_application("medical_aid", {}), {})["approved"]), "无医疗需求被拒")
	check(bool(sys.review_qualification(sys.new_application("medical_aid", {}), {"medical_need": true})["approved"]), "有医疗需求通过")
	check(not bool(sys.review_qualification(sys.new_application("temporary_aid", {}), {})["approved"]), "非危机被拒")
	check(not bool(sys.review_qualification(sys.new_application("homeless_relief", {}), {})["approved"]), "非流浪被拒")
	# 未知类型。
	check(not bool(sys.review_qualification(sys.new_application("bogus", {}), {})["ok"]), "未知申请类型")


func _test_home_match_and_placement() -> void:
	var sys = WelfareScript.new()
	var child: Dictionary = {"id": "c1", "name": "小明"}
	var applicants: Array = [
		{"id": "f1", "name": "甲家", "income": 200000, "housing_score": 0.9},
		{"id": "f2", "name": "乙家", "income": 0, "housing_score": 0.1, "criminal_record": true},
	]
	var m: Dictionary = sys.match_family(child, applicants, {})
	check(bool(m["matched"]) and str(m["family_id"]) == "f1", "匹配最优家庭")
	var none: Dictionary = sys.match_family(child, [{"id": "x", "criminal_record": true, "abuse_history": true}], {})
	check(not bool(none["matched"]), "无合格家庭")
	# 安置返回家庭接口，不维护成员。
	var placed: Dictionary = sys.place_child(child, {"id": "f1", "name": "甲家"}, "adoption", {"day": 10})
	check(bool(placed["ok"]) and bool(placed["family_notified"]), "安置通知家庭")
	var fi: Dictionary = placed["family_interface"]
	check_eq(str(fi["guardian_id"]), "f1", "监护人写入接口")
	check_eq(str(fi["custody"]), "adoption", "抚养类型收养")
	check(not bool(sys.place_child(child, {}, "adoption", {})["ok"]), "无家庭不可安置")
	# 监护评估。
	check(bool(sys.guardianship_assessment(child, {"id": "g1", "capacity": 1})["capable"]), "监护人具备能力")
	check(not bool(sys.guardianship_assessment(child, {"id": "g2", "incapacitated": true})["capable"]), "监护人失能被判无力")


func _test_assistance_disbursement() -> void:
	var sys = WelfareScript.new()
	var app: Dictionary = sys.new_application("dibao", {"id": "r1"})
	sys.review_qualification(app, {"income": 1000, "household_size": 1, "assets": 0})
	check_eq(str(app["status"]), "approved", "低保申请通过")
	var paid: Dictionary = sys.disburse_assistance(app, {}, {})
	check(int(paid["paid"]) > 0, "救助发放")
	check_eq(int(paid["paid"]), 120000, "低保 30 天标准发放")
	# 未通过不予发放。
	var pending: Dictionary = sys.new_application("dibao", {})
	check(not bool(sys.disburse_assistance(pending, {}, {})["ok"]), "未通过不发放")
	# 天数上限封顶。
	var capped: Dictionary = sys.disburse_assistance(app, {}, {"days": 9999})
	check_eq(int(capped["days"]), 365, "发放天数按上限封顶")


func _test_child_crisis() -> void:
	var sys = WelfareScript.new()
	var orphan: Dictionary = sys.child_in_crisis({"id": "c2"}, "orphan", {})
	check_eq(str(orphan["route"]), "foster", "孤儿进入寄养")
	var inst: Dictionary = sys.child_in_crisis({"id": "c3"}, "abandoned", {"foster_available": false})
	check_eq(str(inst["route"]), "institution", "无寄养资源转福利机构")
	var kin: Dictionary = sys.child_in_crisis({"id": "c4"}, "guardian_disabled", {"has_relative": true})
	check_eq(str(kin["route"]), "kinship_care", "父母失能优先亲属照料")
	check(not bool(sys.child_in_crisis({"id": "c5"}, "bogus", {})["ok"]), "未知变故被拒")


func _test_charity_fund() -> void:
	var sys = WelfareScript.new()
	var fund: Dictionary = sys.new_charity_fund("暖心基金", {})
	sys.donate(fund, 100000)
	check_eq(int(fund["balance"]), 100000, "募捐入账")
	sys.spend_fund(fund, "助学", 30000)
	check_eq(int(fund["spent"]), 30000, "支出入账")
	check(not bool(sys.spend_fund(fund, "超额", 999999)["ok"]), "余额不足不可支出")
	var settle: Dictionary = sys.settle_fund(fund, {"overhead_rate": 0.1})
	check_eq(int(settle["overhead"]), 10000, "管理费结算")
	check_eq(int(settle["to_cause"]), 90000, "公益用途金额")
	var audit: Dictionary = sys.audit_transparency(fund, {"disclosed": 30000})
	check_eq(str(audit["grade"]), "A", "充分披露评 A")
	# 善款挪用被查获。
	var mis: Dictionary = sys.misappropriate(fund, 20000, {"roll": 0.0, "detect_risk": 0.4})
	check(bool(mis["detected"]) and bool(mis["criminal"]), "挪用被查获并担刑责")
	var audit2: Dictionary = sys.audit_transparency(fund, {"disclosed": 10000})
	check(float(audit2["transparency"]) < float(audit["transparency"]), "挪用后透明度下降")


func _test_social_worker_and_cases() -> void:
	var sys = WelfareScript.new()
	var worker: Dictionary = sys.new_social_worker("w1", {"name": "小李"})
	check_eq(int(worker["rank_index"]), 0, "初始为社工助理")
	var case: Dictionary = sys.new_case(worker, "family_9", {"kind": "family"})
	check(not bool(case["closed"]), "新个案开启")
	var last: Dictionary = {}
	for i in 4:
		last = sys.follow_up(case, "第 %d 次家访" % (i + 1))
	check(bool(last["closed"]) and int(case["visits"]) == 4, "四次跟进后结案")
	var closed: Dictionary = sys.close_case(worker, case)
	check_eq(int(closed["cases_closed"]), 1, "结案累计业绩")
	# 晋升。
	var veteran: Dictionary = sys.new_social_worker("w2", {"cases_closed": 30})
	var promo: Dictionary = sys.promote_social_worker(veteran)
	check(bool(promo["promoted"]) and int(promo["rank_index"]) == 1, "晋级为社工")
	check_eq(int(veteran["salary"]), 6000, "薪酬随职级提升")


func _test_boundaries() -> void:
	var sys = WelfareScript.new()
	# 虐待举报成立：撤销监护并转寄养。
	var child: Dictionary = {"id": "c6"}
	var guardian: Dictionary = {"id": "g6"}
	var abuse: Dictionary = sys.report_abuse(child, guardian, {"evidence": 0.8, "roll": 0.0})
	check(bool(abuse["substantiated"]) and str(abuse["action"]) == "remove_custody", "虐待举报成立撤销监护")
	check(bool(guardian["abuse_history"]), "记录监护人虐待史")
	check_eq(str(child["welfare_route"]), "foster", "受虐儿童转寄养")
	var cleared: Dictionary = sys.report_abuse({"id": "c7"}, {"id": "g7"}, {"evidence": 0.2, "roll": 0.9})
	check(not bool(cleared["substantiated"]), "证据不足不予认定")
	# 救助依赖与脱困。
	var dependent: Dictionary = {"aid_months": 24, "employable": 0.0}
	var dep: Dictionary = sys.welfare_dependency(dependent, {})
	check(float(dep["dependency"]) > 0.0 and not bool(dep["escaped"]), "长期受助形成依赖")
	var escaped: Dictionary = sys.welfare_dependency(dependent, {"employed": true})
	check(bool(escaped["escaped"]) and str(escaped["route_out"]) == "employment", "就业实现脱困")
