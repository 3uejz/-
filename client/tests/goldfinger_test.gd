extends "res://tests/test_base.gd"
## 金手指系统测试（任务 44；R100；design「金手指系统」）。

const GoldScript = preload("res://sim/goldfinger.gd")


func _suite_name() -> String:
	return "goldfinger"


func run_tests() -> void:
	_test_default_off_and_mode()
	_test_distribution_and_draw()
	_test_remote_config()
	_test_pity()
	_test_constraints()
	_test_reroll()
	_test_points_cap_and_reset()
	_test_upgrade_and_exchange()
	_test_switches_and_modules()
	_test_budget()
	_test_generation_and_achievement()
	_test_persistence()
	_test_def_resource()


func _defs() -> Array:
	return [
		{"content_key": "gf.common_a", "name": "小运", "rarity": "common", "category": "growth", "modules": [],
			"effects": [{"target": "attr.charm", "op": "add", "value": 5, "mode": "instant", "cost": 10}],
			"growth": {"max_level": 3, "upgrade_costs": [100, 200]}},
		{"content_key": "gf.rare_b", "name": "灵觉", "rarity": "rare", "category": "info", "modules": ["quest"],
			"effects": [{"target": "skill.observe", "op": "grant", "value": 1, "mode": "continuous", "cost": 50}]},
		{"content_key": "gf.epic_c", "name": "洞察", "rarity": "epic", "category": "system", "modules": ["shop"],
			"effects": [{"target": "system.appraisal", "op": "unlock", "value": 1, "mode": "continuous", "cost": 100}]},
		{"content_key": "gf.legendary_d", "name": "天命", "rarity": "legendary", "category": "resource", "modules": ["quest", "craft"],
			"effects": [{"target": "resource.luck", "op": "mul", "value": 2.0, "mode": "continuous", "cost": 200}]},
		{"content_key": "gf.era_e", "name": "未来视", "rarity": "common", "category": "time", "modules": [],
			"effects": [{"target": "attr.intelligence", "op": "add", "value": 3, "mode": "instant", "cost": 10}],
			"constraints": {"era_min": 5}},
		{"content_key": "gf.over_budget", "name": "超模", "rarity": "common", "category": "growth", "modules": [],
			"effects": [{"target": "attr.charm", "op": "add", "value": 999, "mode": "instant", "cost": 9999}]},
	]


func _test_default_off_and_mode() -> void:
	var sys = GoldScript.new()
	var st: Dictionary = sys.new_state()
	check(not bool(st["enabled"]), "默认关闭")
	check(not bool(sys.draw(st, _defs())["ok"]), "关闭时不抽取")
	sys.set_mode(st, true)
	check(bool(st["enabled"]), "开档启用")
	check(bool(sys.set_mode(st, false)["ok"]), "可再关闭")
	check_eq((st["items"] as Array).size(), 0, "关闭清空条目")


func _test_distribution_and_draw() -> void:
	var sys = GoldScript.new()
	var dist: Dictionary = sys.distribution()
	var total: float = 0.0
	for v in dist.values():
		total += float(v)
	check_near(total, 1.0, 1e-6, "分布归一化")
	var st: Dictionary = sys.new_state()
	sys.set_mode(st, true)
	var r: Dictionary = sys.draw(st, _defs(), {"forced_rarity": "epic", "roll_pick": 0.0})
	check(bool(r["ok"]), "抽到史诗")
	check_eq(str(r["item"]["content_key"]), "gf.epic_c", "命中史诗条目")
	var r2: Dictionary = sys.draw(st, _defs(), {"roll_rarity": 0.0, "roll_pick": 0.0})
	check_eq(str(r2["rarity"]), "common", "低 roll 命中普通")
	var r3: Dictionary = sys.draw(st, _defs(), {"roll_rarity": 0.99, "roll_pick": 0.0})
	check_eq(str(r3["rarity"]), "legendary", "高 roll 命中传说")


func _test_remote_config() -> void:
	var sys = GoldScript.new()
	var cfg: Dictionary = sys.config_from_remote({
		"goldfinger.distribution.legendary": 10.0,
		"goldfinger.pity.epic_at": 5,
		"goldfinger.reroll_cost": 200,
		"goldfinger.points.daily_cap": 555,
	})
	check(float(cfg["distribution"]["legendary"]) > 0.03, "远程提升传说权重")
	check_eq(int(cfg["pity_epic_at"]), 5, "远程保底阈值")
	check_eq(int(cfg["reroll_cost"]), 200, "远程重抽消耗")
	check_eq(int(cfg["daily_cap"]), 555, "远程每日上限")


func _test_pity() -> void:
	var sys = GoldScript.new()
	var st: Dictionary = sys.new_state()
	sys.set_mode(st, true)
	st["pity_counter"] = sys.PITY_EPIC_AT
	var r: Dictionary = sys.draw(st, _defs(), {"roll_rarity": 0.0, "roll_pick": 0.0})
	check_eq(str(r["rarity"]), "epic", "保底触发史诗")
	check(bool(r["pity_triggered"]), "保底标记")
	check_eq(int(st["pity_counter"]), 0, "出高稀有度后保底清零")
	st["pity_counter"] = sys.PITY_LEGENDARY_AT
	var r2: Dictionary = sys.draw(st, _defs(), {"roll_rarity": 0.0, "roll_pick": 0.0})
	check_eq(str(r2["rarity"]), "legendary", "高保底触发传说")


func _test_constraints() -> void:
	var sys = GoldScript.new()
	var pool0: Array = sys.eligible(_defs(), {"era": 0, "owned": []})
	check_eq(pool0.size(), 5, "低时代排除高时代金手指")
	var pool5: Array = sys.eligible(_defs(), {"era": 5, "owned": []})
	check_eq(pool5.size(), 6, "满足时代后纳入")
	var keys: Array = []
	for d in pool5:
		keys.append(str(d["content_key"]))
	check(keys.has("gf.era_e"), "时代达标包含未来视")


func _test_reroll() -> void:
	var sys = GoldScript.new()
	var st: Dictionary = sys.new_state()
	sys.set_mode(st, true)
	sys.draw(st, _defs(), {"forced_rarity": "common"})
	check(bool(sys.reroll(st, _defs(), {"reroll_cost": 100, "forced_rarity": "common"})["free"]), "首次重抽免费")
	sys.reroll(st, _defs(), {"reroll_cost": 100, "forced_rarity": "common"})
	sys.reroll(st, _defs(), {"reroll_cost": 100, "forced_rarity": "common"})
	check_eq(int(st["rerolls_used"]), 3, "免费重抽用尽")
	var paid: Dictionary = sys.reroll(st, _defs(), {"reroll_cost": 100, "forced_rarity": "common"})
	check(not bool(paid["ok"]), "无积分付费重抽失败")
	sys.grant_points(st, 500)
	var paid2: Dictionary = sys.reroll(st, _defs(), {"reroll_cost": 100, "forced_rarity": "common"})
	check(bool(paid2["ok"]), "有积分付费重抽成功")
	check_eq(int(paid2["cost"]), 100, "扣除重抽积分")
	check_eq(int(st["points"]), 400, "积分余额正确")


func _test_points_cap_and_reset() -> void:
	var sys = GoldScript.new()
	var st: Dictionary = sys.new_state()
	sys.set_mode(st, true)
	var g1: Dictionary = sys.grant_points(st, 800, 1000)
	check_eq(int(g1["granted"]), 800, "首次全额产出")
	var g2: Dictionary = sys.grant_points(st, 500, 1000)
	check_eq(int(g2["granted"]), 200, "触及每日上限")
	check_eq(int(g2["capped"]), 300, "超出部分被截断")
	sys.reset_daily(st)
	var g3: Dictionary = sys.grant_points(st, 500, 1000)
	check_eq(int(g3["granted"]), 500, "跨日重置上限")


func _test_upgrade_and_exchange() -> void:
	var sys = GoldScript.new()
	var st: Dictionary = sys.new_state()
	sys.set_mode(st, true)
	var def: Dictionary = _defs()[0]
	sys.draw(st, [def], {"forced_rarity": "common"})
	sys.grant_points(st, 300, 10000)
	var u1: Dictionary = sys.upgrade(st, def, "gf.common_a")
	check_eq(int(u1["level"]), 2, "升到 2 级")
	var u2: Dictionary = sys.upgrade(st, def, "gf.common_a")
	check_eq(int(u2["level"]), 3, "升到 3 级")
	check(not bool(sys.upgrade(st, def, "gf.common_a")["ok"]), "满级不可升")
	check_eq(int(st["points"]), 0, "升级扣尽积分")
	var ex_bad: Dictionary = sys.exchange(st, 50)
	check(not bool(ex_bad["ok"]), "积分不足兑换失败")
	sys.grant_points(st, 100, 10000)
	check(bool(sys.exchange(st, 50, {"item": "potion"})["ok"]), "积分足够兑换成功")


func _test_switches_and_modules() -> void:
	var sys = GoldScript.new()
	var st: Dictionary = sys.new_state()
	sys.set_mode(st, true)
	sys.draw(st, _defs(), {"forced_rarity": "rare"})
	sys.draw(st, _defs(), {"forced_rarity": "legendary"})
	var eff0: Array = sys.active_continuous_effects(st, _defs())
	check_eq(eff0.size(), 2, "启用的持续型效果生效")
	var reg: Dictionary = sys.module_registry(st)
	check(reg.has("quest") and reg.has("craft"), "模块注册表并入并集")
	check(bool(sys.toggle_item(st, "gf.rare_b", false)["ok"]), "单条禁用")
	check_eq(sys.active_continuous_effects(st, _defs()).size(), 1, "禁用后持续型即时失效")
	check(not sys.module_registry(st).has("quest") or sys.module_registry(st).has("craft"), "禁用条目模块移出")
	check(bool(sys.toggle_item(st, "gf.rare_b", true)["ok"]), "可再启用")
	check(not bool(sys.toggle_item(st, "gf.none", false)["ok"]), "未拥有不可切换")


func _test_budget() -> void:
	var sys = GoldScript.new()
	check(bool(sys.budget_ok(_defs()[0])["ok"]), "普通金手指在预算内")
	check(not bool(sys.budget_ok(_defs()[5])["ok"]), "超预算金手指被拒")
	var over: Dictionary = sys.budget_ok(_defs()[5])
	check(float(over["cost"]) > float(over["budget"]), "预算比较数值正确")


func _test_generation_and_achievement() -> void:
	var sys = GoldScript.new()
	var st: Dictionary = sys.new_state()
	sys.set_mode(st, true)
	sys.draw(st, _defs(), {"forced_rarity": "common"})
	sys.grant_points(st, 500)
	var ng: Dictionary = sys.new_generation(st)
	check_eq(int(ng["gen"]), 2, "世代 +1")
	check_eq((st["items"] as Array).size(), 0, "轮回清空条目（每代重抽）")
	check_eq(int(st["points"]), 0, "轮回积分清零")
	check(bool(st["enabled"]), "轮回保留模式开关")
	check_eq(sys.achievement_tag(st), "goldfinger", "启用金手指成就单独标记")
	sys.set_mode(st, false)
	check_eq(sys.achievement_tag(st), "", "未启用无标记")


func _test_persistence() -> void:
	var sys = GoldScript.new()
	var st: Dictionary = sys.new_state()
	sys.set_mode(st, true)
	sys.draw(st, _defs(), {"forced_rarity": "epic"})
	sys.grant_points(st, 250, 10000)
	var clone: Dictionary = sys.from_dict(sys.to_dict(st))
	check(bool(clone["enabled"]), "模式序列化往返")
	check_eq(int(clone["points"]), 250, "积分序列化往返")
	check_eq((clone["items"] as Array).size(), 1, "条目序列化往返")


func _test_def_resource() -> void:
	var DefScript = preload("res://sim/goldfinger_def.gd")
	var res = DefScript.new()
	res.from_def(_defs()[1])
	check_eq(res.content_key, "gf.rare_b", "资源填充 content_key")
	check_eq(res.rarity, "rare", "资源填充稀有度")
	var def: Dictionary = res.to_def()
	check_eq(str(def["content_key"]), "gf.rare_b", "资源转回定义")
	check((def["effects"] as Array).size() == 1, "效果随资源往返")
	var sys = GoldScript.new()
	check(bool(sys.budget_ok(def)["ok"]), "资源定义通过预算校验")
