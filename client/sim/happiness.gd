class_name HappinessSystem
extends RefCounted
## 幸福与意义感（R44.7、R44.8；design D4）。
##
## 幸福 = 0.25·关系 + 0.2·事业 + 0.2·健康 + 0.15·信仰 + 0.2·意义感。
## 意义感由精神追求、家庭、成就与价值观一致性驱动。
## 长期低值提高精神疾病与中年危机权重；极端低值触发危机事件。

## 幸福加权公式（design D4，权重和 = 1.0）。
const BaselineScript = preload("res://sim/baseline.gd")

const WEIGHTS: Dictionary = {
	"relations": 0.25, "career": 0.20, "health": 0.20, "faith": 0.15, "meaning": 0.20,
}
## 意义感加权公式（权重和 = 1.0）。
const MEANING_WEIGHTS: Dictionary = {
	"pursuit": 0.30, "family": 0.25, "achievement": 0.25, "values_consistency": 0.20,
}

const LOW_THRESHOLD: float = BaselineScript.HAPPY_LOW_THRESHOLD
const EXTREME_LOW: float = BaselineScript.HAPPY_EXTREME_LOW
const LOW_DAYS_FOR_RISK: int = BaselineScript.HAPPY_LOW_DAYS_FOR_RISK
const MIDLIFE_AGE_MIN: float = BaselineScript.HAPPY_MIDLIFE_AGE_MIN
const MIDLIFE_AGE_MAX: float = BaselineScript.HAPPY_MIDLIFE_AGE_MAX


func _clamp100(v: float) -> float:
	return clampf(v, 0.0, 100.0)


## 意义感：精神追求/家庭/成就/价值观一致性加权（R44.7）。
func meaning_score(components: Dictionary) -> float:
	var total: float = 0.0
	for key in MEANING_WEIGHTS.keys():
		total += float(MEANING_WEIGHTS[key]) * _clamp100(float(components.get(key, 0.0)))
	return _clamp100(total)


## 幸福：五分量加权（R44.7）。components 需含 relations/career/health/faith/meaning。
## 若未提供 meaning，则由 pursuit/family/achievement/values_consistency 推导。
func happiness(components: Dictionary) -> float:
	var c: Dictionary = components.duplicate()
	if not c.has("meaning"):
		c["meaning"] = meaning_score(components)
	var total: float = 0.0
	for key in WEIGHTS.keys():
		total += float(WEIGHTS[key]) * _clamp100(float(c.get(key, 0.0)))
	return _clamp100(total)


## 一次计算幸福与意义感。若给出 meaning 则直接采用，否则由四项推导。
func compute(components: Dictionary) -> Dictionary:
	var c: Dictionary = components.duplicate()
	if not c.has("meaning"):
		c["meaning"] = meaning_score(components)
	return {"happiness": happiness(c), "meaning": float(c["meaning"])}


## 写入 player 心理属性（happiness/meaning）。
func update(player: Dictionary, components: Dictionary) -> Dictionary:
	var r: Dictionary = compute(components)
	var psych: Dictionary = player["attrs"]["psychological"]
	psych["happiness"] = r["happiness"]
	psych["meaning"] = r["meaning"]
	return r


## 是否长期低值（幸福或意义低于阈值持续超过 LOW_DAYS_FOR_RISK 天）。
func is_long_term_low(happiness: float, meaning: float, low_days: int) -> bool:
	return (happiness < LOW_THRESHOLD or meaning < LOW_THRESHOLD) and low_days >= LOW_DAYS_FOR_RISK


## 精神疾病权重乘子：长期低值越高，风险越大（R44.8）。
func disorder_risk_multiplier(happiness: float, meaning: float, low_days: int) -> float:
	var m: float = 1.0
	if happiness < LOW_THRESHOLD:
		m += (LOW_THRESHOLD - happiness) / LOW_THRESHOLD
	if meaning < LOW_THRESHOLD:
		m += (LOW_THRESHOLD - meaning) / LOW_THRESHOLD
	if low_days >= LOW_DAYS_FOR_RISK:
		m += 0.5
	return clampf(m, 1.0, 4.0)


## 中年危机事件权重（R44.8）：年龄落在中年窗口且幸福/意义偏低时显著提高。
func midlife_crisis_weight(age: float, happiness: float, meaning: float) -> float:
	if age < MIDLIFE_AGE_MIN or age > MIDLIFE_AGE_MAX:
		return 0.0
	var stress: float = maxf(0.0, LOW_THRESHOLD - happiness) / LOW_THRESHOLD
	stress += maxf(0.0, LOW_THRESHOLD - meaning) / LOW_THRESHOLD
	return clampf(stress, 0.0, 2.0)


## 极端低值触发危机事件（R44.8），返回危机键，无则返回空串。
func crisis_event(happiness: float, meaning: float) -> String:
	if happiness < EXTREME_LOW and meaning < EXTREME_LOW:
		return "existential_crisis"
	if happiness < EXTREME_LOW:
		return "despair_crisis"
	if meaning < EXTREME_LOW:
		return "meaning_crisis"
	return ""
