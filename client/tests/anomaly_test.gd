extends "res://tests/test_base.gd"
## 隐秘异常收容体系测试（任务 36、36.1；R88；design D44）。
## 覆盖：隔离架构（默认隐藏、不参与常规结算）、门闩途径、分级与权限、
##       暴露反噬阈值、记忆删除药剂剂量副作用与使用上限、图鉴可见性、
##       能力线资源与成长、对抗战斗、异常条目校验与生成、跨代传承继承、
##       异常与犯罪系统交叉标记。

const AnomalyScript = preload("res://sim/anomaly.gd")


func _suite_name() -> String:
	return "anomaly"


func run_tests() -> void:
	_test_isolation()
	_test_tables()
	_test_gates()
	_test_exposure_backlash()
	_test_amnestics()
	_test_inheritance()
	_test_clearance_and_catalog()
	_test_abilities()
	_test_combat()
	_test_entry_generation_and_validation()
	_test_faction_missions()
	_test_social_cross()


func _test_isolation() -> void:
	var sys = AnomalyScript.new()
	var st: Dictionary = sys.new_state()
	check(sys.is_hidden(st), "异常状态树默认隐藏")
	check(not sys.is_active(st), "默认未激活")
	check(not sys.can_enter(st), "默认不可进入异常世界")
	check((sys.regular_effects(st) as Dictionary).is_empty(), "隐藏时不参与常规结算")
	# 开启门闩后仍保持隐藏，常规系统不可见。
	sys.open_gate(st, "special_item")
	check((sys.regular_effects(st) as Dictionary).is_empty(), "激活后仍不参与常规结算")
	check(sys.is_active(st), "门闩开启后激活")


func _test_tables() -> void:
	var sys = AnomalyScript.new()
	check_eq(sys.containment_levels().size(), 8, "八种收容等级")
	check_eq(sys.threat_levels().size(), 5, "五种威胁等级")
	check_eq(sys.hazard_types().size(), 8, "八种危害类型")
	check_eq(sys.ability_keys().size(), 4, "四条能力线")
	check_eq(sys.factions().size(), 4, "四类阵营")
	check_eq(sys.identities().size(), 5, "五种玩家身份")
	check_eq(sys.gate_keys().size(), 5, "五种门闩途径")
	check(sys.core_catalog_size() >= 8 and sys.core_catalog_size() <= 15, "核心手写条目 8–15 条")
	check(sys.catalog_size() >= 2000, "条目总量不少于 2000")
	check_eq(str(sys.terms()["foundation"]), "基金会", "术语：基金会")
	check_eq(str(sys.terms()["amnestic"]), "记忆删除药剂", "术语：记忆删除药剂")


func _test_gates() -> void:
	var sys = AnomalyScript.new()
	check(not sys.roll_rare_talent(0.999), "高 roll 不具稀有天赋")
	check(sys.roll_rare_talent(0.0), "低 roll 具备稀有天赋")
	var st: Dictionary = sys.new_state()
	var res: Dictionary = sys.rare_talent_check(st, 0.0)
	check(bool(res["born_with_talent"]), "出生携带稀有天赋")
	check(sys.has_gate(st, "rare_talent"), "开启稀有天赋门闩")
	check(not bool(sys.open_gate(st, "bogus")["ok"]), "未知门闩被拒")


func _test_exposure_backlash() -> void:
	var sys = AnomalyScript.new()
	var s0: Dictionary = sys.new_state()
	sys.add_exposure(s0, 10.0)
	check(not bool(sys.check_backlash(s0)["triggered"]), "低暴露无反噬")
	var s1: Dictionary = sys.new_state()
	sys.add_exposure(s1, 45.0)
	check_eq(str(sys.check_backlash(s1)["type"]), "contamination", "阈值 40 触发认知污染")
	var s2: Dictionary = sys.new_state()
	sys.add_exposure(s2, 65.0)
	check_eq(str(sys.check_backlash(s2)["type"]), "hunt", "阈值 60 触发猎杀")
	var s3: Dictionary = sys.new_state()
	sys.add_exposure(s3, 80.0)
	check_eq(str(sys.check_backlash(s3)["type"]), "containment", "阈值 75 触发收容")
	var s4: Dictionary = sys.new_state()
	sys.add_exposure(s4, 95.0)
	var b4: Dictionary = sys.check_backlash(s4)
	check_eq(str(b4["type"]), "ban", "阈值 90 触发封禁")
	check(bool(b4["irreversible"]), "封禁不可逆")
	var s5: Dictionary = sys.new_state()
	sys.add_exposure(s5, 105.0)
	var b5: Dictionary = sys.check_backlash(s5)
	check_eq(str(b5["type"]), "breakdown", "阈值 100 触发精神崩溃")
	check_eq(str(sys.ending(s5)), "breakdown", "精神崩溃触发不可逆结局")


func _test_amnestics() -> void:
	var sys = AnomalyScript.new()
	var st: Dictionary = sys.new_state()
	sys.contact_hazard(st, "meme", 30.0)
	sys.contact_hazard(st, "cognition", 20.0)
	check_near(sys.contamination_total(st), 50.0, 1e-6, "接触模因与认知累积污染")
	check(float(sys.exposure(st)) > 0.0, "接触危害累积暴露")
	var a1: Dictionary = sys.amnestics(st, 0.5)
	check(bool(a1["ok"]) and float(a1["cleared"]) > 0.0, "记忆删除清除污染")
	check(sys.contamination_total(st) < 50.0, "污染总量下降")
	check(int(a1["memory_gaps"]) > 0, "低剂量也产生记忆缺口")
	check(int(a1["uses"]) == 1, "记录使用次数")
	# 剂量依赖性：高剂量部分不可逆。
	var st2: Dictionary = sys.new_state()
	var a2: Dictionary = sys.amnestics(st2, 0.9)
	check(float(a2["irreversible"]) > 0.0, "高剂量造成部分不可逆损伤")
	# 使用上限。
	sys.amnestics(st, 1.0)
	sys.amnestics(st, 0.5)
	var over: Dictionary = sys.amnestics(st, 0.5)
	check(not bool(over["ok"]) and str(over["reason"]) == "limit_reached", "达到使用上限后拒绝")
	check(int(sys.amnestic_status(st)["uses"]) == 3, "使用次数封顶")
	check(float(sys.amnestic_status(st)["addiction"]) > 0.0, "滥用累积成瘾")


func _test_inheritance() -> void:
	var sys = AnomalyScript.new()
	# 普通路线：不被触发。
	var plain: Dictionary = sys.new_state()
	var plain_heir: Dictionary = sys.new_state()
	var r0: Dictionary = sys.inherit(plain, plain_heir)
	check(not bool(r0["bloodline"]), "普通路线无血脉传承")
	check(not sys.can_enter(plain_heir), "普通路线后代不可进入异常世界")
	check(sys.is_hidden(plain_heir), "普通后代仍隐藏")
	# 异常路线：天赋、血脉、知识、能力可继承。
	var giver: Dictionary = sys.new_state()
	sys.open_gate(giver, "rare_talent")
	giver["anomaly"]["talents"] = ["预知血脉"]
	giver["anomaly"]["knowledge"] = {"封印术": 1}
	sys.gain_exp(giver, "precognition", 1000.0)
	var heir: Dictionary = sys.new_state()
	var r1: Dictionary = sys.inherit(giver, heir)
	check(bool(r1["bloodline"]), "血脉可继承")
	check((heir["anomaly"]["talents"] as Array).has("预知血脉"), "天赋可继承")
	check((heir["anomaly"]["knowledge"] as Dictionary).has("封印术"), "知识可继承")
	check(sys.can_enter(heir), "传承者可持续进入异常世界")
	check_eq(sys.ability_level(heir, "precognition"), 5, "能力等级按比例继承")


func _test_clearance_and_catalog() -> void:
	var sys = AnomalyScript.new()
	var st: Dictionary = sys.new_state()
	var e: Dictionary = sys.entry("异-002")
	check(not e.is_empty(), "读取核心条目")
	check(not sys.is_known(st, "异-002"), "未接触时图鉴不可见")
	var low: Dictionary = sys.encounter(st, "异-002", {})
	check(not bool(low["ok"]) and str(low["reason"]) == "insufficient_clearance", "权限不足不可接触")
	check(not sys.is_known(st, "异-002"), "接触失败不写入图鉴")
	sys.set_clearance(st, 2)
	var ok: Dictionary = sys.encounter(st, "异-002", {})
	check(bool(ok["ok"]) and bool(ok["newly_known"]), "权限足够可接触并解锁图鉴")
	check(sys.is_known(st, "异-002"), "接触后图鉴可见")
	check((sys.known_entries(st) as Array).has("异-002"), "图鉴记录已接触条目")
	var again: Dictionary = sys.encounter(st, "异-002", {})
	check(not bool(again["newly_known"]), "重复接触不再新解锁")
	# D 级人员机制：低权限亦可接触。
	var d: Dictionary = sys.new_state()
	sys.set_d_class(d, true)
	check(bool(sys.encounter(d, "异-058", {})["ok"]), "D 级人员可接触")


func _test_abilities() -> void:
	var sys = AnomalyScript.new()
	var st: Dictionary = sys.new_state()
	var g: Dictionary = sys.gain_exp(st, "cultivation", 450.0)
	check_eq(int(g["level"]), 4, "经验提升修炼等级")
	check(float(sys.exposure(st)) > 0.0, "能力提升同步累积暴露值")
	# 修炼消耗灵力。
	var use: Dictionary = sys.use_ability(st, "cultivation", {})
	check(bool(use["ok"]), "使用修炼能力")
	check(float((st["anomaly"]["resources"] as Dictionary)["mana"]) < 100.0, "修炼消耗灵力")
	# 预知消耗精神与理智。
	var pre: Dictionary = sys.use_ability(st, "precognition", {})
	check(bool(pre["ok"]), "使用预知能力")
	var res: Dictionary = st["anomaly"]["resources"]
	check(float(res["spirit"]) < 100.0 and float(res["sanity"]) < 100.0, "预知消耗精神与理智")
	# 资源不足被拒。
	res["mana"] = 0.0
	check(not bool(sys.use_ability(st, "cultivation", {})["ok"]), "灵力不足拒绝使用")
	check(not bool(sys.use_ability(st, "bogus", {})["ok"]), "未知能力线被拒")


func _test_combat() -> void:
	var sys = AnomalyScript.new()
	var atk: Dictionary = sys.new_state()
	sys.gain_exp(atk, "sorcery", 1000.0)
	var dfn: Dictionary = sys.new_state()
	check(sys._combat_power(atk) > sys._combat_power(dfn), "高能力者战力更高")
	var r: Dictionary = sys.resolve_combat(atk, dfn, {"roll": 0.0})
	check(bool(r["attacker_wins"]), "低 roll 高能力者取胜")
	var r2: Dictionary = sys.resolve_combat(atk, dfn, {"roll": 0.999})
	check(bool(r2["defender_wins"]) or bool(r2["attacker_wins"]), "对抗必有胜负")
	# 收容失效。
	var breach: Dictionary = sys.trigger_containment_breach(dfn, {"exposure": 20.0})
	check(bool(breach["breach"]) and float(sys.exposure(dfn)) >= 20.0, "收容失效抬升暴露")


func _test_entry_generation_and_validation() -> void:
	var sys = AnomalyScript.new()
	var e1: Dictionary = sys.generate_entry(42)
	var e2: Dictionary = sys.generate_entry(42)
	check(e1 == e2, "生成条目受 seed 确定性")
	check(bool(sys.validate_entry(e1)["ok"]), "生成条目通过校验")
	check(sys.containment_levels().has(str(e1["containment"])), "生成条目的收容等级合法")
	check(sys.hazard_types().has(str(e1["hazard"])), "生成条目的危害类型合法")
	var bad: Dictionary = sys.validate_entry({})
	check(not bool(bad["ok"]) and (bad["errors"] as Array).size() > 0, "缺失字段校验失败")
	var invalid: Dictionary = sys.generate_entry(7)
	invalid["containment"] = "bogus"
	check(not bool(sys.validate_entry(invalid)["ok"]), "非法收容等级校验失败")


func _test_faction_missions() -> void:
	var sys = AnomalyScript.new()
	var st: Dictionary = sys.new_state()
	sys.join_faction(st, "foundation", {"reputation": 0.0})
	check_near(sys.faction_reputation(st, "foundation"), 0.0, 1e-9, "初始阵营声望")
	sys.accept_mission(st, "m1", "foundation", {"reward": 20.0})
	var done: Dictionary = sys.complete_mission(st, "m1", {"success": true})
	check(bool(done["ok"]), "完成任务")
	check(float(sys.faction_reputation(st, "foundation")) > 0.0, "完成提升隐藏阵营声望")
	check(not bool(sys.complete_mission(st, "m404", {})["ok"]), "未知任务被拒")


func _test_social_cross() -> void:
	var sys = AnomalyScript.new()
	var st: Dictionary = sys.new_state()
	var normal: Dictionary = sys.misjudged_as_crime(st, {"anomaly_caused": false})
	check(not bool(normal["anomaly_involved"]), "普通事件与异常无关")
	var crossed: Dictionary = sys.misjudged_as_crime(st, {"anomaly_caused": true})
	check(bool(crossed["anomaly_involved"]), "异常导致的事故被识别")
	check(bool(crossed["misjudged_as_crime"]), "标记可能被误判为犯罪")
	check(str(crossed["flag"]) == "anomaly_override", "返回异常覆盖标记")
