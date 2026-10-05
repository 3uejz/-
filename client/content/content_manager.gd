class_name ContentManager
extends RefCounted
## 内容包客户端管理器：按清单下载/校验内容包、应用差量、按区域按需挂载。
## 对应 R36.3/4/6/8/10；下载器通过 fetcher 注入，便于离线测试。
## fetcher 签名：func(url: String) -> PackedByteArray（失败返回空）。
##
## 差量策略：基础包保持原文件不变，差量包单独落盘；挂载时在内存中把差量
## 合并到基础包，避免跨语言重编码导致哈希漂移，可跨会话复用。

const PACK_EXT := ".ltpack"

var manifest: Dictionary = {}
var fetcher: Callable = Callable()
var cache_dir: String = ""
var packs: Dictionary = {}          # category -> ContentPack（已挂载，含差量合并）
var patches: Dictionary = {}        # base pack name -> ContentPack（差量包）
var installed: Dictionary = {}      # pack name -> hash（本次会话已同步）
var issues: Array = []


func _init(manifest_data: Dictionary, fetcher_fn: Callable, cache_path: String) -> void:
	manifest = manifest_data
	fetcher = fetcher_fn
	cache_dir = cache_path


static func from_manifest_file(path: String, fetcher_fn: Callable, cache_path: String) -> ContentManager:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("无法读取内容清单: %s" % path)
		return ContentManager.new({}, fetcher_fn, cache_path)
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	var data: Dictionary = parsed if typeof(parsed) == TYPE_DICTIONARY else {}
	return ContentManager.new(data, fetcher_fn, cache_path)


## 下载并校验清单中所有变更内容包；差量包先于基础包处理。
func sync() -> Array:
	issues.clear()
	_ensure_dir()
	var pack_list: Array = manifest.get("packs", [])
	# 1) 先下载差量包，供基础包判断与挂载时合并。
	for p in pack_list:
		if typeof(p) == TYPE_DICTIONARY and _patch_of(p) != "":
			_sync_patch(p)
	# 2) 再同步基础包：命中本地、命中差量或需全量下载。
	for p in pack_list:
		if typeof(p) == TYPE_DICTIONARY and _patch_of(p) == "":
			_sync_base(p)
	return issues


## 按区域挂载已同步的基础包（挂载时合并其差量）；region_key 为空表示通用包。
func mount_region(region_key: String = "") -> int:
	var mounted := 0
	for p in manifest.get("packs", []):
		if typeof(p) != TYPE_DICTIONARY or _patch_of(p) != "":
			continue
		var pack_region := str(p.get("region_key", ""))
		if region_key != "" and pack_region != "" and pack_region != region_key:
			continue
		var name := str(p.get("name", ""))
		var path := _cache_path(name)
		if _file_hash(path) == "":
			issues.append("未同步，无法挂载: %s" % name)
			continue
		var base := _read_pack(path)
		if base == null:
			issues.append("内容包解码失败: %s" % name)
			continue
		var merged := _merge(base, name)
		packs[merged.category] = merged
		mounted += 1
	return mounted


func mounted_categories() -> Array:
	var keys: Array = packs.keys()
	keys.sort()
	return keys


## 启动交叉引用校验（在挂载后调用）。
func validate() -> Array:
	var registry := ContentRegistry.new()
	for category in packs:
		registry.register(packs[category])
	return registry.validate()


func get_entry(category: String, key: String) -> Dictionary:
	if packs.has(category) and packs[category].entries.has(key):
		return packs[category].entries[key]
	return {}


func _sync_patch(p: Dictionary) -> void:
	var name := str(p.get("name", ""))
	var want := str(p.get("hash", ""))
	if name == "" or want == "":
		issues.append("差量清单条目缺少 name/hash")
		return
	var path := _cache_path(name)
	if str(installed.get(name, "")) != want and _file_hash(path) != want:
		var bytes := _fetch(str(p.get("url", "")))
		if bytes.is_empty():
			issues.append("下载失败: %s" % name)
			return
		if ContentPack.sha256_hex(bytes) != want:
			issues.append("哈希校验失败: %s" % name)
			return
		_write_bytes(path, bytes)
	installed[name] = want
	var pack := _read_pack(path)
	if pack != null:
		patches[str(p.get("patch_of", ""))] = pack


func _sync_base(p: Dictionary) -> void:
	var name := str(p.get("name", ""))
	var want := str(p.get("hash", ""))
	if name == "" or want == "":
		issues.append("清单条目缺少 name/hash")
		return
	if str(installed.get(name, "")) == want:
		return
	var path := _cache_path(name)
	var local := _file_hash(path)
	if local == want:
		installed[name] = want
		return
	# 本地有旧版本且存在差量包时，延迟到挂载时合并，无需全量下载。
	if local != "" and patches.has(name):
		installed[name] = want
		return
	var bytes := _fetch(str(p.get("url", "")))
	if bytes.is_empty():
		issues.append("下载失败: %s" % name)
		return
	if ContentPack.sha256_hex(bytes) != want:
		issues.append("哈希校验失败: %s" % name)
		return
	_write_bytes(path, bytes)
	installed[name] = want


func _merge(base: ContentPack, base_name: String) -> ContentPack:
	if not patches.has(base_name):
		return base
	var merged := ContentPack.new()
	merged.category = base.category
	merged.kind = base.kind
	merged.source_path = base.source_path
	merged.entries = ContentPack.apply_patch(base.entries, patches[base_name].entries)
	return merged


func _patch_of(p: Dictionary) -> String:
	if not p.has("patch_of") or p["patch_of"] == null:
		return ""
	return str(p["patch_of"])


func _fetch(url: String) -> PackedByteArray:
	if not fetcher.is_valid() or url == "":
		return PackedByteArray()
	return fetcher.call(url)


func _cache_path(name: String) -> String:
	return cache_dir.path_join(name + PACK_EXT)


func _read_pack(path: String) -> ContentPack:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var data := f.get_buffer(f.get_length())
	f.close()
	return ContentPack.decode(data, path)


func _file_hash(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var data := f.get_buffer(f.get_length())
	f.close()
	return ContentPack.sha256_hex(data)


func _write_bytes(path: String, data: PackedByteArray) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		issues.append("无法写入: %s" % path)
		return
	f.store_buffer(data)
	f.close()


func _ensure_dir() -> void:
	if cache_dir == "":
		return
	DirAccess.make_dir_recursive_absolute(cache_dir)
