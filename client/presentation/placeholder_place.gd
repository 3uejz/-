extends Node3D
## 占位场所场景（任务 23 / 美术「程序化占位 + 资产契约」）。
## 依据场所分组程序化生成差异化灰盒，使 13 类场所在局部 3D 视图中可肉眼区分。
##
## 替换契约（零改代码）：
##   把真实场景放到 res://presentation/scenes/places/<group>.tscn，
##   place_bindings.scene_for() 会优先命中该约定路径，无需改动任何代码即可替换占位。
## 未提供真实资产时，由本脚本按 PlaceholderAssets.GROUP_STYLES 生成占位。

const PlaceholderAssetsScript = preload("res://sim/placeholder_assets.gd")

## 当前场所分组（由 PlaceSceneManager 在实例化后注入）。
var place_group: String = ""

## 由场景管理器注入分组并重建灰盒。
func set_place_group(group: String) -> void:
	place_group = group
	_apply_style()

func _ready() -> void:
	if place_group != "":
		_apply_style()

func _apply_style() -> void:
	var style: Dictionary = PlaceholderAssetsScript.group_style(place_group)
	var ground := get_node_or_null("Ground") as MeshInstance3D
	if ground != null:
		ground.material_override = _material(style.get("ground", Color(0.5, 0.5, 0.5)))
	var props_root := get_node_or_null("Props")
	if props_root == null:
		props_root = Node3D.new()
		props_root.name = "Props"
		add_child(props_root)
	for child in props_root.get_children():
		props_root.remove_child(child)
		child.free()
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
