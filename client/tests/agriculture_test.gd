extends "res://tests/test_base.gd"
## 农业与乡土测试（任务 29；R66；design D22）。
## 覆盖：作物/牲畜/渠道/灾害数据表、土地取得与资产、种植收成与地力、灾害减产、
##       养殖饲料/繁殖/疫病/价格、市场售卖/订单/期货/滞销/保鲜、征地/空心化/补贴。

const AgriScript = preload("res://sim/agriculture.gd")


func _suite_name() -> String:
	return "agriculture"


func run_tests() -> void:
	_test_tables()
	_test_land()
	_test_plant_and_harvest()
	_test_disaster()
	_test_livestock()
	_test_market()
	_test_rural_and_edges()


func _test_tables() -> void:
	var sys = AgriScript.new()
	check_eq(sys.crop_types().size(), 6, "六种作物")
	check_eq(sys.livestock_types().size(), 5, "五种养殖")
	check_eq(AgriScript.MARKET_CHANNELS.size(), 5, "五种销售渠道")
	check_eq(AgriScript.DISASTERS.size(), 3, "三种灾害")
	check_eq(AgriScript.LAND_MODES.size(), 4, "四种土地方式")
	check_eq(AgriScript.LAND_USES.size(), 4, "四种土地用途")
	for use in AgriScript.LAND_USES:
		check(AgriScript.CROPS.values().any(func(c): return str(c["use"]) == str(use)) or use == "grain", "用途有作物覆盖: " + str(use))


func _test_land() -> void:
	var sys = AgriScript.new()
	var farm: Dictionary = sys.new_farm(10000000)
	var buy: Dictionary = sys.acquire_land(farm, 10.0, "grain", "purchase", 100000)
	check(bool(buy["ok"]), "购买土地")
	check_eq(int(buy["asset_value"]), 1000000, "购买计入资产")
	var lease: Dictionary = sys.acquire_land(farm, 5.0, "grain", "lease", 100000)
	check(bool(lease["ok"]), "租赁土地")
	check_eq(sys.land_asset_value(farm), 1000000, "租赁不计入资产")
	check(not bool(sys.acquire_land(farm, 1.0, "grain", "bogus", 100)["ok"]), "未知方式被拒")
	var f0: float = float((farm["land"] as Array)[0]["fertility"])
	sys.improve_fertility(farm, 0, 0.1)
	check(float((farm["land"] as Array)[0]["fertility"]) > f0, "改良地力")
	sys.rotate(farm, 0)
	check(float((farm["land"] as Array)[0]["fertility"]) > f0, "轮作恢复地力")


func _test_plant_and_harvest() -> void:
	var sys = AgriScript.new()
	var farm: Dictionary = sys.new_farm(1000000)
	sys.acquire_land(farm, 10.0, "grain", "purchase", 100000, {"fertility": 0.8})
	var planted: Dictionary = sys.plant(farm, 0, "rice")
	check(bool(planted["ok"]), "播种水稻")
	check_eq(str(planted["land_use"]), "grain", "作物用途")
	check(not bool(sys.plant(farm, 0, "bogus")["ok"]), "未知作物被拒")
	sys.fertilize(farm, 0)
	sys.irrigate(farm, 0)
	sys.weed(farm, 0)
	var grown: Dictionary = sys.grow(farm, 120.0)
	check((grown["matured"] as Array).has("rice"), "到达生长天数成熟")
	var before: float = float((farm["land"] as Array)[0]["fertility"])
	var harvest: Dictionary = sys.harvest(farm, 0, {"climate": 1.0, "skill": 0.8, "tech": 1.0})
	check(bool(harvest["ok"]), "收成成功")
	check(float(harvest["yield"]) > 0.0, "产量为正")
	check(float((farm["storage"] as Dictionary)["rice"]) > 0.0, "入仓库存")
	check(float((farm["land"] as Array)[0]["fertility"]) < before, "收成消耗地力")
	check_eq((farm["plots"] as Array).size(), 0, "收成后地块清空")


func _test_disaster() -> void:
	var sys = AgriScript.new()
	var good: Dictionary = sys.new_farm(1000000)
	sys.acquire_land(good, 10.0, "grain", "purchase", 100000, {"fertility": 0.8})
	sys.plant(good, 0, "rice")
	sys.grow(good, 120.0)
	var y_good: float = float(sys.harvest(good, 0, {"skill": 0.8})["yield"])
	var bad: Dictionary = sys.new_farm(1000000)
	sys.acquire_land(bad, 10.0, "grain", "purchase", 100000, {"fertility": 0.8})
	sys.plant(bad, 0, "rice")
	sys.grow(bad, 120.0)
	check(not bool(sys.strike_disaster(bad, "bogus", 1.0)["ok"]), "未知灾害被拒")
	var dis: Dictionary = sys.strike_disaster(bad, "pest", 1.0)
	check(bool(dis["ok"]), "虫害发生")
	check_eq(int(dis["affected"]), 1, "影响地块计数")
	var y_bad: float = float(sys.harvest(bad, 0, {"skill": 0.8})["yield"])
	check(y_bad < y_good, "灾害减产")
	check(sys.storage_spoil(good, 1.0)["ok"], "仓储保鲜结算")


func _test_livestock() -> void:
	var sys = AgriScript.new()
	var farm: Dictionary = sys.new_farm(1000000)
	check(not bool(sys.add_livestock(farm, "bogus", 1)["ok"]), "未知牲畜被拒")
	sys.add_livestock(farm, "pig", 100)
	var feed: Dictionary = sys.feed_livestock(farm, 10.0, 0.0)
	check(bool(feed["shortage"]), "饲料不足")
	check(bool((farm["livestock"] as Array)[0]["diseased"]), "缺料致病")
	var breed: Dictionary = sys.breed_livestock(farm, "pig", {"roll": 0.0})
	check(int(breed["born"]) > 0, "繁殖增栏")
	var dis: Dictionary = sys.livestock_disease(farm, "pig", {"roll": 0.0})
	check(int(dis["lost"]) > 0, "疫病损失")
	var price: Dictionary = sys.update_market_prices(farm, {"roll": 0.5})
	check(float(price["factor"]) > 0.0, "市场价格波动")


func _test_market() -> void:
	var sys = AgriScript.new()
	var farm: Dictionary = sys.new_farm(1000000)
	(farm["storage"] as Dictionary)["rice"] = 1000.0
	var m0: int = int(farm["money"])
	var s1: Dictionary = sys.sell(farm, "rice", 500.0, "market")
	check(bool(s1["ok"]), "集市售卖")
	check_eq(int(s1["revenue"]), 1500000, "集市收入")
	check_eq(float((farm["storage"] as Dictionary)["rice"]), 500.0, "扣减库存")
	check(int(farm["money"]) > m0, "资金增加")
	var s2: Dictionary = sys.sell(farm, "rice", 200.0, "order")
	check(int(s2["revenue"]) > int(round(200.0 * 3000.0)), "订单农业溢价")
	check(not bool(sys.sell(farm, "rice", 100.0, "bogus")["ok"]), "未知渠道被拒")
	var uns: Dictionary = sys.unsalable(farm, "rice", {"glut": 0.5})
	check(float(uns["unsalable"]) > 0.0, "滞销判定")
	var order: Dictionary = sys.place_order(farm, "rice", 100.0, 5000)
	check(bool(order["ok"]), "建立订单")
	var fulfill: Dictionary = sys.fulfill_order(farm, 0)
	check_eq(int(fulfill["revenue"]), 500000, "订单交付收入")
	var fut: Dictionary = sys.futures_contract(farm, "rice", 100.0, 3000)
	check(bool(fut["ok"]), "期货建仓")
	var settle: Dictionary = sys.settle_futures(farm, 0, 4000)
	check(int(settle["pnl"]) > 0, "期货平仓盈利")
	# 保鲜：蔬果腐坏更快。
	(farm["storage"] as Dictionary)["vegetable"] = 1000.0
	var spoil: Dictionary = sys.storage_spoil(farm, 10.0)
	check((spoil["spoiled"] as Dictionary).has("vegetable"), "蔬果腐坏")
	check(float((farm["storage"] as Dictionary)["vegetable"]) < 1000.0, "仓储损失")


func _test_rural_and_edges() -> void:
	var sys = AgriScript.new()
	var farm: Dictionary = sys.new_farm(10000000)
	sys.acquire_land(farm, 10.0, "grain", "purchase", 100000, {"fertility": 0.8})
	var req: Dictionary = sys.land_requisition(farm, 0, 50000, 200000)
	check(bool(req["dispute"]), "补偿过低产生纠纷")
	check_eq(int(req["shortfall"]), 150000, "计算补偿差额")
	check(sys.villager_relation(farm, "government") < 0.0, "纠纷降低政府关系")
	sys.set_villager_relation(farm, "neighbor", 10.0)
	check_near(sys.villager_relation(farm, "neighbor"), 10.0, 1e-6, "村民关系记录")
	var hollow: Dictionary = sys.rural_hollowing(farm, 100.0, 0.6)
	check(float(hollow["labor_available"]) < 100.0, "空心化减少劳力")
	check(float(hollow["productivity_penalty"]) > 0.0, "空心化拖累生产")
	var sub: Dictionary = sys.apply_subsidy(farm, 1000)
	check(int(sub["granted"]) > 0, "获得补贴")
	var set_year: Dictionary = sys.settle_year(farm)
	check(set_year.has("income"), "年结算含收入")
	sys.reset_year(farm)
	check_eq(int(farm["year_income"]), 0, "重置年度收入")
	var transfer: Dictionary = sys.land_transfer(farm, 0, "a", "b")
	check(bool(transfer["ok"]), "土地流转")
