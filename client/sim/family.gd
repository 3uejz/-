class_name FamilySystem
extends RefCounted
## 恋爱、婚姻、离婚、出轨与繁衍（R19；design D11）。
##
## 表白按关系、魅力与心情判定；恋人关系与亲密度达标解锁求婚；婚后配偶纳入家庭；
## 支持同居/离婚/出轨（离婚结算财产与心情）；生育时子女遗传父母属性与天赋；
## NPC 可自发婚育形成人口流动。
##
## 设计取舍：
##   - 家庭成员详情保存在本实例 _state（player.schema 根对象 additionalProperties=false，
##     不新增顶层键）；成员同时以 relations(circle=family) 形式对上层可见。
##   - 随机性由注入 rng 决定，便于复现与三端一致。

const ABILITY_KEYS: Array = ["intelligence", "charm", "physique", "willpower", "luck"]
const BIG_FIVE: Array = ["openness", "conscientiousness", "extraversion", "agreeableness", "neuroticism"]

const CONFESS_BASE: float = 0.25
const MARRIAGE_FAVOR_MIN: float = 70.0
const MARRIAGE_INTIMACY_MIN: float = 70.0
const HEREDITY_WEIGHT: float = 0.5
const GENE_NOISE: float = 10.0
const DIVORCE_ASSET_SPLIT: float = 0.5
const DIVORCE_MOOD_PENALTY: float = 25.0
const CHILD_DAILY_EXPENSE: int = 10000
const ELDER_DAILY_EXPENSE: int = 8000

var _state: Dictionary = {}
var _rng = null


func _init(seed: int = 0) -> void:
	var RngScript = preload("res://sim/rng.gd")
	_rng = RngScript.new(seed)
	_state = {"spouse": {}, "married": false, "cohabiting": false, "children": [], "elders": [], "parents": [], "estate": 0, "mood": 50.0}


func state() -> Dictionary:
	return _state


func _clamp100(v: float) -> float:
	return clampf(v, 0.0, 100.0)


# --- 恋爱 ---

## 表白（R19.1）：依据关系、魅力与心情判定成功概率。
func confess(favor: float, charm: float, mood: float, similarity: float = 50.0, rng = null) -> Dictionary:
	var prob: float = CONFESS_BASE
	prob += clampf(favor, -100.0, 100.0) / 100.0 * 0.3
	prob += (charm - 50.0) / 200.0
	prob += (mood - 50.0) / 200.0
	prob += (similarity - 50.0) / 200.0
	prob = clampf(prob, 0.02, 0.98)
	var roll: float = rng.next_float() if rng != null else 0.0
	return {"ok": true, "success": roll < prob, "probability": prob}


## 求婚解锁条件：好感与亲密度达标（R19.2）。
func can_marry(favor: float, intimacy: float) -> bool:
	return favor >= MARRIAGE_FAVOR_MIN and intimacy >= MARRIAGE_INTIMACY_MIN


## 求婚判定。
func propose(favor: float, intimacy: float, charm: float, rng = null) -> Dictionary:
	if not can_marry(favor, intimacy):
		return {"ok": false, "reason": "not_ready"}
	var prob: float = clampf(0.5 + (favor - 70.0) / 100.0 + (intimacy - 70.0) / 100.0 + (charm - 50.0) / 200.0, 0.05, 0.98)
	var roll: float = rng.next_float() if rng != null else 0.0
	return {"ok": true, "success": roll < prob, "probability": prob}


## 结婚：配偶纳入家庭（R19.3）。
func marry(spouse: Dictionary) -> Dictionary:
	_state["spouse"] = spouse
	_state["married"] = true
	return {"ok": true, "spouse": spouse}


## 同居（R19.4）。
func cohabit() -> Dictionary:
	_state["cohabiting"] = true
	return {"ok": true, "cohabiting": true}


## 出轨判定（R19.4）。temptation 为诱惑强度 0..1。
func check_infidelity(temptation: float, rng = null) -> Dictionary:
	var prob: float = clampf(0.05 + temptation * 0.4, 0.0, 0.9)
	var roll: float = rng.next_float() if rng != null else 1.0
	var cheated: bool = roll < prob
	_state["cheated"] = cheated
	return {"cheated": cheated, "probability": prob}


## 离婚（R19.4）：结算财产分割与心情变化。
func divorce(rng = null) -> Dictionary:
	if not bool(_state["married"]):
		return {"ok": false, "reason": "not_married"}
	var estate: int = int(_state.get("estate", 0))
	var split: int = int(round(float(estate) * DIVORCE_ASSET_SPLIT))
	_state["estate"] = estate - split
	_state["mood"] = _clamp100(float(_state.get("mood", 50.0)) - DIVORCE_MOOD_PENALTY)
	_state["married"] = false
	_state["cohabiting"] = false
	var ex: Dictionary = _state.get("spouse", {})
	_state["spouse"] = {}
	return {"ok": true, "split": split, "mood": float(_state["mood"]), "ex": ex}


# --- 繁衍 ---

## 生育（R19.5）：子女遗传父母部分属性与天赋。
func give_birth(parent: Dictionary, spouse: Dictionary, name: String, gender: String = "female") -> Dictionary:
	var child: Dictionary = {"name": name, "gender": gender, "age": 0, "stage": "infant", "parent_id": str(parent.get("id", ""))}
	var ability: Dictionary = {}
	for key in ABILITY_KEYS:
		ability[key] = _inherit(parent, spouse, key)
	child["ability"] = ability
	var personality: Dictionary = {}
	for key in BIG_FIVE:
		personality[key] = _inherit(parent, spouse, key)
	child["personality"] = personality
	child["talents"] = _inherit_talents(parent, spouse)
	var children: Array = _state.get("children", [])
	children.append(child)
	_state["children"] = children
	return child


func _inherit(a: Dictionary, b: Dictionary, key: String) -> float:
	var va: float = _lookup(a, key, 50.0)
	var vb: float = _lookup(b, key, 50.0)
	var base: float = (va + vb) / 2.0 * HEREDITY_WEIGHT + 50.0 * (1.0 - HEREDITY_WEIGHT)
	if _rng != null:
		base += (_rng.next_float() * 2.0 - 1.0) * GENE_NOISE
	return _clamp100(base)


func _lookup(d: Dictionary, key: String, fallback: float) -> float:
	if d.has(key):
		return float(d[key])
	if d.has("attrs"):
		var attrs: Dictionary = d["attrs"]
		for group in attrs.values():
			if group is Dictionary and group.has(key):
				return float(group[key])
	return fallback


func _inherit_talents(a: Dictionary, b: Dictionary) -> Array:
	var tal_a: Array = a.get("talents", [])
	var tal_b: Array = b.get("talents", [])
	var out: Array = []
	for t in tal_a:
		if _rng != null and _rng.next_float() < 0.4:
			out.append(t)
	for t in tal_b:
		if not out.has(t) and _rng != null and _rng.next_float() < 0.4:
			out.append(t)
	return out


## 子女随世界时钟成长（R19.5）。
func grow_children(years: int) -> void:
	var children: Array = _state.get("children", [])
	for child in children:
		child["age"] = int(child.get("age", 0)) + years
		child["stage"] = _stage_of(int(child["age"]))
	_state["children"] = children


func _stage_of(age: int) -> String:
	if age < 3:
		return "infant"
	if age < 6:
		return "toddler"
	if age < 12:
		return "child"
	if age < 18:
		return "teen"
	return "adult"


## NPC 自发婚育：返回新增配对与新生儿数量（R19.7）。
func npc_auto_family(npc_count: int, rng = null) -> Dictionary:
	var marriages: int = 0
	var births: int = 0
	var singles: int = int(float(npc_count) * 0.4)
	while singles >= 2:
		singles -= 2
		if (rng.next_float() if rng != null else 0.0) < 0.5:
			marriages += 1
			if (rng.next_float() if rng != null else 0.0) < 0.6:
				births += 1
	return {"marriages": marriages, "births": births}


## 家庭每日开销（R19.6）。
func daily_expense() -> int:
	return int(_state.get("children", []).size()) * CHILD_DAILY_EXPENSE + int(_state.get("elders", []).size()) * ELDER_DAILY_EXPENSE


func add_elder(elder: Dictionary) -> void:
	var elders: Array = _state.get("elders", [])
	elders.append(elder)
	_state["elders"] = elders


func children() -> Array:
	return _state.get("children", [])


func to_dict() -> Dictionary:
	return _state.duplicate(true)


func from_dict(data: Dictionary) -> void:
	_state = data.duplicate(true)
