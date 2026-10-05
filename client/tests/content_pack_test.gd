extends "res://tests/test_base.gd"
## 内容包容器与注册表测试（任务 23.1 / 23.2）。
## fixture 由 Go 工具链 tools/contentbuilder 构建，验证 GDScript 与 Go 格式互通。

const FIXTURE_DIR := "res://tests/fixtures/content"


func _suite_name() -> String:
	return "content_pack_test"


func run_tests() -> void:
	_test_decode_go_fixture()
	_test_hash_matches_manifest()
	_test_registry_validate()
	_test_encode_decode_roundtrip()
	_test_hash_detects_change()
	_test_cross_reference_detection()


func _test_decode_go_fixture() -> void:
	var pack: ContentPack = ContentPack.load_file(FIXTURE_DIR.path_join("jobs.ltpack"))
	check(pack != null, "应能加载 jobs.ltpack")
	if pack == null:
		return
	check_eq(pack.category, "jobs", "类别应为 jobs")
	check_eq(pack.kind, "data", "包类型应为 data")
	check(pack.entries.size() >= 30, "职业条目应不少于 30")
	var programmer: Dictionary = pack.entries.get("occupation.programmer", {})
	check_eq(programmer.get("name", ""), "程序员", "应解码出职业名称")
	check_eq(int(programmer.get("level", 0)), 4, "应解码出等级")
	var skills: Array = programmer.get("skills", [])
	check(skills.has("skill.coding"), "应解码出技能引用")


func _test_hash_matches_manifest() -> void:
	var manifest := load_json(ProjectSettings.globalize_path(FIXTURE_DIR.path_join("manifest.json")))
	check(not manifest.is_empty(), "应能加载 manifest.json")
	var packs: Array = manifest.get("packs", [])
	check(packs.size() >= 8, "清单应包含多个内容包")
	for p in packs:
		var path := FIXTURE_DIR.path_join(str(p.get("name", "")) + ".ltpack")
		var f := FileAccess.open(path, FileAccess.READ)
		check(f != null, "内容包文件应存在: %s" % path)
		if f == null:
			continue
		var data := f.get_buffer(f.get_length())
		f.close()
		check_eq(ContentPack.sha256_hex(data), str(p.get("hash", "")), "哈希应与清单一致 %s" % str(p.get("name", "")))


func _test_registry_validate() -> void:
	var registry := ContentRegistry.load_dir(ProjectSettings.globalize_path(FIXTURE_DIR))
	check(registry.issues.is_empty(), "加载不应有错误: %s" % str(registry.issues))
	check(registry.count() >= 100, "注册表应载入全部条目")
	var found := registry.validate()
	check(found.is_empty(), "交叉引用校验应通过: %s" % str(found))
	var job := registry.get_entry("jobs", "occupation.doctor")
	check_eq(str(job.get("name", "")), "医生", "注册表应能按 content_key 取条目")


func _test_encode_decode_roundtrip() -> void:
	var source := {
		"skill.coding": {"name": "编程", "domain": "career", "max_level": 20},
		"skill.cooking": {"name": "烹饪", "domain": "life", "max_level": 10},
	}
	var data := ContentPack.encode_bytes("skills", "data", source)
	var pack := ContentPack.decode(data, "<memory>")
	check(pack != null, "自编码内容包应能解码")
	if pack == null:
		return
	check_eq(pack.category, "skills", "往返类别一致")
	check_eq(pack.entries.size(), 2, "往返条目数一致")
	check_eq(str(pack.entries["skill.coding"].get("name", "")), "编程", "往返内容一致")


func _test_hash_detects_change() -> void:
	var f := FileAccess.open(ProjectSettings.globalize_path(FIXTURE_DIR.path_join("items.ltpack")), FileAccess.READ)
	check(f != null, "应能打开 items.ltpack")
	if f == null:
		return
	var data := f.get_buffer(f.get_length())
	f.close()
	var original := ContentPack.sha256_hex(data)
	var tampered := data.duplicate()
	tampered[tampered.size() - 1] = (tampered[tampered.size() - 1] + 1) % 256
	check(original != ContentPack.sha256_hex(tampered), "篡改后哈希应变化")


func _test_cross_reference_detection() -> void:
	var registry := ContentRegistry.new()
	var jobs := ContentPack.new()
	jobs.category = "jobs"
	jobs.entries = {
		"occupation.x": {"name": "X", "skills": ["skill.missing"]},
	}
	registry.register(jobs)
	var issues := registry.validate()
	check(issues.size() == 1, "应检测到 1 条断链引用: %s" % str(issues))
	check(str(issues[0]).contains("skill.missing"), "问题应指向缺失的引用键")
