extends Control
## 混合地图 UI 壳（R42.1–R42.2、R42.9；design D2「地图为 Control 叠加标记」）。
##
## 2D 可缩放的全局混合地图：以经纬度等距投影绘制国家/省/城市节点，支持缩放、平移居中、
## 标记与收藏自定义地点。抵达城市或建筑后切换到 3D 局部探索壳。
##
## 本文件只做结构与接线，不绑定美术资产；headless 下可加载并调用（_draw 不渲染）。

const GeoDataScript = preload("res://sim/geo.gd")
const PlaceManagerScript = preload("res://sim/place_manager.gd")
const ThemeTokensScript = preload("res://ui/theme/theme_tokens.gd")
const Local3DViewScript = preload("res://presentation/local_3d_view.gd")

signal explore_requested(geo_id: String)
signal explore_exited

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
var _theme_scheme: String = "dark"
var _theme_variant: String = "default"
var _draw_levels: Array = [GeoDataScript.GeographicLevel.COUNTRY, GeoDataScript.GeographicLevel.PROVINCE, GeoDataScript.GeographicLevel.CITY]
var _world_3d: Node3D = null
var _local_view = null
var _local_3d_enabled: bool = true
var _atmosphere: Dictionary = {}

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
	if _places == null and _geo != null:
		_places = PlaceManagerScript.new()
		_places.attach_to_geo(_geo, 0, 1)
	queue_redraw()
	_refresh_status()

## 主界面全屏 3D 叠层接管时关闭内嵌小视口，避免重复渲染。
func set_local_3d_enabled(enabled: bool) -> void:
	_local_3d_enabled = enabled

## 注入当前游戏内时刻与天气；内嵌 3D 视口据此更新光照。
func set_atmosphere(minute_of_day: int, condition: String = "clear", precipitation_mm: float = 0.0, status_text: String = "") -> void:
	_atmosphere = {
		"minute_of_day": minute_of_day,
		"condition": condition,
		"precipitation_mm": precipitation_mm,
		"status_text": status_text,
	}
	if _local_view != null:
		_local_view.set_atmosphere(minute_of_day, condition, precipitation_mm)
		_local_view.set_status_text(status_text)

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
			var palette: Dictionary = ThemeTokensScript.colors(_theme_scheme, _theme_variant)
			var color: Color = palette["color.accent"] if level == GeoDataScript.GeographicLevel.CITY else palette["color.text.secondary"]
			draw_circle(p, radius, color)
	for marker in _markers:
		var mp: Vector2 = _project(float(marker["lat"]), float(marker["lon"]))
		draw_rect(Rect2(mp - Vector2(3, 3), Vector2(6, 6)), ThemeTokensScript.colors(_theme_scheme, _theme_variant)["color.state.danger"])

# --- 3D 局部探索壳 ---

func _build_3d_shell() -> void:
	if _local_view != null:
		return
	var holder: Control = _local_3d if is_instance_valid(_local_3d) else get_node_or_null("Local3D")
	if holder == null:
		return
	_local_3d = holder
	_local_view = Local3DViewScript.new()
	_local_view.name = "Local3DView"
	_local_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_local_view.back_requested.connect(exit_3d)
	holder.add_child(_local_view)
	_world_3d = _local_view.world_3d()
	holder.visible = false

## 进入某建筑的 3D 局部探索（结构接线；具体场景由内容包绑定）。
func enter_3d(building_id: String) -> bool:
	if _geo != null and not _geo.has_node(building_id):
		return false
	_current_geo_id = building_id
	_is_3d = true
	if _local_3d_enabled:
		_build_3d_shell()
		if _local_view != null:
			_local_view.show_place(place_group_for(building_id), place_title_for(building_id))
			if not _atmosphere.is_empty():
				_local_view.set_atmosphere(
					int(_atmosphere.get("minute_of_day", 720)),
					String(_atmosphere.get("condition", "clear")),
					float(_atmosphere.get("precipitation_mm", 0.0)))
		if is_instance_valid(_local_3d):
			_local_3d.visible = true
	explore_requested.emit(building_id)
	_refresh_status()
	return true

func exit_3d() -> void:
	_is_3d = false
	if is_instance_valid(_local_3d):
		_local_3d.visible = false
	if _local_view != null:
		_local_view.hide_world()
	explore_exited.emit()
	_refresh_status()

func is_3d_active() -> bool:
	return _is_3d

func current_geo_id() -> String:
	return _current_geo_id

func world_3d() -> Node3D:
	if _local_view == null:
		_build_3d_shell()
	return _world_3d

## 当前建筑对应的 3D 场所分组；无场所数据时回退 special。
func place_group_for(geo_id: String) -> String:
	if _places != null:
		for place in _places.places_in_geo(geo_id):
			return PlaceBindings.group_for_category(String(place.category))
	return "special"

## 建筑内第一个场所的显示名。
func place_title_for(geo_id: String) -> String:
	if _places != null:
		for place in _places.places_in_geo(geo_id):
			return String(place.name)
	return ""

func current_place_group() -> String:
	return place_group_for(_current_geo_id) if _current_geo_id != "" else ""

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
