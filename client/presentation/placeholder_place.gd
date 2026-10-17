extends Node3D
## 场所场景（任务 23 / 美术「程序化模型 + 资产契约」）。
## 优先加载 meshgen 生成的 <group>.glb，使 13 类场所在局部 3D 视图中可肉眼区分；
## 模型缺失或未导入时，按 PlaceholderAssets.GROUP_STYLES 回退程序化灰盒。
##
## 替换契约（零改代码）：
##   把真实场景放到 res://presentation/scenes/places/<group>.tscn，
##   place_bindings.scene_for() 会优先命中该约定路径，无需改动任何代码即可替换本场景。
##   真实模型按 res://assets/models/place_groups/<group>.glb 同名覆盖即可替换生成模型。

const PlaceholderAssetsScript = preload("res://sim/placeholder_assets.gd")

## 程序化生成的场所模型约定目录（meshgen 产物，按 <group>.glb 命名）。
const MODEL_DIR := "res://assets/models/place_groups/"

## 当前场所分组（由 PlaceSceneManager 在实例化后注入）。
var place_group: String = ""

## 是否优先使用生成的 GLB 模型；关闭时回退程序化灰盒（测试与降级用）。
var model_enabled: bool = true

## 由场景管理器注入分组并重建模型/灰盒。
func set_place_group(group: String) -> void:
	place_group = group
	_apply_style()

func _ready() -> void:
	if place_group != "":
		_apply_style()

## 当前分组对应的模型路径；资源未导入或不存在时返回空串。
func model_path() -> String:
	if place_group == "":
		return ""
	var path: String = MODEL_DIR + place_group + ".glb"
	if ResourceLoader.exists(path):
		return path
	return ""

## 是否已加载生成的模型（而非回退灰盒）。
func using_model_assets() -> bool:
	return get_node_or_null("Model") != null

func _apply_style() -> void:
	_clear_model()
	_clear_props()
	var path: String = model_path() if model_enabled else ""
	if path != "":
		var packed := load(path) as PackedScene
		if packed != null:
			var model: Node3D = packed.instantiate()
			model.name = "Model"
			add_child(model)
			# GLB 自带地面瓦片，隐藏场景灰盒地面避免 z-fighting。
			var ground := get_node_or_null("Ground") as MeshInstance3D
			if ground != null:
				ground.visible = false
			return
	_apply_procedural_style()

func _clear_model() -> void:
	var model := get_node_or_null("Model")
	if model != null:
		remove_child(model)
		model.queue_free()
	var ground := get_node_or_null("Ground") as MeshInstance3D
	if ground != null:
		ground.visible = true

func _clear_props() -> void:
	var props_root := get_node_or_null("Props")
	if props_root == null:
		return
	for child in props_root.get_children():
		props_root.remove_child(child)
		child.free()

func _apply_procedural_style() -> void:
	var style: Dictionary = PlaceholderAssetsScript.group_style(place_group)
	var ground := get_node_or_null("Ground") as MeshInstance3D
	if ground != null:
		ground.material_override = _material(style.get("ground", Color(0.5, 0.5, 0.5)))
	var props_root := get_node_or_null("Props")
	if props_root == null:
		props_root = Node3D.new()
		props_root.name = "Props"
		add_child(props_root)
	_clear_props()
	var count: int = int(style.get("props", 1))
	var shape: String = String(style.get("prop", "box"))
	var color: Color = style.get("prop_color", Color(0.7, 0.7, 0.7))
	var scale: Vector3 = style.get("scale", Vector3.ONE)
	for i in count:
		var prop := MeshInstance3D.new()
		prop.name = "Prop%d" % i
		prop.mesh = _mesh(shape)
		prop.material_override = _material(color)
		prop.transform = Transform3D(Basis().scaled(scale), _prop_offset(i, count))
		props_root.add_child(prop)

func _mesh(shape: String) -> Mesh:
	match shape:
		"sphere":
			return SphereMesh.new()
		"cylinder":
			return CylinderMesh.new()
		"capsule":
			return CapsuleMesh.new()
		"prism":
			return PrismMesh.new()
		_:
			return BoxMesh.new()

func _material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	return mat

## 道具沿横向一字排开，居中对称。
func _prop_offset(index: int, count: int) -> Vector3:
	var spacing := 1.6
	var x := (float(index) - float(count - 1) * 0.5) * spacing
	return Vector3(x, 0.5, 0.0)
