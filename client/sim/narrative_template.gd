class_name NarrativeTemplate
extends Resource
## 叙事模板资源（R32.5）：以 Godot Resource 组织，支持条件与多变体文本。
## 字段见 design.md Data Models：conditions、texts、variables。
## 具体条目由任务 23 内容管线导入；此处仅定义结构与默认值。

@export var id: String = ""
## 条件字典：等值、数组包含或 {min,max} 数值区间，见 Narrator._match_conditions。
@export var conditions: Dictionary = {}
## 文本变体：元素为 String 或 {conditions, text}。
@export var texts: Array = []
## 变量默认值：渲染时由调用方 vars 覆盖。
@export var variables: Dictionary = {}

func _init(p_id: String = "", p_conditions: Dictionary = {}, p_texts: Array = [], p_variables: Dictionary = {}) -> void:
	id = p_id
	conditions = p_conditions
	texts = p_texts
	variables = p_variables

## 转为纯字典，便于渲染与序列化。
func to_dict() -> Dictionary:
	return {
		"id": id,
		"conditions": conditions.duplicate(true),
		"texts": texts.duplicate(true),
		"variables": variables.duplicate(true),
	}
