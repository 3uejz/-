@tool
extends EditorPlugin
## 内容工具插件入口（R36.12）：注册内容面板，支持校验、重导入与预览。

const DockScript = preload("res://addons/content_preview/content_dock.gd")

var _dock: Control


func _enter_tree() -> void:
	_dock = DockScript.new()
	_dock.name = "内容工具"
	add_control_to_dock(DOCK_SLOT_RIGHT_BL, _dock)


func _exit_tree() -> void:
	if is_instance_valid(_dock):
		remove_control_from_docks(_dock)
		_dock.queue_free()
	_dock = null
