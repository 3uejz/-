extends "res://tests/test_base.gd"
## 房产系统测试（任务 11；R16、R49；design D9）。
## 覆盖：属性校验、等额本息、市场估值有界、购买（首付/契税/房贷/限购/限贷）、
##       装修、出租、按月持有结算与断供法拍、出售清偿、拆迁补偿、货币守恒。

const PropScript = preload("res://sim/property.gd")
const EconomyScript = preload("res://sim/economy.gd")

func _suite_name() -> String:
	return "property"

func run_tests() -> void:
	_test_make_and_view()
	_test_mortgage_payment()
	_test_market_value_bounded()
	_test_purchase_and_conservation()
	_test_restrictions()
	_test_renovate_and_settle()
	_test_arrears_foreclosure()
	_test_sell_and_demolish()


func _player() -> Dictionary:
	return {"assets": [], "finances": {"cash": 0.0}}


func _flat(base: int = 1000000) -> Dictionary:
	return PropScript.new().make_property({
		"id": "prop.test", "name": "测试公寓", "city": "city.x", "district": "district.y",
		"area_sqm": 90.0, "base_price": base, "property_fee_month": 500,
	})


func _test_make_and_view() -> void:
	var sys = PropScript.new()
	check(sys.make_property({"id": "x"}).is_empty(), "缺必填字段拒绝")
	var p: Dictionary = _flat()
	check(not p.is_empty(), "合法房产构造成功")
	var v: Dictionary = sys.view(p)
	check_eq(str(v.get("id", "")), "prop.test", "看房返回结构")
	check_near(float(v.get("area_sqm", 0.0)), 90.0, 1e-6, "面积字段")
	check_eq(int(p.get("years_remaining", 0)), 70, "产权年限默认 70")


func _test_mortgage_payment() -> void:
	var sys = PropScript.new()
	check_eq(sys.mortgage_payment(120000, 0.0, 10), 1000, "零利率等额本金式均摊")
	var m: int = sys.mortgage_payment(1000000, 0.045, 30)
	check(m > 5000 and m < 5150, "等额本息月供在合理区间")
	check(sys.mortgage_payment(2000000, 0.045, 30) > m, "本金翻倍月供增加")


func _test_market_value_bounded() -> void:
	var sys = PropScript.new()
	var p: Dictionary = _flat(1000000)
	check_eq(sys.market_value(p, {"rate": 0.03, "base_rate": 0.03}), 1000000, "利率等于基准时按基准价")
	var high: int = sys.market_value(p, {"rate": 0.5, "base_rate": 0.03})
	check(high >= 500000, "高利率下估值不低于下限")
	check(high <= 3000000, "估值不超过上限")
	var low: int = sys.market_value(p, {"rate": 0.0, "base_rate": 0.03})
	check(low <= 3000000, "低利率估值有界")


func _test_purchase_and_conservation() -> void:
	var sys = PropScript.new()
	var e = EconomyScript.new(1)
	e.open_account("p", 100000000)
	var player: Dictionary = _player()
	var prop: Dictionary = _flat(1000000)
	var r: Dictionary = sys.purchase(player, e, "p", prop, 10, {"rate": 0.03, "base_rate": 0.03})
	check(r.get("ok", false), "购买成功")
	check_eq(int(r["price"]), 1000000, "成交价按基准")
	check_eq(int(r["down"]), 300000, "首付 30%")
	check_eq(int(r["deed_tax"]), 15000, "契税 1.5%")
	check_eq(int(r["principal"]), 700000, "贷款额")
	check_eq(e.cash("p"), 100000000 - 300000 - 15000 + 700000, "现金流正确")
	check_eq(e.debt("p"), 700000, "房贷计入负债")
	check(e.is_conserved(), "购房后账本守恒")
	check_eq(sys.owned_properties(player).size(), 1, "资产计入一套房产")
	check(bool(prop.get("owner", "") == "p"), "所有权归属正确")


func _test_restrictions() -> void:
	var sys = PropScript.new()
	sys.set_policy({"limit_buy": 1, "max_loans": 1})
	var e = EconomyScript.new(2)
	e.open_account("p", 1000000000)
	var player: Dictionary = _player()
	var p1: Dictionary = _flat(1000000)
	sys.purchase(player, e, "p", p1, 0, {"rate": 0.03, "base_rate": 0.03})
	var p2: Dictionary = sys.make_property({
		"id": "prop.b", "name": "二套", "city": "city.x", "district": "district.z",
		"area_sqm": 60.0, "base_price": 800000,
	})
	var restricted: Dictionary = sys.purchase(player, e, "p", p2, 0, {"rate": 0.03, "base_rate": 0.03})
	check_eq(str(restricted.get("reason", "")), "purchase_restricted", "限购拒绝第二套")
	sys.set_policy({"limit_buy": 0, "max_loans": 1})
	var no_loan: Dictionary = sys.purchase(player, e, "p", p2, 0, {"rate": 0.03, "base_rate": 0.03})
	check(no_loan.get("ok", false), "不限购后第二套可买")
	check_eq(int(no_loan["principal"]), 0, "限贷下第二套不贷款")
	check_eq(int(no_loan["down"]), int(no_loan["price"]), "全款支付")


func _test_renovate_and_settle() -> void:
	var sys = PropScript.new()
	var e = EconomyScript.new(3)
	e.open_account("p", 1000000000)
	var player: Dictionary = _player()
	var prop: Dictionary = _flat(1000000)
	sys.purchase(player, e, "p", prop, 0, {"rate": 0.03, "base_rate": 0.03})
	var before: int = sys.market_value(prop)
	var reno: Dictionary = sys.renovate(player, e, "p", prop, 2, 1000)
	check(reno.get("ok", false), "装修成功")
	check(sys.market_value(prop) > before, "装修提升估值")
	sys.set_rent(prop, 5000, true)
	var mortgage: Dictionary = prop["mortgage"]
	var remaining_before: int = int(mortgage["remaining"])
	var s: Dictionary = sys.monthly_settle(player, e, "p")
	check(int(s["payment"]) > 0, "结算扣除月供")
	check_eq(int(s["rent"]), 5000, "租金计入")
	check(int(prop["mortgage"]["remaining"]) < remaining_before, "房贷余额下降")
	check(int(prop["mortgage"]["months_paid"]) == 1, "还款月数递增")
	check(e.is_conserved(), "持有结算后货币守恒")


func _test_arrears_foreclosure() -> void:
	var sys = PropScript.new()
	var e = EconomyScript.new(4)
	var player: Dictionary = _player()
	var prop: Dictionary = _flat(1000000)
	# 有现金购房
	e.open_account("p", 100000000)
	sys.purchase(player, e, "p", prop, 0, {"rate": 0.03, "base_rate": 0.03})
	# 抽走现金触发断供
	var drained: int = e.cash("p")
	e.add_money("p", -drained, "drain")
	for _i in 3:
		sys.monthly_settle(player, e, "p")
	check_eq(sys.owned_properties(player).size(), 0, "连续断供后房产被法拍")
	check_eq(e.debt("p"), 0, "法拍后债务清零")


func _test_sell_and_demolish() -> void:
	var sys = PropScript.new()
	var e = EconomyScript.new(5)
	e.open_account("p", 100000000)
	var player: Dictionary = _player()
	var prop: Dictionary = _flat(1000000)
	sys.purchase(player, e, "p", prop, 0, {"rate": 0.03, "base_rate": 0.03})
	var cash_before: int = e.cash("p")
	var rent_sale: Dictionary = sys.sell(player, e, "p", prop, {"rate": 0.03, "base_rate": 0.03})
	check(rent_sale.get("ok", false), "出售成功")
	check_eq(sys.owned_properties(player).size(), 0, "出售后移出资产")
	check(e.cash("p") > cash_before, "出售净收入入账")
	check_eq(e.debt("p"), 0, "出售清偿房贷")
	check(e.is_conserved(), "出售后货币守恒")
	var prop2: Dictionary = _flat(500000)
	var player2: Dictionary = _player()
	player2["assets"].append(prop2)
	var demo: Dictionary = sys.demolish(player2, e, "p", prop2, 600000)
	check(demo.get("ok", false), "拆迁成功")
	check_eq(int(demo["compensation"]), 600000, "拆迁补偿")
	check_eq(player2["assets"].size(), 0, "拆迁移出资产")
