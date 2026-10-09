extends "res://tests/test_base.gd"
## UI 行为测试（任务 47.2、47.3）：面板开合与焦点、弹窗互斥与二次确认、打字机、通知分类。

const TypewriterScript = preload("res://ui/layout/typewriter.gd")
const NotifyScript = preload("res://ui/notifications/notification_prefs.gd")
const PanelScript = preload("res://ui/components/panel_registry.gd")
const DialogScript = preload("res://ui/components/dialog_registry.gd")
const SettingsScript = preload("res://ui/settings/settings_model.gd")

func _suite_name() -> String:
	return "ui_behavior"

func run_tests() -> void:
	_test_typewriter()
	_test_notification_prefs()
	_test_panel_open_multi()
	_test_panel_conditions_and_focus()
	_test_dialog_exclusive_and_confirm()
	_test_keymap_and_tts()
	_test_serialization()

func _test_keymap_and_tts() -> void:
	var s = SettingsScript.new()
	check_eq(s.key_for("toggle_pause"), "space", "默认键位")
	check(s.bind("open_backpack", "b")["ok"], "重映射成功")
	check_eq(s.key_for("open_backpack"), "b", "键位已更新")
	var conflict: Dictionary = s.bind("open_status", "b")
	check(not conflict["ok"], "冲突键位被拒绝")
	check_eq(str(conflict.get("conflict", "")), "open_backpack", "报告冲突动作")
	s.reset_keys()
	check_eq(s.key_for("open_backpack"), "i", "恢复默认键位")
	# TTS：平台不可用则保持关闭。
	check(not s.set_tts_enabled(true)["ok"], "无 TTS 时开启失败")
	check(not s.tts_enabled, "无 TTS 时保持关闭")
	s.set_tts_available(true)
	check(s.set_tts_enabled(true)["ok"], "可用时开启成功")
	check(s.tts_enabled, "TTS 已开启")
	check_eq(s.tts_status(), "已开启", "TTS 状态")

func _test_typewriter() -> void:
	var instant = TypewriterScript.new("你好世界", true)
	check(instant.is_done(), "减少动态整条显示")
	check_eq(instant.current(), "你好世界", "减少动态全文")
	var tw = TypewriterScript.new("abcdef", false)
	check(not tw.is_done(), "初始未完成")
	check_eq(tw.current(), "", "初始无字")
	tw.chars_per_second = 10.0
	var partial: String = tw.tick(0.25)
	check_eq(partial.length(), 2, "0.25 秒揭示 2 字")
	tw.tick(10.0)
	check(tw.is_done(), "足够时间后完成")
	check_eq(tw.current(), "abcdef", "完成后全文")
	var tw2 = TypewriterScript.new("longtext", false)
	tw2.tick(0.1)
	tw2.skip()
	check(tw2.is_done(), "跳过立即完成")
	check_near(tw2.progress(), 1.0, 1e-6, "进度到 1")

func _test_notification_prefs() -> void:
	var n = NotifyScript.new()
	check(n.is_enabled("work"), "默认开启")
	check(n.should_notify("work"), "默认可通知")
	n.set_enabled("work", false)
	check(not n.should_notify("work"), "关闭后不通知")
	n.set_tray_enabled(false)
	check(not n.should_notify("event"), "托盘关闭则不通知")
	# 安全阀：危险通知强制弹出。
	n.set_enabled("health_danger", false)
	check(n.should_notify("health_danger"), "安全阀强制通知")
	check(not n.set_enabled("nope", true), "未知分类拒绝")

func _test_panel_open_multi() -> void:
	var p = PanelScript.new()
	check(p.open("character")["ok"], "打开角色面板")
	check(p.open("inventory")["ok"], "打开背包面板")
	check_eq(p.open_count(), 2, "可多开并排")
	check(p.is_open("character") and p.is_open("inventory"), "两个面板均打开")
	check(p.open("character")["already_open"], "重复打开标记已开")
	p.toggle("inventory")
	check(not p.is_open("inventory"), "切换关闭")
	check(not p.open("nope")["ok"], "未知面板拒绝")

func _test_panel_conditions_and_focus() -> void:
	var p = PanelScript.new()
	var base: Array = p.available({})
	check(not base.has("anomaly"), "未接触异常时隐藏异常图鉴")
	check(not base.has("goldfinger"), "未启用金手指时隐藏")
	var revealed: Array = p.available({"revealed_abnormal": true, "goldfinger_enabled": true})
	check(revealed.has("anomaly") and revealed.has("goldfinger"), "条件满足后可见")
	check(not p.open("anomaly", {})["ok"], "条件面板未满足拒绝打开")
	check(p.open("anomaly", {"revealed_abnormal": true})["ok"], "条件满足可打开")
	p.open("character")
	p.open("finance")
	check_eq(p.focused(), "finance", "最后打开为焦点")
	check_eq(p.focus_next(), "anomaly", "焦点循环到首个")
	check_eq(p.focus_prev(), "finance", "焦点回退")
	check_eq(p.focus_prev(), "character", "继续回退")
	p.close("character")
	check_eq(p.focused(), "finance", "关闭后焦点有效")

func _test_dialog_exclusive_and_confirm() -> void:
	var d = DialogScript.new()
	check(d.open("trade")["ok"], "打开交易弹窗")
	check(not d.open("dialogue")["ok"], "已有模态拒绝第二个")
	check(d.close()["ok"], "普通弹窗直接关闭")
	var trial: Dictionary = d.open("trial")
	check(trial["ok"] and trial["needs_confirm"], "审判需二次确认")
	check_eq(str(d.close()["reason"]), "need_confirm", "未确认拒绝关闭")
	check(d.confirm()["ok"], "二次确认成功")
	check(d.close()["ok"], "确认后关闭")
	# force 供内部流转。
	d.open("dying")
	check(d.close(true)["ok"], "force 关闭危险弹窗")

func _test_serialization() -> void:
	var p = PanelScript.new()
	p.open("character")
	p.open("skills")
	var p2 = PanelScript.new()
	p2.from_dict(p.to_dict())
	check_eq(p2.open_count(), 2, "面板开合往返")
	var n = NotifyScript.new()
	n.set_enabled("work", false)
	var n2 = NotifyScript.new()
	n2.from_dict(n.to_dict())
	check(not n2.is_enabled("work"), "通知开关往返")
	var d = DialogScript.new()
	d.open("trade", {"price": 100})
	var d2 = DialogScript.new()
	d2.from_dict(d.to_dict())
	check_eq(d2.current(), "trade", "弹窗往返")
	check_eq(int(d2.payload()["price"]), 100, "弹窗载荷往返")
