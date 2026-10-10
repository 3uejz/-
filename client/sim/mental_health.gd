class_name MentalHealthSystem
extends RefCounted
## 心理状态、精神疾病三维病程与治疗（R8、R44；design D4）。
##
## 覆盖：
##   - 情绪状态（平静/焦虑/抑郁/亢奋）与心情、压力的事件驱动调整（R8）。
##   - 20+ 精神疾病库，含症状、易感因子、触发条件、复发率与治疗生效概率（R44.3）。
##   - 三维病程：发作频率、严重强度、单次持续时长，链路为易感→触发→发作→缓解/慢性化→复发（R44.4）。
##   - 治疗五法（心理咨询/药物/CBT/住院/重症干预），结果根治/缓解/无效三态，含误诊与副作用（R44.6）。
##
## 设计取舍：
##   - 疾病实例状态存于本实例的 _cases 字典（键为疾病键），动态字段不污染 player.schema 白名单。
##   - 随机性由注入 rng 决定，便于复现与三端一致。

const BaselineScript = preload("res://sim/baseline.gd")

const EMOTIONS: Array = ["calm", "anxious", "depressed", "manic"]
const EMOTION_NAMES: Dictionary = {
	"calm": "平静", "anxious": "焦虑", "depressed": "抑郁", "manic": "亢奋",
}

## 病程阶段（R44.4）。
const PHASES: Array = ["vulnerable", "triggered", "episode", "remission", "chronic"]

## 治疗方式及基础参数（R44.6）。数值真源：shared/consistency/baseline/mental_health.json。
const TREATMENTS: Dictionary = BaselineScript.MH_TREATMENTS

## 精神疾病库（22 种）。字段：名称、症状、易感因子（人格维度权重）、触发、基础发生率、复发率、慢性化率。
const DISORDERS: Dictionary = {
	"anxiety": {"name": "焦虑症", "symptoms": ["紧张", "心悸", "坐立不安"], "susceptibility": {"neuroticism": 0.8, "conscientiousness": 0.2}, "triggers": ["stress", "loss"], "base_rate": 0.05, "relapse": 0.45, "chronic": 0.2},
	"depression": {"name": "抑郁症", "symptoms": ["情绪低落", "兴趣丧失", "乏力"], "susceptibility": {"neuroticism": 0.7, "extraversion": -0.2}, "triggers": ["loss", "stress", "illness"], "base_rate": 0.04, "relapse": 0.5, "chronic": 0.25},
	"bipolar": {"name": "双相障碍", "symptoms": ["情绪高涨与低落交替", "冲动", "睡眠减少"], "susceptibility": {"neuroticism": 0.5, "extraversion": 0.3}, "triggers": ["stress", "genetic"], "base_rate": 0.015, "relapse": 0.6, "chronic": 0.5},
	"ptsd": {"name": "创伤后应激障碍", "symptoms": ["闪回", "回避", "警觉增高"], "susceptibility": {"neuroticism": 0.6}, "triggers": ["trauma"], "base_rate": 0.03, "relapse": 0.4, "chronic": 0.35},
	"ocd": {"name": "强迫症", "symptoms": ["强迫思维", "重复行为", "焦虑"], "susceptibility": {"neuroticism": 0.7, "conscientiousness": 0.4}, "triggers": ["stress", "genetic"], "base_rate": 0.02, "relapse": 0.45, "chronic": 0.4},
	"social_phobia": {"name": "社交恐惧症", "symptoms": ["社交回避", "脸红", "恐惧评价"], "susceptibility": {"neuroticism": 0.6, "extraversion": -0.5}, "triggers": ["stress", "trauma"], "base_rate": 0.03, "relapse": 0.35, "chronic": 0.3},
	"panic": {"name": "惊恐障碍", "symptoms": ["突发惊恐", "濒死感", "心悸"], "susceptibility": {"neuroticism": 0.8}, "triggers": ["stress"], "base_rate": 0.02, "relapse": 0.4, "chronic": 0.2},
	"eating": {"name": "进食障碍", "symptoms": ["暴食", "催吐", "体重异常"], "susceptibility": {"neuroticism": 0.6, "conscientiousness": 0.3}, "triggers": ["stress", "body_image"], "base_rate": 0.015, "relapse": 0.4, "chronic": 0.3},
	"schizophrenia": {"name": "精神分裂症", "symptoms": ["幻觉", "妄想", "思维紊乱"], "susceptibility": {"neuroticism": 0.4, "openness": 0.3}, "triggers": ["genetic", "trauma"], "base_rate": 0.005, "relapse": 0.65, "chronic": 0.6},
	"adhd": {"name": "注意缺陷多动障碍", "symptoms": ["注意力涣散", "冲动", "多动"], "susceptibility": {"conscientiousness": -0.6, "extraversion": 0.3}, "triggers": ["genetic"], "base_rate": 0.03, "relapse": 0.3, "chronic": 0.5},
	"bpd": {"name": "边缘型人格障碍", "symptoms": ["情绪不稳", "自我认同紊乱", "关系波动"], "susceptibility": {"neuroticism": 0.8, "agreeableness": -0.3}, "triggers": ["trauma", "loss"], "base_rate": 0.012, "relapse": 0.5, "chronic": 0.45},
	"substance": {"name": "物质使用障碍", "symptoms": ["渴求", "戒断", "耐受"], "susceptibility": {"neuroticism": 0.5, "conscientiousness": -0.4}, "triggers": ["stress", "addiction"], "base_rate": 0.025, "relapse": 0.6, "chronic": 0.4},
	"somatization": {"name": "躯体化障碍", "symptoms": ["无器质性疼痛", "疲劳", "多系统不适"], "susceptibility": {"neuroticism": 0.7}, "triggers": ["stress", "illness"], "base_rate": 0.02, "relapse": 0.35, "chronic": 0.4},
	"hypochondria": {"name": "疑病症", "symptoms": ["过度担忧患病", "反复求医", "躯体关注"], "susceptibility": {"neuroticism": 0.8}, "triggers": ["stress", "illness"], "base_rate": 0.02, "relapse": 0.4, "chronic": 0.4},
	"sad": {"name": "季节性情绪障碍", "symptoms": ["季节性情低落", "嗜睡", "食欲变化"], "susceptibility": {"neuroticism": 0.5}, "triggers": ["season", "stress"], "base_rate": 0.02, "relapse": 0.55, "chronic": 0.2},
	"insomnia": {"name": "失眠障碍", "symptoms": ["入睡困难", "易醒", "疲乏"], "susceptibility": {"neuroticism": 0.6}, "triggers": ["stress", "stay_up"], "base_rate": 0.05, "relapse": 0.5, "chronic": 0.35},
	"burnout": {"name": "职业倦怠", "symptoms": ["耗竭", "去人格化", "效能降低"], "susceptibility": {"conscientiousness": 0.5, "neuroticism": 0.4}, "triggers": ["overwork", "stress"], "base_rate": 0.06, "relapse": 0.4, "chronic": 0.3},
	"grief": {"name": "延长哀伤障碍", "symptoms": ["持续哀伤", "思念", "功能受损"], "susceptibility": {"neuroticism": 0.5}, "triggers": ["loss"], "base_rate": 0.04, "relapse": 0.3, "chronic": 0.25},
	"dissociative": {"name": "解离性障碍", "symptoms": ["失忆", "人格解体", "现实感丧失"], "susceptibility": {"neuroticism": 0.6}, "triggers": ["trauma"], "base_rate": 0.01, "relapse": 0.4, "chronic": 0.4},
	"impulse_control": {"name": "冲动控制障碍", "symptoms": ["纵火/偷窃/赌博冲动", "失控"], "susceptibility": {"conscientiousness": -0.6, "neuroticism": 0.4}, "triggers": ["stress", "addiction"], "base_rate": 0.02, "relapse": 0.45, "chronic": 0.35},
	"phobia": {"name": "特定恐惧症", "symptoms": ["特定对象恐惧", "回避", "惊恐"], "susceptibility": {"neuroticism": 0.6}, "triggers": ["trauma", "stress"], "base_rate": 0.03, "relapse": 0.3, "chronic": 0.4},
	"adjustment": {"name": "适应障碍", "symptoms": ["情绪低落", "焦虑", "功能适应困难"], "susceptibility": {"neuroticism": 0.5}, "triggers": ["stress", "loss", "migration"], "base_rate": 0.06, "relapse": 0.3, "chronic": 0.15},
}

## 事件对心情/压力/情绪的影响（R8.2）。数值真源：shared/consistency/baseline/mental_health.json。
const EVENTS: Dictionary = BaselineScript.MH_EVENTS

var _cases: Dictionary = {}       # disorder_key -> case state
var _cumulative_stress: float = 0.0

const STRESS_DISORDER_THRESHOLD: float = BaselineScript.MH_STRESS_DISORDER_THRESHOLD


func disorders_count() -> int:
	return DISORDERS.size()


func _score(v: Variant) -> float:
	return clampf(float(v), 0.0, 100.0)


# --- R8 情绪状态与事件驱动 ---

## 由心情与压力判定情绪状态（R8.1）。
func emotion_state(mood: float, stress: float) -> String:
	if mood <= 30.0 and stress >= 60.0:
		return "depressed"
	if stress >= 65.0:
		return "anxious"
	if mood >= 80.0 and stress <= 35.0:
		return "manic"
	return "calm"


## 事件调整心情与压力（R8.2）；返回调整后的数值。
func adjust_mood_stress(player: Dictionary, event: String) -> Dictionary:
	var psych: Dictionary = player["attrs"]["psychological"]
	var delta: Dictionary = EVENTS.get(event, {})
	psych["mood"] = _score(float(psych.get("mood", 50.0)) + float(delta.get("mood", 0.0)))
	psych["stress"] = _score(float(psych.get("stress", 40.0)) + float(delta.get("stress", 0.0)))
	return {"mood": float(psych["mood"]), "stress": float(psych["stress"]), "emotion": emotion_state(float(psych["mood"]), float(psych["stress"]))}


## 压力高于阈值时提高患病概率的乘子（R8.3）。压力越高乘子越大。
func stress_risk_multiplier(stress: float) -> float:
	return 1.0 + maxf(0.0, stress - STRESS_DISORDER_THRESHOLD) / 100.0


## 处于抑郁状态时行动效率下降（R8.4）。
func efficiency_factor(emotion: String) -> float:
	match emotion:
		"depressed":
			return 0.6
		"anxious":
			return 0.8
		"manic":
			return 1.1
		_:
			return 1.0


## 抑郁状态限制部分社交（R8.4）。
func social_restricted(emotion: String) -> bool:
	return emotion == "depressed"


# --- R44 精神疾病 ---

## 易感度：疾病权重 × 人格偏离 + 童年创伤 + 家族史，返回 0..1。
func susceptibility(key: String, p: Dictionary, childhood_trauma: float = 0.0, family_history: bool = false) -> float:
	var d: Dictionary = DISORDERS.get(key, {})
	var weights: Dictionary = d.get("susceptibility", {})
	var total_w: float = 0.0
	var acc: float = 0.0
	for dim in weights.keys():
		var w: float = float(weights[dim])
		var v: float = float(p.get(str(dim), 50.0))
		total_w += absf(w)
		# 正权重：该特质越高越易感；负权重：该特质越低越易感。
		if w >= 0.0:
			acc += w * (v / 100.0)
		else:
			acc += (-w) * ((100.0 - v) / 100.0)
	var base: float = (acc / total_w) if total_w > 0.0 else 0.5
	base = base * 0.6 + clampf(childhood_trauma, 0.0, 100.0) / 100.0 * 0.3
	if family_history:
		base += 0.1
	return clampf(base, 0.0, 1.0)


## 触发概率：基础发生率 × 易感 × 压力 × 触发匹配加成，返回 0..1（R44.5）。
func trigger_probability(key: String, susc: float, stress: float, trigger: String = "") -> float:
	var d: Dictionary = DISORDERS.get(key, {})
	if d.is_empty():
		return 0.0
	var rate: float = float(d.get("base_rate", 0.02))
	var p: float = rate * (0.5 + susc) * stress_risk_multiplier(stress)
	var triggers: Array = d.get("triggers", [])
	if trigger != "" and triggers.has(trigger):
		p *= 2.0
	return clampf(p, 0.0, 1.0)


## 按概率注入触发，成功则创建病程（新发或复发）。
func maybe_trigger(key: String, p: Dictionary, stress: float, trigger: String, now_minute: int, rng, childhood_trauma: float = 0.0, family_history: bool = false) -> Dictionary:
	if not DISORDERS.has(key):
		return {"triggered": false, "reason": "unknown_disorder"}
	var susc: float = susceptibility(key, p, childhood_trauma, family_history)
	var prob: float = trigger_probability(key, susc, stress, trigger)
	var roll: float = rng.next_float() if rng != null else 0.0
	if roll >= prob:
		return {"triggered": false, "probability": prob}
	var intensity: float = clampf(30.0 + susc * 50.0 + stress * 0.2, 0.0, 100.0)
	var case: Dictionary = _cases.get(key, {})
	var prior: int = int(case.get("episodes", 0))
	var new_case: Dictionary = {
		"key": key, "phase": "episode", "active": true,
		"intensity": intensity, "frequency_days": _frequency_from(susc),
		"duration_minutes": _duration_from(intensity),
		"remaining_minutes": _duration_from(intensity),
		"episodes": prior + 1, "started_minute": now_minute,
	}
	_cases[key] = new_case
	return {"triggered": true, "case": new_case, "probability": prob}


func _frequency_from(susc: float) -> float:
	# 易感越高，发作越频繁（间隔越短）：7..180 天。
	return clampf(180.0 * (1.0 - susc) + 7.0, 7.0, 180.0)


func _duration_from(intensity: float) -> float:
	# 强度越高单次持续越长：1..30 天（分钟）。
	return clampf((1.0 + intensity / 100.0 * 29.0) * 1440.0, 1440.0, 43200.0)


## 推进病程：发作时间耗尽后按慢性化率转为慢性，否则进入缓解（R44.4）。
func advance(minutes: int, rng = null) -> void:
	for key in _cases.keys():
		var case: Dictionary = _cases[key]
		if not bool(case.get("active", false)):
			continue
		case["remaining_minutes"] = float(case["remaining_minutes"]) - float(minutes)
		if float(case["remaining_minutes"]) <= 0.0:
			case["active"] = false
			var chronic_rate: float = float(DISORDERS[key].get("chronic", 0.3))
			var roll: float = rng.next_float() if rng != null else 0.0
			if roll < chronic_rate:
				case["phase"] = "chronic"
			else:
				case["phase"] = "remission"
				case["remission_minutes"] = 0.0


## 缓解后按复发率可能复发（R44.4）。
func maybe_relapse(key: String, rng) -> bool:
	if not _cases.has(key):
		return false
	var case: Dictionary = _cases[key]
	if str(case.get("phase", "")) != "remission":
		return false
	var rate: float = float(DISORDERS[key].get("relapse", 0.4))
	var roll: float = rng.next_float() if rng != null else 1.0
	if roll < rate:
		case["phase"] = "episode"
		case["active"] = true
		case["remaining_minutes"] = float(case["duration_minutes"])
		case["episodes"] = int(case["episodes"]) + 1
		return true
	return false


## 治疗：结果为根治/缓解/无效三态，可能误诊或产生副作用（R44.6）。
func treat(key: String, method: String, rng = null, diagnosed: bool = true) -> Dictionary:
	if not DISORDERS.has(key):
		return {"ok": false, "reason": "unknown_disorder"}
	if not TREATMENTS.has(method):
		return {"ok": false, "reason": "unknown_treatment"}
	var t: Dictionary = TREATMENTS[method]
	var roll: float = rng.next_float() if rng != null else 0.0
	# 误诊：未确诊即治疗时，有 25% 概率误诊，治疗打折。
	var misdiagnosed: bool = false
	if not diagnosed and roll < 0.25:
		misdiagnosed = true
	var efficacy: float = (1.0 - (0.5 if misdiagnosed else 0.0)) * float(t.get("adherence", 0.8))
	var outcome: String = "ineffective"
	var r2: float = rng.next_float() if rng != null else 0.5
	if r2 < float(t["cure"]) * efficacy:
		outcome = "cured"
	elif r2 < float(t["cure"]) * efficacy + float(t["remit"]) * efficacy:
		outcome = "remitted"
	# 副作用。
	var side_effect: bool = false
	var r3: float = rng.next_float() if rng != null else 0.0
	if r3 < float(t.get("side_effect", 0.0)):
		side_effect = true
	var case: Dictionary = _cases.get(key, {})
	if outcome == "cured":
		if _cases.has(key):
			_cases.erase(key)
	elif outcome == "remitted" and _cases.has(key):
		_cases[key]["active"] = false
		_cases[key]["phase"] = "remission"
	return {
		"ok": true, "key": key, "method": method, "outcome": outcome,
		"misdiagnosed": misdiagnosed, "side_effect": side_effect,
		"cost": int(t.get("cost", 0)), "minutes": int(t.get("minutes", 0)),
	}


func case_of(key: String) -> Dictionary:
	return _cases.get(key, {})


func active_cases() -> Array:
	var out: Array = []
	for key in _cases.keys():
		if bool(_cases[key].get("active", false)):
			out.append(_cases[key])
	return out


func has_active() -> bool:
	return not active_cases().is_empty()
