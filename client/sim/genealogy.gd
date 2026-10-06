class_name GenealogySystem
extends RefCounted
## 家族史与族谱（R97；design「世界记忆与家族史」）。
##
## 族谱树由人物节点（persons）与亲子/配偶边构成；记录历代大事（chronicle）与死亡；
## 支持祖先/后代追溯、世代计算、跨代检索与持久化。面板（任务 47）仅消费本模型。
##
## 设计取舍：人物以纯 Dictionary 表示，树结构自包含、可序列化；不与 FamilySystem
## 的运行时家庭成员绑定，死亡传承时由上层把关键人物投影进来，保持系统松耦合。

const STATUS_ALIVE: String = "alive"
const STATUS_DEAD: String = "dead"


func new_tree() -> Dictionary:
	return {"persons": {}, "seq": 0, "roots": [], "chronicle": []}


func new_person() -> Dictionary:
	return {
		"id": "", "name": "", "gender": "unknown", "generation": 1,
		"birth_minute": 0, "death_minute": -1, "cause": "",
		"parent_ids": [], "spouse_ids": [], "child_ids": [],
		"status": STATUS_ALIVE,
	}


func add_person(tree: Dictionary, spec: Dictionary) -> Dictionary:
	var persons: Dictionary = tree["persons"]
	var id: String = str(spec.get("id", ""))
	if id == "":
		tree["seq"] = int(tree["seq"]) + 1
		id = "p_%d" % int(tree["seq"])
	if persons.has(id):
		return {"ok": false, "reason": "duplicate_id", "id": id}
	var person: Dictionary = new_person()
	person["id"] = id
	person["name"] = str(spec.get("name", ""))
	person["gender"] = str(spec.get("gender", "unknown"))
	person["generation"] = int(spec.get("generation", 1))
	person["birth_minute"] = int(spec.get("birth_minute", 0))
	person["death_minute"] = int(spec.get("death_minute", -1))
	person["cause"] = str(spec.get("cause", ""))
	person["status"] = str(spec.get("status", STATUS_ALIVE))
	persons[id] = person
	if not (tree["roots"] as Array).has(id):
		tree["roots"].append(id)
	return {"ok": true, "id": id}


## 建立亲子边并推导子代世代（父世代 +1，取更大值）。
func link_parent_child(tree: Dictionary, parent_id: String, child_id: String) -> Dictionary:
	var persons: Dictionary = tree["persons"]
	if not persons.has(parent_id) or not persons.has(child_id):
		return {"ok": false, "reason": "not_found"}
	if parent_id == child_id:
		return {"ok": false, "reason": "self_link"}
	var parent: Dictionary = persons[parent_id]
	var child: Dictionary = persons[child_id]
	if not (parent["child_ids"] as Array).has(child_id):
		parent["child_ids"].append(child_id)
	if not (child["parent_ids"] as Array).has(parent_id):
		child["parent_ids"].append(parent_id)
	child["generation"] = maxi(int(child["generation"]), int(parent["generation"]) + 1)
	(tree["roots"] as Array).erase(child_id)
	return {"ok": true}


func link_spouse(tree: Dictionary, a_id: String, b_id: String) -> Dictionary:
	var persons: Dictionary = tree["persons"]
	if not persons.has(a_id) or not persons.has(b_id):
		return {"ok": false, "reason": "not_found"}
	if a_id == b_id:
		return {"ok": false, "reason": "self_link"}
	if not (persons[a_id]["spouse_ids"] as Array).has(b_id):
		persons[a_id]["spouse_ids"].append(b_id)
	if not (persons[b_id]["spouse_ids"] as Array).has(a_id):
		persons[b_id]["spouse_ids"].append(a_id)
	return {"ok": true}


func mark_death(tree: Dictionary, person_id: String, minute: int, cause: String) -> Dictionary:
	var persons: Dictionary = tree["persons"]
	if not persons.has(person_id):
		return {"ok": false, "reason": "not_found"}
	var person: Dictionary = persons[person_id]
	person["status"] = STATUS_DEAD
	person["death_minute"] = minute
	person["cause"] = cause
	add_chronicle(tree, {"minute": minute, "generation": int(person["generation"]), "person_id": person_id, "text": "%s 卒（%s）" % [person["name"], cause]})
	return {"ok": true}


## 历代大事（按时间排序）。
func add_chronicle(tree: Dictionary, record: Dictionary) -> Dictionary:
	var entry: Dictionary = {
		"minute": int(record.get("minute", 0)),
		"generation": int(record.get("generation", 0)),
		"person_id": str(record.get("person_id", "")),
		"text": str(record.get("text", "")),
	}
	(tree["chronicle"] as Array).append(entry)
	(tree["chronicle"] as Array).sort_custom(func(a, b): return int(a["minute"]) < int(b["minute"]))
	return {"ok": true, "total": (tree["chronicle"] as Array).size()}


func chronicle(tree: Dictionary) -> Array:
	return (tree["chronicle"] as Array).duplicate(true)


## 祖先链（含自身，深度优先去重，近亲优先）。
func ancestors(tree: Dictionary, person_id: String, max_depth: int = 32) -> Array:
	var persons: Dictionary = tree["persons"]
	var out: Array = []
	if not persons.has(person_id):
		return out
	var frontier: Array = [person_id]
	var seen: Dictionary = {person_id: true}
	var depth: int = 0
	while not frontier.is_empty() and depth < max_depth:
		var next: Array = []
		for pid in frontier:
			for parent_id in persons[pid]["parent_ids"]:
				if not seen.has(parent_id):
					seen[parent_id] = true
					out.append(parent_id)
					next.append(parent_id)
		frontier = next
		depth += 1
	return out


## 后代链（不含自身，广度优先去重）。
func descendants(tree: Dictionary, person_id: String, max_depth: int = 32) -> Array:
	var persons: Dictionary = tree["persons"]
	var out: Array = []
	if not persons.has(person_id):
		return out
	var frontier: Array = [person_id]
	var seen: Dictionary = {person_id: true}
	var depth: int = 0
	while not frontier.is_empty() and depth < max_depth:
		var next: Array = []
		for pid in frontier:
			for child_id in persons[pid]["child_ids"]:
				if not seen.has(child_id):
					seen[child_id] = true
					out.append(child_id)
					next.append(child_id)
		frontier = next
		depth += 1
	return out


## 跨代检索：按姓名/死因关键字匹配人物。
func search(tree: Dictionary, keyword: String) -> Array:
	var out: Array = []
	if keyword == "":
		return out
	for person in (tree["persons"] as Dictionary).values():
		if str(person["name"]).contains(keyword) or str(person["cause"]).contains(keyword):
			out.append(person.duplicate(true))
	out.sort_custom(func(a, b): return int(a["generation"]) < int(b["generation"]))
	return out


## 家族史概要（面板头部）。
func summary(tree: Dictionary) -> Dictionary:
	var persons: Dictionary = tree["persons"]
	var alive: int = 0
	var max_gen: int = 0
	for person in persons.values():
		if str(person["status"]) == STATUS_ALIVE:
			alive += 1
		max_gen = maxi(max_gen, int(person["generation"]))
	return {
		"total": persons.size(), "alive": alive, "generations": max_gen,
		"roots": (tree["roots"] as Array).duplicate(), "chronicle_count": (tree["chronicle"] as Array).size(),
	}


func to_dict(tree: Dictionary) -> Dictionary:
	return tree.duplicate(true)


func from_dict(data: Dictionary) -> Dictionary:
	return {
		"persons": (data.get("persons", {}) as Dictionary).duplicate(true),
		"seq": int(data.get("seq", 0)),
		"roots": (data.get("roots", []) as Array).duplicate(),
		"chronicle": (data.get("chronicle", []) as Array).duplicate(true),
	}
