extends "res://tests/test_base.gd"
## 3D 表现层骨架与占位资产测试（任务 23）：
## ContentDef Resource 往返、PlaceholderAssets 确定性、Site3DManager 加载/缓存/LOD/淘汰/序列化。

const ContentDefScript = preload("res://sim/content_def.gd")
const PlaceholderAssetsScript = preload("res://sim/placeholder_assets.gd")
const Site3DScript = preload("res://sim/site3d.gd")

func _suite_name() -> String:
	return "site3d"

func run_tests() -> void:
	_test_content_def()
	_test_placeholder_deterministic()
	_test_site_load_and_hit()
	_test_site_lod_reload()
	_test_site_cache_eviction()
	_test_site_serialization()
	_test_site_from_entries()

func _test_site_from_entries() -> void:
	var mgr := Site3DScript.new()
	var n: int = mgr.load_from_entries({
		"site.home": {"scene": "res://assets/placeholder/site_home.tscn", "category": "residence", "radius": 8.0},
		"site.cafe": {"scene": "res://assets/placeholder/site_cafe.tscn"},
		"site.broken": {"category": "x"},
	})
	check_eq(n, 2, "仅注册有场景路径的条目")
	check(mgr.has_binding("site.home"), "地点绑定")
	check(not mgr.has_binding("site.broken"), "缺少场景的条目不注册")
	check_eq(mgr.binding_for("site.home")["category"], "residence", "类别保留")
	check_near(mgr.binding_for("site.home")["radius"], 8.0, 0.001, "半径保留")

func _test_content_def() -> void:
	var def: Resource = ContentDefScript.from_entry("jobs", "occupation.engineer", {"name": "工程师", "level": 3})
	check_eq(def.content_key, "occupation.engineer", "content_key 保留")
	check_eq(def.category, "jobs", "category 保留")
	check_eq(def.get_field("name"), "工程师", "字段读取")
	check(def.has_field("level"), "has_field")
	var entry: Dictionary = def.to_entry()
	check_eq(entry["content_key"], "occupation.engineer", "to_entry 含主键")
	var back: Resource = ContentDefScript.from_dict(def.to_dict())
	check_eq(back.content_key, def.content_key, "from_dict 往返主键")
	check_eq(back.get_field("level"), 3, "from_dict 往返字段")

func _test_placeholder_deterministic() -> void:
	var a: Dictionary = PlaceholderAssetsScript.resolve("location.city.a", "site")
	var b: Dictionary = PlaceholderAssetsScript.resolve("location.city.a", "site")
	check_eq(a["primitive"], b["primitive"], "占位几何体确定")
	check_eq(a["color"], b["color"], "占位颜色确定")
	check(a["placeholder"], "标记为占位")
	check(str(a["path"]).begins_with("res://assets/placeholder/"), "占位路径前缀")
	check(PlaceholderAssetsScript.is_placeholder_path(a["path"]), "占位路径识别")
	check(not PlaceholderAssetsScript.is_placeholder_path("res://assets/models/x.glb"), "真实资产不被识别为占位")

func _test_site_load_and_hit() -> void:
	var mgr := Site3DScript.new()
	mgr.register_placeholder("location.cafe", "shop", 5.0)
	check(mgr.has_binding("location.cafe"), "绑定注册")
	var r1: Dictionary = mgr.request_site("location.cafe", 5.0)
	check_eq(r1["status"], "queued", "首次请求入队")
	check(not mgr.is_loaded("location.cafe"), "未完成加载前不在缓存")
	check_eq(mgr.pending_count(), 1, "待加载计数")
	var done: Dictionary = mgr.poll_load()
	check_eq(done["key"], "location.cafe", "加载完成键")
	check(mgr.is_loaded("location.cafe"), "加载后进入缓存")
	check_eq(mgr.ref_count("location.cafe"), 1, "引用计数为 1")
	var r2: Dictionary = mgr.request_site("location.cafe", 5.0)
	check_eq(r2["status"], "hit", "已在缓存命中")
	check_eq(mgr.ref_count("location.cafe"), 2, "命中累加引用")

func _test_site_lod_reload() -> void:
	var mgr := Site3DScript.new()
	mgr.register_binding("location.park", "res://a.glb", {0: "res://a_lod0.glb", 1: "res://a_lod1.glb", 2: "res://a_lod2.glb"})
	mgr.request_site("location.park", 5.0)
	mgr.poll_load()
	check_eq(mgr.loaded_tier("location.park"), Site3DScript.LOD_NEAR, "近距 LOD0")
	var far: Dictionary = mgr.request_site("location.park", 100.0)
	check_eq(far["status"], "reload", "远距触发重载")
	check_eq(mgr.loaded_tier("location.park"), Site3DScript.LOD_FAR, "切换到 LOD2")
	check_eq(mgr.loaded["location.park"]["path"], "res://a_lod2.glb", "LOD2 路径")
	check_eq(Site3DScript.lod_tier_for(10.0), Site3DScript.LOD_NEAR, "阈值近")
	check_eq(Site3DScript.lod_tier_for(30.0), Site3DScript.LOD_MID, "阈值中")
	check_eq(Site3DScript.lod_tier_for(80.0), Site3DScript.LOD_FAR, "阈值远")

func _test_site_cache_eviction() -> void:
	var mgr := Site3DScript.new()
	mgr.max_cache = 2
	for i in range(4):
		var key := "location.%d" % i
		mgr.register_placeholder(key)
		mgr.request_site(key, 5.0)
		mgr.poll_load()
		# 模拟离开地点：释放引用后才会被 LRU 淘汰。
		mgr.release_site(key)
	check_eq(mgr.loaded_count(), 2, "缓存不超过上限")
	check(mgr.is_loaded("location.3"), "最近加载保留")
	check(not mgr.is_loaded("location.0"), "最久未用被淘汰")
	# 有引用的场景不被淘汰。
	var mgr2 := Site3DScript.new()
	mgr2.max_cache = 1
	mgr2.register_placeholder("location.a")
	mgr2.request_site("location.a", 5.0, 2)
	mgr2.poll_load()
	mgr2.register_placeholder("location.b")
	mgr2.request_site("location.b", 5.0)
	mgr2.poll_load()
	check(mgr2.is_loaded("location.a"), "有引用的场景不被淘汰")

func _test_site_serialization() -> void:
	var mgr := Site3DScript.new()
	mgr.max_cache = 3
	mgr.register_placeholder("location.x")
	mgr.request_site("location.x", 5.0)
	mgr.poll_load()
	var doc: Dictionary = mgr.to_dict()
	var restored := Site3DScript.new()
	restored.from_dict(doc)
	check(restored.has_binding("location.x"), "绑定往返")
	check(restored.is_loaded("location.x"), "缓存往返")
	check_eq(restored.loaded_tier("location.x"), Site3DScript.LOD_NEAR, "LOD 往返")
	check_eq(restored.max_cache, 3, "缓存上限往返")
	check(restored.request_site("location.x", 5.0)["status"] == "hit", "恢复后可命中")
	check_eq(mgr.request_site("location.unknown", 5.0)["status"], "missing", "未绑定地点返回 missing")
