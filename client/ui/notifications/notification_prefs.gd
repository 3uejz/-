class_name NotificationPrefs
extends RefCounted
## 通知分类开关与系统托盘（R35、R57；任务 47.3）。
## 桌面通知按类别可开关；托盘常驻可继续推进世界。纯逻辑，headless 可测。

const CATEGORIES: Array[String] = [
	"work", "medication", "repayment", "appointment", "health_danger", "event", "social",
]

## 危险类通知即使关闭分类，仍受安全阀强制弹出（见 ui.md 9）。
const SAFETY_OVERRIDE: Array[String] = ["health_danger"]

var tray_enabled: bool = true
var _enabled: Dictionary = {}

func _init() -> void:
	for c in CATEGORIES:
		_enabled[c] = true

func categories() -> Array:
	return CATEGORIES.duplicate()

func is_enabled(category: String) -> bool:
	if not _enabled.has(category):
		return false
	return bool(_enabled[category])

func set_enabled(category: String, value: bool) -> bool:
	if not _enabled.has(category):
		return false
	_enabled[category] = value
	return true

func set_tray_enabled(value: bool) -> void:
	tray_enabled = value

## 是否应发送桌面通知。
func should_notify(category: String) -> bool:
	if SAFETY_OVERRIDE.has(category):
		return true
	if not _enabled.has(category):
		return false
	return tray_enabled and bool(_enabled[category])

func to_dict() -> Dictionary:
	return {"tray_enabled": tray_enabled, "enabled": _enabled.duplicate(true)}

func from_dict(data: Dictionary) -> void:
	tray_enabled = bool(data.get("tray_enabled", true))
	var raw: Dictionary = Dictionary(data.get("enabled", {}))
	for c in CATEGORIES:
		_enabled[c] = bool(raw.get(c, true))
