class_name ContentDef
extends Resource
## 通用内容条目 Resource（任务 23：内容目录骨架与 Resource 定义）。
## 把轻量二进制容器 / catalog 条目包装成 Godot Resource，供编辑器与运行时统一使用。
## 具体内容类别通过 category 区分，字段存于 fields，避免为每类维护单独 .gd。

@export var content_key: String = ""
@export var category: String = ""
@export var fields: Dictionary = {}


static func from_entry(p_category: String, p_key: String, p_fields: Dictionary) -> ContentDef:
	var def := ContentDef.new()
	def.category = p_category
	def.content_key = p_key
	def.fields = p_fields.duplicate(true)
	return def


## 还原为 catalog/容器条目字段（含 content_key）。
func to_entry() -> Dictionary:
	var out: Dictionary = fields.duplicate(true)
	out["content_key"] = content_key
	return out


func get_field(name: String, default_value: Variant = null) -> Variant:
	return fields.get(name, default_value)


func has_field(name: String) -> bool:
	return fields.has(name)


func to_dict() -> Dictionary:
	return {
		"content_key": content_key,
		"category": category,
		"fields": fields.duplicate(true),
	}


static func from_dict(doc: Dictionary) -> ContentDef:
	return ContentDef.from_entry(
		str(doc.get("category", "")),
		str(doc.get("content_key", "")),
		doc.get("fields", {}) if doc.get("fields") is Dictionary else {})
