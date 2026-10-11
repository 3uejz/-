extends "res://tests/test_base.gd"
## 任务 47 收尾测试：历史窗口化、内联插画解析、通知中心（桌面通知 + 托盘 + 聚焦）。

const HistoryScript = preload("res://ui/layout/history_view.gd")
const IllustrationScript = preload("res://ui/components/illustration.gd")
const CenterScript = preload("res://ui/notifications/notification_center.gd")

func _suite_name() -> String:
	return "ui_narrative"

func run_tests() -> void:
	_test_history_window()
	_test_history_clamp_and_roundtrip()
	_test_illustration_resolve()
	_test_notification_center()
	_test_tray_advance()

func _test_history_window() -> void:
	var h = HistoryScript.new()
	check(h.is_empty(), "初始为空")
	for i in range(1000):
		h.append({"text": "行 %d" % i, "type": "info"})
	check_eq(h.count(), 1000, "历史行数")
	check_eq(h.total_height(20.0), 20000.0, "总高度")
	# 视口 100px、行高 20px、无 overscan → 恰好 5 行。
	var w: Dictionary = h.visible_window(0.0, 100.0, 20.0, 0)
	check_eq(int(w["start"]), 0, "窗口起点")
	check_eq(int(w["end"]), 5, "窗口终点")
	# 滚动到第 500 行附近。
	var w2: Dictionary = h.visible_window(10000.0, 100.0, 20.0, 0)
	check_eq(int(w2["start"]), 500, "滚动后起点")
	check_eq(int(w2["end"]), 505, "滚动后终点")
	# overscan 预取并夹到范围。
	var w3: Dictionary = h.visible_window(19990.0, 100.0, 20.0, 3)
	check_eq(int(w3["end"]), 1000, "窗口夹到总数")
	var rows: Array = h.window_rows(0.0, 40.0, 20.0, 0)
	check_eq(rows.size(), 2, "window_rows 数量")
	check_eq(String(rows[0]["row"]["text"]), "行 0", "window_rows 内容")

func _test_history_clamp_and_roundtrip() -> void:
	var h = HistoryScript.new()
	for i in range(10):
		h.append({"text": str(i)})
	check_eq(h.clamp_scroll(-5.0, 100.0, 20.0), 0.0, "负滚动夹到 0")
	check_eq(h.clamp_scroll(999.0, 100.0, 20.0), 100.0, "超界滚动夹到最大")
	var snap: Dictionary = h.to_dict()
	var h2 = HistoryScript.new()
	h2.from_dict(snap)
	check_eq(h2.count(), 10, "序列化往返")

func _test_illustration_resolve() -> void:
	check(not IllustrationScript.has_asset("scene.rain"), "无资产时 has_asset=false")
	var r: Dictionary = IllustrationScript.resolve("illus.scene.rain", "雨夜")
	check(not bool(r["available"]), "缺图回退占位")
	check(bool(r["placeholder"]), "标记为占位")
	check_eq(String(r["caption"]), "雨夜", "保留 caption")
	check_eq(String(r["key"]), "scene.rain", "去前缀")
	check(String(r["path"]).find("_placeholder") >= 0, "回退占位路径")

func _test_notification_center() -> void:
	var c = CenterScript.new()
	check_eq((c.categories() as Array).size(), 7, "七类通知")
	var posted: Array = []
	c.poster = func(title, body): posted.append([title, body])
	var r: Dictionary = c.notify("work", "上班", "该上班了", "career")
	check(bool(r["sent"]), "已发送")
	check(not bool(r["queued"]), "聚焦时直接发送不入队")
	check_eq(posted.size(), 1, "投递一次")
	# 分类关闭 → 静音。
	c.set_enabled("work", false)
	check_eq(String(c.notify("work", "上班")["reason"]), "muted", "关闭分类静音")
	# 危险类受安全阀强制。
	c.set_enabled("health_danger", false)
	check(bool(c.notify("health_danger", "危险")["sent"]), "危险类强制弹出")
	# 未聚焦入队，聚焦后排空。
	c.blur()
	var r2: Dictionary = c.notify("social", "约会", "", "relations")
	check(bool(r2["queued"]), "未聚焦入队")
	check_eq(c.pending(), 1, "队列长度")
	var drained: Array = c.focus()
	check_eq(drained.size(), 1, "聚焦排空")
	check_eq(String(drained[0]["panel"]), "relations", "保留目标面板")

func _test_tray_advance() -> void:
	var c = CenterScript.new()
	c.set_tray_enabled(false)
	check(not c.should_advance_world(), "关闭托盘则停止推进")
	c.set_tray_enabled(true)
	check(c.should_advance_world(), "托盘常驻继续推进")
