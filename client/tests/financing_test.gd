extends "res://tests/test_base.gd"
## 创业融资测试（任务 13；R47.7-8；design D7）。
## 覆盖：股权表、逐轮融资与稀释、估值、对赌回购/失去控制权、IPO 与并购退出。

const FinancingScript = preload("res://sim/financing.gd")
const EconomyScript = preload("res://sim/economy.gd")


func _suite_name() -> String:
	return "financing"


func run_tests() -> void:
	_test_cap_table()
	_test_raise_rounds()
	_test_estimate_valuation()
	_test_vam()
	_test_exit()


func _econ():
	return EconomyScript.new(1)


func _make_company(account: String, history: Array = []) -> Dictionary:
	return {"account": account, "revenue_history": history}


# --- 股权表 ---

func _test_cap_table() -> void:
	var sys = FinancingScript.new()
	var cap: Dictionary = sys.new_cap_table("co.x")
	check_near(sys.founder_equity(cap), 1.0, 0.0001, "创始人初始 100%")
	check_near(sys.investor_equity(cap), 0.0, 0.0001, "无投资人")
	check_eq(sys.next_stage(cap), "seed", "首轮为种子轮")
	check(bool(cap["control"]), "初始控股")


# --- 逐轮融资与稀释 ---

func _test_raise_rounds() -> void:
	var sys = FinancingScript.new()
	var econ = _econ()
	var company: Dictionary = _make_company("company.co.x")
	var cap: Dictionary = sys.new_cap_table("co.x")
	# 种子轮：出让 15%，估值 1 亿（最小单位）。
	var r1: Dictionary = sys.raise_round(cap, company, econ, {"equity_pct": 0.15, "valuation": 100000000})
	check(bool(r1["ok"]) and r1["stage"] == "seed", "种子轮成功")
	check_eq(int(r1["investment"]), 15000000, "融资额为估值乘以出让比例")
	check_near(sys.founder_equity(cap), 0.85, 0.0001, "创始人被稀释至 85%")
	check_eq(econ.liquid("company.co.x"), 15000000, "融资款进入公司账户")
	check_eq(sys.next_stage(cap), "angel", "下一轮为天使轮")
	# 越轮融资拒绝。
	check_eq(str(sys.raise_round(cap, company, econ, {"stage": "b"})["reason"]), "bad_stage", "越轮融资拒绝")
	# 依次走完天使/A/B/C 轮。
	sys.raise_round(cap, company, econ, {"equity_pct": 0.15, "valuation": 100000000})
	sys.raise_round(cap, company, econ, {"equity_pct": 0.15, "valuation": 100000000})
	sys.raise_round(cap, company, econ, {"equity_pct": 0.10, "valuation": 100000000})
	sys.raise_round(cap, company, econ, {"equity_pct": 0.10, "valuation": 100000000})
	check_eq(sys.next_stage(cap), "", "C 轮后无后续轮次")
	check_eq(str(sys.raise_round(cap, company, econ, {})["reason"]), "no_more_rounds", "轮次耗尽拒绝")
	check_near(sys.founder_equity(cap), 0.49744125, 0.000001, "多轮后创始人持股")
	check_near(sys.founder_equity(cap) + sys.investor_equity(cap), 1.0, 0.000001, "股权表归一")
	check(bool(cap["control"]), "多轮后仍控股")
	check_eq(econ.liquid("company.co.x"), 65000000, "累计融资额入账")
	# 期权池稀释。
	sys.dilute(cap, 0.10)
	check_near(sys.founder_equity(cap), 0.49744125 * 0.9, 0.000001, "期权池稀释创始人")
	check_near(sys.holder_equity(cap, "esop"), 0.10, 0.000001, "期权池获 10%")


# --- 估值 ---

func _test_estimate_valuation() -> void:
	var sys = FinancingScript.new()
	var empty: Dictionary = _make_company("company.co.e")
	check_eq(sys.estimate_valuation(empty), FinancingScript.MIN_VALUATION, "无营收取估值下限")
	var company: Dictionary = _make_company("company.co.v", [
		{"day": 1, "revenue": 200000, "costs": 0, "profit": 200000},
		{"day": 2, "revenue": 300000, "costs": 0, "profit": 300000},
	])
	var low: int = sys.estimate_valuation(company, 1.0)
	var high: int = sys.estimate_valuation(company, 2.5)
	check(low > FinancingScript.MIN_VALUATION, "有营收估值高于下限")
	check(high > low, "市场情绪推高估值")
	check_near(sys.estimate_valuation(company, 1.0, 0.0), 300000.0 * 365.0 * 8.0, 1.0, "增长由参数覆盖")


# --- 对赌 ---

func _test_vam() -> void:
	var sys = FinancingScript.new()
	var econ = _econ()
	var company: Dictionary = _make_company("company.co.vam")
	econ.open_account("company.co.vam", 30000000)
	var cap: Dictionary = sys.new_cap_table("co.vam")
	cap["valuation"] = 100000000
	check(bool(sys.settle_vam(cap, company, econ, 1000, 2000)["passed"]), "达标通过")
	# 未达标且有资力 → 自动回购。
	var r: Dictionary = sys.settle_vam(cap, company, econ, 2000, 1000)
	check(str(r["remedy"]) == "repurchase", "有资力时自动回购")
	check_eq(int(r["cost"]), 20000000, "回购金额为估值两成")
	check_eq(econ.liquid("company.co.vam"), 10000000, "回购扣减公司资金")
	# 无力回购 → 让渡控制权并可能被踢出。
	var poor: Dictionary = _make_company("company.co.poor")
	econ.open_account("company.co.poor", 0)
	var cap2: Dictionary = sys.new_cap_table("co.poor")
	cap2["holders"] = [
		{"id": "founder", "name": "创始人", "type": "founder", "equity": 0.5, "invested": 0},
		{"id": "inv.a", "name": "投资人", "type": "investor", "equity": 0.5, "invested": 0},
	]
	var rc: Dictionary = sys.settle_vam(cap2, poor, econ, 2000, 1000)
	check(str(rc["remedy"]) == "control", "无力回购触发失去控制权")
	check(bool(rc["kicked_out"]), "创始人被踢出局")
	check(not bool(cap2["control"]), "控股标记失效")


# --- 退出 ---

func _test_exit() -> void:
	var sys = FinancingScript.new()
	var econ = _econ()
	var company: Dictionary = _make_company("company.co.exit")
	var cap: Dictionary = sys.new_cap_table("co.exit")
	cap["holders"] = [
		{"id": "founder", "name": "创始人", "type": "founder", "equity": 0.5, "invested": 0},
		{"id": "inv.a", "name": "投资人", "type": "investor", "equity": 0.5, "invested": 0},
	]
	var r: Dictionary = sys.exit(cap, company, econ, "ipo", {"valuation": 1000000000, "owner_account": "owner"})
	check(bool(r["ok"]) and r["kind"] == "ipo", "IPO 退出成功")
	check_eq(int(r["proceeds"]), 500000000, "创始人按持股获得退出收益")
	check_eq(econ.liquid("owner"), 500000000, "退出收益进入创始人账户")
	check_eq(str(sys.exit(cap, company, econ, "ipo")["reason"]), "exited", "不可重复退出")
	# 并购退出与非法类型。
	var cap2: Dictionary = sys.new_cap_table("co.m")
	var r2: Dictionary = sys.exit(cap2, company, econ, "acquired", {"valuation": 400000000, "owner_account": "owner"})
	check(bool(r2["ok"]) and int(r2["proceeds"]) == 400000000, "并购按 100% 持股获全额")
	check_eq(str(sys.exit(sys.new_cap_table("co.k"), company, econ, "nope")["reason"]), "bad_kind", "非法退出类型拒绝")
