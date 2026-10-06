class_name GoldfingerDef
extends Resource
## 金手指内容定义资源（R100；design「金手指系统」内容格式）。
## 与运行时状态区分：本资源是库中每一条金手指的静态定义（对应
## shared/schemas/goldfinger-def.schema.json），运行时状态见 GoldfingerSystem.new_state()。
## 具体条目由任务 23 内容管线自 content/catalog/goldfingers.json 导入；此处定义结构与默认值。

@export var content_key: String = ""
@export var name: String = ""
## 稀有度：common / rare / epic / legendary。
@export var rarity: String = "common"
## 内核分类：info / time / resource / growth / system。
@export var category: String = "growth"
@export var description: String = ""
## 该金手指启用的元层面板模块。
@export var modules: Array = []
## 效果列表：{target, op, value, mode, condition, cost}。
@export var effects: Array = []
@export var growth: Dictionary = {}
@export var points: Dictionary = {}
@export var constraints: Dictionary = {}
@export var draw: Dictionary = {}
@export var meta: Dictionary = {}


func _init(p_content_key: String = "") -> void:
	content_key = p_content_key


## 转为纯字典，供 GoldfingerSystem 消费。
func to_def() -> Dictionary:
	var def: Dictionary = {
		"content_key": content_key, "name": name, "rarity": rarity,
		"category": category, "description": description,
		"modules": modules.duplicate(true), "effects": effects.duplicate(true),
	}
	if not growth.is_empty():
		def["growth"] = growth.duplicate(true)
	if not points.is_empty():
		def["points"] = points.duplicate(true)
	if not constraints.is_empty():
		def["constraints"] = constraints.duplicate(true)
	if not draw.is_empty():
		def["draw"] = draw.duplicate(true)
	if not meta.is_empty():
		def["meta"] = meta.duplicate(true)
	return def


## 由纯字典填充资源字段。
func from_def(def: Dictionary) -> void:
	content_key = str(def.get("content_key", ""))
	name = str(def.get("name", ""))
	rarity = str(def.get("rarity", "common"))
	category = str(def.get("category", "growth"))
	description = str(def.get("description", ""))
	modules = (def.get("modules", []) as Array).duplicate(true)
	effects = (def.get("effects", []) as Array).duplicate(true)
	growth = (def.get("growth", {}) as Dictionary).duplicate(true)
	points = (def.get("points", {}) as Dictionary).duplicate(true)
	constraints = (def.get("constraints", {}) as Dictionary).duplicate(true)
	draw = (def.get("draw", {}) as Dictionary).duplicate(true)
	meta = (def.get("meta", {}) as Dictionary).duplicate(true)
