extends "res://tests/test_base.gd"
## 餐饮与食品工业测试（任务 33；R74；design D30）。
## 覆盖：数据表、成本毛利与原料涨价、选址与翻台率、单日经营与外卖抽成、
##       供应链与污染、认证与扩张、食安事故与召回、评星营销与厨师流失、食品工业。

const DiningScript = preload("res://sim/dining.gd")


func _suite_name() -> String:
	return "dining"


func run_tests() -> void:
	_test_tables()
	_test_menu_and_margin()
	_test_location_and_capacity()
	_test_sell_day_and_takeout()
	_test_supply_chain()
	_test_expansion_and_certification()
	_test_food_safety_incident()
	_test_reviews_marketing_and_chef()
	_test_food_industry()


func _test_tables() -> void:
	var sys = DiningScript.new()
	check_eq(sys.recipe_keys().size(), 4, "四种菜谱")
	check_eq(sys.material_keys().size(), 6, "六类原料")
	check_eq(sys.staff_role_keys().size(), 4, "四类岗位")
	check_eq(sys.expansion_modes().size(), 5, "五种扩张模式")
	check_eq(sys.channel_keys().size(), 4, "四种渠道")
	check_eq(sys.certification_keys().size(), 4, "四项食安认证")
	check_eq(int((sys.recipe_def("home_style") as Dictionary)["base_price"]), 3600, "家常小炒定价")


func _test_menu_and_margin() -> void:
	var sys = DiningScript.new()
	var r: Dictionary = sys.new_restaurant(1000000)
	sys.add_to_menu(r, "home_style")
	check_eq(sys.menu_keys(r).size(), 1, "菜单加入菜品")
	# 成本 = 0.5×800 + 0.3×3000 + 0.2×1500 = 1600。
	check_eq(sys.recipe_cost(r, "home_style"), 1600, "单份成本")
	var m: Dictionary = sys.recipe_margin(r, "home_style")
	check_eq(int(m["price"]), 3600, "定价")
	check_eq(int(m["gross_profit"]), 2000, "毛利额")
	check_near(float(m["gross_margin"]), 2000.0 / 3600.0, 1e-6, "毛利率")
	sys.set_price(r, "home_style", 4000)
	check_eq(sys.day_price(r, "home_style"), 4000, "覆盖定价")
	# 原料涨价：肉类翻倍 → 400 + 1800 + 300 = 2500。
	sys.ingredient_price_shock(r, "meat", 2.0)
	check_eq(sys.recipe_cost(r, "home_style"), 2500, "原料涨价推高成本")
	check(not bool(sys.recipe_margin(r, "bogus")["ok"]), "未知菜谱被拒")


func _test_location_and_capacity() -> void:
	var sys = DiningScript.new()
	var r: Dictionary = sys.new_restaurant(1000000, {"reputation": 50.0})
	sys.choose_location(r, "r1", 60.0, 30000, 1.0)
	var q: Dictionary = sys.location_quality(r)
	check_near(float(q["foot_traffic"]), 1.0, 1e-9, "客流记录")
	check(float(q["score"]) > 0.0, "选址评分")
	var cap0: float = sys.daily_capacity(r)
	sys.hire(r, "waiter", 5)
	var cap1: float = sys.daily_capacity(r)
	check(cap1 > cap0, "增加服务员提升翻台产能")
	sys.hire(r, "chef", 2)
	check(sys.daily_capacity(r) > cap1, "增加主厨进一步提升产能")
	check(sys.expected_turnover(r) <= 6.0 + 1e-9, "翻台率不超上限")


func _test_sell_day_and_takeout() -> void:
	var sys = DiningScript.new()
	var r: Dictionary = sys.new_restaurant(1000000, {
		"area_sqm": 60.0, "foot_traffic": 1.0, "monthly_rent": 30000, "tables": 10, "seats_per_table": 4,
	})
	sys.add_to_menu(r, "home_style")
	sys.hire(r, "chef", 1)
	sys.hire(r, "cook", 2)
	sys.hire(r, "waiter", 3)
	var money0: int = int(r["money"])
	var day: Dictionary = sys.sell_day(r, {"channel": "dine_in"})
	check(bool(day["ok"]), "单日经营成功")
	check(float(day["covers"]) > 0.0, "有客流")
	check(int(day["revenue"]) > 0, "有收入")
	var expected_profit: int = int(day["revenue"]) - int(day["commission"]) - int(day["cogs"]) - int(day["rent"]) - int(day["payroll"])
	check_eq(int(day["profit"]), expected_profit, "利润恒等式")
	check_eq(int(r["money"]), money0 + expected_profit, "利润入账")
	# 外卖默认关闭。
	var r2: Dictionary = sys.new_restaurant(1000000)
	sys.add_to_menu(r2, "home_style")
	var disabled: Dictionary = sys.sell_day(r2, {"channel": "takeout"})
	check(not bool(disabled["ok"]) and str(disabled["reason"]) == "channel_disabled", "外卖未开通被拒")
	(r2["channel"] as Dictionary)["takeout"] = true
	var to: Dictionary = sys.sell_day(r2, {"channel": "takeout"})
	check(bool(to["ok"]) and int(to["commission"]) > 0, "外卖平台抽成")
	var c: Dictionary = sys.takeout_commission(10000)
	check_eq(int(c["commission"]), 2000, "外卖抽成比例")
	check(not bool(sys.sell_day(r, {"channel": "bogus"})["ok"]), "未知渠道被拒")


func _test_supply_chain() -> void:
	var sys = DiningScript.new()
	var r: Dictionary = sys.new_restaurant(1000000)
	var miss: Dictionary = sys.purchase(r, "meat", 10.0)
	check(not bool(miss["ok"]) and str(miss["reason"]) == "no_supplier", "无供应商断料")
	sys.add_supplier(r, {"id": "s1", "materials": ["meat", "vegetable"], "price_factor": 1.2, "reliability": 1.0})
	var buy: Dictionary = sys.purchase(r, "meat", 100.0)
	check(bool(buy["ok"]) and int(buy["unit_cost"]) == 3600, "采购涨价系数")
	check(not bool(buy["contaminated"]), "正常供应商未污染")
	sys.contaminate_supply(r, "s1")
	var buy2: Dictionary = sys.purchase(r, "meat", 10.0)
	check(bool(buy2["contaminated"]), "污染供应商标记")
	sys.add_supplier(r, {"id": "s2", "materials": ["seafood"], "price_factor": 1.0, "reliability": 0.5})
	var partial: Dictionary = sys.purchase(r, "seafood", 100.0)
	check(bool(partial["ok"]) and float(partial["shortfall"]) > 0.0, "低可靠性部分断料")
	var risk: Dictionary = sys.supply_risk(r)
	check((risk["single_source"] as Array).has("meat"), "识别单一供应商风险")
	check(not bool(sys.contaminate_supply(r, "bogus")["ok"]), "未知供应商被拒")


func _test_expansion_and_certification() -> void:
	var sys = DiningScript.new()
	var r: Dictionary = sys.new_restaurant(30000000, {"hygiene": 90.0, "brand": 80.0})
	sys.hire(r, "chef", 2)
	check(not sys.can_enter_mode(r, "chain"), "初始标准化未达连锁门槛")
	check(bool(sys.certify(r, "haccp")["ok"]), "申请 HACCP 认证")
	check(sys.has_certification(r, "haccp"), "认证登记")
	check(sys.can_enter_mode(r, "chain"), "认证后满足连锁门槛")
	check(bool(sys.expand_to(r, "chain")["ok"]), "扩张为连锁门店")
	check_eq(str(r["mode"]), "chain", "经营模式更新")
	check(not sys.can_enter_mode(r, "central_kitchen"), "标准化不足中央厨房")
	check(bool(sys.certify(r, "iso22000")["ok"]), "申请 ISO 22000")
	check(sys.can_enter_mode(r, "central_kitchen"), "标准化达标中央厨房")
	check(bool(sys.expand_to(r, "central_kitchen")["ok"]), "开设中央厨房")
	check(bool(r["central_kitchen"]), "中央厨房标记")
	check(sys.can_enter_mode(r, "food_factory"), "可进入食品工业")
	check(bool(sys.expand_to(r, "food_factory")["ok"]), "扩张为食品工业")
	var fr: Dictionary = sys.franchise(r, 500000)
	check(bool(fr["ok"]) and int(fr["franchise_count"]) == 1, "开放连锁加盟")
	var stores0: int = int(r["stores"])
	check(bool(sys.open_store(r, 100000)["ok"]) and int(r["stores"]) == stores0 + 1, "新开门店")
	# 卫生不足无法认证。
	var low: Dictionary = sys.new_restaurant(1000000, {"hygiene": 50.0})
	check(not bool(sys.certify(low, "haccp")["ok"]), "卫生不足拒绝认证")


func _test_food_safety_incident() -> void:
	var sys = DiningScript.new()
	var r: Dictionary = sys.new_restaurant(10000000)
	var money0: int = int(r["money"])
	var rep0: float = float(r["reputation"])
	var inc: Dictionary = sys.food_safety_incident(r, "contamination", 0.8)
	check(bool(inc["ok"]), "食安事故触发")
	check(int((inc["incident"] as Dictionary)["penalty"]) > 0, "有处罚")
	check(int(r["money"]) < money0, "事故扣款")
	check(float(r["reputation"]) < rep0, "口碑下滑")
	check(not bool(sys.food_safety_incident(r, "bogus", 0.5)["ok"]), "未知事由被拒")
	var severe: Dictionary = sys.food_safety_incident(r, "poisoning", 0.95)
	check(bool((severe["incident"] as Dictionary)["suspended"]), "严重事故停业整顿")
	var qc: Dictionary = sys.quality_control(r, {"roll": 0.0})
	check(not bool(qc["passed"]), "低分抽查不合格")
	check(bool(sys.quality_control(r, {"roll": 1.0})["passed"]), "高分抽查合格")
	var rec: Dictionary = sys.recall_product(r, "home_style", 100.0)
	check(int(rec["cost"]) > 0, "召回产生费用")


func _test_reviews_marketing_and_chef() -> void:
	var sys = DiningScript.new()
	var r: Dictionary = sys.new_restaurant(10000000, {"reputation": 50.0, "hygiene": 70.0})
	sys.add_to_menu(r, "home_style")
	var stars: int = sys.review_stars(r)
	check(stars >= 1 and stars <= 5, "评星在 1..5")
	check(not str(sys.star_name(r)).is_empty(), "评星名称")
	var rank: Dictionary = sys.rank_listing(r, 100)
	check(int(rank["rank"]) >= 1 and int(rank["rank"]) <= 100, "榜单排名区间")
	var mk: Dictionary = sys.marketing_campaign(r, "ads", 200000)
	check(bool(mk["ok"]) and float(r["marketing"]) > 1.0, "广告提升营销")
	var bl: Dictionary = sys.marketing_campaign(r, "influencer", 200000, null, {"roll": 0.0})
	check(bool(bl["backlash"]), "网红营销反噬")
	var boom: Dictionary = sys.viral_event(r, 0.2)
	check_eq(str(boom["kind"]), "boom", "网红爆单")
	var crisis: Dictionary = sys.viral_event(r, 0.8)
	check_eq(str(crisis["kind"]), "crisis", "差评危机")
	# 厨师被挖角。
	var r2: Dictionary = sys.new_restaurant(1000000)
	sys.hire(r2, "chef", 2)
	r2["chef_loyalty"] = 10.0
	var po: Dictionary = sys.poach_chef(r2, 0.0)
	check(bool(po["poached"]) and sys.staff_count(r2, "chef") == 1, "厨师被挖角流失")
	var r3: Dictionary = sys.new_restaurant(1000000)
	check(not bool(sys.poach_chef(r3, 0.0)["ok"]), "无主厨时不可挖角")


func _test_food_industry() -> void:
	var sys = DiningScript.new()
	var r: Dictionary = sys.new_restaurant(10000000)
	var bad: Dictionary = sys.process_food(r, "home_style", 10.0)
	check(not bool(bad["ok"]) and str(bad["reason"]) == "no_food_facility", "无中央厨房不可加工")
	r["central_kitchen"] = true
	var ok: Dictionary = sys.process_food(r, "home_style", 10.0)
	check(bool(ok["ok"]) and sys.product_qty(r, "home_style") > 0.0, "加工预包装食品")
	check(float(ok["shelf_life_days"]) > 0.0, "保质期")
	var dist: Dictionary = sys.distribute(r, "home_style", 5.0, "retail")
	check(bool(dist["ok"]) and int(dist["net"]) > 0, "渠道分销")
	var sp: Dictionary = sys.spoilage(r, 90.0)
	check(float(sp["lost"]) >= 0.0, "保质损耗")
	check(bool(sys.to_dict(r).has("products")), "序列化快照")
