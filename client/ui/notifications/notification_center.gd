class_name NotificationCenter
extends RefCounted
## 通知中心：桌面通知分类开关 + 托盘常驻 + 点击聚焦（R35、R57；任务 47 收尾）。
## 组合 NotificationPrefs（分类/托盘）与可选 poster（系统通知投递，注入 Callable）；
## 窗口未聚焦时入队为游戏内角标，聚焦后 drain。纯逻辑，headless 可测。

const PrefsScript = preload("res://ui/notifications/notification_prefs.gd")

var prefs
## 系统通知投递回调：func(title: String, body: String)。缺失时降级为仅游戏内角标。
var poster: Callable = Callable()
var focused: bool = true

var _queue: Array = []

func _init(prefs_obj = null) -> void:
	prefs = prefs_obj if prefs_obj != null else PrefsScript.new()

func categories() -> Array:
	return prefs.categories()

func is_enabled(category: String) -> bool:
	return prefs.is_enabled(category)

func set_enabled(category: String, value: bool) -> bool:
	return prefs.set_enabled(category, value)

func set_tray_enabled(value: bool) -> void:
	prefs.set_tray_enabled(value)

## 托盘常驻时世界是否应继续按 1x 推进（最小化后仍运行）。
func should_advance_world() -> bool:
	return bool(prefs.tray_enabled)

## 触发通知。返回 {sent, queued, reason, panel}。
## category 关闭时被静音（危险类受安全阀强制）；未聚焦时入队。
func notify(category: String, title: String, body: String = "", panel: String = "") -> Dictionary:
	if not prefs.should_notify(category):
		return {"sent": false, "queued": false, "reason": "muted", "panel": panel}
	if poster.is_valid():
		poster.call(title, body)
	var queued: bool = not focused
	if queued:
		_queue.append({"category": category, "title": title, "body": body, "panel": panel})
	return {"sent": true, "queued": queued, "reason": "ok", "panel": panel}

func pending() -> int:
	return _queue.size()

func peek() -> Array:
	return _queue.duplicate(true)

## 聚焦窗口；返回被排空的队列（供角标汇总）。
func focus() -> Array:
	focused = true
	return drain()

func blur() -> void:
	focused = false

func drain() -> Array:
	var items: Array = _queue.duplicate(true)
	_queue.clear()
	return items

func to_dict() -> Dictionary:
	return {"focused": focused, "queue": _queue.duplicate(true), "prefs": prefs.to_dict()}

func from_dict(data: Dictionary) -> void:
	focused = bool(data.get("focused", true))
	_queue = (data.get("queue", []) as Array).duplicate(true)
	prefs.from_dict(Dictionary(data.get("prefs", {})))
