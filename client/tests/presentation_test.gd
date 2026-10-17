extends "res://tests/test_base.gd"
## 3D 表现层框架测试（任务 23：局部 3D 场景切换、缓存池、LOD、与文字 UI 解耦）。


class FakeLoader:
	extends RefCounted
	var calls: Array = []
	var scene: PackedScene
	func load_scene(path: String) -> PackedScene:
		calls.append(path)
		return scene


func _suite_name() -> String:
	return "presentation"


func run_tests() -> void:
	_test_event_bus()
	_test_switch_and_cache()
	_test_lru_eviction()
	_test_lod_resolution()
	_test_unregistered_place()
	_test_place_bindings()
	_test_placeholder_group_styles()
	_test_place_models()
	_test_presentation_root()


func _test_event_bus() -> void:
	var bus := PresentationBus.new()
	var received: Array = []
	var token := bus.subscribe("item.gained", func(payload): received.append(payload))
	check_eq(bus.subscriber_count("item.gained"), 1, "应有一个订阅者")
	check_eq(bus.publish("item.gained", {"key": "item.apple"}), 1, "应投递给一个订阅者")
	check_eq(received.size(), 1, "订阅者应收到事件")
	check(bus.unsubscribe(token), "取消订阅应成功")
	check_eq(bus.publish("item.gained", {}), 0, "取消后不应再投递")


func _make_manager() -> PlaceSceneManager:
	var mgr := PlaceSceneManager.new()
	root.add_child(mgr)
	return mgr


func _fake_loader(mgr: PlaceSceneManager) -> FakeLoader:
	var fake := FakeLoader.new()
	fake.scene = load("res://presentation/scenes/placeholder_place.tscn")
	mgr.loader = Callable(fake, "load_scene")
	return fake


func _test_switch_and_cache() -> void:
	var mgr := _make_manager()
	var fake := _fake_loader(mgr)
	mgr.register_binding("home", "res://fake/home.tscn")
	mgr.register_binding("shop", "res://fake/shop.tscn")
	var changed: Array = []
	mgr.scene_changed.connect(func(key, _inst): changed.append(key))

	check(mgr.switch_place("home"), "切换应成功")
	check_eq(mgr.current_place, "home", "当前场所应为 home")
	check(mgr.get_instance("home") != null, "应实例化场景")
	check_eq(mgr.load_count, 1, "首次应加载一次")

	check(mgr.switch_place("shop"), "切换 shop 应成功")
	check_eq(mgr.get_instance("home"), null, "离开后 home 实例应被释放")
	check_eq(mgr.load_count, 2, "新场景应加载一次")

	check(mgr.switch_place("home"), "切回 home 应成功")
	check_eq(mgr.load_count, 2, "缓存命中不应重复加载")
	check_eq(changed.size(), 3, "应发出三次切换事件")
	mgr.queue_free()


func _test_lru_eviction() -> void:
	var mgr := _make_manager()
	var fake := _fake_loader(mgr)
	mgr.max_pool_size = 1
	mgr.register_binding("a", "res://fake/a.tscn")
	mgr.register_binding("b", "res://fake/b.tscn")
	check(mgr.switch_place("a"), "切换 a")
	check(mgr.switch_place("b"), "切换 b")
	check_eq(mgr.pool_size(), 1, "缓存池应受上限约束")
	check(mgr.switch_place("a"), "再次切换 a")
	check_eq(mgr.load_count, 3, "被淘汰的资源应重新加载")
	mgr.queue_free()


func _test_lod_resolution() -> void:
	var mgr := _make_manager()
	_fake_loader(mgr)
	mgr.register_binding("shop", "res://fake/shop.tscn", {
		"near": "res://fake/shop_near.tscn",
		"mid": "res://fake/shop_mid.tscn",
		"far": "res://fake/shop_far.tscn",
	})
	check_eq(mgr.resolve_lod("shop", 3.0), "near", "近距离应用 near LOD")
	check_eq(mgr.resolve_lod("shop", 20.0), "mid", "中距离应用 mid LOD")
	check_eq(mgr.resolve_lod("shop", 99.0), "far", "远距离应用 far LOD")
	check_eq(mgr.resolve_path("shop", "far"), "res://fake/shop_far.tscn", "路径应按 LOD 解析")
	mgr.register_binding("plain", "res://fake/plain.tscn")
	check_eq(mgr.resolve_lod("plain", 99.0), "default", "未配置 LOD 时返回 default")
	mgr.queue_free()


func _test_unregistered_place() -> void:
	var mgr := _make_manager()
	_fake_loader(mgr)
	var failures: Array = []
	mgr.scene_load_failed.connect(func(key, reason): failures.append([key, reason]))
	check(not mgr.switch_place("nowhere"), "未注册场所切换应失败")
	check_eq(failures.size(), 1, "应报告加载失败")
	mgr.queue_free()


func _test_place_bindings() -> void:
	var mgr := _make_manager()
	check_eq(PlaceBindings.register_all(mgr), 13, "应注册 13 个场所分组")
	check(PlaceBindings.has_group("medical"), "应包含医疗分组")
	check(PlaceBindings.scene_for("medical").ends_with("placeholder_place.tscn"), "首发使用占位场景")
	# 默认加载器直接加载占位场景，验证绑定可实际实例化。
	check(mgr.switch_place("medical"), "绑定场景应可加载")
	check(mgr.get_instance("medical") != null, "应实例化医疗场所")
	mgr.queue_free()


func _test_placeholder_group_styles() -> void:
	# 13 组差异化风格齐备，关键分组形状不同（回退路径）。
	check_eq(PlaceholderAssets.GROUP_STYLES.size(), 13, "13 组风格齐备")
	check_eq(String(PlaceholderAssets.group_style("medical").get("prop", "")), "prism", "医疗道具为棱柱")
	check_eq(String(PlaceholderAssets.group_style("nature").get("prop", "")), "sphere", "自然道具为球体")
	check_eq(String(PlaceholderAssets.group_style("unknown").get("prop", "")), "prism", "未知分组回退 special")
	# 场景管理器注入分组后优先使用生成的 GLB 模型。
	var mgr := _make_manager()
	check_eq(PlaceBindings.register_all(mgr), 13, "注册 13 个分组")
	check(mgr.switch_place("medical"), "医疗场景可加载")
	var inst: Node = mgr.get_instance("medical")
	check(inst != null, "应实例化医疗场所")
	check(inst.using_model_assets(), "医疗场所应使用生成的 GLB 模型")
	check(inst.get_node_or_null("Model") != null, "模型节点存在")
	var ground: MeshInstance3D = inst.get_node_or_null("Ground")
	check(ground != null and not ground.visible, "使用模型时隐藏灰盒地面")
	# 关闭模型后回退程序化灰盒，道具数量仍由风格表决定。
	var fallback: Node3D = load("res://presentation/scenes/placeholder_place.tscn").instantiate()
	fallback.model_enabled = false
	root.add_child(fallback)
	fallback.set_place_group("nature")
	var props: Node = fallback.get_node_or_null("Props")
	check(props != null and props.get_child_count() == int(PlaceholderAssets.group_style("nature").get("props", 0)), "回退灰盒道具数量匹配")
	fallback.queue_free()
	mgr.queue_free()


func _test_place_models() -> void:
	# meshgen 产物契约：13 个分组各有可导入的 GLB 与清单。
	for g in PlaceBindings.GROUPS:
		var path: String = "res://assets/models/place_groups/%s.glb" % g
		check(ResourceLoader.exists(path), "场所模型存在：%s" % g)
		var packed := load(path) as PackedScene
		check(packed != null, "场所模型可加载：%s" % g)
		if packed != null:
			var node: Node = packed.instantiate()
			check(node is Node3D, "场所模型根节点为 3D：%s" % g)
			node.free()
	check(FileAccess.file_exists("res://assets/models/place_groups/manifest.json"), "模型清单存在")


func _test_presentation_root() -> void:
	var pr := PresentationRoot.new()
	root.add_child(pr)
	check_eq(pr.binding_count(), 13, "表现层根应完成场所绑定")
	var got: Array = []
	pr.bus.subscribe("evt", func(p): got.append(p))
	check_eq(pr.publish("evt", 42), 1, "表现层根应转发事件")
	check_eq(got.size(), 1, "订阅者应收到事件")
	pr.queue_free()
