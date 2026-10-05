class_name PlaceSceneManager
extends Node
## 局部 3D 场景管理：按当前场所加载/卸载场景、异步资源、缓存池与场景级 LOD。
## 跨场所切换由 2D 地图与文字指令驱动，不做无缝开放世界流式加载。
## 与玩法解耦：本类只依据外部指令切换表现，不修改任何玩法状态。

signal scene_changed(place_key: String, instance: Node)
signal scene_load_failed(place_key: String, reason: String)
signal scene_unloaded(place_key: String)

## 绑定的资源加载器，签名 func(path: String) -> PackedScene；默认走 ResourceLoader。
var loader: Callable = Callable()
## 缓存池上限（PackedScene 份数）。
var max_pool_size: int = 8
## 场景挂载根；为空时挂到自身。
var scene_root: Node = null

var _bindings: Dictionary = {}       # place_key -> { "path": String, "lods": {level: path} }
var _pool: Dictionary = {}           # path -> PackedScene
var _pool_order: Array = []          # LRU 顺序（尾部最新）
var _instances: Dictionary = {}      # place_key -> Node
var current_place: String = ""
var load_count: int = 0              # 实际调用加载器的次数（测试用）


func _ready() -> void:
	if scene_root == null:
		scene_root = self


## 注册场所绑定。lods 形如 { "near": path, "mid": path, "far": path }；为空则统一用 path。
func register_binding(place_key: String, scene_path: String, lods: Dictionary = {}) -> void:
	_bindings[place_key] = {"path": scene_path, "lods": lods.duplicate(true)}


func has_binding(place_key: String) -> bool:
	return _bindings.has(place_key)


## 立即切换场景（同步获取缓存或加载资源）。
func switch_place(place_key: String, lod_level: String = "") -> bool:
	if not _bindings.has(place_key):
		scene_load_failed.emit(place_key, "未注册的场所")
		return false
	var path := resolve_path(place_key, lod_level)
	if path == "":
		scene_load_failed.emit(place_key, "缺少场景资源")
		return false
	var packed := _acquire(path)
	if packed == null or not (packed is PackedScene):
		scene_load_failed.emit(place_key, "资源加载失败: %s" % path)
		return false

	_release_instance(current_place)
	current_place = place_key
	var instance: Node = packed.instantiate()
	if instance is Node3D:
		(instance as Node3D).name = "Place_%s" % place_key
	var host: Node = scene_root if scene_root != null else self
	host.add_child(instance)
	_instances[place_key] = instance
	scene_changed.emit(place_key, instance)
	return true


## 卸载指定场所的实例（不从缓存池移除）。
func unload_place(place_key: String) -> void:
	_release_instance(place_key)
	if current_place == place_key:
		current_place = ""


## 清空缓存池（释放已缓存的 PackedScene 引用）。
func clear_pool() -> void:
	_pool.clear()
	_pool_order.clear()


func pool_size() -> int:
	return _pool.size()


func binding_count() -> int:
	return _bindings.size()


## 依据距离选择 LOD 层级；未配置 lods 时返回 "default"。
func resolve_lod(place_key: String, distance: float, near: float = 8.0, mid: float = 30.0) -> String:
	if not _bindings.has(place_key):
		return ""
	var lods: Dictionary = _bindings[place_key]["lods"]
	if lods.is_empty():
		return "default"
	if distance <= near:
		return "near"
	if distance <= mid:
		return "mid"
	return "far"


func resolve_path(place_key: String, lod_level: String) -> String:
	if not _bindings.has(place_key):
		return ""
	var binding: Dictionary = _bindings[place_key]
	var lods: Dictionary = binding["lods"]
	if lod_level == "" or lods.is_empty():
		return str(binding["path"])
	if lods.has(lod_level):
		return str(lods[lod_level])
	return str(binding["path"])


func get_instance(place_key: String) -> Node:
	return _instances.get(place_key, null)


func _acquire(path: String) -> PackedScene:
	if _pool.has(path):
		_touch(path)
		return _pool[path]
	var packed: PackedScene = null
	if loader.is_valid():
		packed = loader.call(path)
	else:
		packed = ResourceLoader.load(path)
	if packed != null:
		load_count += 1
		_pool[path] = packed
		_pool_order.append(path)
		_evict_if_needed()
	return packed


func _touch(path: String) -> void:
	_pool_order.erase(path)
	_pool_order.append(path)


func _evict_if_needed() -> void:
	while _pool_order.size() > max_pool_size:
		var oldest: String = _pool_order.pop_front()
		_pool.erase(oldest)


func _release_instance(place_key: String) -> void:
	if place_key == "" or not _instances.has(place_key):
		return
	var node: Node = _instances[place_key]
	_instances.erase(place_key)
	if is_instance_valid(node):
		node.queue_free()
	scene_unloaded.emit(place_key)
