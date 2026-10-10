class_name PanelContent
extends RefCounted
## 面板内容装配（R35、R57；任务 47/51）。
## 把 GameState 玩家字典转换为面板可渲染的结构化行数据，与视图解耦，headless 可测。
## 输出统一为 {title, empty, empty_hint, sections:[{title, rows:[{label, value}]}]}。
## 名称解析通过可选 Callable 注入（内容注册表在线时传入），离线回退 content_key。

const RegistryScript = preload("res://ui/components/panel_registry.gd")

const QUALITY_LABELS: Dictionary = {
	"common": "普通", "fine": "精良", "rare": "稀有", "legendary": "传说",
}
const QUALITY_ORDER: Array[String] = ["common", "fine", "rare", "legendary"]

const GENDER_LABELS: Dictionary = {
	"male": "男", "female": "女", "nonbinary": "非二元", "unknown": "未知",
}

## 生理/营养/心理/能力/人格/价值观的展示顺序与中文标签（确定性）。
const ATTR_SPECS: Array = [
	["physiological", "生理", [
		["health", "健康"], ["stamina", "体力"], ["hunger", "饥饿"],
		["thirst", "口渴"], ["cleanliness", "清洁"], ["sleep_debt", "睡眠债"],
	]],
	["nutrition", "营养", [
		["protein", "蛋白质"], ["carbs", "碳水"], ["fat", "脂肪"],
		["vitamins", "维生素"], ["minerals", "矿物质"],
	]],
	["psychological", "心理", [
		["mood", "心情"], ["stress", "压力"], ["happiness", "幸福"], ["meaning", "意义"],
	]],
	["ability", "能力", [
		["intelligence", "智力"], ["charm", "魅力"], ["physique", "体质"],
		["willpower", "意志"], ["luck", "幸运"],
	]],
	["personality", "人格", [
		["openness", "开放性"], ["conscientiousness", "尽责性"], ["extraversion", "外向性"],
		["agreeableness", "宜人性"], ["neuroticism", "神经质"],
	]],
	["values", "价值观", [
		["selfish_altruistic", "利己—利他"], ["conservative_open", "保守—开放"],
		["material_spiritual", "物质—精神"],
	]],
]

## 面板入口：按 id 装配内容；未实现的面板返回建设中占位（不抛错）。
static func build(id: String, player: Dictionary, name_resolver: Callable = Callable()) -> Dictionary:
	var title: String = String((RegistryScript.PANELS.get(id, {}) as Dictionary).get("title", id))
	var data: Dictionary
	match id:
		"character":
			data = character(player)
		"inventory":
			data = inventory(player, name_resolver)
		_:
			data = _empty(title, "该面板尚在建设中")
	data["title"] = title
	return data

# --- 角色与属性 ---

static func character(player: Dictionary) -> Dictionary:
	if player.is_empty() or not player.has("attrs"):
		return _empty("角色与属性", "尚未生成角色数据")
	var attrs: Dictionary = player.get("attrs", {})
	var sections: Array = []
	sections.append({
		"title": "基本",
		"rows": [
			{"label": "姓名", "value": String(player.get("name", "无名"))},
			{"label": "性别", "value": String(GENDER_LABELS.get(String(player.get("gender", "unknown")), "未知"))},
			{"label": "国籍", "value": _strip_prefix(String(player.get("nation", "")), "nation.")},
			{"label": "信用分", "value": str(int(player.get("credit_score", 0)))},
		],
	})
	for spec in ATTR_SPECS:
		var group: Dictionary = attrs.get(String(spec[0]), {})
		if group.is_empty():
			continue
		var rows: Array = []
		for field in spec[2]:
			var key: String = String(field[0])
			rows.append({"label": String(field[1]), "value": _num(group.get(key, 0.0))})
		sections.append({"title": String(spec[1]), "rows": rows})
	return {"empty": false, "empty_hint": "", "sections": sections}

# --- 背包与装备 ---

static func inventory(player: Dictionary, name_resolver: Callable = Callable()) -> Dictionary:
	if player.is_empty():
		return _empty("背包与装备", "尚未生成角色数据")
	var items: Array = player.get("inventory", [])
	var equipment: Array = player.get("equipment", [])
	var sections: Array = []
	for quality in QUALITY_ORDER:
		var rows: Array = []
		for item in items:
			if String(item.get("quality", "common")) != quality:
				continue
			rows.append({"label": _name_of(item, name_resolver), "value": _quantity(item)})
		if not rows.is_empty():
			sections.append({"title": "物品 · %s" % String(QUALITY_LABELS[quality]), "rows": rows})
	# 未标注品质的物品归入「普通」之外的兜底，避免遗漏。
	var loose: Array = []
	for item in items:
		if not QUALITY_LABELS.has(String(item.get("quality", "common"))):
			loose.append({"label": _name_of(item, name_resolver), "value": _quantity(item)})
	if not loose.is_empty():
		sections.append({"title": "物品 · 未分类", "rows": loose})
	if not equipment.is_empty():
		var eq_rows: Array = []
		for slot in equipment:
			eq_rows.append({"label": _resolve(String(slot), name_resolver), "value": "已装备"})
		sections.append({"title": "装备", "rows": eq_rows})
	if sections.is_empty():
		return _empty("背包与装备", "背包空空如也，可通过购买、拾取或任务获取物品")
	return {"empty": false, "empty_hint": "", "sections": sections}

# --- 内部 ---

static func _name_of(item: Dictionary, name_resolver: Callable) -> String:
	return _resolve(String(item.get("content_key", "?")), name_resolver)

static func _resolve(key: String, name_resolver: Callable) -> String:
	if name_resolver.is_valid():
		var nm: Variant = name_resolver.call(key)
		if nm != null and String(nm) != "":
			return String(nm)
	return _strip_prefix(key, "item.")

static func _quantity(item: Dictionary) -> String:
	var text: String = "x%d" % int(item.get("quantity", 0))
	if item.has("durability"):
		text += " · 耐久%s" % _num(item.get("durability", 0.0))
	return text

static func _strip_prefix(value: String, prefix: String) -> String:
	if value.begins_with(prefix):
		return value.substr(prefix.length())
	return value

static func _num(value: Variant) -> String:
	return "%.0f" % float(value)

static func _empty(title: String, hint: String) -> Dictionary:
	return {"title": title, "empty": true, "empty_hint": hint, "sections": []}
