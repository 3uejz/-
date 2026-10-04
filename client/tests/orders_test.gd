extends "res://tests/test_base.gd"
## 网络消费与订单测试（任务 11；R49.7–R49.9；design D9）。
## 覆盖：渠道完整性、定价（折扣/配送/关税）、订单状态机与物流 tick、
##       即时履约、退货窗口与退款、投诉、订阅扣费与停用、消费心理、假货标记、货币守恒。

const OrderScript = preload("res://sim/orders.gd")
const EconomyScript = preload("res://sim/economy.gd")

func _suite_name() -> String:
	return "orders"

func run_tests() -> void:
	_test_channels()
	_test_pricing()
	_test_lifecycle_and_logistics()
	_test_instant_fulfillment()
	_test_return_and_refund()
	_test_return_window()
	_test_complaint_and_counterfeit()
	_test_subscription()
	_test_psychology()


func _test_channels() -> void:
	var sys = OrderScript.new()
	var ch: Array = sys.channels()
	for need in ["ecommerce", "livestream", "delivery", "secondhand", "group_buy", "crossborder", "rideshare", "online_edu", "streaming", "digital"]:
		check(ch.has(need), "渠道存在: " + need)
	check(sys.is_instant("digital"), "数字内容即时履约")
	check(not sys.is_instant("ecommerce"), "电商走物流")


func _test_pricing() -> void:
	var sys = OrderScript.new()
	var d: Dictionary = sys.place_order("delivery", "item.apple", 2, 0, 500)
	check_eq(int(d["subtotal"]), 1000, "小计")
	check_eq(int(d["shipping_fee"]), 300, "外卖配送费")
	check_eq(int(d["amount"]), 1300, "外卖总价")
	var s: Dictionary = sys.place_order("secondhand", "item.phone", 1, 0, 10000)
	check_eq(int(s["discount"]), 5000, "二手五折")
	check_eq(int(s["amount"]), 5000, "二手成交价")
	var c: Dictionary = sys.place_order("crossborder", "item.watch", 1, 0, 100000)
	check_eq(int(c["tariff"]), 10000, "跨境关税 10%")
	check_eq(int(c["amount"]), 110000, "跨境含税总价")


func _economy() -> Variant:
	var e = EconomyScript.new(11)
	e.open_account("p", 1000000)
	e.open_account("platform", 0)
	return e


func _test_lifecycle_and_logistics() -> void:
	var sys = OrderScript.new()
	var e = _economy()
	var o: Dictionary = sys.place_order("ecommerce", "item.apple", 1, 0, 1000)
	check(sys.pay(o, e, "p", 0), "支付成功")
	check_eq(str(o["status"]), "shipping", "实物进入物流")
	check_eq(e.cash("p"), 999000, "支付扣款")
	check_eq(e.cash("platform"), 1000, "卖家收款")
	check(e.is_conserved(), "支付后货币守恒")
	check_eq(sys.advance(o, 2), "shipping", "未到期仍在途")
	check_eq(sys.advance(o, 3), "delivered", "到期送达")
	check_eq(sys.advance(o, 5), "delivered", "自动完成前仍为已送达")
	var orders: Array = [o]
	var completed: Array = sys.tick(orders, 6)
	check_eq(completed.size(), 1, "tick 收集完成订单")
	check_eq(str(o["status"]), "completed", "验收完成")


func _test_instant_fulfillment() -> void:
	var sys = OrderScript.new()
	var e = _economy()
	var o: Dictionary = sys.place_order("digital", "item.novel", 1, 0, 4500)
	check(sys.pay(o, e, "p", 0), "数字内容支付成功")
	check_eq(str(o["status"]), "delivered", "即时履约送达")
	check_eq(sys.advance(o, 3), "completed", "即时订单自动完成")


func _test_return_and_refund() -> void:
	var sys = OrderScript.new()
	var e = _economy()
	var o: Dictionary = sys.place_order("ecommerce", "item.apple", 1, 0, 1000)
	sys.pay(o, e, "p", 0)
	sys.advance(o, 3)
	var cash_after_pay: int = e.cash("p")
	check(sys.request_return(o, 5).get("ok", false), "窗口内可退货")
	check_eq(str(o["status"]), "refunding", "进入退款流程")
	var r: Dictionary = sys.approve_refund(o, e, "p")
	check(r.get("ok", false), "同意退款")
	check_eq(int(r["refund"]), 1000, "退款金额")
	check_eq(e.cash("p"), cash_after_pay + 1000, "退款到账")
	check(e.is_conserved(), "退款后货币守恒")


func _test_return_window() -> void:
	var sys = OrderScript.new()
	var o: Dictionary = sys.place_order("ecommerce", "item.apple", 1, 0, 1000)
	# 未送达不可退
	check(not sys.request_return(o, 1).get("ok", false), "未送达不可退货")
	o["status"] = "delivered"
	o["delivered_day"] = 0
	check(not sys.request_return(o, 100).get("ok", false), "超窗口拒绝退货")


func _test_complaint_and_counterfeit() -> void:
	var sys = OrderScript.new()
	var o: Dictionary = sys.place_order("ecommerce", "item.phone", 1, 0, 10000)
	check_eq(sys.complain(o), 1, "投诉计数")
	check_eq(sys.complain(o), 2, "投诉累加")
	check(sys.mark_counterfeit(o, 0.01, 0.05), "低 roll 判为假货")
	check(not sys.mark_counterfeit(o, 0.9, 0.05), "高 roll 非假货")


func _test_subscription() -> void:
	var sys = OrderScript.new()
	var e = _economy()
	var sub: Dictionary = sys.subscribe("streaming", "plan.basic", 3000, 0)
	check(not sub.is_empty(), "订阅创建")
	var b1: Dictionary = sys.bill_subscription(sub, e, "p", 0)
	check_eq(int(b1["charged"]), 3000, "首月扣费")
	var again: Dictionary = sys.bill_subscription(sub, e, "p", 5)
	check_eq(int(again["charged"]), 0, "同月不重复扣费")
	var b2: Dictionary = sys.bill_subscription(sub, e, "p", 30)
	check_eq(int(b2["charged"]), 3000, "次月扣费")
	check(e.is_conserved(), "订阅扣费后货币守恒")
	var e2 = EconomyScript.new(12)
	e2.open_account("q", 100)
	var sub2: Dictionary = sys.subscribe("streaming", "plan.pro", 3000, 0)
	var b3: Dictionary = sys.bill_subscription(sub2, e2, "q", 0)
	check_eq(str(b3["reason"]), "suspended", "余额不足停用")
	check(not bool(sub2["active"]), "订阅状态停用")


func _test_psychology() -> void:
	var sys = OrderScript.new()
	check_near(sys.impulse_factor("livestream", 1.0), 1.8, 1e-6, "直播冲动因子")
	check(sys.impulse_factor("livestream", 100.0) <= 3.0, "冲动因子有上界")
	check_near(sys.impulse_factor("rideshare", 1.0), 1.0, 1e-6, "网约车无冲动加成")
	check_near(sys.conspicuous_factor(0.0, 100.0), 1.0, 1e-6, "零收入攀比最强")
	check_near(sys.conspicuous_factor(100.0, 100.0), 0.0, 1e-6, "收入持平无攀比")
