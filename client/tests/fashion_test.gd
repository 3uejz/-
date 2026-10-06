extends "res://tests/test_base.gd"
## 时尚、设计与奢侈品测试（任务 33；R75；design D31）。
## 覆盖：数据表、作品评分（技能+灵感+潮流契合）、潮流周期与引领/跟潮、时装周与联名限量、
##       代言人与翻车、奢侈品鉴定/二手/拍卖/保值、品牌老化复兴与抄袭指控、假货侵权。

const FashionScript = preload("res://sim/fashion.gd")


func _suite_name() -> String:
	return "fashion"


func run_tests() -> void:
	_test_tables()
	_test_design_score()
	_test_trend_cycle()
	_test_fashion_week_and_collab()
	_test_endorser_scandal()
	_test_luxury_market()
	_test_brand_aging_and_plagiarism()


func _test_tables() -> void:
	var sys = FashionScript.new()
	check_eq(sys.discipline_keys().size(), 5, "五类设计路径")
	check_eq(sys.positioning_keys().size(), 4, "四种品牌定位")
	check_eq(sys.season_keys().size(), 3, "三个季节")
	check_eq(sys.luxury_keys().size(), 5, "五类奢侈品")
	check_eq(str(sys.trend_phase_names()["emerging"]), "新兴", "潮流阶段命名")
	check_eq(str((sys.discipline_def("apparel") as Dictionary)["name"]), "服装设计", "服装设计路径")


func _test_design_score() -> void:
	var sys = FashionScript.new()
	var trend: Dictionary = sys.new_trend({"hot_discipline": "apparel", "phase": "emerging"})
	var skills: Array = [{"content_key": "skill.design_apparel", "level": 20}]
	# 热门学科 + 满灵感 + 满契合：0.45×100 + 0.20×100 + 0.35×100 = 100。
	var d: Dictionary = sys.create_design("apparel", skills, trend, null, {"inspiration": 100.0})
	check(bool(d["ok"]), "创作成功")
	check_near(float(d["score"]), 100.0, 1e-6, "满技能满灵感满契合")
	check_eq(str(d["grade"]), "masterpiece", "大师级")
	# 非热门学科契合度低：0.45×100 + 20 + 0.35×0.25×100 = 73.75。
	var graphic_skills: Array = [{"content_key": "skill.design_graphic", "level": 20}]
	var d2: Dictionary = sys.create_design("graphic", graphic_skills, trend, null, {"inspiration": 100.0})
	check_near(float(d2["score"]), 73.75, 1e-6, "非热门学科契合度低")
	check(float(d2["score"]) < float(d["score"]), "契合度影响评分")
	# 抄袭惩罚。
	var d3: Dictionary = sys.create_design("apparel", skills, trend, null, {"inspiration": 100.0, "plagiarized": true, "similarity": 1.0})
	check(float(d3["score"]) < float(d["score"]), "抄袭拉低评分")
	check(not bool(sys.create_design("bogus", [], {})["ok"]), "未知学科被拒")


func _test_trend_cycle() -> void:
	var sys = FashionScript.new()
	var trend: Dictionary = sys.new_trend({"hot_discipline": "apparel", "phase": "emerging"})
	check_eq(str(trend["phase"]), "emerging", "新潮流新兴")
	check_eq(str(sys.advance_trend(trend)["phase"]), "rising", "潮流上升")
	check_eq(str(sys.advance_trend(trend)["phase"]), "peak", "潮流顶峰")
	check_eq(str(sys.advance_trend(trend)["phase"]), "declining", "潮流退潮")
	var restart: Dictionary = sys.advance_trend(trend, {"next_hot": "jewelry"})
	check_eq(str(restart["phase"]), "emerging", "潮流重启新兴")
	check_eq(str(restart["hot_discipline"]), "jewelry", "换热门学科")
	# 引领 vs 跟潮。
	var leader: Dictionary = sys.new_brand(1000000, {"reputation": 80.0})
	check_eq(sys.leading_or_following(leader, {"phase": "emerging"}), "leading", "新兴期高声誉引领潮流")
	check_eq(sys.leading_or_following(leader, {"phase": "peak"}), "following", "顶峰期跟潮")


func _test_fashion_week_and_collab() -> void:
	var sys = FashionScript.new()
	var brand: Dictionary = sys.new_brand(10000000, {"positioning": "premium", "fame": 60.0})
	var premium: float = sys.brand_premium(brand)
	check(premium > 1.0, "品牌溢价大于 1")
	var fw: Dictionary = sys.fashion_week(brand, [{"score": 80.0}, {"score": 90.0}], {"season": "aw"})
	check(bool(fw["ok"]) and int(fw["orders"]) > 0, "时装周产生订单")
	check_near(float(fw["avg_score"]), 85.0, 1e-6, "作品均分")
	check(float(fw["premium"]) > 1.0, "时装周品牌溢价")
	var c: Dictionary = sys.collab(brand, 80.0)
	check(int(c["revenue"]) > 0 and float(c["hype"]) > 0.0, "联名收益与热度")
	var bv0: int = int(brand["brand_value"])
	var le: Dictionary = sys.limited_edition(brand, "sneaker", 100)
	check(int(le["price"]) > 0 and int(brand["brand_value"]) > bv0, "限量发售提升品牌价值")
	check(float(le["scarcity"]) > 0.0, "稀缺度")


func _test_endorser_scandal() -> void:
	var sys = FashionScript.new()
	var brand: Dictionary = sys.new_brand(10000000)
	var fame0: float = float(brand["fame"])
	var e: Dictionary = sys.endorse(brand, {"id": "s1", "name": "明星", "fame": 90.0, "scandal_risk": 0.5, "cost": 1000000})
	check(bool(e["ok"]) and float(brand["fame"]) > fame0, "签约代言人提升热度")
	var rep0: float = float(brand["reputation"])
	var sc: Dictionary = sys.endorser_scandal(brand, 0.1)
	check(bool(sc["scandal"]) and float(brand["reputation"]) < rep0, "代言翻车损伤声誉")
	# 高 roll 不命中风险。
	var brand2: Dictionary = sys.new_brand(10000000)
	sys.endorse(brand2, {"id": "s2", "name": "代言", "fame": 80.0, "scandal_risk": 0.3})
	check(not bool(sys.endorser_scandal(brand2, 0.9)["scandal"]), "风险未命中")
	var brand3: Dictionary = sys.new_brand(1000000)
	check(not bool(sys.endorser_scandal(brand3, 0.1)["ok"]), "无代言人不可翻车")


func _test_luxury_market() -> void:
	var sys = FashionScript.new()
	var genuine: Dictionary = {"authentic": true, "provenance": 1.0, "value": 50000}
	var a: Dictionary = sys.authenticate(genuine)
	check_eq(str(a["result"]), "genuine", "确认为真品")
	var fake: Dictionary = {"authentic": false, "provenance": 1.0, "value": 50000}
	var af: Dictionary = sys.authenticate(fake, {"roll": 0.1})
	check_eq(str(af["result"]), "counterfeit", "鉴定为仿品")
	var sh: Dictionary = sys.secondhand_price(genuine, 0.8)
	check(int(sh["price"]) > 0 and int(sh["price"]) < 50000, "二手折价")
	var auc: Dictionary = sys.auction(genuine, [40000, 60000], {"reserve": 50000})
	check(bool(auc["sold"]) and int(auc["price"]) == 60000, "拍卖成交")
	var low: Dictionary = sys.auction(genuine, [10000], {"reserve": 50000})
	check(not bool(low["sold"]), "低于保留价流拍")
	var cv: Dictionary = sys.collectible_value(100000, 5.0, 0.05)
	check(int(cv["value"]) > 100000 and not bool(cv["bubble_risk"]), "收藏保值")
	var cv2: Dictionary = sys.collectible_value(100000, 5.0, 0.2)
	check(bool(cv2["bubble_risk"]), "高收益标记泡沫")
	var brand: Dictionary = sys.new_brand(10000000)
	var ch: Dictionary = sys.counterfeit_hit(brand, 1000000, {"patent": true})
	check(bool(ch["litigation"]) and int(ch["recovered"]) > 0, "专利维权追偿")


func _test_brand_aging_and_plagiarism() -> void:
	var sys = FashionScript.new()
	var brand: Dictionary = sys.new_brand(10000000, {"positioning": "mass"})
	var rel0: float = float(brand["relevance"])
	sys.brand_aging(brand, 5.0)
	check(float(brand["relevance"]) < rel0, "品牌老化相关度下降")
	var aged: float = float(brand["relevance"])
	sys.renew_brand(brand, "designer_change", 5000000)
	check(float(brand["relevance"]) > aged, "品牌复兴提升相关度")
	# 抄袭指控。
	var b2: Dictionary = sys.new_brand(10000000)
	var rep0: float = float(b2["reputation"])
	var pa: Dictionary = sys.plagiarism_accusation(b2, {"value": 1000000}, 0.9, null, {"roll": 0.0})
	check(bool(pa["accused"]) and bool(pa["guilty"]), "高相似度被认定抄袭")
	check(int(pa["damages"]) > 0 and float(b2["reputation"]) < rep0, "抄袭赔偿与声誉下滑")
	var pa2: Dictionary = sys.plagiarism_accusation(b2, {}, 0.2)
	check(not bool(pa2["accused"]), "低相似度不指控")
	# 营销反噬。
	var mk: Dictionary = sys.run_marketing(b2, "influencer", 1000000, null, {"roll": 0.0})
	check(bool(mk["backlash"]), "营销反噬")
	check(bool(sys.to_dict(brand).has("relevance")), "序列化快照")
