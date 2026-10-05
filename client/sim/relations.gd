class_name RelationshipSystem
extends RefCounted
## 五维关系网络（R18、R20、R50.1–R50.2；design D10）。
##
## 维度：好感 favor(−100..100)、信任 trust(0..100)、敬畏 awe(0..100)、
##       恩怨 grudge(−100..100)、亲密度 intimacy(0..100)。
## 规则：
##   - 单次互动各维度增减设上限（防一次刷满）；重大事件可大幅跳变；
##   - 未互动关系按年指数衰减（复用基线 relation_annual_decay_k）；
##   - 分级以好感为主轴、信任/亲密/敬畏修正；恩怨过低转为仇敌；
##   - 圈层（朋友/同学/同事/邻居/网友）影响互动加成；
##   - 关系网络传播：行善/作恶经见证者按关系强弱传播初始态度。

const BaselineScript = preload("res://sim/baseline.gd")

const DIMS: Array = ["favor", "trust", "awe", "grudge", "intimacy"]

## 单次互动上限（普通 / 重大事件）。
const INTERACTION_CAP: float = 15.0
const MAJOR_CAP: float = 60.0

## 关系分级（按好感主轴，其余维度修正）。
const LEVEL_STRANGER: String = "stranger"
const LEVEL_ACQUAINTANCE: String = "acquaintance"
const LEVEL_FAMILIAR: String = "familiar"
const LEVEL_FRIEND: String = "friend"
const LEVEL_BEST_FRIEND: String = "best_friend"
const LEVEL_LOVER: String = "lover"
const LEVEL_FAMILY: String = "family"
const LEVEL_ENEMY: String = "enemy"

const LEVEL_NAMES: Dictionary = {
	"stranger": "陌路", "acquaintance": "点头", "familiar": "熟人",
	"friend": "朋友", "best_friend": "挚友", "lover": "恋人",
	"family": "家人", "enemy": "仇敌",
}

## 互动类型 → 各维度基础增减。major=true 的重大事件用 MAJOR_CAP。
const INTERACTIONS: Dictionary = {
	"chat": {"favor": 1.0, "trust": 0.5, "intimacy": 0.5},
	"gift": {"favor": 3.0, "trust": 1.0, "intimacy": 1.0},
	"dine": {"favor": 4.0, "intimacy": 1.5},
	"party": {"favor": 5.0, "intimacy": 2.0},
	"celebrate": {"favor": 4.0, "intimacy": 1.5},
	"help": {"favor": 6.0, "trust": 3.0, "grudge": -2.0},
	"cooperate": {"favor": 4.0, "trust": 2.0},
	"rescue": {"favor": 30.0, "trust": 20.0, "intimacy": 10.0, "major": true},
	"betray": {"favor": -40.0, "trust": -40.0, "grudge": 50.0, "major": true},
	"insult": {"favor": -8.0, "grudge": 8.0},
	"conflict": {"favor": -15.0, "grudge": 15.0},
}

## 高好感解锁的特殊互动。
const UNLOCK_THRESHOLDS: Dictionary = {
	"introduce_job": 60.0, "borrow": 70.0, "partner": 80.0, "marry": 90.0,
}

var _levels: Array = [LEVEL_ENEMY, LEVEL_STRANGER, LEVEL_ACQUAINTANCE, LEVEL_FAMILIAR,
	LEVEL_FRIEND, LEVEL_BEST_FRIEND, LEVEL_LOVER, LEVEL_FAMILY]


# --- 关系存取 ---

func _rel_list(owner: Dictionary) -> Array:
	if not owner.has("relations") or typeof(owner["relations"]) != TYPE_ARRAY:
		owner["relations"] = []
	return owner["relations"]


func get_relation(owner: Dictionary, target_id: String) -> Dictionary:
	for r in _rel_list(owner):
		if r is Dictionary and str(r.get("target_id", "")) == target_id:
			return r
	return {}


## 取得（必要时创建）关系条目。默认中性：好感 0、信任 20、敬畏 0、恩怨 0、亲密 0。
func ensure_relation(owner: Dictionary, target_id: String) -> Dictionary:
	var rel: Dictionary = get_relation(owner, target_id)
	if not rel.is_empty():
		return rel
	rel = {
		"target_id": target_id,
		"favor": 0.0, "trust": 20.0, "awe": 0.0, "grudge": 0.0, "intimacy": 0.0,
		"romance": false, "circles": [], "last_interaction_minute": -1,
		"interactions": 0,
	}
	_rel_list(owner).append(rel)
	return rel


func remove_relation(owner: Dictionary, target_id: String) -> bool:
	var list: Array = _rel_list(owner)
	for i in list.size():
		if str((list[i] as Dictionary).get("target_id", "")) == target_id:
			list.remove_at(i)
			return true
	return false


func _dim_range(dim: String) -> Array:
	var r: Array = BaselineScript.effective_range(dim)
	if r.size() == 2:
		return r
	return [-100.0, 100.0]


func _clamp_dim(dim: String, value: float) -> float:
	var r: Array = _dim_range(dim)
	return clampf(value, float(r[0]), float(r[1]))


# --- 互动结算 ---

## 应用一次互动。opts:
##   minute(相关时间)、personality(大五字典)、values(价值轴字典)、
##   circle(圈层，可选)、romance(是否亲密行为，可选)。
## 返回 {ok, type, deltas, relation, level}。
func apply_interaction(owner: Dictionary, target_id: String, type: String, opts: Dictionary = {}) -> Dictionary:
	if not INTERACTIONS.has(type):
		return {"ok": false, "reason": "unknown_interaction"}
	var spec: Dictionary = INTERACTIONS[type]
	var major: bool = bool(spec.get("major", false))
	var cap: float = MAJOR_CAP if major else INTERACTION_CAP
	var rel: Dictionary = ensure_relation(owner, target_id)
	var modifier: float = _interaction_modifier(opts)
	var deltas: Dictionary = {}
	for dim in DIMS:
		var base: float = float(spec.get(dim, 0.0))
		if base == 0.0:
			continue
		base *= modifier
		# 正常互动受上限约束；重大事件按 MAJOR_CAP 大幅跳变。
		base = clampf(base, -cap, cap)
		var before: float = float(rel.get(dim, 0.0))
		rel[dim] = _clamp_dim(dim, before + base)
		deltas[dim] = float(rel[dim]) - before
	if spec.has("circle") or opts.has("circle"):
		set_circle(rel, str(opts.get("circle", spec.get("circle", ""))))
	if bool(opts.get("romance", false)):
		rel["romance"] = true
	rel["last_interaction_minute"] = int(opts.get("minute", rel.get("last_interaction_minute", -1)))
	rel["interactions"] = int(rel.get("interactions", 0)) + 1
	return {"ok": true, "type": type, "deltas": deltas, "relation": rel, "level": classify(rel)}


## 性格/价值观修正：亲和提升好感增益，神经质放大恩怨，开放提升亲密。
func _interaction_modifier(opts: Dictionary) -> float:
	var m: float = 1.0
	var p: Dictionary = opts.get("personality", {})
	if not p.is_empty():
		m += (float(p.get("agreeableness", 50.0)) - 50.0) / 200.0
		m += (float(p.get("extraversion", 50.0)) - 50.0) / 400.0
	var v: Dictionary = opts.get("values", {})
	if not v.is_empty():
		m += (float(v.get("conservative_open", 50.0)) - 50.0) / 400.0
	return clampf(m, 0.5, 1.5)


# --- 分级与解锁 ---

## 按好感主轴 + 信任/亲密/敬畏修正分级；恩怨过低优先判为仇敌。
func classify(rel: Dictionary) -> String:
	var favor: float = float(rel.get("favor", 0.0))
	var trust: float = float(rel.get("trust", 0.0))
	var intimacy: float = float(rel.get("intimacy", 0.0))
	var grudge: float = float(rel.get("grudge", 0.0))
	if grudge <= -60.0 or favor <= -60.0:
		return LEVEL_ENEMY
	var score: float = favor + (trust - 50.0) * 0.2 + intimacy * 0.3
	if bool(rel.get("romance", false)) and score >= 75.0 and intimacy >= 60.0:
		return LEVEL_LOVER
	if score >= 85.0 and intimacy >= 70.0:
		return LEVEL_FAMILY
	if score >= 70.0:
		return LEVEL_BEST_FRIEND
	if score >= 45.0:
		return LEVEL_FRIEND
	if score >= 20.0:
		return LEVEL_FAMILIAR
	if score >= 5.0:
		return LEVEL_ACQUAINTANCE
	return LEVEL_STRANGER


func level_name(level: String) -> String:
	return str(LEVEL_NAMES.get(level, level))


func set_circle(rel: Dictionary, circle: String) -> void:
	if circle == "":
		return
	var circles: Array = rel.get("circles", [])
	if not circles.has(circle):
		circles.append(circle)
	rel["circles"] = circles


## 高好感解锁的特殊互动；恋人额外解锁求婚。
func unlocked_actions(rel: Dictionary) -> Array:
	var out: Array = []
	if rel.is_empty():
		return out
	var favor: float = float(rel.get("favor", 0.0))
	for action in UNLOCK_THRESHOLDS.keys():
		if favor >= float(UNLOCK_THRESHOLDS[action]):
			out.append(action)
	if bool(rel.get("romance", false)) and not out.has("marry") and favor >= 80.0:
		out.append("marry")
	return out


## 恩怨过低时拒绝互动。
func rejects_interaction(rel: Dictionary) -> bool:
	if rel.is_empty():
		return false
	return float(rel.get("grudge", 0.0)) <= -50.0 or float(rel.get("favor", 0.0)) <= -50.0


# --- 衰减与传播 ---

## 年度衰减：未互动关系各维度按指数衰减（恩怨随之缓和）。
func decay_all(owner: Dictionary, idle_years: float) -> int:
	var count: int = 0
	for rel in _rel_list(owner):
		if not (rel is Dictionary):
			continue
		for dim in DIMS:
			var value: float = float(rel.get(dim, 0.0))
			if value != 0.0:
				rel[dim] = _clamp_dim(dim, BaselineScript.apply_relation_decay(value, idle_years))
		count += 1
	return count


## 行为传播：玩家行善/作恶经见证者按既有关系强弱调整初始好感。
## witnesses: [{id, strength 0..1}]；valence ∈ [-1,1]。
func propagate(owner: Dictionary, witnesses: Array, valence: float, magnitude: float = 5.0) -> Dictionary:
	var affected: int = 0
	for w in witnesses:
		if not (w is Dictionary):
			continue
		var rel: Dictionary = ensure_relation(owner, str(w.get("id", "")))
		var strength: float = clampf(float(w.get("strength", 1.0)), 0.0, 1.0)
		var delta: float = clampf(valence * magnitude * strength, -INTERACTION_CAP, INTERACTION_CAP)
		rel["favor"] = _clamp_dim("favor", float(rel.get("favor", 0.0)) + delta)
		affected += 1
	return {"affected": affected, "valence": valence}


func to_dict(owner: Dictionary) -> Array:
	return _rel_list(owner).duplicate(true)
