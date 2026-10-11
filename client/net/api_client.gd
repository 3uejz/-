class_name ApiClient
extends RefCounted
## 客户端 ↔ 后端 REST 客户端（同步核心）。
##
## 设计：本类只负责「构建请求 → 解析响应 → 会话状态机」，网络 I/O 由注入的
## `transport: Callable` 完成。transport 契约（同步）：
##     func(req: Dictionary) -> Dictionary
##   req  = { url:String, method:String, headers:Dictionary, body:String }
##   resp = { ok:bool, status:int, headers:Dictionary, body:String, error:String }
## 真实网络实现见 `client/net/http_transport.gd`（异步 Node）；测试用同步 mock。
##
## 约定见 shared/conventions.md 与 shared/openapi/openapi.yaml。

signal tokens_changed
signal session_cleared

# --- 单例式错误码（对齐 httpx） ---
const CODE_OFFLINE := "OFFLINE"
const CODE_VALIDATION := "VALIDATION_FAILED"
const CODE_UNAUTHENTICATED := "UNAUTHENTICATED"
const CODE_TOKEN_EXPIRED := "TOKEN_EXPIRED"
const CODE_FORBIDDEN := "FORBIDDEN"
const CODE_NOT_FOUND := "NOT_FOUND"
const CODE_CONFLICT := "CONFLICT"
const CODE_SAVE_CONFLICT := "SAVE_CONFLICT"
const CODE_SAVE_HASH_MISMATCH := "SAVE_HASH_MISMATCH"
const CODE_IDEMPOTENCY_REPLAY := "IDEMPOTENCY_REPLAY"
const CODE_RATE_LIMITED := "RATE_LIMITED"
const CODE_INTERNAL := "INTERNAL"
const CODE_UPSTREAM := "UPSTREAM_UNAVAILABLE"

const DEFAULT_BASE_URL := "http://127.0.0.1:8080"
const DEFAULT_PREFIX := "/api/v1"
const DEFAULT_TIMEOUT_MS := 15000

# --- 配置 ---
var base_url: String = DEFAULT_BASE_URL
var api_prefix: String = DEFAULT_PREFIX
var device_id: String = ""
var user_agent: String = "lifetext-godot"

# --- 会话 ---
var access_token: String = ""
var refresh_token: String = ""
var account_id: String = ""
var access_expires_in: int = 0

## 网络实现（同步）。未设置时所有请求返回 OFFLINE。
var transport: Callable = Callable()
## 令牌变化回调，用于持久化到 user://（由上层注入）。
var on_tokens_changed: Callable = Callable()
## 每次请求完成后回调（可观测）。参数为结果 Dictionary。
var on_result: Callable = Callable()

var _refreshing: bool = false

# ============================================================
# 配置 / 会话
# ============================================================

func configure(url: String, prefix: String = DEFAULT_PREFIX) -> void:
	base_url = url.strip_edges().trim_suffix("/")
	api_prefix = prefix

func is_authenticated() -> bool:
	return access_token != ""

func clear_session() -> void:
	access_token = ""
	refresh_token = ""
	account_id = ""
	access_expires_in = 0
	session_cleared.emit()
	_notify_tokens()

func restore_session(data: Dictionary) -> void:
	access_token = str(data.get("access_token", ""))
	refresh_token = str(data.get("refresh_token", ""))
	account_id = str(data.get("account_id", ""))
	access_expires_in = int(data.get("expires_in", 0))

func session_dict() -> Dictionary:
	return {
		"access_token": access_token,
		"refresh_token": refresh_token,
		"account_id": account_id,
		"expires_in": access_expires_in,
	}

func _apply_tokens(data: Variant) -> void:
	if typeof(data) != TYPE_DICTIONARY:
		return
	var d: Dictionary = data
	if d.has("access_token"):
		access_token = str(d.get("access_token", ""))
	if d.has("refresh_token"):
		refresh_token = str(d.get("refresh_token", ""))
	if d.has("account_id"):
		account_id = str(d.get("account_id", ""))
	if d.has("expires_in"):
		access_expires_in = int(d.get("expires_in", 0))
	tokens_changed.emit()
	_notify_tokens()

func _notify_tokens() -> void:
	if on_tokens_changed.is_valid():
		on_tokens_changed.call(session_dict())

# ============================================================
# 请求构建 / 发送 / 解析
# ============================================================

func _full_url(path: String, query: Dictionary = {}) -> String:
	var url := "%s%s%s" % [base_url, api_prefix, path]
	var parts: PackedStringArray = []
	for key in query.keys():
		var value: Variant = query[key]
		if value == null or str(value) == "":
			continue
		parts.append("%s=%s" % [key, _url_encode(str(value))])
	if not parts.is_empty():
		url += "?" + "&".join(parts)
	return url

func _url_encode(text: String) -> String:
	return text.uri_encode()

## 构建 HTTP 请求描述（供真实/模拟 transport 使用）。
func build_request(method: String, path: String, opts: Dictionary = {}) -> Dictionary:
	var headers: Dictionary = {
		"Accept": "application/json",
		"User-Agent": user_agent,
	}
	if device_id != "":
		headers["X-Device-Id"] = device_id
	var body_text := ""
	if opts.has("body") and opts["body"] != null:
		headers["Content-Type"] = "application/json"
		body_text = JSON.stringify(opts["body"])
	var authed := bool(opts.get("authed", false))
	if authed and access_token != "":
		headers["Authorization"] = "Bearer %s" % access_token
	if opts.has("if_match") and str(opts["if_match"]) != "":
		headers["If-Match"] = str(opts["if_match"])
	if opts.has("if_none_match") and str(opts["if_none_match"]) != "":
		headers["If-None-Match"] = str(opts["if_none_match"])
	if opts.has("idempotency_key") and str(opts["idempotency_key"]) != "":
		headers["Idempotency-Key"] = str(opts["idempotency_key"])
	if opts.has("extra_headers"):
		for k in (opts["extra_headers"] as Dictionary).keys():
			headers[k] = opts["extra_headers"][k]
	var query: Dictionary = opts.get("query", {})
	return {
		"url": _full_url(path, query),
		"method": method.to_upper(),
		"headers": headers,
		"body": body_text,
		"timeout_ms": int(opts.get("timeout_ms", DEFAULT_TIMEOUT_MS)),
	}

## 解析 transport 响应为统一结果。
func handle_response(resp: Dictionary) -> Dictionary:
	var result: Dictionary = {
		"ok": false,
		"status": int(resp.get("status", 0)),
		"code": "",
		"message": "",
		"data": null,
		"etag": "",
		"not_modified": false,
		"request_id": "",
		"offline": false,
	}
	if not bool(resp.get("ok", false)):
		result["offline"] = true
		result["code"] = CODE_OFFLINE
		result["message"] = str(resp.get("error", "network error"))
		return result
	var status := int(resp.get("status", 0))
	var headers: Dictionary = resp.get("headers", {})
	result["etag"] = _header(headers, "etag")
	var text := str(resp.get("body", ""))
	var trimmed := text.strip_edges()
	var parsed: Variant = null
	if trimmed.begins_with("{") or trimmed.begins_with("["):
		parsed = JSON.parse_string(trimmed)
	if status == 304:
		result["ok"] = true
		result["not_modified"] = true
		return result
	if status >= 200 and status < 300:
		result["ok"] = true
		result["data"] = parsed
		return result
	if typeof(parsed) == TYPE_DICTIONARY and (parsed as Dictionary).has("code"):
		var err: Dictionary = parsed
		result["code"] = str(err.get("code", ""))
		result["message"] = str(err.get("message", ""))
		result["data"] = err.get("details", null)
		result["request_id"] = str(err.get("request_id", ""))
	else:
		result["code"] = "HTTP_%d" % status
		result["message"] = text if text != "" else ("HTTP %d" % status)
	return result

func _header(headers: Dictionary, name: String) -> String:
	var lower := name.to_lower()
	for key in headers.keys():
		if str(key).to_lower() == lower:
			return str(headers[key])
	return ""

func _send(req: Dictionary) -> Dictionary:
	if not transport.is_valid():
		return {"ok": false, "status": 0, "error": "no transport configured"}
	var resp: Variant = transport.call(req)
	if typeof(resp) != TYPE_DICTIONARY:
		return {"ok": false, "status": 0, "error": "transport returned non-dict"}
	return resp

## 单次请求（不处理自动刷新）。
func execute(method: String, path: String, opts: Dictionary = {}) -> Dictionary:
	var result := handle_response(_send(build_request(method, path, opts)))
	if on_result.is_valid():
		on_result.call(result)
	return result

## 带鉴权请求；遇 TOKEN_EXPIRED 自动刷新一次后重试。
func execute_authed(method: String, path: String, opts: Dictionary = {}) -> Dictionary:
	var o := opts.duplicate()
	o["authed"] = true
	var result := execute(method, path, o)
	if result["code"] == CODE_TOKEN_EXPIRED and refresh_token != "" and not bool(o.get("_no_retry", false)):
		var refreshed := refresh()
		if refreshed["ok"]:
			var retry := execute(method, path, o)
			retry["retried"] = true
			return retry
		result["refresh_failed"] = true
	return result

# ============================================================
# 鉴权
# ============================================================

func register(username: String, password: String) -> Dictionary:
	var result := execute("POST", "/auth/register", {"body": {"username": username, "password": password}})
	if result["ok"]:
		_apply_tokens(result["data"])
	return result

func login(username: String, password: String) -> Dictionary:
	var result := execute("POST", "/auth/login", {"body": {"username": username, "password": password}})
	if result["ok"]:
		_apply_tokens(result["data"])
	return result

func refresh() -> Dictionary:
	if refresh_token == "":
		return {
			"ok": false, "status": 0, "code": CODE_UNAUTHENTICATED,
			"message": "no refresh token", "data": null, "etag": "",
			"not_modified": false, "request_id": "", "offline": false,
		}
	if _refreshing:
		return {"ok": false, "status": 0, "code": CODE_OFFLINE, "message": "refresh in progress"}
	_refreshing = true
	var result := execute("POST", "/auth/refresh", {"body": {"refresh_token": refresh_token}})
	_refreshing = false
	if result["ok"]:
		_apply_tokens(result["data"])
	else:
		clear_session()
	return result

func logout() -> Dictionary:
	var result := execute("POST", "/auth/logout", {"body": {"refresh_token": refresh_token}, "authed": true})
	if result["ok"] or result["code"] == CODE_UNAUTHENTICATED:
		clear_session()
	return result

# ============================================================
# 存档
# ============================================================

func list_saves(limit: int = 50, cursor: String = "") -> Dictionary:
	var query := {"limit": limit}
	if cursor != "":
		query["cursor"] = cursor
	return execute_authed("GET", "/saves", {"query": query})

func get_save(slot: int, if_none_match: String = "") -> Dictionary:
	return execute_authed("GET", "/saves/%d" % slot, {"if_none_match": if_none_match})

func put_save(slot: int, doc: Dictionary, expected_etag: String = "", idempotency_key: String = "") -> Dictionary:
	return execute_authed("PUT", "/saves/%d" % slot, {
		"body": doc,
		"if_match": expected_etag,
		"idempotency_key": idempotency_key if idempotency_key != "" else Uuid.v7(),
	})

func save_versions(slot: int) -> Dictionary:
	return execute_authed("GET", "/saves/%d/versions" % slot)

func rollback_save(slot: int, version: int, idempotency_key: String = "") -> Dictionary:
	return execute_authed("POST", "/saves/%d/rollback" % slot, {
		"body": {"version": version},
		"idempotency_key": idempotency_key if idempotency_key != "" else Uuid.v7(),
	})

func resolve_save(slot: int, resolution: String, cloud_version: int = 0, local_blob: Variant = null) -> Dictionary:
	var body := {"resolution": resolution}
	if cloud_version > 0:
		body["cloud_version"] = cloud_version
	if local_blob != null:
		body["local_blob"] = local_blob
	return execute_authed("POST", "/saves/%d/resolve" % slot, {"body": body})

# ============================================================
# 内容 / 配置 / 公告（公共）
# ============================================================

func content_manifest(if_none_match: String = "") -> Dictionary:
	return execute("GET", "/content/manifest", {"if_none_match": if_none_match})

func remote_config(if_none_match: String = "") -> Dictionary:
	return execute("GET", "/config", {"if_none_match": if_none_match})

func announcements() -> Dictionary:
	return execute("GET", "/announcements")

# ============================================================
# 传承档案
# ============================================================

func get_legacy(if_none_match: String = "") -> Dictionary:
	return execute_authed("GET", "/legacy", {"if_none_match": if_none_match})

func put_legacy(doc: Dictionary, if_match: String = "") -> Dictionary:
	return execute_authed("PUT", "/legacy", {"body": doc, "if_match": if_match})

# ============================================================
# 遥测
# ============================================================

func post_telemetry(events: Array) -> Dictionary:
	return execute_authed("POST", "/telemetry/events", {"body": {"events": events}})

# ============================================================
# 世界（全球人口与宏观经济）
# ============================================================

func world_summary(if_none_match: String = "") -> Dictionary:
	return execute_authed("GET", "/world/summary", {"if_none_match": if_none_match})

func sync_world(summary: Dictionary) -> Dictionary:
	return execute_authed("POST", "/world/sync", {"body": summary})
