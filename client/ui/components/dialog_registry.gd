class_name DialogRegistry
extends RefCounted
## 关键弹窗注册与互斥（R57；任务 47.2）。
## 8 类弹窗；模态弹窗同一时刻至多一个；危险决策需二次确认后方可关闭。纯逻辑，headless 可测。

const DIALOGS: Dictionary = {
	"open_character_setup": {"title": "开档设定", "confirm": false, "dismissible": true},
	"event_choice": {"title": "事件选项", "confirm": false, "dismissible": false},
	"trade": {"title": "交易", "confirm": false, "dismissible": true},
	"dialogue": {"title": "对话", "confirm": false, "dismissible": true},
	"trial": {"title": "审判", "confirm": true, "dismissible": false},
	"dying": {"title": "临终", "confirm": true, "dismissible": false},
	"life_summary": {"title": "人生总结", "confirm": false, "dismissible": true},
	"inheritance": {"title": "传承结算", "confirm": true, "dismissible": false},
}

var _current: String = ""
var _confirmed: bool = false
var _payload: Dictionary = {}

func dialog_ids() -> Array:
	var ids: Array = DIALOGS.keys()
	ids.sort()
	return ids

func exists(id: String) -> bool:
	return DIALOGS.has(id)

func current() -> String:
	return _current

func is_open() -> bool:
	return not _current.is_empty()

## 打开弹窗。已有模态时拒绝；危险弹窗返回 needs_confirm。
func open(id: String, payload: Dictionary = {}) -> Dictionary:
	if not exists(id):
		return {"ok": false, "reason": "unknown_dialog"}
	if is_open():
		return {"ok": false, "reason": "modal_busy", "current": _current}
	_current = id
	_confirmed = false
	_payload = payload.duplicate(true)
	var needs: bool = bool((DIALOGS[id] as Dictionary).get("confirm", false))
	return {"ok": true, "modal": true, "needs_confirm": needs, "title": String(DIALOGS[id]["title"])}

## 二次确认危险操作。
func confirm() -> Dictionary:
	if not is_open():
		return {"ok": false, "reason": "no_dialog"}
	if not bool((DIALOGS[_current] as Dictionary).get("confirm", false)):
		return {"ok": false, "reason": "no_confirm_required"}
	_confirmed = true
	return {"ok": true, "confirmed": true}

func is_confirmed() -> bool:
	return _confirmed

## 关闭弹窗。危险弹窗未确认时拒绝；force 仅供程序内部流转使用。
func close(force: bool = false) -> Dictionary:
	if not is_open():
		return {"ok": false, "reason": "no_dialog"}
	var needs: bool = bool((DIALOGS[_current] as Dictionary).get("confirm", false))
	if needs and not _confirmed and not force:
		return {"ok": false, "reason": "need_confirm"}
	var closed: String = _current
	_current = ""
	_confirmed = false
	_payload = {}
	return {"ok": true, "closed": closed}

func payload() -> Dictionary:
	return _payload.duplicate(true)

func to_dict() -> Dictionary:
	return {"current": _current, "confirmed": _confirmed, "payload": _payload.duplicate(true)}

func from_dict(data: Dictionary) -> void:
	var id: String = String(data.get("current", ""))
	_current = id if exists(id) else ""
	_confirmed = bool(data.get("confirmed", false))
	_payload = Dictionary(data.get("payload", {})).duplicate(true)
