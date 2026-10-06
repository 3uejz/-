extends "res://tests/test_base.gd"
## 殡葬、器官捐献与纪念测试（任务 36；R86；design D42）。
## 覆盖：殡葬方式与执行、遗产不足边界、器官/遗体捐献登记审查撤销与分配移植、
##       纪念碑祭扫数字纪念、遗嘱执行、殡葬行业暴利监管与陋习改革、
##       无人认领遗体与捐献争议。

const FuneralScript = preload("res://sim/funeral.gd")


func _suite_name() -> String:
	return "funeral"


func run_tests() -> void:
	_test_tables()
	_test_arrange_and_execute()
	_test_insufficient_estate()
	_test_donation_flow()
	_test_memorial()
	_test_will_execution()
	_test_industry()
	_test_boundaries()


func _test_tables() -> void:
	var sys = FuneralScript.new()
	check_eq(sys.methods().size(), 5, "五种殡葬方式")
	check_eq(str(sys.method_def("cremation")["name"]), "火化", "火化名称")
	check_eq(sys.grave_types().size(), 3, "三种墓位")
	check_eq(sys.donation_organs().size(), 6, "六类可捐献器官")
	check_eq(sys.memorial_kinds().size(), 4, "四种纪念形式")


func _test_arrange_and_execute() -> void:
	var sys = FuneralScript.new()
	var state: Dictionary = sys.new_state()
	var arr: Dictionary = sys.arrange_funeral({"id": "d1", "estate": 500000}, state, {"method": "burial", "grave": "standard"})
	check(bool(arr["ok"]), "安排殡葬成功")
	check_eq(str(arr["method"]), "burial", "土葬")
	check_eq(int(arr["cost"]), 60000 + 200000, "费用含墓位")
	check(bool(arr["affordable"]), "遗产充足")
	var ex: Dictionary = sys.execute_funeral(state, {})
	check(bool(ex["executed"]), "执行殡葬")
	check_eq(int(ex["paid"]), 260000, "支付费用")
	check(float(ex["meaning"]) > 0.0, "执行提升意义感")
	check(float(state["family_relations"]) > 0.0, "执行提升家庭关系")
	# 未安排不可执行。
	check(not bool(sys.execute_funeral(sys.new_state(), {})["ok"]), "未安排不可执行")


func _test_insufficient_estate() -> void:
	var sys = FuneralScript.new()
	var state: Dictionary = sys.new_state()
	var arr: Dictionary = sys.arrange_funeral({"id": "d2", "estate": 1000}, state, {"method": "burial"})
	check(not bool(arr["affordable"]), "遗产不足无法负担")
	check_eq(str(arr["reason"]), "insufficient_estate", "标记遗产不足")
	var ex: Dictionary = sys.execute_funeral(state, {})
	check(not bool(ex["ok"]) and str(ex["reason"]) == "insufficient_estate", "遗产不足拒绝下葬")
	# 公益救助兜底。
	var rescued: Dictionary = sys.execute_funeral(state, {"public_assistance": true})
	check(bool(rescued["ok"]) and bool(rescued["public_assistance"]), "公益救助可下葬")
	check_eq(int(rescued["paid"]), 0, "公益救助无需支付")


func _test_donation_flow() -> void:
	var sys = FuneralScript.new()
	var state: Dictionary = sys.new_state()
	# 生前登记。
	var reg: Dictionary = sys.register_donation(state, {"organs": ["heart", "kidney"]})
	check(bool(reg["registered"]) and (reg["organs"] as Array).size() == 2, "生前登记捐献")
	check(not bool(sys.register_donation(state, {"organs": ["bogus"]})["ok"]), "未知器官被拒")
	# 生前不可由家属撤销。
	check_eq(str(sys.revoke_donation(state, {})["reason"]), "donor_alive", "生前不可撤销")
	# 伦理与法律审查。
	var ethics: Dictionary = sys.review_ethics(state, {"roll": 0.0})
	check(bool(ethics["approved"]) and bool(ethics["legal"]), "伦理法律审查通过")
	# 器官分配：按紧迫度匹配。
	var recipients: Array = [
		{"id": "r1", "organ": "heart", "urgency": 0.9},
		{"id": "r2", "organ": "heart", "urgency": 0.5},
		{"id": "r3", "organ": "kidney", "urgency": 0.7},
	]
	var alloc: Dictionary = sys.allocate_organs(state, recipients, {})
	check_eq(int(alloc["count"]), 2, "分配两个器官")
	var allocs: Array = alloc["allocated"]
	check_eq(str(allocs[0]["recipient_id"]), "r1", "心脏给最紧迫者")
	# 移植接口。
	var tx: Dictionary = sys.transplant({"id": "r1"}, "heart", {"roll": 0.9})
	check(bool(tx["success"]) and not bool(tx["rejection"]), "移植成功")
	var tx2: Dictionary = sys.transplant({"id": "r2"}, "heart", {"roll": 0.0})
	check(bool(tx2["rejection"]), "低 roll 排异")
	# 死后家属撤销。
	var state2: Dictionary = sys.new_state()
	sys.register_donation(state2, {})
	sys.review_ethics(state2, {"roll": 0.0})
	var rev: Dictionary = sys.revoke_donation(state2, {"deceased": true, "by": "family"})
	check(bool(rev["revoked"]), "家属可撤销捐献")
	check(not bool(sys.allocate_organs(state2, recipients, {})["ok"]), "撤销后不可分配")


func _test_memorial() -> void:
	var sys = FuneralScript.new()
	var state: Dictionary = sys.new_state()
	var m: Dictionary = sys.build_memorial(state, "monument", {"name": "先人碑"})
	check(bool(m["ok"]) and float(m["meaning"]) > 0.0, "立碑提升意义感")
	check(not bool(sys.build_memorial(state, "bogus", {})["ok"]), "未知纪念形式被拒")
	var sweep: Dictionary = sys.tomb_sweeping(state, {"kind": "monument"})
	check(bool(sweep["ok"]) and int(sweep["visits"]) == 1, "祭扫累计次数")
	check(not bool(sys.tomb_sweeping(state, {"kind": "family_grave"})["ok"]), "无对应纪念不可祭扫")
	var dig: Dictionary = sys.create_digital_memorial(state, {"visits": 5})
	check(bool(dig["created"]) and int(dig["visits"]) == 5, "数字纪念可访问")


func _test_will_execution() -> void:
	var sys = FuneralScript.new()
	var state: Dictionary = sys.new_state()
	var will: Dictionary = {
		"valid": true, "funeral_method": "tree_burial", "grave": "family",
		"donation": true, "organs": ["cornea"], "beneficiaries": [{"id": "h1", "share": 1.0}],
	}
	var res: Dictionary = sys.execute_will(will, {"id": "d3"}, state)
	check(bool(res["executed"]), "有效遗嘱执行")
	check_eq(str(state["wishes"]["method"]), "tree_burial", "记录生前殡葬意愿")
	check(bool(state["donation"]["registered"]), "按意愿登记捐献")
	# 据此安排殡葬。
	var arr: Dictionary = sys.arrange_funeral({}, state, {})
	check_eq(str(arr["method"]), "tree_burial", "按生前意愿选树葬")
	check_eq(str(arr["grave"]), "family", "按生前意愿选家族墓")
	# 无效遗嘱不执行。
	var state2: Dictionary = sys.new_state()
	var bad: Dictionary = sys.execute_will({"valid": false}, {"id": "d4"}, state2)
	check(not bool(bad["executed"]), "无效遗嘱不执行")


func _test_industry() -> void:
	var sys = FuneralScript.new()
	var home: Dictionary = sys.new_funeral_home("归安堂", {"price_mult": 3.0, "balance": 0})
	var q: Dictionary = sys.quote_service(home, "cremation", {})
	check_eq(int(q["price"]), 60000, "三倍溢价报价")
	var sale: Dictionary = sys.settle_sale(home, "cremation", {})
	check_eq(int(sale["profit"]), 40000, "暴利利润")
	check(bool(sale["excessive"]), "暴利被标记")
	# 监管查处。
	var reg: Dictionary = sys.regulate_market(home, {"roll": 0.0, "detect_rate": 0.5, "fine": 200000})
	check(bool(reg["detected"]) and int(reg["fine"]) > 0, "暴利被查处")
	check(bool(home["regulated"]), "标记已受监管")
	# 陋习改革。
	var state: Dictionary = sys.new_state()
	state["industry"] = home
	var reform: Dictionary = sys.reform_customs(state, {"price_cut": 0.5})
	check(bool(reform["ok"]) and float(reform["price_mult"]) < 3.0, "改革降低溢价")
	check(not bool(sys.reform_customs(sys.new_state(), {})["ok"]), "无经营体不可改革")


func _test_boundaries() -> void:
	var sys = FuneralScript.new()
	# 无人认领遗体。
	var state: Dictionary = sys.new_state()
	check(not bool(sys.unclaimed_body(state, {})["ok"]), "非无主遗体被拒")
	var un: Dictionary = sys.unclaimed_body(state, {"unclaimed": true, "action": "public_cremation"})
	check(bool(un["ok"]) and bool(un["anonymous"]), "无主遗体公益火化")
	# 捐献争议。
	var state2: Dictionary = sys.new_state()
	sys.register_donation(state2, {})
	sys.review_ethics(state2, {"roll": 0.0})
	var disp: Dictionary = sys.donation_dispute(state2, {"roll": 0.0, "revoke": true})
	check(bool(disp["dispute"]) and bool(disp["resolved"]), "捐献争议被裁定")
	check(bool(disp["revoked"]), "争议裁定撤销捐献")
