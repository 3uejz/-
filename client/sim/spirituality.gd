class_name SpiritualitySystem
extends RefCounted
## 价值观三轴、精神追求、信仰与精神危机（R55；design D4、D15）。
##
## 覆盖：
##   - 价值观三轴（利己-利他、保守-开放、物质-精神）随重大选择微调、随阅历缓慢漂移（R55.1）。
##   - 精神追求：冥想、修行、哲学阅读、写作、自省、志愿服务、艺术创作，降低压力并提升幸福/意义（R55.3、R55.5）。
##   - 可选信仰/哲学流派，深度追求解锁境界（R55.4）。
##   - 精神危机：中年危机、意义丧失、信仰动摇、存在焦虑，提供宗教/哲学/心理援助出口（R55.6）。
##   - 邪教/极端组织卷入风险（R55.7）。
##
## 设计取舍：
##   - 追求深度按小时累计，避免分钟级浮点噪声；境界阈值以累计小时判定。
##   - 随机性由注入 rng 决定，便于复现。

const PersonalityScript = preload("res://sim/personality.gd")

## 价值观三轴（R55.1）。
const VALUES: Array = ["selfish_altruistic", "conservative_open", "material_spiritual"]
const VALUE_NAMES: Dictionary = {
	"selfish_altruistic": "利己-利他", "conservative_open": "保守-开放", "material_spiritual": "物质-精神",
}

## 精神追求（R55.3）。数值为「每持续 1 小时」的增量；drift 为期望人格漂移，value_drift 为价值观漂移。
const PURSUITS: Dictionary = {
	"meditation": {"name": "冥想", "stress": -8.0, "happiness": 2.0, "meaning": 6.0, "drift": {"neuroticism": -1.5, "openness": 0.5}, "value_drift": {"material_spiritual": 0.6}},
	"asceticism": {"name": "修行", "stress": -6.0, "happiness": 1.0, "meaning": 8.0, "drift": {"conscientiousness": 1.5, "extraversion": -0.5}, "value_drift": {"material_spiritual": 0.8}},
	"philosophy_reading": {"name": "哲学阅读", "stress": -4.0, "happiness": 1.5, "meaning": 7.0, "drift": {"openness": 1.5}, "value_drift": {"conservative_open": 0.6}},
	"writing": {"name": "写作", "stress": -3.0, "happiness": 2.0, "meaning": 6.0, "drift": {"openness": 1.0, "conscientiousness": 0.5}, "value_drift": {"material_spiritual": 0.4}},
	"introspection": {"name": "自省", "stress": -5.0, "happiness": 1.0, "meaning": 5.0, "drift": {"neuroticism": -1.0, "agreeableness": 0.5}, "value_drift": {}},
	"volunteering": {"name": "志愿服务", "stress": -3.0, "happiness": 4.0, "meaning": 8.0, "drift": {"agreeableness": 1.5}, "value_drift": {"selfish_altruistic": 1.0}},
	"art_creation": {"name": "艺术创作", "stress": -4.0, "happiness": 5.0, "meaning": 7.0, "drift": {"openness": 1.0}, "value_drift": {"material_spiritual": 0.5}},
}

## 信仰/哲学流派（R55.4）。
const FAITHS: Dictionary = {
	"buddhism": {"name": "佛教", "type": "religion", "stress": -6.0, "meaning": 8.0},
	"taoism": {"name": "道家", "type": "religion", "stress": -6.0, "meaning": 7.0},
	"christianity": {"name": "基督教", "type": "religion", "stress": -5.0, "meaning": 8.0},
	"islam": {"name": "伊斯兰教", "type": "religion", "stress": -5.0, "meaning": 8.0},
	"stoicism": {"name": "斯多葛主义", "type": "philosophy", "stress": -7.0, "meaning": 6.0},
	"existentialism": {"name": "存在主义", "type": "philosophy", "stress": -3.0, "meaning": 7.0},
	"humanism": {"name": "人道主义", "type": "philosophy", "stress": -4.0, "meaning": 7.0},
	"confucianism": {"name": "儒家", "type": "philosophy", "stress": -4.0, "meaning": 6.0},
	"nihilism": {"name": "虚无主义", "type": "philosophy", "stress": 2.0, "meaning": -3.0},
	"utilitarianism": {"name": "功利主义", "type": "philosophy", "stress": -2.0, "meaning": 4.0},
}

## 追求累计深度（小时）→ 境界。
const REALM_THRESHOLDS: Array = [0.0, 50.0, 150.0, 400.0, 1000.0]
const REALM_NAMES: Array = ["入门", "小成", "精进", "通透", "境界"]

## 精神危机事件（R55.6）。
const CRISES: Array = ["midlife_crisis", "meaning_loss", "faith_crisis", "existential_anxiety"]
const CRISIS_EXITS: Dictionary = {
	"midlife_crisis": ["religion", "philosophy", "psychology"],
	"meaning_loss": ["philosophy", "volunteering", "religion"],
	"faith_crisis": ["religion", "philosophy", "psychology"],
	"existential_anxiety": ["philosophy", "psychology", "religion"],
}


func _clamp100(v: float) -> float:
	return clampf(v, 0.0, 100.0)


func new_state() -> Dictionary:
	return {"depth": {}, "faith": "", "faith_depth": 0.0, "crisis": "", "cult": false}


## 价值观随重大选择微调（R55.1、R55.2）。axis 名，delta 期望变化；返回实际变化。
func adjust_values(values: Dictionary, axis: String, delta: float) -> float:
	if not VALUES.has(axis):
		return 0.0
	var old: float = _clamp100(float(values.get(axis, 50.0)))
	var v: float = _clamp100(old + delta)
	values[axis] = v
	return v - old


## 价值观与一次选择的一致性得分 0..100（R55.2）。choice 为各轴目标值，差异越小一致性越高。
func value_consistency(values: Dictionary, choice: Dictionary) -> float:
	if choice.is_empty():
		return 50.0
	var acc: float = 0.0
	for axis in choice.keys():
		acc += absf(_clamp100(float(values.get(str(axis), 50.0))) - _clamp100(float(choice[axis])))
	acc /= float(choice.size())
	return _clamp100(100.0 - acc)


## 执行一次精神追求（R55.3、R55.5）。minutes 为投入时长。
## 返回压力/幸福/意义增量、人格与价值观漂移、是否解锁新境界。
func pursue(state: Dictionary, kind: String, minutes: float, rng = null, personality = null, cumulative = null) -> Dictionary:
	if not PURSUITS.has(kind):
		return {"ok": false, "reason": "unknown_pursuit"}
	var p: Dictionary = PURSUITS[kind]
	var hours: float = maxf(0.0, minutes) / 60.0
	var before_realm: int = realm_index(state, kind)
	var depths: Dictionary = state.get("depth", {})
	depths[kind] = float(depths.get(kind, 0.0)) + hours
	state["depth"] = depths
	var after_realm: int = realm_index(state, kind)

	var drift_applied: Dictionary = {}
	var personality_drifted: bool = false
	if personality != null and cumulative != null and not p["drift"].is_empty():
		# 漂移概率：每持续小时 10%，最多 80%。
		var chance: float = minf(0.8, hours * 0.1)
		if rng == null or rng.next_float() < chance:
			var scale: float = clampf(hours, 0.0, 3.0)
			var delta: Dictionary = {}
			for k in p["drift"].keys():
				delta[k] = float(p["drift"][k]) * scale
			drift_applied = PersonalityScript.new().drift(personality, delta, 100.0, cumulative)
			personality_drifted = true

	return {
		"ok": true, "kind": kind,
		"stress": float(p["stress"]) * hours,
		"happiness": float(p["happiness"]) * hours,
		"meaning": float(p["meaning"]) * hours,
		"drift": drift_applied, "personality_drifted": personality_drifted,
		"value_drift": p["value_drift"],
		"realm_index": after_realm, "realm": REALM_NAMES[after_realm],
		"realm_unlocked": after_realm > before_realm,
	}


## 加入/皈依信仰（R55.4）。
func convert(state: Dictionary, faith: String) -> Dictionary:
	if not FAITHS.has(faith):
		return {"ok": false, "reason": "unknown_faith"}
	state["faith"] = faith
	return {"ok": true, "faith": faith, "name": FAITHS[faith]["name"], "type": FAITHS[faith]["type"]}


## 深化信仰，按小时累计深度并解锁境界（R55.4）。
func deepen_faith(state: Dictionary, minutes: float, rng = null) -> Dictionary:
	if str(state.get("faith", "")) == "":
		return {"ok": false, "reason": "no_faith"}
	var f: Dictionary = FAITHS[str(state["faith"])]
	var hours: float = maxf(0.0, minutes) / 60.0
	var before: int = faith_realm_index(state)
	state["faith_depth"] = float(state.get("faith_depth", 0.0)) + hours
	var after: int = faith_realm_index(state)
	return {
		"ok": true, "stress": float(f["stress"]) * hours, "meaning": float(f["meaning"]) * hours,
		"realm_index": after, "realm": REALM_NAMES[after], "realm_unlocked": after > before,
	}


## 深度追求的境界等级（0..4）。
func realm_index(state: Dictionary, kind: String) -> int:
	var d: float = float(state.get("depth", {}).get(kind, 0.0))
	var idx: int = 0
	for i in range(REALM_THRESHOLDS.size()):
		if d >= float(REALM_THRESHOLDS[i]):
			idx = i
	return idx


func faith_realm_index(state: Dictionary) -> int:
	var d: float = float(state.get("faith_depth", 0.0))
	var idx: int = 0
	for i in range(REALM_THRESHOLDS.size()):
		if d >= float(REALM_THRESHOLDS[i]):
			idx = i
	return idx


## 触发精神危机（R55.6）。条件满足时返回危机键与出口选项，否则空。
func check_crisis(state: Dictionary, happiness: float, meaning: float, midlife_weight: float = 0.0, rng = null) -> Dictionary:
	if meaning < 25.0:
		return _crisis_result("meaning_loss")
	if midlife_weight > 0.5:
		return _crisis_result("midlife_crisis")
	if str(state.get("faith", "")) != "" and float(state.get("faith_depth", 0.0)) > 0.0 and meaning < 40.0:
		return _crisis_result("faith_crisis")
	if happiness < 25.0 and meaning < 40.0:
		return _crisis_result("existential_anxiety")
	return {"event": "", "exits": []}


func _crisis_result(key: String) -> Dictionary:
	return {"event": key, "exits": CRISIS_EXITS.get(key, []), "options": CRISIS_EXITS.get(key, []).duplicate()}


## 通过出口化解危机：宗教/哲学/心理援助。返回对意义与压力的影响。
func resolve_crisis(state: Dictionary, crisis: String, exit_kind: String) -> Dictionary:
	var allowed: Array = CRISIS_EXITS.get(crisis, [])
	if not allowed.has(exit_kind):
		return {"ok": false, "reason": "invalid_exit"}
	state["crisis"] = ""
	match exit_kind:
		"religion":
			return {"ok": true, "meaning": 12.0, "stress": -10.0, "via": "religion"}
		"philosophy":
			return {"ok": true, "meaning": 10.0, "stress": -8.0, "via": "philosophy"}
		"psychology":
			return {"ok": true, "meaning": 6.0, "stress": -12.0, "via": "psychology"}
		"volunteering":
			return {"ok": true, "meaning": 9.0, "stress": -6.0, "via": "volunteering"}
		_:
			return {"ok": true, "meaning": 5.0, "stress": -4.0, "via": exit_kind}


## 卷入邪教/极端组织的风险 0..1（R55.7）：意义缺失、神经质高、缺乏信仰时上升。
func cult_risk(values: Dictionary, personality: Dictionary, faith: String) -> float:
	var risk: float = (float(personality.get("neuroticism", 50.0)) - 50.0) / 100.0 + 0.2
	if str(faith) == "":
		risk += 0.2
	risk += maxf(0.0, 50.0 - float(values.get("material_spiritual", 50.0))) / 200.0
	return clampf(risk, 0.0, 1.0)


## 按风险判定是否卷入邪教（R55.7）。
func maybe_join_cult(values: Dictionary, personality: Dictionary, faith: String, rng) -> bool:
	var roll: float = rng.next_float() if rng != null else 1.0
	return roll < cult_risk(values, personality, faith)
