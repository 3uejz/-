class_name DisabilityElderlySystem
extends RefCounted
## 残障与养老（R65；design D21）。
##
## 覆盖：
##   - 残障来源（先天/伤病/事故/战争）与类型（肢体/视听/智力/精神）、程度轻中重；
##     以持久状态修正可用动词与移动能力；
##   - 辅具（轮椅/助听器/义肢/导盲犬/无障碍改造/康复训练）与手术康复部分恢复；
##   - 养老三模式（居家/社区/机构）、退休金与社保、临终关怀；
##   - 护理关系的情感与财务成本、护工失职与虐待追责；
##   - 认知障碍影响遗嘱/决策能力，引入监护制度；
##   - 残障歧视影响就业与社交。
##
## 设计取舍：
##   - 残障状态为纯数据 Dictionary；每条 condition 记录类型/来源/程度与移动惩罚；
##   - 移动能力由各项惩罚之和减去辅具加成得到，统一决定可用动词与歧视惩罚；
##   - 程度为重（heavy）的智力/精神障碍判定为无决策能力，纳入监护制度。

const SOURCE_CONCENTIAL: String = "congenital"
const SOURCES: Array = ["congenital", "illness", "accident", "war"]
const SOURCE_NAMES: Dictionary = {"congenital": "先天", "illness": "伤病", "accident": "事故", "war": "战争"}

const TYPE_PHYSICAL: String = "physical"
const TYPES: Array = ["physical", "sensory", "intellectual", "mental"]
const TYPE_NAMES: Dictionary = {"physical": "肢体", "sensory": "视听", "intellectual": "智力", "mental": "精神"}

const SEVERITIES: Dictionary = {"light": 1, "medium": 2, "heavy": 3}
const SEVERITY_NAMES: Dictionary = {"light": "轻度", "medium": "中度", "heavy": "重度"}
const SEVERITY_PENALTY: Dictionary = {"light": 0.15, "medium": 0.40, "heavy": 0.75}

## 各类型受限动词。
const TYPE_VERBS: Dictionary = {
	"physical": ["搬运", "奔跑", "攀爬", "长途驾驶"],
	"sensory": ["阅读", "驾驶", "观察", "精细作业"],
	"intellectual": ["管理", "投资", "签约", "作证"],
	"mental": ["社交", "工作", "决策", "出庭"],
}

## 辅具：花费、移动加成、适用类型。
const DEVICES: Dictionary = {
	"wheelchair": {"name": "轮椅", "cost": 800000, "mobility_bonus": 0.50, "types": ["physical"]},
	"hearing_aid": {"name": "助听器", "cost": 200000, "mobility_bonus": 0.10, "types": ["sensory"]},
	"prosthesis": {"name": "义肢", "cost": 1500000, "mobility_bonus": 0.40, "types": ["physical"]},
	"guide_dog": {"name": "导盲犬", "cost": 300000, "mobility_bonus": 0.35, "types": ["sensory"]},
	"accessibility": {"name": "无障碍改造", "cost": 500000, "mobility_bonus": 0.20, "types": ["physical", "sensory"]},
	"rehab": {"name": "康复训练", "cost": 100000, "mobility_bonus": 0.15, "types": ["physical", "sensory", "intellectual", "mental"]},
}

## 养老模式：月成本、质量、心情影响与寿命修正。
const CARE_HOME: String = "home_care"
const CARE_COMMUNITY: String = "community_care"
const CARE_INSTITUTION: String = "institution_care"
const CARE_MODES: Dictionary = {
	"home_care": {"name": "居家护理", "cost_per_month": 400000, "quality": 0.50, "happiness": 0.0, "life_modifier": 0.0},
	"community_care": {"name": "社区养老", "cost_per_month": 600000, "quality": 0.65, "happiness": 2.0, "life_modifier": 0.1},
	"institution_care": {"name": "机构养老", "cost_per_month": 1200000, "quality": 0.80, "happiness": -1.0, "life_modifier": 0.2},
}


# --- 状态与残障 ---

## 新建残障/养老状态。
func new_state() -> Dictionary:
	return {
		"conditions": [], "devices": [], "recovery": 0.0,
		"care_mode": "", "cognitive": false, "guardian": "", "hospice": false,
		"accessible": false, "retirement_years": 0.0,
	}


## 新增一项残障状态。
func acquire(state: Dictionary, d_type: String, source: String, severity: String) -> Dictionary:
	if not TYPES.has(d_type):
		return {"ok": false, "reason": "unknown_type"}
	if not SOURCES.has(source):
		return {"ok": false, "reason": "unknown_source"}
	if not SEVERITIES.has(severity):
		return {"ok": false, "reason": "unknown_severity"}
	var penalty: float = float(SEVERITY_PENALTY[severity])
	var mobility_penalty: float = penalty if d_type == TYPE_PHYSICAL else penalty * 0.3
	var cond: Dictionary = {
		"type": d_type, "source": source, "severity": severity,
		"level": int(SEVERITIES[severity]),
		"mobility_penalty": mobility_penalty,
		"restricted_verbs": (TYPE_VERBS[d_type] as Array).duplicate(),
	}
	(state["conditions"] as Array).append(cond)
	if d_type == "intellectual" or d_type == "mental":
		state["cognitive"] = true
	return {"ok": true, "condition": cond, "mobility": mobility(state)}


## 移动能力：1 减去各项移动惩罚，再加上辅具加成，夹在 0..1。
func mobility(state: Dictionary) -> float:
	var penalty: float = 0.0
	for c in (state.get("conditions", []) as Array):
		penalty += float((c as Dictionary).get("mobility_penalty", 0.0))
	var bonus: float = 0.0
	for d in (state.get("devices", []) as Array):
		var dev: Dictionary = DEVICES.get(str(d), {})
		bonus += float(dev.get("mobility_bonus", 0.0))
	if bool(state.get("accessible", false)):
		bonus += 0.15
	return clampf(1.0 - penalty + bonus, 0.0, 1.0)


func restricted_verbs(state: Dictionary) -> Array:
	var out: Array = []
	for c in (state.get("conditions", []) as Array):
		for v in (c as Dictionary).get("restricted_verbs", []):
			if not out.has(v):
				out.append(v)
	return out


func available_verbs(state: Dictionary, base_verbs: Array) -> Array:
	var out: Array = []
	var blocked: Array = restricted_verbs(state)
	for v in base_verbs:
		if not blocked.has(v):
			out.append(v)
	return out


# --- 辅具与康复 ---

## 装配辅具：适用任一所患残障类型即有效。
func fit_device(state: Dictionary, device_key: String) -> Dictionary:
	if not DEVICES.has(device_key):
		return {"ok": false, "reason": "unknown_device"}
	var dev: Dictionary = DEVICES[device_key]
	var applicable: bool = false
	var types: Array = dev["types"]
	for c in (state.get("conditions", []) as Array):
		if types.has(str((c as Dictionary)["type"])):
			applicable = true
			break
	if not applicable:
		return {"ok": false, "reason": "not_applicable"}
	(state["devices"] as Array).append(device_key)
	return {"ok": true, "device": device_key, "mobility": mobility(state), "cost": int(dev["cost"])}


## 手术/康复：部分恢复，按比例降低各残障的移动惩罚。
func surgery_recovery(state: Dictionary, amount: float) -> Dictionary:
	var recover: float = clampf(amount, 0.0, 1.0)
	state["recovery"] = clampf(float(state.get("recovery", 0.0)) + recover, 0.0, 1.0)
	for c in (state.get("conditions", []) as Array):
		var cond: Dictionary = c
		cond["mobility_penalty"] = maxf(0.0, float(cond.get("mobility_penalty", 0.0)) * (1.0 - recover))
	return {"ok": true, "recovery": float(state["recovery"]), "mobility": mobility(state)}


## 无障碍场所减少惩罚。
func set_accessible(state: Dictionary, accessible: bool) -> Dictionary:
	state["accessible"] = accessible
	return {"ok": true, "mobility": mobility(state)}


# --- 养老 ---

## 退休金：替代率随缴费年限上升。
func retirement_pension(avg_salary: float, years: float, opts: Dictionary = {}) -> Dictionary:
	var base_rate: float = float(opts.get("base_rate", 0.40))
	var bonus: float = minf(maxf(0.0, years), 40.0) / 40.0 * float(opts.get("years_bonus", 0.20))
	var rate: float = clampf(base_rate + bonus, 0.0, 1.0)
	return {"ok": true, "monthly": int(round(maxf(0.0, avg_salary) * rate)), "replacement_rate": rate}


## 社保与退休记录。
func enroll_social_security(state: Dictionary, years: float) -> Dictionary:
	state["retirement_years"] = float(state.get("retirement_years", 0.0)) + maxf(0.0, years)
	return {"ok": true, "retirement_years": float(state["retirement_years"]), "insured": true}


func choose_care_mode(state: Dictionary, mode: String) -> Dictionary:
	if not CARE_MODES.has(mode):
		return {"ok": false, "reason": "unknown_mode"}
	state["care_mode"] = mode
	return {"ok": true, "mode": mode, "def": (CARE_MODES[mode] as Dictionary).duplicate(true)}


## 结算 months 个月的养老效果：返回成本、心情与寿命修正。
func care_outcome(state: Dictionary, months: float) -> Dictionary:
	var mode: String = str(state.get("care_mode", ""))
	if not CARE_MODES.has(mode):
		return {"ok": false, "reason": "no_care_mode"}
	var cm: Dictionary = CARE_MODES[mode]
	var cost: int = int(round(float(cm["cost_per_month"]) * maxf(0.0, months)))
	var quality: float = float(cm["quality"])
	# 失能越重，机构/社区的质量收益越明显。
	var care_bonus: float = (1.0 - mobility(state)) * quality
	return {
		"ok": true, "mode": mode, "cost": cost,
		"happiness": float(cm["happiness"]) + care_bonus * 4.0,
		"life_modifier": float(cm["life_modifier"]) * quality,
	}


## 临终关怀：以质量决定舒适与尊严。
func hospice_care(state: Dictionary, quality: float) -> Dictionary:
	state["hospice"] = true
	var q: float = clampf(quality, 0.0, 1.0)
	return {"ok": true, "comfort": q, "dignity": q, "pain_relief": q}


# --- 护理关系 ---

## 护理成本：财务按需护理天数，情感成本随照料时长累积。
func caregiver_cost(state: Dictionary, days: float, opts: Dictionary = {}) -> Dictionary:
	var mode: String = str(opts.get("mode", state.get("care_mode", CARE_HOME)))
	var cm: Dictionary = CARE_MODES.get(mode, CARE_MODES[CARE_HOME])
	var monthly: float = float(cm["cost_per_month"])
	var d: float = maxf(0.0, days)
	var financial: int = int(round(monthly * d / 30.0))
	var emotional: float = clampf(d / 365.0 * 0.5, 0.0, 1.0)
	return {"ok": true, "financial_cost": financial, "emotional_cost": emotional}


## 护工事件：护理质量越低，失职/虐待概率越高。
func caregiver_event(quality: float, opts: Dictionary = {}, rng = null) -> Dictionary:
	var q: float = clampf(quality, 0.0, 1.0)
	var abuse_chance: float = (1.0 - q) * 0.30
	var neglect_chance: float = (1.0 - q) * 0.50
	var roll: float = _roll(float(opts.get("roll", -1.0)), rng)
	var incident: String = ""
	var severity: float = 0.0
	if roll < abuse_chance:
		incident = "abuse"
		severity = clampf((abuse_chance - roll) / maxf(0.01, abuse_chance), 0.0, 1.0)
	elif roll < neglect_chance:
		incident = "neglect"
		severity = clampf((neglect_chance - roll) / maxf(0.01, neglect_chance), 0.0, 1.0)
	return {"ok": true, "incident": incident, "severity": severity}


## 虐待/失职追责：赔偿 + 吊销资格处罚。
func hold_accountable(incident: Dictionary) -> Dictionary:
	var kind: String = str(incident.get("incident", ""))
	if kind == "":
		return {"ok": false, "reason": "no_incident"}
	var severity: float = clampf(float(incident.get("severity", 0.0)), 0.0, 1.0)
	var compensation: int = int(round(severity * 500000.0))
	return {
		"ok": true, "kind": kind, "compensation": compensation,
		"license_revoked": kind == "abuse", "criminal": kind == "abuse",
	}


# --- 监护与歧视 ---

func has_cognitive_impairment(state: Dictionary) -> bool:
	return bool(state.get("cognitive", false))


## 决策能力：无认知障碍则为真；有则看重度障碍（重度则丧失）。
func decision_capacity(state: Dictionary) -> bool:
	if not bool(state.get("cognitive", false)):
		return true
	var worst: int = 0
	for c in (state.get("conditions", []) as Array):
		var cond: Dictionary = c
		if str(cond["type"]) == "intellectual" or str(cond["type"]) == "mental":
			worst = maxi(worst, int(cond.get("level", 0)))
	return worst < 3


## 遗嘱有效性：需具备决策能力，否则需监护人追认。
func is_will_valid(state: Dictionary) -> bool:
	return decision_capacity(state)


## 建立监护：仅在丧失决策能力时成立。
func establish_guardianship(state: Dictionary, guardian_id: String) -> Dictionary:
	if decision_capacity(state):
		return {"ok": false, "reason": "has_capacity"}
	state["guardian"] = guardian_id
	return {"ok": true, "guardian": guardian_id, "ward_can_act": false}


## 残障歧视惩罚：移动能力越低，就业/社交惩罚越重。
func discrimination_penalty(state: Dictionary, context: String) -> float:
	var penalty: float = clampf(1.0 - mobility(state), 0.0, 1.0)
	match context:
		"employment":
			return penalty * 0.50
		"social":
			return penalty * 0.30
		_:
			return penalty * 0.20


func _roll(forced: float, rng) -> float:
	if forced >= 0.0:
		return clampf(forced, 0.0, 1.0)
	if rng != null:
		return rng.next_float()
	return 0.0


func to_dict(state: Dictionary) -> Dictionary:
	return state.duplicate(true)


func from_dict(data: Dictionary) -> Dictionary:
	return data.duplicate(true)
