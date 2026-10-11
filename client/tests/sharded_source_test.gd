extends "res://tests/test_base.gd"
## 分包分片下载与按区域挂载测试（任务 23，R36）：断点续传、分片哈希、LRU 淘汰。

const ShardedScript = preload("res://content/sharded_source.gd")
const CACHE := "user://lt_shard_test"

var _keep: Array = []


class RangeFetcher:
	extends RefCounted
	var blobs: Dictionary = {}    # url -> PackedByteArray
	var corrupt_part: String = "" # 命中 "<url>@<offset>" 时末字节翻转
	var fetch_calls: int = 0       # 网络请求计数，用于断言断点续传不回源
	func fetch(url: String, offset: int, length: int) -> PackedByteArray:
		fetch_calls += 1
		if not blobs.has(url):
			return PackedByteArray()
		var full: PackedByteArray = blobs[url]
		if offset < 0 or offset + length > full.size():
			return PackedByteArray()
		var chunk: PackedByteArray = full.slice(offset, offset + length)
		if corrupt_part == "%s@%d" % [url, offset] and chunk.size() > 0:
			chunk[chunk.size() - 1] = (chunk[chunk.size() - 1] + 1) % 256
		return chunk


func _suite_name() -> String:
	return "sharded_source"


func run_tests() -> void:
	_clear_cache()
	_test_plan_and_download()
	_test_part_hash_mismatch()
	_test_region_mount()
	_test_lru_eviction()


func _clear_cache() -> void:
	var abs := ProjectSettings.globalize_path(CACHE)
	var d := DirAccess.open(abs)
	if d == null:
		DirAccess.make_dir_recursive_absolute(abs)
		return
	for f in d.get_files():
		d.remove(f)


func _blob(n: int) -> PackedByteArray:
	var b := PackedByteArray()
	for i in range(n):
		b.append((i * 7 + 3) % 256)
	return b


func _make(manifest: Dictionary, fetcher: RangeFetcher, budget: int = 0):
	var s = ShardedScript.new(manifest, Callable(fetcher, "fetch"), CACHE, budget)
	_keep.append(fetcher)
	return s


func _shard_manifest() -> Dictionary:
	var full := _blob(300)
	var parts: Array = []
	for off in [0, 100, 200]:
		parts.append({"offset": off, "length": 100, "hash": ContentPack.sha256_hex(full.slice(off, off + 100))})
	return {
		"shard_bytes": 100,
		"shards": [
			{"id": "east_0", "region": "east", "size": 300, "hash": ContentPack.sha256_hex(full), "url": "pack://east", "parts": parts},
		],
		"_full": full,
	}


func _test_plan_and_download() -> void:
	var m: Dictionary = _shard_manifest()
	var f := RangeFetcher.new()
	f.blobs["pack://east"] = m["_full"]
	var s = _make(m, f)
	check_eq(s.plan("east_0").size(), 3, "初始计划 3 块")
	check_eq(s.plan("missing").size(), 0, "未知分片无计划")
	var r: Dictionary = s.download_shard("east_0")
	check(bool(r["ok"]), "分片下载成功")
	check_eq(int(r["bytes_downloaded"]), 300, "下载字节数")
	check_eq(f.fetch_calls, 3, "首次下载恰好请求 3 块")
	check(s.is_downloaded("east_0"), "已缓存")
	check_eq(s.cached_bytes(), 300, "缓存字节统计")
	var r2: Dictionary = s.download_shard("east_0")
	check(bool(r2["ok"]), "重复下载成功")
	check_eq(int(r2["bytes_downloaded"]), 0, "断点续传不重复下载")
	check_eq(f.fetch_calls, 3, "重复下载不回源（断点续传生效）")


func _test_part_hash_mismatch() -> void:
	var m: Dictionary = _shard_manifest()
	var f := RangeFetcher.new()
	f.blobs["pack://east"] = m["_full"]
	f.corrupt_part = "pack://east@100"
	var s = _make(m, f)
	var r: Dictionary = s.download_shard("east_0")
	check(not bool(r["ok"]), "损坏块被拒")
	check_eq(String(r["reason"]), "part_hash_mismatch", "报块哈希不符")


func _test_region_mount() -> void:
	var m: Dictionary = _shard_manifest()
	var f := RangeFetcher.new()
	f.blobs["pack://east"] = m["_full"]
	var s = _make(m, f)
	check_eq(s.regions(), ["east"], "区域列表")
	var r: Dictionary = s.mount_region("east")
	check(bool(r["ok"]), "区域挂载成功")
	check_eq(int(r["mounted"]), 1, "挂载 1 片")
	check(s.is_mounted("east_0"), "分片已挂载")
	check_eq(s.unmount_region("east"), 1, "卸载成功")


func _test_lru_eviction() -> void:
	var full := _blob(200)
	var parts1: Array = []
	var parts2: Array = []
	for off in [0, 100]:
		parts1.append({"offset": off, "length": 100, "hash": ContentPack.sha256_hex(full.slice(off, off + 100))})
	for off in [0, 100]:
		parts2.append({"offset": off, "length": 100, "hash": ContentPack.sha256_hex(full.slice(off, off + 100))})
	var manifest := {"shard_bytes": 100, "shards": [
		{"id": "east_0", "region": "east", "size": 200, "hash": ContentPack.sha256_hex(full), "url": "pack://e1", "parts": parts1},
		{"id": "west_0", "region": "west", "size": 200, "hash": ContentPack.sha256_hex(full), "url": "pack://w1", "parts": parts2},
	]}
	var f := RangeFetcher.new()
	f.blobs["pack://e1"] = full
	f.blobs["pack://w1"] = full
	# 预算只够一片：先下载 west（未挂载），再挂载 east，触发对 west 的 LRU 淘汰。
	var s = _make(manifest, f, 200)
	check(bool(s.download_shard("west_0")["ok"]), "预下载 west")
	check(s.is_downloaded("west_0"), "west 已缓存")
	var r: Dictionary = s.mount_region("east")
	check(bool(r["ok"]), "挂载 east")
	check(s.is_downloaded("east_0"), "east 保留")
	check(not s.is_downloaded("west_0"), "west 被 LRU 淘汰")
	# ContentManager 集成：注入分片源后按区域键挂载美术包。
	var manager = ContentManager.new({}, Callable(), CACHE)
	manager.set_sharded_source(s)
	check_eq(manager.mount_region("east"), 1, "经内容管理器挂载分片区域")
