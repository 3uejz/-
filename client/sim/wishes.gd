class_name WishSystem
extends RefCounted
## 人生愿望（R30；design「死亡、传承与轮回」）。
##
## 玩家自设愿望，同时最多 3 个；追踪进度并在达成时庆祝；达成后可设定新愿望。

const BaselineScript = preload("res://sim/baseline.gd")

const MAX_WISHES: int = BaselineScript.WISH_MAX_WISHES
const WISH_TYPES: Array = ["wealth", "skill", "relationship", "career", "travel", "family", "custom"]
const WISH_TYPE_NAMES: Dictionary = {
	"wealth": "财富", "skill": "技能", "relationship": "情感", "career": "事业",
	"travel": "旅行", "family": "家庭", "custom": "自定义",
}


func new_state() -> Dictionary:
	return {"wishes": [], "celebrations": []}


func active_count(state: Dictionary) -> int:
	var n: int = 0
	for w in state["wishes"]:
		if not bool(w["completed"]):
			n += 1
	return n


## 设定愿望（R30.1、R30.3）：未完成愿望满 3 个时拒绝；达成后可设定新愿望。
func set_wish(state: Dictionary, wish_id: String, type: String, description: String, target: float) -> Dictionary:
	if not WISH_TYPES.has(type):
		return {"ok": false, "reason": "unknown_type"}
	for w in state["wishes"]:
		if str(w["id"]) == wish_id:
			return {"ok": false, "reason": "duplicate_id"}
	if active_count(state) >= MAX_WISHES:
		return {"ok": false, "reason": "wish_limit_reached", "max": MAX_WISHES}
	state["wishes"].append({"id": wish_id, "type": type, "description": description, "target": maxf(0.0, target), "progress": 0.0, "completed": false})
	return {"ok": true, "wish_id": wish_id, "active": active_count(state)}


## 追踪进度（R30.2）。
func update_progress(state: Dictionary, type: String, value: float) -> Dictionary:
	var completed: Array = []
	for w in state["wishes"]:
		if bool(w["completed"]) or str(w["type"]) != type:
			continue
		w["progress"] = maxf(float(w["progress"]), value)
		if float(w["target"]) > 0.0 and float(w["progress"]) >= float(w["target"]):
			w["completed"] = true
			state["celebrations"].append("愿望达成：%s" % str(w["description"]))
			completed.append(str(w["id"]))
	return {"ok": true, "completed": completed}


## 达成庆祝记录（R30.2）。
func celebrations(state: Dictionary) -> Array:
	return (state["celebrations"] as Array).duplicate()


## 可设定新愿望数量（R30.3）。
func available_slots(state: Dictionary) -> int:
	return maxi(0, MAX_WISHES - active_count(state))


func to_dict(state: Dictionary) -> Dictionary:
	return state.duplicate(true)


func from_dict(data: Dictionary) -> Dictionary:
	return {"wishes": (data.get("wishes", []) as Array).duplicate(true), "celebrations": (data.get("celebrations", []) as Array).duplicate(true)}
