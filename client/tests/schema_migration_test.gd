extends "res://tests/test_base.gd"
## 领域状态 schema 扩展与存档迁移测试（任务 49.1）。
## 校验 v2 默认结构、SaveMigrations 注册与 v1->v2 迁移补全、既有值不被覆盖。

const GameStateScript = preload("res://autoload/game_state.gd")
const SaveManagerScript = preload("res://sim/save_manager.gd")
const SaveMigrationsScript = preload("res://sim/save_migrations.gd")
const UuidScript = preload("res://sim/uuid.gd")

var _dir: String

func _suite_name() -> String:
	return "schema_migration"

func run_tests() -> void:
	_dir = "/tmp/lifetext_schema_mig_%d" % Time.get_ticks_usec()
	_test_game_state_v2()
	_test_migration_fills_v2_fields()
	_test_migration_preserves_existing()
	_test_game_state_schema_version()

## game_state 默认结构应包含 v2 新增的 player 与 world_delta 字段。
func _test_game_state_v2() -> void:
	var gs := GameStateScript.new()
	gs.new_game(11)
	var p: Dictionary = gs.player
	for key in [
		"family", "memory", "pets", "military", "disabilities", "lands",
		"digital_assets", "cases", "credit_score", "will", "orders",
		"itineraries", "awards", "medical_records",
	]:
		check(p.has(key), "player 含 v2 字段 %s" % key)
	for key in ["loans", "leases", "insurances", "investments"]:
		check((p["finances"] as Dictionary).has(key), "finances 含 %s" % key)
	for key in ["mental", "treatments", "injuries"]:
		check((p["health"] as Dictionary).has(key), "health 含 %s" % key)
	check((p["legal"] as Dictionary).has("active_case_ids"), "legal 含 active_case_ids")
	var wd: Dictionary = gs.world_delta
	for key in [
		"cases", "disasters", "anomalies", "factories", "ips", "sports",
		"orders", "itineraries", "medical_records", "projects", "awards",
	]:
		check(wd.has(key), "world_delta 含 %s" % key)
	gs.free()

func _test_game_state_schema_version() -> void:
	check_eq(GameStateScript.SCHEMA_VERSION, 2, "GameState schema_version 升至 v2")
	check_eq(SaveMigrationsScript.CURRENT_SCHEMA_VERSION, 2, "迁移目录当前版本一致")

## 模拟旧档（v1，缺 v2 字段）：经 SaveMigrations.apply_default 后应升级且字段补齐。
func _test_migration_fills_v2_fields() -> void:
	var dir: String = _dir.path_join("fill")
	var sm := SaveManagerScript.new(dir)
	SaveMigrationsScript.apply_default(sm)
	check_eq(sm.target_schema_version, 2, "apply_default 设置目标版本")

	var old_doc: Dictionary = {
		"meta": {"schema_version": 1, "game_version": "0.0.1", "playthrough_id": _uuid(), "seed": 5},
		"clock": {"absolute_minutes": 0},
		"player": {"id": _uuid(), "name": "旧档", "finances": {"cash": 10.0}, "health": {}, "legal": {}},
		"world_delta": {"npcs": [{"id": _uuid()}]},
		"rng": {},
	}
	var saved: Dictionary = sm.save("m", old_doc)
	check(saved["ok"], "旧档写入成功")
	var loaded: Dictionary = sm.load("m")
	check(loaded["ok"], "旧档迁移读取成功")
	if not loaded["ok"]:
		return
	var doc: Dictionary = loaded["doc"]
	check_eq(doc["meta"]["schema_version"], 2, "schema 升至 v2")
	check(doc["player"].has("family"), "迁移补 player.family")
	check(doc["player"].has("memory"), "迁移补 player.memory")
	check_eq(doc["player"]["credit_score"], 650, "迁移补信用分默认值")
	check(doc["player"]["finances"].has("loans"), "迁移补 finances.loans")
	check(doc["player"]["health"].has("mental"), "迁移补 health.mental")
	check(doc["world_delta"].has("cases"), "迁移补 world_delta.cases")
	check((doc["world_delta"]["npcs"][0] as Dictionary).has("memory"), "迁移补 NPC.memory")

## 已有 v2 字段不应被迁移覆盖。
func _test_migration_preserves_existing() -> void:
	var dir: String = _dir.path_join("preserve")
	var sm := SaveManagerScript.new(dir)
	SaveMigrationsScript.apply_default(sm)
	var doc: Dictionary = {
		"meta": {"schema_version": 1, "game_version": "0.0.1", "playthrough_id": _uuid(), "seed": 9},
		"clock": {"absolute_minutes": 0},
		"player": {"id": _uuid(), "name": "保留", "credit_score": 800, "family": {"spouse_id": _uuid()}},
		"world_delta": {"cases": [{"id": _uuid()}]},
		"rng": {},
	}
	var saved: Dictionary = sm.save("p", doc)
	check(saved["ok"], "写入成功")
	var loaded: Dictionary = sm.load("p")
	check(loaded["ok"], "迁移读取成功")
	if loaded["ok"]:
		check_eq(loaded["doc"]["player"]["credit_score"], 800, "已有信用分不被覆盖")
		check(loaded["doc"]["player"]["family"].has("spouse_id"), "已有 family 保留")
		check_eq(loaded["doc"]["world_delta"]["cases"].size(), 1, "已有案件保留")

func _uuid() -> String:
	return UuidScript.v7()
