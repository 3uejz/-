extends "res://tests/test_base.gd"
## 灰产黑市测试（任务 21；R26；design D12/D14）。

const GrayScript = preload("res://sim/gray_market.gd")


class FixedRng:
	var seq: Array
	var i: int = 0
	func _init(s: Array) -> void:
		seq = s
	func next_float() -> float:
		var v: float = float(seq[i % seq.size()])
		i += 1
		return v


func _suite_name() -> String:
	return "gray_market"


func run_tests() -> void:
	_test_catalog()
	_test_black_market()
	_test_gambling()
	_test_loan()
	_test_smuggling()


func _test_catalog() -> void:
	var sys = GrayScript.new()
	check_eq(sys.black_market_goods().size(), 7, "七类黑市商品")
	check_eq(sys.gambling_games().size(), 6, "六种赌博")
	check_eq(sys.smuggling_routes().size(), 5, "五条走私线路")


func _test_black_market() -> void:
	var sys = GrayScript.new()
	var state: Dictionary = {}
	var b: Dictionary = sys.buy(state, "counterfeit_bag", 2)
	check(bool(b["ok"]), "黑市买入")
	check_eq(int(b["cost"]), 160000, "买入成本")
	check(bool(b["illegal"]), "违禁品标记")
	check(float(state["heat"]) > 0.0, "累积热度")
	var s: Dictionary = sys.sell(state, "counterfeit_bag", 1)
	check_eq(int(s["revenue"]), 150000, "卖出收入")
	check_eq(int(state["inventory"]["counterfeit_bag"]), 1, "库存扣减")


func _test_gambling() -> void:
	var sys = GrayScript.new()
	var state: Dictionary = {}
	var win: Dictionary = sys.gamble(state, "dice", 10000, 0.0, FixedRng.new([0.9]))
	check(bool(win["won"]), "高点数获胜")
	check(int(win["payout"]) > 10000, "赔付大于本金")
	var lose: Dictionary = sys.gamble(state, "dice", 10000, 0.0, FixedRng.new([0.0]))
	check(not bool(lose["won"]), "低点数失败")
	check(float(state["gambling_addiction"]) > 0.0, "赌博成瘾累积")


func _test_loan() -> void:
	var sys = GrayScript.new()
	var state: Dictionary = {}
	var l: Dictionary = sys.loan_shark_borrow(state, 100000, 30)
	check_eq(int(l["due"]), 130000, "本息合计")
	var loan: Dictionary = state["loans"][0]
	var od: Dictionary = sys.loan_overdue(state, 40)
	check(int(od["collections"]) > 0, "逾期触发催收")
	check(int(loan["due"]) > 130000, "逾期罚息")
	var r: Dictionary = sys.repay(state, loan, int(loan["due"]))
	check(bool(r["repaid"]), "还清贷款")


func _test_smuggling() -> void:
	var sys = GrayScript.new()
	var state: Dictionary = {}
	var ok: Dictionary = sys.smuggle(state, "electronics", 0.0, FixedRng.new([0.99]))
	check(not bool(ok["caught"]), "走私成功")
	check_eq(int(ok["profit"]), 300000, "走私利润")
	var state2: Dictionary = {}
	var caught: Dictionary = sys.smuggle(state2, "electronics", 0.0, FixedRng.new([0.0]))
	check(bool(caught["caught"]), "走私被查获")
	check_eq(str(caught["crime"]), "smuggling", "返回刑事信息")
	var state3: Dictionary = {}
	state3["heat"] = 70.0
	var inf: Dictionary = sys.infamy(state3)
	check(bool(inf["wanted"]), "高热被通缉")
