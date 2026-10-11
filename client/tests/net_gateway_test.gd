extends "res://tests/test_base.gd"
## Net 网关测试：异步请求编排、令牌持久化、遥测刷出。
##
## 说明：网关方法是协程，测试覆写 `_initialize` 为异步驱动；MockNet 覆写 `_send`
## 返回预置响应（同步值，`await` 立即完成），因此无需真实网络。

class MockNet extends "res://autoload/net.gd":
	var responses: Array = []
	var sent: Array = []

	func _send(req: Dictionary) -> Dictionary:
		sent.append(req)
		if responses.is_empty():
			return {"ok": true, "status": 200, "headers": {}, "body": "", "error": ""}
		return responses.pop_front()

var net: MockNet

func _suite_name() -> String:
	return "net_gateway"

func _initialize() -> void:
	print("[test] %s" % _suite_name())
	net = MockNet.new()
	net.setup("http://test.local")
	_run()

func _run() -> void:
	await _test_login()
	await _test_auto_refresh()
	await _test_flush_telemetry()
	await _test_session_persistence()
	net.free()
	if failures == 0:
		print("[test] %s PASS" % _suite_name())
	else:
		print("[test] %s FAILURES: %d" % [_suite_name(), failures])
	quit(failures)

func _resp(status: int, body: Variant) -> Dictionary:
	return {"ok": true, "status": status, "headers": {}, "body": JSON.stringify(body), "error": ""}

func _test_login() -> void:
	net.responses = [_resp(200, {"access_token": "a1", "refresh_token": "r1", "expires_in": 1800, "account_id": "acc"})]
	net.sent = []
	var r: Dictionary = await net.login_async("alice", "password123")
	check(r["ok"], "登录成功")
	check_eq(net.api.access_token, "a1", "登录后 access 写入")
	check_eq(net.api.refresh_token, "r1", "登录后 refresh 写入")
	check_eq(net.sent[0]["url"], "http://test.local/api/v1/auth/login", "登录 URL")
	check_eq(net.sent[0]["headers"]["X-Device-Id"], net.api.device_id, "携带设备号")

func _test_auto_refresh() -> void:
	net.responses = [
		_resp(401, {"code": "TOKEN_EXPIRED", "message": "过期"}),
		_resp(200, {"access_token": "a2", "refresh_token": "r2", "expires_in": 1800}),
		_resp(200, {"items": []}),
	]
	net.sent = []
	var r: Dictionary = await net.list_saves_async()
	check(r["ok"], "自动刷新后重试成功")
	check(bool(r.get("retried", false)), "标记已重试")
	check_eq(net.sent.size(), 3, "共三次请求")
	check_eq(net.sent[1]["url"], "http://test.local/api/v1/auth/refresh", "第二次为刷新")
	check_eq(net.sent[1]["body"], JSON.stringify({"refresh_token": "r1"}), "刷新体含旧 refresh")
	check_eq(net.api.refresh_token, "r2", "refresh 已轮换")
	check_eq(net.sent[2]["headers"]["Authorization"], "Bearer a2", "重试用新 access")

func _test_flush_telemetry() -> void:
	net.outbox.enqueue({"name": "e1"}, "id-1")
	net.outbox.enqueue({"name": "e2"}, "id-2")
	net.responses = [_resp(202, {"accepted": ["id-1"], "rejected": [{"event_id": "id-2", "code": "VALIDATION_FAILED"}]})]
	net.sent = []
	var r: Dictionary = await net.flush_telemetry_async()
	check(r["ok"], "遥测刷出成功")
	check_eq(r["accepted"], 1, "接受一条")
	check_eq(r["rejected"], 1, "拒绝一条")
	check_eq(net.outbox.pending_count(), 0, "队列清空")
	check_eq(net.sent[0]["url"], "http://test.local/api/v1/telemetry/events", "遥测路径")

func _test_session_persistence() -> void:
	check(FileAccess.file_exists("user://net_session.json"), "会话已持久化到 user://")
	var fresh := MockNet.new()
	fresh.setup("http://test.local")
	check_eq(fresh.api.access_token, "a2", "新实例恢复 access")
	check_eq(fresh.api.refresh_token, "r2", "新实例恢复 refresh")
	check_eq(fresh.api.device_id, net.api.device_id, "设备号跨实例稳定")
	fresh.free()
