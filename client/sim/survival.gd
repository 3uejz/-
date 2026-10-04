class_name Survival
extends RefCounted
## 生理生存、营养、成瘾、临终与死亡（R7、R12、R43；design D3）。
##
## 直接读写 GameState 的 player["attrs"]（生理/营养/心理/能力）与 player["health"]（疾病、成瘾、
## 寿命估计）。属性统一 clamp 到 baseline.effective_range（默认 0..100，可远程覆盖）。
##
## 设计取舍：
## - player.health.addictions 条目严格保持 player.schema.json 允许的字段
##   （content_key / craving / tolerance），戒断阶段等动态状态保存在本实例的
##   _addiction_runtime 中，并通过 to_dict/from_dict 持久化（单活动玩家，M0）。
## - 长期过量计数 _excess_days、遗嘱 _will、死亡/临终标志同样保存在本实例。
## - 数值默认全部集中在 client/sim/baseline.gd 并支持远程配置覆盖。

const BaselineScript = preload("res://sim/baseline.gd")
const GregorianScript = preload("res://sim/gregorian.gd")
const RngScript = preload("res://sim/rng.gd")

const MINUTES_PER_YEAR: float = 365.25 * 1440.0

const PHYSIOLOGICAL: Array = ["health", "stamina", "hunger", "thirst", "cleanliness", "sleep_debt"]
const NUTRIENTS: Array = ["protein", "carbs", "fat", "vitamins", "minerals"]
const ADDICTION_KINDS: Array = ["tobacco", "alcohol", "drug", "gambling", "internet"]

## 成瘾阶段（design：未接触 → 偶尔 1–19 → 依赖 20–59 → 重度 60–100）。
enum AddictionStage { NONE = 0, OCCASIONAL = 1, DEPENDENT = 2, SEVERE = 3 }

## 营养失衡对应的疾病键（design D3）。
const NUTRIENT_DISEASE: Dictionary = {
	"protein": "disease.protein_deficiency",
	"carbs": "disease.hypoglycemia",
	"fat": "disease.hormone_imbalance",
	"vitamins": "disease.scurvy",
	"minerals": "disease.anemia",
}

## 遗嘱六种形式（R43.8）：公证效力最高；口头仅限临终且需见证；带形式瑕疵者可被挑战。
const WILL_FORMS: Dictionary = {
	"notarized": {"priority": 100, "witness_required": false, "dying_required": false, "challengeable": false, "label": "公证遗嘱"},
	"holographic": {"priority": 70, "witness_required": false, "dying_required": false, "challengeable": true, "label": "自书遗嘱"},
	"witnessed": {"priority": 60, "witness_required": true, "dying_required": false, "challengeable": true, "label": "代书遗嘱"},
	"printed": {"priority": 50, "witness_required": true, "dying_required": false, "challengeable": true, "label": "打印遗嘱"},
	"audio_video": {"priority": 40, "witness_required": true, "dying_required": false, "challengeable": true, "label": "录音录像遗嘱"},
	"oral": {"priority": 20, "witness_required": true, "dying_required": true, "challengeable": true, "label": "口头遗嘱"},
}

## 临终阶段仍开放的动词（R43.7）：告别、立/改遗嘱、遗言、探视、后事、器官捐献与查看。
const DYING_ALLOWED_VERBS: Array = [
	"告别", "立遗嘱", "改遗嘱", "遗言", "探视", "安排后事", "器官捐献", "查看", "状态",
]

var _now_minute: int = 0
var _dead: bool = false
var _dying: bool = false
var _rng = null
var _excess_days: Dictionary = {}        # nutrient -> 连续过量天数
var _addiction_runtime: Dictionary = {}  # kind -> 动态状态
var _will: Dictionary = {}

func _init(seed: int = 0) -> void:
	_rng = RngScript.new(seed)


# --- 时钟与状态 ---

func now_minute() -> int:
	return _now_minute

func advance_now(minutes: int) -> void:
	_now_minute += maxi(0, minutes)

func is_dead() -> bool:
	return _dead

func is_dying() -> bool:
	return _dying


# --- 数值辅助 ---

func _clamp_score(v: float) -> float:
	var r: Array = BaselineScript.effective_range("attribute")
	return clampf(v, float(r[0]), float(r[1]))


func _phys(player: Dictionary) -> Dictionary:
	return player["attrs"]["physiological"]


func _nutrition(player: Dictionary) -> Dictionary:
	return player["attrs"]["nutrition"]


func _species(kind: String) -> Dictionary:
	var table: Dictionary = BaselineScript.effective_param("addiction_species", BaselineScript.ADDICTION_SPECIES)
	if table is Dictionary and table.has(kind):
		return table[kind]
	return {"dose_gain": 2.0, "tolerance_growth": 0.02, "withdrawal_intensity": 5.0, "relapse_rate": 0.4, "treatment_days": 30.0, "withdrawal_days": 7.0, "physiological": true}


# --- 生理六项衰减 ---

## 推进六项生理属性。opts 可含：asleep(bool)、labor_intensity(0..1)、age_years。
func decay_physiological(player: Dictionary, minutes: int, opts: Dictionary = {}) -> void:
	if _dead or minutes <= 0:
		return
	var p: Dictionary = _phys(player)
	var hours: float = float(minutes) / 60.0
	var asleep: bool = bool(opts.get("asleep", false))
	var labor: float = clampf(float(opts.get("labor_intensity", 0.0)), 0.0, 1.0)
	var age: float = float(opts.get("age_years", age_years(player)))

	p["hunger"] = _clamp_score(float(p["hunger"]) - BaselineScript.HUNGER_DECAY_PER_MIN * float(minutes))
	p["thirst"] = _clamp_score(float(p["thirst"]) - BaselineScript.THIRST_DECAY_PER_MIN * float(minutes))
	p["cleanliness"] = _clamp_score(float(p["cleanliness"]) - BaselineScript.CLEANLINESS_DECAY_PER_MIN * float(minutes))

	if asleep:
		p["sleep_debt"] = _clamp_score(float(p["sleep_debt"]) - BaselineScript.SLEEP_DEBT_RECOVER_PER_HOUR * hours)
		p["stamina"] = _clamp_score(float(p["stamina"]) + BaselineScript.STAMINA_REGEN_ASLEEP_PER_HOUR * hours)
	else:
		p["sleep_debt"] = _clamp_score(float(p["sleep_debt"]) + BaselineScript.SLEEP_DEBT_GAIN_PER_HOUR * hours)
		var stamina: float = float(p["stamina"]) + BaselineScript.STAMINA_REGEN_AWAKE_PER_HOUR * hours - BaselineScript.STAMINA_DRAIN_PER_HOUR * labor * hours
		p["stamina"] = _clamp_score(stamina)

	_apply_sleep_debt_effects(player, hours, asleep)
	_apply_health_change(player, hours, age)


## 睡眠债超阈降低智力与心情；睡眠充足时心情缓慢恢复（R7.6）。
func _apply_sleep_debt_effects(player: Dictionary, hours: float, asleep: bool) -> void:
	var p: Dictionary = _phys(player)
	var excess: float = maxf(0.0, float(p["sleep_debt"]) - BaselineScript.SLEEP_DEBT_THRESHOLD)
	if excess > 0.0:
		var attr_max: float = float(BaselineScript.effective_range("attribute")[1])
		var span: float = maxf(1.0, attr_max - BaselineScript.SLEEP_DEBT_THRESHOLD)
		var drain: float = clampf(excess / span, 0.0, 1.0)
		var ability: Dictionary = player["attrs"]["ability"]
		var psych: Dictionary = player["attrs"]["psychological"]
		ability["intelligence"] = _clamp_score(float(ability["intelligence"]) - BaselineScript.SLEEP_DEBT_INTELLIGENCE_PENALTY_PER_HOUR * drain * hours)
		psych["mood"] = _clamp_score(float(psych["mood"]) - BaselineScript.SLEEP_DEBT_MOOD_PENALTY_PER_HOUR * drain * hours)
	elif asleep:
		var psych2: Dictionary = player["attrs"]["psychological"]
		psych2["mood"] = _clamp_score(float(psych2["mood"]) + BaselineScript.MOOD_RECOVER_PER_HOUR * hours)


## 健康：饱食/口渴归零后扣血（口渴更快），否则随年龄递减速率恢复。
func _apply_health_change(player: Dictionary, hours: float, age: float) -> void:
	var p: Dictionary = _phys(player)
	var starving: bool = float(p["hunger"]) <= 0.0
	var dehydrated: bool = float(p["thirst"]) <= 0.0
	var delta: float = 0.0
	if starving:
		delta -= BaselineScript.STARVE_HEALTH_PER_HOUR * hours
	if dehydrated:
		delta -= BaselineScript.DEHYDRATE_HEALTH_PER_HOUR * hours
	if not starving and not dehydrated:
		var age_factor: float = maxf(0.0, 1.0 - BaselineScript.HEALTH_REGEN_AGE_DECAY_PER_YEAR * maxf(0.0, age))
		delta += BaselineScript.HEALTH_REGEN_PER_HOUR * age_factor * hours
	p["health"] = _clamp_score(float(p["health"]) + delta)


# --- 营养五项 ---

## 按游戏日推进营养储备；随年龄与劳动强度上调衰减。长期过量累计天数用于风险判定。
func update_nutrition(player: Dictionary, days: float, opts: Dictionary = {}) -> void:
	if _dead or days <= 0.0:
		return
	var n: Dictionary = _nutrition(player)
	var scale: float = _nutrition_scale(player, opts)
	var table: Dictionary = BaselineScript.effective_param("nutrition_decay_per_day", BaselineScript.NUTRITION_DECAY_PER_DAY)
	for key in NUTRIENTS:
		var base: float = float(table.get(key, 0.0))
		n[key] = _clamp_score(float(n[key]) - base * scale * days)
	for key in NUTRIENTS:
		if float(n[key]) > BaselineScript.NUTRITION_EXCESS_THRESHOLD:
			_excess_days[key] = float(_excess_days.get(key, 0.0)) + days
		else:
			_excess_days[key] = 0.0


func _nutrition_scale(player: Dictionary, opts: Dictionary) -> float:
	var age: float = float(opts.get("age_years", age_years(player)))
	var labor: float = clampf(float(opts.get("labor_intensity", 0.0)), 0.0, 1.0)
	var age_part: float = BaselineScript.NUTRITION_AGE_SCALE_PER_YEAR * maxf(0.0, age - BaselineScript.NUTRITION_AGE_BASE_YEARS)
	return maxf(0.0, 1.0 + age_part + BaselineScript.NUTRITION_LABOR_SCALE * labor)


## 进食：先补足营养储备再补饱食，超储量计为过量（R43.2）。
## food 形如 {"protein":10,"carbs":30,"fat":8,"vitamins":6,"minerals":4,"satiety":40}。
func eat(player: Dictionary, food: Dictionary) -> Dictionary:
	if _dead:
		return {"applied": false, "over": {}, "satiety_added": 0.0}
	var n: Dictionary = _nutrition(player)
	var over: Dictionary = {}
	for key in NUTRIENTS:
		if not food.has(key):
			continue
		var amount: float = float(food[key])
		if amount <= 0.0:
			continue
		var before: float = float(n[key])
		n[key] = _clamp_score(before + amount)
		var spilled: float = before + amount - float(n[key])
		if spilled > 0.0:
			over[key] = spilled
	var satiety: float = float(food.get("satiety", food.get("hunger", 0.0)))
	var p: Dictionary = _phys(player)
	var before_hunger: float = float(p["hunger"])
	p["hunger"] = _clamp_score(before_hunger + satiety)
	return {"applied": true, "over": over, "satiety_added": float(p["hunger"]) - before_hunger}


## 营养状态：每项给出数值、失衡分级与对应疾病键（design：轻 <30、重 <15）。
func nutrition_status(player: Dictionary) -> Dictionary:
	var n: Dictionary = _nutrition(player)
	var out: Dictionary = {}
	for key in NUTRIENTS:
		var value: float = float(n[key])
		var level: String = "normal"
		if value < BaselineScript.NUTRITION_SEVERE_THRESHOLD:
			level = "severe"
		elif value < BaselineScript.NUTRITION_LIGHT_THRESHOLD:
			level = "light"
		out[key] = {
			"value": value,
			"level": level,
			"disease_key": NUTRIENT_DISEASE[key] if level != "normal" else "",
		}
	return out


## 长期过量风险：连续超阈达 NUTRIENT_EXCESS_DAYS_REQUIRED 日的营养项。
func excess_risks() -> Dictionary:
	var out: Dictionary = {}
	for key in NUTRIENTS:
		var days: float = float(_excess_days.get(key, 0.0))
		if days >= BaselineScript.NUTRITION_EXCESS_DAYS_REQUIRED:
			out[key] = days
	return out


# --- 成瘾五类 ---

func addiction_key(kind: String) -> String:
	return "addiction." + kind


func _kind_of(content_key: String) -> String:
	if content_key.begins_with("addiction."):
		return content_key.substr("addiction.".length())
	return ""


func get_addiction(player: Dictionary, kind: String) -> Dictionary:
	var list: Array = player["health"]["addictions"]
	var key: String = addiction_key(kind)
	for entry in list:
		if str(entry.get("content_key", "")) == key:
			return entry
	return {}


func _ensure_addiction(player: Dictionary, kind: String) -> Dictionary:
	var existing: Dictionary = get_addiction(player, kind)
	if not existing.is_empty():
		return existing
	var entry: Dictionary = {"content_key": addiction_key(kind), "craving": 0.0, "tolerance": 0.0}
	player["health"]["addictions"].append(entry)
	return entry


func _runtime(kind: String) -> Dictionary:
	if not _addiction_runtime.has(kind):
		_addiction_runtime[kind] = {
			"last_use_minute": -1, "in_withdrawal": false,
			"withdrawal_days_left": 0.0, "recovered": false,
		}
	return _addiction_runtime[kind]


func addiction_stage(craving: float) -> int:
	if craving <= 0.0:
		return AddictionStage.NONE
	if craving < BaselineScript.ADDICTION_DEPENDENT_MIN:
		return AddictionStage.OCCASIONAL
	if craving < BaselineScript.ADDICTION_SEVERE_MIN:
		return AddictionStage.DEPENDENT
	return AddictionStage.SEVERE


## 阶段中文名，含戒断中/康复过渡态。
func addiction_phase(player: Dictionary, kind: String) -> String:
	var entry: Dictionary = get_addiction(player, kind)
	if entry.is_empty():
		return "未接触"
	var rt: Dictionary = _runtime(kind)
	if bool(rt["in_withdrawal"]):
		return "戒断中"
	if bool(rt["recovered"]) and float(entry["craving"]) <= BaselineScript.ADDICTION_DEPENDENT_MIN:
		return "康复"
	match addiction_stage(float(entry["craving"])):
		AddictionStage.OCCASIONAL:
			return "偶尔"
		AddictionStage.DEPENDENT:
			return "依赖"
		AddictionStage.SEVERE:
			return "重度"
		_:
			return "未接触"


## 使用一次成瘾物/行为：craving 累积，耐受上升使效果边际递减、累积加快（design）。
func addict(player: Dictionary, kind: String, dose: float = 1.0, opts: Dictionary = {}) -> Dictionary:
	if _dead or not ADDICTION_KINDS.has(kind) or dose <= 0.0:
		return {}
	var species: Dictionary = _species(kind)
	var entry: Dictionary = _ensure_addiction(player, kind)
	var tolerance: float = float(entry.get("tolerance", 0.0))
	var accumulation: float = 1.0 + tolerance * float(species["tolerance_growth"]) * 10.0
	entry["craving"] = _clamp_score(float(entry["craving"]) + dose * float(species["dose_gain"]) * accumulation)
	entry["tolerance"] = maxf(0.0, tolerance + dose * float(species["tolerance_growth"]))
	var rt: Dictionary = _runtime(kind)
	rt["last_use_minute"] = _now_minute
	rt["in_withdrawal"] = false
	rt["withdrawal_days_left"] = 0.0
	rt["recovered"] = false
	return {
		"kind": kind, "craving": float(entry["craving"]),
		"stage": addiction_stage(float(entry["craving"])),
	}


## 推进成瘾：craving 自然消退；依赖且停用进入戒断中并降低心情/意志/体力。
func update_addictions(player: Dictionary, minutes: int, opts: Dictionary = {}) -> void:
	if _dead or minutes <= 0:
		return
	var days: float = float(minutes) / 1440.0
	var table: Dictionary = BaselineScript.effective_param("addiction_species", BaselineScript.ADDICTION_SPECIES)
	for entry in player["health"]["addictions"]:
		var kind: String = _kind_of(str(entry.get("content_key", "")))
		if kind == "":
			continue
		var species: Dictionary = table.get(kind, _species(kind))
		var rt: Dictionary = _runtime(kind)
		entry["craving"] = _clamp_score(float(entry["craving"]) - BaselineScript.ADDICTION_CRAVING_DECAY_PER_DAY * days)
		var idle_hours: float = INF
		if int(rt["last_use_minute"]) >= 0:
			idle_hours = float(_now_minute - int(rt["last_use_minute"])) / 60.0
		if not bool(rt["in_withdrawal"]) and float(entry["craving"]) >= BaselineScript.ADDICTION_DEPENDENT_MIN \
				and idle_hours >= BaselineScript.ADDICTION_WITHDRAWAL_TRIGGER_HOURS:
			rt["in_withdrawal"] = true
			rt["withdrawal_days_left"] = float(species["withdrawal_days"])
		if bool(rt["in_withdrawal"]):
			var duration_days: float = maxf(1.0, float(species["withdrawal_days"]))
			var per_day: float = float(species["withdrawal_intensity"]) / duration_days
			var psych: Dictionary = player["attrs"]["psychological"]
			var ability: Dictionary = player["attrs"]["ability"]
			psych["mood"] = _clamp_score(float(psych["mood"]) - per_day * days)
			ability["willpower"] = _clamp_score(float(ability["willpower"]) - per_day * 0.5 * days)
			if bool(species["physiological"]):
				var p: Dictionary = _phys(player)
				p["stamina"] = _clamp_score(float(p["stamina"]) - per_day * days)
			rt["withdrawal_days_left"] = maxf(0.0, float(rt["withdrawal_days_left"]) - days)
			if float(rt["withdrawal_days_left"]) <= 0.0:
				rt["in_withdrawal"] = false
				entry["craving"] = _clamp_score(float(entry["craving"]) * 0.5)
				rt["recovered"] = true


## 治疗成瘾：心理咨询、药物替代、住院戒瘾；降低累积、提高戒断成功率但不保证根治（R43.6）。
func treat_addiction(player: Dictionary, kind: String, method: String = "counseling") -> Dictionary:
	var entry: Dictionary = get_addiction(player, kind)
	if entry.is_empty():
		return {"ok": false, "reason": "无该成瘾"}
	var scheme: Dictionary = BaselineScript.ADDICTION_TREATMENT.get(method, BaselineScript.ADDICTION_TREATMENT["counseling"])
	entry["craving"] = _clamp_score(float(entry["craving"]) * (1.0 - float(scheme["reduction"])))
	var success_chance: float = clampf(float(scheme["success_bonus"]) + (1.0 - float(entry["craving"]) / 100.0) * 0.3, 0.0, 0.95)
	var success: bool = _rng.next_float() < success_chance and float(entry["craving"]) < BaselineScript.ADDICTION_DEPENDENT_MIN
	if success:
		var rt: Dictionary = _runtime(kind)
		rt["in_withdrawal"] = false
		rt["withdrawal_days_left"] = 0.0
		rt["recovered"] = true
	return {"ok": true, "success": success, "craving": float(entry["craving"])}


## 脱瘾后按复发率重新接触（design：强行戒断有复发率）。
func relapse(player: Dictionary, kind: String) -> bool:
	var entry: Dictionary = get_addiction(player, kind)
	if entry.is_empty():
		return false
	var species: Dictionary = _species(kind)
	if _rng.next_float() < float(species["relapse_rate"]):
		entry["craving"] = _clamp_score(float(entry["craving"]) + 10.0)
		_runtime(kind)["recovered"] = false
		return true
	return false


# --- 年龄、寿命与死亡 ---

func age_years(player: Dictionary) -> float:
	var birth: int = int(player.get("birth_minutes", 0))
	return maxf(0.0, float(_now_minute - birth) / MINUTES_PER_YEAR)


## lifespan = base + health_hist + medical + luck − disease_load（design Numeric Models）。
func estimate_lifespan_years(health_history: float = 0.0, medical: float = 0.0, luck: float = 0.0, disease_load: float = 0.0) -> float:
	return maxf(0.0, BaselineScript.LIFESPAN_BASE_YEARS + health_history + medical + luck - disease_load)


func lifespan_estimate_minutes(health_history: float = 0.0, medical: float = 0.0, luck: float = 0.0, disease_load: float = 0.0) -> int:
	return int(round(estimate_lifespan_years(health_history, medical, luck, disease_load) * MINUTES_PER_YEAR))


## 把寿命估计写回 player.health.lifespan_estimate_minutes（schema 允许字段）。
func sync_lifespan_estimate(player: Dictionary, health_history: float = 0.0, medical: float = 0.0, luck: float = 0.0, disease_load: float = 0.0) -> void:
	player["health"]["lifespan_estimate_minutes"] = lifespan_estimate_minutes(health_history, medical, luck, disease_load)


## 判定临终与死亡，并更新内部标志。死亡优先于临终。
## opts 可含：age_years、lifespan_years、health_history、medical、luck、disease_load、
## terminal_disease(确诊绝症)、treatment_available、fatal(致命意外)。
func evaluate(player: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var health: float = float(_phys(player)["health"])
	var age: float = float(opts.get("age_years", age_years(player)))
	var lifespan: float = float(opts.get("lifespan_years", -1.0))
	if lifespan < 0.0:
		lifespan = estimate_lifespan_years(
			float(opts.get("health_history", 0.0)), float(opts.get("medical", 0.0)),
			float(opts.get("luck", 0.0)), float(opts.get("disease_load", 0.0)))
	var dying: bool = false
	if health <= BaselineScript.DYING_HEALTH_THRESHOLD and not bool(opts.get("treatment_available", true)):
		dying = true
	if age >= lifespan - BaselineScript.DYING_LIFESPAN_MARGIN_YEARS and health < BaselineScript.DYING_HEALTH_MARGIN:
		dying = true
	if bool(opts.get("terminal_disease", false)):
		dying = true
	_dying = dying
	if health <= 0.0 or age >= lifespan or bool(opts.get("fatal", false)):
		_dead = true
	if _dead:
		_dying = false
	return {"dying": _dying, "dead": _dead, "health": health, "age_years": age, "lifespan_years": lifespan}


# --- 综合推进 ---

## 推进全部生理模拟；死亡后冻结（不再改变任何属性）。
func advance(player: Dictionary, minutes: int, opts: Dictionary = {}) -> Dictionary:
	if _dead:
		return {"advanced_minutes": 0, "frozen": true, "dead": true, "dying": false}
	if minutes <= 0:
		var ev0: Dictionary = evaluate(player, opts)
		return {"advanced_minutes": 0, "frozen": false, "dead": ev0["dead"], "dying": ev0["dying"]}
	_now_minute += minutes
	decay_physiological(player, minutes, opts)
	update_nutrition(player, float(minutes) / 1440.0, opts)
	update_addictions(player, minutes, opts)
	var ev: Dictionary = evaluate(player, opts)
	return {
		"advanced_minutes": minutes, "frozen": false,
		"dead": ev["dead"], "dying": ev["dying"],
		"excess_risks": excess_risks(),
	}


# --- 临终动词门控 ---

func verb_allowed(verb: String) -> bool:
	if not _dying:
		return true
	return DYING_ALLOWED_VERBS.has(verb)


func allowed_verbs() -> Array:
	return DYING_ALLOWED_VERBS.duplicate()


# --- 遗嘱与人生总结 ---

## 校验遗嘱形式：见证、临终（口头）要求与优先级（R43.8）。
func validate_will(form: String, opts: Dictionary = {}) -> Dictionary:
	if not WILL_FORMS.has(form):
		return {"valid": false, "reason": "未知遗嘱形式"}
	var spec: Dictionary = WILL_FORMS[form]
	var witnessed: bool = bool(opts.get("witnessed", false))
	if bool(spec["witness_required"]) and not witnessed:
		return {"valid": false, "reason": "缺少见证人"}
	if bool(spec["dying_required"]) and not _dying:
		return {"valid": false, "reason": "口头遗嘱仅限临终"}
	return {
		"valid": true, "priority": int(spec["priority"]),
		"challengeable": bool(spec["challengeable"]), "label": str(spec["label"]),
	}


## 立/改遗嘱。content 可含财产分割、监护、遗言、器官捐献、丧葬方式（R43.9）。
func make_will(form: String, content: Dictionary = {}, opts: Dictionary = {}) -> Dictionary:
	var validation: Dictionary = validate_will(form, opts)
	if not bool(validation["valid"]):
		return {"ok": false, "validation": validation}
	_will = {
		"form": form, "content": content.duplicate(true),
		"priority": validation["priority"], "challengeable": validation["challengeable"], "valid": true,
	}
	return {"ok": true, "will": _will.duplicate(true)}


func get_will() -> Dictionary:
	return _will.duplicate(true)


func clear_will() -> void:
	_will = {}


func has_valid_will() -> bool:
	return not _will.is_empty() and bool(_will.get("valid", false))


## 人生总结报告（R12.5）：大事记时间线、生涯统计与最终称号。
func life_summary(player: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var timeline: Array = []
	if opts.get("timeline") is Array:
		timeline = (opts["timeline"] as Array).duplicate(true)
	return {
		"name": str(player.get("name", "无名")),
		"gender": str(player.get("gender", "nonbinary")),
		"age_years": float(opts.get("age_years", age_years(player))),
		"death_minutes": int(opts.get("death_minutes", _now_minute)),
		"final_title": str(opts.get("final_title", "凡人")),
		"timeline": timeline,
		"career": opts.get("career", {}),
		"achievements": player.get("achievements", []).duplicate(),
		"has_will": has_valid_will(),
	}


# --- 序列化 ---

func to_dict() -> Dictionary:
	return {
		"now_minute": _now_minute,
		"dead": _dead,
		"dying": _dying,
		"excess_days": _excess_days.duplicate(true),
		"addiction_runtime": _addiction_runtime.duplicate(true),
		"will": _will.duplicate(true),
	}


func from_dict(data: Dictionary) -> void:
	_now_minute = int(data.get("now_minute", 0))
	_dead = bool(data.get("dead", false))
	_dying = bool(data.get("dying", false))
	var ex: Variant = data.get("excess_days", {})
	_excess_days = (ex as Dictionary).duplicate(true) if ex is Dictionary else {}
	var rt: Variant = data.get("addiction_runtime", {})
	_addiction_runtime = (rt as Dictionary).duplicate(true) if rt is Dictionary else {}
	var w: Variant = data.get("will", {})
	_will = (w as Dictionary).duplicate(true) if w is Dictionary else {}
