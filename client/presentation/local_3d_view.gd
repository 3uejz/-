class_name Local3DView
extends SubViewportContainer
## 局部 3D 视图：一个自包含的视口 + 相机 + 环境 + 太阳 + 场所表现层。
##
## 供地图面板与主界面全屏叠层复用：
##   - 自己持有 SubViewport，避免与 2D UI 的渲染顺序互相干扰；
##   - 按场所分组切换 PresentationRoot 中的占位场景；
##   - 按游戏内分钟与天气驱动天空、太阳、雾和曝光。
##
## 本类只读外部注入的表现参数，不反向修改玩法状态。

signal back_requested
signal place_shown(group: String)

const CAMERA_MIN_DISTANCE: float = 8.0
const CAMERA_MAX_DISTANCE: float = 42.0
const CAMERA_MIN_PITCH: float = 0.08
const CAMERA_MAX_PITCH: float = 1.15

var _viewport: SubViewport
var _world: Node3D
var _presentation: PresentationRoot
var _camera: Camera3D
var _sun: DirectionalLight3D
var _environment: WorldEnvironment
var _environment_resource: Environment
var _sky_material: ProceduralSkyMaterial
var _current_group: String = ""
var _camera_yaw: float = 0.35
var _camera_pitch: float = 0.34
var _camera_distance: float = 26.0
var _camera_target := Vector3(0.0, 2.2, 0.0)
var _back_button: Button
var _hint: Label
var _title: Label
var _status: Label
var _actor: Node3D
var _npc_root: MultiMeshInstance3D
var _precip: CPUParticles3D
var _weather: String = "clear"
var _ground: MeshInstance3D
var _ground_materials: Dictionary = {}
var _torso: MeshInstance3D
var _head: MeshInstance3D
var _hair: MeshInstance3D
var _arm_l: Node3D
var _arm_r: Node3D
var _leg_l: Node3D
var _leg_r: Node3D
var _walk_phase: float = 0.0
var _moving: bool = false
var _skin_color := Color(0.82, 0.66, 0.54)
var _hair_color := Color(0.15, 0.12, 0.10)
var _outfit_color := Color(0.24, 0.36, 0.50)
var _lamps: Array[OmniLight3D] = []
var _lamp_material: StandardMaterial3D
var _eye_l: MeshInstance3D
var _eye_r: MeshInstance3D
var _blink_clock: float = 0.0
var _blink_next: float = 3.2
var _idle_clock: float = 0.0
var _npc_data: Array = []
var _npc_poses: Array = []
var _npc_clock: float = 0.0


func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	_apply_precipitation(_weather, 0.0)
	visible = false
	_update_camera()


func _build() -> void:
	if _viewport != null:
		return
	_viewport = SubViewport.new()
	_viewport.name = "Viewport"
	_viewport.size = Vector2i(1280, 720)
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)

	_world = Node3D.new()
	_world.name = "World"
	_viewport.add_child(_world)

	_build_environment()
	_build_ground()
	_build_actor()
	_build_street_lamps()
	_build_npcs()
	_build_precipitation()

	_presentation = PresentationRoot.new()
	_presentation.name = "Presentation"
	_world.add_child(_presentation)
	_presentation.ensure_initialized()

	_camera = Camera3D.new()
	_camera.name = "Camera3D"
	_camera.fov = 58.0
	_camera.near = 0.1
	_camera.far = 400.0
	_camera.current = true
	_world.add_child(_camera)

	_build_overlay_controls()


func _build_environment() -> void:
	_environment = WorldEnvironment.new()
	_environment.name = "WorldEnvironment"
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	_sky_material = ProceduralSkyMaterial.new()
	var sky := Sky.new()
	sky.sky_material = _sky_material
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.05
	env.glow_enabled = true
	env.glow_intensity = 0.3
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	env.ssao_enabled = true
	env.ssao_radius = 1.1
	env.ssao_intensity = 1.8
	env.ssao_power = 1.4
	env.fog_enabled = true
	env.fog_density = 0.006
	env.fog_sky_affect = 0.25
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.05
	_environment.environment = env
	_environment_resource = env
	_world.add_child(_environment)

	_sun = DirectionalLight3D.new()
	_sun.name = "Sun"
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 80.0
	_sun.light_energy = 1.2
	_world.add_child(_sun)


## 主角：分件低多边形人形（头/发/眼/躯干/四肢/鞋），支持走姿摆动与形象参数。
## 分件结构便于后续替换为骨骼动画模型；当前不依赖外部角色资产。
func _build_actor() -> void:
	_actor = Node3D.new()
	_actor.name = "Actor"
	_actor.position = Vector3(0.0, 0.0, 2.6)
	_world.add_child(_actor)

	_torso = _add_part(_actor, "Torso", _capsule(0.23, 0.62), Vector3(0.0, 1.14, 0.0))
	_head = _add_part(_actor, "Head", _sphere(0.16), Vector3(0.0, 1.62, 0.0))
	_hair = _add_part(_actor, "Hair", _sphere(0.17), Vector3(0.0, 1.68, -0.01))
	_hair.scale = Vector3(1.02, 0.72, 1.02)
	_eye_l = _add_part(_actor, "EyeL", _sphere(0.022), Vector3(-0.058, 1.65, 0.145))
	_eye_r = _add_part(_actor, "EyeR", _sphere(0.022), Vector3(0.058, 1.65, 0.145))
	_eye_l.material_override = _flat_material(Color(0.10, 0.10, 0.12))
	_eye_r.material_override = _flat_material(Color(0.10, 0.10, 0.12))

	_arm_l = _limb_pivot(_actor, "ArmL", Vector3(-0.28, 1.40, 0.0), 0.60, 0.065)
	_arm_r = _limb_pivot(_actor, "ArmR", Vector3(0.28, 1.40, 0.0), 0.60, 0.065)
	_leg_l = _limb_pivot(_actor, "LegL", Vector3(-0.11, 0.84, 0.0), 0.80, 0.085)
	_leg_r = _limb_pivot(_actor, "LegR", Vector3(0.11, 0.84, 0.0), 0.80, 0.085)
	_add_part(_actor, "ShoeL", _box(Vector3(0.16, 0.09, 0.28)), Vector3(-0.11, 0.05, 0.04))
	_add_part(_actor, "ShoeR", _box(Vector3(0.16, 0.09, 0.28)), Vector3(0.11, 0.05, 0.04))
	set_appearance({})

## 街灯：黄昏后自动点亮，为夜间与雾雨场景提供近景暖光。
func _build_street_lamps() -> void:
	var root := Node3D.new()
	root.name = "Lamps"
	_world.add_child(root)
	_lamp_material = StandardMaterial3D.new()
	_lamp_material.albedo_color = Color(0.22, 0.20, 0.16)
	_lamp_material.emission_enabled = true
	_lamp_material.emission = Color(1.0, 0.82, 0.55)
	_lamp_material.emission_energy_multiplier = 0.2
	var positions: Array = [Vector3(-8.5, 0.0, -4.0), Vector3(8.5, 0.0, -4.0), Vector3(-8.5, 0.0, 6.0), Vector3(8.5, 0.0, 6.0), Vector3(-3.0, 0.0, -10.0), Vector3(3.0, 0.0, -10.0)]
	for i in positions.size():
		var pos: Vector3 = positions[i]
		var pole := _add_part(root, "Pole%d" % i, _capsule(0.07, 4.2), pos + Vector3(0.0, 2.1, 0.0))
		pole.material_override = _flat_material(Color(0.16, 0.17, 0.18))
		var head := _add_part(root, "Head%d" % i, _box(Vector3(0.46, 0.14, 0.46)), pos + Vector3(0.0, 4.18, 0.0))
		head.material_override = _lamp_material
		var light := OmniLight3D.new()
		light.name = "Light%d" % i
		light.position = pos + Vector3(0.0, 3.95, 0.0)
		light.omni_range = 12.0
		light.omni_attenuation = 1.1
		light.light_color = Color(1.0, 0.86, 0.64)
		light.light_energy = 0.0
		light.shadow_enabled = false
		root.add_child(light)
		_lamps.append(light)

func _add_part(parent: Node3D, part_name: String, mesh: Mesh, pos: Vector3) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = part_name
	part.mesh = mesh
	part.position = pos
	part.material_override = _flat_material(Color(0.72, 0.66, 0.58))
	parent.add_child(part)
	return part

## 四肢枢轴：枢轴在肩/髋，网格向 -Y 偏移半长，旋转枢轴即摆动。
func _limb_pivot(parent: Node3D, pivot_name: String, pos: Vector3, length: float, radius: float) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = pivot_name
	pivot.position = pos
	parent.add_child(pivot)
	var mesh := _add_part(pivot, "Mesh", _capsule(radius, length), Vector3(0.0, -length * 0.5, 0.0))
	mesh.material_override = _flat_material(Color(0.24, 0.36, 0.50))
	return pivot

func _capsule(radius: float, height: float) -> CapsuleMesh:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	return mesh

func _sphere(radius: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	return mesh

func _box(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh

## 接入 D6 形象档案：身高缩放、BMI 体宽、肤色/发色/服装色。
## 未提供的字段使用中性默认，保证开档前也能显示。
func set_appearance(profile: Dictionary) -> void:
	_build_actor_parts_guard()
	var height_cm: float = float(profile.get("height_cm", 175.0))
	var bmi: float = float(profile.get("bmi", 22.0))
	var height_scale: float = clampf(height_cm / 175.0, 0.82, 1.18)
	var girth: float = clampf(1.0 + (bmi - 22.0) * 0.018, 0.85, 1.2)
	var gender: String = String(profile.get("gender", "male"))
	var seed_text: String = "%s|%s" % [gender, str(profile.get("appearance_score", 50.0))]
	var seed_value: int = int(seed_text.hash())
	var skin_palette: Array = [Color(0.91, 0.76, 0.64), Color(0.82, 0.65, 0.51), Color(0.70, 0.53, 0.40), Color(0.55, 0.40, 0.30), Color(0.42, 0.30, 0.23)]
	var hair_palette: Array = [Color(0.12, 0.10, 0.09), Color(0.24, 0.16, 0.10), Color(0.42, 0.28, 0.16), Color(0.62, 0.50, 0.34), Color(0.30, 0.30, 0.32)]
	var skin: Color = skin_palette[absi(seed_value) % skin_palette.size()]
	var hair: Color = hair_palette[absi(seed_value / 7) % hair_palette.size()]
	var outfit_hue: float = 0.56 if gender == "male" else 0.02
	var outfit: Color = Color.from_hsv(outfit_hue, 0.42, 0.46)
	_actor.scale = Vector3(1.0, height_scale, 1.0)
	_actor.set_meta("girth", girth)
	_skin_color = skin
	_hair_color = hair
	_outfit_color = outfit
	if _head != null:
		_head.material_override = _flat_material(skin)
	if _hair != null:
		_hair.material_override = _flat_material(hair)
		var long_hair: bool = gender == "female"
		_hair.scale = Vector3(1.04, 1.05 if long_hair else 0.72, 1.04)
		_hair.position.y = 1.64 if long_hair else 1.68
	if _torso != null:
		_torso.scale = Vector3(girth, 1.0, girth * 0.78)
		_torso.material_override = _flat_material(outfit)
	for pivot in [_arm_l, _arm_r, _leg_l, _leg_r]:
		if pivot == null:
			continue
		var mesh: MeshInstance3D = pivot.get_node_or_null("Mesh")
		if mesh != null:
			var is_arm: bool = pivot.name.begins_with("Arm")
			mesh.material_override = _flat_material(outfit if is_arm else Color(0.18, 0.20, 0.26))
	_actor.visible = true

func _build_actor_parts_guard() -> void:
	if _actor == null:
		_build_actor()

## NPC 简化表现：MultiMesh 一次绘制多名路人，远景自动隐藏。
func _build_npcs() -> void:
	_npc_root = MultiMeshInstance3D.new()
	_npc_root.name = "NPCs"
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.21
	mesh.height = 1.42
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = 24
	_npc_data.clear()
	for i in 24:
		var angle: float = float(i) * TAU / 24.0 + float(i % 5) * 0.17
		var radius: float = 3.2 + float((i * 7) % 9)
		var center := Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		var base_scale: float = 0.92 + float(i % 4) * 0.04
		var height: float = 0.71 * base_scale + float(i % 3) * 0.03
		var basis := Basis().scaled(Vector3.ONE * base_scale)
		mm.set_instance_transform(i, Transform3D(basis, center + Vector3(0.0, height, 0.0)))
		var tone: float = 0.42 + float((i * 13) % 20) * 0.012
		mm.set_instance_color(i, Color(tone, tone * 0.96 + float(i % 3) * 0.02, tone * 0.9))
		_npc_data.append({
			"center": center, "y": height, "scale": base_scale,
			"phase": float(i) * 0.7, "speed": 0.35 + float(i % 5) * 0.09,
			"radius": 0.18 + float(i % 4) * 0.13,
		})
	_npc_root.multimesh = mm
	var npc_material := _flat_material(Color(0.9, 0.9, 0.9))
	npc_material.vertex_color_use_as_albedo = true
	_npc_root.material_override = npc_material
	_npc_root.visibility_range_end = 70.0
	_world.add_child(_npc_root)

## 降水粒子：雨丝/雪花跟随相机，按天气开关。
func _build_precipitation() -> void:
	_precip = CPUParticles3D.new()
	_precip.name = "Precipitation"
	_precip.emitting = false
	_precip.amount = 420
	_precip.lifetime = 1.8
	_precip.local_coords = false
	_precip.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_precip.emission_box_extents = Vector3(16.0, 4.0, 16.0)
	_precip.direction = Vector3(0.0, -1.0, 0.0)
	_precip.spread = 4.0
	_precip.gravity = Vector3(0.0, -12.0, 0.0)
	_precip.initial_velocity_min = 9.0
	_precip.initial_velocity_max = 14.0
	var drop := BoxMesh.new()
	drop.size = Vector3(0.012, 0.34, 0.012)
	_precip.mesh = drop
	var mat := _flat_material(Color(0.72, 0.80, 0.92))
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color.a = 0.55
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_precip.material_override = mat
	_precip.position = Vector3(0.0, 12.0, 0.0)
	_world.add_child(_precip)

func _flat_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.72
	return material

## 一块远景地面，避免模型地面瓦片之外直接露出天空。
func _build_ground() -> void:
	_ground = MeshInstance3D.new()
	_ground.name = "Ground"
	var plane := PlaneMesh.new()
	plane.size = Vector2(240.0, 240.0)
	_ground.mesh = plane
	_ground.material_override = _ground_material("asphalt")
	_ground.position.y = -0.06
	_world.add_child(_ground)

## 地面材质：优先使用 CC0 贴图；未导入时回退程序化噪声，保证任何环境可运行。
func _ground_material(kind: String) -> StandardMaterial3D:
	if _ground_materials.has(kind):
		return _ground_materials[kind]
	var material := StandardMaterial3D.new()
	material.roughness = 0.94
	if kind == "grass":
		material.albedo_color = Color(0.42, 0.47, 0.34)
	else:
		material.albedo_color = Color(0.40, 0.41, 0.40)
	var diffuse_path: String = "res://assets/textures/%s_diff_1k.jpg" % kind
	var normal_path: String = "res://assets/textures/%s_nor_1k.jpg" % kind
	if ResourceLoader.exists(diffuse_path):
		material.albedo_texture = load(diffuse_path)
	else:
		var noise := FastNoiseLite.new()
		noise.frequency = 0.045
		noise.fractal_octaves = 4
		var texture := NoiseTexture2D.new()
		texture.width = 256
		texture.height = 256
		texture.seamless = true
		texture.noise = noise
		material.albedo_texture = texture
	if ResourceLoader.exists(normal_path):
		material.normal_enabled = true
		material.normal_texture = load(normal_path)
		material.normal_scale = 0.7
	material.uv1_scale = Vector3(36.0, 36.0, 1.0)
	_ground_materials[kind] = material
	return material

func _apply_ground(group: String) -> void:
	if _ground == null:
		return
	var kind: String = "grass" if group in ["nature", "residence"] else "asphalt"
	_ground.material_override = _ground_material(kind)


func _build_overlay_controls() -> void:
	_back_button = Button.new()
	_back_button.name = "BackButton"
	_back_button.text = "返回地图"
	_back_button.position = Vector2(16.0, 16.0)
	_back_button.size = Vector2(104.0, 34.0)
	_back_button.pressed.connect(func() -> void: back_requested.emit())
	add_child(_back_button)

	_hint = Label.new()
	_hint.name = "Hint"
	_hint.text = "WASD 移动　左键拖动旋转　滚轮缩放　Esc 返回"
	_hint.position = Vector2(16.0, 56.0)
	_hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	_hint.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.65))
	_hint.add_theme_constant_override("shadow_offset_x", 1)
	_hint.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_hint)

	_title = Label.new()
	_title.name = "PlaceTitle"
	_title.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_title.offset_top = 18.0
	_title.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 22)
	_title.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	_title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	_title.add_theme_constant_override("shadow_offset_x", 1)
	_title.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_title)

	_status = Label.new()
	_status.name = "Status"
	_status.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_status.offset_left = 16.0
	_status.offset_bottom = -14.0
	_status.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_status.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	_status.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	_status.add_theme_constant_override("shadow_offset_x", 1)
	_status.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_status)


## 切换到指定场所分组；分组与 PlaceBindings.GROUPS 对齐。
func show_place(group: String, title: String = "") -> bool:
	_build()
	var key: String = group if PlaceBindings.has_group(group) else "special"
	if not _presentation.show_place(key):
		return false
	_current_group = key
	_apply_ground(key)
	if title != "":
		set_place_title(title)
	visible = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_update_camera()
	place_shown.emit(key)
	return true


## 3D 叠层顶部显示场所名。
func set_place_title(title: String) -> void:
	_build()
	if _title != null:
		_title.text = title

## 3D 叠层底部显示时刻与天气。
func set_status_text(text: String) -> void:
	_build()
	if _status != null:
		_status.text = text

func hide_world() -> void:
	visible = false
	if _viewport != null:
		_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED


func current_group() -> String:
	return _current_group


func world_3d() -> Node3D:
	_build()
	return _world


func camera() -> Camera3D:
	_build()
	return _camera


## 按游戏内分钟与天气更新天空、太阳、雾和曝光。
## condition 使用 baseline 的英文状态键（clear/overcast/light_rain/fog...）。
func set_atmosphere(minute_of_day: int, condition: String = "clear", precipitation_mm: float = 0.0) -> void:
	_build()
	var minute: int = posmod(minute_of_day, 1440)
	var daylight: float = _daylight_at(minute)
	var day_t: float = clampf((float(minute) - 300.0) / 840.0, 0.0, 1.0)
	var altitude: float = sin(day_t * PI) * 62.0
	var azimuth: float = 90.0 + day_t * 180.0
	_sun.rotation_degrees = Vector3(-(90.0 - altitude), azimuth, 0.0)
	_sun.light_energy = 0.04 + daylight * 1.25
	_sun.light_color = Color(1.0, 0.84, 0.64).lerp(Color(1.0, 0.97, 0.92), clampf(daylight * 1.6, 0.0, 1.0))

	_weather = condition
	_apply_precipitation(condition, precipitation_mm)
	var weather: Dictionary = _weather_tint(condition, precipitation_mm)
	var night_top := Color(0.018, 0.026, 0.062)
	var night_horizon := Color(0.055, 0.075, 0.14)
	var day_top: Color = (Color(0.22, 0.43, 0.76) as Color).lerp(weather["top"], weather["mix"])
	var day_horizon: Color = (Color(0.72, 0.83, 0.94) as Color).lerp(weather["horizon"], weather["mix"])
	_sky_material.sky_top_color = night_top.lerp(day_top, clampf(daylight * 1.35, 0.0, 1.0))
	_sky_material.sky_horizon_color = night_horizon.lerp(day_horizon, clampf(daylight * 1.45, 0.0, 1.0))
	_sky_material.ground_horizon_color = _sky_material.sky_horizon_color
	_sky_material.ground_bottom_color = night_top.lerp(Color(0.16, 0.17, 0.15), daylight)
	_sky_material.sun_angle_max = 24.0
	_sky_material.sky_energy_multiplier = 0.25 + daylight * 0.9

	var fog_color: Color = _sky_material.sky_horizon_color.lerp(Color(0.58, 0.62, 0.66), 0.35)
	_environment_resource.fog_light_color = fog_color
	_environment_resource.fog_density = float(weather["fog"])
	_environment_resource.ambient_light_energy = 0.18 + daylight * 0.8
	_environment_resource.tonemap_exposure = 0.85 + daylight * 0.35
	var night: float = 1.0 - clampf(daylight * 1.5, 0.0, 1.0)
	var lamp_energy: float = night * (1.15 + weather["mix"] * 0.8)
	for lamp in _lamps:
		lamp.light_energy = lamp_energy
	if _lamp_material != null:
		_lamp_material.emission_energy_multiplier = 0.15 + night * 2.6


func _process(delta: float) -> void:
	if not visible:
		return
	if _actor != null:
		var move := Vector3.ZERO
		if Input.is_key_pressed(KEY_W):
			move.z -= 1.0
		if Input.is_key_pressed(KEY_S):
			move.z += 1.0
		if Input.is_key_pressed(KEY_A):
			move.x -= 1.0
		if Input.is_key_pressed(KEY_D):
			move.x += 1.0
		_moving = move != Vector3.ZERO
		if _moving:
			move = move.normalized()
			var forward := Vector3(-sin(_camera_yaw), 0.0, -cos(_camera_yaw))
			var right := Vector3(cos(_camera_yaw), 0.0, -sin(_camera_yaw))
			var step: Vector3 = (forward * move.z + right * move.x) * 3.4 * delta
			_actor.position += step
			var flat := Vector2(_actor.position.x, _actor.position.z)
			if flat.length() > 14.0:
				flat = flat.normalized() * 14.0
				_actor.position.x = flat.x
				_actor.position.z = flat.y
			_actor.rotation.y = atan2(step.x, step.z)
			_walk_phase += delta * 9.0
			_actor.position.y = absf(sin(_walk_phase)) * 0.035
		else:
			_walk_phase = lerpf(_walk_phase, 0.0, minf(1.0, delta * 8.0))
			_actor.position.y = sin(float(Time.get_ticks_msec()) * 0.002) * 0.012
		var swing: float = sin(_walk_phase) * 0.55 if _moving else 0.0
		if _leg_l != null:
			_leg_l.rotation.x = swing
		if _leg_r != null:
			_leg_r.rotation.x = -swing
		if _arm_l != null:
			_arm_l.rotation.x = -swing * 0.8
		if _arm_r != null:
			_arm_r.rotation.x = swing * 0.8
		_idle_clock += delta
		if not _moving:
			var idle_sway: float = sin(_idle_clock * 0.9) * 0.035
			if _arm_l != null:
				_arm_l.rotation.x = idle_sway
			if _arm_r != null:
				_arm_r.rotation.x = -idle_sway
		_blink_clock += delta
		if _blink_clock >= _blink_next:
			_blink_clock = 0.0
			_blink_next = 2.4 + fmod(absf(sin(float(Time.get_ticks_msec()) * 0.0007)), 1.0) * 3.6
		var blink_scale: float = 0.12 if _blink_clock < 0.12 else 1.0
		if _eye_l != null:
			_eye_l.scale.y = blink_scale
		if _eye_r != null:
			_eye_r.scale.y = blink_scale
		_camera_target = Vector3(_actor.position.x, 2.2, _actor.position.z)
		_update_camera()
	if _npc_root != null and _npc_root.multimesh != null:
		_npc_clock += delta
		_update_npcs()
	if _precip != null and _precip.emitting and _camera != null:
		_precip.position = Vector3(_camera.position.x, 12.0, _camera.position.z)


## 路人微动：围绕各自站位小幅踱步、轻微起伏，避免整条街像静物。
func _update_npcs() -> void:
	var mm: MultiMesh = _npc_root.multimesh
	_npc_poses.clear()
	for i in mini(_npc_data.size(), mm.instance_count):
		var data: Dictionary = _npc_data[i]
		var phase: float = float(data["phase"]) + _npc_clock * float(data["speed"])
		var center: Vector3 = data["center"]
		var drift_r: float = float(data["radius"])
		var pos := Vector3(
			center.x + cos(phase) * drift_r,
			float(data["y"]) + sin(phase * 2.0) * 0.03,
			center.z + sin(phase) * drift_r
		)
		var yaw: float = atan2(-sin(phase), cos(phase))
		var basis := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * float(data["scale"]))
		mm.set_instance_transform(i, Transform3D(basis, pos))
		_npc_poses.append(pos)

## 当前路人位置快照（供无人渲染的测试核验微动）。
func npc_positions() -> Array:
	return _npc_poses.duplicate()

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_ESCAPE:
		back_requested.emit()
		accept_event()

## 按天气切换雨雪粒子；无降水天气关闭发射。
func _apply_precipitation(condition: String, precipitation_mm: float) -> void:
	if _precip == null:
		return
	var snow: bool = condition in ["light_snow", "moderate_snow", "heavy_snow", "snowstorm", "hail"]
	var rain: bool = condition in ["light_rain", "moderate_rain", "heavy_rain", "rainstorm", "thunderstorm", "freezing_rain"]
	if not (snow or rain):
		_precip.emitting = false
		return
	if snow:
		var flake := SphereMesh.new()
		flake.radius = 0.035
		flake.height = 0.07
		_precip.mesh = flake
		_precip.amount = 320
		_precip.lifetime = 4.5
		_precip.gravity = Vector3(0.0, -2.2, 0.0)
		_precip.initial_velocity_min = 0.6
		_precip.initial_velocity_max = 1.4
		_precip.spread = 18.0
		_set_particle_color(Color(0.96, 0.97, 1.0, 0.9))
	else:
		var drop := BoxMesh.new()
		drop.size = Vector3(0.012, 0.34, 0.012)
		_precip.mesh = drop
		_precip.amount = 420
		_precip.lifetime = 1.6
		_precip.gravity = Vector3(0.0, -12.0, 0.0)
		_precip.initial_velocity_min = 9.0
		_precip.initial_velocity_max = 15.0 + float(precipitation_mm) * 0.2
		_precip.spread = 4.0
		_set_particle_color(Color(0.72, 0.80, 0.92, 0.55))
	_precip.emitting = false
	if _precip.is_inside_tree():
		_precip.emitting = true

func _set_particle_color(color: Color) -> void:
	var material := _precip.material_override as StandardMaterial3D
	if material == null:
		material = StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_precip.material_override = material
	material.albedo_color = color

func _daylight_at(minute: int) -> float:
	if minute < 300 or minute > 1140:
		return 0.0
	return clampf(sin(float(minute - 300) / 840.0 * PI), 0.0, 1.0)


## 返回天空色调、雾密度与混合权重；雨雪雾霾会比晴天更灰、更浑浊。
func _weather_tint(condition: String, precipitation_mm: float) -> Dictionary:
	var family := condition
	var top := Color(0.30, 0.43, 0.58)
	var horizon := Color(0.66, 0.72, 0.78)
	var fog: float = 0.006
	var mix: float = 0.2
	match family:
		"overcast":
			mix = 0.7
			fog = 0.012
		"light_rain", "moderate_rain", "heavy_rain", "rainstorm", "thunderstorm", "freezing_rain":
			mix = 0.85
			fog = 0.018 + float(precipitation_mm) * 0.0015
		"light_snow", "moderate_snow", "heavy_snow", "snowstorm", "hail":
			top = Color(0.62, 0.67, 0.74)
			horizon = Color(0.82, 0.85, 0.88)
			mix = 0.85
			fog = 0.022
		"fog":
			top = Color(0.55, 0.58, 0.60)
			horizon = Color(0.68, 0.70, 0.71)
			mix = 0.9
			fog = 0.045
		"haze", "dust":
			top = Color(0.58, 0.53, 0.43)
			horizon = Color(0.72, 0.68, 0.58)
			mix = 0.85
			fog = 0.03
		"partly_cloudy":
			mix = 0.35
			fog = 0.008
		_:
			top = Color(0.24, 0.48, 0.82)
			horizon = Color(0.74, 0.86, 0.96)
			mix = 0.08
			fog = 0.005
	return {"top": top, "horizon": horizon, "fog": fog, "mix": mix}


func _update_camera() -> void:
	if _camera == null:
		return
	var horizontal: float = cos(_camera_pitch) * _camera_distance
	var offset := Vector3(
		sin(_camera_yaw) * horizontal,
		sin(_camera_pitch) * _camera_distance,
		cos(_camera_yaw) * horizontal
	)
	_camera.position = _camera_target + offset
	if _camera.is_inside_tree():
		_camera.look_at(_camera_target, Vector3.UP)
	else:
		_camera.look_at_from_position(_camera.position, _camera_target, Vector3.UP)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		var motion := event as InputEventMouseMotion
		_camera_yaw -= motion.relative.x * 0.006
		_camera_pitch = clampf(_camera_pitch + motion.relative.y * 0.005, CAMERA_MIN_PITCH, CAMERA_MAX_PITCH)
		_update_camera()
		accept_event()
	elif event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if not button.pressed:
			return
		if button.button_index == MOUSE_BUTTON_WHEEL_UP:
			_camera_distance = clampf(_camera_distance * 0.9, CAMERA_MIN_DISTANCE, CAMERA_MAX_DISTANCE)
			_update_camera()
			accept_event()
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_camera_distance = clampf(_camera_distance / 0.9, CAMERA_MIN_DISTANCE, CAMERA_MAX_DISTANCE)
			_update_camera()
			accept_event()
