class_name EmergencySystem
extends RefCounted

const BaselineScript = preload("res://sim/baseline.gd")
## 应急、消防与灾害救援（R80；design D36）。
##
## 覆盖：
##   - 职业：消防/急救/海警/山地/地震/洪水救援，专业训练与装备；
##   - 触发流程：报警 → 出警 → 救援 → 善后；响应时间直接影响伤亡结局；
##   - 分诊与资源：大规模事件检伤分类，资源不足时取舍（红/黄/绿/黑）；
##   - 志愿救援：采购设备、组建志愿组织并与专业队伍联动；
##   - 边界：现场二次事故、救援人员伤亡、指挥失当追责、灾后心理创伤。
##
## 设计取舍：
##   - 事件为纯数据 Dictionary，按 STAGES 推进，便于存读档与 headless 测试；
##   - 伤亡模型为确定性函数：需救治人数随响应时间线性上升（单调），
##     实际死亡由分诊救治率决定；资源/分诊直接决定结局，便于属性测试；
##   - 随机项（二次事故、救援人员伤亡）由外部注入 roll/rng，缺省确定化。

const PROF_FIRE: String = "fire"
const PROF_EMS: String = "ems"
const PROF_COAST_GUARD: String = "coast_guard"
const PROF_MOUNTAIN: String = "mountain_rescue"
const PROF_EARTHQUAKE: String = "earthquake_rescue"
const PROF_FLOOD: String = "flood_rescue"

## 职业：基准出警时间（分钟）与专用装备。
## 应急专业与基础响应时间。数值真源：shared/consistency/baseline/emergency.json。
const PROFESSIONS: Dictionary = BaselineScript.EM_PROFESSIONS

## 触发流程。
const STAGE_ALARM: String = "alarm"
const STAGE_DISPATCH: String = "dispatch"
const STAGE_RESCUE: String = "rescue"
const STAGE_AFTERMATH: String = "aftermath"
const STAGES: Array = ["alarm", "dispatch", "rescue", "aftermath"]
const STAGE_NAMES: Dictionary = {
	"alarm": "报警", "dispatch": "出警", "rescue": "救援", "aftermath": "善后",
}

## 检伤分类等级。
const TRIAGE_RED: String = "red"
const TRIAGE_YELLOW: String = "yellow"
const TRIAGE_GREEN: String = "green"
const TRIAGE_BLACK: String = "black"

const DEFAULT_RESPONSE_CAP: float = BaselineScript.EM_DEFAULT_RESPONSE_CAP
## 分诊存活率：及时救治与延迟救治的差异。
const SURVIVAL_TREATED: float = BaselineScript.EM_SURVIVAL_TREATED
const SURVIVAL_UNTREATED: float = BaselineScript.EM_SURVIVAL_UNTREATED
## 现场二次事故 / 指挥失当阈值。
const SECONDARY_BASE_RISK: float = BaselineScript.EM_SECONDARY_BASE_RISK
const COMMAND_FAULT_LINE: float = BaselineScript.EM_COMMAND_FAULT_LINE


# --- 数据表 ---

func profession_keys() -> Array:
	return PROFESSIONS.keys()


func profession_def(key: String) -> Dictionary:
	if not PROFESSIONS.has(key):
		return {}
	return (PROFESSIONS[key] as Dictionary).duplicate(true)


func stage_names() -> Dictionary:
	return STAGE_NAMES.duplicate(true)


func _roll(forced: float, rng) -> float:
	if forced >= 0.0:
		return clampf(forced, 0.0, 1.0)
	if rng != null:
		return rng.next_float()
	return 0.0


# --- 事件 ---

## 新建事件。type 为职业键；severity 0..1；at_risk 为需救助人数；trapped 为被困人数。
func new_incident(type: String, opts: Dictionary = {}) -> Dictionary:
	if not PROFESSIONS.has(type):
		type = PROF_FIRE
	return {
		"type": type,
		"region": str(opts.get("region", "")),
		"severity": clampf(float(opts.get("severity", 0.5)), 0.0, 1.0),
		"at_risk": maxi(0, int(opts.get("at_risk", 0))),
		"trapped": maxi(0, int(opts.get("trapped", 0))),
		"stage": STAGE_ALARM,
		"response_minutes": -1.0,
		"training": clampf(float(opts.get("training", 0.5)), 0.0, 1.0),
		"equipment_level": clampf(float(opts.get("equipment_level", 0.5)), 0.0, 1.0),
		"command_quality": clampf(float(opts.get("command_quality", 0.7)), 0.0, 1.0),
		"resources": {
			"medical_capacity": maxi(0, int(opts.get("medical_capacity", 20))),
			"rescue_teams": maxi(1, int(opts.get("rescue_teams", 1))),
		},
		"triage": {},
		"deaths": 0,
		"injured": 0,
		"rescued": 0,
		"responder_casualties": 0,
		"secondary": false,
		"fault": "",
	}


func alarm(incident: Dictionary) -> Dictionary:
	incident["stage"] = STAGE_ALARM
	return {"ok": true, "stage": incident["stage"]}


## 出警：计算响应时间。距离越远、装备/训练越差、志愿支援越少，响应越慢。
## opts: profession/distance_km/volunteers/volunteer_org/roll。
func dispatch(incident: Dictionary, opts: Dictionary = {}) -> Dictionary:
	incident["stage"] = STAGE_DISPATCH
	var prof: String = str(opts.get("profession", incident.get("type", PROF_FIRE)))
	var base: float = float((PROFESSIONS.get(prof, {}) as Dictionary).get("base_response", 10.0))
	var distance: float = maxf(0.0, float(opts.get("distance_km", 5.0)))
	var training: float = clampf(float(incident.get("training", 0.5)), 0.0, 1.0)
	var equipment: float = clampf(float(incident.get("equipment_level", 0.5)), 0.0, 1.0)
	var volunteers: int = maxi(0, int(opts.get("volunteers", 0)))
	var teams: int = maxi(1, int((incident["resources"] as Dictionary).get("rescue_teams", 1)))
	# 基础响应随距离增加；训练与装备缩减响应；志愿者与更多队伍进一步压缩。
	var t: float = base + distance * 1.5
	t *= 1.0 - 0.3 * training
	t *= 1.0 - 0.25 * equipment
	t *= 1.0 / (1.0 + float(teams - 1) * 0.2)
	t *= 1.0 / (1.0 + float(volunteers) * 0.05)
	var response: float = clampf(t, 1.0, DEFAULT_RESPONSE_CAP * 2.0)
	incident["response_minutes"] = response
	return {"ok": true, "stage": incident["stage"], "response_minutes": response, "profession": prof}


func response_time(incident: Dictionary) -> float:
	return float(incident.get("response_minutes", -1.0))


## 需救治人数（伤情规模）：随响应时间线性上升，与严重度/风险人数成正比。
func estimate_casualties(incident: Dictionary, response_minutes: float, opts: Dictionary = {}) -> float:
	var cap: float = maxf(1.0, float(opts.get("response_cap", DEFAULT_RESPONSE_CAP)))
	var severity: float = clampf(float(incident.get("severity", 0.5)), 0.0, 1.0)
	var at_risk: float = maxf(0.0, float(incident.get("at_risk", 0)))
	var rf: float = clampf(maxf(0.0, response_minutes) / cap, 0.0, 1.0)
	var rate: float = clampf(0.02 + 0.25 * rf, 0.0, 1.0) * (0.5 + severity)
	return at_risk * rate


## 检伤分类：按容量优先救治红>黄>绿；超出容量者延迟（黑/待救）。
func triage(injured: float, capacity: int, opts: Dictionary = {}) -> Dictionary:
	var total: float = maxf(0.0, injured)
	var red: float = total * 0.25
	var yellow: float = total * 0.40
	var green: float = total * 0.35
	var cap: float = maxf(0.0, float(capacity))
	# 优先级：红 -> 黄 -> 绿。
	var red_treated: float = minf(red, cap)
	cap -= red_treated
	var yellow_treated: float = minf(yellow, cap)
	cap -= yellow_treated
	var green_treated: float = minf(green, cap)
	var treated: float = red_treated + yellow_treated + green_treated
	var untreated: float = total - treated
	return {
		"red": red, "yellow": yellow, "green": green,
		"treated": treated, "untreated": untreated,
		"red_treated": red_treated, "yellow_treated": yellow_treated, "green_treated": green_treated,
		"capacity": int(capacity),
	}


## 救援结算：分诊救治率决定死亡人数；被困者减去死亡即获救。
func rescue(incident: Dictionary, opts: Dictionary = {}) -> Dictionary:
	incident["stage"] = STAGE_RESCUE
	var response: float = response_time(incident)
	if response < 0.0:
		response = float(opts.get("response_minutes", 30.0))
		incident["response_minutes"] = response
	var injured: float = estimate_casualties(incident, response, opts)
	var capacity: int = int((incident["resources"] as Dictionary).get("medical_capacity", 0))
	var tri: Dictionary = triage(injured, capacity, opts)
	var treated: float = float(tri["treated"])
	var untreated: float = float(tri["untreated"])
	var survivors: float = treated * SURVIVAL_TREATED + untreated * SURVIVAL_UNTREATED
	var deaths_f: float = maxf(0.0, injured - survivors)
	var rescued_f: float = maxf(0.0, float(incident.get("trapped", 0)) - deaths_f)
	incident["injured"] = int(round(injured))
	incident["deaths"] = int(round(deaths_f))
	incident["rescued"] = int(round(rescued_f))
	incident["triage"] = tri
	return {
		"ok": true, "stage": incident["stage"], "response_minutes": response,
		"injured": int(incident["injured"]), "deaths": int(incident["deaths"]),
		"rescued": int(incident["rescued"]), "triage": tri,
	}


## 现场二次事故：可造成额外伤亡与救援人员伤亡。
func secondary_incident(incident: Dictionary, opts: Dictionary = {}, rng = null) -> Dictionary:
	var risk: float = clampf(float(opts.get("risk", SECONDARY_BASE_RISK)) + clampf(float(incident.get("severity", 0.5)) - 0.5, 0.0, 0.5), 0.0, 0.95)
	var roll: float = _roll(float(opts.get("roll", -1.0)), rng)
	var occurred: bool = roll < risk
	if occurred:
		incident["secondary"] = true
		var extra: int = maxi(1, int(round(float(incident.get("at_risk", 0)) * 0.05)))
		incident["deaths"] = int(incident.get("deaths", 0)) + extra
		incident["responder_casualties"] = int(incident.get("responder_casualties", 0)) + maxi(1, int(round(float(extra) * 0.5)))
	else:
		incident["secondary"] = false
	return {
		"ok": true, "occurred": occurred, "risk": risk, "roll": roll,
		"deaths": int(incident.get("deaths", 0)),
		"responder_casualties": int(incident.get("responder_casualties", 0)),
	}


## 救援人员伤亡：指挥质量越低、严重度越高，救援者伤亡风险越大。
func rescuer_casualties(incident: Dictionary, opts: Dictionary = {}) -> int:
	var command: float = clampf(float(incident.get("command_quality", 0.7)), 0.0, 1.0)
	var severity: float = clampf(float(incident.get("severity", 0.5)), 0.0, 1.0)
	var risk: float = clampf((1.0 - command) * 0.4 + severity * 0.2, 0.0, 0.8)
	var teams: int = maxi(1, int((incident["resources"] as Dictionary).get("rescue_teams", 1)))
	var n: int = int(round(float(teams) * risk))
	if bool(opts.get("force", false)):
		n = maxi(n, 1)
	incident["responder_casualties"] = int(incident.get("responder_casualties", 0)) + n
	return n


## 善后：指挥失当追责与灾后心理创伤评估。
func aftermath(incident: Dictionary, opts: Dictionary = {}) -> Dictionary:
	incident["stage"] = STAGE_AFTERMATH
	var command: float = clampf(float(incident.get("command_quality", 0.7)), 0.0, 1.0)
	var deaths: int = int(incident.get("deaths", 0))
	var fault: String = ""
	var penalty: int = 0
	if command < COMMAND_FAULT_LINE and deaths > 0:
		fault = "command_fault"
		penalty = int(round(float(deaths) * 10000.0 * (COMMAND_FAULT_LINE - command)))
	elif bool(incident.get("secondary", false)) and bool(opts.get("blamed", true)):
		fault = "secondary_negligence"
		penalty = int(round(float(deaths) * 5000.0))
	incident["fault"] = fault
	var trauma: float = clampf(float(deaths) * 0.02 + float(incident.get("responder_casualties", 0)) * 0.1, 0.0, 1.0)
	return {
		"ok": true, "stage": incident["stage"], "fault": fault, "penalty": penalty,
		"psych_trauma": trauma, "deaths": deaths,
		"rescued": int(incident.get("rescued", 0)),
	}


## 推进状态机：报警 → 出警 → 救援 → 善后。
func advance(incident: Dictionary, opts: Dictionary = {}, rng = null) -> Dictionary:
	match str(incident.get("stage", STAGE_ALARM)):
		STAGE_ALARM:
			return dispatch(incident, opts)
		STAGE_DISPATCH:
			return rescue(incident, opts)
		STAGE_RESCUE:
			return aftermath(incident, opts)
		_:
			return {"ok": false, "reason": "terminal", "stage": incident["stage"]}


# --- 志愿救援 ---

func new_volunteer_org(name: String, opts: Dictionary = {}) -> Dictionary:
	return {
		"name": name,
		"volunteers": maxi(0, int(opts.get("volunteers", 0))),
		"equipment": maxi(0, int(opts.get("equipment", 0))),
		"funds": maxi(0, int(opts.get("funds", 0))),
		"reputation": clampf(float(opts.get("reputation", 0.3)), 0.0, 1.0),
	}


## 采购救援设备。
func purchase_equipment(org: Dictionary, item: String, cost: int) -> Dictionary:
	var c: int = maxi(0, cost)
	if int(org.get("funds", 0)) < c:
		return {"ok": false, "reason": "insufficient_funds"}
	org["funds"] = int(org["funds"]) - c
	org["equipment"] = int(org.get("equipment", 0)) + 1
	var items: Array = org.get("items", [])
	items.append(item)
	org["items"] = items
	return {"ok": true, "equipment": int(org["equipment"]), "funds": int(org["funds"])}


func recruit_volunteers(org: Dictionary, count: int) -> Dictionary:
	org["volunteers"] = maxi(0, int(org.get("volunteers", 0)) + count)
	return {"ok": true, "volunteers": int(org["volunteers"])}


## 志愿支援出警：志愿者与设备越多，响应时间越短。
func volunteer_dispatch(org: Dictionary, incident: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var merged: Dictionary = opts.duplicate()
	merged["volunteers"] = int(opts.get("volunteers", org.get("volunteers", 0)))
	merged["equipment_level"] = clampf(float(incident.get("equipment_level", 0.5)) + float(org.get("equipment", 0)) * 0.02, 0.0, 1.0)
	incident["equipment_level"] = float(merged["equipment_level"])
	return dispatch(incident, merged)


# --- 序列化 ---

func to_dict(state: Dictionary) -> Dictionary:
	return state.duplicate(true)


func from_dict(data: Dictionary) -> Dictionary:
	return data.duplicate(true)
