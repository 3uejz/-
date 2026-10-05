class_name WorldMemorySystem
extends RefCounted
## 世界记忆与家族史（R31、R29；design「世界记忆与家族史」）。
##
## 四类载体：传说事件、世交世仇、称号纪念、隐藏事件；由重大行为生成，带重大度与
## 时间戳；按重大度设定半衰期衰减，被引用或传播可减缓；影响后代初始态度并解锁事件；
## 随世界延续而非角色死亡清除。

const CARRIERS: Array = ["legend", "feud", "title", "hidden"]
const CARRIER_NAMES: Dictionary = {"legend": "传说事件", "feud": "世交世仇", "title": "称号纪念", "hidden": "隐藏事件"}

const BASE_HALF_LIFE_DAYS: float = 30.0
const FADE_THRESHOLD: float = 1.0


func carriers() -> Array:
	return CARRIERS.duplicate()


func new_store() -> Dictionary:
	return {"memories": [], "seq": 0}


## 生成世界记忆（R29/R31）。gravity 0..100，重大度越高衰减越慢。
func add_memory(store: Dictionary, carrier: String, description: String, gravity: float, minute: int, subjects: Array = []) -> Dictionary:
	if not CARRIERS.has(carrier):
		return {"ok": false, "reason": "unknown_carrier"}
	store["seq"] = int(store["seq"]) + 1
	var mem: Dictionary = {
		"id": "%s_%d" % [carrier, int(store["seq"])],
		"carrier": carrier, "description": description,
		"gravity": clampf(gravity, 0.0, 100.0), "minute": minute,
		"subjects": subjects.duplicate(), "references": 0,
	}
	store["memories"].append(mem)
	return {"ok": true, "id": mem["id"], "name": CARRIER_NAMES[carrier]}


func half_life_days(gravity: float) -> float:
	return BASE_HALF_LIFE_DAYS * (1.0 + clampf(gravity, 0.0, 100.0) / 20.0)


## 当前权重（按半衰期衰减）（design「衰减」）。
func current_weight(memory: Dictionary, now_minute: int) -> float:
	var days: float = float(now_minute - int(memory["minute"])) / 1440.0
	var hl: float = half_life_days(float(memory["gravity"]))
	var refs: int = int(memory.get("references", 0))
	var slow: float = 1.0 + float(refs) * 0.25
	return float(memory["gravity"]) * pow(0.5, maxf(0.0, days) / (hl * slow))


## 引用/传播减缓衰减（design「作用」）。
func cite_memory(store: Dictionary, memory_id: String) -> Dictionary:
	for m in store["memories"]:
		if str(m["id"]) == memory_id:
			m["references"] = int(m["references"]) + 1
			return {"ok": true, "references": int(m["references"])}
	return {"ok": false, "reason": "not_found"}


## 清理已淡出的记忆（design「衰减」）。
func tick(store: Dictionary, now_minute: int) -> Dictionary:
	var survivors: Array = []
	var faded: int = 0
	for m in store["memories"]:
		if current_weight(m, now_minute) >= FADE_THRESHOLD:
			survivors.append(m)
		else:
			faded += 1
	store["memories"] = survivors
	return {"ok": true, "faded": faded, "remaining": survivors.size()}


## 影响后代/NPC 初始态度（design「作用」）。
func attitude_modifier(store: Dictionary, subject: String, now_minute: int) -> float:
	var total: float = 0.0
	for m in store["memories"]:
		if (m["subjects"] as Array).has(subject):
			total += current_weight(m, now_minute)
	return clampf(total / 200.0, -1.0, 1.0)


## 按重大度排序的检索（家族史面板）。
func top_memories(store: Dictionary, now_minute: int, limit: int = 10) -> Array:
	var decorated: Array = []
	for m in store["memories"]:
		decorated.append({"memory": m, "weight": current_weight(m, now_minute)})
	decorated.sort_custom(func(a, b): return float(a["weight"]) > float(b["weight"]))
	var out: Array = []
	for i in mini(limit, decorated.size()):
		out.append(decorated[i]["memory"])
	return out


func to_dict(store: Dictionary) -> Dictionary:
	return store.duplicate(true)


func from_dict(data: Dictionary) -> Dictionary:
	return {"memories": (data.get("memories", []) as Array).duplicate(true), "seq": int(data.get("seq", 0))}
