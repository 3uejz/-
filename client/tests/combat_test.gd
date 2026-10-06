extends "res://tests/test_base.gd"
## 冲突与战斗框架测试（任务 41.1；R96；design「冲突与战斗」）。
## 覆盖：招式四源合并与风格独立、行动点与资源消耗、命中/失手、
## 蓄力与连招、持续伤害与控制状态、士气崩溃逃跑、回合结算与胜负、
## 生命归零死亡接入（临终/传承钩子）、确定性、有限回合终止、
## 战斗守恒（生命与行动点只在结算中增减、伤害落在招式区间内）、序列化往返。

const CombatScript = preload("res://sim/combat.gd")


func _suite_name() -> String:
	return "combat"


func run_tests() -> void:
	_test_tables_and_sources()
	_test_combatant_and_encounter()
	_test_action_damage_and_ap()
	_test_hit_and_miss()
	_test_charge_and_combo()
	_test_control_status()
	_test_dot_tick()
	_test_morale_break_flee()
	_test_death_and_hook()
	_test_determinism()
	_test_finite_termination()
	_test_conservation()
	_test_serialization()


func _make_player(moves: Array = ["jab", "hook", "grapple", "windup", "finisher"]) -> Dictionary:
	return CombatScript.new().new_combatant({
		"id": "hero", "name": "勇者", "side": "player", "moves": moves,
	})


func _test_tables_and_sources() -> void:
	var sys = CombatScript.new()
	check_eq(sys.style_name("anomaly"), "异常对抗", "风格中文名")
	check_eq(sys.style_keys().size(), 5, "五种战斗风格")
	check(sys.move_keys("brawl").has("hook"), "斗殴有重摆拳")
	check(sys.move_keys("anomaly").has("spirit_bolt"), "异常对抗有灵击")
	check(not sys.move_keys("anomaly").has("hook"), "风格招式相互独立")
	check_eq(sys.status_type_name("dot"), "持续伤害", "状态类型中文名")
	# 招式四源合并：技能 / 职业 / 装备 / 内容包。
	var c: Dictionary = sys.new_combatant({"id": "x", "move_sources": {"skill": ["jab"], "profession": [], "equipment": ["hook"], "content": ["grapple"]}})
	var granted: Array = sys.granted_moves(c, "brawl")
	check(granted.has("jab") and granted.has("hook") and granted.has("grapple"), "四源招式合并")
	var pool: Array = sys.move_pool(c, "brawl")
	check(pool.has("jab") and pool.has("hook") and pool.has("grapple"), "招式池含四源招式")


func _test_combatant_and_encounter() -> void:
	var sys = CombatScript.new()
	var c: Dictionary = sys.new_combatant({})
	check_eq(int(c["max_hp"]), 100, "默认生命上限")
	check_eq(int(c["ap"]), 3, "默认行动点")
	check_eq(int(c["stamina"]), 50, "默认体力")
	check_eq((c["statuses"] as Array).size(), 0, "初始无状态")
	var enc: Dictionary = sys.new_encounter("brawl", _make_player(), [sys.new_combatant({"id": "foe", "name": "对手", "side": "enemy"})], {})
	check_eq(str(enc["style"]), "brawl", "遭遇风格")
	check_eq((enc["order"] as Array).size(), 2, "回合序列含双方")
	check_eq(str(enc["outcome"]), "ongoing", "初始未结束")


func _test_action_damage_and_ap() -> void:
	var sys = CombatScript.new()
	var foe: Dictionary = sys.new_combatant({"id": "foe", "name": "对手", "side": "enemy"})
	var enc: Dictionary = sys.new_encounter("brawl", _make_player(["jab"]), [foe], {})
	var ap0: int = int(enc["actors"]["hero"]["ap"])
	var hp0: int = int(foe["hp"])
	var res: Dictionary = sys.player_action(enc, "jab", {"roll": 0.0, "roll_dmg": 1.0})
	check(bool(res["ok"]), "刺拳执行成功")
	check(bool(res["hit"]), "低掷骰命中")
	var dealt: int = int(res["damage"])
	check(dealt >= 6 and dealt <= 10, "伤害落在招式区间内")
	check_eq(int(foe["hp"]), hp0 - dealt, "生命按伤害减扣")
	check_eq(int(enc["actors"]["hero"]["ap"]), ap0 - 1, "消耗行动点")
	check_eq(int(enc["actors"]["hero"]["stamina"]), 46, "消耗体力")
	check((enc["log"] as Array).size() > 0, "写入战斗日志")


func _test_hit_and_miss() -> void:
	var sys = CombatScript.new()
	var foe: Dictionary = sys.new_combatant({"id": "foe", "name": "对手", "side": "enemy"})
	var enc: Dictionary = sys.new_encounter("brawl", _make_player(["jab"]), [foe], {})
	var res: Dictionary = sys.player_action(enc, "jab", {"roll": 0.99, "roll_dmg": 1.0})
	check(bool(res["ok"]), "刺拳执行")
	check(not bool(res["hit"]), "高掷骰失手")
	check_eq(int(foe["hp"]), 100, "失手不减生命")
	check_eq(int(enc["actors"]["hero"]["combo"]), 0, "失手重置连招")


func _test_charge_and_combo() -> void:
	var sys = CombatScript.new()
	var foe: Dictionary = sys.new_combatant({"id": "foe", "name": "对手", "side": "enemy"})
	var hero: Dictionary = sys.new_combatant({"id": "hero", "name": "勇者", "side": "player", "max_ap": 4, "moves": ["windup", "finisher", "jab"]})
	var enc: Dictionary = sys.new_encounter("brawl", hero, [foe], {})
	var avail0: Array = sys.available_moves(enc, "hero")
	check(not avail0.has("finisher"), "未蓄力不可用终结技")
	sys.player_action(enc, "windup", {"roll": 0.0})
	sys.player_action(enc, "windup", {"roll": 0.0})
	check_eq(int(enc["actors"]["hero"]["charge"]), 2, "蓄力叠两层")
	var avail1: Array = sys.available_moves(enc, "hero")
	check(avail1.has("finisher"), "蓄力两层可用终结技")
	var res: Dictionary = sys.player_action(enc, "finisher", {"roll": 0.0, "roll_dmg": 1.0})
	check(bool(res["hit"]), "终结技命中")
	check(int(res["damage"]) >= 20 and int(res["damage"]) <= 30, "终结技伤害区间")
	check_eq(int(enc["actors"]["hero"]["charge"]), 0, "终结技消耗蓄力")
	check_eq(int(enc["actors"]["hero"]["combo"]), 1, "命中累积连招")


func _test_control_status() -> void:
	var sys = CombatScript.new()
	var foe: Dictionary = sys.new_combatant({"id": "foe", "name": "对手", "side": "enemy", "moves": ["jab"]})
	var enc: Dictionary = sys.new_encounter("brawl", _make_player(["grapple"]), [foe], {})
	sys.player_action(enc, "grapple", {"roll": 0.0, "roll_dmg": 1.0})
	var has_control: bool = false
	for s in (foe["statuses"] as Array):
		if str((s as Dictionary).get("type", "")) == "control":
			has_control = true
	check(has_control, "擒拿施加控制状态")
	var hp_before: int = int(enc["actors"]["hero"]["hp"])
	sys.enemy_turn(enc, {"roll": 0.0, "roll_dmg": 1.0})
	check_eq(int(enc["actors"]["hero"]["hp"]), hp_before, "受控敌人本回合无法行动")


func _test_dot_tick() -> void:
	var sys = CombatScript.new()
	var foe: Dictionary = sys.new_combatant({"id": "foe", "name": "对手", "side": "enemy"})
	var enc: Dictionary = sys.new_encounter("brawl", _make_player(["hook"]), [foe], {})
	sys.player_action(enc, "hook", {"roll": 0.0, "roll_dmg": 0.0})
	var hp_after_hit: int = int(foe["hp"])
	var has_dot: bool = false
	for s in (foe["statuses"] as Array):
		if str((s as Dictionary).get("type", "")) == "dot":
			has_dot = true
	check(has_dot, "重摆拳施加持续伤害")
	sys.tick_statuses(enc)
	check_eq(int(foe["hp"]), hp_after_hit - 3, "持续伤害每回合结算")
	sys.tick_statuses(enc)
	sys.tick_statuses(enc)
	check_eq((foe["statuses"] as Array).size(), 0, "持续伤害到期末被移除")


func _test_morale_break_flee() -> void:
	var sys = CombatScript.new()
	var foe: Dictionary = sys.new_combatant({"id": "foe", "name": "对手", "side": "enemy", "max_hp": 100, "hp": 10})
	var enc: Dictionary = sys.new_encounter("war", _make_player([]), [foe], {})
	(foe["statuses"] as Array).append({"id": "fear", "type": "morale", "duration": 5, "magnitude": 0.8})
	var outcome: String = sys.check_outcome(enc)
	check(bool(foe["fled"]), "低血高恐惧士气崩溃逃跑")
	check_eq(outcome, "player_win", "敌方逃跑判负")
	check(sys._morale_factor(foe) < 1.0, "恐惧压低士气系数")


func _test_death_and_hook() -> void:
	var sys = CombatScript.new()
	# 敌方被击杀。
	var foe: Dictionary = sys.new_combatant({"id": "foe", "name": "对手", "side": "enemy", "max_hp": 5, "hp": 5})
	var enc: Dictionary = sys.new_encounter("brawl", _make_player(["jab"]), [foe], {})
	sys.player_action(enc, "jab", {"roll": 0.0, "roll_dmg": 1.0})
	var outcome: String = sys.check_outcome(enc)
	check_eq(outcome, "player_win", "击杀敌方判胜")
	check(bool(foe["downed"]), "敌方标记倒下")
	check_eq((enc["deaths"] as Array).size(), 1, "记录死亡")
	var hook: Dictionary = sys.resolve_death(enc, "foe", {"killer": "hero"})
	check(bool(hook["death"]), "死亡接入返回死亡标记")
	check_eq(str(hook["hook"]), "last_rites_inheritance", "接入临终与传承钩子")
	# 玩家阵亡。
	var hero: Dictionary = sys.new_combatant({"id": "hero", "name": "勇者", "side": "player", "max_hp": 100, "hp": 3, "moves": []})
	var brute: Dictionary = sys.new_combatant({"id": "brute", "name": "强敌", "side": "enemy", "max_hp": 200, "hp": 200, "moves": ["charge_line"], "move_sources": {"skill": [], "profession": [], "equipment": [], "content": []}})
	var enc2: Dictionary = sys.new_encounter("war", hero, [brute], {})
	sys.enemy_turn(enc2, {"roll": 0.0, "roll_dmg": 1.0})
	var outcome2: String = sys.check_outcome(enc2)
	check_eq(outcome2, "enemy_win", "玩家生命归零判负")
	check_eq(int(hero["hp"]), 0, "玩家生命钳制为 0")
	var phook: Dictionary = sys.resolve_death(enc2, "hero", {"trigger": "combat"})
	check(bool(phook["death"]), "玩家死亡接入")


func _test_determinism() -> void:
	var sys = CombatScript.new()
	var enc_a: Dictionary = sys.new_encounter("brawl", _make_player(["jab"]), [sys.new_combatant({"id": "foe", "side": "enemy"})], {})
	var enc_b: Dictionary = sys.new_encounter("brawl", _make_player(["jab"]), [sys.new_combatant({"id": "foe", "side": "enemy"})], {})
	sys.run_round(enc_a, "jab", {"roll": 0.3, "roll_dmg": 0.4})
	sys.run_round(enc_b, "jab", {"roll": 0.3, "roll_dmg": 0.4})
	check_eq(int(enc_a["actors"]["foe"]["hp"]), int(enc_b["actors"]["foe"]["hp"]), "相同掷骰结果一致")
	check_eq(str(enc_a["outcome"]), str(enc_b["outcome"]), "相同掷骰胜负一致")


func _test_finite_termination() -> void:
	var sys = CombatScript.new()
	var foe: Dictionary = sys.new_combatant({"id": "foe", "side": "enemy", "moves": ["jab"]})
	var enc: Dictionary = sys.new_encounter("arena", _make_player(["jab"]), [foe], {"max_rounds": 3})
	var guard: int = 0
	while str(enc["outcome"]) == "ongoing" and guard < 20:
		guard += 1
		sys.run_round(enc, "jab", {"roll": 0.5, "roll_dmg": 0.5})
	check(str(enc["outcome"]) != "ongoing", "有限回合内终止")
	check(int(enc["round"]) <= 3, "不超过回合上限")
	check(bool(enc["outcome"] in ["player_win", "enemy_win", "draw"]), "终局为有效胜负")


func _test_conservation() -> void:
	var sys = CombatScript.new()
	var foep: Dictionary = sys.new_combatant({"id": "foe", "side": "enemy"})
	var enc: Dictionary = sys.new_encounter("brawl", _make_player(["jab", "hook"]), [foep], {})
	for i in range(4):
		var before: int = int(foep["hp"])
		var res: Dictionary = sys.player_action(enc, "jab", {"roll": 0.0, "roll_dmg": 0.5})
		if bool(res.get("hit", false)):
			check_eq(int(res["damage"]), before - int(foep["hp"]), "伤害等于生命减量")
		check(int(enc["actors"]["hero"]["ap"]) >= 0, "行动点非负")
		check(int(foep["hp"]) >= 0 and int(foep["hp"]) <= int(foep["max_hp"]), "生命有界")
		# 补回行动点继续。
		enc["actors"]["hero"]["ap"] = 3
	# 伤害始终落在招式区间内。
	var hero: Dictionary = enc["actors"]["hero"]
	for r in [0.0, 0.25, 0.5, 0.75, 1.0]:
		var d: int = sys.effective_damage(hero, sys.move_def("brawl", "hook"), r)
		check(d >= 14 and d <= 22, "重摆拳伤害始终在区间内")


func _test_serialization() -> void:
	var sys = CombatScript.new()
	var enc: Dictionary = sys.new_encounter("brawl", _make_player(["jab"]), [sys.new_combatant({"id": "foe", "side": "enemy"})], {})
	sys.player_action(enc, "jab", {"roll": 0.0, "roll_dmg": 0.5})
	var clone: Dictionary = sys.from_dict(sys.to_dict(enc))
	check_eq(str(clone["style"]), "brawl", "序列化风格往返")
	check_eq((clone["order"] as Array).size(), 2, "序列化回合序列往返")
	check_eq(int(clone["actors"]["foe"]["hp"]), int(enc["actors"]["foe"]["hp"]), "序列化生命往返")
