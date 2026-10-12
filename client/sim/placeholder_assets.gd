class_name PlaceholderAssets
extends RefCounted
## 占位资产解析器（任务 23：美术资产尚未进场时，为任意内容键生成确定性占位描述）。
## 不加载真实资源；按内容键哈希稳定地映射到基础几何体与颜色，
## 使表现层在没有任何 glTF/贴图时也能构建可玩的灰盒场景。
## 真实资产到位后，只需在 Site3DManager 中注册真实场景路径覆盖占位绑定。

const PRIMITIVES: Array[String] = ["box", "sphere", "cylinder", "capsule", "prism"]

## 占位约定：所有占位资源路径带此前缀，便于打包与排查。
const PLACEHOLDER_PREFIX := "res://assets/placeholder/"

## 场所分组 → 差异化占位风格（13 组，对齐 place_bindings.GROUPS）。
## 目标：无真实资产时，13 类场所在局部 3D 视图中即可肉眼区分；真实资产到位后按约定路径替换。
## 字段：ground(地面色) / prop(道具形状) / prop_color(道具色) / props(道具数量) / scale(道具缩放)。
const GROUP_STYLES: Dictionary = {
	"residence": {"ground": Color(0.36, 0.42, 0.30), "prop": "box", "prop_color": Color(0.62, 0.45, 0.32), "props": 2, "scale": Vector3(1.4, 1.0, 1.4)},
	"dining": {"ground": Color(0.46, 0.37, 0.28), "prop": "cylinder", "prop_color": Color(0.80, 0.56, 0.30), "props": 3, "scale": Vector3(0.8, 0.6, 0.8)},
	"retail": {"ground": Color(0.50, 0.48, 0.42), "prop": "box", "prop_color": Color(0.86, 0.70, 0.34), "props": 4, "scale": Vector3(0.9, 0.9, 0.9)},
	"medical": {"ground": Color(0.86, 0.89, 0.91), "prop": "prism", "prop_color": Color(0.82, 0.26, 0.26), "props": 1, "scale": Vector3(1.6, 1.0, 1.6)},
	"education": {"ground": Color(0.60, 0.63, 0.55), "prop": "box", "prop_color": Color(0.34, 0.50, 0.76), "props": 3, "scale": Vector3(1.0, 0.8, 1.0)},
	"government": {"ground": Color(0.55, 0.55, 0.59), "prop": "cylinder", "prop_color": Color(0.62, 0.22, 0.26), "props": 4, "scale": Vector3(0.7, 1.2, 0.7)},
	"transport": {"ground": Color(0.30, 0.30, 0.34), "prop": "capsule", "prop_color": Color(0.90, 0.76, 0.20), "props": 3, "scale": Vector3(0.8, 0.7, 1.6)},
	"culture": {"ground": Color(0.42, 0.34, 0.45), "prop": "sphere", "prop_color": Color(0.56, 0.40, 0.72), "props": 2, "scale": Vector3(1.2, 1.2, 1.2)},
	"religion": {"ground": Color(0.40, 0.36, 0.44), "prop": "prism", "prop_color": Color(0.86, 0.80, 0.55), "props": 1, "scale": Vector3(1.2, 1.8, 1.2)},
	"industry": {"ground": Color(0.35, 0.34, 0.30), "prop": "box", "prop_color": Color(0.72, 0.46, 0.24), "props": 5, "scale": Vector3(1.1, 1.3, 1.1)},
	"finance": {"ground": Color(0.28, 0.32, 0.36), "prop": "cylinder", "prop_color": Color(0.82, 0.68, 0.30), "props": 4, "scale": Vector3(0.6, 1.6, 0.6)},
	"nature": {"ground": Color(0.30, 0.46, 0.28), "prop": "sphere", "prop_color": Color(0.34, 0.60, 0.32), "props": 5, "scale": Vector3(1.3, 1.3, 1.3)},
	"special": {"ground": Color(0.30, 0.26, 0.40), "prop": "prism", "prop_color": Color(0.60, 0.35, 0.82), "props": 2, "scale": Vector3(1.0, 1.6, 1.0)},
}

## 取场所分组的差异化风格；未知分组回退 special。
static func group_style(group: String) -> Dictionary:
	return GROUP_STYLES.get(group, GROUP_STYLES["special"])


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
