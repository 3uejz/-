class_name MemorySystem
extends RefCounted
## NPC 记忆条目队列（R50.5–R50.6；design D10）。
##
## 规则：
##   - 每 NPC 条目上限约 50，超出按「情感权重绝对值 × 新鲜度」淘汰；
##   - 字段：类型、时间戳、涉及对象、情感权重(−100..100)、重大度、可见性；
##   - 半衰期随重大度（越重大记得越久）；被反复引用则加固；
##   - 按情境检索相关记忆供叙事引用；冲突取情感权重高者；
##   - NPC 死亡后记忆归档为遗产线索/世界记忆素材。

const MAX_ENTRIES: int = 50
const BASE_HALF_LIFE_YEARS: float = 1.0
const MAX_HALF_LIFE_YEARS: float = 10.0
const REINFORCE_AMOUNT: float = 5.0
const MINUTES_PER_YEAR: float = 365.25 * 1440.0

## 记忆类型。
const TYPES: Array = ["shared_experience", "promise", "conflict", "secret", "favor"]

var _seq: int = 0


func _entries(npc: Dictionary) -> Array:
	if not npc.has("memory") or typeof(npc["memory"]) != TYPE_ARRAY:
		npc["memory"] = []
	return npc["memory"]


## 半衰期（年）：重大度越高越长。
func half_life_years(severity: float) -> float:
	var s: float = clampf(severity, 0.0, 100.0)
	return clampf(BASE_HALF_LIFE_YEARS + s / 100.0 * (MAX_HALF_LIFE_YEARS - BASE_HALF_LIFE_YEARS),
		BASE_HALF_LIFE_YEARS, MAX_HALF_LIFE_YEARS)


## 新鲜度 0..1，随年龄按半衰期指数衰减。
func freshness(entry: Dictionary, now_minute: int) -> float:
	var age_years: float = maxf(0.0, float(now_minute - int(entry.get("minute", 0))) / MINUTES_PER_YEAR)
	var hl: float = half_life_years(float(entry.get("severity", 0.0)))
	return pow(0.5, age_years / maxf(0.01, hl))


## 有效强度 = |情感权重| × 新鲜度 ×（引用加固）。
func effective_weight(entry: Dictionary, now_minute: int) -> float:
	var refs: int = int(entry.get("refs", 0))
	var reinforce: float = 1.0 + 0.1 * float(refs)
	return absf(float(entry.get("weight", 0.0))) * freshness(entry, now_minute) * reinforce


## 添加记忆；超上限时淘汰有效强度最低者。返回条目。
func add_memory(npc: Dictionary, entry: Dictionary) -> Dictionary:
	var list: Array = _entries(npc)
	_seq += 1
	var mem: Dictionary = {
		"id": str(entry.get("id", "mem.%d" % _seq)),
		"type": str(entry.get("type", "shared_experience")),
		"content": str(entry.get("content", "")),
		"minute": int(entry.get("minute", 0)),
		"subjects": (entry.get("subjects", []) as Array).duplicate(),
		"weight": clampf(float(entry.get("weight", 0.0)), -100.0, 100.0),
		"severity": clampf(float(entry.get("severity", 0.0)), 0.0, 100.0),
		"visibility": str(entry.get("visibility", "private")),
		"refs": int(entry.get("refs", 0)),
		"archived": false,
	}
	list.append(mem)
	_prune(npc)
	return mem


func _prune(npc: Dictionary) -> void:
	var list: Array = _entries(npc)
	if list.size() <= MAX_ENTRIES:
		return
	var now: int = _latest_minute(list)
	# 找出有效强度最低的条目并移除（保留最近）。
	var worst_idx: int = 0
	var worst: float = INF
	for i in list.size():
		var eff: float = effective_weight(list[i], now)
		if eff < worst:
			worst = eff
			worst_idx = i
	list.remove_at(worst_idx)


func _latest_minute(list: Array) -> int:
	var latest: int = 0
	for m in list:
		latest = maxi(latest, int((m as Dictionary).get("minute", 0)))
	return latest


## 检索相关记忆：按情境的涉及对象/类型过滤，按有效强度排序，返回前 k 条。
func retrieve(npc: Dictionary, context: Dictionary, k: int = 3) -> Array:
	var subjects: Array = context.get("subjects", [])
	var types: Array = context.get("types", [])
	var now: int = int(context.get("now_minute", _latest_minute(_entries(npc))))
	var candidates: Array = []
	for mem in _entries(npc):
		if bool((mem as Dictionary).get("archived", false)):
			continue
		var m: Dictionary = mem
		var matched: bool = subjects.is_empty() and types.is_empty()
		if not subjects.is_empty():
			var ms: Array = m.get("subjects", [])
			for s in subjects:
				if ms.has(s):
					matched = true
					break
		if not matched and not types.is_empty() and types.has(str(m.get("type", ""))):
			matched = true
		if matched:
			candidates.append(m)
	candidates.sort_custom(func(a, b): return effective_weight(a, now) > effective_weight(b, now))
	if candidates.size() > k:
		candidates.resize(k)
	return candidates


## 引用加固：情感权重按符号增强并计引用次数。
func reinforce(npc: Dictionary, memory_id: String) -> Dictionary:
	for mem in _entries(npc):
		if str((mem as Dictionary).get("id", "")) == memory_id:
			var m: Dictionary = mem
			var w: float = float(m.get("weight", 0.0))
			var sign: float = 1.0 if w >= 0.0 else -1.0
			m["weight"] = clampf(w + sign * REINFORCE_AMOUNT, -100.0, 100.0)
			m["refs"] = int(m.get("refs", 0)) + 1
			return m
	return {}


## 时间衰减：按半衰期收缩情感权重幅度，随时间淡忘。
func decay_all(npc: Dictionary, years: float) -> int:
	var count: int = 0
	for mem in _entries(npc):
		var m: Dictionary = mem
		var hl: float = half_life_years(float(m.get("severity", 0.0)))
		var factor: float = pow(0.5, maxf(0.0, years) / maxf(0.01, hl))
		m["weight"] = clampf(float(m.get("weight", 0.0)) * factor, -100.0, 100.0)
		count += 1
	return count


## 冲突消解：同一事件的多条记忆取有效强度（情感权重）高者。
func resolve_conflict(entries: Array, now_minute: int = 0) -> Dictionary:
	var best: Dictionary = {}
	var best_eff: float = -1.0
	for e in entries:
		if not (e is Dictionary):
			continue
		var eff: float = effective_weight(e, now_minute)
		if eff > best_eff:
			best_eff = eff
			best = e
	return best


## 死亡归档：全部条目标记归档，返回归档副本（供遗产线索/世界记忆）。
func archive_on_death(npc: Dictionary) -> Array:
	var archived: Array = []
	for mem in _entries(npc):
		var m: Dictionary = mem
		m["archived"] = true
		if str(m.get("visibility", "private")) == "public" or float(m.get("severity", 0.0)) >= 70.0:
			archived.append(m.duplicate(true))
	return archived


## 生成对话可引用的记忆句子（叙事层用）。
func dialogue_citations(npc: Dictionary, context: Dictionary, k: int = 3) -> Array:
	var out: Array = []
	for mem in retrieve(npc, context, k):
		var m: Dictionary = mem
		var text: String = str(m.get("content", ""))
		if text == "":
			text = str(m.get("type", ""))
		out.append(text)
	return out


func count(npc: Dictionary) -> int:
	return _entries(npc).size()


func to_dict(npc: Dictionary) -> Array:
	return _entries(npc).duplicate(true)
