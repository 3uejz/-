class_name PanelRegistry
extends RefCounted
## 侧边抽屉面板注册与开合（R57；任务 47.2）。
## 12 个面板可多开并排；异常图鉴/金手指为条件可见。纯逻辑，headless 可测。

const COND_ALWAYS: String = "always"
const COND_ABNORMAL: String = "abnormal"
const COND_GOLDFINGER: String = "goldfinger"

const PANELS: Dictionary = {
	"character": {"title": "角色与属性", "condition": COND_ALWAYS},
	"skills": {"title": "技能树", "condition": COND_ALWAYS},
	"inventory": {"title": "背包与装备", "condition": COND_ALWAYS},
	"relations": {"title": "关系与人脉", "condition": COND_ALWAYS},
	"map": {"title": "地图", "condition": COND_ALWAYS},
	"career": {"title": "工作与职业", "condition": COND_ALWAYS},
	"finance": {"title": "资产与财务", "condition": COND_ALWAYS},
	"achievements": {"title": "成就与图鉴", "condition": COND_ALWAYS},
	"family": {"title": "家族史与传承", "condition": COND_ALWAYS},
	"anomaly": {"title": "异常图鉴", "condition": COND_ABNORMAL},
	"goldfinger": {"title": "金手指", "condition": COND_GOLDFINGER},
	"settings": {"title": "设置", "condition": COND_ALWAYS},
}

var _open: Array[String] = []       # 打开顺序（末尾为焦点）
var _focus: int = -1

func panel_ids() -> Array:
	var ids: Array = PANELS.keys()
	ids.sort()
	return ids

func title_of(id: String) -> String:
	return String((PANELS.get(id, {}) as Dictionary).get("title", id))

func exists(id: String) -> bool:
	return PANELS.has(id)

## 条件可见：仅返回满足条件的面板 id。
func available(conditions: Dictionary = {}) -> Array:
	var out: Array = []
	for id in panel_ids():
		if _visible(id, conditions):
			out.append(id)
	return out

func _visible(id: String, conditions: Dictionary) -> bool:
	var cond: String = String((PANELS.get(id, {}) as Dictionary).get("condition", COND_ALWAYS))
	match cond:
		COND_ABNORMAL:
			return bool(conditions.get("revealed_abnormal", false))
		COND_GOLDFINGER:
			return bool(conditions.get("goldfinger_enabled", false))
		_:
			return true

func open(id: String, conditions: Dictionary = {}) -> Dictionary:
	if not exists(id):
		return {"ok": false, "reason": "unknown_panel"}
	if not _visible(id, conditions):
		return {"ok": false, "reason": "hidden"}
	if _open.has(id):
		_focus = _open.find(id)
		return {"ok": true, "already_open": true}
	_open.append(id)
	_focus = _open.size() - 1
	return {"ok": true, "already_open": false}

func close(id: String) -> bool:
	var idx: int = _open.find(id)
	if idx < 0:
		return false
	_open.remove_at(idx)
	if _open.is_empty():
		_focus = -1
	else:
		_focus = clampi(_focus, 0, _open.size() - 1)
	return true

func toggle(id: String, conditions: Dictionary = {}) -> Dictionary:
	if is_open(id):
		close(id)
		return {"ok": true, "open": false}
	var r: Dictionary = open(id, conditions)
	r["open"] = is_open(id)
	return r

func is_open(id: String) -> bool:
	return _open.has(id)

func open_ids() -> Array:
	return _open.duplicate()

func open_count() -> int:
	return _open.size()

## 键盘焦点导航：在已打开面板间循环。
func focus_next() -> String:
	if _open.is_empty():
		return ""
	_focus = (_focus + 1) % _open.size()
	return _open[_focus]

func focus_prev() -> String:
	if _open.is_empty():
		return ""
	_focus = (_focus - 1 + _open.size()) % _open.size()
	return _open[_focus]

func focused() -> String:
	if _open.is_empty():
		return ""
	return _open[_focus]

func to_dict() -> Dictionary:
	return {"open": _open.duplicate(), "focus": _focus}

func from_dict(data: Dictionary) -> void:
	_open.clear()
	for id in data.get("open", []):
		if exists(String(id)):
			_open.append(String(id))
	_focus = clampi(int(data.get("focus", -1)), -1, _open.size() - 1)
