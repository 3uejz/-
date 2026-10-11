class_name ShardedSource
extends RefCounted
## 大资源分包与分片差量下载、按区域按需挂载（R36；任务 23，面向 30GB 级资产）。
##
## 分片（shard）在清单中按固定 shard_bytes 切块，每块记录 offset/length/hash；
## 下载器通过 range_fetcher 注入以避免把整份资产读入内存：
##   range_fetcher 签名：func(url: String, offset: int, length: int) -> PackedByteArray
## 支持断点续传（已下载分片记录在案，重复调用只补缺失部分）、整片哈希校验、
## 按区域挂载（只取所需区域分片）与按 LRU 淘汰未挂载分片到磁盘预算内。
## 纯逻辑，可 headless 测试。

var manifest: Dictionary = {}
var range_fetcher: Callable = Callable()
var cache_dir: String = ""
## 磁盘预算（字节）；0 表示不限。
var disk_budget: int = 0

var _mounted: Dictionary = {}     # shard id -> true
var _downloaded: Dictionary = {}  # shard id -> {size, hash, last_used, path}
var _parts: Dictionary = {}       # shard id -> { offset: true } 已完成分片
## 无缓存目录（cache_dir==""）时的内存块回退：shard id -> { offset: PackedByteArray }。
var _mem_parts: Dictionary = {}
var _clock: int = 0


func _init(manifest_data: Dictionary = {}, fetcher_fn: Callable = Callable(), cache_path: String = "", budget_bytes: int = 0) -> void:
	manifest = manifest_data
	range_fetcher = fetcher_fn
	cache_dir = cache_path
	disk_budget = budget_bytes


func shards() -> Array:
	return (manifest.get("shards", []) as Array).duplicate(true)


func shard(id: String) -> Dictionary:
	for s in manifest.get("shards", []):
		if typeof(s) == TYPE_DICTIONARY and String(s.get("id", "")) == id:
			return s
	return {}


func regions() -> Array:
	var out: Array = []
	for s in manifest.get("shards", []):
		if typeof(s) != TYPE_DICTIONARY:
			continue
		var r := String(s.get("region", ""))
		if r != "" and not out.has(r):
			out.append(r)
	out.sort()
	return out


## 计算某分片尚未下载的块（断点续传：已下载块跳过）。
func plan(id: String) -> Array:
	var s: Dictionary = shard(id)
	if s.is_empty():
		return []
	var done: Dictionary = _parts.get(id, {})
	var out: Array = []
	for p in s.get("parts", []):
		if typeof(p) != TYPE_DICTIONARY:
			continue
		var off := int(p.get("offset", 0))
		if not done.has(off):
			out.append(p)
	return out


## 下载并校验单个分片；返回 {ok, reason, bytes_downloaded}。
func download_shard(id: String) -> Dictionary:
	var s: Dictionary = shard(id)
	if s.is_empty():
		return {"ok": false, "reason": "unknown_shard", "bytes_downloaded": 0}
	if not range_fetcher.is_valid():
		return {"ok": false, "reason": "no_fetcher", "bytes_downloaded": 0}
	var url := String(s.get("url", ""))
	var done: Dictionary = _parts.get(id, {})
	var got := 0
	for p in s.get("parts", []):
		if typeof(p) != TYPE_DICTIONARY:
			continue
		var off := int(p.get("offset", 0))
		var length := int(p.get("length", 0))
		if done.has(off):
			continue
		var chunk: PackedByteArray = range_fetcher.call(url, off, length)
		if chunk.size() != length:
			return {"ok": false, "reason": "short_read", "bytes_downloaded": got}
		if ContentPack.sha256_hex(chunk) != String(p.get("hash", "")):
			return {"ok": false, "reason": "part_hash_mismatch", "bytes_downloaded": got}
		done[off] = true
		_store_part(id, off, chunk)
		got += length
	_parts[id] = done
	var full := _assemble(id)
	if full.size() != int(s.get("size", full.size())):
		return {"ok": false, "reason": "size_mismatch", "bytes_downloaded": got}
	if ContentPack.sha256_hex(full) != String(s.get("hash", "")):
		return {"ok": false, "reason": "shard_hash_mismatch", "bytes_downloaded": got}
	_write_cache(id, full)
	_clock += 1
	_downloaded[id] = {"size": full.size(), "hash": String(s.get("hash", "")), "last_used": _clock, "path": _cache_path(id)}
	return {"ok": true, "reason": "ok", "bytes_downloaded": got}


## 按区域挂载：下载该区域全部分片；返回挂载数量。
func mount_region(region_key: String) -> Dictionary:
	var count := 0
	var failed: Array = []
	for s in manifest.get("shards", []):
		if typeof(s) != TYPE_DICTIONARY or String(s.get("region", "")) != region_key:
			continue
		var id := String(s.get("id", ""))
		if not _downloaded.has(id):
			var r: Dictionary = download_shard(id)
			if not bool(r["ok"]):
				failed.append({"id": id, "reason": String(r["reason"])})
				continue
		_mounted[id] = true
		count += 1
	_evict_if_needed()
	return {"ok": failed.is_empty(), "mounted": count, "failed": failed}


func unmount_region(region_key: String) -> int:
	var n := 0
	for s in manifest.get("shards", []):
		if typeof(s) != TYPE_DICTIONARY or String(s.get("region", "")) != region_key:
			continue
		var id := String(s.get("id", ""))
		if _mounted.erase(id):
			n += 1
	return n


func is_downloaded(id: String) -> bool:
	return _downloaded.has(id)

func is_mounted(id: String) -> bool:
	return _mounted.has(id)

func mounted_shards() -> Array:
	var ids: Array = _mounted.keys()
	ids.sort()
	return ids


## 已缓存总分片数（按图纸大小计）。
func cached_bytes() -> int:
	var n := 0
	for id in _downloaded:
		n += int(_downloaded[id].get("size", 0))
	return n


## 超预算时按 LRU 淘汰未挂载分片。
func _evict_if_needed() -> void:
	if disk_budget <= 0:
		return
	while cached_bytes() > disk_budget:
		var victim := ""
		var oldest := 1 << 62
		for id in _downloaded:
			if _mounted.has(id):
				continue
			var lu := int(_downloaded[id].get("last_used", 0))
			if lu < oldest:
				oldest = lu
				victim = id
		if victim == "":
			return
		_downloaded.erase(victim)
		_parts.erase(victim)
		_remove_cache(victim)
		_clear_parts(victim)


## 从已落盘的块拼装整片，不再次回源（断点续传/重复调用不产生额外网络请求）。
## 仅当某块在内存与磁盘都缺失时才回源补齐一次（例如仅丢失部分缓存）。
func _assemble(id: String) -> PackedByteArray:
	var s: Dictionary = shard(id)
	var out := PackedByteArray()
	var parts: Array = (s.get("parts", []) as Array).duplicate()
	parts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["offset"]) < int(b["offset"]))
	for p in parts:
		var off := int(p["offset"])
		var chunk: PackedByteArray = _load_part(id, off)
		if chunk.is_empty() and range_fetcher.is_valid():
			chunk = range_fetcher.call(String(s.get("url", "")), off, int(p["length"]))
			_store_part(id, off, chunk)
		out.append_array(chunk)
	return out


func _cache_path(id: String) -> String:
	return cache_dir.path_join(id + ".shard") if cache_dir != "" else ""


func _write_cache(id: String, data: PackedByteArray) -> void:
	if cache_dir == "":
		return
	DirAccess.make_dir_recursive_absolute(cache_dir)
	var f := FileAccess.open(_cache_path(id), FileAccess.WRITE)
	if f == null:
		return
	f.store_buffer(data)
	f.close()


func _remove_cache(id: String) -> void:
	if cache_dir == "":
		return
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_cache_path(id)))


func _part_path(id: String, offset: int) -> String:
	return cache_dir.path_join("%s.%d.part" % [id, offset])


## 落盘（有缓存目录）或存入内存（无缓存目录），供 _assemble 复用。
func _store_part(id: String, offset: int, chunk: PackedByteArray) -> void:
	if cache_dir == "":
		if not _mem_parts.has(id):
			_mem_parts[id] = {}
		_mem_parts[id][offset] = chunk
		return
	DirAccess.make_dir_recursive_absolute(cache_dir)
	var f := FileAccess.open(_part_path(id, offset), FileAccess.WRITE)
	if f == null:
		return
	f.store_buffer(chunk)
	f.close()


func _load_part(id: String, offset: int) -> PackedByteArray:
	if cache_dir == "":
		return _mem_parts.get(id, {}).get(offset, PackedByteArray())
	var path := _part_path(id, offset)
	if not FileAccess.file_exists(path):
		return PackedByteArray()
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return PackedByteArray()
	var data := f.get_buffer(f.get_length())
	f.close()
	return data


func _clear_parts(id: String) -> void:
	_mem_parts.erase(id)
	if cache_dir == "":
		return
	var s: Dictionary = shard(id)
	for p in s.get("parts", []):
		if typeof(p) != TYPE_DICTIONARY:
			continue
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_part_path(id, int(p.get("offset", 0)))))
