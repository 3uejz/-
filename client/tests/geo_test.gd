extends "res://tests/test_base.gd"
## 地理、场所、交通与混合地图测试（任务 8.1；对应 R3、R4、R42）。
## 覆盖：程序生成可复现、六级层级与地点下限、核心城市手工、跨国差异、
##       场所类型/查询、两种出行数值、十二种交通、换乘路径守恒、地图 UI 壳。

const GeoDataScript = preload("res://sim/geo.gd")
const PlaceManagerScript = preload("res://sim/place_manager.gd")
const TransportScript = preload("res://sim/transport.gd")
const BaselineScript = preload("res://sim/baseline.gd")

func _suite_name() -> String:
	return "geo"

func run_tests() -> void:
	_test_generation_reproducible()
	_test_levels_and_location_count()
	_test_core_city_manual_real_coords()
	_test_multi_country_differences()
	_test_place_types_and_query()
	_test_transport_modes_and_conditions()
	_test_distance_and_monotonic()
	_test_route_conservation_and_transfer()
	_test_map_view_shell()


func _make_geo(seed: int = 20261004):
	var geo = GeoDataScript.new()
	geo.generate(seed)
	return geo


## 同种子程序生成可复现；不同种子不同。
func _test_generation_reproducible() -> void:
	var a = _make_geo(1234)
	var b = _make_geo(1234)
	check_eq(a.count(), b.count(), "同种子节点总数一致")
	check_eq(a.signature(), b.signature(), "同种子节点 id 签名一致")
	# 抽样比较一个程序生成城市的属性（含随机属性）。
	var gen_cities: Array = []
	for id in a.nodes_at_level(GeoDataScript.GeographicLevel.CITY):
		if not a.get_node(id).manual:
			gen_cities.append(id)
	check(gen_cities.size() > 0, "存在程序生成城市")
	if gen_cities.size() > 0:
		var cid: String = String(gen_cities[0])
		check(_deep_equal(a.get_node(cid).to_dict(), b.get_node(cid).to_dict()), "同种子生成城市属性一致")

	var c = _make_geo(9999)
	check(a.signature() != c.signature(), "不同种子签名不同")


## 六级地理齐全，且地点数不少于 R3.2 下限。
func _test_levels_and_location_count() -> void:
	var geo = _make_geo(7)
	check(geo.count() >= BaselineScript.GEO_MIN_TOTAL_LOCATIONS, "地点总数 ≥ %d，实际 %d" % [BaselineScript.GEO_MIN_TOTAL_LOCATIONS, geo.count()])
	for level in range(6):
		check(geo.nodes_at_level(level).size() > 0, "第 %d 级（%s）非空" % [level, GeoDataScript.LEVEL_NAMES[level]])
	check_eq(GeoDataScript.LEVEL_NAMES.size(), 6, "六级名称齐全")
	check_eq(GeoDataScript.LEVEL_CODES.size(), 6, "六级代码齐全")


## 核心城市手工设计、真实坐标；建筑层级路径完整。
func _test_core_city_manual_real_coords() -> void:
	var geo = _make_geo(20261004)
	var found: Array = geo.find_by_name("北京", GeoDataScript.GeographicLevel.CITY)
	check(found.size() > 0, "找到核心城市北京")
	if found.size() == 0:
		return
	var beijing = geo.get_node(String(found[0]))
	check(beijing.manual, "北京为手工设计")
	check_near(float(beijing.location["lat"]), 39.9042, 0.01, "北京纬度真实")
	check_near(float(beijing.location["lon"]), 116.4074, 0.01, "北京经度真实")

	# 建筑为最小可进入单元：路径应含 国家→省→市→区→街→建筑 六段。
	var buildings: Array = geo.nodes_at_level(GeoDataScript.GeographicLevel.BUILDING)
	var path: Array = geo.path_of(String(buildings[0]))
	check_eq(path.size(), 6, "建筑到根的层级路径为六段")
	check_eq(geo.get_node(String(path[0])).level, GeoDataScript.GeographicLevel.COUNTRY, "路径首段为国家")
	check_eq(geo.get_node(String(path[5])).level, GeoDataScript.GeographicLevel.BUILDING, "路径末段为建筑")


## 跨国在语言/法律/货币/证件/文化/时区上存在差异。
func _test_multi_country_differences() -> void:
	var geo = _make_geo(42)
	var cn = geo.country_profile("CN")
	var us = geo.country_profile("US")
	var jp = geo.country_profile("JP")
	check(cn != null and us != null and jp != null, "核心国家档案存在")
	if cn == null or us == null or jp == null:
		return
	check_eq(cn.currency, "CNY", "中国货币 CNY")
	check_eq(us.currency, "USD", "美国货币 USD")
	check_eq(jp.currency, "JPY", "日本货币 JPY")
	check(cn.utc_offset_minutes != us.utc_offset_minutes, "中美时区不同")
	check(cn.utc_offset_minutes != jp.utc_offset_minutes, "中日时区不同")
	check_eq(geo.local_minute("CN", 0), 480, "中国 UTC+8")
	check_eq(geo.local_minute("US", 0), -300, "美国 UTC-5")
	check_eq(geo.local_minute("JP", 0), 540, "日本 UTC+9")
	check(cn.languages[0] != us.languages[0] and cn.languages[0] != jp.languages[0], "语言不同")
	check(cn.legal_system != us.legal_system, "法律体系不同")
	check(cn.documents[0] != us.documents[0], "证件不同")
	check(cn.culture[0] != jp.culture[0], "文化不同")
	check(cn.drive_side != jp.drive_side, "驾驶方向不同")

	var currencies: Dictionary = {}
	for code in geo.countries():
		currencies[geo.country_profile(String(code)).currency] = true
	check(currencies.size() >= 8, "存在不少于 8 种货币，实际 %d" % currencies.size())


## 场所类型 ≥ 100 且覆盖 13 类；布点、营业与查询可用。
func _test_place_types_and_query() -> void:
	var pm = PlaceManagerScript.new()
	check(pm.type_count() >= 100, "场所类型 ≥ 100，实际 %d" % pm.type_count())
	check_eq(pm.categories().size(), 13, "13 大类齐全")
	for category in pm.categories():
		check(pm.types_in_category(String(category)).size() >= 8, "类别 %s 至少 8 类场所" % String(category))
	var t = pm.get_type("convenience_store")
	check(t != null, "可取到类型定义")
	check(t.available_verbs.size() > 0, "类型定义含可用动词")
	check(t.scene_binding.length() > 0, "类型定义含 3D 场景绑定")

	var geo = _make_geo(7)
	var building_count: int = geo.nodes_at_level(GeoDataScript.GeographicLevel.BUILDING).size()
	var created: int = pm.attach_to_geo(geo, 7, 1)
	check_eq(created, building_count, "每个建筑布 1 个场所")
	check_eq(pm.place_count(), building_count, "场所实例数与建筑数一致")

	var foods: Array = pm.query({"category": "food"})
	check(foods.size() > 0, "按类别查询到餐饮场所")
	var by_type: Array = pm.query({"type_key": "convenience_store"})
	check(by_type.size() > 0, "按类型查询到便利店")
	var sample = by_type[0]
	check(pm.query({"open_at": 720}).size() > 0, "按营业时间查询非空")

	# 24 小时便利店全天营业；夜市跨夜。
	check(sample.is_open_at(0) and sample.is_open_at(1439), "便利店 24 小时营业")
	var night = pm.get_type("night_market")
	var night_place = pm.register_place("night_market", sample.geo_id, {"name": "夜市"})
	check(night_place.is_open_at(1200), "夜市晚间营业")
	check(not night_place.is_open_at(500), "夜市白天不营业")
	check(night_place.is_open_at(60), "夜市跨夜仍在营业")

	check(pm.set_favorite(sample.id, true), "收藏场所")
	check(pm.favorites().has(sample.id), "收藏列表含该场所")


## 十二种交通齐全、字段完整；条件校验可用。
func _test_transport_modes_and_conditions() -> void:
	var tr = TransportScript.new()
	check_eq(tr.mode_count(), 12, "十二种交通方式")
	var keys: Array = tr.mode_keys()
	check_eq(keys.size(), 12, "方式键数量为 12")
	for key in keys:
		var info: Dictionary = tr.mode_info(String(key))
		check(info.has("speed_kmh") and info.has("base_fare") and info.has("per_km") and info.has("comfort"), "方式 %s 字段完整" % String(key))
		check(float(info["speed_kmh"]) > 0.0, "方式 %s 速度为正" % String(key))

	# 自驾缺证件与车辆应提示（R4.4）。
	var missing: Array = tr.missing_conditions("self_drive", [])
	check(missing.has("driver_license") and missing.has("vehicle"), "自驾缺驾照与车辆")
	check(tr.missing_conditions("self_drive", ["driver_license", "vehicle"]).is_empty(), "条件齐备无缺失")
	check(tr.required_conditions("airplane").has("passport"), "飞机需要护照")

	var trip: Dictionary = tr.estimate_trip("self_drive", {"lat": 39.9, "lon": 116.4}, {"lat": 31.2, "lon": 121.5}, {"owned": []})
	check(not trip["ok"], "条件不足时 estimate 标记失败")
	check(trip["missing"].size() == 2, "缺失两条条件")


## 真实坐标距离与耗时/费用单调。
func _test_distance_and_monotonic() -> void:
	# 北京—上海球面距离约 1067 km。
	var d: float = GeoDataScript.distance_km(39.9042, 116.4074, 31.2304, 121.4737)
	check(absf(d - 1067.0) < 60.0, "北京—上海距离合理，实际 %.1f km" % d)

	var tr = TransportScript.new()
	var origin: Dictionary = {"lat": 31.2304, "lon": 121.4737}
	var prev_minutes: float = -1.0
	var prev_cost: float = -1.0
	for dist in [10.0, 50.0, 200.0]:
		var target: Dictionary = {"lat": 31.2304 + dist / 111.0, "lon": 121.4737}
		var trip: Dictionary = tr.estimate_trip("bus", origin, target)
		check(trip["ok"], "公交出行成功")
		check(float(trip["minutes"]) > prev_minutes, "公交耗时随距离单调递增 (%.1f)" % dist)
		check(float(trip["cost"]) > prev_cost, "公交费用随距离单调递增 (%.1f)" % dist)
		prev_minutes = float(trip["minutes"])
		prev_cost = float(trip["cost"])

	# 同一距离下飞机快于步行。
	var near: Dictionary = {"lat": 31.2304 + 100.0 / 111.0, "lon": 121.4737}
	var walk: Dictionary = tr.estimate_trip("walk", origin, near)
	var plane_time: float = float(tr.estimate_trip("airplane", origin, near, {"owned": ["passport"]})["minutes"])
	check(plane_time < float(walk["minutes"]), "飞机快于步行")


## 枢纽换乘路径守恒（分段相加）、含换乘等待。
func _test_route_conservation_and_transfer() -> void:
	var tr = TransportScript.new()
	var net = tr.build_demo_network()
	check(net.has_hub("bj_south"), "枢纽网络含北京南站")

	var route: Dictionary = tr.route(net, "bj_south", "sh_pudong", 480)
	check(route["ok"], "规划出北京南站→上海浦东机场路径")
	check(int(route["segment_count"]) >= 2, "跨城路径至少两段")
	check(int(route["transfers"]) >= 1, "至少一次换乘")

	var minutes_sum: float = 0.0
	var cost_sum: float = 0.0
	var dist_sum: float = 0.0
	for seg in route["segments"]:
		minutes_sum += float(seg["minutes"])
		cost_sum += float(seg["cost"])
		dist_sum += float(seg["distance_km"])
	check_near(float(route["total_minutes"]), minutes_sum, 1e-6, "总耗时等于各段相加")
	check_near(float(route["total_cost"]), cost_sum, 1e-6, "总费用等于各段相加")
	check_near(float(route["total_distance_km"]), dist_sum, 1e-6, "总距离等于各段相加")
	check_near(float(route["arrival_minute"]), 480.0 + minutes_sum, 1e-6, "到达时刻 = 出发 + 总耗时")

	# 换乘段应包含正的换乘等待。
	var has_transfer_wait: bool = false
	for seg in route["segments"]:
		if float(seg["transfer_minutes"]) > 0.0:
			has_transfer_wait = true
	check(has_transfer_wait, "换乘段含换乘等待")

	# 未知枢纽返回失败而非崩溃。
	var bad: Dictionary = tr.route(net, "nowhere", "sh_pudong", 0)
	check(not bad["ok"], "未知枢纽规划失败")


## 混合地图 UI 壳：可实例化、缩放、居中、进入/退出 3D。
func _test_map_view_shell() -> void:
	var scene = load("res://ui/map/map_view.tscn")
	check(scene != null, "地图场景可加载")
	if scene == null:
		return
	var view = scene.instantiate()
	get_root().add_child(view)

	var geo = _make_geo(7)
	var pm = PlaceManagerScript.new()
	pm.attach_to_geo(geo, 7, 1)
	view.setup(geo, pm)

	var z0: float = view.zoom()
	view.zoom_in()
	check(view.zoom() > z0, "放大提高缩放")
	view.zoom_out()
	view.zoom_out()
	check(view.zoom() < z0, "缩小降低缩放")
	view.set_zoom(1000.0)
	check_near(view.zoom(), 8.0, 1e-6, "缩放上限被钳制")

	check(view.center_on("cn.beijing"), "以北京居中")
	var buildings: Array = geo.nodes_at_level(GeoDataScript.GeographicLevel.BUILDING)
	check(view.enter_3d(String(buildings[0])), "进入 3D 局部探索")
	check(view.is_3d_active(), "3D 状态为真")
	check(view.world_3d() != null, "3D 世界壳存在")
	view.exit_3d()
	check(not view.is_3d_active(), "退出 3D")
	check(not view.enter_3d("not.exist"), "无效建筑进入 3D 失败")

	var state: Dictionary = view.map_state()
	check(state.has("zoom") and state.has("is_3d"), "地图状态可读")
	view.queue_free()


## 深度相等（兼容 JSON 数字 float 与 int）。
func _deep_equal(a: Variant, b: Variant) -> bool:
	var ta: int = typeof(a)
	var tb: int = typeof(b)
	if ta != tb:
		if (ta == TYPE_INT or ta == TYPE_FLOAT) and (tb == TYPE_INT or tb == TYPE_FLOAT):
			return float(a) == float(b)
		return false
	if ta == TYPE_DICTIONARY:
		var da: Dictionary = a
		var db: Dictionary = b
		if da.size() != db.size():
			return false
		for key in da.keys():
			if not db.has(key) or not _deep_equal(da[key], db[key]):
				return false
		return true
	if ta == TYPE_ARRAY:
		var aa: Array = a
		var ab: Array = b
		if aa.size() != ab.size():
			return false
		for i in aa.size():
			if not _deep_equal(aa[i], ab[i]):
				return false
		return true
	return a == b
