class_name PlaceBindings
extends RefCounted
## 地点 3D 场景绑定：按场所分组映射到场景资源。
## 首发以占位场景接通管线，真实资产按分组逐一替换，接口不变（R36.7、R36.11）。

const PLACEHOLDER := "res://presentation/scenes/placeholder_place.tscn"

## 真实资产约定目录：把 <group>.tscn 放入此处即可自动替换占位，无需改动代码。
const PLACES_DIR := "res://presentation/scenes/places/"

## 场所分组（对齐 content-catalog §1 的场所类型分组）。
const GROUPS: Array = [
	"residence", "dining", "retail", "medical", "education", "government",
	"transport", "culture", "religion", "industry", "finance", "nature", "special",
]

const PLACE_GROUPS: Dictionary = {
	"residence": PLACEHOLDER,
	"dining": PLACEHOLDER,
	"retail": PLACEHOLDER,
	"medical": PLACEHOLDER,
	"education": PLACEHOLDER,
	"government": PLACEHOLDER,
	"transport": PLACEHOLDER,
	"culture": PLACEHOLDER,
	"religion": PLACEHOLDER,
	"industry": PLACEHOLDER,
	"finance": PLACEHOLDER,
	"nature": PLACEHOLDER,
	"special": PLACEHOLDER,
}


static func scene_for(group: String) -> String:
	# 优先命中约定路径的真实资产；缺失时回退差异化占位场景。
	var convention: String = PLACES_DIR + group + ".tscn"
	if ResourceLoader.exists(convention):
		return convention
	return str(PLACE_GROUPS.get(group, PLACEHOLDER))


static func has_group(group: String) -> bool:
	return PLACE_GROUPS.has(group)


## 把所有分组绑定注册到场景管理器，返回注册数量。
static func register_all(manager: PlaceSceneManager) -> int:
	var count := 0
	for group in PLACE_GROUPS:
		manager.register_binding(group, str(PLACE_GROUPS[group]))
		count += 1
	return count
