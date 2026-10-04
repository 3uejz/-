extends "res://tests/test_base.gd"
## GameState 与本地存档测试（任务 3.1）：往返、损坏容错、迁移、备份、导出导入、分块。

const GameStateScript = preload("res://autoload/game_state.gd")
const SaveManagerScript = preload("res://sim/save_manager.gd")
const SaveCodecScript = preload("res://sim/save_codec.gd")
const UuidScript = preload("res://sim/uuid.gd")

var _dir: String

func _suite_name() -> String:
	return "save"

func run_tests() -> void:
	_dir = "/tmp/lifetext_save_test_%d" % Time.get_ticks_usec()
	_test_uuid()
	_test_roundtrip()
	_test_corruption()
	_test_migration()
	_test_backup_rotation()
	_test_export_import()
	_test_chunked()

func _test_uuid() -> void:
	var id := UuidScript.v7()
	check_eq(id.length(), 36, "UUID 长度")
	check_eq(id.substr(14, 1), "7", "UUIDv7 版本位")
	check("89ab".contains(id.substr(19, 1)), "UUIDv7 变体位")

func _test_roundtrip() -> void:
	var gs := GameStateScript.new()
	gs.new_game(12345)
	gs.player["name"] = "阿测"
	var sm := SaveManagerScript.new(_dir)
	var saved: Dictionary = sm.save("a", gs.to_dict())
	check(saved["ok"], "保存成功")
	var loaded: Dictionary = sm.load("a")
	check(loaded["ok"], "读取成功")
	if loaded["ok"]:
		check_eq(loaded["doc"]["meta"]["seed"], 12345, "种子往返")
		check_eq(loaded["doc"]["player"]["name"], "阿测", "玩家名往返")
		check_eq(loaded["doc"]["meta"]["playthrough_id"], gs.meta["playthrough_id"], "playthrough_id 往返")
	gs.free()

func _test_corruption() -> void:
	var gs := GameStateScript.new()
	gs.new_game(1)
	var sm := SaveManagerScript.new(_dir)
	sm.save("corrupt", gs.to_dict())

	var f := FileAccess.open(sm.main_path("corrupt"), FileAccess.WRITE)
	f.store_string("{ 这不是合法 JSON")
	f.close()
	var bad: Dictionary = sm.load("corrupt")
	check(not bad["ok"], "损坏 JSON 被拒绝")

	# 内容被篡改（JSON 仍合法）→ 哈希不匹配。
	sm.save("tamper", gs.to_dict())
	var path: String = sm.main_path("tamper")
	var text: String = FileAccess.open(path, FileAccess.READ).get_as_text()
	var tampered: String = text.replace("无名", "篡改名")
	var w := FileAccess.open(path, FileAccess.WRITE)
	w.store_string(tampered)
	w.close()
	var result: Dictionary = sm.load("tamper")
	check(not result["ok"], "篡改内容被哈希拒绝")
	gs.free()

func _test_migration() -> void:
	var gs := GameStateScript.new()
	gs.new_game(7)
	var dir2: String = _dir.path_join("migrate")
	var sm := SaveManagerScript.new(dir2)
	sm.target_schema_version = 2
	sm.register_migration(1, func(doc: Dictionary) -> Dictionary:
		doc["player"]["name"] = "迁移后"
		return doc)
	sm.save("m", gs.to_dict())
	var loaded: Dictionary = sm.load("m")
	check(loaded["ok"], "迁移读取成功")
	if loaded["ok"]:
		check_eq(loaded["doc"]["meta"]["schema_version"], 2, "schema 升级到 v2")
		check_eq(loaded["doc"]["player"]["name"], "迁移后", "迁移逻辑生效")
	gs.free()

func _test_backup_rotation() -> void:
	var gs := GameStateScript.new()
	gs.new_game(2)
	var dir3: String = _dir.path_join("backup")
	var sm := SaveManagerScript.new(dir3)
	for i in 6:
		gs.player["name"] = "第%d次" % i
		sm.save("b", gs.to_dict())
	var baks := _count_prefix(dir3, "slot_b.bak")
	check_eq(baks, SaveManagerScript.MAX_BACKUPS, "备份数量上限")
	check(FileAccess.file_exists(sm.backup_path("b", 0)), "存在最近备份 bak0")
	check(not FileAccess.file_exists(sm.backup_path("b", SaveManagerScript.MAX_BACKUPS)), "不超出备份上限")
	gs.free()

func _test_export_import() -> void:
	var gs := GameStateScript.new()
	gs.new_game(999)
	gs.player["name"] = "导出者"
	var sm := SaveManagerScript.new(_dir.path_join("io"))
	sm.save("src", gs.to_dict())
	var dest: String = _dir.path_join("io").path_join("exported.json")
	var exp: Dictionary = sm.export_save("src", dest)
	check(exp["ok"], "导出成功")
	var imp: Dictionary = sm.import_save(dest, "dst")
	check(imp["ok"], "导入并校验成功")
	if imp["ok"]:
		check_eq(imp["doc"]["meta"]["seed"], 999, "导入种子一致")
		check_eq(imp["doc"]["player"]["name"], "导出者", "导入玩家名一致")
	gs.free()

func _test_chunked() -> void:
	var gs := GameStateScript.new()
	gs.new_game(555)
	gs.player["name"] = "分块者"
	var dir5: String = _dir.path_join("chunk")
	var sm := SaveManagerScript.new(dir5)
	var saved: Dictionary = sm.save("c", gs.to_dict(), true)
	check(saved["ok"], "分块保存成功")
	check(FileAccess.file_exists(sm.chunk_path("c", "player")), "存在 player 分块")
	check(FileAccess.file_exists(sm.chunk_path("c", "world_delta")), "存在 world 分块")

	var main_text: String = FileAccess.open(sm.main_path("c"), FileAccess.READ).get_as_text()
	var main_doc: Dictionary = SaveCodecScript.parse(main_text)["doc"]
	check(main_doc.has("chunks"), "主文件含分块清单")
	check(not main_doc.has("player"), "主文件不再内联 player")

	var loaded: Dictionary = sm.load("c")
	check(loaded["ok"], "分块读取成功")
	if loaded["ok"]:
		check_eq(loaded["doc"]["player"]["name"], "分块者", "分块后玩家名还原")
		check(loaded["doc"].has("world_delta"), "分块后 world_delta 还原")
	gs.free()

func _count_prefix(dir: String, prefix: String) -> int:
	var d := DirAccess.open(dir)
	if d == null:
		return 0
	var count: int = 0
	for name in d.get_files():
		if name.begins_with(prefix):
			count += 1
	return count
