extends "res://tests/test_base.gd"
## 债务服务、当铺与小贷测试（任务 35、35.1；R83；design D39）。
## 重点覆盖任务 35.1：合法催收不违法；灰色催收产生违法标记/法律后果/人身风险，
## 且与利率上限、无牌经营等合规边界交互正确。

const DebtScript = preload("res://sim/debt_service.gd")


func _suite_name() -> String:
	return "debt_service"


func run_tests() -> void:
	_test_tables()
	_test_compliance()
	_test_credit_and_disburse()
	_test_legal_collection()
	_test_gray_collection_consequences()
	_test_collection_compliance_interaction()
	_test_distress_and_boundaries()


## 构造一笔完全合规的信贷：持牌放贷人、利率低于上限。
func _compliant(sys) -> Array:
	var lender: Dictionary = sys.new_lender("bank", {"license": true})
	var loan: Dictionary = sys.new_loan("l1", "micro_loan", 10000, {"rate": 0.12, "lender": "bank", "term_days": 365})
	return [lender, loan]


func _test_tables() -> void:
	var sys = DebtScript.new()
	check_eq(sys.business_keys().size(), 6, "六类债务业务")
	check_eq(sys.collection_mode_keys().size(), 5, "五种催收方式")
	check(sys.is_legal_collection("reminder"), "提醒属合法催收")
	check(sys.is_legal_collection("litigation"), "诉讼属合法催收")
	check(not sys.is_legal_collection("harassment"), "骚扰属灰色催收")
	check(sys.is_gray_collection("violence"), "暴力催收属灰色")
	check(sys.business_available("p2p", 2015), "P2P 在 2015 可用")
	check(not sys.business_available("p2p", 2022), "P2P 在 2022 不可用")
	check_near(sys.interest_cap("micro_loan"), 0.24, 1e-9, "小贷利率上限")


func _test_compliance() -> void:
	var sys = DebtScript.new()
	var pair: Array = _compliant(sys)
	var lender: Dictionary = pair[0]
	var loan: Dictionary = pair[1]
	check(sys.rate_compliant(loan), "利率合规")
	var status: Dictionary = sys.compliance_status(loan, lender)
	check(bool(status["compliant"]), "合规借款")
	# 利率超上限。
	var over: Dictionary = sys.new_loan("l2", "micro_loan", 10000, {"rate": 0.5, "lender": "bank"})
	check(not sys.rate_compliant(over), "超上限利率不合规")
	check((sys.compliance_status(over, lender)["violations"] as Array).has("interest_over_cap"), "记录利率违规")
	# 无牌经营。
	var unlicensed: Dictionary = sys.new_lender("gray", {"license": false})
	var l3: Dictionary = sys.new_loan("l3", "micro_loan", 10000, {"rate": 0.12, "lender": "gray"})
	check(not sys.license_status(l3, unlicensed), "无牌经营")
	var reg: Dictionary = sys.regulate(l3, unlicensed)
	check(bool(reg["illegal"]), "无牌放贷入违法处理")
	check((reg["violations"] as Array).has("unlicensed"), "记录无牌违规")
	check_eq(int(unlicensed["violations"]), 1, "放贷人违法计数")
	# 典当需抵押。
	var pawn: Dictionary = sys.new_loan("l4", "pawn", 10000, {"rate": 0.12, "lender": "bank"})
	check((sys.compliance_status(pawn, lender)["violations"] as Array).has("missing_collateral"), "典当缺抵押")


func _test_credit_and_disburse() -> void:
	var sys = DebtScript.new()
	var pair: Array = _compliant(sys)
	var lender: Dictionary = pair[0]
	var loan: Dictionary = pair[1]
	var good: Dictionary = {"income": 100000.0, "debt": 0.0, "credit_history": 0.9}
	check(bool(sys.assess_credit(good, loan, {})["approved"]), "优质借款人获批")
	var poor: Dictionary = {"income": 1000.0, "debt": 50000.0, "credit_history": 0.3}
	check(not bool(sys.assess_credit(poor, loan, {})["approved"]), "劣质借款人被拒")
	# 砍头息：到手金额低于本金。
	var cut: Dictionary = sys.new_loan("l5", "micro_loan", 10000, {"rate": 0.12, "cut_interest": 1000})
	var disb: Dictionary = sys.disburse(cut, lender, {})
	check_eq(int(disb["amount"]), 9000, "砍头息后到手金额")
	var approve: Dictionary = sys.approve_loan(good, loan, lender, {})
	check(bool(approve["approved"]) and bool((approve["disbursement"] as Dictionary)["ok"]), "审批放款一步完成")


func _test_legal_collection() -> void:
	var sys = DebtScript.new()
	var pair: Array = _compliant(sys)
	var lender: Dictionary = pair[0]
	var loan: Dictionary = pair[1]
	var reminder: Dictionary = sys.collect(loan, "reminder", lender, {})
	check(bool(reminder["legal_collection"]), "提醒属合法催收")
	check(not bool(reminder["illegal"]), "合法催收不违法")
	check_eq(str(reminder["legal_consequence"]), "none", "合法催收无法律后果")
	check_near(float(reminder["personal_risk"]), 0.0, 1e-9, "合法催收无人身风险")
	check(bool(reminder["enforceable"]), "合规借款可执行")
	var lit: Dictionary = sys.collect(loan, "litigation", lender, {})
	check(not bool(lit["illegal"]), "诉讼催收不违法")
	check(not bool(loan["illegal_collection"]), "未标记灰色催收")


func _test_gray_collection_consequences() -> void:
	var sys = DebtScript.new()
	var pair: Array = _compliant(sys)
	var lender: Dictionary = pair[0]
	var loan: Dictionary = pair[1]
	# 骚扰。
	var harass: Dictionary = sys.collect(loan, "harassment", lender, {"injury_roll": 1.0, "suicide_roll": 1.0})
	check(bool(harass["illegal"]), "骚扰构成违法")
	check(float(harass["personal_risk"]) > 0.0, "骚扰有人身风险")
	check_eq(str(harass["victim_harm"]), "distress", "骚扰造成精神困扰")
	check_eq(str(harass["legal_consequence"]), "civil", "骚扰承担民事责任")
	# 上门施压。
	var home: Dictionary = sys.collect(loan, "home_visit", lender, {"injury_roll": 1.0, "suicide_roll": 1.0})
	check_eq(str(home["legal_consequence"]), "administrative", "上门施压承担行政责任")
	check(float(home["personal_risk"]) > float(harass["personal_risk"]), "上门风险高于骚扰")
	# 暴力催收致伤。
	var violence: Dictionary = sys.collect(loan, "violence", lender, {"injury_roll": 0.0, "suicide_roll": 1.0})
	check(bool(violence["illegal"]), "暴力催收违法")
	check(bool(violence["injury"]), "暴力催收致伤")
	check_eq(str(violence["victim_harm"]), "injury", "人身伤害结果")
	check_eq(str(violence["legal_consequence"]), "criminal", "暴力催收承担刑事责任")
	check(float(violence["personal_risk"]) > float(harass["personal_risk"]), "暴力风险最高")
	check(bool(loan["illegal_collection"]), "借款被标记灰色催收")
	# 催收致自杀。
	var pair2: Array = _compliant(sys)
	var loan2: Dictionary = pair2[1]
	var suicide: Dictionary = sys.collect(loan2, "violence", pair2[0], {"injury_roll": 1.0, "suicide_roll": 0.0})
	check(bool(suicide["suicide"]), "催收致自杀")
	check_eq(str(suicide["victim_harm"]), "death", "死亡后果")
	var rec: Dictionary = sys.record_suicide_incident(loan2, pair2[0], {})
	check(bool(rec["criminal_liability"]), "致自杀承担刑事与道德后果")


func _test_collection_compliance_interaction() -> void:
	var sys = DebtScript.new()
	# 合规借款上的灰色催收。
	var pair: Array = _compliant(sys)
	var loan_ok: Dictionary = pair[1]
	var gray_ok: Dictionary = sys.collect(loan_ok, "violence", pair[0], {"injury_roll": 1.0, "suicide_roll": 1.0})
	check(not bool(gray_ok["aggravated"]), "合规借款不加重")
	# 违规借款上的灰色催收：无牌 + 超上限 => 加重。
	var unlicensed: Dictionary = sys.new_lender("gray", {"license": false})
	var bad: Dictionary = sys.new_loan("b1", "micro_loan", 10000, {"rate": 0.5, "lender": "gray"})
	var gray_bad: Dictionary = sys.collect(bad, "violence", unlicensed, {"injury_roll": 1.0, "suicide_roll": 1.0})
	check(bool(gray_bad["aggravated"]), "违规借款加重后果")
	check(float(gray_bad["personal_risk"]) > float(gray_ok["personal_risk"]), "违规叠加灰色催收风险更高")
	check_eq(str(gray_bad["legal_consequence"]), "criminal", "叠加后仍为刑事")
	# 合法催收对违规借款：仍不违法，但不可执行 / 超上限部分不受保护。
	var unlicensed2: Dictionary = sys.new_lender("gray2", {"license": false})
	var illegal_loan: Dictionary = sys.new_loan("b2", "micro_loan", 10000, {"rate": 0.12, "lender": "gray2"})
	var lit: Dictionary = sys.collect(illegal_loan, "litigation", unlicensed2, {})
	check(not bool(lit["illegal"]), "合法催收路径不因放贷违规而变为违法")
	check(not bool(lit["enforceable"]), "无牌放贷的债权不可执行")
	check((lit["violations"] as Array).has("unlicensed"), "记录放贷违规")
	var over_loan: Dictionary = sys.new_loan("b3", "micro_loan", 10000, {"rate": 0.5, "lender": "bank", "term_days": 365})
	over_loan["outstanding"] = 15000
	var lit2: Dictionary = sys.collect(over_loan, "litigation", pair[0], {})
	check(int(lit2["recoverable"]) < 15000, "超出利率上限部分不受保护")
	check_near(float(lit2["recoverable"]), 12400.0, 1.0, "仅按法定本息可执行")


func _test_distress_and_boundaries() -> void:
	var sys = DebtScript.new()
	var pair: Array = _compliant(sys)
	var loan: Dictionary = pair[1]
	# 坏账回收。
	var d: Dictionary = sys.default_loan(loan, {})
	check(int(d["bad_debt"]) > 0, "无担保产生坏账")
	var secured: Dictionary = sys.new_loan("s1", "pawn", 10000, {"rate": 0.12, "collateral_value": 4000})
	var d2: Dictionary = sys.default_loan(secured, {})
	check(int(d2["bad_debt"]) < int(d["bad_debt"]), "有抵押降低坏账")
	# 跑路。
	var abscond: Dictionary = sys.abscond(sys.new_loan("a1", "private_lending", 5000, {"rate": 0.1}), {"roll": 0.0})
	check(bool(abscond["absconded"]) and bool(abscond["recovered"]), "低 roll 追偿成功")
	# 套路贷。
	var trick: Dictionary = sys.new_loan("t1", "private_lending", 10000, {"rate": 0.1, "cut_interest": 2000})
	check(bool(sys.predatory_loan(trick, {})["predatory"]), "砍头息构成套路贷")
	# 非法集资。
	var unlicensed: Dictionary = sys.new_lender("gray", {"license": false})
	check(bool(sys.illegal_fundraising(unlicensed, 1000000, {"public": true})["illegal"]), "无牌公开募资构成非法集资")
	var licensed: Dictionary = sys.new_lender("bank", {"license": true})
	check(not bool(sys.illegal_fundraising(licensed, 1000000, {"public": true})["illegal"]), "持牌募资合法")
	# 以贷养贷。
	var old: Dictionary = sys.new_loan("o1", "private_lending", 10000, {"rate": 0.2})
	var newl: Dictionary = sys.new_loan("n1", "private_lending", 12000, {"rate": 0.2, "service_fee": 500})
	var roll: Dictionary = sys.borrow_to_repay(old, newl, {})
	check(bool(roll["rolled_over"]) and int(roll["snowball_debt"]) > 10000, "以贷养贷债务雪球")
	# 债务重组。
	var rest: Dictionary = sys.new_loan("r1", "private_lending", 10000, {"rate": 0.36})
	var rr: Dictionary = sys.restructure(rest, {"haircut": 0.2, "rate_cut": 0.1, "extend_days": 180})
	check_eq(int(rr["outstanding"]), 8000, "本金减免")
	check_near(float(rr["rate"]), 0.26, 1e-9, "降息")
	# 个人破产时代限定。
	var borrower: Dictionary = {"credit_history": 0.8}
	var loans: Array = [sys.new_loan("p1", "private_lending", 5000, {"rate": 0.1})]
	var bank: Dictionary = sys.personal_bankruptcy(borrower, loans, 2022, {})
	check(bool(bank["ok"]) and int(bank["discharged"]) > 0, "2022 允许个人破产")
	var too_early: Dictionary = sys.personal_bankruptcy({"credit_history": 0.8}, [sys.new_loan("p2", "private_lending", 5000, {})], 2015, {})
	check(not bool(too_early["ok"]), "2015 不允许个人破产")
