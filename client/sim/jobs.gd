class_name JobSystem
extends RefCounted
## 职业树、求职面试、工作结算与晋升退休（R13、R47；design D7）。
##
## 职责：
##   - 可扩展职业目录：按行业分树，岗位定义学历/技能/证书要求、薪资、工时、
##     晋升链、声望与招聘信息，岗位数量随内容包扩展且不设上限（R13.1、R47.9）；
##   - 求职与面试：依据条件列出可应聘岗位并支持面试掷骰（R13.3）；
##   - 工作结算：扣除体力与心情、按日结算工资，心情过低降低效率（R13.4、R13.7）；
##   - 试用转正、跳槽、加班、请假、失业救济与退休（R13.6）；
##   - 年结算提供升职机会（R13.5）。
##
## 设计取舍：
##   - 岗位定义（JobDef）为只读字典，运行期由内容包注册；起始目录保证可玩与测试；
##   - 就业状态存于 player["job"]（对齐 player.schema 的 job 字段）；
##   - 薪资为月薪，最小货币单位整数（BaselineGenerated.MONEY_MINOR_SCALE）；
##     工资经 EconomySystem.transfer 由雇主账户结算给员工账户，保证货币守恒。

const BaselineScript = preload("res://sim/baseline.gd")

const MINUTES_PER_YEAR: float = 365.25 * 1440.0
const DAYS_PER_MONTH: float = 30.0

## 学历顺序（高学历满足低学历要求；与 EducationSystem 口径一致）。
const DEGREE_ORDER: Array = [
	"edu.kindergarten", "edu.primary", "edu.junior", "edu.high_school",
	"edu.college", "edu.bachelor", "edu.master", "edu.doctor",
]

## 行业（可随内容包扩展）。
const INDUSTRIES: Array = [
	"agriculture", "industry", "construction", "transport", "it", "finance",
	"medical", "education", "law", "service", "entertainment", "media",
	"government", "military", "research", "art", "sports", "catering",
	"retail", "handicraft", "mining", "professional", "emerging",
]

const STATUS_UNEMPLOYED: String = "unemployed"
const STATUS_PROBATION: String = "probation"
const STATUS_REGULAR: String = "regular"
const STATUS_RETIRED: String = "retired"

const DEF_REQUIRED: Array = ["id", "name", "industry", "base_salary"]
const DEF_DEFAULTS: Dictionary = {
	"education": [],
	"skills": {},
	"licenses": [],
	"hours_per_day": 8.0,
	"promotion_chain": [],
	"prestige": 30.0,
	"min_age": 16,
	"max_age": 70,
	"min_health": 20.0,
	"military": false,
}

const PROBATION_DAYS: int = 90
const WORK_STAMINA_PER_HOUR: float = 6.0
const WORK_MOOD_PER_HOUR: float = 1.5
const MOOD_THRESHOLD: float = 40.0
const PERFORMANCE_GAIN_PER_HOUR: float = 0.25
const PERFORMANCE_DECAY_PER_DAY: float = 0.1
const PROMOTION_PERFORMANCE_MIN: float = 70.0
const PROMOTION_INTERNAL_REP_MIN: float = 60.0
const PROMOTION_BASE_CHANCE: float = 0.55
const INTERVIEW_CHARM_WEIGHT: float = 0.15
const INTERVIEW_LUCK_WEIGHT: float = 0.1
const RETIREMENT_YEARS_REQUIRED: float = 20.0
const RETIREMENT_PENSION_RATE: float = 0.02

var _defs: Dictionary = {}   # id -> def


# --- 目录 ---

## 注册岗位定义；缺必填字段或行业非法返回 {}。
func register(def: Dictionary) -> Dictionary:
	for key in DEF_REQUIRED:
		if not def.has(key):
			return {}
	if not INDUSTRIES.has(str(def["industry"])):
		return {}
	var full: Dictionary = DEF_DEFAULTS.duplicate(true)
	for k in def.keys():
		full[k] = def[k]
	full["id"] = str(full["id"])
	full["name"] = str(full["name"])
	full["industry"] = str(full["industry"])
	full["base_salary"] = maxi(0, int(full["base_salary"]))
	full["hours_per_day"] = clampf(float(full["hours_per_day"]), 0.0, 24.0)
	full["prestige"] = clampf(float(full["prestige"]), 0.0, 100.0)
	full["min_age"] = int(full["min_age"])
	full["max_age"] = int(full["max_age"])
	full["min_health"] = clampf(float(full["min_health"]), 0.0, 100.0)
	full["military"] = bool(full["military"])
	_defs[full["id"]] = full
	return full


func register_many(defs: Array) -> int:
	var n: int = 0
	for d in defs:
		if d is Dictionary and not register(d).is_empty():
			n += 1
	return n


func has_def(id: String) -> bool:
	return _defs.has(id)


func get_def(id: String) -> Dictionary:
	return _defs.get(id, {})


func def_count() -> int:
	return _defs.size()


func ids() -> Array:
	var out: Array = _defs.keys()
	out.sort()
	return out


func by_industry(industry: String) -> Array:
	var out: Array = []
	for id in ids():
		if str((_defs[id] as Dictionary)["industry"]) == industry:
			out.append(_defs[id])
	return out


func is_military(id: String) -> bool:
	var d: Dictionary = get_def(id)
	return bool(d.get("military", false))


## 内置起步目录（内容包补齐属任务 50；此处保证可玩与测试）。
## 同一条晋升链的岗位都登记该链，链内顺序即晋升顺序。
func register_starter_catalog() -> int:
	var prog: Array = ["job.junior_programmer", "job.programmer", "job.senior_programmer", "job.architect"]
	var bank: Array = ["job.teller", "job.financial_analyst", "job.fund_manager"]
	var med: Array = ["job.nurse", "job.doctor", "job.chief_physician"]
	var edu: Array = ["job.teacher", "job.professor"]
	var serv: Array = ["job.waiter", "job.chef"]
	var gov: Array = ["job.civil_servant", "job.section_chief"]
	var ret: Array = ["job.clerk", "job.store_manager"]
	var ind: Array = ["job.worker", "job.foreman", "job.factory_manager"]
	var con: Array = ["job.construction_worker", "job.site_supervisor", "job.project_manager"]
	return register_many([
		{"id": "job.farmer", "name": "农民", "industry": "agriculture", "base_salary": 400000, "prestige": 20.0, "promotion_chain": ["job.farmer"]},
		{"id": "job.worker", "name": "普工", "industry": "industry", "base_salary": 450000, "prestige": 22.0, "promotion_chain": ind},
		{"id": "job.foreman", "name": "车间主任", "industry": "industry", "base_salary": 800000, "prestige": 45.0, "promotion_chain": ind},
		{"id": "job.factory_manager", "name": "厂长", "industry": "industry", "base_salary": 1500000, "prestige": 62.0, "promotion_chain": ind},
		{"id": "job.construction_worker", "name": "建筑工", "industry": "construction", "base_salary": 500000, "prestige": 22.0, "promotion_chain": con},
		{"id": "job.site_supervisor", "name": "施工员", "industry": "construction", "base_salary": 900000, "prestige": 45.0, "promotion_chain": con},
		{"id": "job.project_manager", "name": "项目经理", "industry": "construction", "base_salary": 1800000, "prestige": 65.0, "promotion_chain": con},
		{"id": "job.driver", "name": "司机", "industry": "transport", "base_salary": 600000, "prestige": 25.0, "licenses": ["license.driver_c1"], "promotion_chain": ["job.driver"]},
		{"id": "job.junior_programmer", "name": "初级程序员", "industry": "it", "base_salary": 1200000, "prestige": 45.0, "skills": {"skill.programming": 3}, "education": ["edu.bachelor"], "promotion_chain": prog},
		{"id": "job.programmer", "name": "程序员", "industry": "it", "base_salary": 2000000, "prestige": 55.0, "skills": {"skill.programming": 6}, "education": ["edu.bachelor"], "promotion_chain": prog},
		{"id": "job.senior_programmer", "name": "高级程序员", "industry": "it", "base_salary": 3500000, "prestige": 70.0, "skills": {"skill.programming": 10}, "education": ["edu.bachelor"], "promotion_chain": prog},
		{"id": "job.architect", "name": "架构师", "industry": "it", "base_salary": 6000000, "prestige": 85.0, "skills": {"skill.programming": 14}, "education": ["edu.bachelor"], "promotion_chain": prog},
		{"id": "job.teller", "name": "银行柜员", "industry": "finance", "base_salary": 700000, "prestige": 40.0, "education": ["edu.bachelor"], "promotion_chain": bank},
		{"id": "job.financial_analyst", "name": "金融分析师", "industry": "finance", "base_salary": 1500000, "prestige": 60.0, "education": ["edu.bachelor"], "skills": {"skill.finance": 5}, "promotion_chain": bank},
		{"id": "job.fund_manager", "name": "基金经理", "industry": "finance", "base_salary": 4000000, "prestige": 82.0, "education": ["edu.master"], "skills": {"skill.finance": 10}, "promotion_chain": bank},
		{"id": "job.nurse", "name": "护士", "industry": "medical", "base_salary": 800000, "prestige": 45.0, "licenses": ["license.nurse"], "promotion_chain": med},
		{"id": "job.doctor", "name": "医生", "industry": "medical", "base_salary": 2000000, "prestige": 72.0, "licenses": ["license.doctor"], "education": ["edu.bachelor"], "promotion_chain": med},
		{"id": "job.chief_physician", "name": "主任医师", "industry": "medical", "base_salary": 5000000, "prestige": 90.0, "licenses": ["license.doctor"], "education": ["edu.master"], "promotion_chain": med},
		{"id": "job.teacher", "name": "教师", "industry": "education", "base_salary": 800000, "prestige": 55.0, "licenses": ["license.teacher"], "education": ["edu.bachelor"], "promotion_chain": edu},
		{"id": "job.professor", "name": "教授", "industry": "education", "base_salary": 2500000, "prestige": 88.0, "education": ["edu.doctor"], "skills": {"skill.academic": 10}, "promotion_chain": edu},
		{"id": "job.lawyer", "name": "律师", "industry": "law", "base_salary": 1500000, "prestige": 70.0, "licenses": ["license.lawyer"], "education": ["edu.bachelor"], "promotion_chain": ["job.lawyer"]},
		{"id": "job.waiter", "name": "服务员", "industry": "service", "base_salary": 400000, "prestige": 18.0, "promotion_chain": serv},
		{"id": "job.chef", "name": "厨师", "industry": "catering", "base_salary": 800000, "prestige": 40.0, "promotion_chain": serv},
		{"id": "job.actor", "name": "演员", "industry": "entertainment", "base_salary": 1000000, "prestige": 68.0, "promotion_chain": ["job.actor"]},
		{"id": "job.journalist", "name": "记者", "industry": "media", "base_salary": 900000, "prestige": 55.0, "promotion_chain": ["job.journalist"]},
		{"id": "job.civil_servant", "name": "公务员", "industry": "government", "base_salary": 800000, "prestige": 65.0, "education": ["edu.bachelor"], "promotion_chain": gov},
		{"id": "job.section_chief", "name": "科长", "industry": "government", "base_salary": 1500000, "prestige": 80.0, "education": ["edu.bachelor"], "promotion_chain": gov},
		{"id": "job.soldier", "name": "军人", "industry": "military", "base_salary": 600000, "prestige": 60.0, "min_age": 18, "max_age": 24, "military": true, "promotion_chain": ["job.soldier"]},
		{"id": "job.researcher", "name": "研究员", "industry": "research", "base_salary": 1200000, "prestige": 72.0, "education": ["edu.master"], "skills": {"skill.academic": 5}, "promotion_chain": ["job.researcher"]},
		{"id": "job.painter", "name": "画家", "industry": "art", "base_salary": 600000, "prestige": 50.0, "promotion_chain": ["job.painter"]},
		{"id": "job.athlete", "name": "运动员", "industry": "sports", "base_salary": 1000000, "prestige": 65.0, "min_health": 60.0, "promotion_chain": ["job.athlete"]},
		{"id": "job.clerk", "name": "店员", "industry": "retail", "base_salary": 450000, "prestige": 20.0, "promotion_chain": ret},
		{"id": "job.store_manager", "name": "店长", "industry": "retail", "base_salary": 1200000, "prestige": 50.0, "skills": {"skill.management": 4}, "promotion_chain": ret},
		{"id": "job.craftsman", "name": "手工艺人", "industry": "handicraft", "base_salary": 600000, "prestige": 40.0, "promotion_chain": ["job.craftsman"]},
		{"id": "job.miner", "name": "矿工", "industry": "mining", "base_salary": 700000, "prestige": 25.0, "min_health": 40.0, "promotion_chain": ["job.miner"]},
	])


# --- 资格判定 ---

func _skill_levels(player: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var skills: Variant = player.get("skills", [])
	if skills is Array:
		for s in (skills as Array):
			if s is Dictionary:
				out[str((s as Dictionary).get("content_key", ""))] = int((s as Dictionary).get("level", 0))
	return out


func _credential_keys(player: Dictionary, which: String) -> Array:
	var out: Array = []
	var creds: Variant = player.get(which, [])
	if creds is Array:
		for c in (creds as Array):
			if c is Dictionary:
				out.append(str((c as Dictionary).get("content_key", "")))
	return out


## 学历是否达到要求：高学历满足低学历要求；非学历条目按精确匹配。
func _has_degree_at_least(player: Dictionary, required: String) -> bool:
	var req_rank: int = DEGREE_ORDER.find(required)
	var creds: Variant = player.get("education", [])
	if creds is Array:
		for c in (creds as Array):
			if not (c is Dictionary):
				continue
			if str((c as Dictionary).get("status", "")) != "graduated":
				continue
			var key: String = str((c as Dictionary).get("content_key", ""))
			if req_rank < 0:
				if key == required:
					return true
			elif DEGREE_ORDER.find(key) >= req_rank:
				return true
	return false


func _age_years(player: Dictionary, now_minute: int) -> float:
	if now_minute >= 0 and player.has("birth_minutes"):
		return maxf(0.0, (float(now_minute) - float(player["birth_minutes"])) / MINUTES_PER_YEAR)
	if player.has("age"):
		return float(player["age"])
	return -1.0


## 检查玩家是否满足岗位准入；返回 {ok, missing:[...]}。opts.now_minute 用于年龄校验。
func matches_requirements(player: Dictionary, job_id: String, opts: Dictionary = {}) -> Dictionary:
	var def: Dictionary = get_def(job_id)
	if def.is_empty():
		return {"ok": false, "missing": ["job_not_found"]}
	var missing: Array = []
	for e in (def["education"] as Array):
		if not _has_degree_at_least(player, str(e)):
			missing.append("education:" + str(e))
	var licenses: Array = _credential_keys(player, "licenses")
	for l in (def["licenses"] as Array):
		if not licenses.has(str(l)):
			missing.append("license:" + str(l))
	var skills: Dictionary = _skill_levels(player)
	var req_skills: Dictionary = def["skills"]
	for k in req_skills.keys():
		if int(skills.get(str(k), 0)) < int(req_skills[k]):
			missing.append("skill:" + str(k))
	var now_minute: int = int(opts.get("now_minute", -1))
	var age: float = _age_years(player, now_minute)
	if age >= 0.0 and (age < float(def["min_age"]) or age > float(def["max_age"])):
		missing.append("age")
	var health: float = _attr(player, "physiological", "health", 100.0)
	if health < float(def["min_health"]):
		missing.append("health")
	return {"ok": missing.is_empty(), "missing": missing}


func _attr(player: Dictionary, group: String, key: String, default_value: float) -> float:
	var attrs: Variant = player.get("attrs", {})
	if attrs is Dictionary:
		var g: Variant = (attrs as Dictionary).get(group, {})
		if g is Dictionary:
			return float((g as Dictionary).get(key, default_value))
	return default_value


# --- 求职与面试 ---

## 面试得分 0..100：技能匹配 + 学历 + 魅力 + 运气 − 岗位声望门槛。
func interview_score(player: Dictionary, job_id: String, rng, opts: Dictionary = {}) -> float:
	var def: Dictionary = get_def(job_id)
	if def.is_empty():
		return 0.0
	var req_skills: Dictionary = def["skills"]
	var skills: Dictionary = _skill_levels(player)
	var skill_score: float = 60.0
	if req_skills.size() > 0:
		var total: float = 0.0
		for k in req_skills.keys():
			total += clampf(float(skills.get(str(k), 0)) / maxf(1.0, float(req_skills[k])), 0.0, 1.0)
		skill_score = 100.0 * total / float(req_skills.size())
	var education_bonus: float = 0.0
	var education: Array = _credential_keys(player, "education")
	for e in (def["education"] as Array):
		if education.has(str(e)):
			education_bonus += 10.0
	var charm: float = _attr(player, "ability", "charm", 50.0)
	var luck: float = _attr(player, "ability", "luck", 50.0)
	var roll: float = 0.0
	if rng != null:
		roll = rng.next_float() * 20.0 - 10.0
	var score: float = (
		0.55 * skill_score
		+ education_bonus
		+ INTERVIEW_CHARM_WEIGHT * charm
		+ INTERVIEW_LUCK_WEIGHT * luck
		+ roll
		- 0.3 * float(def["prestige"])
	)
	return clampf(score, 0.0, 100.0)


## 列出可应聘岗位，按声望与薪资排序。opts.unemployment 影响通过门槛（此处仅过滤）。
func openings(player: Dictionary, opts: Dictionary = {}) -> Array:
	var out: Array = []
	for id in ids():
		var def: Dictionary = get_def(id)
		if is_military(id) and not bool(opts.get("include_military", false)):
			continue
		var req: Dictionary = matches_requirements(player, id, opts)
		if bool(req["ok"]):
			out.append(def)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["prestige"]) < float(b["prestige"]))
	return out


## 求职并面试；满足条件且面试达标即入职。返回 {ok, hired, score, reason, job}。
func apply(player: Dictionary, job_id: String, rng, minute: int, opts: Dictionary = {}) -> Dictionary:
	var req: Dictionary = matches_requirements(player, job_id, {"now_minute": minute})
	if not bool(req["ok"]):
		return {"ok": false, "hired": false, "reason": "unqualified", "missing": req["missing"]}
	var score: float = interview_score(player, job_id, rng, opts)
	var difficulty: float = float(opts.get("hire_difficulty", BaselineScript.EMPLOYMENT_BASE_HIRE_DIFFICULTY))
	var threshold: float = 45.0 + 35.0 * difficulty
	if score < threshold:
		return {"ok": true, "hired": false, "score": score, "reason": "rejected"}
	var hired: Dictionary = hire(player, job_id, minute, opts)
	return {"ok": true, "hired": true, "score": score, "job": hired}


## 直接入职（入职逻辑可被指令层复用）。opts.salary 可覆盖月薪。
func hire(player: Dictionary, job_id: String, minute: int, opts: Dictionary = {}) -> Dictionary:
	var def: Dictionary = get_def(job_id)
	if def.is_empty():
		return {}
	var salary: int = int(opts.get("salary", def["base_salary"]))
	var job: Dictionary = {
		"content_key": job_id,
		"title": str(def["name"]),
		"industry": str(def["industry"]),
		"salary": salary,
		"hired_minutes": minute,
		"performance": 50.0,
		"internal_reputation": 50.0,
		"status": STATUS_PROBATION,
		"probation_end_minutes": minute + PROBATION_DAYS * 1440,
		"last_paid_day": -1,
		"hours_worked_today": 0.0,
	}
	player["job"] = job
	return job


func current_job(player: Dictionary) -> Dictionary:
	var job: Variant = player.get("job", {})
	return job if job is Dictionary else {}


func is_employed(player: Dictionary) -> bool:
	var job: Dictionary = current_job(player)
	return not job.is_empty() and str(job.get("status", "")) != STATUS_RETIRED


func resign(player: Dictionary, _minute: int) -> Dictionary:
	var job: Dictionary = current_job(player)
	player["job"] = {}
	return {"ok": true, "from": job}


## 退休：按工龄与月薪计算一次性退休金（由雇主/社保账户支出，这里仅返回金额）。
func retire(player: Dictionary, minute: int, opts: Dictionary = {}) -> Dictionary:
	var job: Dictionary = current_job(player)
	if job.is_empty():
		return {"ok": false, "reason": "unemployed"}
	var worked_years: float = maxf(0.0, (float(minute) - float(job.get("hired_minutes", minute))) / MINUTES_PER_YEAR)
	var pension: int = int(float(job.get("salary", 0)) * RETIREMENT_PENSION_RATE * maxf(1.0, worked_years))
	job["status"] = STATUS_RETIRED
	player["job"] = job
	return {"ok": true, "pension": pension, "worked_years": worked_years, "voluntary": bool(opts.get("voluntary", true))}


# --- 工作结算 ---

## 心情过低降低效率：心情 >= 阈值时为 1，低于阈值线性降至 0.5（R13.7）。
func efficiency(player: Dictionary) -> float:
	var mood: float = _attr(player, "psychological", "mood", 100.0)
	if mood >= MOOD_THRESHOLD:
		return 1.0
	return 0.5 + 0.5 * (mood / MOOD_THRESHOLD)


## 执行工作 minutes 分钟：扣体力与心情、累计绩效。返回 {ok, efficiency, performance}。
func work(player: Dictionary, minutes: float, opts: Dictionary = {}) -> Dictionary:
	var job: Dictionary = current_job(player)
	if job.is_empty() or str(job.get("status", "")) == STATUS_RETIRED:
		return {"ok": false, "reason": "unemployed"}
	var hours: float = maxf(0.0, minutes) / 60.0
	var eff: float = efficiency(player)
	var stamina_drain: float = WORK_STAMINA_PER_HOUR * hours * float(opts.get("intensity", 1.0))
	var mood_drain: float = WORK_MOOD_PER_HOUR * hours * (1.5 - eff)
	_drain_attr(player, "physiological", "stamina", stamina_drain)
	_drain_attr(player, "psychological", "mood", mood_drain)
	var gain: float = PERFORMANCE_GAIN_PER_HOUR * hours * eff
	job["performance"] = clampf(float(job.get("performance", 50.0)) + gain, 0.0, 100.0)
	job["hours_worked_today"] = float(job.get("hours_worked_today", 0.0)) + hours
	player["job"] = job
	return {"ok": true, "efficiency": eff, "performance": float(job["performance"]), "hours": hours}


func _drain_attr(player: Dictionary, group: String, key: String, amount: float) -> void:
	var attrs: Variant = player.get("attrs", {})
	if attrs is Dictionary:
		var g: Variant = (attrs as Dictionary).get(group, {})
		if g is Dictionary:
			(g as Dictionary)[key] = clampf(float((g as Dictionary).get(key, 0.0)) - amount, 0.0, 100.0)


## 按日结算工资：由 employer_account 转给 employee_account（货币守恒，R13.4）。
func settle_day(player: Dictionary, economy, employee_account: String, employer_account: String, days: int = 1) -> Dictionary:
	var job: Dictionary = current_job(player)
	if job.is_empty() or str(job.get("status", "")) == STATUS_RETIRED:
		return {"ok": false, "reason": "unemployed", "paid": 0}
	if not economy.has_account(employer_account):
		return {"ok": false, "reason": "no_employer_account", "paid": 0}
	var wage_per_day: int = int(float(job.get("salary", 0)) / DAYS_PER_MONTH)
	var total: int = wage_per_day * maxi(0, days)
	var amount: int = mini(total, economy.liquid(employer_account))
	if amount > 0:
		economy.transfer(employer_account, employee_account, amount, "wage")
	job["last_paid_day"] = int(job.get("last_paid_day", -1)) + maxi(0, days)
	job["hours_worked_today"] = 0.0
	player["job"] = job
	var full: bool = amount >= total
	return {"ok": full, "paid": amount, "expected": total, "arrears": total - amount}


func tick_day(player: Dictionary) -> void:
	var job: Dictionary = current_job(player)
	if job.is_empty() or str(job.get("status", "")) == STATUS_RETIRED:
		return
	job["performance"] = clampf(float(job.get("performance", 50.0)) - PERFORMANCE_DECAY_PER_DAY, 0.0, 100.0)
	job["hours_worked_today"] = 0.0


# --- 晋升 ---

func eligible_promotion(player: Dictionary) -> bool:
	var job: Dictionary = current_job(player)
	if job.is_empty() or str(job.get("status", "")) == STATUS_RETIRED:
		return false
	if str(job.get("status", "")) == STATUS_PROBATION:
		return false
	return (
		float(job.get("performance", 0.0)) >= PROMOTION_PERFORMANCE_MIN
		and float(job.get("internal_reputation", 0.0)) >= PROMOTION_INTERNAL_REP_MIN
	)


## 晋升到晋升链的下一个岗位；无下一级返回 reason=max_rank。
func promote(player: Dictionary, minute: int) -> Dictionary:
	var job: Dictionary = current_job(player)
	if job.is_empty():
		return {"ok": false, "reason": "unemployed"}
	var def: Dictionary = get_def(str(job.get("content_key", "")))
	if def.is_empty():
		return {"ok": false, "reason": "no_def"}
	var chain: Array = def["promotion_chain"]
	var idx: int = chain.find(str(job["content_key"]))
	if idx < 0 or idx + 1 >= chain.size():
		return {"ok": false, "reason": "max_rank"}
	var next_id: String = str(chain[idx + 1])
	var next_def: Dictionary = get_def(next_id)
	var from_id: String = str(job["content_key"])
	var new_job: Dictionary = {
		"content_key": next_id,
		"title": str(next_def["name"]),
		"industry": str(next_def["industry"]),
		"salary": int(next_def["base_salary"]),
		"hired_minutes": int(job.get("hired_minutes", minute)),
		"performance": 60.0,
		"internal_reputation": float(job.get("internal_reputation", 50.0)),
		"status": STATUS_REGULAR,
		"probation_end_minutes": int(job.get("probation_end_minutes", minute)),
		"last_paid_day": int(job.get("last_paid_day", -1)),
		"hours_worked_today": 0.0,
	}
	player["job"] = new_job
	return {"ok": true, "from": from_id, "to": next_id, "salary": int(next_def["base_salary"])}


## 年结算：达标且掷骰通过则给出升职机会（R13.5）。返回是否晋升。
func annual_promotion_check(player: Dictionary, rng, minute: int, opts: Dictionary = {}) -> Dictionary:
	if not eligible_promotion(player):
		return {"ok": false, "reason": "not_eligible"}
	var roll: float = rng.next_float() if rng != null else 0.5
	var chance: float = float(opts.get("chance", PROMOTION_BASE_CHANCE))
	if roll <= chance:
		var r: Dictionary = promote(player, minute)
		r["roll"] = roll
		return r
	return {"ok": false, "reason": "no_opening", "roll": roll}


func regularize(player: Dictionary, minute: int) -> Dictionary:
	var job: Dictionary = current_job(player)
	if job.is_empty():
		return {"ok": false, "reason": "unemployed"}
	if int(job.get("probation_end_minutes", 0)) <= minute:
		job["status"] = STATUS_REGULAR
		player["job"] = job
		return {"ok": true}
	return {"ok": false, "reason": "still_probation"}


func to_dict() -> Dictionary:
	return {"defs": _defs.duplicate(true)}
