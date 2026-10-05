extends "res://tests/test_base.gd"
## 内容管理器测试（任务 23：差量更新、哈希校验、按区域挂载，R36.3/4/6/8/10）。

const STEP1 := "res://tests/fixtures/content_step1"
const STEP2 := "res://tests/fixtures/content_step2"
const CACHE := "user://lt_content_manager_test"

## 保持 FakeFetcher 强引用：Godot 的 Callable 不持有 RefCounted 目标的强引用。
var _keep: Array = []


class FakeFetcher:
	extends RefCounted
	var base_dir: String
	var corrupt_name: String = ""
	func fetch(url: String) -> PackedByteArray:
		var path := base_dir.path_join(url.get_file())
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			return PackedByteArray()
		var data := f.get_buffer(f.get_length())
		f.close()
		if corrupt_name != "" and url.get_file() == corrupt_name and data.size() > 0:
			data[data.size() - 1] = (data[data.size() - 1] + 1) % 256
		return data


func _suite_name() -> String:
	return "content_manager"


func run_tests() -> void:
	_clear_cache()
	_test_base_sync_and_mount()
	_test_patch_update()
	_test_hash_mismatch()


func _clear_cache() -> void:
	var dir := DirAccess.open(ProjectSettings.globalize_path(CACHE))
	if dir == null:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CACHE))
		return
	for f in dir.get_files():
		dir.remove(f)


func _fetcher(fixture: String, corrupt: String = "") -> Callable:
	var ff := FakeFetcher.new()
	ff.base_dir = ProjectSettings.globalize_path(fixture)
	ff.corrupt_name = corrupt
	_keep.append(ff)
	return Callable(ff, "fetch")


func _test_base_sync_and_mount() -> void:
	var manifest := ProjectSettings.globalize_path(STEP1.path_join("manifest.json"))
	var mgr := ContentManager.from_manifest_file(manifest, _fetcher(STEP1), ProjectSettings.globalize_path(CACHE))
	check_eq(mgr.sync().size(), 0, "基础同步不应有错误")
	check_eq(mgr.mount_region(""), 9, "应挂载 9 个类别")
	check(mgr.mounted_categories().has("jobs"), "应挂载 jobs")
	check(mgr.mounted_categories().has("items"), "应挂载 items")
	check_eq(mgr.validate().size(), 0, "基础内容交叉引用应通过")
	var apple := mgr.get_entry("items", "item.apple")
	check_eq(int(apple.get("price", -1)), 600, "基础物品价格应为 600")


func _test_patch_update() -> void:
	# 先完成基础同步（写入缓存），再应用差量清单。
	var base := ContentManager.from_manifest_file(
		ProjectSettings.globalize_path(STEP1.path_join("manifest.json")), _fetcher(STEP1), ProjectSettings.globalize_path(CACHE))
	base.sync()
	base.mount_region("")
	var before := int(base.get_entry("items", "item.apple").get("price", -1))
	check_eq(before, 600, "更新前价格")

	var patched := ContentManager.from_manifest_file(
		ProjectSettings.globalize_path(STEP2.path_join("combined-manifest.json")), _fetcher(STEP2), ProjectSettings.globalize_path(CACHE))
	var patch_issues := patched.sync()
	check_eq(patch_issues.size(), 0, "差量同步不应有错误: %s" % str(patch_issues))
	var mounted := patched.mount_region("")
	check_eq(mounted, 9, "差量后仍应挂载 9 个类别")
	check_eq(patched.validate().size(), 0, "差量后交叉引用应通过")
	var apple := patched.get_entry("items", "item.apple")
	check_eq(int(apple.get("price", -1)), 700, "差量应更新苹果价格")
	check(not patched.get_entry("items", "item.new_thing").is_empty(), "差量应新增条目")
	check_eq(base.get_entry("items", "item.new_thing").is_empty(), true, "原管理器不受影响")


func _test_hash_mismatch() -> void:
	var cache := CACHE + "_hash"
	var dir := DirAccess.open(ProjectSettings.globalize_path(cache))
	if dir != null:
		for f in dir.get_files():
			dir.remove(f)
	var mgr := ContentManager.from_manifest_file(
		ProjectSettings.globalize_path(STEP1.path_join("manifest.json")),
		_fetcher(STEP1, "items.ltpack"), ProjectSettings.globalize_path(cache))
	var issues := mgr.sync()
	var found := false
	for i in issues:
		if str(i).contains("哈希校验失败"):
			found = true
	check(found, "损坏的内容包应触发哈希校验失败: %s" % str(issues))
