extends "res://tests/test_base.gd"
## 主界面壳端到端冒烟测试（任务 47/51）：主题应用、抽屉容器、两验证面板开合多开。
## 主壳需在首帧后方进入就绪态，故测试推迟到 _process 执行。

var _main
var _ran := false

func _suite_name() -> String:
	return "ui_shell"

func _initialize() -> void:
	print("[test] %s" % _suite_name())
	var packed = load("res://ui/main.tscn")
	if packed == null:
		_fail("main.tscn 无法加载")
		quit(failures)
		return
	_main = packed.instantiate()
	root.add_child(_main)

func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	run_tests()
	if failures == 0:
		print("[test] %s PASS" % _suite_name())
	else:
		print("[test] %s FAILURES: %d" % [_suite_name(), failures])
	quit(failures)
	return true

func run_tests() -> void:
	_test_scene_ready()
	_test_panel_open_close()

func _test_scene_ready() -> void:
	check(_main.is_node_ready(), "主壳进入就绪态")
	check(_main.theme != null, "主壳已应用主题")
	check(_main.get_node_or_null("Root/Drawers") != null, "已创建抽屉容器")
	check_eq(_main.panel_count(), 0, "初始无打开面板")
	check(_main.has_method("open_panel"), "暴露面板接口")

func _test_panel_open_close() -> void:
	check(_main.open_panel("character"), "打开角色面板")
	check(_main.has_panel("character"), "角色面板存在")
	check(_main.open_panel("inventory"), "打开背包面板")
	check_eq(_main.panel_count(), 2, "可多开并排")
	check(_main.close_panel("character"), "关闭角色面板")
	check(not _main.has_panel("character"), "角色面板已移除")
	check_eq(_main.panel_count(), 1, "关闭后剩一个面板")
	check(not _main.open_panel("does_not_exist"), "未知面板拒绝打开")
	check(_main.open_panel("settings"), "打开设置面板")
	check(_main.has_panel("settings"), "设置面板存在")
	_main.free()
