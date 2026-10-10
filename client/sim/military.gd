class_name MilitarySystem
extends RefCounted
## 军旅生涯：入伍、兵种、军衔、训练/驻防/任务、晋升、退役与拒征逃兵（R47.1-3；design D7）。
##
## 要点：
##   - 入伍校验年龄、健康、学历与政审（犯罪记录）；
##   - 兵种：陆、海、空、火箭、后勤、通信、特种，各有技能需求与晋升速度；
##   - 军衔细分：士兵/士官/尉官/校官/将官，各级有年限、考核与军功要求；
##   - 军旅循环：训练 → 驻防 → 任务/演习 → 军功/伤亡 → 晋升/转业；
##   - 在役限制部分民事自由；拒征或逃兵触发法律后果（联动 D12）。
##
## 设计取舍：
##   - 军籍状态存于 player["military"]；军衔为 RANKS 索引，替换时整表更新；
##   - 军功为累计值，各级设累计军功门槛，避免晋升时做减法；
##   - 伤亡只写入健康惩罚/击杀标记，最终死亡由生存系统统一裁定。

const BaselineScript = preload("res://sim/baseline.gd")

const MINUTES_PER_YEAR: float = 365.25 * 1440.0

const ENLIST_MIN_AGE: float = BaselineScript.MILITARY_ENLIST_MIN_AGE
const ENLIST_MAX_AGE: float = BaselineScript.MILITARY_ENLIST_MAX_AGE
const ENLIST_MIN_HEALTH: float = BaselineScript.MILITARY_ENLIST_MIN_HEALTH
const ENLIST_MIN_EDUCATION: String = "edu.high_school"

## 兵种：技能需求、晋升速度（>1 更快）、作战强度（影响伤亡与军功）。
const BRANCHES: Dictionary = {
	"army": {"name": "陆军", "skills": {"skill.physique": 3}, "promotion_speed": 1.0, "combat": 0.5},
	"navy": {"name": "海军", "skills": {"skill.physique": 3, "skill.technical": 2}, "promotion_speed": 0.95, "combat": 0.5},
	"air": {"name": "空军", "skills": {"skill.technical": 5}, "promotion_speed": 0.9, "combat": 0.6},
	"rocket": {"name": "火箭军", "skills": {"skill.technical": 5, "skill.academic": 4}, "promotion_speed": 0.85, "combat": 0.6},
	"logistics": {"name": "后勤", "skills": {"skill.management": 3}, "promotion_speed": 1.1, "combat": 0.25},
	"signal": {"name": "通信", "skills": {"skill.technical": 4}, "promotion_speed": 1.0, "combat": 0.3},
	"special": {"name": "特种", "skills": {"skill.physique": 6, "skill.willpower": 5}, "promotion_speed": 0.8, "combat": 0.9},
}

## 军衔表：grade ∈ soldier/nco/officer/field/general；min_years 为本级最低年限，
## merit_required 为累计军功门槛，pay 为月薪（最小货币单位）。
const RANKS: Array = [
	{"key": "private", "name": "列兵", "grade": "soldier", "min_years": 1.0, "merit_required": 0.0, "pay": 600000},
	{"key": "lance_corporal", "name": "上等兵", "grade": "soldier", "min_years": 1.0, "merit_required": 5.0, "pay": 700000},
	{"key": "corporal", "name": "下士", "grade": "nco", "min_years": 2.0, "merit_required": 15.0, "pay": 900000},
	{"key": "sergeant", "name": "中士", "grade": "nco", "min_years": 3.0, "merit_required": 30.0, "pay": 1200000},
	{"key": "staff_sergeant", "name": "上士", "grade": "nco", "min_years": 4.0, "merit_required": 50.0, "pay": 1600000},
	{"key": "sergeant_major", "name": "军士长", "grade": "nco", "min_years": 5.0, "merit_required": 80.0, "pay": 2200000},
	{"key": "second_lieutenant", "name": "少尉", "grade": "officer", "min_years": 3.0, "merit_required": 110.0, "pay": 2000000},
	{"key": "lieutenant", "name": "中尉", "grade": "officer", "min_years": 3.0, "merit_required": 150.0, "pay": 2600000},
	{"key": "captain", "name": "上尉", "grade": "officer", "min_years": 4.0, "merit_required": 200.0, "pay": 3300000},
	{"key": "major", "name": "少校", "grade": "field", "min_years": 4.0, "merit_required": 270.0, "pay": 4200000},
	{"key": "lieutenant_colonel", "name": "中校", "grade": "field", "min_years": 4.0, "merit_required": 350.0, "pay": 5200000},
	{"key": "colonel", "name": "上校", "grade": "field", "min_years": 5.0, "merit_required": 450.0, "pay": 6500000},
	{"key": "major_general", "name": "少将", "grade": "general", "min_years": 5.0, "merit_required": 600.0, "pay": 8500000},
	{"key": "lieutenant_general", "name": "中将", "grade": "general", "min_years": 5.0, "merit_required": 800.0, "pay": 11000000},
	{"key": "general", "name": "上将", "grade": "general", "min_years": 6.0, "merit_required": 1050.0, "pay": 14000000},
]

const STATUS_SERVING: String = "serving"
const STATUS_DISCHARGED: String = "discharged"
const STATUS_DESERTER: String = "deserter"

## 在役期间受限的民事动词（部分民事自由）。
const RESTRICTED_VERBS: Array = [
	"辞职", "跳槽", "创业", "注册公司", "参选", "入党", "移民", "出国", "罢工",
]

const MISSION_BASE_CASUALTY: float = BaselineScript.MILITARY_MISSION_BASE_CASUALTY
const MISSION_MERIT_BASE: float = BaselineScript.MILITARY_MISSION_MERIT_BASE
const TRAINING_MERIT_PER_DAY: float = BaselineScript.MILITARY_TRAINING_MERIT_PER_DAY
const GARRISON_MERIT_PER_YEAR: float = BaselineScript.MILITARY_GARRISON_MERIT_PER_YEAR
const DISCHARGE_PAY_PER_YEAR: float = BaselineScript.MILITARY_DISCHARGE_PAY_PER_YEAR   # 退役金 = 月薪 × 年数 × 系数（月数）


# --- 兵种与军衔 ---

func branches() -> Array:
	return BRANCHES.keys()


func has_branch(key: String) -> bool:
	return BRANCHES.has(key)


func rank_count() -> int:
	return RANKS.size()


func rank(index: int) -> Dictionary:
	if index < 0 or index >= RANKS.size():
		return {}
	return RANKS[index]


func rank_index_by_key(key: String) -> int:
	for i in RANKS.size():
		if str((RANKS[i] as Dictionary)["key"]) == key:
			return i
	return -1


func _skill_levels(player: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var skills: Variant = player.get("skills", [])
	if skills is Array:
		for s in (skills as Array):
			if s is Dictionary:
				out[str((s as Dictionary).get("content_key", ""))] = int((s as Dictionary).get("level", 0))
	return out


func _credential_keys(player: Dictionary) -> Array:
	var out: Array = []
	var creds: Variant = player.get("education", [])
	if creds is Array:
		for c in (creds as Array):
			if c is Dictionary:
				out.append(str((c as Dictionary).get("content_key", "")))
	return out


func _attr(player: Dictionary, group: String, key: String, default_value: float) -> float:
	var attrs: Variant = player.get("attrs", {})
	if attrs is Dictionary:
		var g: Variant = (attrs as Dictionary).get(group, {})
		if g is Dictionary:
			return float((g as Dictionary).get(key, default_value))
	return default_value


func _age_years(player: Dictionary, now_minute: int) -> float:
	if now_minute >= 0 and player.has("birth_minutes"):
		return maxf(0.0, (float(now_minute) - float(player["birth_minutes"])) / MINUTES_PER_YEAR)
	if player.has("age"):
		return float(player["age"])
	return -1.0


func military_state(player: Dictionary) -> Dictionary:
	var m: Variant = player.get("military", {})
	return m if m is Dictionary else {}


func is_serving(player: Dictionary) -> bool:
	return str(military_state(player).get("status", "")) == STATUS_SERVING


# --- 入伍 ---

## 校验入伍条件：年龄、健康、学历、政审、兵种技能、未在役。
func enlist_requirements(player: Dictionary, branch: String, opts: Dictionary = {}) -> Dictionary:
	var missing: Array = []
	if not BRANCHES.has(branch):
		return {"ok": false, "missing": ["branch_not_found"]}
	if is_serving(player):
		missing.append("already_serving")
	var now_minute: int = int(opts.get("now_minute", -1))
	var age: float = _age_years(player, now_minute)
	if age >= 0.0 and (age < ENLIST_MIN_AGE or age > ENLIST_MAX_AGE):
		missing.append("age")
	if _attr(player, "physiological", "health", 100.0) < ENLIST_MIN_HEALTH:
		missing.append("health")
	if not _credential_keys(player).has(ENLIST_MIN_EDUCATION):
		missing.append("education")
	var legal: Variant = player.get("legal", {})
	if legal is Dictionary and bool((legal as Dictionary).get("criminal_record", false)):
		missing.append("political_review")
	var branch_def: Dictionary = BRANCHES[branch]
	var skills: Dictionary = _skill_levels(player)
	var req: Dictionary = branch_def["skills"]
	for k in req.keys():
		if int(skills.get(str(k), 0)) < int(req[k]):
			missing.append("skill:" + str(k))
	return {"ok": missing.is_empty(), "missing": missing}


func enlist(player: Dictionary, branch: String, minute: int, opts: Dictionary = {}) -> Dictionary:
	var req: Dictionary = enlist_requirements(player, branch, {"now_minute": minute})
	if not bool(req["ok"]):
		return {"ok": false, "reason": "unqualified", "missing": req["missing"]}
	var state: Dictionary = {
		"branch": branch,
		"branch_name": str((BRANCHES[branch] as Dictionary)["name"]),
		"rank_index": 0,
		"rank_key": str((RANKS[0] as Dictionary)["key"]),
		"enlisted_minutes": minute,
		"rank_started_minutes": minute,
		"merits": 0.0,
		"casualties": 0,
		"status": STATUS_SERVING,
		"unit_id": str(opts.get("unit_id", "unit.%s" % branch)),
	}
	player["military"] = state
	return {"ok": true, "state": state}


# --- 军旅循环 ---

## 训练：积累少量军功并提升体质类技能经验（此处只记军功）。
func train(player: Dictionary, days: float) -> Dictionary:
	if not is_serving(player):
		return {"ok": false, "reason": "not_serving"}
	var state: Dictionary = military_state(player)
	state["merits"] = float(state.get("merits", 0.0)) + TRAINING_MERIT_PER_DAY * maxf(0.0, days)
	player["military"] = state
	return {"ok": true, "merits": float(state["merits"])}


## 驻防：按年累积军功（无风险）。
func garrison(player: Dictionary, years: float) -> Dictionary:
	if not is_serving(player):
		return {"ok": false, "reason": "not_serving"}
	var state: Dictionary = military_state(player)
	state["merits"] = float(state.get("merits", 0.0)) + GARRISON_MERIT_PER_YEAR * maxf(0.0, years)
	player["military"] = state
	return {"ok": true, "merits": float(state["merits"])}


## 任务/演习：按兵种作战强度掷骰，产生军功或伤亡（R47.1）。
func mission(player: Dictionary, rng, opts: Dictionary = {}) -> Dictionary:
	if not is_serving(player):
		return {"ok": false, "reason": "not_serving"}
	var state: Dictionary = military_state(player)
	var branch: Dictionary = BRANCHES.get(str(state["branch"]), {})
	var combat: float = float(branch.get("combat", 0.5))
	var difficulty: float = float(opts.get("difficulty", 1.0))
	var roll: float = rng.next_float() if rng != null else 0.5
	var casualty_chance: float = MISSION_BASE_CASUALTY * combat * difficulty
	var merit_gain: float = MISSION_MERIT_BASE * (0.5 + combat) * difficulty
	var outcome: String = "merit"
	var casualty: bool = false
	var kia: bool = false
	if roll < casualty_chance:
		outcome = "casualty"
		casualty = true
		state["casualties"] = int(state.get("casualties", 0)) + 1
		var wound: float = 20.0 + 40.0 * combat
		if roll < casualty_chance * 0.25:
			kia = true
			_set_health(player, 0.0)
		else:
			_set_health(player, maxf(0.0, _attr(player, "physiological", "health", 100.0) - wound))
		merit_gain *= 1.5   # 负伤也计入军功
	else:
		outcome = "merit"
	state["merits"] = float(state.get("merits", 0.0)) + merit_gain
	player["military"] = state
	return {"ok": true, "outcome": outcome, "merits_gained": merit_gain, "casualty": casualty, "kia": kia, "merits": float(state["merits"])}


func _set_health(player: Dictionary, value: float) -> void:
	var attrs: Variant = player.get("attrs", {})
	if attrs is Dictionary:
		var g: Variant = (attrs as Dictionary).get("physiological", {})
		if g is Dictionary:
			(g as Dictionary)["health"] = clampf(value, 0.0, 100.0)


## 晋升考核：满足本级年限（按兵种晋升速度修正）与累计军功门槛。
func evaluate_promotion(player: Dictionary, now_minute: int) -> bool:
	if not is_serving(player):
		return false
	var state: Dictionary = military_state(player)
	var idx: int = int(state.get("rank_index", 0))
	if idx + 1 >= RANKS.size():
		return false
	var next_rank: Dictionary = RANKS[idx + 1]
	var branch: Dictionary = BRANCHES.get(str(state["branch"]), {})
	var speed: float = maxf(0.1, float(branch.get("promotion_speed", 1.0)))
	var years: float = maxf(0.0, (float(now_minute) - float(state.get("rank_started_minutes", now_minute))) / MINUTES_PER_YEAR)
	var required_years: float = float((RANKS[idx] as Dictionary)["min_years"]) / speed
	var has_years: bool = years >= required_years
	var has_merits: bool = float(state.get("merits", 0.0)) >= float(next_rank["merit_required"])
	return has_years and has_merits


func promote(player: Dictionary, minute: int) -> Dictionary:
	if not is_serving(player):
		return {"ok": false, "reason": "not_serving"}
	if not evaluate_promotion(player, minute):
		return {"ok": false, "reason": "not_eligible"}
	var state: Dictionary = military_state(player)
	var idx: int = int(state["rank_index"]) + 1
	var rank_def: Dictionary = RANKS[idx]
	state["rank_index"] = idx
	state["rank_key"] = str(rank_def["key"])
	state["rank_started_minutes"] = minute
	player["military"] = state
	return {"ok": true, "rank_key": str(rank_def["key"]), "rank_name": str(rank_def["name"]), "grade": str(rank_def["grade"])}


func monthly_pay(player: Dictionary) -> int:
	var state: Dictionary = military_state(player)
	var idx: int = int(state.get("rank_index", 0))
	var r: Dictionary = rank(idx)
	return int(r.get("pay", 0))


# --- 退役与逃兵 ---

## 退役/转业：发放退役金并返回民用岗位过渡信息（R47.1）。
func discharge(player: Dictionary, minute: int, opts: Dictionary = {}) -> Dictionary:
	var state: Dictionary = military_state(player)
	if state.is_empty() or str(state.get("status", "")) != STATUS_SERVING:
		return {"ok": false, "reason": "not_serving"}
	var years: float = maxf(0.0, (float(minute) - float(state.get("enlisted_minutes", minute))) / MINUTES_PER_YEAR)
	var severance: int = int(float(monthly_pay(player)) * years * DISCHARGE_PAY_PER_YEAR)
	state["status"] = STATUS_DISCHARGED
	state["discharged_minutes"] = minute
	state["severance"] = severance
	player["military"] = state
	return {
		"ok": true, "severance": severance, "years": years,
		"resettlement_job": str(opts.get("resettlement_job", "job.civil_servant")),
		"transition_days": int(opts.get("transition_days", 90)),
	}


## 拒征/逃兵：触发法律后果（联动 D12）。
func desert(player: Dictionary, minute: int) -> Dictionary:
	var state: Dictionary = military_state(player)
	if state.is_empty() or str(state.get("status", "")) != STATUS_SERVING:
		return {"ok": false, "reason": "not_serving"}
	state["status"] = STATUS_DESERTER
	state["deserted_minutes"] = minute
	player["military"] = state
	var legal: Variant = player.get("legal", {})
	if not (legal is Dictionary):
		legal = {"wanted_level": 0, "criminal_record": false, "in_prison": false}
	legal["criminal_record"] = true
	legal["wanted_level"] = int(legal.get("wanted_level", 0)) + 3
	player["legal"] = legal
	return {"ok": true, "status": STATUS_DESERTER, "wanted_level": int(legal["wanted_level"]), "criminal_record": true}


## 在役期间是否禁用某民事动词。
func restricts_civil(player: Dictionary, verb: String) -> bool:
	return is_serving(player) and RESTRICTED_VERBS.has(verb)


func restricted_verbs(player: Dictionary) -> Array:
	return RESTRICTED_VERBS.duplicate() if is_serving(player) else []


func to_dict(player: Dictionary) -> Dictionary:
	return military_state(player).duplicate(true)


func from_dict(data: Dictionary) -> Dictionary:
	return data.duplicate(true)
