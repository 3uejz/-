extends "res://tests/test_base.gd"
## ApiClient 契约测试：请求构建、响应解析、会话状态机、自动刷新、离线降级。

class MockTransport extends RefCounted:
	var requests: Array = []
	var _responses: Array = []

	func queue_json(status: int, body: Variant, headers: Dictionary = {}) -> void:
		var text := "" if body == null else JSON.stringify(body)
		_responses.append({"ok": true, "status": status, "headers": headers, "body": text, "error": ""})

	func queue_raw(status: int, text: String, headers: Dictionary = {}) -> void:
		_responses.append({"ok": true, "status": status, "headers": headers, "body": text, "error": ""})

	func queue_offline(error: String) -> void:
		_responses.append({"ok": false, "status": 0, "headers": {}, "body": "", "error": error})

	func send(req: Dictionary) -> Dictionary:
		requests.append(req)
		if _responses.is_empty():
			return {"ok": true, "status": 200, "headers": {}, "body": "", "error": ""}
		return _responses.pop_front()

var mock: MockTransport
var client: ApiClient

func _suite_name() -> String:
	return "net_api"

func _new_client() -> ApiClient:
	mock = MockTransport.new()
	client = ApiClient.new()
	client.configure("http://localhost:9000")
	client.device_id = "dev-1"
	client.transport = Callable(mock, "send")
	client.access_token = "tok"
	client.refresh_token = "ref"
	return client

func run_tests() -> void:
	_test_build_request()
	_test_handle_response()
	_test_login_applies_tokens()
	_test_auto_refresh_retry()
	_test_refresh_failure_clears_session()
	_test_put_save_headers_and_body()
	_test_get_save_etag_304()
	_test_list_saves_query()
	_test_logout_clears_session()
	_test_world_and_config()
	_test_offline_without_transport()

func _test_build_request() -> void:
	_new_client()
	var req := client.build_request("get", "/saves", {"query": {"limit": 50, "cursor": "abc"}, "authed": true})
	check_eq(req["method"], "GET", "method 大写")
	check_eq(req["url"], "http://localhost:9000/api/v1/saves?limit=50&cursor=abc", "url 与 query 拼接")
	check_eq(req["headers"]["Accept"], "application/json", "Accept 头")
	check_eq(req["headers"]["X-Device-Id"], "dev-1", "设备头")
	check_eq(req["headers"]["Authorization"], "Bearer tok", "鉴权头")

	var req2 := client.build_request("PUT", "/saves/3", {
		"body": {"a": 1},
		"if_match": "\"e1\"",
		"idempotency_key": "idem-1",
	})
	check_eq(req2["headers"]["Content-Type"], "application/json", "JSON 内容类型")
	check_eq(req2["body"], JSON.stringify({"a": 1}), "JSON 请求体")
	check_eq(req2["headers"]["If-Match"], "\"e1\"", "If-Match 头")
	check_eq(req2["headers"]["Idempotency-Key"], "idem-1", "幂等键头")

func _test_handle_response() -> void:
	_new_client()
	var ok := client.handle_response({"ok": true, "status": 200, "headers": {"ETag": "\"z\""}, "body": "{\"k\":1}"})
	check(ok["ok"], "200 成功")
	check_eq(ok["etag"], "\"z\"", "ETag 大小写无关读取")
	check_eq(ok["data"]["k"], 1, "成功解析 data")

	var err := client.handle_response({"ok": true, "status": 409, "headers": {}, "body": "{\"code\":\"SAVE_CONFLICT\",\"message\":\"冲突\",\"request_id\":\"r1\"}"})
	check(not err["ok"], "409 失败")
	check_eq(err["code"], "SAVE_CONFLICT", "错误码解析")
	check_eq(err["message"], "冲突", "错误信息解析")
	check_eq(err["request_id"], "r1", "request_id 解析")

	var non_env := client.handle_response({"ok": true, "status": 500, "headers": {}, "body": "boom"})
	check_eq(non_env["code"], "HTTP_500", "非信封错误回退 HTTP_500")

	var nm := client.handle_response({"ok": true, "status": 304, "headers": {}, "body": ""})
	check(nm["ok"] and nm["not_modified"], "304 视为成功且 not_modified")

	var off := client.handle_response({"ok": false, "status": 0, "error": "boom"})
	check(off["offline"], "网络失败标记 offline")
	check_eq(off["code"], "OFFLINE", "网络失败错误码")

func _test_login_applies_tokens() -> void:
	_new_client()
	var box := [0]
	client.tokens_changed.connect(func() -> void: box[0] += 1)
	mock.queue_json(200, {"access_token": "a1", "refresh_token": "r1", "expires_in": 1800, "account_id": "acc"})
	var result := client.login("alice", "password123")
	check(result["ok"], "登录成功")
	check_eq(client.access_token, "a1", "access 写入")
	check_eq(client.refresh_token, "r1", "refresh 写入")
	check_eq(client.account_id, "acc", "account_id 写入")
	check_eq(client.access_expires_in, 1800, "expires_in 写入")
	check_eq(box[0], 1, "tokens_changed 触发一次")
	check_eq(mock.requests[0]["url"], "http://localhost:9000/api/v1/auth/login", "登录路径")
	check_eq(mock.requests[0]["body"], JSON.stringify({"username": "alice", "password": "password123"}), "登录体")

func _test_auto_refresh_retry() -> void:
	_new_client()
	mock.queue_json(401, {"code": "TOKEN_EXPIRED", "message": "过期"})
	mock.queue_json(200, {"access_token": "new1", "refresh_token": "new2", "expires_in": 1800})
	mock.queue_json(200, {"items": []})
	var result := client.list_saves()
	check(result["ok"], "刷新后重试成功")
	check(bool(result.get("retried", false)), "标记已重试")
	check_eq(mock.requests.size(), 3, "共三次请求")
	check_eq(mock.requests[0]["headers"]["Authorization"], "Bearer tok", "首请求用旧 access")
	check_eq(mock.requests[1]["url"], "http://localhost:9000/api/v1/auth/refresh", "第二次为刷新")
	check_eq(mock.requests[1]["body"], JSON.stringify({"refresh_token": "ref"}), "刷新体含当前 refresh")
	check_eq(mock.requests[2]["headers"]["Authorization"], "Bearer new1", "重试用新 access")
	check_eq(client.refresh_token, "new2", "refresh 已轮换")

func _test_refresh_failure_clears_session() -> void:
	_new_client()
	var cleared := [0]
	client.session_cleared.connect(func() -> void: cleared[0] += 1)
	mock.queue_json(401, {"code": "TOKEN_EXPIRED", "message": "过期"})
	mock.queue_json(401, {"code": "UNAUTHENTICATED", "message": "refresh 失效"})
	var result := client.list_saves()
	check(not result["ok"], "刷新失败则请求失败")
	check(bool(result.get("refresh_failed", false)), "标记刷新失败")
	check_eq(client.access_token, "", "会话已清空 access")
	check_eq(client.refresh_token, "", "会话已清空 refresh")
	check_eq(cleared[0], 1, "session_cleared 触发一次")

func _test_put_save_headers_and_body() -> void:
	_new_client()
	mock.queue_json(200, {"slot": 3, "version": 2, "hash": "h", "updated_at": "t"})
	var result := client.put_save(3, {"hp": 9}, "\"e9\"", "idem-9")
	check(result["ok"], "上传成功")
	check_eq(mock.requests[0]["method"], "PUT", "方法为 PUT")
	check_eq(mock.requests[0]["url"], "http://localhost:9000/api/v1/saves/3", "槽路径")
	check_eq(mock.requests[0]["headers"]["If-Match"], "\"e9\"", "携带 If-Match")
	check_eq(mock.requests[0]["headers"]["Idempotency-Key"], "idem-9", "携带幂等键")
	check_eq(mock.requests[0]["body"], JSON.stringify({"hp": 9}), "存档体")

func _test_get_save_etag_304() -> void:
	_new_client()
	mock.queue_raw(304, "", {"ETag": "\"e1\""})
	var result := client.get_save(1, "\"e1\"")
	check(result["ok"] and result["not_modified"], "304 未修改")
	check_eq(mock.requests[0]["headers"]["If-None-Match"], "\"e1\"", "携带 If-None-Match")

func _test_list_saves_query() -> void:
	_new_client()
	mock.queue_json(200, {"items": [], "next_cursor": null})
	var result := client.list_saves(20, "cur")
	check(result["ok"], "列表成功")
	check(mock.requests[0]["url"].ends_with("/saves?limit=20&cursor=cur"), "列表查询参数")

func _test_logout_clears_session() -> void:
	_new_client()
	mock.queue_raw(204, "")
	var result := client.logout()
	check(result["ok"], "登出成功")
	check_eq(client.access_token, "", "登出清空 access")
	check_eq(client.refresh_token, "", "登出清空 refresh")

func _test_world_and_config() -> void:
	_new_client()
	mock.queue_raw(304, "", {"ETag": "\"w1\""})
	var summary := client.world_summary("\"w1\"")
	check(summary["ok"] and summary["not_modified"], "世界摘要 304")

	mock.queue_json(200, {"version": 1, "signals": []})
	var synced := client.sync_world({"version": 1, "signals": []})
	check(synced["ok"], "世界同步成功")
	check_eq(mock.requests[1]["url"], "http://localhost:9000/api/v1/world/sync", "同步路径")
	check_eq(mock.requests[1]["body"], JSON.stringify({"version": 1, "signals": []}), "同步体")

	mock.queue_json(200, {"version": 3, "values": {}})
	var cfg := client.remote_config()
	check(cfg["ok"], "远程配置成功")
	check_eq(mock.requests[2]["url"], "http://localhost:9000/api/v1/config", "配置路径")

func _test_offline_without_transport() -> void:
	_new_client()
	client.transport = Callable()
	var result := client.login("bob", "password123")
	check(not result["ok"], "无传输时失败")
	check(result["offline"], "无传输标记 offline")
	check_eq(result["code"], "OFFLINE", "无传输错误码")
