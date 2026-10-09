class_name Site3DManager
extends RefCounted
## 局部 3D 场景管理器（任务 23：按当前场所加载与卸载、异步加载与资源缓存池、场景级 LOD）。
## 纯逻辑：不直接持有节点树，只维护「地点键 -> 场景路径」绑定、加载队列、引用计数与 LRU 缓存。
## 表现层（client/ui/...）按本类返回的 path/tier 真正实例化与释放场景，便于 headless 测试。
## 设计约束：不做无缝开放世界流式加载；跨场所切换由指令驱动。

const LOD_NEAR: int = 0
const LOD_MID: int = 1
const LOD_FAR: int = 2
## 距离阈值（米）：<= NEAR_MAX 用 LOD0，<= MID_MAX 用 LOD1，其余 LOD2。
const NEAR_MAX_DISTANCE: float = 15.0
const MID_MAX_DISTANCE: float = 40.0
const DEFAULT_CACHE_SIZE: int = 8

var bindings: Dictionary = {}   # location_key -> {"scene":String,"lods":{tier:path},"category":String,"radius":float,"placeholder":bool}
var loaded: Dictionary = {}     # location_key -> {"tier":int,"path":String,"refs":int,"last_used":int}
var pending: Array = []         # [{key,tier,path,refs}]
var max_cache: int = DEFAULT_CACHE_SIZE
var events: Array = []
var _clock: int = 0


## 注册地点到 3D 场景的绑定。lod_paths 为 {tier:int -> 路径}，缺省时回退到 scene_path。
func register_binding(location_key: String, scene_path: String, lod_paths: Dictionary = {}, category: String = "", radius: float = 0.0) -> void:
	bindings[location_key] = {
		"scene": scene_path,
		"lods": lod_paths.duplicate(true),
		"category": category,
		"radius": radius,
		"placeholder": PlaceholderAssets.is_placeholder_path(scene_path),
	}


## 便捷方法：无真实资产时注册占位绑定（灰盒）。
func register_placeholder(location_key: String, category: String = "", radius: float = 6.0) -> void:
	var desc: Dictionary = PlaceholderAssets.scene_descriptor(location_key, category, radius)
	register_binding(location_key, desc["path"], {}, category, radius)
	bindings[location_key]["placeholder"] = true
	bindings[location_key]["primitive"] = desc["primitive"]
	bindings[location_key]["color"] = desc["color"]


## 从 contentregistry 的 sites 类别批量注册绑定：
## entries 为 content_key -> {scene, category, radius}。
func load_from_entries(entries: Dictionary) -> int:
	var n: int = 0
	for key in entries:
		var f: Dictionary = entries[key] if entries[key] is Dictionary else {}
		var scene: String = str(f.get("scene", ""))
		if scene == "":
			continue
		register_binding(str(key), scene, {}, str(f.get("category", "")), float(f.get("radius", 0.0)))
		n += 1
	return n


## 从 ContentRegistry 的 "sites" 类别注册绑定；返回注册数量。
func load_from_registry(registry) -> int:
	if registry == null:
		return 0
	var cats: Variant = registry.get("entries")
	if not (cats is Dictionary) or not cats.has("sites"):
		return 0
	return load_from_entries(cats["sites"])


func has_binding(location_key: String) -> bool:
	return bindings.has(location_key)


func binding_for(location_key: String) -> Dictionary:
	return bindings.get(location_key, {})


static func lod_tier_for(distance: float) -> int:
	if distance <= NEAR_MAX_DISTANCE:
		return LOD_NEAR
	if distance <= MID_MAX_DISTANCE:
		return LOD_MID
	return LOD_FAR


func path_for(location_key: String, tier: int) -> String:
	if not bindings.has(location_key):
		return ""
	var b: Dictionary = bindings[location_key]
	var lods: Dictionary = b.get("lods", {})
	if lods.has(tier):
		return str(lods[tier])
	return str(b.get("scene", ""))


func is_loaded(location_key: String) -> bool:
	return loaded.has(location_key)


func loaded_tier(location_key: String) -> int:
	if not loaded.has(location_key):
		return -1
	return int(loaded[location_key].get("tier", -1))


func ref_count(location_key: String) -> int:
	if not loaded.has(location_key):
		return 0
	return int(loaded[location_key].get("refs", 0))


## 请求进入某地点。返回 {ok, status, tier, path}；status in {missing,hit,reload,queued}。
func request_site(location_key: String, distance: float, refs: int = 1) -> Dictionary:
	if not bindings.has(location_key):
		return {"ok": false, "status": "missing", "tier": -1, "path": ""}
	var tier: int = lod_tier_for(distance)
	if loaded.has(location_key):
		var e: Dictionary = loaded[location_key]
		e["refs"] = int(e.get("refs", 0)) + maxi(refs, 1)
		_touch(location_key)
		if int(e.get("tier", -1)) == tier:
			_log("hit", location_key, tier)
			return {"ok": true, "status": "hit", "tier": tier, "path": str(e.get("path", ""))}
		e["tier"] = tier
		e["path"] = path_for(location_key, tier)
		_log("reload", location_key, tier)
		return {"ok": true, "status": "reload", "tier": tier, "path": str(e["path"])}
	pending.append({"key": location_key, "tier": tier, "path": path_for(location_key, tier), "refs": maxi(refs, 1)})
	_log("queued", location_key, tier)
	return {"ok": true, "status": "queued", "tier": tier, "path": path_for(location_key, tier)}


## 完成一个待加载项（模拟异步加载完成）。返回加载结果，队列为空时返回 {}。
func poll_load() -> Dictionary:
	if pending.is_empty():
		return {}
	var item: Dictionary = pending.pop_front()
	var key: String = str(item["key"])
	var tier: int = int(item["tier"])
	var path: String = str(item["path"])
	var refs: int = int(item["refs"])
	if loaded.has(key):
		var e: Dictionary = loaded[key]
		e["refs"] = int(e.get("refs", 0)) + refs
		e["tier"] = tier
		e["path"] = path
		_touch(key)
	else:
		_clock += 1
		loaded[key] = {"tier": tier, "path": path, "refs": refs, "last_used": _clock}
	_log("loaded", key, tier)
	_evict()
	return {"key": key, "tier": tier, "path": path}


## 完成全部待加载项。
func drain() -> Array:
	var out: Array = []
	while not pending.is_empty():
		out.append(poll_load())
	return out


func release_site(location_key: String, refs: int = 1) -> bool:
	if not loaded.has(location_key):
		return false
	loaded[location_key]["refs"] = maxi(0, int(loaded[location_key]["refs"]) - maxi(refs, 1))
	return true


func unload(location_key: String) -> bool:
	if not loaded.has(location_key):
		return false
	var tier: int = int(loaded[location_key].get("tier", -1))
	loaded.erase(location_key)
	_log("unloaded", location_key, tier)
	return true


func loaded_count() -> int:
	return loaded.size()


func pending_count() -> int:
	return pending.size()


func _touch(location_key: String) -> void:
	_clock += 1
	if loaded.has(location_key):
		loaded[location_key]["last_used"] = _clock


## 缓存池超限时按 LRU 淘汰「无引用」场景。
func _evict() -> void:
	while loaded.size() > max_cache:
		var victim: String = ""
		var oldest: int = 1 << 62
		for k in loaded:
			if int(loaded[k].get("refs", 0)) > 0:
				continue
			var lu: int = int(loaded[k].get("last_used", 0))
			if lu < oldest:
				oldest = lu
				victim = str(k)
		if victim == "":
			break
		_log("evicted", victim, int(loaded[victim].get("tier", -1)))
		loaded.erase(victim)


func _log(action: String, key: String, tier: int) -> void:
	events.append({"action": action, "key": key, "tier": tier, "at": _clock})


func to_dict() -> Dictionary:
	var bin_out: Dictionary = {}
	for k in bindings:
		bin_out[k] = {
			"scene": bindings[k].get("scene", ""),
			"lods": bindings[k].get("lods", {}),
			"category": bindings[k].get("category", ""),
			"radius": bindings[k].get("radius", 0.0),
		}
	var loaded_out: Dictionary = {}
	for k in loaded:
		loaded_out[k] = loaded[k].duplicate(true)
	return {
		"bindings": bin_out,
		"loaded": loaded_out,
		"pending": pending.duplicate(true),
		"max_cache": max_cache,
		"clock": _clock,
	}


func from_dict(doc: Dictionary) -> void:
	bindings.clear()
	loaded.clear()
	pending.clear()
	var b: Dictionary = doc.get("bindings", {}) if doc.get("bindings") is Dictionary else {}
	for k in b:
		var item: Dictionary = b[k]
		register_binding(str(k), str(item.get("scene", "")), item.get("lods", {}), str(item.get("category", "")), float(item.get("radius", 0.0)))
	var l: Dictionary = doc.get("loaded", {}) if doc.get("loaded") is Dictionary else {}
	for k in l:
		loaded[str(k)] = (l[k] as Dictionary).duplicate(true)
	pending = doc.get("pending", []).duplicate(true) if doc.get("pending") is Array else []
	max_cache = int(doc.get("max_cache", DEFAULT_CACHE_SIZE))
	_clock = int(doc.get("clock", 0))
