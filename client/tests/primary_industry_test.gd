extends "res://tests/test_base.gd"
## 农林牧渔深化测试（任务 32；R73；design D29）。
## 覆盖：数据表、渔业（捕捞/养殖/休渔/海难/资源恢复）、林业（林权/采伐/造林/护林/火灾/木材/碳汇）、
##       狩猎（许可/枪支政策/无证违法/保护区）、生态（过度开发/水土流失/修复/入侵物种）、边界。

const PrimaryScript = preload("res://sim/primary_industry.gd")


func _suite_name() -> String:
	return "primary_industry"


func run_tests() -> void:
	_test_tables()
	_test_fishery()
	_test_forest()
	_test_hunting()
	_test_ecology()
	_test_edges()


func _test_tables() -> void:
	var sys = PrimaryScript.new()
	check_eq(PrimaryScript.FISH_SPECIES.size(), 3, "三种渔业资源")
	check_eq(PrimaryScript.FOREST_TYPES.size(), 3, "三种林分")
	check_eq(PrimaryScript.GAME_SPECIES.size(), 3, "三种野味")


func _test_fishery() -> void:
	var sys = PrimaryScript.new()
	var f: Dictionary = sys.new_fishery(1000000, {"boats": 10})
	check(bool(sys.add_boat(f, 2)["ok"]), "增加渔船")
	check_eq(int(f["boats"]), 12, "渔船数量更新")
	var caught: Dictionary = sys.catch_fish(f, "cod", 300.0)
	check(bool(caught["ok"]) and float(caught["caught"]) > 0.0, "捕捞成功")
	check(float(f["resource_ratio"]) < 1.0, "捕捞降低资源比例")
	var ratio0: float = float(f["resource_ratio"])
	sys.recover_resource(f, 365.0)
	check(float(f["resource_ratio"]) >= ratio0, "资源恢复")
	# 过度捕捞后恢复变慢：资源比例越低，恢复速率越低。
	var low: Dictionary = sys.new_fishery(1000000, {"boats": 100})
	sys.catch_fish(low, "tuna", 100000.0)
	var low_ratio: float = float(low["resource_ratio"])
	var recovered: Dictionary = sys.recover_resource(low, 365.0)
	check(float(recovered["resource_ratio"]) - low_ratio <= 0.02 + 1e-9, "过度捕捞后恢复缓慢")
	# 养殖不受休渔限制。
	f["aquaculture"] = 10.0
	var aqua: Dictionary = sys.harvest_aquaculture(f, "shrimp")
	check(bool(aqua["ok"]) and int(aqua["revenue"]) > 0, "养殖收获")
	# 休渔期违规被罚。
	sys.start_closed_season(f)
	check(sys.is_closed_season(f), "进入休渔期")
	var money0: int = int(f["money"])
	var bad: Dictionary = sys.catch_fish(f, "cod", 100.0)
	check(not bool(bad["ok"]) and str(bad["reason"]) == "closed_season", "休渔期禁止捕捞")
	check(int((bad["violation"] as Dictionary)["fine"]) > 0, "休渔违规罚款")
	check(int(f["money"]) < money0, "罚款扣款")
	# 海难损失渔船。
	var storm: Dictionary = sys.storm_check(f, {"storm_severity": 1.0, "roll": 0.0})
	check(bool(storm["occurred"]) and int(storm["boats_lost"]) > 0, "海难损失渔船")
	check(not bool(sys.catch_fish(f, "bogus", 1.0)["ok"]), "未知鱼种被拒")


func _test_forest() -> void:
	var sys = PrimaryScript.new()
	var forest: Dictionary = sys.new_forest(1000000, {"forest_type": "timber", "area": 100.0, "trees": 10000.0})
	check(not bool(sys.log_trees(forest, 100.0)["ok"]), "无林权不能采伐")
	sys.grant_forest_rights(forest)
	check(bool(forest["rights"]), "取得林权")
	var logged: Dictionary = sys.log_trees(forest, 1000.0)
	check(bool(logged["ok"]) and float(logged["timber"]) > 0.0, "采伐产出木材")
	check(float(forest["trees"]) < 10000.0, "采伐减少林木")
	check(float(forest["fire_risk"]) > PrimaryScript.FIRE_BASE_RISK, "过度采伐提高火灾风险")
	sys.reforest(forest, 500.0)
	check(float(forest["trees"]) > float(logged["trees"]), "造林增加林木")
	var risk0: float = float(forest["fire_risk"])
	sys.patrol_fire(forest)
	check(float(forest["fire_risk"]) < risk0, "护林降低火灾风险")
	var fire: Dictionary = sys.fire_check(forest, {"roll": 0.0, "severity": 0.5})
	check(bool(fire["occurred"]) and float(fire["lost_trees"]) > 0.0, "火灾损失林木")
	check(int(fire["restoration_cost"]) > 0, "火灾修复成本")
	var sale: Dictionary = sys.timber_market(forest, 10.0, 500)
	check(bool(sale["ok"]) and int(sale["revenue"]) > 0, "木材市场销售")
	var carbon: Dictionary = sys.carbon_sink(forest, 100, {"years": 1.0})
	check(float(carbon["credits"]) > 0.0 and int(carbon["revenue"]) > 0, "林业碳汇")


func _test_hunting() -> void:
	var sys = PrimaryScript.new()
	# 枪支政策禁止则无法取得许可。
	var forbidden: Dictionary = sys.new_hunter(100000, {"gun_policy_allows": false})
	check(not bool(sys.hunting_license(forbidden)["ok"]), "枪支政策禁止不予许可")
	# 无证狩猎违法。
	var poacher: Dictionary = sys.new_hunter(100000)
	var illegal: Dictionary = sys.hunt(poacher, "deer", 2.0, {})
	check(not bool(illegal["legal"]), "无证狩猎违法")
	check(int(poacher["wanted_level"]) > 0, "无证狩猎提高通缉")
	# 合法狩猎。
	var hunter: Dictionary = sys.new_hunter(100000, {"gun_permit": true})
	var lic: Dictionary = sys.hunting_license(hunter)
	check(bool(lic["ok"]) and bool(hunter["license"]), "取得狩猎许可")
	var hunt: Dictionary = sys.hunt(hunter, "rabbit", 10.0, {"roll": 0.0, "hit_rate": 0.7})
	check(bool(hunt["legal"]) and float(hunt["harvested"]) > 0.0, "合法狩猎有收获")
	check(int(hunt["revenue"]) > 0, "狩猎收益")
	# 保护区狩猎违法。
	var protected: Dictionary = sys.hunt(hunter, "deer", 1.0, {"roll": 0.0, "in_protected_area": true})
	check(not bool(protected["ok"]) and str(protected["reason"]) == "protected_area", "保护区禁止狩猎")
	check(not bool(sys.hunt(hunter, "bogus", 1.0)["ok"]), "未知野味被拒")


func _test_ecology() -> void:
	var sys = PrimaryScript.new()
	var state: Dictionary = sys.new_ecology()
	var od: Dictionary = sys.over_develop(state, 0.5)
	check(float(od["resource_ratio"]) < 1.0, "过度开发资源衰退")
	check(float(od["erosion"]) > 0.0, "过度开发水土流失")
	var restore: Dictionary = sys.restore_ecology(state, 1000000)
	check(int(restore["cost"]) > 0 and float(restore["restoration_done"]) > 0.0, "生态修复")
	sys.invasive_species(state, "water_hyacinth", 0.5)
	check(float((state["invasive"] as Dictionary)["water_hyacinth"]) > 0.0, "外来物种入侵")
	var storm: Dictionary = sys.extreme_weather(state, 0.8)
	check(float(storm["yield_loss_ratio"]) > 0.0, "极端天气减产")


func _test_edges() -> void:
	var sys = PrimaryScript.new()
	var state: Dictionary = sys.new_ecology()
	var smuggle: Dictionary = sys.poaching_smuggling(state, "deer", 5.0, {"roll": 0.0, "detection_chance": 0.3})
	check(int(smuggle["revenue"]) > 0, "偷猎走私收益")
	check(bool(smuggle["detected"]), "偷猎被查获")
	check(int(state["wanted_level"]) > 0, "偷猎提高通缉")
	var erosion: Dictionary = sys.soil_erosion(state, 0.5)
	check(float(erosion["erosion"]) > 0.0 and float(erosion["soil_quality"]) < 1.0, "水土流失降低土壤质量")
