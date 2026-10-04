extends "res://tests/test_base.gd"
## 物品、背包与物权测试（任务 11；R16、R49；design D9）。
## 覆盖：目录可扩展无上限、堆叠与非堆叠、格数/重量上限、使用效果、过期结算、
##       耐久损耗与维修、按年保值、价格与 MarketSystem 联动、物权（典当/赎回）、
##       赠送与继承、购买/出售经 EconomySystem 结算并守恒。

const ItemScript = preload("res://sim/items.gd")
const EconomyScript = preload("res://sim/economy.gd")
const MarketScript = preload("res://sim/market.gd")
const BaselineScript = preload("res://sim/baseline.gd")

func _suite_name() -> String:
	return "items"

func run_tests() -> void:
	BaselineScript.clear_overrides()
	_test_catalog_extensible()
	_test_stack_and_nonstack()
	_test_capacity_slots_and_weight()
	_test_use_effects()
	_test_expiry()
	_test_durability_and_repair()
	_test_depreciation()
	_test_pricing_and_market()
	_test_ownership_and_pawn_redeem()
	_test_give_and_inherit()
	_test_buy_sell_conservation()
	BaselineScript.clear_overrides()


func _player() -> Dictionary:
	return {
		"attrs": {
			"physiological": {"health": 50.0, "stamina": 50.0, "hunger": 50.0, "thirst": 50.0, "cleanliness": 50.0, "sleep_debt": 10.0},
			"nutrition": {"protein": 50.0, "carbs": 50.0, "fat": 50.0, "vitamins": 50.0, "minerals": 50.0},
			"psychological": {"mood": 50.0, "stress": 50.0, "happiness": 50.0, "meaning": 50.0},
			"ability": {"intelligence": 50.0, "charm": 50.0, "physique": 50.0, "willpower": 50.0, "luck": 50.0},
		},
		"inventory": [],
		"equipment": [],
	}


# --- 目录 ---

func _test_catalog_extensible() -> void:
	var sys = ItemScript.new()
	check(sys.register_starter_catalog() >= 15, "起步目录注册成功")
	var base: int = sys.def_count()
	check(sys.register({"name": "缺 id"}) == {}, "缺必填字段拒绝注册")
	check(sys.register({"id": "x", "name": "类别非法", "category": "nope", "base_price": 1.0}) == {}, "非法类别拒绝注册")
	for i in 200:
		sys.register({"id": "item.custom_%d" % i, "name": "自定义%d" % i, "category": "daily", "base_price": 1.0})
	check_eq(sys.def_count(), base + 200, "目录可扩展且无种类上限")
	check(sys.has_def("item.apple"), "内置条目存在")
	check_eq(sys.rarity_rank("item.watch"), 2, "稀有度分级正确")


# --- 背包 ---

func _test_stack_and_nonstack() -> void:
	var sys = ItemScript.new()
	sys.register_starter_catalog()
	var p: Dictionary = _player()
	check_eq(int(sys.add(p, "item.apple", 5)["added"]), 5, "堆叠物品入包")
	check_eq(p["inventory"].size(), 1, "堆叠合并为一条")
	check_eq(sys.count(p, "item.apple"), 5, "数量统计正确")
	sys.add(p, "item.tshirt", 1)
	sys.add(p, "item.tshirt", 1)
	check_eq(p["inventory"].size(), 3, "非堆叠物品逐条占位")


func _test_capacity_slots_and_weight() -> void:
	var small = ItemScript.new(2, 50.0)
	small.register_starter_catalog()
	var p: Dictionary = _player()
	check(small.add(p, "item.tshirt", 1).get("ok", false), "第 1 件入包")
	check(small.add(p, "item.tshirt", 1).get("ok", false), "第 2 件入包")
	var over: Dictionary = small.add(p, "item.tshirt", 1)
	check_eq(str(over.get("reason", "")), "over_capacity", "超过格数上限拒绝")
	var heavy = ItemScript.new(100, 10.0)
	heavy.register_starter_catalog()
	var p2: Dictionary = _player()
	check_eq(str(heavy.add(p2, "item.fridge", 1).get("reason", "")), "over_capacity", "超过重量上限拒绝")
	check(heavy.add(p2, "item.chair", 1).get("ok", false), "未超重可入包")


# --- 使用与过期 ---

func _test_use_effects() -> void:
	var sys = ItemScript.new()
	sys.register_starter_catalog()
	var p: Dictionary = _player()
	sys.add(p, "item.apple", 2)
	var r: Dictionary = sys.use(p, "item.apple")
	check(r.get("ok", false), "使用苹果成功")
	check_near(float(p["attrs"]["physiological"]["hunger"]), 70.0, 1e-6, "饥饿效果应用")
	check_eq(sys.count(p, "item.apple"), 1, "使用消耗 1 个")
	var bad: Dictionary = sys.use(p, "item.watch")
	check(not bad.get("ok", false), "未持有则不可使用")


func _test_expiry() -> void:
	var sys = ItemScript.new()
	sys.register_starter_catalog()
	var p: Dictionary = _player()
	sys.add(p, "item.bread", 2, {"day": 0})
	check_eq(sys.tick_day(p, 2).size(), 0, "保质期内不过期")
	var expired: Array = sys.tick_day(p, 3)
	check_eq(expired.size(), 1, "过期结算返回提示")
	check_eq(sys.count(p, "item.bread"), 0, "过期物品移除")


# --- 耐久与保值 ---

func _test_durability_and_repair() -> void:
	var sys = ItemScript.new()
	sys.register_starter_catalog()
	var p: Dictionary = _player()
	sys.add(p, "item.phone", 1)
	check_eq(sys.damage(p, "item.phone", 30), 70, "耐久扣减")
	check_eq(sys.repair(p, "item.phone", 1000), 100, "维修不超过上限")
	check(sys.damage(p, "item.phone", 1000) == 0, "耐久归零")
	check_eq(sys.count(p, "item.phone"), 0, "报废后移除")


func _test_depreciation() -> void:
	var sys = ItemScript.new(100, 5000.0)
	sys.register_starter_catalog()
	var p: Dictionary = _player()
	sys.add(p, "item.car", 1, {"day": 0})
	var inst: Dictionary = p["inventory"][0]
	var v0: int = sys.instance_value_minor(inst, 0)
	var v5: int = sys.instance_value_minor(inst, 365 * 5)
	check(v0 > 0, "新车有现值")
	check(v5 < v0, "按年保值率使现值下降")
	check(v5 > 0, "现值不为负")


# --- 定价 ---

func _test_pricing_and_market() -> void:
	var sys = ItemScript.new()
	sys.register_starter_catalog()
	var scale: int = int(BaselineScript.MONEY_MINOR_SCALE)
	check_eq(sys.price_minor("item.apple", null), 5 * scale, "无市场时按基准价")
	var market = MarketScript.new()
	market.register_good("item.apple", 20.0, "daily")
	var mp: int = sys.price_minor("item.apple", market)
	check(mp > 0, "接入市场后价格为正")
	check(mp != 5 * scale, "接入市场后使用市场价")


# --- 物权 ---

func _test_ownership_and_pawn_redeem() -> void:
	var sys = ItemScript.new()
	sys.register_starter_catalog()
	var e = EconomyScript.new(1)
	e.open_account("p", 1000)
	e.open_account("pawnshop", 0)
	var p: Dictionary = _player()
	sys.add(p, "item.watch", 1)
	check(sys.pawn(p, e, "p", "item.watch", 500), "典当成功")
	check_eq(sys.ownership_of(p, "item.watch"), "pawn", "物权转为典当")
	check_eq(e.cash("p"), 1500, "当金入账")
	check(e.is_conserved(), "典当后货币守恒")
	check(not sys.redeem(p, e, "p", "item.watch", 5000), "余额不足不可赎回")
	check(sys.redeem(p, e, "p", "item.watch", 500), "赎回成功")
	check_eq(sys.ownership_of(p, "item.watch"), "own", "恢复所有权")
	check_eq(e.cash("p"), 1000, "赎回扣款")
	check(e.is_conserved(), "赎回后货币守恒")


# --- 赠送与继承 ---

func _test_give_and_inherit() -> void:
	var sys = ItemScript.new()
	sys.register_starter_catalog()
	var a: Dictionary = _player()
	var b: Dictionary = _player()
	sys.add(a, "item.apple", 3)
	check_eq(sys.give(a, b, "item.apple", 2), 2, "赠送转移数量")
	check_eq(sys.count(a, "item.apple"), 1, "赠送方扣减")
	check_eq(sys.count(b, "item.apple"), 2, "受赠方增加")
	var heir: Dictionary = _player()
	var leftover: Array = sys.inherit_all(a, heir)
	check_eq(sys.count(a, "item.apple"), 0, "继承清空被继承人")
	check_eq(sys.count(heir, "item.apple"), 1, "继承方获得")
	check_eq(leftover.size(), 0, "容量充足无遗留")


# --- 买卖守恒 ---

func _test_buy_sell_conservation() -> void:
	var sys = ItemScript.new()
	sys.register_starter_catalog()
	var e = EconomyScript.new(7)
	e.open_account("p", 100000)
	e.open_account("market", 0)
	var p: Dictionary = _player()
	var r: Dictionary = sys.buy(p, e, "p", "item.apple", 2)
	check(r.get("ok", false), "购买成功")
	check_eq(sys.count(p, "item.apple"), 2, "购入入包")
	check_eq(e.cash("p"), 100000 - int(r["cost_minor"]), "购买扣费")
	check_eq(e.cash("market"), int(r["cost_minor"]), "卖家收款")
	check(e.is_conserved(), "购买后货币守恒")
	var poor = EconomyScript.new(8)
	poor.open_account("q", 0)
	var qp: Dictionary = _player()
	var fail: Dictionary = sys.buy(qp, poor, "q", "item.phone", 1)
	check_eq(str(fail.get("reason", "")), "insufficient_funds", "余额不足购买失败")
	var s: Dictionary = sys.sell(p, e, "p", "item.apple", 2)
	check(s.get("ok", false), "出售成功")
	check_eq(sys.count(p, "item.apple"), 0, "出售扣物")
	check(e.is_conserved(), "出售后货币守恒")
