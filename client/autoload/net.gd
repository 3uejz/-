extends Node
## Net — 后端网关 autoload。
##
## 把同步的 `ApiClient` 核心与异步的 `HttpTransport` 组合为游戏可用的 async API，
## 并负责令牌/设备号持久化（`user://`）。配置项：ProjectSettings `lifetext/api_base_url`
## （默认 `http://127.0.0.1:8080`）。未配置或离线时所有调用返回 `OFFLINE` 结果，不阻塞玩法。
##
## 用法：
##     var r: Dictionary = await Net.login_async("alice", "password123")
##     if r["ok"]: ...
##
## 注意：`run_tests()` 同步执行、不能 await，因此游戏内一律使用本网关的 `*_async` 方法；
## `ApiClient` 的同步方法仅供无网络依赖的逻辑与单测使用。

const SESSION_PATH := "user://net_session.json"
const DEVICE_PATH := "user://net_device_id.txt"
const SETTINGS_KEY := "lifetext/api_base_url"

var api: ApiClient
var http: HttpTransport
var outbox: TelemetryOutbox
var base_url: String = ""
var _ready_done: bool = false

func _ready() -> void:
	setup()

## 幂等初始化；测试可先行调用以避免依赖 _ready。
func setup(base_url_override: String = "") -> void:
	if _ready_done:
		return
	_ready_done = true
	api = ApiClient.new()
	http = HttpTransport.new()
	http.name = "HttpTransport"
	add_child(http)
	outbox = TelemetryOutbox.new()
	var url := base_url_override
	if url == "":
		url = str(ProjectSettings.get_setting(SETTINGS_KEY, ApiClient.DEFAULT_BASE_URL))
	base_url = url
	api.configure(url)
	api.device_id = _load_or_create_device_id()
	api.on_tokens_changed = Callable(self, "_persist_session")
	_restore_session()

# ============================================================
# 持久化
# ============================================================

func _load_or_create_device_id() -> String:
	if FileAccess.file_exists(DEVICE_PATH):
		var f := FileAccess.open(DEVICE_PATH, FileAccess.READ)
		if f != null:
			var id := f.get_as_text().strip_edges()
			f.close()
			if id != "":
				return id
	var id := Uuid.v7()
	var w := FileAccess.open(DEVICE_PATH, FileAccess.WRITE)
	if w != null:
		w.store_string(id)
		w.close()
	return id

func _persist_session(session: Dictionary) -> void:
	var w := FileAccess.open(SESSION_PATH, FileAccess.WRITE)
	if w == null:
		return
	w.store_string(JSON.stringify(session))
	w.close()

func _restore_session() -> void:
	if not FileAccess.file_exists(SESSION_PATH):
		return
	var f := FileAccess.open(SESSION_PATH, FileAccess.READ)
	if f == null:
		return
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) == TYPE_DICTIONARY:
		api.restore_session(parsed)

# ============================================================
# 通用异步请求
# ============================================================

func _send(req: Dictionary) -> Dictionary:
	return await http.send(req)

func _offline(message: String) -> Dictionary:
	return {
		"ok": false, "status": 0, "code": ApiClient.CODE_OFFLINE, "message": message,
		"data": null, "etag": "", "not_modified": false, "request_id": "", "offline": true,
	}

func request_async(method: String, path: String, opts: Dictionary = {}) -> Dictionary:
	if api == null or http == null:
		return _offline("net not setup")
	var result := api.handle_response(await _send(api.build_request(method, path, opts)))
	if result["code"] == ApiClient.CODE_TOKEN_EXPIRED and api.refresh_token != "":
		var refreshed := await refresh_async()
		if refreshed["ok"]:
			result = api.handle_response(await _send(api.build_request(method, path, opts)))
			result["retried"] = true
	return result

# ============================================================
# 鉴权
# ============================================================

func register_async(username: String, password: String) -> Dictionary:
	var r := await request_async("POST", "/auth/register", {"body": {"username": username, "password": password}})
	if r["ok"]:
		api.apply_tokens(r["data"])
	return r

func login_async(username: String, password: String) -> Dictionary:
	var r := await request_async("POST", "/auth/login", {"body": {"username": username, "password": password}})
	if r["ok"]:
		api.apply_tokens(r["data"])
	return r

func refresh_async() -> Dictionary:
	if api == null or api.refresh_token == "":
		return _offline("no refresh token")
	var r := await request_async("POST", "/auth/refresh", {"body": {"refresh_token": api.refresh_token}})
	if r["ok"]:
		api.apply_tokens(r["data"])
	else:
		api.clear_session()
	return r

func logout_async() -> Dictionary:
	var r := await request_async("POST", "/auth/logout", {"body": {"refresh_token": api.refresh_token}, "authed": true})
	if r["ok"] or r["code"] == ApiClient.CODE_UNAUTHENTICATED:
		api.clear_session()
	return r

# ============================================================
# 存档
# ============================================================

func list_saves_async(limit: int = 50, cursor: String = "") -> Dictionary:
	var query := {"limit": limit}
	if cursor != "":
		query["cursor"] = cursor
	return await request_async("GET", "/saves", {"query": query, "authed": true})

func get_save_async(slot: int, if_none_match: String = "") -> Dictionary:
	return await request_async("GET", "/saves/%d" % slot, {"authed": true, "if_none_match": if_none_match})

func put_save_async(slot: int, doc: Dictionary, expected_etag: String = "", idempotency_key: String = "") -> Dictionary:
	return await request_async("PUT", "/saves/%d" % slot, {
		"body": doc, "authed": true, "if_match": expected_etag,
		"idempotency_key": idempotency_key if idempotency_key != "" else Uuid.v7(),
	})

func save_versions_async(slot: int) -> Dictionary:
	return await request_async("GET", "/saves/%d/versions" % slot, {"authed": true})

func rollback_save_async(slot: int, version: int, idempotency_key: String = "") -> Dictionary:
	return await request_async("POST", "/saves/%d/rollback" % slot, {
		"body": {"version": version}, "authed": true,
		"idempotency_key": idempotency_key if idempotency_key != "" else Uuid.v7(),
	})

func resolve_save_async(slot: int, resolution: String, cloud_version: int = 0, local_blob: Variant = null) -> Dictionary:
	var body := {"resolution": resolution}
	if cloud_version > 0:
		body["cloud_version"] = cloud_version
	if local_blob != null:
		body["local_blob"] = local_blob
	return await request_async("POST", "/saves/%d/resolve" % slot, {"body": body, "authed": true})

# ============================================================
# 内容 / 配置 / 公告 / 传承 / 世界
# ============================================================

func content_manifest_async(if_none_match: String = "") -> Dictionary:
	return await request_async("GET", "/content/manifest", {"if_none_match": if_none_match})

func remote_config_async(if_none_match: String = "") -> Dictionary:
	return await request_async("GET", "/config", {"if_none_match": if_none_match})

func announcements_async() -> Dictionary:
	return await request_async("GET", "/announcements")

func get_legacy_async(if_none_match: String = "") -> Dictionary:
	return await request_async("GET", "/legacy", {"authed": true, "if_none_match": if_none_match})

func put_legacy_async(doc: Dictionary, if_match: String = "") -> Dictionary:
	return await request_async("PUT", "/legacy", {"body": doc, "authed": true, "if_match": if_match})

func world_summary_async(if_none_match: String = "") -> Dictionary:
	return await request_async("GET", "/world/summary", {"authed": true, "if_none_match": if_none_match})

func sync_world_async(summary: Dictionary) -> Dictionary:
	return await request_async("POST", "/world/sync", {"body": summary, "authed": true})

# ============================================================
# 遥测
# ============================================================

## 把离线队列按批刷出（单批 ≤500）。失败保留，被拒丢弃。
func flush_telemetry_async() -> Dictionary:
	if api == null or outbox == null:
		return {"ok": false, "skipped": false, "accepted": 0, "rejected": 0, "remaining": 0, "offline": true}
	if outbox.pending_count() == 0:
		return {"ok": true, "skipped": true, "accepted": 0, "rejected": 0, "remaining": 0}
	var batch := outbox.take_batch()
	var result := await request_async("POST", "/telemetry/events", {"body": {"events": batch}, "authed": true})
	return outbox.apply_result(batch, result)
