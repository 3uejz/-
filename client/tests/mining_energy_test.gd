extends "res://tests/test_base.gd"
## 矿业、能源与资源测试（任务 32；R72；design D28）。
## 覆盖：数据表、矿权与勘探、开采/运输/冶炼/销售链、安全与职业病、能源价格周期、
##       期货与长约、新能源电网调度/碳交易/补贴、资源枯竭与城市衰退、战略管制、价格崩盘。

const MiningScript = preload("res://sim/mining_energy.gd")


func _suite_name() -> String:
	return "mining_energy"


func run_tests() -> void:
	_test_tables()
	_test_concession_and_explore()
	_test_mining_chain()
	_test_safety_and_accidents()
	_test_energy_cycle_and_contracts()
	_test_new_energy()
	_test_resource_and_crash()


func _test_tables() -> void:
	var sys = MiningScript.new()
	check_eq(sys.mineral_keys().size(), 4, "四种矿产")
	check_eq(sys.energy_keys().size(), 5, "五种能源")
	check_eq(MiningScript.ACCIDENT_TYPES.size(), 4, "四类事故")
	check_eq(MiningScript.NEW_ENERGY_KINDS.size(), 4, "四类新能源")


func _test_concession_and_explore() -> void:
	var sys = MiningScript.new()
	var m: Dictionary = sys.new_mine("iron", 100000000)
	check(not bool(sys.acquire_concession(m)["ok"]), "无资质不能取得矿权")
	(m["qualifications"] as Array).append("mining_license")
	var c: Dictionary = sys.acquire_concession(m)
	check(bool(c["ok"]) and bool(m["concession"]), "取得矿权特许")
	check(int(m["money"]) < 100000000, "支付特许资本")
	check(not bool(sys.extract(m, 100.0)["ok"]), "未勘探不可开采")
	var e: Dictionary = sys.explore(m, 10000000)
	check(bool(e["ok"]) and float(m["reserve"]) > 0.0, "勘探揭示储量")
	check(float(m["grade"]) > 0.0, "勘探品位为正")
	check(bool(m["explored"]), "标记已勘探")


func _test_mining_chain() -> void:
	var sys = MiningScript.new()
	var m: Dictionary = sys.new_mine("copper", 100000000, {"qualifications": ["mining_license"]})
	sys.acquire_concession(m)
	sys.explore(m, 10000000)
	var reserve0: float = float(m["reserve"])
	var ex: Dictionary = sys.extract(m, 1000.0)
	check(bool(ex["ok"]) and float(ex["ore"]) > 0.0, "开采产出矿石")
	check(float(m["reserve"]) < reserve0, "开采消耗储量")
	check(float(m["stockpile_ore"]) > 0.0, "矿石入库")
	var tr: Dictionary = sys.transport_ore(m, float(ex["ore"]))
	check(float(tr["transported"]) > 0.0, "矿石运输")
	var sm: Dictionary = sys.smelt(m, float(tr["transported"]))
	check(float(sm["metal"]) > 0.0, "冶炼产出金属")
	check(float(sm["metal"]) < float(sm["smelted_ore"]), "品位与收得率折损")
	var money0: int = int(m["money"])
	var sale: Dictionary = sys.sell(m, float(sm["metal"]))
	check(bool(sale["ok"]) and int(sale["revenue"]) > 0, "销售精炼金属")
	check(int(m["money"]) > money0, "销售回款")


func _test_safety_and_accidents() -> void:
	var sys = MiningScript.new()
	var m: Dictionary = sys.new_mine("coal", 100000000, {"qualifications": ["mining_license"], "workers": 100})
	var rate0: float = sys.accident_rate(m)
	sys.safety_invest(m, 20000000)
	check(float(m["safety"]) > 0.5, "安全投入提升安全等级")
	var rate1: float = sys.accident_rate(m)
	check(rate1 < rate0, "安全投入降低事故率")
	# roll=0 必触发事故；安全提升后触发概率下降。
	var hurt: Dictionary = sys.accident_check(m, {"roll": 0.0})
	check(bool(hurt["occurred"]), "低掷骰触发事故")
	check(int(hurt["injured"]) > 0, "事故受伤人数")
	check(str(hurt["kind_name"]) != "", "事故类型具名")
	var safe: Dictionary = sys.accident_check(m, {"base_rate": 0.0, "roll": 0.0})
	check(not bool(safe["occurred"]), "零风险不触发事故")
	var fine: Dictionary = sys.environmental_liability(m, 500000)
	check(int(fine["fine"]) == 500000 and float(m["environment_liability"]) > 0.0, "环保事故追责")


func _test_energy_cycle_and_contracts() -> void:
	var sys = MiningScript.new()
	var state: Dictionary = sys.new_energy_state()
	var oil0: int = sys.energy_price(state, "oil")
	sys.tick_energy(state, 1.0)
	var oil1: int = sys.energy_price(state, "oil")
	check(oil1 != oil0, "能源价格随周期波动")
	# 可复现：同样初始与步长得到同样结果。
	var s2: Dictionary = sys.new_energy_state()
	sys.tick_energy(s2, 1.0)
	check_eq(sys.energy_price(s2, "oil"), oil1, "能源价格周期可复现")
	check(sys.futures_contract(state, "oil", 100.0, oil0)["ok"], "建立期货")
	var settle: Dictionary = sys.settle_futures(state, "oil", 0, oil0 + 10000)
	check(int(settle["pnl"]) > 0, "期货盈利")
	check(not state.has("long_term_contracts"), "长约未建立前无记录")
	var ltc: Dictionary = sys.long_term_contract(state, "power", 1000.0, 80000, 3.0)
	check(bool(ltc["ok"]) and (state["long_term_contracts"] as Array).size() == 1, "建立长约")


func _test_new_energy() -> void:
	var sys = MiningScript.new()
	var wind: Dictionary = sys.new_energy_project("wind", 1000.0)
	check(str(wind["name"]) == "风电", "风电项目")
	var dispatch: Dictionary = sys.grid_dispatch(wind, 500.0)
	check(float(dispatch["supply"]) > 0.0, "电网调度出力")
	check_near(float(dispatch["gap"]), 0.0, 1e-9, "需求被满足")
	var storage: Dictionary = sys.new_energy_project("storage", 1000.0)
	var d2: Dictionary = sys.grid_dispatch(storage, 500.0, {"storage_capacity": 1000.0})
	check(float(d2["stored"]) > 0.0, "储能吸收富余")
	var carbon: Dictionary = sys.carbon_trade(wind, 100.0, 50)
	check(int(carbon["revenue"]) == 5000, "碳交易收入")
	var sub: Dictionary = sys.apply_subsidy(wind, 200000)
	check(int(sub["granted"]) == 200000 and float(wind["subsidy"]) > 0.0, "新能源补贴")


func _test_resource_and_crash() -> void:
	var sys = MiningScript.new()
	var m: Dictionary = sys.new_mine("gold", 100000000, {"qualifications": ["mining_license"], "workers": 100})
	sys.acquire_concession(m)
	sys.explore(m, 1000000)
	# 采空导致枯竭。
	var depleted: Dictionary = sys.extract(m, float(m["reserve"]) * 10.0)
	check(bool(depleted["depleted"]), "采空标记枯竭")
	check(not bool(m["operating"]), "枯竭停产")
	var city: Dictionary = {"population": 1000000}
	var decline: Dictionary = sys.resource_city_decline(city, m)
	check(float(decline["decline"]) > 0.0, "资源城市衰退")
	check(int(city["population"]) < 1000000, "人口流失")
	# 战略资源管制与囤积。
	var state: Dictionary = sys.new_energy_state()
	sys.set_strategic_control(state, "oil", 0.6)
	check_near(sys.tradable_ratio(state, "oil"), 0.4, 1e-9, "管制降低可交易比例")
	sys.stockpile(state, "oil", 5000.0)
	check(float((state["stockpile"] as Dictionary)["oil"]) == 5000.0, "战略囤积")
	# 价格崩盘引发裁员停产。
	var m2: Dictionary = sys.new_mine("iron", 100000000, {"workers": 100})
	m2["refined_metal"] = 5000.0
	var crash: Dictionary = sys.price_crash(m2, 0.5)
	check(int(crash["layoff"]) > 0 and not bool(m2["operating"]), "价格崩盘裁员停产")
	check(int(crash["loss"]) > 0, "价格崩盘损失")
