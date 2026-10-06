class_name CombatSystem
extends RefCounted
## 冲突与战斗统一框架（R96；design「冲突与战斗」）。
##
## 覆盖：
##   - 统一接口：回合序列、行动点、生命与状态容器、敌方 AI、结算钩子与战斗日志；
##   - 领域规则：街头斗殴 / 犯罪对抗 / 异常对抗 / 战争战斗 / 竞技对抗，各自独立招式表、
##     属性权重与胜负条件；异常对抗额外纳入灵力与精神；
##   - 招式来源：技能等级、职业身份、装备与法器、内容包定义四源合并为可用招式池；
##   - 节奏资源：蓄力（跨回合积累）与连招（条件衔接）；普通战斗消耗体力，异常战斗消耗灵力与精神；
##   - 状态效果：持续伤害、控制、士气心理、部位受伤四类，统一 tick、叠加上限与驱散；
##   - 回合流程：玩家手动选择行动 → 结算 → 敌方 AI → 状态 tick → 判定胜负；
##   - 死亡接入：生命归零产生结算钩子，交给临终与传承流程。
##
## 设计取舍：
##   - 遭遇、战斗者、状态均为纯数据 Dictionary，便于存读档与 headless 测试；
##   - 命中与伤害统一走 _roll(forced, rng)，缺省确定化；伤害 clamp 在招式定义区间内
##     （对应 Correctness Property 16），行动点与生命只在结算中按定义增减（Property 15）；
##   - 与既有系统解耦：死亡 / 收容 / 军旅 / 比赛结果以结构化返回值交给上层编排。

## 战斗风格：名称、主资源、胜负条件、属性权重与默认技能。
const STYLES: Dictionary = {
	"brawl": {
		"name": "街头斗殴", "resource": "stamina", "win": "ko", "max_rounds": 20,
		"weights": {"strength": 0.5, "agility": 0.3, "will": 0.2}, "skill": "brawl",
	},
	"crime": {
		"name": "犯罪对抗", "resource": "stamina", "win": "ko", "max_rounds": 20,
		"weights": {"agility": 0.4, "strength": 0.3, "will": 0.3}, "skill": "combat",
	},
	"anomaly": {
		"name": "异常对抗", "resource": "spirit", "win": "seal", "max_rounds": 25,
		"weights": {"cognition": 0.4, "will": 0.4, "spirit": 0.2}, "skill": "anomaly",
	},
	"war": {
		"name": "战争战斗", "resource": "stamina", "win": "morale", "max_rounds": 30,
		"weights": {"strength": 0.3, "will": 0.4, "agility": 0.3}, "skill": "combat",
	},
	"arena": {
		"name": "竞技对抗", "resource": "stamina", "win": "judgment", "max_rounds": 12,
		"weights": {"strength": 0.35, "agility": 0.35, "will": 0.3}, "skill": "combat",
	},
}

## 各风格的独立招式表。招式字段：
##   cost{ap,stamina,spirit,sanity}、target、power、damage[min,max]、attr、skill、
##   status、charge_gain、requires_charge/consumes_charge、requires_combo、cooldown、heal。
const MOVES: Dictionary = {
	"brawl": {
		"jab": {"name": "刺拳", "cost": {"ap": 1, "stamina": 4}, "target": "enemy", "power": 0.9, "damage": [6, 10], "attr": "strength", "skill": "brawl"},
		"hook": {"name": "重摆拳", "cost": {"ap": 2, "stamina": 12}, "target": "enemy", "power": 1.4, "damage": [14, 22], "attr": "strength", "skill": "brawl", "cooldown": 1, "status": {"id": "bleed", "type": "dot", "duration": 3, "magnitude": 3}},
		"grapple": {"name": "擒拿", "cost": {"ap": 1, "stamina": 8}, "target": "enemy", "power": 0.6, "damage": [2, 5], "attr": "strength", "skill": "brawl", "status": {"id": "stun", "type": "control", "duration": 1, "magnitude": 1.0}},
		"windup": {"name": "蓄力", "cost": {"ap": 1, "stamina": 3}, "target": "self", "power": 0.0, "charge_gain": 1},
		"finisher": {"name": "终结技", "cost": {"ap": 2, "stamina": 16}, "target": "enemy", "power": 1.9, "damage": [20, 30], "attr": "strength", "skill": "brawl", "requires_charge": 2, "consumes_charge": true, "cooldown": 2},
	},
	"crime": {
		"shove": {"name": "推搡", "cost": {"ap": 1, "stamina": 4}, "target": "enemy", "power": 0.9, "damage": [5, 9], "attr": "agility", "skill": "combat"},
		"sneak_strike": {"name": "偷袭", "cost": {"ap": 2, "stamina": 10}, "target": "enemy", "power": 1.5, "damage": [12, 20], "attr": "agility", "skill": "combat", "cooldown": 1},
		"disarm": {"name": "夺械", "cost": {"ap": 1, "stamina": 8}, "target": "enemy", "power": 0.5, "damage": [2, 4], "attr": "agility", "skill": "combat", "status": {"id": "disarm", "type": "control", "duration": 2, "magnitude": 0.8}},
		"tackle": {"name": "扑倒", "cost": {"ap": 1, "stamina": 9}, "target": "enemy", "power": 1.0, "damage": [6, 12], "attr": "strength", "skill": "combat", "status": {"id": "stun", "type": "control", "duration": 1, "magnitude": 1.0}},
		"escape": {"name": "脱身", "cost": {"ap": 1, "stamina": 5}, "target": "self", "power": 0.0, "status": {"id": "evasion", "type": "evasion", "duration": 1, "magnitude": 0.3}},
	},
	"anomaly": {
		"spirit_bolt": {"name": "灵击", "cost": {"ap": 1, "spirit": 8}, "target": "enemy", "power": 1.2, "damage": [10, 18], "attr": "cognition", "skill": "anomaly"},
		"seal_ritual": {"name": "封印术", "cost": {"ap": 2, "spirit": 18}, "target": "enemy", "power": 1.6, "damage": [16, 26], "attr": "will", "skill": "anomaly", "cooldown": 2},
		"ward": {"name": "结界", "cost": {"ap": 1, "spirit": 6}, "target": "self", "power": 0.0, "status": {"id": "ward", "type": "evasion", "duration": 2, "magnitude": 0.35}},
		"mind_break": {"name": "精神冲击", "cost": {"ap": 1, "spirit": 10, "sanity": 5}, "target": "enemy", "power": 0.8, "damage": [4, 10], "attr": "will", "skill": "anomaly", "status": {"id": "fear", "type": "morale", "duration": 2, "magnitude": 0.6}},
		"banish": {"name": "放逐", "cost": {"ap": 2, "spirit": 22}, "target": "enemy", "power": 1.8, "damage": [20, 32], "attr": "cognition", "skill": "anomaly", "requires_charge": 2, "consumes_charge": true, "cooldown": 3},
	},
	"war": {
		"volley": {"name": "齐射", "cost": {"ap": 1, "stamina": 10}, "target": "enemy", "power": 1.1, "damage": [8, 16], "attr": "will", "skill": "combat"},
		"charge_line": {"name": "冲锋", "cost": {"ap": 2, "stamina": 16}, "target": "enemy", "power": 1.5, "damage": [14, 24], "attr": "strength", "skill": "combat", "cooldown": 2},
		"hold_position": {"name": "坚守", "cost": {"ap": 1, "stamina": 6}, "target": "self", "power": 0.0, "charge_gain": 1, "status": {"id": "guard", "type": "evasion", "duration": 1, "magnitude": 0.25}},
		"flank": {"name": "侧翼包抄", "cost": {"ap": 2, "stamina": 14}, "target": "enemy", "power": 1.3, "damage": [10, 20], "attr": "agility", "skill": "combat", "status": {"id": "wound_arm", "type": "wound", "duration": 3, "magnitude": 0.3, "part": "arm"}},
		"rally": {"name": "整队", "cost": {"ap": 1, "stamina": 5}, "target": "self", "power": 0.0, "heal": 10, "status": {"id": "morale_boost", "type": "morale_boost", "duration": 2, "magnitude": 0.4}},
	},
	"arena": {
		"jab": {"name": "刺拳", "cost": {"ap": 1, "stamina": 4}, "target": "enemy", "power": 0.9, "damage": [6, 10], "attr": "agility", "skill": "combat"},
		"combo_strike": {"name": "连打", "cost": {"ap": 1, "stamina": 8}, "target": "enemy", "power": 1.1, "damage": [8, 14], "attr": "agility", "skill": "combat", "requires_combo": 1},
		"heavy_blow": {"name": "重击", "cost": {"ap": 2, "stamina": 14}, "target": "enemy", "power": 1.5, "damage": [14, 22], "attr": "strength", "skill": "combat", "cooldown": 1},
		"feint": {"name": "虚招", "cost": {"ap": 1, "stamina": 6}, "target": "self", "power": 0.0, "charge_gain": 1, "status": {"id": "evasion", "type": "evasion", "duration": 1, "magnitude": 0.3}},
		"clinch": {"name": "缠抱", "cost": {"ap": 1, "stamina": 9}, "target": "enemy", "power": 0.7, "damage": [4, 8], "attr": "strength", "skill": "combat", "status": {"id": "stun", "type": "control", "duration": 1, "magnitude": 1.0}},
	},
}

## 状态类型说明（用于 UI 与测试断言）。
const STATUS_TYPES: Dictionary = {
	"dot": "持续伤害", "control": "控制", "morale": "士气心理", "wound": "部位受伤",
	"evasion": "闪避", "morale_boost": "士气增益",
}

var _seq: int = 0


func _roll(forced: float, rng) -> float:
	if forced >= 0.0:
		return clampf(forced, 0.0, 1.0)
	if rng != null:
		return rng.next_float()
	return 0.0


# --- 数据表 ---

func style_keys() -> Array:
	return STYLES.keys()


func style_def(style: String) -> Dictionary:
	if not STYLES.has(style):
		return {}
	return (STYLES[style] as Dictionary).duplicate(true)


func style_name(style: String) -> String:
	return str((STYLES.get(style, {}) as Dictionary).get("name", style))


func move_keys(style: String) -> Array:
	return (MOVES.get(style, {}) as Dictionary).keys()


func move_def(style: String, move_id: String) -> Dictionary:
	var table: Dictionary = MOVES.get(style, {})
	if not table.has(move_id):
		return {}
	var d: Dictionary = (table[move_id] as Dictionary).duplicate(true)
	d["id"] = move_id
	return d


func move_name(style: String, move_id: String) -> String:
	var table: Dictionary = MOVES.get(style, {})
	return str((table.get(move_id, {}) as Dictionary).get("name", move_id))


func status_type_name(t: String) -> String:
	return str(STATUS_TYPES.get(t, t))


# --- 战斗者 ---

## 新建战斗者。attrs 属性 0..1；skills 技能 0..1；move_sources 为招式四源。
func new_combatant(opts: Dictionary = {}) -> Dictionary:
	_seq += 1
	var max_hp: int = maxi(1, int(opts.get("max_hp", 100)))
	var max_ap: int = maxi(1, int(opts.get("max_ap", 3)))
	return {
		"id": str(opts.get("id", "actor.%d" % _seq)),
		"name": str(opts.get("name", "战斗者")),
		"side": str(opts.get("side", "enemy")),
		"hp": maxi(0, int(opts.get("hp", max_hp))),
		"max_hp": max_hp,
		"ap": max_ap,
		"max_ap": max_ap,
		"stamina": maxi(0, int(opts.get("stamina", 50))),
		"max_stamina": maxi(1, int(opts.get("max_stamina", 50))),
		"spirit": maxi(0, int(opts.get("spirit", 50))),
		"max_spirit": maxi(1, int(opts.get("max_spirit", 50))),
		"sanity": maxi(0, int(opts.get("sanity", 80))),
		"max_sanity": maxi(1, int(opts.get("max_sanity", 80))),
		"attrs": (opts.get("attrs", {"strength": 0.5, "agility": 0.5, "will": 0.5, "cognition": 0.5, "spirit": 0.5}) as Dictionary).duplicate(true),
		"skills": (opts.get("skills", {}) as Dictionary).duplicate(true),
		"moves": (opts.get("moves", []) as Array).duplicate(),
		"move_sources": (opts.get("move_sources", {"skill": [], "profession": [], "equipment": [], "content": []}) as Dictionary).duplicate(true),
		"ai": (opts.get("ai", {"policy": "balanced"}) as Dictionary).duplicate(true),
		"statuses": [],
		"wounds": {},
		"cooldowns": {},
		"charge": 0,
		"combo": 0,
		"downed": false,
		"fled": false,
	}


## 四源合并：技能等级、职业身份、装备与法器、内容包定义。
func granted_moves(combatant: Dictionary, style: String) -> Array:
	var src: Dictionary = combatant.get("move_sources", {})
	var table: Dictionary = MOVES.get(style, {})
	var out: Array = []
	for key in ["skill", "profession", "equipment", "content"]:
		for mid in (src.get(key, []) as Array):
			var s: String = str(mid)
			if table.has(s) and not out.has(s):
				out.append(s)
	return out


## 可用招式池：显式招式 ∪ 四源招式（仅保留该风格存在的招式）。
func move_pool(combatant: Dictionary, style: String) -> Array:
	var table: Dictionary = MOVES.get(style, {})
	var out: Array = []
	for mid in (combatant.get("moves", []) as Array):
		var s: String = str(mid)
		if table.has(s) and not out.has(s):
			out.append(s)
	for mid in granted_moves(combatant, style):
		if not out.has(mid):
			out.append(mid)
	return out


# --- 遭遇 ---

## 新建遭遇：player 为玩家战斗者，enemies 为敌方数组。
func new_encounter(style: String, player: Dictionary, enemies: Array, opts: Dictionary = {}) -> Dictionary:
	var actual_style: String = style if STYLES.has(style) else "brawl"
	var order: Array = [player["id"]]
	var actors: Dictionary = {str(player["id"]): player}
	for e in enemies:
		var ed: Dictionary = e
		order.append(ed["id"])
		actors[str(ed["id"])] = ed
	return {
		"id": str(opts.get("id", "encounter.%d" % _seq)),
		"style": actual_style,
		"player_id": str(player["id"]),
		"order": order,
		"actors": actors,
		"round": 0,
		"max_rounds": maxi(1, int(opts.get("max_rounds", (STYLES[actual_style] as Dictionary)["max_rounds"]))),
		"outcome": "ongoing",
		"log": [],
		"damage": {},
		"deaths": [],
	}


func _actor(encounter: Dictionary, actor_id: String) -> Dictionary:
	return encounter["actors"][actor_id]


func _side_of(encounter: Dictionary, actor_id: String) -> String:
	return str((_actor(encounter, actor_id) as Dictionary).get("side", "enemy"))


func _count_alive(encounter: Dictionary, side: String) -> int:
	var n: int = 0
	for id in encounter["order"]:
		var a: Dictionary = _actor(encounter, id)
		if str(a["side"]) == side and int(a["hp"]) > 0 and not bool(a["fled"]):
			n += 1
	return n


# --- 可用招式 ---

func available_moves(encounter: Dictionary, actor_id: String) -> Array:
	var style: String = encounter["style"]
	var actor: Dictionary = _actor(encounter, actor_id)
	var out: Array = []
	for mid in move_pool(actor, style):
		var m: Dictionary = (MOVES[style] as Dictionary)[mid]
		if _can_use(actor, m):
			out.append(mid)
	return out


func _can_use(actor: Dictionary, m: Dictionary) -> bool:
	var cost: Dictionary = m.get("cost", {})
	if int(actor["ap"]) < int(cost.get("ap", 0)):
		return false
	if int(actor["stamina"]) < int(cost.get("stamina", 0)):
		return false
	if int(actor["spirit"]) < int(cost.get("spirit", 0)):
		return false
	if int(actor["sanity"]) < int(cost.get("sanity", 0)):
		return false
	if int(actor["cooldowns"].get(str(m.get("id", "")), 0)) > 0:
		return false
	if int(m.get("requires_charge", 0)) > int(actor["charge"]):
		return false
	if int(m.get("requires_combo", 0)) > int(actor["combo"]):
		return false
	return true


func _pay_cost(actor: Dictionary, cost: Dictionary) -> void:
	actor["ap"] = maxi(0, int(actor["ap"]) - int(cost.get("ap", 0)))
	actor["stamina"] = maxi(0, int(actor["stamina"]) - int(cost.get("stamina", 0)))
	actor["spirit"] = maxi(0, int(actor["spirit"]) - int(cost.get("spirit", 0)))
	actor["sanity"] = maxi(0, int(actor["sanity"]) - int(cost.get("sanity", 0)))


# --- 属性与修正 ---

func _attr(actor: Dictionary, key: String) -> float:
	return clampf(float((actor.get("attrs", {}) as Dictionary).get(key, 0.5)), 0.0, 1.0)


func _skill(actor: Dictionary, key: String) -> float:
	return clampf(float((actor.get("skills", {}) as Dictionary).get(key, 0.0)), 0.0, 1.0)


func _morale_factor(actor: Dictionary) -> float:
	var f: float = 1.0
	for s in (actor.get("statuses", []) as Array):
		var sd: Dictionary = s
		var st: String = str(sd.get("type", ""))
		if st == "morale":
			f -= float(sd.get("magnitude", 0.0)) * 0.3
		elif st == "morale_boost":
			f += float(sd.get("magnitude", 0.0)) * 0.2
	var hp_ratio: float = float(actor["hp"]) / maxf(1.0, float(actor["max_hp"]))
	if hp_ratio < 0.3:
		f *= 0.85
	return clampf(f, 0.4, 1.3)


func _wound_factor(actor: Dictionary) -> float:
	var total: float = 0.0
	for part in (actor.get("wounds", {}) as Dictionary).keys():
		total += float((actor["wounds"] as Dictionary)[part])
	return clampf(1.0 - total * 0.3, 0.4, 1.0)


func _evasion_of(actor: Dictionary) -> float:
	for s in (actor.get("statuses", []) as Array):
		if str((s as Dictionary).get("type", "")) == "evasion":
			return clampf(float((s as Dictionary).get("magnitude", 0.0)), 0.0, 0.9)
	return 0.0


func _morale_break(actor: Dictionary) -> bool:
	var hp_ratio: float = float(actor["hp"]) / maxf(1.0, float(actor["max_hp"]))
	var fear: float = 0.0
	for s in (actor.get("statuses", []) as Array):
		if str((s as Dictionary).get("type", "")) == "morale":
			fear += float((s as Dictionary).get("magnitude", 0.0))
	return hp_ratio <= 0.25 and fear >= 0.8


func _has_control(actor: Dictionary) -> bool:
	for s in (actor.get("statuses", []) as Array):
		if str((s as Dictionary).get("type", "")) == "control" and int((s as Dictionary).get("duration", 0)) > 0:
			return true
	return false


# --- 命中与伤害 ---

func hit_chance(actor: Dictionary, target: Dictionary, m: Dictionary) -> float:
	var acc: float = 0.75
	acc += _attr(actor, str(m.get("attr", "strength"))) * 0.2
	acc += _skill(actor, str(m.get("skill", ""))) * 0.1
	acc += clampf(float(actor["combo"]) * 0.05, 0.0, 0.15)
	acc -= _evasion_of(target)
	acc -= _attr(target, "agility") * 0.15
	return clampf(acc, 0.05, 0.98)


func _power_factor(actor: Dictionary, m: Dictionary) -> float:
	var f: float = 0.7
	f += 0.3 * _skill(actor, str(m.get("skill", "")))
	f += 0.3 * _attr(actor, str(m.get("attr", "strength")))
	f *= _morale_factor(actor)
	f *= _wound_factor(actor)
	if bool(m.get("consumes_charge", false)) and int(actor["charge"]) > 0:
		f *= 1.0 + float(actor["charge"]) * 0.15
	if int(actor["combo"]) > 0:
		f *= 1.0 + float(mini(3, int(actor["combo"]))) * 0.08
	return f


## 伤害：基础落在 [min,max]，乘以修正后 clamp 回区间（Property 16）。
func effective_damage(actor: Dictionary, m: Dictionary, forced_roll: float = -1.0, rng = null) -> int:
	if not m.has("damage"):
		return 0
	var dmg: Array = m["damage"]
	var lo: int = int(dmg[0])
	var hi: int = int(dmg[1])
	var roll: float = _roll(forced_roll, rng)
	var raw: float = float(lo) + (float(hi) - float(lo)) * roll
	var d: int = int(round(raw * _power_factor(actor, m)))
	return clampi(d, lo, hi)


# --- 行动 ---

func player_action(encounter: Dictionary, move_id: String, opts: Dictionary = {}, rng = null) -> Dictionary:
	return _act(encounter, str(encounter["player_id"]), move_id, opts, rng)


func _pick_target_id(encounter: Dictionary, actor: Dictionary, m: Dictionary, opts: Dictionary) -> String:
	if opts.has("target_id"):
		return str(opts["target_id"])
	var want_side: String = "enemy" if str(actor["side"]) == "player" else "player"
	for id in encounter["order"]:
		var a: Dictionary = _actor(encounter, id)
		if str(a["side"]) == want_side and int(a["hp"]) > 0 and not bool(a["fled"]):
			return str(id)
	return ""


func _act(encounter: Dictionary, actor_id: String, move_id: String, opts: Dictionary, rng) -> Dictionary:
	if str(encounter["outcome"]) != "ongoing":
		return {"ok": false, "reason": "finished"}
	if not (encounter["actors"] as Dictionary).has(actor_id):
		return {"ok": false, "reason": "unknown_actor"}
	var actor: Dictionary = _actor(encounter, actor_id)
	if int(actor["hp"]) <= 0 or bool(actor["fled"]):
		return {"ok": false, "reason": "incapacitated"}
	if _has_control(actor):
		return {"ok": false, "reason": "controlled"}
	var style: String = encounter["style"]
	if not (MOVES.get(style, {}) as Dictionary).has(move_id):
		return {"ok": false, "reason": "unknown_move"}
	var m: Dictionary = (MOVES[style] as Dictionary)[move_id]
	m = m.duplicate(true)
	m["id"] = move_id
	if not _can_use(actor, m):
		return {"ok": false, "reason": "cannot_use"}
	_pay_cost(actor, m.get("cost", {}))
	var result: Dictionary = {"ok": true, "actor": actor_id, "move": move_id, "name": str(m.get("name", move_id))}
	# 自身招式：蓄力 / 状态 / 治疗。
	if str(m.get("target", "enemy")) == "self":
		_apply_self(encounter, actor, m)
		result["target"] = actor_id
		return result
	var target_id: String = _pick_target_id(encounter, actor, m, opts)
	if target_id == "":
		return {"ok": true, "actor": actor_id, "move": move_id, "name": str(m.get("name", move_id)), "hit": false, "reason": "no_target"}
	var target: Dictionary = _actor(encounter, target_id)
	var hit_roll: float = _roll(float(opts.get("roll", -1.0)), rng)
	var chance: float = hit_chance(actor, target, m)
	var hit: bool = hit_roll < chance
	result["target"] = target_id
	result["hit"] = hit
	result["hit_chance"] = chance
	if not hit:
		actor["combo"] = 0
		_add_log(encounter, "%s 的「%s」落空。" % [actor["name"], str(m.get("name", move_id))])
		return result
	# 命中：伤害 + 状态 + 节奏资源。
	var dmg: int = effective_damage(actor, m, float(opts.get("roll_dmg", -1.0)), rng)
	var dealt: int = _apply_damage(encounter, target, dmg, actor_id)
	result["damage"] = dealt
	if m.has("status"):
		_apply_status(target, m["status"] as Dictionary)
	if int(m.get("charge_gain", 0)) > 0:
		actor["charge"] = mini(5, int(actor["charge"]) + int(m["charge_gain"]))
	if bool(m.get("consumes_charge", false)):
		actor["charge"] = 0
	actor["combo"] = mini(5, int(actor["combo"]) + 1)
	if int(m.get("cooldown", 0)) > 0:
		(actor["cooldowns"] as Dictionary)[move_id] = int(m["cooldown"])
	_add_log(encounter, "%s 的「%s」命中，造成 %d 点伤害。" % [actor["name"], str(m.get("name", move_id)), dealt])
	return result


func _apply_self(encounter: Dictionary, actor: Dictionary, m: Dictionary) -> void:
	if int(m.get("charge_gain", 0)) > 0:
		actor["charge"] = mini(5, int(actor["charge"]) + int(m["charge_gain"]))
	if int(m.get("heal", 0)) > 0:
		actor["hp"] = mini(int(actor["max_hp"]), int(actor["hp"]) + int(m["heal"]))
	if m.has("status"):
		_apply_status(actor, m["status"] as Dictionary)
	_add_log(encounter, "%s 施展「%s」。" % [actor["name"], str(m.get("name", ""))])


func _apply_damage(encounter: Dictionary, target: Dictionary, amount: int, source_id: String) -> int:
	var before: int = int(target["hp"])
	target["hp"] = maxi(0, before - maxi(0, amount))
	var dealt: int = before - int(target["hp"])
	(encounter["damage"] as Dictionary)[source_id] = int((encounter["damage"] as Dictionary).get(source_id, 0)) + dealt
	if int(target["hp"]) == 0 and not bool(target["downed"]):
		target["downed"] = true
		(encounter["deaths"] as Array).append({
			"actor": str(target["id"]), "name": str(target["name"]),
			"side": str(target["side"]), "killer": source_id, "round": int(encounter["round"]),
		})
		_add_log(encounter, "%s 生命归零，倒下。" % str(target["name"]))
	return dealt


func _apply_status(target: Dictionary, status: Dictionary) -> void:
	var list: Array = target["statuses"]
	for s in list:
		var sd: Dictionary = s
		if str(sd.get("id", "")) == str(status.get("id", "")) and str(sd.get("type", "")) == str(status.get("type", "")):
			sd["duration"] = maxi(int(sd.get("duration", 0)), int(status.get("duration", 0)))
			sd["magnitude"] = maxf(float(sd.get("magnitude", 0.0)), float(status.get("magnitude", 0.0)))
			return
	list.append(status.duplicate(true))
	if str(status.get("type", "")) == "wound":
		var part: String = str(status.get("part", "body"))
		(target["wounds"] as Dictionary)[part] = maxf(float((target["wounds"] as Dictionary).get(part, 0.0)), float(status.get("magnitude", 0.0)))


# --- 敌方 AI ---

func enemy_turn(encounter: Dictionary, opts: Dictionary = {}, rng = null) -> Dictionary:
	var results: Array = []
	for id in encounter["order"]:
		var a: Dictionary = _actor(encounter, str(id))
		if str(a["side"]) == "player":
			continue
		if int(a["hp"]) <= 0 or bool(a["fled"]):
			continue
		if str(encounter["outcome"]) != "ongoing":
			break
		_begin_actor_turn(a)
		var guard: int = 0
		while guard < 3 and int(a["ap"]) > 0 and str(encounter["outcome"]) == "ongoing":
			guard += 1
			var mv: String = _ai_choose(encounter, a)
			if mv == "":
				break
			results.append(_act(encounter, str(id), mv, opts, rng))
	return {"ok": true, "actions": results}


func _ai_choose(encounter: Dictionary, actor: Dictionary) -> String:
	var pool: Array = available_moves(encounter, str(actor["id"]))
	if pool.is_empty():
		return ""
	var policy: String = str((actor.get("ai", {}) as Dictionary).get("policy", "balanced"))
	var low: bool = int(actor["hp"]) * 3 <= int(actor["max_hp"])
	if low:
		if pool.has("guard"):
			return "guard"
		if pool.has("ward"):
			return "ward"
		if pool.has("rally"):
			return "rally"
		if pool.has("hold_position"):
			return "hold_position"
	var best: String = ""
	var best_power: float = -1.0
	for mid in pool:
		var m: Dictionary = (MOVES[str(encounter["style"])] as Dictionary)[mid]
		var p: float = float(m.get("power", 0.0))
		# 防守型偏好自身招式与低消耗；进攻型纯取威力。
		if policy == "defensive" and str(m.get("target", "enemy")) == "self":
			p += 0.5
		if p > best_power:
			best_power = p
			best = str(mid)
	return best


func _begin_actor_turn(actor: Dictionary) -> void:
	actor["ap"] = int(actor["max_ap"])


# --- 状态 tick 与回合 ---

func tick_statuses(encounter: Dictionary, opts: Dictionary = {}, rng = null) -> Dictionary:
	var ticks: Array = []
	for id in encounter["order"]:
		var a: Dictionary = _actor(encounter, str(id))
		# 冷却递减。
		var cds: Dictionary = a["cooldowns"]
		for mid in cds.keys():
			cds[mid] = maxi(0, int(cds[mid]) - 1)
		# 状态结算（持续伤害 + 时长递减）。
		var survivors: Array = []
		for s in (a["statuses"] as Array):
			var sd: Dictionary = s
			if str(sd.get("type", "")) == "dot" and int(a["hp"]) > 0:
				var dot: int = int(round(float(sd.get("magnitude", 0.0))))
				if dot > 0:
					_apply_damage(encounter, a, dot, str(sd.get("source", "dot")))
					ticks.append({"actor": str(id), "type": "dot", "damage": dot})
			sd["duration"] = int(sd.get("duration", 0)) - 1
			if int(sd["duration"]) > 0:
				survivors.append(sd)
			elif str(sd.get("type", "")) == "wound":
				(a["wounds"] as Dictionary).erase(str(sd.get("part", "body")))
		a["statuses"] = survivors
	return {"ok": true, "ticks": ticks}


func check_outcome(encounter: Dictionary) -> String:
	# 士气崩溃：低血 + 高恐惧 → 逃跑。
	for id in encounter["order"]:
		var a: Dictionary = _actor(encounter, str(id))
		if int(a["hp"]) > 0 and not bool(a["fled"]) and _morale_break(a):
			a["fled"] = true
			_add_log(encounter, "%s 士气崩溃，逃离战斗。" % str(a["name"]))
	var p_alive: int = _count_alive(encounter, "player")
	var e_alive: int = _count_alive(encounter, "enemy")
	var outcome: String = "ongoing"
	if p_alive == 0 and e_alive == 0:
		outcome = "draw"
	elif p_alive == 0:
		outcome = "enemy_win"
	elif e_alive == 0:
		outcome = "player_win"
	elif int(encounter["round"]) >= int(encounter["max_rounds"]):
		outcome = _decide_timeout(encounter)
	encounter["outcome"] = outcome
	return outcome


func _team_score(encounter: Dictionary, side: String) -> float:
	var s: float = 0.0
	for id in encounter["order"]:
		var a: Dictionary = _actor(encounter, str(id))
		if str(a["side"]) != side:
			continue
		s += float(a["hp"])
		s += float((encounter["damage"] as Dictionary).get(str(id), 0))
	return s


func _decide_timeout(encounter: Dictionary) -> String:
	var win: String = str((STYLES[encounter["style"]] as Dictionary).get("win", "ko"))
	if win == "judgment":
		var ps: float = _team_score(encounter, "player")
		var es: float = _team_score(encounter, "enemy")
		if ps > es:
			return "player_win"
		if es > ps:
			return "enemy_win"
		return "draw"
	var ph: float = _team_hp(encounter, "player")
	var eh: float = _team_hp(encounter, "enemy")
	if ph > eh:
		return "player_win"
	if eh > ph:
		return "enemy_win"
	return "draw"


func _team_hp(encounter: Dictionary, side: String) -> float:
	var s: float = 0.0
	for id in encounter["order"]:
		var a: Dictionary = _actor(encounter, str(id))
		if str(a["side"]) == side and not bool(a["fled"]):
			s += float(a["hp"])
	return s


## 完整一回合：重置玩家行动点 → 玩家行动 → 敌方 AI → 状态 tick → 判定胜负。
func run_round(encounter: Dictionary, move_id: String, opts: Dictionary = {}, rng = null) -> Dictionary:
	if str(encounter["outcome"]) != "ongoing":
		return {"ok": false, "reason": "finished", "outcome": str(encounter["outcome"])}
	var player: Dictionary = _actor(encounter, str(encounter["player_id"]))
	_begin_actor_turn(player)
	var action: Dictionary = player_action(encounter, move_id, opts, rng)
	var enemy: Dictionary = enemy_turn(encounter, opts, rng)
	tick_statuses(encounter, opts, rng)
	encounter["round"] = int(encounter["round"]) + 1
	var outcome: String = check_outcome(encounter)
	return {
		"ok": true, "round": int(encounter["round"]), "action": action,
		"enemy": enemy, "outcome": outcome,
	}


# --- 结算钩子 ---

## 死亡接入：返回交给临终 / 传承流程的握手载荷。
func resolve_death(encounter: Dictionary, actor_id: String, opts: Dictionary = {}) -> Dictionary:
	if not (encounter["actors"] as Dictionary).has(actor_id):
		return {"ok": false, "reason": "unknown_actor"}
	var a: Dictionary = _actor(encounter, actor_id)
	return {
		"ok": true, "actor": actor_id, "name": str(a["name"]), "side": str(a["side"]),
		"death": true, "trigger": str(opts.get("trigger", "combat")),
		"killer": str(opts.get("killer", "")), "fatal_part": str(opts.get("fatal_part", "")),
		"round": int(encounter["round"]), "hook": "last_rites_inheritance",
	}


func battle_log(encounter: Dictionary) -> Array:
	return (encounter.get("log", []) as Array).duplicate(true)


func _add_log(encounter: Dictionary, text: String) -> void:
	(encounter["log"] as Array).append({"round": int(encounter["round"]), "text": text})


# --- 序列化 ---

func to_dict(state: Dictionary) -> Dictionary:
	return state.duplicate(true)


func from_dict(data: Dictionary) -> Dictionary:
	return data.duplicate(true)
