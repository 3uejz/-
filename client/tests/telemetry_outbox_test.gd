extends "res://tests/test_base.gd"
## TelemetryOutbox 测试：去重入队、批量刷出、拒绝处理、离线保留、序列化。

class MockClient extends ApiClient:
	var calls: Array = []
	var response: Dictionary = {}

	func post_telemetry(events: Array) -> Dictionary:
		calls.append(events)
		return response

func _suite_name() -> String:
	return "telemetry_outbox"

func _accepted(ids: Array) -> Dictionary:
	return {"ok": true, "status": 202, "code": "", "message": "", "offline": false, "data": {"accepted": ids, "rejected": []}}

func run_tests() -> void:
	_test_dedupe_enqueue()
	_test_flush_accepted_and_rejected()
	_test_flush_offline_keeps_queue()
	_test_roundtrip()

func _test_dedupe_enqueue() -> void:
	var box := TelemetryOutbox.new()
	var id1 := box.enqueue({"name": "e1"}, "id-1")
	check_eq(id1, "id-1", "使用显式 event_id")
	check_eq(box.pending_count(), 1, "入队一条")
	box.enqueue({"name": "e1b"}, "id-1")
	check_eq(box.pending_count(), 1, "重复 event_id 不再入队")
	var auto := box.enqueue({"name": "e2"})
	check(auto != "", "自动生成 event_id")
	check_eq(box.pending_count(), 2, "不同事件入队")

func _test_flush_accepted_and_rejected() -> void:
	var box := TelemetryOutbox.new()
	box.enqueue({"name": "a"}, "id-a")
	box.enqueue({"name": "b"}, "id-b")
	var cli := MockClient.new()
	cli.response = {"ok": true, "status": 202, "data": {"accepted": ["id-a"], "rejected": [{"event_id": "id-b", "code": "VALIDATION_FAILED"}]}}
	var result := box.flush(cli)
	check(result["ok"], "刷出成功")
	check_eq(result["accepted"], 1, "一条被接受")
	check_eq(result["rejected"], 1, "一条被拒绝")
	check_eq(result["remaining"], 0, "队列清空")
	check_eq(box.last_rejected.size(), 1, "记录拒绝")
	check_eq(box.last_rejected[0]["event_id"], "id-b", "拒绝 event_id")
	check_eq(box.last_rejected[0]["code"], "VALIDATION_FAILED", "拒绝码")
	check_eq(cli.calls.size(), 1, "客户端被调用一次")
	check_eq(cli.calls[0].size(), 2, "批量含两条")

func _test_flush_offline_keeps_queue() -> void:
	var box := TelemetryOutbox.new()
	box.enqueue({"name": "a"})
	box.enqueue({"name": "b"})
	box.enqueue({"name": "c"})
	var cli := MockClient.new()
	cli.response = {"ok": false, "status": 0, "code": "OFFLINE", "offline": true}
	var result := box.flush(cli)
	check(not result["ok"], "离线刷出失败")
	check_eq(result["remaining"], 3, "离线保留全部")
	check_eq(box.pending_count(), 3, "队列未清空")

func _test_roundtrip() -> void:
	var box := TelemetryOutbox.new()
	box.enqueue({"name": "a"}, "id-a")
	box.enqueue({"name": "b"}, "id-b")
	var cli := MockClient.new()
	cli.response = _accepted(["id-a", "id-b"])
	box.flush(cli)
	check_eq(box.pending_count(), 0, "全部接受后队列清空")
	box.enqueue({"name": "c"}, "id-c")
	var restored := TelemetryOutbox.new()
	restored.from_dict(box.to_dict())
	check_eq(restored.pending_count(), 1, "恢复待发队列")
	check_eq(restored.pending_events()[0]["event_id"], "id-c", "恢复内容正确")
	# 已接受事件恢复后仍防重复入队
	restored.enqueue({"name": "a"}, "id-a")
	check_eq(restored.pending_count(), 1, "恢复后仍按已接受去重")
