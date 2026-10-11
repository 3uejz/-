extends "res://tests/test_base.gd"
## Net 网关「活服务端」联调测试（真实 HTTP）。
##
## 需要后端在 127.0.0.1:8080 运行（`bash scripts/services.sh start` + 启动 server）。
## 后端不可达时打印 SKIP 并以 0 退出，保证离线运行 `scripts/test.sh` 依然通过。
##
## 以 --script 运行时 Autoload 不挂载，故直接实例化 net 并挂到场景树根，
## 使 HttpTransport/HTTPRequest 能收到帧回调。

const BASE := "http://127.0.0.1:8080"

var net
var user := ""
var password := "Passw0rd!12345"

func _suite_name() -> String:
	return "net_live"

func _initialize() -> void:
	print("[test] %s" % _suite_name())
	_boot()

func _boot() -> void:
	# 等首帧，确保 root Window 已进入场景树，HTTPRequest 才能发起请求
	await process_frame
	net = load("res://autoload/net.gd").new()
	get_root().add_child(net)
	net.setup(BASE)
	await _run()

func _run() -> void:
	# 连通性探测
	var probe: Dictionary = await net.request_async("GET", "/health")
	if not probe["ok"]:
		print("[test] %s SKIP (后端未启动: %s)" % [_suite_name(), probe.get("code", "")])
		_cleanup(0)
		return
	check_eq(probe["status"], 200, "health 200")

	user = "godot_%d" % int(Time.get_unix_time_from_system())

	await _test_auth()
	await _test_readonly()
	await _test_saves()
	await _test_legacy()
	await _test_telemetry()
	await _test_refresh_logout()

	if failures == 0:
		print("[test] %s PASS" % _suite_name())
	else:
		print("[test] %s FAILURES: %d" % [_suite_name(), failures])
	_cleanup(failures)

func _cleanup(code: int) -> void:
	net.queue_free()
	quit(code)

func _now_rfc3339() -> String:
	return Time.get_datetime_string_from_system(true) + "Z"

# ------------------------------------------------------------

func _test_auth() -> void:
	var r: Dictionary = await net.register_async(user, password)
	check(r["ok"], "注册成功: %s" % r.get("message", ""))
	check(net.api.access_token != "", "注册后持有 access")
	check(net.api.account_id != "", "注册后持有 account_id")

	var l: Dictionary = await net.login_async(user, password)
	check(l["ok"], "登录成功")
	check_eq(net.api.access_token != "", true, "登录后 access 非空")

	# 错误口令应返回 UNAUTHENTICATED
	var bad: Dictionary = await net.login_async(user, "wrong-password-xxx")
	check(not bad["ok"], "错误口令被拒")
	check_eq(bad["code"], "UNAUTHENTICATED", "错误码 UNAUTHENTICATED")

	# 重新登录拿回有效会话供后续用例
	await net.login_async(user, password)

func _test_readonly() -> void:
	var cfg: Dictionary = await net.remote_config_async()
	check(cfg["ok"], "远程配置读取成功")

	var ann: Dictionary = await net.announcements_async()
	check(ann["ok"], "公告读取成功")

	var manifest: Dictionary = await net.content_manifest_async()
	check(manifest["ok"], "内容清单读取成功")
	check(typeof(manifest["data"]) == TYPE_DICTIONARY, "清单为对象")
	check(manifest["etag"] != "", "清单带 ETag")

	# 条件请求：携带相同 ETag 应 304
	var cached: Dictionary = await net.content_manifest_async(manifest["etag"])
	check(cached["ok"], "条件请求成功")
	check(cached["not_modified"], "相同 ETag 返回 304")

	var world: Dictionary = await net.world_summary_async()
	check(world["ok"], "世界摘要读取成功")
	check(world["etag"] != "", "世界摘要带 ETag")

func _test_saves() -> void:
	var pt := Uuid.v7()
	var doc1 := {"meta": {"schema_version": 1, "game_version": "0.1.0", "playthrough_id": pt, "seed": 42}, "clock": {"absolute_minutes": 0}}
	var key1 := Uuid.v7()
	var put1: Dictionary = await net.put_save_async(1, doc1, "", key1)
	check(put1["ok"], "首次存档写入成功: %s" % put1.get("message", ""))
	check_eq(put1["status"], 201, "新建返回 201")
	var etag1: String = put1["etag"]
	check(etag1 != "", "存档带 ETag")

	# 幂等键重放：同键同体应复用既有版本，不新增
	var put_replay: Dictionary = await net.put_save_async(1, doc1, "", key1)
	check(put_replay["ok"], "幂等键重放成功")
	check_eq(put_replay["etag"], etag1, "幂等重放不推进版本")

	var got: Dictionary = await net.get_save_async(1)
	check(got["ok"], "存档读取成功")
	check_eq(got["etag"], etag1, "读取 ETag 与写入一致")

	# 乐观锁：正确 ETag 覆盖
	var doc2 := {"meta": {"schema_version": 1, "game_version": "0.1.0", "playthrough_id": pt, "seed": 42}, "clock": {"absolute_minutes": 120}}
	var put2: Dictionary = await net.put_save_async(1, doc2, etag1)
	check(put2["ok"], "带 If-Match 覆盖成功")
	check_eq(put2["status"], 200, "覆盖返回 200")
	check(put2["etag"] != etag1, "版本号推进，ETag 变化")

	# 陈旧 ETag 触发 409 SAVE_CONFLICT
	var stale: Dictionary = await net.put_save_async(1, doc2, etag1)
	check(not stale["ok"], "陈旧 ETag 被拒")
	check_eq(stale["code"], "SAVE_CONFLICT", "冲突码 SAVE_CONFLICT")

	var versions: Dictionary = await net.save_versions_async(1)
	check(versions["ok"], "版本列表读取成功")
	check_eq(typeof(versions["data"]), TYPE_ARRAY, "版本为数组")

	var rollback: Dictionary = await net.rollback_save_async(1, 1)
	check(rollback["ok"], "回滚到版本 1 成功")

	var list: Dictionary = await net.list_saves_async()
	check(list["ok"], "存档列表读取成功")
	check_eq(typeof(list["data"]), TYPE_DICTIONARY, "列表为对象")

func _test_legacy() -> void:
	var pt := Uuid.v7()
	var put: Dictionary = await net.put_legacy_async({"playthrough_id": pt, "generation": 1, "inheritance": {"trait": "diligent"}})
	check(put["ok"], "传承档案写入成功")
	var got: Dictionary = await net.get_legacy_async()
	check(got["ok"], "传承档案读取成功")

func _test_telemetry() -> void:
	net.outbox.clear()
	net.outbox.enqueue({"event_type": "session_start", "occurred_at": _now_rfc3339(), "schema_version": 1, "payload": {"v": 1}})
	net.outbox.enqueue({"event_type": "verb_use", "occurred_at": _now_rfc3339(), "schema_version": 1})
	check_eq(net.outbox.pending_count(), 2, "入队两条")
	var r: Dictionary = await net.flush_telemetry_async()
	check(r["ok"], "遥测刷出成功")
	check_eq(r["accepted"], 2, "两条被接受")
	check_eq(net.outbox.pending_count(), 0, "队列清空")

func _test_refresh_logout() -> void:
	var refresh: Dictionary = await net.refresh_async()
	check(refresh["ok"], "令牌刷新成功")
	check(net.api.access_token != "", "刷新后持有新 access")

	var out: Dictionary = await net.logout_async()
	check(out["ok"], "登出成功")
	check_eq(net.api.access_token, "", "登出后清空 access")

	# 登出后访问受保护接口应未鉴权
	var guarded: Dictionary = await net.get_save_async(1)
	check(not guarded["ok"], "登出后受保护接口被拒")
	check_eq(guarded["code"], "UNAUTHENTICATED", "未鉴权码")
