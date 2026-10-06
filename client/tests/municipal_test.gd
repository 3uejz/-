extends "res://tests/test_base.gd"
## 市政公用与邮政测试（任务 35；R82；design D38）。
## 覆盖：数据表、设施养护与老化、施工对通行的影响、道路反复开挖与公园维护缺位、
##       邮政时效/丢件/破损/理赔与爆仓、快递员职业路径、特许经营资质与质量考核。

const MunicipalScript = preload("res://sim/municipal.gd")


func _suite_name() -> String:
	return "municipal"


func run_tests() -> void:
	_test_tables()
	_test_facility_and_maintenance()
	_test_construction_and_commute()
	_test_boundaries()
	_test_postal_delivery_and_claim()
	_test_postal_overload()
	_test_courier_career()
	_test_franchise()


func _test_tables() -> void:
	var sys = MunicipalScript.new()
	check_eq(sys.facility_types().size(), 7, "七类市政设施")
	check_eq(sys.franchise_service_keys().size(), 5, "五类特许经营服务")
	check_eq(sys.courier_ranks().size(), 5, "五级快递员职业路径")
	check_eq(sys.facility_name("road"), "道路", "道路名称")
	for key in sys.facility_types():
		check(sys.facility_condition(sys.new_city(1000), key) >= 0.0, "设施健康度非负: " + str(key))


func _test_facility_and_maintenance() -> void:
	var sys = MunicipalScript.new()
	var city: Dictionary = sys.new_city(1000000)
	var base: float = sys.facility_condition(city, "road")
	check(base > 0.0, "初始健康度为正")
	sys.maintain_facility(city, "road", 800000)
	check(sys.facility_condition(city, "road") > base, "养护提升健康度")
	check_eq(sys.facility_grade(city, "road"), "优", "高健康度为优")
	var before: float = sys.facility_condition(city, "road")
	sys.age_facilities(city, 5.0)
	check(sys.facility_condition(city, "road") < before, "老化降低健康度")
	check(not bool(sys.maintain_facility(city, "bogus", 1000)["ok"]), "未知设施被拒")


func _test_construction_and_commute() -> void:
	var sys = MunicipalScript.new()
	var city: Dictionary = sys.new_city(500000)
	var normal: float = sys.commute_impact(city)
	var start: Dictionary = sys.start_construction(city, "road", {"days": 10.0})
	check(bool(start["ok"]), "开工成功")
	var during: float = sys.commute_impact(city)
	check(during > normal, "施工抬高通行影响系数")
	check(not bool(sys.start_construction(city, "road", {"days": 5.0})["ok"]), "重复开工被拒")
	var adv: Dictionary = sys.advance_construction(city, 10.0)
	check((adv["completed"] as Array).has("road"), "施工完成")
	check(sys.commute_impact(city) < during, "完工后通行改善")
	# 扰民与投诉。
	var c: Dictionary = sys.report_nuisance(city, {"source": "construction", "severity": 0.5})
	check_eq(sys.unresolved_complaints(city), 1, "投诉登记未解决")
	sys.resolve_complaint(city, 0, {})
	check_eq(sys.unresolved_complaints(city), 0, "投诉已解决")
	check(bool(c["resolved"]), "投诉状态更新")


func _test_boundaries() -> void:
	var sys = MunicipalScript.new()
	# 道路反复开挖。
	var city: Dictionary = sys.new_city(200000)
	var first: Dictionary = sys.start_excavation(city, "road", {"day": 0})
	check(not bool(first["repeated"]), "首次开挖不重复")
	var second: Dictionary = sys.start_excavation(city, "road", {"day": 30})
	check(bool(second["repeated"]), "窗口期内反复开挖")
	check(int(second["extra_cost"]) > 0, "反复开挖产生额外成本")
	# 公园维护缺位。
	var city2: Dictionary = sys.new_city(200000)
	sys.age_facilities(city2, 10.0)
	var parks: Array = sys.inspect_parks(city2)
	check(parks.size() > 0 and bool((parks[0] as Dictionary)["neglected"]), "公园维护缺位被识别")


func _test_postal_delivery_and_claim() -> void:
	var sys = MunicipalScript.new()
	var hub: Dictionary = sys.new_postal_hub({"capacity_per_day": 1000})
	# 正常投递。
	var ok_parcel: Dictionary = sys.new_parcel("p1", {"distance_km": 100.0, "value": 10000})
	var ok_r: Dictionary = sys.ship(hub, ok_parcel, {"loss_roll": 1.0, "damage_roll": 1.0})
	check_eq(str(ok_r["status"]), "delivered", "正常投递")
	check(bool(ok_r["on_time"]), "正常时效内")
	# 丢件与理赔。
	var lost: Dictionary = sys.new_parcel("p2", {"distance_km": 100.0, "value": 10000})
	var lost_r: Dictionary = sys.ship(hub, lost, {"loss_roll": 0.0, "damage_roll": 1.0})
	check(bool(lost_r["lost"]), "丢件")
	var claim: Dictionary = sys.file_claim(hub, lost, {})
	check_eq(int(claim["paid"]), 10000, "未保价按上限赔付")
	check(not bool(sys.file_claim(hub, lost, {})["ok"]), "不重复理赔")
	# 破损与保价理赔。
	var dmg: Dictionary = sys.new_parcel("p3", {"distance_km": 100.0, "value": 20000, "insured": true})
	var dmg_r: Dictionary = sys.ship(hub, dmg, {"loss_roll": 1.0, "damage_roll": 0.0})
	check(bool(dmg_r["damaged"]), "破损")
	check_eq(int(sys.file_claim(hub, dmg, {})["paid"]), 20000, "保价按货值赔付")


func _test_postal_overload() -> void:
	var sys = MunicipalScript.new()
	var hub: Dictionary = sys.new_postal_hub({"capacity_per_day": 1})
	for i in 5:
		sys.accept_parcel(hub, sys.new_parcel("o%d" % i, {"distance_km": 100.0}))
	check(sys.postal_overload(hub) > 1.0, "待处理量超容量为爆仓")
	var first: Dictionary = (hub["pending"] as Array)[0]
	var r: Dictionary = sys.ship(hub, first, {"loss_roll": 1.0, "damage_roll": 1.0})
	check(bool(r["overloaded"]), "爆仓标记")
	check(int(r["delay_days"]) > 0, "爆仓顺延时效")


func _test_courier_career() -> void:
	var sys = MunicipalScript.new()
	var courier: Dictionary = sys.new_courier("c1", {"deliveries": 99})
	check_eq(int(courier["income"]), 3000, "实习快递员起薪")
	var r: Dictionary = sys.courier_deliver(courier, sys.new_parcel("cp1", {}), {})
	check(bool(r["promoted"]), "达标晋升")
	check_eq(int(courier["rank_index"]), 1, "晋升为快递员")
	check_eq(int(courier["income"]), 5000, "晋升涨薪")
	# 破损件扣声誉。
	var rep: float = float(courier["reputation"])
	var bad: Dictionary = sys.new_parcel("cp2", {})
	bad["damaged"] = true
	sys.courier_deliver(courier, bad, {})
	check(float(courier["reputation"]) < rep, "破损件扣减声誉")


func _test_franchise() -> void:
	var sys = MunicipalScript.new()
	var city: Dictionary = sys.new_city(300000)
	var unlicensed: Dictionary = {"id": "op1", "license": false}
	check(not bool(sys.grant_franchise(city, "water_supply", unlicensed, {})["ok"]), "无资质不得供水特许")
	var licensed: Dictionary = {"id": "op2", "license": true}
	var grant: Dictionary = sys.grant_franchise(city, "water_supply", licensed, {})
	check(bool(grant["ok"]), "有资质可获特许")
	# 质量考核不达标。
	var contract: Dictionary = grant["contract"]
	var assess: Dictionary = sys.assess_service_quality(city, contract, 0.2, {})
	check(not bool(assess["passed"]) and int(assess["penalty"]) > 0, "质量不达标扣减服务费")
	check(not bool(contract["active"]), "不达标停业整改")
	# 投诉累计触发复核。
	var c2: Dictionary = sys.grant_franchise(city, "waste_collection", licensed, {})["contract"]
	sys.franchise_complaint(city, c2, {})
	sys.franchise_complaint(city, c2, {})
	var third: Dictionary = sys.franchise_complaint(city, c2, {})
	check(bool(third["review"]), "三次投诉触发复核")
	check(bool(sys.government_purchase(city, "street_cleaning", 1000000, {})["ok"]), "政府购买服务")
