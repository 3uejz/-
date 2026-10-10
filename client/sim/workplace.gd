class_name WorkplaceSystem
extends RefCounted
## 职场关系、派系与办公室政治（R13.8、R47.4-6；design D7）。
##
## 维度：上下级好感、同事支持度、绩效分、派系归属，另加公司内部声望与行业口碑。
## 事件：抢功、甩锅、站队、举报，按关系与性格掷骰（R47.5）。
## 派系：多派系动态博弈，玩家可站队、骑墙或自组；派系影响资源、晋升与裁员。
## 恶化后果：排挤、调岗、降职、解雇，权重随关系恶化上升（R47.6）。
## 晋升：绩效 + 关系 + 声望 + 运气共同决定。
##
## 设计取舍：
##   - 职场状态存于独立 work 字典，与 player["job"] 解耦，便于 headless 测试与存档；
##   - 与 NPC 的五维关系由调用方注入 RelationshipSystem（可为 null），本模块只读其好感轴；
##   - 事件结果确定化由注入 rng 决定，便于复现与三端对齐。

const BaselineScript = preload("res://sim/baseline.gd")

## 职场数值真源：shared/consistency/baseline/workplace.json。
const DIM_MAX: float = BaselineScript.WORK_DIM_MAX

const EVENT_CREDIT_GRAB: String = "credit_grab"   # 抢功
const EVENT_BLAME: String = "blame"               # 甩锅
const EVENT_TAKE_SIDES: String = "take_sides"     # 站队
const EVENT_REPORT: String = "report"             # 举报

## 恶化后果（由轻到重）。
const ACTIONS: Array = ["none", "sidelined", "transfer", "demote", "fire"]

const EVENT_WEIGHTS: Dictionary = BaselineScript.WORK_EVENT_WEIGHTS

const PROMOTION_PERFORMANCE_WEIGHT: float = BaselineScript.WORK_PROMOTION_PERFORMANCE_WEIGHT
const PROMOTION_SUPERVISOR_WEIGHT: float = BaselineScript.WORK_PROMOTION_SUPERVISOR_WEIGHT
const PROMOTION_REPUTATION_WEIGHT: float = BaselineScript.WORK_PROMOTION_REPUTATION_WEIGHT
const PROMOTION_LUCK_WEIGHT: float = BaselineScript.WORK_PROMOTION_LUCK_WEIGHT
const PROMOTION_INDUSTRY_WEIGHT: float = BaselineScript.WORK_PROMOTION_INDUSTRY_WEIGHT
const PROMOTION_THRESHOLD: float = BaselineScript.WORK_PROMOTION_THRESHOLD

const FACTION_POWER_MAX: float = BaselineScript.WORK_FACTION_POWER_MAX


# --- 初始化与存取 ---

## 新建职场状态。supervisor_id 为直属上级，colleagues 为同事 id 列表。
func init_workplace(company_id: String, supervisor_id: String, colleagues: Array) -> Dictionary:
	var work: Dictionary = {
		"company_id": company_id,
		"supervisor_id": supervisor_id,
		"colleague_ids": colleagues.duplicate(),
		"supervisor_favor": 50.0,
		"colleague_support": 50.0,
		"performance": 50.0,
		"internal_reputation": 50.0,
		"industry_reputation": 50.0,
		"faction": "none",
		"factions": {},
		"conflicts": [],
	}
	return work


func add_faction(work: Dictionary, id: String, name: String, power: float = 30.0, alignment: String = "neutral") -> Dictionary:
	var factions: Dictionary = work.get("factions", {})
	if not factions.has(id):
		factions[id] = {
			"id": id, "name": name,
			"power": clampf(power, 0.0, FACTION_POWER_MAX),
			"alignment": alignment, "members": [],
		}
		work["factions"] = factions
	return work


func join_faction(work: Dictionary, id: String) -> Dictionary:
	var factions: Dictionary = work.get("factions", {})
	if not factions.has(id):
		return {"ok": false, "reason": "no_such_faction"}
	var f: Dictionary = factions[id]
	var members: Array = f.get("members", [])
	members.append("player")
	f["members"] = members
	f["power"] = clampf(float(f.get("power", 30.0)) + 5.0, 0.0, FACTION_POWER_MAX)
	factions[id] = f
	work["factions"] = factions
	work["faction"] = id
	return {"ok": true, "faction": id}


func stay_neutral(work: Dictionary) -> Dictionary:
	work["faction"] = "none"
	return {"ok": true, "faction": "none"}


func found_faction(work: Dictionary, id: String, name: String) -> Dictionary:
	work = add_faction(work, id, name, 20.0, "player")
	var r: Dictionary = join_faction(work, id)
	r["founded"] = true
	return r


func faction_power(work: Dictionary, id: String) -> float:
	var factions: Dictionary = work.get("factions", {})
	if not factions.has(id):
		return 0.0
	return float((factions[id] as Dictionary).get("power", 0.0))


## 派系动态博弈：各派系力量向均值回归并叠加随机漂移，所属派系影响玩家支持度。
func settle_factions(work: Dictionary, rng) -> Dictionary:
	var factions: Dictionary = work.get("factions", {})
	var total: float = 0.0
	var count: int = 0
	for id in factions.keys():
		total += float((factions[id] as Dictionary).get("power", 0.0))
		count += 1
	if count == 0:
		return {"mean": 0.0}
	var mean: float = total / float(count)
	var drift: float = rng.next_float() * 6.0 - 3.0 if rng != null else 0.0
	for id in factions.keys():
		var f: Dictionary = factions[id]
		var p: float = float(f.get("power", 0.0))
		p = clampf(p + 0.1 * (mean - p) + drift, 0.0, FACTION_POWER_MAX)
		f["power"] = p
		factions[id] = f
	work["factions"] = factions
	# 所属派系力量影响同事支持。
	var my: String = str(work.get("faction", "none"))
	if my != "none" and factions.has(my):
		var bonus: float = (faction_power(work, my) - mean) * 0.2
		work["colleague_support"] = clampf(float(work.get("colleague_support", 50.0)) + bonus, 0.0, DIM_MAX)
	return {"mean": mean, "drift": drift}


# --- 办公室政治 ---

func _pers(player: Dictionary, key: String, default_value: float = 50.0) -> float:
	var attrs: Variant = player.get("attrs", {})
	if attrs is Dictionary:
		var g: Variant = (attrs as Dictionary).get("personality", {})
		if g is Dictionary:
			return float((g as Dictionary).get(key, default_value))
	return default_value


func _ability(player: Dictionary, key: String, default_value: float = 50.0) -> float:
	var attrs: Variant = player.get("attrs", {})
	if attrs is Dictionary:
		var g: Variant = (attrs as Dictionary).get("ability", {})
		if g is Dictionary:
			return float((g as Dictionary).get(key, default_value))
	return default_value


func _relation_favor(relations, player: Dictionary, target_id: String, default_value: float = 0.0) -> float:
	if relations == null or target_id.is_empty():
		return default_value
	var rel: Dictionary = relations.get_relation(player, target_id)
	return float(rel.get("favor", default_value))


func _pick_event(rng) -> String:
	var roll: float = rng.next_float() if rng != null else 0.5
	var acc: float = 0.0
	for key in [EVENT_CREDIT_GRAB, EVENT_BLAME, EVENT_TAKE_SIDES, EVENT_REPORT]:
		acc += float(EVENT_WEIGHTS[key])
		if roll <= acc:
			return key
	return EVENT_REPORT


## 发起一次办公室政治事件并按关系与性格掷骰（R47.5）。
## 返回 {event, actor, success, deltas, fired?}，并就地更新 work。
func office_politics(work: Dictionary, player: Dictionary, relations, rng, opts: Dictionary = {}) -> Dictionary:
	var event: String = str(opts.get("event", _pick_event(rng)))
	if not EVENT_WEIGHTS.has(event):
		event = EVENT_CREDIT_GRAB
	var colleagues: Array = work.get("colleague_ids", [])
	var actor: String = ""
	if colleagues.size() > 0 and rng != null:
		actor = str(colleagues[rng.next_u64() % colleagues.size()])
	# 玩家应对分：绩效、关系、声望、运气、尽责与情绪稳定性。
	var player_score: float = (
		0.35 * float(work.get("performance", 50.0))
		+ 0.20 * float(work.get("supervisor_favor", 50.0))
		+ 0.15 * float(work.get("colleague_support", 50.0))
		+ 0.10 * _ability(player, "luck", 50.0)
		+ 0.10 * _pers(player, "conscientiousness", 50.0)
		+ 0.10 * (100.0 - _pers(player, "neuroticism", 50.0))
	)
	# 对手分：派系力量与随机，抢功/举报对手更强。
	var base: float = 55.0
	if event == EVENT_CREDIT_GRAB or event == EVENT_REPORT:
		base += 10.0
	var roll: float = rng.next_float() * 40.0 if rng != null else 20.0
	var opponent_score: float = base + roll + 0.1 * faction_power(work, str(work.get("faction", "none")))
	var success: bool = player_score >= opponent_score
	var deltas: Dictionary = _apply_event(work, event, success)
	var record: Dictionary = {
		"event": event, "actor": actor, "success": success,
		"player_score": player_score, "opponent_score": opponent_score, "deltas": deltas,
	}
	var conflicts: Array = work.get("conflicts", [])
	conflicts.append(record)
	work["conflicts"] = conflicts
	if bool(opts.get("check_repercussion", false)):
		var rep: Dictionary = apply_repercussion(work, player, rng)
		if str(rep.get("action", "none")) == "fire":
			record["fired"] = true
	return record


func _apply_event(work: Dictionary, event: String, success: bool) -> Dictionary:
	var d: Dictionary = {"supervisor_favor": 0.0, "colleague_support": 0.0, "internal_reputation": 0.0}
	match event:
		EVENT_CREDIT_GRAB:
			if success:
				d["internal_reputation"] = 6.0
				d["supervisor_favor"] = 4.0
			else:
				d["internal_reputation"] = -4.0
				d["colleague_support"] = -3.0
		EVENT_BLAME:
			if success:
				d["colleague_support"] = 3.0
			else:
				d["supervisor_favor"] = -6.0
				d["internal_reputation"] = -3.0
		EVENT_TAKE_SIDES:
			if success:
				d["colleague_support"] = 5.0
			else:
				d["colleague_support"] = -5.0
				d["supervisor_favor"] = -2.0
		EVENT_REPORT:
			if success:
				d["internal_reputation"] = 4.0
				d["supervisor_favor"] = 3.0
			else:
				d["internal_reputation"] = -5.0
				d["supervisor_favor"] = -5.0
	for key in d.keys():
		var cur: float = float(work.get(key, 50.0))
		work[key] = clampf(cur + float(d[key]), 0.0, DIM_MAX)
	return d


# --- 晋升 ---

## 晋升综合分 0..100：绩效 + 上下级好感 + 内部声望 + 行业口碑 + 运气（R47.6）。
func promotion_score(work: Dictionary, player: Dictionary, relations, rng) -> float:
	var supervisor_favor: float = float(work.get("supervisor_favor", 50.0))
	var rel_favor: float = _relation_favor(relations, player, str(work.get("supervisor_id", "")), 0.0)
	var relation_term: float = clampf(50.0 + 0.5 * rel_favor, 0.0, 100.0)
	var score: float = (
		PROMOTION_PERFORMANCE_WEIGHT * float(work.get("performance", 50.0))
		+ PROMOTION_SUPERVISOR_WEIGHT * (0.5 * supervisor_favor + 0.5 * relation_term)
		+ PROMOTION_REPUTATION_WEIGHT * float(work.get("internal_reputation", 50.0))
		+ PROMOTION_INDUSTRY_WEIGHT * float(work.get("industry_reputation", 50.0))
		+ PROMOTION_LUCK_WEIGHT * _ability(player, "luck", 50.0)
	)
	var roll: float = rng.next_float() * 10.0 - 5.0 if rng != null else 0.0
	return clampf(score + roll, 0.0, 100.0)


func should_promote(work: Dictionary, player: Dictionary, relations, rng, threshold: float = PROMOTION_THRESHOLD) -> bool:
	return promotion_score(work, player, relations, rng) >= threshold


# --- 恶化和裁员 ---

## 关系恶化的被裁风险 0..1（含派系力量保护）。
func deterioration_risk(work: Dictionary) -> float:
	var sup: float = clampf(float(work.get("supervisor_favor", 50.0)), 0.0, 100.0)
	var col: float = clampf(float(work.get("colleague_support", 50.0)), 0.0, 100.0)
	var rep: float = clampf(float(work.get("internal_reputation", 50.0)), 0.0, 100.0)
	var risk: float = (60.0 - sup) / 60.0 * 0.4 + (60.0 - col) / 60.0 * 0.3 + (60.0 - rep) / 60.0 * 0.3
	var faction: String = str(work.get("faction", "none"))
	if faction != "none":
		risk -= 0.15 * (faction_power(work, faction) / 100.0)
	return clampf(risk, 0.0, 1.0)


## 依据恶化风险掷骰决定后果：排挤/调岗/降职/解雇（R47.6）。
func apply_repercussion(work: Dictionary, player: Dictionary, rng) -> Dictionary:
	var risk: float = deterioration_risk(work)
	var roll: float = rng.next_float() if rng != null else 1.0
	if roll > risk:
		return {"action": "none", "risk": risk}
	var tier: float = risk - roll  # 差值越大后果越重
	var action: String = "sidelined"
	if tier > 0.4:
		action = "fire"
	elif tier > 0.25:
		action = "demote"
	elif tier > 0.1:
		action = "transfer"
	match action:
		"sidelined":
			work["performance"] = clampf(float(work.get("performance", 50.0)) - 5.0, 0.0, DIM_MAX)
		"transfer":
			work["colleague_support"] = clampf(float(work.get("colleague_support", 50.0)) - 10.0, 0.0, DIM_MAX)
		"demote":
			work["internal_reputation"] = clampf(float(work.get("internal_reputation", 50.0)) - 15.0, 0.0, DIM_MAX)
		"fire":
			work["internal_reputation"] = 0.0
	return {"action": action, "risk": risk, "roll": roll}


func to_dict(work: Dictionary) -> Dictionary:
	return work.duplicate(true)


func from_dict(data: Dictionary) -> Dictionary:
	return data.duplicate(true)
