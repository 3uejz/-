class_name OrganizationSystem
extends RefCounted
## 组织与社团（R63；design D19）。
##
## 覆盖：
##   - 8 类组织：工会/行业协会/NGO/兴趣俱乐部/宗教团体/政党/秘密结社/犯罪团伙，
##     各有目标、合法性、会费、成员规模、资源与影响力；
##   - 成员机制：会费、活动义务、关系网、特殊任务、内部晋升、退出成本与叛逃风险；
##   - 集体行动：罢工/请愿/募捐/游行/抵制，成功率由成员规模、外部支持、对方压力与舆论决定；
##   - 内部派系：斗争影响资源与地位，可夺权、分裂、被清洗；
##   - 秘密组织：暴露触发法律与声望清算，含反侦察与内鬼；
##   - 边界：罢工致失业与行业停摆、组织破产解散。
##
## 设计取舍：
##   - 组织状态为纯数据 Dictionary；玩家成员关系存于 owner["org_memberships"] 数组，便于存读档与 headless 测试；
##   - 集体行动与派系斗争的随机项由外部注入 roll/rng，缺省时确定化（roll=0），便于测试；
##   - “暴露”由被查热度 heat 与反侦察 counter_intel 共同决定，超阈后由 handle_exposure 统一清算。

const BaselineScript = preload("res://sim/baseline.gd")

const LEGAL: String = "legal"
const GRAY: String = "gray"
const ILLEGAL: String = "illegal"

## 组织类型：目标 / 合法性 / 月会费 / 最低成员 / 基础影响力 / 是否秘密。
const ORG_TYPES: Dictionary = {
	"union": {"name": "工会", "goal": "维护劳工权益", "legality": LEGAL, "base_fee": 50000, "min_members": 20, "influence": 0.50, "secret": false},
	"trade_association": {"name": "行业协会", "goal": "协调行业利益", "legality": LEGAL, "base_fee": 120000, "min_members": 10, "influence": 0.60, "secret": false},
	"ngo": {"name": "NGO", "goal": "公益与公众倡导", "legality": LEGAL, "base_fee": 30000, "min_members": 5, "influence": 0.40, "secret": false},
	"club": {"name": "兴趣俱乐部", "goal": "共同爱好与互助", "legality": LEGAL, "base_fee": 10000, "min_members": 3, "influence": 0.15, "secret": false},
	"religious": {"name": "宗教团体", "goal": "信仰、教化与互助", "legality": LEGAL, "base_fee": 20000, "min_members": 10, "influence": 0.50, "secret": false},
	"party": {"name": "政党", "goal": "参与政治与执政", "legality": LEGAL, "base_fee": 200000, "min_members": 50, "influence": 0.85, "secret": false},
	"secret_society": {"name": "秘密结社", "goal": "隐秘互助与扩张", "legality": GRAY, "base_fee": 80000, "min_members": 5, "influence": 0.45, "secret": true},
	"criminal_gang": {"name": "犯罪团伙", "goal": "非法牟利与地盘", "legality": ILLEGAL, "base_fee": 100000, "min_members": 5, "influence": 0.55, "secret": true},
}

## 内部晋升阶梯：以完成任务数为门槛。
const MEMBER_RANKS: Array = [
	{"key": "member", "name": "成员", "tasks_required": 0, "stipend": 0},
	{"key": "core", "name": "骨干", "tasks_required": 3, "stipend": 20000},
	{"key": "officer", "name": "干部", "tasks_required": 8, "stipend": 80000},
	{"key": "leader", "name": "首领", "tasks_required": 15, "stipend": 300000},
]

## 集体行动：基础成功率 + 四项权重（对方压力为负向）。
const ACTIONS: Dictionary = {
	"strike": {"name": "罢工", "base": 0.35, "w_members": 0.30, "w_support": 0.20, "w_pressure": -0.18, "w_opinion": 0.28, "industry_halt": true, "unemployment": true, "resource_gain": 0.0},
	"petition": {"name": "请愿", "base": 0.45, "w_members": 0.20, "w_support": 0.25, "w_pressure": -0.10, "w_opinion": 0.30, "industry_halt": false, "unemployment": false, "resource_gain": 0.0},
	"fundraiser": {"name": "募捐", "base": 0.55, "w_members": 0.25, "w_support": 0.30, "w_pressure": 0.00, "w_opinion": 0.20, "industry_halt": false, "unemployment": false, "resource_gain": 1.0},
	"march": {"name": "游行", "base": 0.35, "w_members": 0.30, "w_support": 0.20, "w_pressure": -0.22, "w_opinion": 0.30, "industry_halt": false, "unemployment": false, "resource_gain": 0.0},
	"boycott": {"name": "抵制", "base": 0.40, "w_members": 0.22, "w_support": 0.25, "w_pressure": -0.15, "w_opinion": 0.33, "industry_halt": false, "unemployment": false, "resource_gain": 0.0},
}

const EXPOSE_HEAT_THRESHOLD: float = BaselineScript.ORG_EXPOSE_HEAT_THRESHOLD
const EXPOSE_HEAT_MAX: float = BaselineScript.ORG_EXPOSE_HEAT_MAX


# --- 类型表 ---

func org_types() -> Array:
	return ORG_TYPES.keys()


func type_count() -> int:
	return ORG_TYPES.size()


func has_type(key: String) -> bool:
	return ORG_TYPES.has(key)


func type_def(key: String) -> Dictionary:
	if not ORG_TYPES.has(key):
		return {}
	return (ORG_TYPES[key] as Dictionary).duplicate(true)


func legalities() -> Array:
	return [LEGAL, GRAY, ILLEGAL]


func member_ranks() -> Array:
	return MEMBER_RANKS.duplicate(true)


func rank(index: int) -> Dictionary:
	if index < 0 or index >= MEMBER_RANKS.size():
		return {}
	return (MEMBER_RANKS[index] as Dictionary).duplicate(true)


func is_secret(org: Dictionary) -> bool:
	var def: Dictionary = ORG_TYPES.get(str(org.get("type", "")), {})
	return bool(def.get("secret", false))


func _roll(forced: float, rng) -> float:
	if forced >= 0.0:
		return clampf(forced, 0.0, 1.0)
	if rng != null:
		return rng.next_float()
	return 0.0


# --- 组织建立 ---

## 新建组织状态。members 影响初始影响力与资源规模。
func create_org(org_type: String, members: int, opts: Dictionary = {}) -> Dictionary:
	if not ORG_TYPES.has(org_type):
		return {"ok": false, "reason": "unknown_type"}
	var def: Dictionary = ORG_TYPES[org_type]
	var m: int = maxi(0, members)
	var influence: float = clampf(float(def["influence"]) + float(m) / 1000.0, 0.0, 1.0)
	var org: Dictionary = {
		"id": str(opts.get("id", "org_%s" % org_type)),
		"type": org_type,
		"name": str(opts.get("name", def["name"])),
		"goal": str(def["goal"]),
		"legality": str(def["legality"]),
		"members": m,
		"resources": int(opts.get("resources", m * 10000)),
		"influence": influence,
		"cohesion": clampf(float(opts.get("cohesion", 0.7)), 0.0, 1.0),
		"factions": [],
		"leader_faction": "",
		"exposed": false,
		"heat": 0.0,
		"counter_intel": clampf(float(opts.get("counter_intel", 0.5)), 0.0, 1.0),
		"purge_count": 0,
		"bankrupt": false,
		"disbanded": false,
	}
	return {"ok": true, "org": org}


# --- 成员机制 ---

func memberships(owner: Dictionary) -> Array:
	if not owner.has("org_memberships") or typeof(owner["org_memberships"]) != TYPE_ARRAY:
		owner["org_memberships"] = []
	return owner["org_memberships"]


func membership(owner: Dictionary, org_id: String) -> Dictionary:
	for m in memberships(owner):
		if m is Dictionary and str((m as Dictionary).get("org_id", "")) == org_id:
			return m
	return {}


## 加入组织：写入会费、活动义务、关系网与晋升路径，并返回契约信息。
func join(owner: Dictionary, org: Dictionary, opts: Dictionary = {}) -> Dictionary:
	if bool(org.get("disbanded", false)):
		return {"ok": false, "reason": "disbanded"}
	var org_id: String = str(org.get("id", ""))
	if not membership(owner, org_id).is_empty():
		return {"ok": false, "reason": "already_member"}
	var def: Dictionary = ORG_TYPES.get(str(org.get("type", "")), {})
	var membership_entry: Dictionary = {
		"org_id": org_id,
		"rank_index": 0,
		"rank_key": str((MEMBER_RANKS[0] as Dictionary)["key"]),
		"dues_owed": int(def.get("base_fee", 0)),
		"tasks_completed": 0,
		"faction": "",
		"joined_minute": int(opts.get("minute", 0)),
	}
	memberships(owner).append(membership_entry)
	org["members"] = int(org.get("members", 0)) + 1
	return {
		"ok": true,
		"membership": membership_entry,
		"dues": int(def.get("base_fee", 0)),
		"obligation_days_per_month": int(opts.get("obligation_days", 2)),
		"network_size": int(opts.get("network_size", 5)),
		"exit_cost": exit_cost(org, false),
		"promotion_path": MEMBER_RANKS.duplicate(true),
	}


## 缴纳会费，清减欠费。
func pay_dues(membership_entry: Dictionary, amount: int) -> Dictionary:
	var paid: int = maxi(0, amount)
	membership_entry["dues_owed"] = maxi(0, int(membership_entry.get("dues_owed", 0)) - paid)
	return {"ok": true, "paid": paid, "dues_owed": int(membership_entry["dues_owed"])}


## 派发特殊任务。
func assign_task(org: Dictionary, membership_entry: Dictionary, task: String) -> Dictionary:
	if bool(org.get("disbanded", false)):
		return {"ok": false, "reason": "disbanded"}
	membership_entry["pending_task"] = task
	return {"ok": true, "task": task}


## 完成特殊任务；成功才计入晋升所需任务数。
func complete_task(org: Dictionary, membership_entry: Dictionary, success: bool) -> Dictionary:
	if not membership_entry.has("pending_task"):
		return {"ok": false, "reason": "no_task"}
	var task: String = str(membership_entry["pending_task"])
	membership_entry.erase("pending_task")
	if success:
		membership_entry["tasks_completed"] = int(membership_entry.get("tasks_completed", 0)) + 1
		org["influence"] = clampf(float(org.get("influence", 0.0)) + 0.005, 0.0, 1.0)
	return {
		"ok": true, "task": task, "success": success,
		"tasks_completed": int(membership_entry.get("tasks_completed", 0)),
	}


func evaluate_promotion(org: Dictionary, membership_entry: Dictionary) -> bool:
	var idx: int = int(membership_entry.get("rank_index", 0))
	if idx + 1 >= MEMBER_RANKS.size():
		return false
	var need: int = int((MEMBER_RANKS[idx + 1] as Dictionary)["tasks_required"])
	return int(membership_entry.get("tasks_completed", 0)) >= need


func promote(org: Dictionary, membership_entry: Dictionary) -> Dictionary:
	if not evaluate_promotion(org, membership_entry):
		return {"ok": false, "reason": "not_eligible"}
	var idx: int = int(membership_entry.get("rank_index", 0)) + 1
	var rank_def: Dictionary = MEMBER_RANKS[idx]
	membership_entry["rank_index"] = idx
	membership_entry["rank_key"] = str(rank_def["key"])
	return {"ok": true, "rank_index": idx, "rank_key": str(rank_def["key"]), "rank_name": str(rank_def["name"])}


func stipend(membership_entry: Dictionary) -> int:
	var idx: int = int(membership_entry.get("rank_index", 0))
	var r: Dictionary = rank(idx)
	return int(r.get("stipend", 0))


## 退出成本：合法组织低廉，秘密/非法组织高昂；未获批准额外加价。
func exit_cost(org: Dictionary, approved: bool) -> int:
	var def: Dictionary = ORG_TYPES.get(str(org.get("type", "")), {})
	var fee: int = int(def.get("base_fee", 0))
	var legality: String = str(def.get("legality", LEGAL))
	var cost: int = 0
	if legality == GRAY:
		cost = fee * 2
	elif legality == ILLEGAL:
		cost = fee * 5
	if not approved:
		cost = int(round(float(cost) * 1.5))
	return cost


## 退出组织：结算退出成本、叛逃风险与法律风险；叛逃秘密组织会提高被查热度。
func leave(owner: Dictionary, org: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var entry: Dictionary = membership(owner, str(org.get("id", "")))
	if entry.is_empty():
		return {"ok": false, "reason": "not_member"}
	var approved: bool = bool(opts.get("approved", false))
	var def: Dictionary = ORG_TYPES.get(str(org.get("type", "")), {})
	var legality: String = str(def.get("legality", LEGAL))
	var defection_risk: float = 0.05
	var legal_risk: float = 0.0
	if legality == GRAY:
		defection_risk = 0.30
		legal_risk = 0.15
	elif legality == ILLEGAL:
		defection_risk = 0.60
		legal_risk = 0.40
	if not approved:
		defection_risk += 0.20
	# 未获批准叛逃秘密组织会暴露组织。
	if not approved and bool(def.get("secret", false)):
		org["heat"] = clampf(float(org.get("heat", 0.0)) + defection_risk * 50.0, 0.0, EXPOSE_HEAT_MAX)
	var cost: int = exit_cost(org, approved)
	var list: Array = memberships(owner)
	for i in list.size():
		if str((list[i] as Dictionary).get("org_id", "")) == str(org.get("id", "")):
			list.remove_at(i)
			break
	org["members"] = maxi(0, int(org.get("members", 0)) - 1)
	return {
		"ok": true, "exit_cost": cost,
		"defection_risk": clampf(defection_risk, 0.0, 1.0),
		"legal_risk": legal_risk, "approved": approved,
	}


# --- 集体行动 ---

## 集体行动成功率 = base + 成员规模 + 外部支持 + 对方压力(负) + 舆论。
## opts: members/target_members/external_support/opponent_pressure/public_opinion/roll。
func action_probability(org: Dictionary, action: String, opts: Dictionary = {}) -> float:
	if not ACTIONS.has(action):
		return 0.0
	var a: Dictionary = ACTIONS[action]
	var members: float = float(opts.get("members", org.get("members", 0)))
	var target: float = maxf(1.0, float(opts.get("target_members", 100.0)))
	var members_factor: float = clampf(members / target, 0.0, 1.0)
	var support: float = clampf(float(opts.get("external_support", 0.0)), 0.0, 1.0)
	var pressure: float = clampf(float(opts.get("opponent_pressure", 0.0)), 0.0, 1.0)
	var opinion: float = clampf(float(opts.get("public_opinion", 0.0)), -1.0, 1.0)
	var prob: float = float(a["base"]) \
		+ float(a["w_members"]) * members_factor \
		+ float(a["w_support"]) * support \
		+ float(a["w_pressure"]) * pressure \
		+ float(a["w_opinion"]) * opinion
	return clampf(prob, 0.05, 0.95)


## 发起集体行动。成功则提升影响力；罢工成功额外引发失业与行业停摆。
func collective_action(org: Dictionary, action: String, opts: Dictionary = {}, rng = null) -> Dictionary:
	if not ACTIONS.has(action):
		return {"ok": false, "reason": "unknown_action"}
	if bool(org.get("disbanded", false)):
		return {"ok": false, "reason": "disbanded"}
	var a: Dictionary = ACTIONS[action]
	var prob: float = action_probability(org, action, opts)
	var roll: float = _roll(float(opts.get("roll", -1.0)), rng)
	var success: bool = roll < prob
	var members: int = int(opts.get("members", org.get("members", 0)))
	var consequences: Dictionary = {}
	if success:
		org["influence"] = clampf(float(org.get("influence", 0.0)) + 0.03, 0.0, 1.0)
		if bool(a.get("industry_halt", false)):
			consequences["industry_halt"] = true
		if bool(a.get("unemployment", false)):
			consequences["unemployment"] = int(round(float(members) * 0.5))
		if float(a.get("resource_gain", 0.0)) > 0.0:
			var gain: int = int(round(float(opts.get("external_support", 0.0)) * float(members) * 100.0))
			org["resources"] = int(org.get("resources", 0)) + gain
			consequences["raised"] = gain
	else:
		org["influence"] = clampf(float(org.get("influence", 0.0)) - 0.01, 0.0, 1.0)
		org["heat"] = clampf(float(org.get("heat", 0.0)) + 20.0, 0.0, EXPOSE_HEAT_MAX)
	return {
		"ok": true, "action": action, "probability": prob, "success": success,
		"consequences": consequences, "influence": float(org["influence"]),
	}


# --- 内部派系 ---

func form_faction(org: Dictionary, name: String, strength: float) -> Dictionary:
	var factions: Array = org["factions"]
	for f in factions:
		if str((f as Dictionary)["name"]) == name:
			(f as Dictionary)["strength"] = clampf(float((f as Dictionary)["strength"]) + strength, 0.0, 1.0)
			return {"ok": true, "faction": f}
	var faction: Dictionary = {"name": name, "strength": clampf(strength, 0.0, 1.0)}
	factions.append(faction)
	return {"ok": true, "faction": faction}


func faction_strength(org: Dictionary, name: String) -> float:
	for f in (org["factions"] as Array):
		if str((f as Dictionary)["name"]) == name:
			return float((f as Dictionary)["strength"])
	return 0.0


## 派系斗争：可夺权/分裂/被清洗/妥协；结果由派系相对实力与 roll 决定。
func faction_struggle(org: Dictionary, name: String, opts: Dictionary = {}, rng = null) -> Dictionary:
	if faction_strength(org, name) <= 0.0:
		return {"ok": false, "reason": "no_faction"}
	var self_strength: float = faction_strength(org, name)
	var strongest_other: float = 0.0
	for f in (org["factions"] as Array):
		if str((f as Dictionary)["name"]) != name:
			strongest_other = maxf(strongest_other, float((f as Dictionary)["strength"]))
	var sway: float = self_strength - strongest_other
	var roll: float = _roll(float(opts.get("roll", -1.0)), rng)
	var outcome: String = "compromise"
	if roll < 0.40:
		outcome = "seize_power" if sway >= 0.0 else "split"
	elif roll < 0.75:
		outcome = "compromise"
	else:
		outcome = "purge"
	match outcome:
		"seize_power":
			org["leader_faction"] = name
			org["influence"] = clampf(float(org.get("influence", 0.0)) + 0.05, 0.0, 1.0)
		"split":
			var leaving: int = int(round(float(org.get("members", 0)) * 0.4))
			org["members"] = maxi(0, int(org.get("members", 0)) - leaving)
			org["resources"] = int(round(float(org.get("resources", 0)) * 0.6))
			org["cohesion"] = clampf(float(org.get("cohesion", 0.0)) - 0.20, 0.0, 1.0)
		"purge":
			org["purge_count"] = int(org.get("purge_count", 0)) + 1
			var purged: int = int(round(float(org.get("members", 0)) * 0.2))
			org["members"] = maxi(0, int(org.get("members", 0)) - purged)
			org["cohesion"] = clampf(float(org.get("cohesion", 0.0)) - 0.10, 0.0, 1.0)
			org["factions"] = []
		"compromise":
			org["cohesion"] = clampf(float(org.get("cohesion", 0.0)) + 0.05, 0.0, 1.0)
	return {
		"ok": true, "outcome": outcome, "members": int(org["members"]),
		"cohesion": float(org["cohesion"]), "resources": int(org["resources"]),
	}


# --- 秘密组织：暴露、反侦察与内鬼 ---

func add_heat(org: Dictionary, amount: float) -> Dictionary:
	org["heat"] = clampf(float(org.get("heat", 0.0)) + maxf(0.0, amount), 0.0, EXPOSE_HEAT_MAX)
	return {"ok": true, "heat": float(org["heat"])}


func set_counter_intel(org: Dictionary, value: float) -> Dictionary:
	org["counter_intel"] = clampf(value, 0.0, 1.0)
	return {"ok": true, "counter_intel": float(org["counter_intel"])}


func expose_threshold(org: Dictionary) -> float:
	# 反侦察越强，暴露阈值越高。
	return EXPOSE_HEAT_THRESHOLD * (1.0 + float(org.get("counter_intel", 0.5)))


## 判定是否暴露：仅秘密组织；heat 超阈值且随机命中。
func attempt_expose(org: Dictionary, opts: Dictionary = {}, rng = null) -> Dictionary:
	if not is_secret(org):
		return {"ok": false, "reason": "not_secret"}
	var heat: float = float(org.get("heat", 0.0))
	var threshold: float = expose_threshold(org)
	var roll: float = _roll(float(opts.get("roll", -1.0)), rng)
	var chance: float = clampf(heat / EXPOSE_HEAT_MAX, 0.0, 0.95)
	var exposed: bool = heat >= threshold and roll < chance
	if exposed:
		org["exposed"] = true
	return {"ok": true, "exposed": exposed, "heat": heat, "threshold": threshold, "chance": chance}


## 暴露清算：组织解散，玩家留下案底与声望损失（联动 D12）。
func handle_exposure(owner: Dictionary, org: Dictionary) -> Dictionary:
	if not bool(org.get("exposed", false)):
		return {"ok": false, "reason": "not_exposed"}
	org["disbanded"] = true
	org["members"] = 0
	org["factions"] = []
	org["heat"] = 0.0
	var legal: Variant = owner.get("legal", {})
	if not (legal is Dictionary):
		legal = {}
	(legal as Dictionary)["criminal_record"] = true
	(legal as Dictionary)["wanted_level"] = int((legal as Dictionary).get("wanted_level", 0)) + 2
	owner["legal"] = legal
	var rep_delta: float = -30.0
	var rep: Variant = owner.get("reputation", {})
	if rep is Dictionary and not (rep as Dictionary).is_empty():
		if (rep as Dictionary).has("fame"):
			(rep as Dictionary)["fame"] = clampf(float((rep as Dictionary)["fame"]) + rep_delta, -100.0, 100.0)
		elif (rep as Dictionary).has("public"):
			(rep as Dictionary)["public"] = clampf(float((rep as Dictionary)["public"]) + rep_delta, -100.0, 100.0)
		owner["reputation"] = rep
	return {
		"ok": true, "disbanded": true, "criminal_record": true,
		"wanted_level": int((legal as Dictionary)["wanted_level"]),
		"reputation_delta": rep_delta,
	}


func plant_mole(org: Dictionary, name: String) -> Dictionary:
	org["mole"] = name
	return {"ok": true, "mole": name}


## 排查内鬼：命中则揪出；未命中反而抬高被查热度。
func detect_mole(org: Dictionary, opts: Dictionary = {}, rng = null) -> Dictionary:
	if not org.has("mole"):
		return {"ok": true, "found": false, "mole": ""}
	var chance: float = 0.30 + float(org.get("counter_intel", 0.5)) * 0.50
	var roll: float = _roll(float(opts.get("roll", -1.0)), rng)
	if roll < chance:
		var name: String = str(org["mole"])
		org.erase("mole")
		return {"ok": true, "found": true, "mole": name}
	org["heat"] = clampf(float(org.get("heat", 0.0)) + 15.0, 0.0, EXPOSE_HEAT_MAX)
	return {"ok": true, "found": false, "mole": "", "heat": float(org["heat"])}


# --- 财务与解散 ---

## 结算收支；持续资不抵债且无成员时破产。
func tick_finance(org: Dictionary, income: int, expense: int) -> Dictionary:
	org["resources"] = int(org.get("resources", 0)) + int(income) - int(expense)
	if int(org["resources"]) < 0 and int(org.get("members", 0)) <= 0:
		org["bankrupt"] = true
	return {"ok": true, "resources": int(org["resources"]), "bankrupt": bool(org.get("bankrupt", false))}


## 破产解散：成员与派系清空，组织终止。
func declare_bankruptcy(org: Dictionary) -> Dictionary:
	org["bankrupt"] = true
	org["disbanded"] = true
	org["members"] = 0
	org["factions"] = []
	org["leader_faction"] = ""
	return {"ok": true, "bankrupt": true, "disbanded": true}


func to_dict(org: Dictionary) -> Dictionary:
	return org.duplicate(true)


func from_dict(data: Dictionary) -> Dictionary:
	return data.duplicate(true)
