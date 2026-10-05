extends "res://tests/test_base.gd"
## 创业经营测试（任务 13；R14；design D7）。
## 覆盖：注册校验与本金转账、选址/营业/打烊、进货与定价、营业客流收入与缺货、
##       雇佣解雇与欠薪忠诚、离职、纳税、扩张、资不抵债与破产清算。

const CompanyScript = preload("res://sim/company.gd")
const EconomyScript = preload("res://sim/economy.gd")
const RngScript = preload("res://sim/rng.gd")
const BaselineScript = preload("res://sim/baseline.gd")


func _suite_name() -> String:
	return "company"


func run_tests() -> void:
	BaselineScript.clear_overrides()
	_test_register()
	_test_site_stock_price()
	_test_tick_day_revenue_and_shortage()
	_test_payroll_and_resign()
	_test_tax_and_expand()
	_test_bankruptcy()
	BaselineScript.clear_overrides()


func _econ(owner_cash: int):
	var econ = EconomyScript.new(1)
	econ.open_account("owner", owner_cash)
	return econ


func _open_shop(econ, owner_cash: int = 10000000, area: float = 100.0, rent: int = 30000) -> Dictionary:
	if not econ.has_account("owner"):
		econ.open_account("owner", owner_cash)
	var r: Dictionary = CompanyScript.new().register_company(econ, "owner", {
		"kind": "company", "name": "测试公司", "capital": 5000000, "id": "co.a",
	})
	var co: Dictionary = r["company"]
	CompanyScript.new().choose_site(co, "region.a", area, rent)
	CompanyScript.new().open_shop(co)
	co["reputation"] = 80.0
	return co


# --- 注册 ---

func _test_register() -> void:
	var sys = CompanyScript.new()
	var econ = _econ(10000000)
	check_eq(str(sys.register_company(econ, "owner", {"kind": "nope", "name": "x", "capital": 1})["reason"]), "bad_kind", "非法类型拒绝")
	check_eq(str(sys.register_company(econ, "owner", {"kind": "company", "name": "", "capital": 1000000})["reason"]), "empty_name", "空名拒绝")
	check_eq(str(sys.register_company(econ, "owner", {"kind": "company", "name": "x", "capital": 100})["reason"]), "insufficient_capital", "本金不足门槛拒绝")
	check_eq(str(sys.register_company(econ, "nobody", {"kind": "company", "name": "x", "capital": 1000000})["reason"]), "no_owner_account", "无业主账户拒绝")
	# 资金不足
	var poor = EconomyScript.new(1)
	poor.open_account("owner", 500000)
	check_eq(str(sys.register_company(poor, "owner", {"kind": "company", "name": "x", "capital": 1000000})["reason"]), "insufficient_funds", "业主资金不足拒绝")
	# 成功且本金转入公司账户（守恒）
	var before: int = econ.liquid("owner")
	var r: Dictionary = sys.register_company(econ, "owner", {"kind": "company", "name": "测试公司", "capital": 2000000, "id": "co.ok"})
	check(bool(r["ok"]), "注册成功")
	check_eq(econ.liquid("owner"), before - 2000000, "本金从业主扣除")
	check_eq(econ.liquid("company.co.ok"), 2000000, "本金进入公司账户")
	check_eq(econ.total_money(), 10000000, "本金转账保持货币守恒")


# --- 选址、进货、定价 ---

func _test_site_stock_price() -> void:
	var sys = CompanyScript.new()
	var econ = _econ(10000000)
	var co: Dictionary = sys.register_company(econ, "owner", {"kind": "company", "name": "店", "capital": 5000000, "id": "co.s"})["company"]
	check(not bool(sys.open_shop(co)["ok"]), "未选址不可营业")
	sys.choose_site(co, "region.a", 100.0, 30000)
	check(bool(sys.open_shop(co)["ok"]), "选址后可营业")
	econ.open_account("supplier", 0)
	var before: int = econ.total_money()
	var st: Dictionary = sys.stock(co, econ, "good.apple", 100, 1000, "supplier")
	check(bool(st["ok"]) and int(st["cost"]) == 100000, "进货成功")
	check_eq(sys.inventory_qty(co, "good.apple"), 100, "库存入库")
	check_eq(econ.total_money(), before, "向供货方付款守恒")
	check_eq(econ.liquid("supplier"), 100000, "供货方收款")
	# 二次进货成本加权
	sys.stock(co, econ, "good.apple", 100, 2000, "supplier")
	check_eq(int(co["inventory"]["good.apple"]["unit_cost"]), 1500, "加权成本")
	check(bool(sys.set_price(co, "good.apple", 1800)["ok"]), "定价成功")
	check(not sys.stock(co, econ, "good.apple", 999999, 1000, "supplier")["ok"], "资金不足拒绝进货")


# --- 营业客流与缺货 ---

func _test_tick_day_revenue_and_shortage() -> void:
	var sys = CompanyScript.new()
	var econ = _econ(10000000)
	var co: Dictionary = _open_shop(econ)
	sys.stock(co, econ, "good.apple", 100, 1000)
	sys.set_price(co, "good.apple", 1200)
	var r: Dictionary = sys.tick_day(co, econ, 1)
	check(bool(r["ok"]), "营业日结算成功")
	check(int(r["revenue"]) > 0, "营业产生收入")
	check(int(r["costs"]) > 0, "营业产生房租成本")
	check(sys.inventory_qty(co, "good.apple") < 100, "销售减少库存")
	check(float(co["reputation"]) > 80.0, "无缺货声誉上升")
	# 库存清空 → 停售并提示补货
	co["inventory"]["good.apple"]["qty"] = 0
	var r2: Dictionary = sys.tick_day(co, econ, 2)
	check((r2["shortages"] as Array).has("good.apple"), "缺货被提示")
	check_eq(int(r2["revenue"]), 0, "缺货无收入")
	check(float(co["reputation"]) < 80.2, "缺货降低声誉")
	# 打烊后不结算
	sys.close_shop(co)
	check(not bool(sys.tick_day(co, econ, 3)["ok"]), "打烊后不营业")


# --- 雇佣、欠薪与离职 ---

func _test_payroll_and_resign() -> void:
	var sys = CompanyScript.new()
	var econ = _econ(100000000)
	var co: Dictionary = _open_shop(econ)
	check(bool(sys.hire(co, "npc.a", 300000, {"name": "员工甲"})["ok"]), "雇佣成功")
	check(not bool(sys.hire(co, "npc.a", 300000)["ok"]), "重复雇佣拒绝")
	check_eq(sys.payroll_cost(co, 30), 300000, "月工资成本")
	check(bool(sys.fire(co, "npc.a")["ok"]), "解雇成功")
	check(not bool(sys.fire(co, "npc.a")["ok"]), "解雇不存在员工失败")
	# 欠薪：公司账户资金不足 → 忠诚下降
	var poor: Dictionary = _open_shop(econ)
	poor["account"] = "company.poor"
	econ.open_account("company.poor", 1000)
	sys.hire(poor, "npc.b", 300000)
	var r: Dictionary = sys.tick_day(poor, econ, 1)
	check(int(r["wages_unpaid"]) > 0, "欠薪被记录")
	check(float(poor["employees"][0]["loyalty"]) < 70.0, "欠薪降低忠诚")
	# 忠诚过低叠加随机 → 离职
	var c: Dictionary = _open_shop(econ)
	c["account"] = "company.c"
	econ.open_account("company.c", 0)
	sys.hire(c, "npc.c", 300000, {"loyalty": 0.0})
	var rng = RngScript.new(7)
	var resigned: bool = false
	for i in 50:
		var rr: Dictionary = sys.tick_day(c, econ, 10 + i, rng)
		if (rr["resigned"] as Array).size() > 0:
			resigned = true
			break
	check(resigned, "忠诚过低最终离职")


# --- 纳税与扩张 ---

func _test_tax_and_expand() -> void:
	var sys = CompanyScript.new()
	var econ = _econ(10000000)
	var co: Dictionary = _open_shop(econ)
	econ.open_account("gov", 0)
	var t: Dictionary = sys.settle_tax(co, econ, "gov", 1000)
	check(int(t["tax"]) > 0, "正利润缴税")
	check_eq(econ.liquid("gov"), int(t["tax"]), "税款进入政府账户")
	check_eq(int(sys.settle_tax(co, econ, "gov", -5)["tax"]), 0, "亏损不缴税")
	var branches: int = int(co["branches"])
	check(bool(sys.expand(co, econ, 100000)["ok"]), "扩张成功")
	check_eq(int(co["branches"]), branches + 1, "分店数 +1")
	check(not bool(sys.expand(co, econ, 99999999999)["ok"]), "资金不足拒绝扩张")


# --- 破产 ---

func _test_bankruptcy() -> void:
	var sys = CompanyScript.new()
	var econ = _econ(10000000)
	var co: Dictionary = _open_shop(econ)
	sys.stock(co, econ, "good.apple", 100, 1000)
	econ.add_money("company.co.a", -9999999, "loss")
	check(sys.is_insolvent(co, econ), "资不抵债被识别")
	var r: Dictionary = sys.bankrupt(co, econ)
	check(bool(r["ok"]), "破产清算成功")
	check_eq(str(co["status"]), "bankrupt", "状态改为破产")
	check_eq((co["inventory"] as Dictionary).size(), 0, "清算清空库存")
	check_eq((co["employees"] as Array).size(), 0, "清算清空员工")
