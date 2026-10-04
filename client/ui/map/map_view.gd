extends Control
## 混合地图 UI 壳（R42.1–R42.2、R42.9；design D2「地图为 Control 叠加标记」）。
##
## 2D 可缩放的全局混合地图：以经纬度等距投影绘制国家/省/城市节点，支持缩放、平移居中、
## 标记与收藏自定义地点。抵达城市或建筑后切换到 3D 局部探索壳。
##
## 本文件只做结构与接线，不绑定美术资产；headless 下可加载并调用（_draw 不渲染）。

const GeoDataScript = preload("res://sim/geo.gd")
const PlaceManagerScript = preload("res://sim/place_manager.gd")

const MIN_ZOOM: float = 0.25
const MAX_ZOOM: float = 8.0
const ZOOM_STEP: float = 1.5

@onready var _title: Label = $Title
@onready var _map_canvas: Control = $MapCanvas
@onready var _status_label: Label = $StatusLabel
@onready var _zoom_in_button: Button = $ZoomInButton
@onready var _zoom_out_button: Button = $ZoomOutButton
@onready var _toggle_3d_button: Button = $Toggle3DButton
@onready var _local_3d: Control = $Local3D

var _geo = null
var _places = null
var _zoom: float = 1.0
var _center_lat: float = 20.0
var _center_lon: float = 0.0
var _current_geo_id: String = ""
var _is_3d: bool = false
var _markers: Array = []        # 收藏/自定义标记：{id, lat, lon, label}
var _draw_levels: Array = [GeoDataScript.GeographicLevel.COUNTRY, GeoDataScript.GeographicLevel.PROVINCE, GeoDataScript.GeographicLevel.CITY]
var _viewport: SubViewport = null
var _world_3d: Node3D = null

func _ready() -> void:
	if is_instance_valid(_zoom_in_button):
		_zoom_in_button.pressed.connect(zoom_in)
	if is_instance_valid(_zoom_out_button):
		_zoom_out_button.pressed.connect(zoom_out)
	if is_instance_valid(_toggle_3d_button):
		_toggle_3d_button.pressed.connect(_on_toggle_3d)
	_build_3d_shell()
	_refresh_status()
	queue_redraw()

## 注入地理与场所数据（由 GameState/主界面接线）。
func setup(geo, places = null) -> void:
	_geo = geo
	_places = places
	queue_redraw()
	_refresh_status()

# --- 2D 地图 ---

func set_zoom(value: float) -> float:
	_zoom = clampf(value, MIN_ZOOM, MAX_ZOOM)
	queue_redraw()
	_refresh_status()
	return _zoom

func zoom_in() -> float:
	return set_zoom(_zoom * ZOOM_STEP)

func zoom_out() -> float:
	return set_zoom(_zoom / ZOOM_STEP)

func zoom() -> float:
	return _zoom

## 以某地理节点为中心（缩放不改变底层状态，R42.10）。
func center_on(geo_id: String) -> bool:
	if _geo == null or not _geo.has_node(geo_id):
		return false
	var node = _geo.get_node(geo_id)
	_center_lat = float(node.location.get("lat", _center_lat))
	_center_lon = float(node.location.get("lon", _center_lon))
	queue_redraw()
	return true

## 标记或收藏自定义地点（R42.9）。
func mark_place(place_id: String, label: String = "") -> bool:
	if _places == null:
		return false
	var place = _places.get_place(place_id)
	if place == null:
		return false
	_places.set_favorite(place_id, true)
	_markers.append({"id": place_id, "lat": float(place.location.get("lat", 0.0)), "lon": float(place.location.get("lon", 0.0)), "label": label})
	queue_redraw()
	return true

func markers() -> Array:
	return _markers.duplicate(true)

func _project(lat: float, lon: float) -> Vector2:
	var size: Vector2 = _map_canvas.size if is_instance_valid(_map_canvas) and _map_canvas.size.x > 0.0 else Vector2(1600.0, 900.0)
	var x: float = fposmod(lon - _center_lon + 180.0, 360.0) - 180.0
	var y: float = lat - _center_lat
	var base: Vector2 = Vector2(size.x / 2.0, size.y / 2.0)
	var scale: float = _zoom * (size.y / 180.0)
	return base + Vector2(x * scale, -y * scale)

func _draw() -> void:
	if _geo == null:
		return
	for level in _draw_levels:
		for id in _geo.nodes_at_level(level):
			var node = _geo.get_node(id)
			var p: Vector2 = _project(float(node.location.get("lat", 0.0)), float(node.location.get("lon", 0.0)))
			var radius: float = 2.0 + float(level) * 1.5
			var color: Color = Color(0.9, 0.75, 0.3) if level == GeoDataScript.GeographicLevel.CITY else Color(0.6, 0.6, 0.6)
			draw_circle(p, radius, color)
	for marker in _markers:
		var mp: Vector2 = _project(float(marker["lat"]), float(marker["lon"]))
		draw_rect(Rect2(mp - Vector2(3, 3), Vector2(6, 6)), Color(0.9, 0.2, 0.2))

# --- 3D 局部探索壳 ---

func _build_3d_shell() -> void:
	if _world_3d != null:
		return
	var holder: Control = _local_3d if is_instance_valid(_local_3d) else get_node_or_null("Local3D")
	if holder == null:
		return
	_local_3d = holder
	var container := SubViewportContainer.new()
	container.name = "ViewportContainer"
	container.stretch = true
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	_viewport = SubViewport.new()
	_viewport.name = "LocalViewport"
	_viewport.size = Vector2i(1280, 720)
	_world_3d = Node3D.new()
	_world_3d.name = "LocalWorld"
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	camera.position = Vector3(0, 1.6, 4)
	_world_3d.add_child(camera)
	_viewport.add_child(_world_3d)
	container.add_child(_viewport)
	holder.add_child(container)
	holder.visible = false

## 进入某建筑的 3D 局部探索（结构接线；具体场景由内容包绑定）。
func enter_3d(building_id: String) -> bool:
	if _geo != null and not _geo.has_node(building_id):
		return false
	_build_3d_shell()
	_current_geo_id = building_id
	_is_3d = true
	if is_instance_valid(_local_3d):
		_local_3d.visible = true
	if is_instance_valid(_viewport):
		_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_refresh_status()
	return true

func exit_3d() -> void:
	_is_3d = false
	if is_instance_valid(_local_3d):
		_local_3d.visible = false
	_refresh_status()

func is_3d_active() -> bool:
	return _is_3d

func current_geo_id() -> String:
	return _current_geo_id

func world_3d() -> Node3D:
	if _world_3d == null:
		_build_3d_shell()
	return _world_3d

func _on_toggle_3d() -> void:
	if _is_3d:
		exit_3d()
	else:
		var target: String = _current_geo_id
		if target.is_empty() and _geo != null:
			var cities: Array = _geo.nodes_at_level(GeoDataScript.GeographicLevel.BUILDING)
			target = String(cities[0]) if cities.size() > 0 else ""
		if not target.is_empty():
			enter_3d(target)

# --- 状态 ---

func map_state() -> Dictionary:
	return {
		"zoom": _zoom, "center_lat": _center_lat, "center_lon": _center_lon,
		"is_3d": _is_3d, "current_geo_id": _current_geo_id,
		"marker_count": _markers.size(),
		"favorites": _places.favorites() if _places != null else [],
	}

func _refresh_status() -> void:
	if is_instance_valid(_status_label):
		_status_label.text = "3D 局部探索：%s" % _current_geo_id if _is_3d else "2D 全局地图  缩放 %.2fx" % _zoom
	if is_instance_valid(_toggle_3d_button):
		_toggle_3d_button.text = "返回地图" if _is_3d else "进入3D"
