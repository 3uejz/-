class_name PlaceholderAssets
extends RefCounted
## 占位资产解析器（任务 23：美术资产尚未进场时，为任意内容键生成确定性占位描述）。
## 不加载真实资源；按内容键哈希稳定地映射到基础几何体与颜色，
## 使表现层在没有任何 glTF/贴图时也能构建可玩的灰盒场景。
## 真实资产到位后，只需在 Site3DManager 中注册真实场景路径覆盖占位绑定。

const PRIMITIVES: Array[String] = ["box", "sphere", "cylinder", "capsule", "prism"]

## 占位约定：所有占位资源路径带此前缀，便于打包与排查。
const PLACEHOLDER_PREFIX := "res://assets/placeholder/"


static func primitive_for(key: String) -> String:
	var h: int = absi(key.hash())
	return PRIMITIVES[h % PRIMITIVES.size()]


static func color_for(key: String) -> Color:
	var h: int = absi(key.hash())
	var hue: float = float(h % 360) / 360.0
	var sat: float = 0.30 + float((h / 360) % 30) / 100.0
	var val: float = 0.75 + float((h / 10800) % 20) / 100.0
	return Color.from_hsv(hue, clampf(sat, 0.0, 1.0), clampf(val, 0.0, 1.0))


## 生成占位模型描述（供表现层构建灰盒网格）。
static func resolve(key: String, kind: String = "model") -> Dictionary:
	return {
		"key": key,
		"kind": kind,
		"placeholder": true,
		"primitive": primitive_for(key),
		"color": color_for(key),
		"path": placeholder_path(key),
	}


## 生成占位场景描述（地点 3D 场景绑定用）。
static func scene_descriptor(location_key: String, kind: String = "site", radius: float = 6.0) -> Dictionary:
	return {
		"key": location_key,
		"kind": kind,
		"placeholder": true,
		"primitive": primitive_for(location_key),
		"color": color_for(location_key),
		"path": placeholder_path(location_key),
		"radius": radius,
	}


static func placeholder_path(key: String) -> String:
	return PLACEHOLDER_PREFIX + key.replace(".", "_") + ".tscn"


static func is_placeholder_path(path: String) -> bool:
	return path.begins_with(PLACEHOLDER_PREFIX)
