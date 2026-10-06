class_name LateTechSystem
extends RefCounted
## 后期科技（R68；design D24）。
##
## 覆盖：
##   - 科技阶段：信息 → 智能 → 星际；逐级解锁职业、设备、场所与生活方式，并提供
##     `unlock_stage` / `unlocked` 查询 / 时代解锁判定（与 D1 时代键衔接）；
##   - 职业路径：航天、深海勘探、机器人运维、AI 训练/伦理、生物科技，含技能门槛与薪资；
##   - 风险收益：太空旅行/空间站/深海/星球殖民等高风险高回报路径，含事故与伤亡概率；
##   - 自动化冲击：提升效率的同时淘汰传统岗位并创造新岗位，产生失业率与社会保障议题、社会事件；
##   - 太空与极端环境：失重/辐射/深海高压的健康惩罚（结构化返回供 D3 健康系统消费）；
##   - 生物科技与延寿：返回寿命增益（联动 D3/D45）；
##   - 边界：技术失业社会事件、气候难民、技术事故连锁、AI 伦理与失控。
##
## 设计取舍：
##   - 世界科技状态为纯数据 Dictionary；阶段与解锁集合可存读档；
##   - 阶段推进严格顺序解锁：不能跳级，但可由时代键批量同步；
##   - 随机项（事故/伤亡/AI 失控）由 opts 的 roll 或外部 rng 注入，缺省确定化，便于断言；
##   - 健康惩罚与寿命增益只以数值/结构化返回，不直接改写健康系统，保持解耦。

const STAGE_INFORMATION: String = "information"
const STAGE_INTELLIGENT: String = "intelligent"
const STAGE_INTERSTELLAR: String = "interstellar"

const STAGES: Array = ["information", "intelligent", "interstellar"]
const STAGE_INDEX: Dictionary = {"information": 0, "intelligent": 1, "interstellar": 2}

## 时代键 → 后期科技阶段索引；更早时代返回 -1（无后期科技）。
const ERA_STAGE: Dictionary = {"information": 0, "intelligent": 1, "interstellar": 2}

## 各阶段解锁内容。
const STAGE_DEFS: Dictionary = {
	"information": {
		"name": "信息", "era_key": "information",
		"jobs": ["robot_operator", "ai_trainer"],
		"equipment": ["server_farm"],
		"places": ["data_center"],
		"lifestyles": ["online_work"],
	},
	"intelligent": {
		"name": "智能", "era_key": "intelligent",
		"jobs": ["aerospace_astronaut", "aerospace_engineer", "deep_sea_explorer", "robot_operator", "ai_trainer", "ai_ethicist", "biotech_researcher"],
		"equipment": ["space_station", "deep_submersible"],
		"places": ["spaceport", "deep_sea_base"],
		"lifestyles": ["smart_home"],
	},
	"interstellar": {
		"name": "星际", "era_key": "interstellar",
		"jobs": ["space_miner", "colonist"],
		"equipment": ["starship"],
		"places": ["colony"],
		"lifestyles": ["spacefaring"],
	},
}

## 职业路径：所属阶段、技能门槛、薪资、基础风险。
const CAREERS: Dictionary = {
	"robot_operator": {"name": "机器人运维", "stage": "information", "skill": "skill.programming", "min_level": 6, "salary": 150000, "risk": 0.03},
	"ai_trainer": {"name": "AI 训练师", "stage": "information", "skill": "skill.data_analysis", "min_level": 8, "salary": 220000, "risk": 0.02},
	"aerospace_engineer": {"name": "航天工程师", "stage": "intelligent", "skill": "skill.engineering", "min_level": 10, "salary": 300000, "risk": 0.05},
	"aerospace_astronaut": {"name": "宇航员", "stage": "intelligent", "skill": "skill.physique", "min_level": 14, "salary": 500000, "risk": 0.15},
	"deep_sea_explorer": {"name": "深海勘探员", "stage": "intelligent", "skill": "skill.technical", "min_level": 10, "salary": 400000, "risk": 0.25},
	"ai_ethicist": {"name": "AI 伦理师", "stage": "intelligent", "skill": "skill.philosophy", "min_level": 12, "salary": 280000, "risk": 0.01},
	"biotech_researcher": {"name": "生物科技研究员", "stage": "intelligent", "skill": "skill.biology", "min_level": 12, "salary": 350000, "risk": 0.05},
	"space_miner": {"name": "太空矿工", "stage": "interstellar", "skill": "skill.engineering", "min_level": 8, "salary": 800000, "risk": 0.20},
	"colonist": {"name": "星球殖民者", "stage": "interstellar", "skill": "skill.survival", "min_level": 12, "salary": 600000, "risk": 0.30},
}

## 高风险高回报任务：阶段、技能门槛、基准回报、事故率、事故致死率、环境。
const MISSIONS: Dictionary = {
	"space_travel": {"name": "太空旅行", "stage": "intelligent", "min_skill": 8, "reward": 1000000, "accident": 0.20, "casualty": 0.05, "environment": "weightless"},
	"space_station_work": {"name": "空间站工作", "stage": "intelligent", "min_skill": 10, "reward": 2000000, "accident": 0.30, "casualty": 0.08, "environment": "weightless"},
	"deep_sea_operation": {"name": "深海作业", "stage": "intelligent", "min_skill": 10, "reward": 1500000, "accident": 0.28, "casualty": 0.06, "environment": "high_pressure"},
	"planet_colonization": {"name": "星球殖民", "stage": "interstellar", "min_skill": 14, "reward": 5000000, "accident": 0.35, "casualty": 0.12, "environment": "radiation"},
}

## 极端环境健康影响基线（每次暴露单位）。
const ENVIRONMENTS: Dictionary = {
	"weightless": {"name": "失重", "bone_loss": 0.02, "muscle_loss": 0.02, "radiation": 0.0, "pressure": 0.0},
	"radiation": {"name": "辐射", "bone_loss": 0.0, "muscle_loss": 0.005, "radiation": 0.05, "pressure": 0.0},
	"high_pressure": {"name": "深海高压", "bone_loss": 0.0, "muscle_loss": 0.01, "radiation": 0.0, "pressure": 0.04},
}


func _roll(forced: float, rng) -> float:
	if forced >= 0.0:
		return clampf(forced, 0.0, 1.0)
	if rng != null:
		return rng.next_float()
	return 0.0


# --- 阶段与解锁 ---

func new_state(opts: Dictionary = {}) -> Dictionary:
	var start: int = clampi(int(opts.get("stage_index", 0)), 0, STAGES.size() - 1)
	return {
		"stage_index": start,
		"unlocked_stages": STAGES.slice(0, start + 1),
		"lifespan_bonus": 0.0,
		"unemployment_rate": 0.0,
		"warming": 0.0,
		"events": [],
	}


func stage_count() -> int:
	return STAGES.size()


func stage_def(key: String) -> Dictionary:
	return (STAGE_DEFS.get(key, {}) as Dictionary).duplicate(true)


func current_stage(state: Dictionary) -> String:
	return str(STAGES[clampi(int(state.get("stage_index", 0)), 0, STAGES.size() - 1)])


func stage_index(key: String) -> int:
	return int(STAGE_INDEX.get(key, -1))


## 时代键 → 阶段索引；更早时代返回 -1。
func stage_index_for_era(era_key: String) -> int:
	return int(ERA_STAGE.get(era_key, -1))


## 时代解锁判定：给定时代键，判断是否已达到可解锁的目标阶段。
func can_unlock_by_era(state: Dictionary, era_key: String) -> bool:
	var target: int = stage_index_for_era(era_key)
	if target < 0:
		return false
	return target >= int(state.get("stage_index", 0))


## 解锁下一阶段；严格顺序，不能跳级。
func unlock_stage(state: Dictionary, stage_or_key: Variant) -> Dictionary:
	var key: String = _key_of(stage_or_key)
	if not STAGE_INDEX.has(key):
		return {"ok": false, "reason": "unknown_stage"}
	var idx: int = int(STAGE_INDEX[key])
	var current: int = int(state.get("stage_index", 0))
	if idx <= current:
		return {"ok": false, "reason": "already_unlocked", "stage": key}
	if idx > current + 1:
		return {"ok": false, "reason": "locked", "required": STAGES[current + 1]}
	state["stage_index"] = idx
	state["unlocked_stages"] = STAGES.slice(0, idx + 1)
	return {"ok": true, "stage": key, "unlocked_stages": (state["unlocked_stages"] as Array).duplicate()}


## 按时代键同步阶段（不降级）。
func sync_with_era(state: Dictionary, era_key: String) -> Dictionary:
	var target: int = stage_index_for_era(era_key)
	if target < 0:
		return {"ok": false, "reason": "era_before_late_tech"}
	while int(state.get("stage_index", 0)) < target:
		var r: Dictionary = unlock_stage(state, STAGES[int(state["stage_index"]) + 1])
		if not bool(r.get("ok", false)):
			break
	return {"ok": true, "stage_index": int(state["stage_index"]), "stage": current_stage(state)}


## 查询某阶段是否解锁了某类内容。category ∈ jobs/equipment/places/lifestyles。
func unlocked(state: Dictionary, category: String, key: String) -> bool:
	var last: int = int(state.get("stage_index", 0))
	for i in range(last + 1):
		var def: Dictionary = STAGE_DEFS[STAGES[i]]
		if (def.get(category, []) as Array).has(key):
			return true
	return false


func _key_of(stage_or_key: Variant) -> String:
	if typeof(stage_or_key) == TYPE_INT or typeof(stage_or_key) == TYPE_FLOAT:
		var i: int = clampi(int(stage_or_key), 0, STAGES.size() - 1)
		return str(STAGES[i])
	return str(stage_or_key)


# --- 职业路径 ---

func careers_for_stage(stage_key: String) -> Array:
	var out: Array = []
	for k in CAREERS.keys():
		if str((CAREERS[k] as Dictionary)["stage"]) == stage_key:
			out.append(k)
	return out


func career_unlocked(state: Dictionary, career_key: String) -> bool:
	if not CAREERS.has(career_key):
		return false
	var def: Dictionary = CAREERS[career_key]
	return int(STAGE_INDEX.get(str(def["stage"]), 99)) <= int(state.get("stage_index", 0))


## 应聘职业：校验阶段解锁与技能门槛，返回薪资与风险。
func apply_for_career(state: Dictionary, career_key: String, skill_level: int, opts: Dictionary = {}) -> Dictionary:
	if not CAREERS.has(career_key):
		return {"ok": false, "reason": "unknown_career"}
	if not career_unlocked(state, career_key):
		return {"ok": false, "reason": "stage_locked"}
	var def: Dictionary = CAREERS[career_key]
	if skill_level < int(def["min_level"]):
		return {"ok": false, "reason": "skill_too_low", "required": int(def["min_level"])}
	return {
		"ok": true, "career": career_key, "name": str(def["name"]),
		"salary": int(def["salary"]), "risk": float(def["risk"]),
	}


# --- 高风险任务 ---

## 执行高风险高回报任务：事故/伤亡由任务风险与技能缓解共同决定。
func risk_mission(state: Dictionary, mission_key: String, skill_level: int, opts: Dictionary = {}, rng = null) -> Dictionary:
	if not MISSIONS.has(mission_key):
		return {"ok": false, "reason": "unknown_mission"}
	var def: Dictionary = MISSIONS[mission_key]
	if int(STAGE_INDEX.get(str(def["stage"]), 99)) > int(state.get("stage_index", 0)):
		return {"ok": false, "reason": "stage_locked"}
	if skill_level < int(def["min_skill"]):
		return {"ok": false, "reason": "skill_too_low", "required": int(def["min_skill"])}
	var mitigation: float = clampf(float(skill_level) / 20.0, 0.0, 1.0)
	var accident_prob: float = clampf(float(def["accident"]) * (1.0 - mitigation * 0.5), 0.01, 0.95)
	var roll: float = _roll(float(opts.get("roll", -1.0)), rng)
	var accident: bool = roll < accident_prob
	var casualty: bool = false
	if accident:
		var casualty_roll: float = _roll(float(opts.get("casualty_roll", -1.0)), rng)
		casualty = casualty_roll < float(def["casualty"])
	var reward: int = int(def["reward"]) if not casualty else 0
	var env_effect: Dictionary = {}
	if accident:
		env_effect = extreme_environment_effect(str(def["environment"]), 1.0, opts)
	return {
		"ok": true, "mission": mission_key, "accident": accident, "casualty": casualty,
		"accident_probability": accident_prob, "reward": reward,
		"environment_effect": env_effect,
	}


# --- 自动化冲击 ---

## 自动化：效率提升，淘汰传统岗位并创造新岗位，可能引发失业与社会保障议题。
func automation_impact(state: Dictionary, efficiency: float, opts: Dictionary = {}) -> Dictionary:
	var e: float = clampf(efficiency, 0.0, 2.0)
	var traditional: float = maxf(1.0, float(opts.get("traditional_jobs", 100000.0)))
	var jobs_lost: int = int(round(traditional * clampf(e * 0.3, 0.0, 0.8)))
	var jobs_created: int = int(round(float(opts.get("new_job_capacity", 40000.0)) * clampf(e * 0.6, 0.0, 1.5)))
	var net: int = jobs_created - jobs_lost
	var rate: float = clampf(float(opts.get("base_unemployment", 0.05)) - float(net) / traditional, 0.0, 0.6)
	state["unemployment_rate"] = rate
	var issue: bool = rate >= float(opts.get("issue_threshold", 0.12))
	var events: Array = []
	if issue:
		events.append({"type": "unemployment_crisis", "rate": rate, "jobs_lost": jobs_lost})
	(state["events"] as Array).append_array(events)
	return {
		"ok": true, "efficiency": e, "jobs_lost": jobs_lost, "jobs_created": jobs_created,
		"net_jobs": net, "unemployment_rate": rate,
		"social_security_issue": issue, "events": events,
	}


# --- 极端环境 ---

## 极端环境暴露的健康惩罚。exposure 为暴露强度，tolerance 为适应/防护 0..1。
func extreme_environment_effect(environment: String, exposure: float, opts: Dictionary = {}) -> Dictionary:
	if not ENVIRONMENTS.has(environment):
		return {"ok": false, "reason": "unknown_environment"}
	var def: Dictionary = ENVIRONMENTS[environment]
	var factor: float = maxf(0.0, exposure) * (1.0 - clampf(float(opts.get("tolerance", 0.0)), 0.0, 0.9))
	var bone: float = float(def["bone_loss"]) * factor
	var muscle: float = float(def["muscle_loss"]) * factor
	var radiation: float = float(def["radiation"]) * factor
	var pressure: float = float(def["pressure"]) * factor
	return {
		"ok": true, "environment": environment,
		"bone_loss": bone, "muscle_loss": muscle,
		"radiation_dose": radiation, "pressure_damage": pressure,
		"health_penalty": bone + muscle + radiation * 2.0 + pressure,
	}


# --- 生物科技与延寿 ---

## 生物科技延寿：每百万投入增益约 2 年，伴随副作用风险（联动 D3/D45）。
func biotech_lifespan(state: Dictionary, investment: float, opts: Dictionary = {}) -> Dictionary:
	var inv: float = maxf(0.0, investment)
	var gain: float = clampf(inv / 1000000.0 * float(opts.get("years_per_million", 2.0)), 0.0, 20.0)
	var side_effect: float = clampf(inv / 1000000.0 * 0.05, 0.0, 0.8)
	state["lifespan_bonus"] = float(state.get("lifespan_bonus", 0.0)) + gain
	return {
		"ok": true, "lifespan_gain": gain,
		"total_bonus": float(state["lifespan_bonus"]), "side_effect_risk": side_effect,
	}


# --- 边界：气候难民、AI 伦理与事故连锁 ---

## 长期气候变化的难民潮（联动 D13）。
func climate_refugees(state: Dictionary, warming: float, opts: Dictionary = {}) -> Dictionary:
	var w: float = maxf(0.0, warming)
	var pop: float = maxf(1.0, float(opts.get("coastal_population", 1000000.0)))
	var rate: float = clampf((w - 1.0) * 0.05, 0.0, 0.5)
	var refugees: int = int(round(pop * rate))
	state["warming"] = w
	var events: Array = []
	if refugees > 0:
		events.append({"type": "climate_refugee", "count": refugees, "warming": w})
	(state["events"] as Array).append_array(events)
	return {"ok": true, "refugees": refugees, "warming": w, "events": events}


## AI 伦理失控与技术事故连锁（联动 D44 异常）。
func ai_ethics_incident(state: Dictionary, autonomy: float, opts: Dictionary = {}, rng = null) -> Dictionary:
	var a: float = clampf(autonomy, 0.0, 1.0)
	var prob: float = clampf(a * 0.5 + float(opts.get("risk", 0.0)), 0.0, 0.95)
	var roll: float = _roll(float(opts.get("roll", -1.0)), rng)
	var loss: bool = roll < prob
	var chain: Array = []
	if loss:
		chain.append({"type": "ai_loss_of_control", "autonomy": a})
		if bool(opts.get("critical", false)):
			chain.append({"type": "infrastructure_failure"})
		(state["events"] as Array).append_array(chain)
	return {"ok": true, "loss_of_control": loss, "chain": chain, "probability": prob}


func to_dict(state: Dictionary) -> Dictionary:
	return state.duplicate(true)


func from_dict(data: Dictionary) -> Dictionary:
	return data.duplicate(true)
