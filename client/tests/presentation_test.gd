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
