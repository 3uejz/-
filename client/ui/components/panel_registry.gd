class_name PanelRegistry
extends RefCounted
## 侧边抽屉面板注册与开合（R57；任务 47.2）。
## 41 个面板可多开并排；异常图鉴/金手指/人生结算为条件可见（全量面板清单见 `ui.md` §4）。纯逻辑，headless 可测。

const COND_ALWAYS: String = "always"
const COND_ABNORMAL: String = "abnormal"
const COND_GOLDFINGER: String = "goldfinger"
const COND_DEAD: String = "dead"

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
	"business": {"title": "经营", "condition": COND_ALWAYS},
	"organizations": {"title": "组织", "condition": COND_ALWAYS},
	"legal": {"title": "案件与法律", "condition": COND_ALWAYS},
	"rescue": {"title": "救援与灾害", "condition": COND_ALWAYS},
	"environment": {"title": "环保与碳市场", "condition": COND_ALWAYS},
	"municipal": {"title": "市政", "condition": COND_ALWAYS},
	"debt": {"title": "债务与催收", "condition": COND_ALWAYS},
	"consumer": {"title": "维权与消费", "condition": COND_ALWAYS},
	"welfare": {"title": "救助与福利", "condition": COND_ALWAYS},
	"funeral": {"title": "殡葬", "condition": COND_ALWAYS},
	"metaphysics": {"title": "玄学", "condition": COND_ALWAYS},
	"medical": {"title": "医疗", "condition": COND_ALWAYS},
	"mental": {"title": "精神健康", "condition": COND_ALWAYS},
	"spirit": {"title": "精神追求", "condition": COND_ALWAYS},
	"language": {"title": "语言与文化", "condition": COND_ALWAYS},
	"content_industry": {"title": "文娱", "condition": COND_ALWAYS},
	"engineering": {"title": "工程与基建", "condition": COND_ALWAYS},
	"services": {"title": "专业与生活服务", "condition": COND_ALWAYS},
	"transport_infra": {"title": "交通基建", "condition": COND_ALWAYS},
	"household": {"title": "家庭与宠物", "condition": COND_ALWAYS},
	"sports": {"title": "体育", "condition": COND_ALWAYS},
	"events": {"title": "活动与展会", "condition": COND_ALWAYS},
	"awards": {"title": "奖项与荣誉", "condition": COND_ALWAYS},
	"digital": {"title": "数字与平台", "condition": COND_ALWAYS},
	"epidemic": {"title": "疫情与公共卫生", "condition": COND_ALWAYS},
	"war": {"title": "战争与军旅", "condition": COND_ALWAYS},
	"market": {"title": "宏观行情", "condition": COND_ALWAYS},
	"weather": {"title": "天气预报", "condition": COND_ALWAYS},
	"anomaly": {"title": "异常图鉴", "condition": COND_ABNORMAL},
	"goldfinger": {"title": "金手指", "condition": COND_GOLDFINGER},
	"ending": {"title": "人生结算", "condition": COND_DEAD},
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
		COND_DEAD:
			return bool(conditions.get("dead", false))
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
