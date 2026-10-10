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

const CIRCLE_LABELS: Dictionary = {
	"friend": "朋友", "classmate": "同学", "colleague": "同事", "neighbor": "邻居",
	"online": "网友", "family": "家人", "other": "其他",
}

const CREDENTIAL_STATUS: Dictionary = {
	"in_progress": "在读", "graduated": "已毕业", "revoked": "已吊销", "expired": "已过期",
}

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
		"skills":
			data = skills(player, name_resolver)
		"career":
			data = career(player, name_resolver)
		"finance":
			data = finance(player, name_resolver)
		"relations":
			data = relations(player, name_resolver)
		"achievements":
			data = achievements(player, name_resolver)
		"family":
			data = family(player, name_resolver)
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

# --- 技能树 ---

static func skills(player: Dictionary, name_resolver: Callable = Callable()) -> Dictionary:
	if player.is_empty():
		return _empty("技能树", "尚未生成角色数据")
	var arr: Array = player.get("skills", [])
	if arr.is_empty():
		return _empty("技能树", "尚未习得技能，可通过学习与练习提升")
	var rows: Array = []
	for s in arr:
		var value: String = "Lv%d" % int(s.get("level", 0))
		if s.has("xp"):
			value += " · 经验%s" % _num(s.get("xp", 0.0))
		rows.append({"label": _resolve(String(s.get("content_key", "?")), name_resolver), "value": value})
	return {"empty": false, "empty_hint": "", "sections": [{"title": "技能", "rows": rows}]}

# --- 工作与职业 ---

static func career(player: Dictionary, name_resolver: Callable = Callable()) -> Dictionary:
	if player.is_empty():
		return _empty("工作与职业", "尚未生成角色数据")
	var job: Dictionary = player.get("job", {})
	var education: Array = player.get("education", [])
	var licenses: Array = player.get("licenses", [])
	if job.is_empty() and education.is_empty() and licenses.is_empty():
		return _empty("工作与职业", "尚未就业，可通过求职寻找工作")
	var sections: Array = []
	var job_rows: Array = []
	if job.is_empty():
		job_rows.append({"label": "当前", "value": "无业"})
	else:
		var title: String = String(job.get("title", ""))
		job_rows.append({"label": "职位", "value": title if title != "" else _resolve(String(job.get("content_key", "?")), name_resolver)})
		if job.has("industry"):
			job_rows.append({"label": "行业", "value": _resolve(String(job.get("industry", "")), name_resolver)})
		if job.has("salary"):
			job_rows.append({"label": "月薪", "value": _money(job.get("salary", 0.0))})
		if job.has("performance"):
			job_rows.append({"label": "绩效", "value": _num(job.get("performance", 0.0))})
		if job.has("internal_reputation"):
			job_rows.append({"label": "内部声望", "value": _num(job.get("internal_reputation", 0.0))})
	sections.append({"title": "职业", "rows": job_rows})
	if not education.is_empty():
		sections.append({"title": "学历", "rows": _credential_rows(education, name_resolver)})
	if not licenses.is_empty():
		sections.append({"title": "执照", "rows": _credential_rows(licenses, name_resolver)})
	return {"empty": false, "empty_hint": "", "sections": sections}

static func _credential_rows(items: Array, name_resolver: Callable) -> Array:
	var rows: Array = []
	for c in items:
		var status: String = String(CREDENTIAL_STATUS.get(String(c.get("status", "")), String(c.get("status", ""))))
		rows.append({"label": _resolve(String(c.get("content_key", "?")), name_resolver), "value": status})
	return rows

# --- 资产与财务 ---

static func finance(player: Dictionary, name_resolver: Callable = Callable()) -> Dictionary:
	if player.is_empty():
		return _empty("资产与财务", "尚未生成角色数据")
	var fin: Dictionary = player.get("finances", {})
	var assets: Array = player.get("assets", [])
	var rows: Array = [
		{"label": "现金", "value": _money(fin.get("cash", 0.0))},
		{"label": "银行存款", "value": _money(fin.get("bank", 0.0))},
		{"label": "负债", "value": _money(fin.get("debt", 0.0))},
		{"label": "信用分", "value": str(int(player.get("credit_score", 0)))},
	]
	if fin.has("monthly_income"):
		rows.append({"label": "月收入", "value": _money(fin.get("monthly_income", 0.0))})
	if fin.has("monthly_expense"):
		rows.append({"label": "月支出", "value": _money(fin.get("monthly_expense", 0.0))})
	if fin.has("credit_limit"):
		rows.append({"label": "信用额度", "value": _money(fin.get("credit_limit", 0.0))})
	var sections: Array = [{"title": "资金", "rows": rows}]
	if not assets.is_empty():
		var asset_rows: Array = []
		for a in assets:
			var value: String = _money(a.get("value", 0.0)) if a.has("value") else "—"
			if bool(a.get("mortgaged", false)):
				value += " · 已抵押"
			asset_rows.append({"label": _resolve(String(a.get("content_key", "?")), name_resolver), "value": value})
		sections.append({"title": "资产", "rows": asset_rows})
	return {"empty": false, "empty_hint": "", "sections": sections}

# --- 关系与人脉 ---

static func relations(player: Dictionary, name_resolver: Callable = Callable()) -> Dictionary:
	if player.is_empty():
		return _empty("关系与人脉", "尚未生成角色数据")
	var arr: Array = player.get("relations", [])
	if arr.is_empty():
		return _empty("关系与人脉", "尚无关系，可在日常互动中结识他人")
	var rows: Array = []
	for r in arr:
		var circle: String = String(CIRCLE_LABELS.get(String(r.get("circle", "")), ""))
		var value: String = "好感%d · 信任%d" % [int(r.get("favor", 0)), int(r.get("trust", 0))]
		if circle != "":
			value = "%s · %s" % [circle, value]
		rows.append({"label": _short_id(String(r.get("target_id", "?"))), "value": value})
	return {"empty": false, "empty_hint": "", "sections": [{"title": "关系", "rows": rows}]}

# --- 成就与图鉴 ---

static func achievements(player: Dictionary, name_resolver: Callable = Callable()) -> Dictionary:
	if player.is_empty():
		return _empty("成就与图鉴", "尚未生成角色数据")
	var arr: Array = player.get("achievements", [])
	if arr.is_empty():
		return _empty("成就与图鉴", "尚无成就，继续体验人生解锁")
	var rows: Array = []
	for key in arr:
		rows.append({"label": _resolve(String(key), name_resolver), "value": "已达成"})
	return {"empty": false, "empty_hint": "", "sections": [{"title": "成就", "rows": rows}]}

# --- 家族史与传承 ---

static func family(player: Dictionary, name_resolver: Callable = Callable()) -> Dictionary:
	if player.is_empty():
		return _empty("家族史与传承", "尚未生成角色数据")
	var fam: Dictionary = player.get("family", {})
	if fam.is_empty():
		return _empty("家族史与传承", "首代尚无家族记录，随传承积累")
	var rows: Array = []
	if not String(fam.get("spouse_id", "")).is_empty():
		rows.append({"label": "配偶", "value": _short_id(String(fam["spouse_id"]))})
	rows.append({"label": "伴侣", "value": str((fam.get("partner_ids", []) as Array).size())})
	rows.append({"label": "子女", "value": str((fam.get("children_ids", []) as Array).size())})
	rows.append({"label": "父母", "value": str((fam.get("parent_ids", []) as Array).size())})
	rows.append({"label": "兄弟姐妹", "value": str((fam.get("sibling_ids", []) as Array).size())})
	rows.append({"label": "养子女", "value": str((fam.get("adopted_ids", []) as Array).size())})
	var pregnancy: Dictionary = fam.get("pregnancy", {})
	if not pregnancy.is_empty() and pregnancy.has("due_minutes"):
		rows.append({"label": "预产", "value": "第 %d 分钟" % int(pregnancy.get("due_minutes", 0))})
	return {"empty": false, "empty_hint": "", "sections": [{"title": "家庭", "rows": rows}]}

# --- 内部 ---

static func _name_of(item: Dictionary, name_resolver: Callable) -> String:
	return _resolve(String(item.get("content_key", "?")), name_resolver)

const KEY_PREFIXES: Array[String] = [
	"item.", "skill.", "job.", "industry.", "edu.", "license.",
	"asset.", "achv.", "inv.", "map.", "org.", "nation.", "language.",
]

static func _resolve(key: String, name_resolver: Callable) -> String:
	if name_resolver.is_valid():
		var nm: Variant = name_resolver.call(key)
		if nm != null and String(nm) != "":
			return String(nm)
	for prefix in KEY_PREFIXES:
		if key.begins_with(prefix):
			return key.substr(prefix.length())
	return key

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

static func _money(value: Variant) -> String:
	return "%.0f" % float(value)

static func _short_id(value: String) -> String:
	if value.length() <= 8:
		return value
	return value.substr(value.length() - 8)

static func _empty(title: String, hint: String) -> Dictionary:
	return {"title": title, "empty": true, "empty_hint": hint, "sections": []}
