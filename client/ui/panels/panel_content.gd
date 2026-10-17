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

const SCHEME_LABELS: Dictionary = {"dark": "暗色", "light": "亮色"}
const VARIANT_LABELS: Dictionary = {
	"default": "默认", "high_contrast": "高对比", "colorblind": "色盲友好",
}
const ACCENT_LABELS: Dictionary = {
	"cinnabar": "朱砂", "daiqing": "黛青", "indigo": "花青", "ochre": "赭石", "jade": "石绿",
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
## context 可选携带视图外部数据：regions/current_region/itineraries（地图）、settings（设置）。
static func build(id: String, player: Dictionary, name_resolver: Callable = Callable(), context: Dictionary = {}) -> Dictionary:
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
		"map":
			data = map_panel(context, name_resolver)
		"settings":
			data = settings_panel(context)
		"business":
			data = business(player, context, name_resolver)
		"organizations":
			data = organizations(player, context, name_resolver)
		"legal":
			data = legal(player, context, name_resolver)
		"rescue":
			data = rescue(player, context, name_resolver)
		"environment":
			data = environment(player, context, name_resolver)
		"municipal":
			data = municipal(player, context, name_resolver)
		"debt":
			data = debt(player, context, name_resolver)
		"consumer":
			data = consumer(player, context, name_resolver)
		"welfare":
			data = welfare(player, context, name_resolver)
		"funeral":
			data = funeral(player, context, name_resolver)
		"metaphysics":
			data = metaphysics(player, context, name_resolver)
		"medical":
			data = medical(player, context, name_resolver)
		"mental":
			data = mental(player, context, name_resolver)
		"spirit":
			data = spirit(player, context, name_resolver)
		"language":
			data = language(player, context, name_resolver)
		"disability":
			data = disability(player, context, name_resolver)
		"agriculture":
			data = agriculture(player, context, name_resolver)
		"late_tech":
			data = late_tech(player, context, name_resolver)
		"ip_media":
			data = ip_media(player, context, name_resolver)
		"content_industry":
			data = content_industry(player, context, name_resolver)
		"engineering":
			data = engineering(player, context, name_resolver)
		"services":
			data = services(player, context, name_resolver)
		"transport_infra":
			data = transport_infra(player, context, name_resolver)
		"household":
			data = household(player, name_resolver)
		"sports":
			data = sports(player, context, name_resolver)
		"events":
			data = events_panel(player, context, name_resolver)
		"awards":
			data = awards(player, context, name_resolver)
		"digital":
			data = digital(player, context, name_resolver)
		"epidemic":
			data = epidemic(player, context, name_resolver)
		"war":
			data = war(player, name_resolver)
		"market":
			data = market(player, context)
		"weather":
			data = weather(player, context, name_resolver)
		"anomaly":
			data = anomaly(player, context, name_resolver)
		"goldfinger":
			data = goldfinger(player, name_resolver)
		"ending":
			data = ending(context)
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

# --- 人生结算 ---

## 死亡结算面板：读取 SimHost.death_summary()（经 context["death"] 注入）。
static func ending(context: Dictionary) -> Dictionary:
	var s: Dictionary = context.get("death", {}) if context.get("death") is Dictionary else {}
	if s.is_empty():
		return _empty("人生结算", "尚未结算")
	var sections: Array = []
	sections.append({
		"title": "生平",
		"rows": [
			{"label": "姓名", "value": String(s.get("name", "无名"))},
			{"label": "性别", "value": String(GENDER_LABELS.get(String(s.get("gender", "unknown")), "未知"))},
			{"label": "享年", "value": "%d 岁" % int(s.get("age_years", 0.0))},
			{"label": "终号", "value": String(s.get("final_title", "凡人"))},
			{"label": "遗嘱", "value": "有" if bool(s.get("has_will", false)) else "无"},
		],
	})
	var heirs: Dictionary = s.get("heirs", {}) if s.get("heirs") is Dictionary else {}
	var heir_labels: Dictionary = {"spouse": "配偶", "children": "子女", "parents": "父母", "siblings": "兄弟姐妹"}
	var heir_rows: Array = []
	for key in ["spouse", "children", "parents", "siblings"]:
		var arr: Array = heirs.get(key, []) if heirs.get(key, []) is Array else []
		heir_rows.append({"label": String(heir_labels.get(key, key)), "value": "%d 位" % arr.size()})
	sections.append({"title": "遗产", "rows": [
		{"label": "净额", "value": "%.1f 万元" % (float(s.get("estate_minor", 0.0)) / 1000000.0)},
	]})
	sections.append({"title": "法定继承人", "rows": heir_rows})
	if s.get("timeline") is Array and not (s["timeline"] as Array).is_empty():
		var tl_rows: Array = []
		for item in (s["timeline"] as Array):
			tl_rows.append({"label": "·", "value": String(item)})
		sections.append({"title": "人生大事记", "rows": tl_rows})
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
	if not (fam.get("guardian_ids", []) as Array).is_empty():
		rows.append({"label": "指定监护人", "value": str((fam.get("guardian_ids", []) as Array).size())})
	var pregnancy: Dictionary = fam.get("pregnancy", {})
	if not pregnancy.is_empty() and pregnancy.has("due_minutes"):
		rows.append({"label": "预产", "value": "第 %d 分钟" % int(pregnancy.get("due_minutes", 0))})
	return {"empty": false, "empty_hint": "", "sections": [{"title": "家庭", "rows": rows}]}

# --- 地图 ---

static func map_panel(context: Dictionary, name_resolver: Callable = Callable()) -> Dictionary:
	var regions: Array = context.get("regions", [])
	var current: String = String(context.get("current_region", ""))
	var itineraries: Array = context.get("itineraries", [])
	if regions.is_empty() and current.is_empty() and itineraries.is_empty():
		return _empty("地图", "尚未探索地图，先从所在区域开始移动")
	var sections: Array = []
	if current != "":
		sections.append({"title": "当前区域", "rows": [{"label": _resolve(current, name_resolver), "value": "所在"}]})
	if not regions.is_empty():
		var region_rows: Array = []
		for r in regions:
			var parts := PackedStringArray()
			if r.has("population"):
				parts.append("人口%d" % int(r["population"]))
			if r.has("price_index"):
				parts.append("物价%.2f" % float(r["price_index"]))
			if r.has("safety"):
				parts.append("治安%d" % int(r["safety"]))
			region_rows.append({
				"label": _resolve(String(r.get("region_key", "?")), name_resolver),
				"value": " · ".join(parts) if parts.size() > 0 else "已到访",
			})
		sections.append({"title": "已到访区域", "rows": region_rows})
	if not itineraries.is_empty():
		var trip_rows: Array = []
		for it in itineraries:
			var dest: Dictionary = it.get("destination", {})
			var key: String = String(dest.get("region_id", dest.get("location_key", "?")))
			var value: String = String(it.get("mode", ""))
			if it.has("arrive_minutes"):
				value += " · 抵达%d" % int(it["arrive_minutes"])
			trip_rows.append({"label": _resolve(key, name_resolver), "value": value})
		sections.append({"title": "行程", "rows": trip_rows})
	return {"empty": false, "empty_hint": "", "sections": sections}

# --- 设置 ---

static func settings_panel(context: Dictionary) -> Dictionary:
	var s: Dictionary = context.get("settings", {})
	if s.is_empty():
		return _empty("设置", "设置尚未接入")
	var appearance: Array = []
	if s.has("scheme"):
		appearance.append({"label": "主题", "value": String(SCHEME_LABELS.get(String(s["scheme"]), String(s["scheme"])))})
	if s.has("variant"):
		appearance.append({"label": "配色方案", "value": String(VARIANT_LABELS.get(String(s["variant"]), String(s["variant"])))})
	if s.has("accent"):
		appearance.append({"label": "主题色", "value": String(ACCENT_LABELS.get(String(s["accent"]), String(s["accent"])))})
	if s.has("ui_scale"):
		appearance.append({"label": "界面缩放", "value": "%d%%" % int(round(float(s["ui_scale"]) * 100.0))})
	if s.has("body_font_scale"):
		appearance.append({"label": "正文字号", "value": "%d%%" % int(round(float(s["body_font_scale"]) * 100.0))})
	var access: Array = []
	if s.has("reduce_motion"):
		access.append({"label": "减少动态", "value": _yes_no(s["reduce_motion"])})
	if s.has("tts_enabled"):
		access.append({"label": "文本朗读", "value": _yes_no(s["tts_enabled"])})
	var misc: Array = []
	if s.has("speed_level"):
		misc.append({"label": "推进倍速", "value": "%dx" % int(s["speed_level"])})
	if s.has("tray_enabled"):
		misc.append({"label": "系统托盘", "value": _yes_no(s["tray_enabled"])})
	var sections: Array = []
	if not appearance.is_empty():
		sections.append({"title": "外观", "rows": appearance})
	if not access.is_empty():
		sections.append({"title": "无障碍", "rows": access})
	if not misc.is_empty():
		sections.append({"title": "其他", "rows": misc})
	return {"empty": false, "empty_hint": "", "sections": sections}

static func _yes_no(value: Variant) -> String:
	return "开启" if bool(value) else "关闭"

# --- 领域面板（D8–D50 摘要视图）---
# 这些面板把玩家/世界增量中已有字段装配为行数据；缺失数据时给出引导性空态。
# 世界级数据经 context["world_delta"] 注入（由 main._panel_context 提供）。

const FIELD_LABELS: Dictionary = {
	"status": "状态", "type": "类型", "stage": "阶段", "level": "等级", "grade": "等级",
	"amount": "金额", "value": "价值", "price": "价格", "balance": "余额", "salary": "薪资",
	"principal": "本金", "rate": "利率", "revenue": "收入", "cost": "成本", "profit": "利润",
	"progress": "进度", "score": "得分", "rank": "排名", "rating": "评级", "severity": "严重度",
	"stock": "库存", "capacity": "产能", "industry": "行业", "region": "区域", "venue": "场馆",
	"members": "成员", "reputation": "声望", "royalty": "分成", "budget": "预算", "area": "面积",
	"kind": "类别", "platform": "平台", "followers": "粉丝", "teams": "队伍", "year": "年份",
	"branch": "军种", "unit": "部队", "containment": "收容等级", "faction": "阵营", "class": "分级",
	"start_minutes": "开始", "arrive_minutes": "抵达", "due_minutes": "到期", "signed_minutes": "签订",
}

static func _world(context: Dictionary) -> Dictionary:
	var w: Variant = context.get("world_delta", context.get("world", {}))
	return w if w is Dictionary else {}

static func _section(title: String, rows: Array) -> Dictionary:
	return {"title": title, "rows": rows}

static func _ok(sections: Array) -> Dictionary:
	return {"empty": false, "empty_hint": "", "sections": sections}

static func _fmt_value(key: String, value: Variant) -> String:
	match key:
		"amount", "value", "price", "balance", "salary", "principal", "revenue", "cost", "profit", "budget":
			return _money(value)
		"rate":
			return "%.2f%%" % (float(value) * 100.0)
		"start_minutes", "arrive_minutes", "due_minutes", "signed_minutes":
			return "%d 分钟" % int(value)
		_:
			if typeof(value) == TYPE_BOOL:
				return _yes_no(value)
			if typeof(value) == TYPE_FLOAT:
				return _num(value)
			return str(value)

## 把字典数组渲染为行：名称取 name/title/content_key，值取 fields 中存在的键。
static func _rows_from(items: Array, fields: Array, name_resolver: Callable) -> Array:
	var rows: Array = []
	for it in items:
		if typeof(it) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = it
		var name := String(d.get("name", d.get("title", "")))
		if name == "":
			name = _resolve(String(d.get("content_key", d.get("region_key", d.get("id", "?")))), name_resolver)
		var parts := PackedStringArray()
		for f in fields:
			var key := String(f)
			if d.has(key):
				parts.append("%s%s" % [String(FIELD_LABELS.get(key, key)), _fmt_value(key, d[key])])
		rows.append({"label": name, "value": " · ".join(parts) if parts.size() > 0 else "—"})
	return rows

static func _items_of(items: Variant) -> Array:
	return items if items is Array else []

static func business(player: Dictionary, context: Dictionary, name_resolver: Callable = Callable()) -> Dictionary:
	if player.is_empty():
		return _empty("经营", "尚未生成角色数据")
	var w: Dictionary = _world(context)
	var sections: Array = []
	var companies: Array = _items_of(w.get("companies", []))
	var factories: Array = _items_of(w.get("factories", []))
	if not companies.is_empty():
		sections.append(_section("公司", _rows_from(companies, ["industry", "stage", "profit"], name_resolver)))
	if not factories.is_empty():
		sections.append(_section("工厂与产线", _rows_from(factories, ["industry", "stock", "capacity"], name_resolver)))
	var mfg: Dictionary = context.get("manufacturing", {}) if context.get("manufacturing") is Dictionary else {}
	if not mfg.is_empty():
		sections.append_array(_mfg_sections(mfg))
	var trd: Dictionary = context.get("trade", {}) if context.get("trade") is Dictionary else {}
	var shipments: Array = _items_of(trd.get("shipments", []))
	if not shipments.is_empty():
		var trows: Array = []
		for sh in shipments:
			if sh is Dictionary:
				var sd: Dictionary = sh
				trows.append({
					"label": "%s #%d" % [String(sd.get("goods", "货物")), int(sd.get("index", 0))],
					"value": "%s · %s · %s" % [
						String(sd.get("stage_name", "")),
						String(sd.get("incoterm", "未签约")),
						("已结汇" if bool(sd.get("settled", false)) else ("运费 %d" % int(sd.get("freight", 0)))),
					],
				})
		sections.append(_section("外贸单据", trows))
	var mn: Dictionary = context.get("mining", {}) if context.get("mining") is Dictionary else {}
	if not mn.is_empty():
		sections.append_array(_mining_sections(mn))
	var dng: Dictionary = context.get("dining", {}) if context.get("dining") is Dictionary else {}
	if not dng.is_empty():
		sections.append_array(_dining_sections(dng))
	var fsh: Dictionary = context.get("fashion", {}) if context.get("fashion") is Dictionary else {}
	if not fsh.is_empty():
		sections.append_array(_fashion_sections(fsh))
	if sections.is_empty():
		return _empty("经营", "尚无产业；可通过创业、融资或收购开启经营")
	return _ok(sections)

## 时尚面板分区：品牌概况、潮流、作品、库存。
static func _fashion_sections(fsh: Dictionary) -> Array:
	var sections: Array = []
	sections.append(_section("品牌概况", [
		{"label": "名称", "value": String(fsh.get("name", ""))},
		{"label": "定位", "value": String(fsh.get("positioning_name", ""))},
		{"label": "资金", "value": str(int(fsh.get("money", 0)))},
		{"label": "品牌价值", "value": str(int(fsh.get("brand_value", 0)))},
		{"label": "溢价系数", "value": "%.2f" % float(fsh.get("premium", 1.0))},
		{"label": "声誉", "value": "%.0f" % float(fsh.get("reputation", 0.0))},
		{"label": "热度", "value": "%.0f" % float(fsh.get("fame", 0.0))},
		{"label": "相关度", "value": "%.0f" % float(fsh.get("relevance", 0.0))},
		{"label": "门店", "value": "%d 家" % int(fsh.get("stores", 0))},
	]))
	sections.append(_section("时尚潮流", [
		{"label": "阶段", "value": String(fsh.get("trend_phase_name", ""))},
		{"label": "热门学科", "value": String(fsh.get("trend_hot", ""))},
	]))
	var designs: Array = _items_of(fsh.get("designs", []))
	if not designs.is_empty():
		var rows: Array = []
		for d in designs:
			if d is Dictionary:
				var dd: Dictionary = d
				rows.append({"label": String(dd.get("discipline_name", "?")), "value": "评分 %.0f · %s" % [float(dd.get("score", 0.0)), String(dd.get("grade", ""))]})
		sections.append(_section("作品", rows))
	var inv: Array = _items_of(fsh.get("inventory", []))
	if not inv.is_empty():
		var irows: Array = []
		for it in inv:
			if it is Dictionary:
				var id: Dictionary = it
				irows.append({"label": String(id.get("key", "?")), "value": "%d 件 · 单价 %d" % [int(id.get("qty", 0)), int(id.get("price", 0))]})
		sections.append(_section("库存", irows))
	return sections

## 体育面板分区：球员生涯、所属球会、积分榜。
static func _sports_sections(spo: Dictionary) -> Array:
	var sections: Array = []
	sections.append(_section("球员生涯", [
		{"label": "阶段", "value": String(spo.get("stage", ""))},
		{"label": "年龄", "value": str(int(spo.get("age", 0)))},
		{"label": "状态", "value": "%.0f" % float(spo.get("form", 0.0))},
		{"label": "身价", "value": str(int(spo.get("market_value", 0)))},
		{"label": "月薪", "value": str(int(spo.get("wage", 0)))},
		{"label": "伤病", "value": "%d 天" % int(spo.get("injury_days", 0.0))},
		{"label": "禁赛", "value": "%d 天" % int(spo.get("ban_days", 0.0))},
		{"label": "出场", "value": str(int(spo.get("appearances", 0)))},
		{"label": "进球", "value": str(int(spo.get("goals", 0)))},
		{"label": "赞助", "value": "%d 家" % int(spo.get("sponsors", 0))},
	]))
	sections.append(_section("所属球会", [
		{"label": "名称", "value": String(spo.get("club", ""))},
		{"label": "级别", "value": String(spo.get("club_division", ""))},
		{"label": "预算", "value": str(int(spo.get("budget", 0)))},
	]))
	var rows_list: Array = _items_of(spo.get("standings", []))
	if not rows_list.is_empty():
		var rows: Array = []
		for row in rows_list:
			if row is Dictionary:
				var rd: Dictionary = row
				rows.append({"label": String(rd.get("id", "?")), "value": "%d 场 · %d 分 · 净胜 %d" % [int(rd.get("played", 0)), int(rd.get("points", 0)), int(rd.get("goals_for", 0)) - int(rd.get("goals_against", 0))]})
		sections.append(_section("积分榜", rows))
	return sections

## 餐饮面板分区：门店概况、菜单、员工、产品、认证。
static func _dining_sections(dng: Dictionary) -> Array:
	var sections: Array = []
	sections.append(_section("餐厅概况", [
		{"label": "名称", "value": String(dng.get("name", ""))},
		{"label": "经营模式", "value": String(dng.get("mode_name", ""))},
		{"label": "门店", "value": "%d 家" % int(dng.get("stores", 1))},
		{"label": "资金", "value": str(int(dng.get("money", 0)))},
		{"label": "评星", "value": String(dng.get("stars_name", ""))},
		{"label": "口碑", "value": "%.0f" % float(dng.get("reputation", 0.0))},
		{"label": "卫生", "value": "%.0f" % float(dng.get("hygiene", 0.0))},
		{"label": "品牌", "value": "%.0f" % float(dng.get("brand", 0.0))},
		{"label": "翻台率", "value": "%.2f" % float(dng.get("turnover", 0.0))},
	]))
	var menu: Array = _items_of(dng.get("menu", []))
	if not menu.is_empty():
		var rows: Array = []
		for m in menu:
			if m is Dictionary:
				var md: Dictionary = m
				rows.append({"label": String(md.get("name", "?")), "value": "售价 %d · 成本 %d · 毛利 %.0f%%" % [int(md.get("price", 0)), int(md.get("cost", 0)), float(md.get("margin", 0.0)) * 100.0]})
		sections.append(_section("菜单", rows))
	var staff: Array = _items_of(dng.get("staff", []))
	if not staff.is_empty():
		var srows: Array = []
		for s in staff:
			if s is Dictionary:
				srows.append({"label": String((s as Dictionary).get("name", "?")), "value": "%d 人" % int((s as Dictionary).get("count", 0))})
		sections.append(_section("员工", srows))
	var products: Array = _items_of(dng.get("products", []))
	if not products.is_empty():
		var prows: Array = []
		for p in products:
			if p is Dictionary:
				prows.append({"label": String((p as Dictionary).get("key", "?")), "value": "%.1f" % float((p as Dictionary).get("qty", 0.0))})
		sections.append(_section("预包装库存", prows))
	var certs: Array = _items_of(dng.get("certifications", []))
	if not certs.is_empty():
		var names: Array = []
		for c in certs:
			names.append(String(c))
		sections.append(_section("食安认证", [{"label": "已取得", "value": "、".join(PackedStringArray(names))}]))
	return sections

## 制造业面板分区：工厂概况、人员、原料、成品、订单。
static func _mfg_sections(mfg: Dictionary) -> Array:
	var sections: Array = []
	var overview: Array = [{
		"label": "经营模式", "value": String(mfg.get("mode_name", "")),
	}, {
		"label": "营运资金", "value": str(int(mfg.get("money", 0))),
	}, {
		"label": "用工人数", "value": str(int(mfg.get("headcount", 0))),
	}, {
		"label": "有效产能", "value": "%.1f（瓶颈：%s）" % [float(mfg.get("effective_capacity", 0.0)), _mfg_bottleneck_cn(String(mfg.get("bottleneck", "")))],
	}]
	var disruptions: Array = _items_of(mfg.get("active_disruptions", []))
	if not disruptions.is_empty():
		overview.append({"label": "在产风险", "value": "%d 项中断" % disruptions.size()})
	sections.append(_section("工厂概况", overview))
	var staff: Array = _items_of(mfg.get("staff", []))
	if not staff.is_empty():
		var srows: Array = []
		for s in staff:
			if s is Dictionary:
				srows.append({"label": String((s as Dictionary).get("name", "?")), "value": "%d 人" % int((s as Dictionary).get("count", 0))})
		sections.append(_section("产线人员", srows))
	var materials: Array = _items_of(mfg.get("materials", []))
	if not materials.is_empty():
		var mrows: Array = []
		for m in materials:
			if m is Dictionary:
				mrows.append({"label": String((m as Dictionary).get("id", "?")), "value": "%.1f" % float((m as Dictionary).get("qty", 0.0))})
		sections.append(_section("原料库存", mrows))
	var products: Array = _items_of(mfg.get("products", []))
	if not products.is_empty():
		var prows: Array = []
		for p in products:
			if p is Dictionary:
				prows.append({"label": String((p as Dictionary).get("name", "?")), "value": "%.1f" % float((p as Dictionary).get("qty", 0.0))})
		sections.append(_section("成品库存", prows))
	var orders: Array = _items_of(mfg.get("orders", []))
	if not orders.is_empty():
		var orows: Array = []
		for o in orders:
			if o is Dictionary:
				var od: Dictionary = o
				var state: String = "已交付" if bool(od.get("fulfilled", false)) else "进行中"
				orows.append({"label": "%s 订单 #%d" % [String(od.get("name", "?")), int(od.get("index", 0))], "value": "%s %.1f/%.1f" % [state, float(od.get("delivered", 0.0)), float(od.get("quantity", 0.0))]})
		sections.append(_section("订单", orows))
	return sections

## 矿业/能源面板分区：矿场概况、能源价格、新能源项目。
static func _mining_sections(mn: Dictionary) -> Array:
	var sections: Array = []
	var mine: Dictionary = mn.get("mine", {}) if mn.get("mine") is Dictionary else {}
	if not mine.is_empty():
		var overview: Array = [
			{"label": "矿种", "value": String(mine.get("mineral_name", ""))},
			{"label": "矿权", "value": ("已取得" if bool(mine.get("concession", false)) else "未取得")},
			{"label": "勘探", "value": ("已勘探" if bool(mine.get("explored", false)) else "未勘探")},
			{"label": "储量", "value": "%.0f" % float(mine.get("reserve", 0.0))},
			{"label": "品位", "value": "%.2f" % float(mine.get("grade", 0.0))},
			{"label": "安全投入", "value": "%.2f" % float(mine.get("safety", 0.5))},
			{"label": "矿石库存", "value": "%.1f" % float(mine.get("stockpile_ore", 0.0))},
			{"label": "待炼矿石", "value": "%.1f" % float(mine.get("in_transit_ore", 0.0))},
			{"label": "精炼金属", "value": "%.1f" % float(mine.get("refined_metal", 0.0))},
			{"label": "累计营收", "value": str(int(mine.get("revenue", 0)))},
		]
		sections.append(_section("矿场概况", overview))
	var prices: Array = _items_of(mn.get("energy_prices", []))
	if not prices.is_empty():
		var prows: Array = []
		for p in prices:
			if p is Dictionary:
				prows.append({"label": String((p as Dictionary).get("name", "?")), "value": str(int((p as Dictionary).get("price", 0)))})
		sections.append(_section("能源价格", prows))
	var projects: Array = _items_of(mn.get("projects", []))
	if not projects.is_empty():
		var jrows: Array = []
		for pj in projects:
			if pj is Dictionary:
				jrows.append({"label": String((pj as Dictionary).get("name", "?")), "value": "装机 %.1f" % float((pj as Dictionary).get("capacity", 0.0))})
		sections.append(_section("新能源项目", jrows))
	return sections

static func _mfg_bottleneck_cn(key: String) -> String:
	match key:
		"equipment":
			return "设备"
		"labor":
			return "人力"
		"efficiency":
			return "效率"
		"material":
			return "原料"
		_:
			return key if key != "" else "无"

static func organizations(player: Dictionary, context: Dictionary, name_resolver: Callable = Callable()) -> Dictionary:
	if player.is_empty():
		return _empty("组织", "尚未生成角色数据")
	var data: Variant = context.get("organizations", {})
	var memberships: Array = _items_of((data as Dictionary).get("memberships", [])) if data is Dictionary else []
	var available: Array = _items_of((data as Dictionary).get("available", [])) if data is Dictionary else []
	var sections: Array = []
	if not memberships.is_empty():
		var rows: Array = []
		for m in memberships:
			if typeof(m) != TYPE_DICTIONARY:
				continue
			var d: Dictionary = m
			var parts := PackedStringArray([String(d.get("type", "")), String(d.get("rank", ""))])
			parts.append("成员 %s" % str(d.get("members", 0)))
			parts.append("影响力 %s" % String(d.get("influence", "")))
			if int(d.get("dues_owed", 0)) > 0:
				parts.append("欠费 %s" % _money(d.get("dues_owed", 0)))
			rows.append({"label": String(d.get("name", "?")), "value": " · ".join(parts)})
		sections.append(_section("我的组织", rows))
	if not available.is_empty():
		var arows: Array = []
		for a in available:
			if typeof(a) != TYPE_DICTIONARY:
				continue
			var d: Dictionary = a
			arows.append({"label": String(d.get("name", "?")), "value": "%s · 入会费 %s · %s" % [String(d.get("type", "")), _money(d.get("fee", 0)), String(d.get("legality", ""))]})
		sections.append(_section("可加入组织", arows))
	if sections.is_empty():
		var orgs: Array = _items_of(_world(context).get("organizations", []))
		if orgs.is_empty():
			return _empty("组织", "尚未加入组织；可加入工会、协会、NGO、俱乐部或阵营")
		sections.append(_section("组织", _rows_from(orgs, ["type", "members", "reputation", "rank"], name_resolver)))
	return _ok(sections)

static func legal(player: Dictionary, context: Dictionary, name_resolver: Callable = Callable()) -> Dictionary:
	if player.is_empty():
		return _empty("案件与法律", "尚未生成角色数据")
	var sections: Array = []
	var lg: Dictionary = player.get("legal", {})
	var wanted: int = int(lg.get("wanted_level", 0))
	var criminal: bool = bool(lg.get("criminal_record", false))
	var in_prison: bool = bool(lg.get("in_prison", false))
	if wanted > 0 or criminal or in_prison:
		var st: Array = [
			{"label": "通缉等级", "value": str(wanted)},
			{"label": "犯罪记录", "value": _yes_no(criminal)},
			{"label": "在押", "value": _yes_no(in_prison)},
		]
		if lg.has("release_minutes"):
			st.append({"label": "预计释放", "value": "%d 分钟" % int(lg["release_minutes"])})
		sections.append(_section("法律状态", st))
	var cases: Array = _items_of(player.get("cases", [])) + _items_of(_world(context).get("cases", []))
	if not cases.is_empty():
		sections.append(_section("案件", _rows_from(cases, ["type", "stage", "status"], name_resolver)))
	var pol: Dictionary = context.get("police", {})
	if pol.has("case"):
		var pc: Dictionary = pol["case"]
		var rows: Array = [
			{"label": "罪名", "value": String(pc.get("crime", ""))},
			{"label": "阶段", "value": String(pc.get("stage", ""))},
			{"label": "角色", "value": String(pc.get("role", ""))},
			{"label": "证据强度", "value": "%.2f" % float(pc.get("evidence_score", 0.0))},
			{"label": "线索", "value": "%.2f" % float(pc.get("leads", 0.0))},
			{"label": "程序合法度", "value": "%.2f" % float(pc.get("legality", 0.0))},
			{"label": "侦破概率", "value": "%.2f" % float(pc.get("solve_probability", 0.0))},
		]
		if bool(pc.get("wrongful", false)):
			rows.append({"label": "警示", "value": "疑似冤假错案"})
		sections.append(_section("经办案件", rows))
		var ev_rows: Array = []
		for e in (pc.get("evidence", []) as Array):
			ev_rows.append({"label": String((e as Dictionary).get("name", "")), "value": "%.2f" % float((e as Dictionary).get("value", 0.0))})
		if not ev_rows.is_empty():
			sections.append(_section("证据链", ev_rows))
	if pol.has("firm"):
		var pf: Dictionary = pol["firm"]
		sections.append(_section("安保公司", [
			{"label": "名称", "value": String(pf.get("name", ""))},
			{"label": "人手", "value": str(int(pf.get("staff", 0)))},
			{"label": "资金", "value": _money(int(pf.get("funds", 0)))},
			{"label": "声誉", "value": "%.2f" % float(pf.get("reputation", 0.0))},
		]))
		var c_rows: Array = _rows_from(_items_of(pf.get("contracts", [])), ["name", "fee", "resolved", "failure"], name_resolver)
		if not c_rows.is_empty():
			sections.append(_section("安保业务", c_rows))
	if sections.is_empty():
		return _empty("案件与法律", "暂无案件；如需可寻求法律咨询与代理")
	return _ok(sections)

static func rescue(player: Dictionary, context: Dictionary, name_resolver: Callable = Callable()) -> Dictionary:
	if player.is_empty():
		return _empty("救援与灾害", "尚未生成角色数据")
	var sections: Array = []
	var disasters: Array = _items_of(_world(context).get("disasters", []))
	if not disasters.is_empty():
		sections.append(_section("灾害态势", _rows_from(disasters, ["type", "severity", "status", "region"], name_resolver)))
	var disabilities: Array = _items_of(player.get("disabilities", []))
	if not disabilities.is_empty():
		sections.append(_section("伤残与救助", _rows_from(disabilities, ["type", "severity", "status"], name_resolver)))
	var emg: Dictionary = context.get("emergency", {})
	if emg.has("incident"):
		var ei: Dictionary = emg["incident"]
		var rows: Array = [
			{"label": "类型", "value": String(ei.get("type", ""))},
			{"label": "阶段", "value": String(ei.get("stage", ""))},
			{"label": "严重度", "value": "%.2f" % float(ei.get("severity", 0.0))},
			{"label": "响应时间", "value": "%.1f 分钟" % float(ei.get("response_minutes", -1.0))},
			{"label": "需救治", "value": str(int(ei.get("injured", 0)))},
			{"label": "死亡", "value": str(int(ei.get("deaths", 0)))},
			{"label": "获救", "value": str(int(ei.get("rescued", 0)))},
		]
		if String(ei.get("fault", "")) != "":
			rows.append({"label": "责任认定", "value": String(ei.get("fault", ""))})
		sections.append(_section("处置事件", rows))
		var tri: Dictionary = ei.get("triage", {})
		if not tri.is_empty():
			sections.append(_section("检伤分诊", [
				{"label": "已救治", "value": "%.0f" % float(tri.get("treated", 0.0))},
				{"label": "待救治", "value": "%.0f" % float(tri.get("untreated", 0.0))},
			]))
	if emg.has("org"):
		var eo: Dictionary = emg["org"]
		sections.append(_section("志愿救援队", [
			{"label": "名称", "value": String(eo.get("name", ""))},
			{"label": "志愿者", "value": str(int(eo.get("volunteers", 0)))},
			{"label": "装备", "value": str(int(eo.get("equipment", 0)))},
			{"label": "资金", "value": _money(int(eo.get("funds", 0)))},
			{"label": "声誉", "value": "%.2f" % float(eo.get("reputation", 0.0))},
		]))
	if sections.is_empty():
		return _empty("救援与灾害", "当前无灾害；可关注常态风险与应急演练")
	return _ok(sections)

static func environment(player: Dictionary, context: Dictionary, name_resolver: Callable = Callable()) -> Dictionary:
	if player.is_empty():
		return _empty("环保与碳市场", "尚未生成角色数据")
	var sections: Array = []
	var lands: Array = _items_of(player.get("lands", []))
	if not lands.is_empty():
		sections.append(_section("土地与生态", _rows_from(lands, ["kind", "area", "value"], name_resolver)))
	var env: Dictionary = context.get("environment", {})
	if env.has("city"):
		var c: Dictionary = env["city"]
		sections.append(_section("城市环保", [
			{"label": "垃圾分类率", "value": "%.2f" % float(c.get("garbage_sorting", 0.0))},
			{"label": "回收率", "value": "%.2f" % float(c.get("recycling_rate", 0.0))},
			{"label": "污水处理率", "value": "%.2f" % float(c.get("sewage_treatment", 0.0))},
			{"label": "空气质量", "value": "%.2f" % float(c.get("air_quality", 0.0))},
			{"label": "污染指数", "value": "%.2f" % float(c.get("pollution_index", 0.0))},
			{"label": "健康指数", "value": "%.2f" % float(c.get("health_index", 0.0))},
			{"label": "诉讼在办", "value": _yes_no(bool(c.get("lawsuit_open", false)))},
		]))
	if env.has("enterprise"):
		var e: Dictionary = env["enterprise"]
		sections.append(_section("企业碳账户", [
			{"label": "名称", "value": String(e.get("name", ""))},
			{"label": "排放", "value": "%.1f" % float(e.get("emissions", 0.0))},
			{"label": "配额", "value": "%.1f" % float(e.get("quota", 0.0))},
			{"label": "碳信用", "value": "%.1f" % float(e.get("credits", 0.0))},
			{"label": "碳平衡", "value": "%.1f" % float(e.get("balance", 0.0))},
			{"label": "ESG", "value": "%.1f" % float(e.get("esg", 0.0))},
			{"label": "罚款", "value": _money(int(e.get("fines", 0)))},
		]))
	if env.has("org"):
		var o: Dictionary = env["org"]
		sections.append(_section("环保组织", [
			{"label": "类型", "value": String(o.get("kind", ""))},
			{"label": "名称", "value": String(o.get("name", ""))},
			{"label": "资金", "value": _money(int(o.get("funds", 0)))},
			{"label": "声誉", "value": "%.2f" % float(o.get("reputation", 0.0))},
			{"label": "累计减排", "value": "%.1f" % float(o.get("emission_cut", 0.0))},
		]))
	if sections.is_empty():
		return _empty("环保与碳市场", "未涉猎低碳项目；可从绿色产业、减排项目或碳交易入门")
	return _ok(sections)

static func municipal(player: Dictionary, context: Dictionary, name_resolver: Callable = Callable()) -> Dictionary:
	if player.is_empty():
		return _empty("市政", "尚未生成角色数据")
	var mu: Dictionary = context.get("municipal", {})
	var sections: Array = []
	if mu.has("city"):
		var c: Dictionary = mu["city"]
		var facs: Array = _items_of(c.get("facilities", []))
		if not facs.is_empty():
			sections.append(_section("市政设施", _rows_from(facs, ["condition", "grade"], name_resolver)))
		sections.append(_section("通行与扰民", [
			{"label": "通行系数", "value": "%.2f" % float(c.get("commute_factor", 1.0))},
			{"label": "扰民度", "value": "%.2f" % float(c.get("nuisance", 0.0))},
			{"label": "未处理投诉", "value": str(int(c.get("unresolved_complaints", 0)))},
			{"label": "特许合同", "value": str(int(c.get("franchises", 0)))},
		]))
	if mu.has("hub"):
		var h: Dictionary = mu["hub"]
		sections.append(_section("邮政枢纽", [
			{"label": "待处理", "value": str(int(h.get("pending", 0)))},
			{"label": "已处理", "value": str(int(h.get("processed", 0)))},
			{"label": "丢失", "value": str(int(h.get("lost", 0)))},
			{"label": "破损", "value": str(int(h.get("damaged", 0)))},
			{"label": "累计理赔", "value": _money(int(h.get("claims_paid", 0)))},
			{"label": "爆仓程度", "value": "%.2f" % float(h.get("overload", 0.0))},
		]))
	if mu.has("courier"):
		var co: Dictionary = mu["courier"]
		sections.append(_section("快递员", [
			{"label": "姓名", "value": String(co.get("name", ""))},
			{"label": "揽投量", "value": str(int(co.get("deliveries", 0)))},
			{"label": "职级序号", "value": str(int(co.get("rank_index", 0)))},
			{"label": "月收入", "value": _money(int(co.get("income", 0)))},
			{"label": "声誉", "value": "%.2f" % float(co.get("reputation", 0.0))},
		]))
	if sections.is_empty():
		return _empty("市政", "暂无市政事项；可从市政养护、邮政快递或特许经营入门")
	return _ok(sections)

static func debt(player: Dictionary, context: Dictionary, name_resolver: Callable = Callable()) -> Dictionary:
	if player.is_empty():
		return _empty("债务与催收", "尚未生成角色数据")
	var fin: Dictionary = player.get("finances", {})
	var loans: Array = _items_of(fin.get("loans", []))
	var leases: Array = _items_of(fin.get("leases", []))
	var debt_amount: float = float(fin.get("debt", 0.0))
	var db: Dictionary = context.get("debt", {})
	var sections: Array = []
	if not db.is_empty():
		if db.has("loan"):
			var ln: Dictionary = db["loan"]
			sections.append(_section("我的借款", [
				{"label": "业务", "value": String(ln.get("business", ""))},
				{"label": "本金", "value": _money(int(ln.get("principal", 0)))},
				{"label": "剩余", "value": _money(int(ln.get("outstanding", 0)))},
				{"label": "年利率", "value": "%.2f" % float(ln.get("rate", 0.0))},
				{"label": "状态", "value": String(ln.get("status", ""))},
				{"label": "合规", "value": _yes_no(bool(ln.get("compliant", true)))},
				{"label": "套路贷", "value": _yes_no(bool(ln.get("predatory", false)))},
			]))
		if db.has("lend"):
			var le: Dictionary = db["lend"]
			sections.append(_section("我放出的贷款", [
				{"label": "业务", "value": String(le.get("business", ""))},
				{"label": "本金", "value": _money(int(le.get("principal", 0)))},
				{"label": "剩余", "value": _money(int(le.get("outstanding", 0)))},
				{"label": "年利率", "value": "%.2f" % float(le.get("rate", 0.0))},
				{"label": "状态", "value": String(le.get("status", ""))},
				{"label": "合规", "value": _yes_no(bool(le.get("compliant", true)))},
				{"label": "催收次数", "value": str(int(le.get("modes", 0)))},
				{"label": "违法催收", "value": _yes_no(bool(le.get("illegal_collection", false)))},
			]))
		if db.has("lender"):
			var ld: Dictionary = db["lender"]
			sections.append(_section("放贷人", [
				{"label": "牌照", "value": _yes_no(bool(ld.get("license", false)))},
				{"label": "违规次数", "value": str(int(ld.get("violations", 0)))},
				{"label": "声誉", "value": "%.2f" % float(ld.get("reputation", 0.0))},
			]))
		var pawns: Array = _items_of(db.get("pawns", []))
		if not pawns.is_empty():
			var prows: Array = []
			for p in pawns:
				var pd: Dictionary = p
				prows.append({"label": String(pd.get("item", "?")), "value": _money(int(pd.get("amount", 0)))})
			sections.append(_section("典当物", prows))
	if loans.is_empty() and leases.is_empty() and debt_amount <= 0.0 and sections.is_empty():
		return _empty("债务与催收", "暂无负债；当前可用信用额度 %s" % _money(fin.get("credit_limit", 0.0)))
	var overview: Array = [
		{"label": "负债总额", "value": _money(debt_amount)},
		{"label": "信用分", "value": str(int(player.get("credit_score", 0)))},
	]
	if fin.has("credit_limit"):
		overview.append({"label": "信用额度", "value": _money(fin.get("credit_limit", 0.0))})
	sections.push_front(_section("负债概览", overview))
	if not loans.is_empty():
		sections.append(_section("借款明细", _rows_from(loans, ["principal", "rate", "status", "due_minutes"], name_resolver)))
	if not leases.is_empty():
		sections.append(_section("租赁", _rows_from(leases, ["type", "amount", "status", "due_minutes"], name_resolver)))
	return _ok(sections)

static func consumer(player: Dictionary, context: Dictionary, name_resolver: Callable = Callable()) -> Dictionary:
	if player.is_empty():
		return _empty("维权与消费", "尚未生成角色数据")
	var cs: Dictionary = context.get("consumer", {})
	var sections: Array = []
	if not cs.is_empty():
		if cs.has("order"):
			var o: Dictionary = cs["order"]
			sections.append(_section("消费订单", [
				{"label": "金额", "value": _money(int(o.get("amount", 0)))},
				{"label": "类别", "value": String(o.get("category", ""))},
				{"label": "缺陷", "value": _yes_no(bool(o.get("defective", false)))},
				{"label": "假货", "value": _yes_no(bool(o.get("fake", false)))},
				{"label": "状态", "value": String(o.get("status", ""))},
				{"label": "已退款", "value": _money(int(o.get("refunded", 0)))},
				{"label": "投诉次数", "value": str(int(o.get("complaints", 0)))},
			]))
		if cs.has("product"):
			var pr: Dictionary = cs["product"]
			sections.append(_section("商品", [
				{"label": "名称", "value": String(pr.get("name", ""))},
				{"label": "价格", "value": _money(int(pr.get("price", 0)))},
				{"label": "质保天数", "value": str(int(pr.get("warranty_days", 0)))},
				{"label": "已召回", "value": _yes_no(bool(pr.get("recalled", false)))},
			]))
		if cs.has("merchant"):
			var m: Dictionary = cs["merchant"]
			sections.append(_section("涉事商家", [
				{"label": "名称", "value": String(m.get("name", ""))},
				{"label": "声誉", "value": "%.2f" % float(m.get("reputation", 0.0))},
				{"label": "销量", "value": "%.2f" % float(m.get("sales", 0.0))},
				{"label": "罚款", "value": _money(int(m.get("fines", 0)))},
				{"label": "累计赔偿", "value": _money(int(m.get("compensation_paid", 0)))},
				{"label": "已下架", "value": _yes_no(bool(m.get("delisted", false)))},
			]))
	var cases: Array = _items_of(player.get("cases", []))
	if not cases.is_empty():
		sections.append(_section("投诉与维权", _rows_from(cases, ["type", "stage", "status"], name_resolver)))
	if sections.is_empty():
		return _empty("维权与消费", "暂无投诉；遇到消费纠纷可投诉、举证并申请调解或仲裁")
	return _ok(sections)

static func welfare(player: Dictionary, context: Dictionary = {}, name_resolver: Callable = Callable()) -> Dictionary:
	if player.is_empty():
		return _empty("救助与福利", "尚未生成角色数据")
	var wf: Dictionary = context.get("welfare", {})
	var sections: Array = _welfare_sections(wf)
	if sections.is_empty():
		var level: int = int(player.get("disability_level", 0))
		var disabilities: Array = _items_of(player.get("disabilities", []))
		if level <= 0 and disabilities.is_empty():
			return _empty("救助与福利", "暂无救助资格；可申请低保/医疗救助或登记慈善基金")
		var rows: Array = [
			{"label": "残疾等级", "value": str(level)},
			{"label": "认定项", "value": str(disabilities.size())},
			{"label": "信用分", "value": str(int(player.get("credit_score", 0)))},
		]
		sections.append(_section("资格概览", rows))
	return _ok(sections)

static func _welfare_sections(wf: Dictionary) -> Array:
	var sections: Array = []
	var app: Dictionary = wf.get("application", {})
	if not app.is_empty():
		var rows: Array = [
			{"label": "申请类型", "value": String(app.get("kind_name", ""))},
			{"label": "状态", "value": "已批准" if bool(app.get("approved", false)) else "已驳回"},
		]
		if int(app.get("amount", 0)) > 0:
			rows.append({"label": "申请金额", "value": str(int(app.get("amount", 0)))})
		if int(app.get("disbursed", 0)) > 0:
			rows.append({"label": "已发放", "value": str(int(app.get("disbursed", 0)))})
		var reasons: Array = app.get("reasons", [])
		if not reasons.is_empty():
			rows.append({"label": "驳回原因", "value": ", ".join(_str_list(reasons))})
		sections.append(_section("申请与资格", rows))
	var fund: Dictionary = wf.get("fund", {})
	if not fund.is_empty():
		var frows: Array = [
			{"label": "基金", "value": String(fund.get("name", ""))},
			{"label": "结余", "value": str(int(fund.get("balance", 0)))},
			{"label": "累计募得", "value": str(int(fund.get("raised", 0)))},
			{"label": "累计支出", "value": str(int(fund.get("spent", 0)))},
			{"label": "透明度", "value": "%d%%" % int(round(float(fund.get("transparency", 0.0)) * 100.0))},
		]
		sections.append(_section("慈善基金", frows))
	var worker: Dictionary = wf.get("worker", {})
	if not worker.is_empty():
		var wrows: Array = [
			{"label": "社工", "value": String(worker.get("name", ""))},
			{"label": "累计结案", "value": str(int(worker.get("cases_closed", 0)))},
			{"label": "在办个案", "value": str(int(worker.get("active_cases", 0)))},
		]
		sections.append(_section("社工", wrows))
	var wcase: Dictionary = wf.get("case", {})
	if not wcase.is_empty():
		var crows: Array = [
			{"label": "个案编号", "value": String(wcase.get("id", ""))},
			{"label": "状态", "value": "已结案" if String(wcase.get("status", "")) == "closed" else "在办"},
			{"label": "家访次数", "value": str(int(wcase.get("visits", 0)))},
			{"label": "进展", "value": "%d%%" % int(round(float(wcase.get("progress", 0.0)) * 100.0))},
		]
		sections.append(_section("个案", crows))
	var child: Dictionary = wf.get("child", {})
	if not child.is_empty():
		sections.append(_section("变故儿童", [
			{"label": "儿童", "value": String(child.get("id", ""))},
			{"label": "安置去向", "value": _welfare_route_cn(String(child.get("route", "")))},
		]))
	return sections

static func _welfare_route_cn(route: String) -> String:
	match route:
		"kinship_care":
			return "亲属抚养"
		"institution":
			return "福利机构"
		"relief":
			return "救助体系"
		"foster":
			return "寄养家庭"
		_:
			return "未安置"

static func _str_list(items: Array) -> Array:
	var out: Array = []
	for item in items:
		out.append(String(item))
	return out

static func funeral(player: Dictionary, context: Dictionary = {}, name_resolver: Callable = Callable()) -> Dictionary:
	if player.is_empty():
		return _empty("殡葬", "尚未生成角色数据")
	var fn: Dictionary = context.get("funeral", {})
	var sections: Array = _funeral_sections(fn)
	# 遗嘱信息（若已立）。
	var will: Dictionary = player.get("will", {})
	if not will.is_empty():
		var wrows: Array = []
		if will.has("written_minutes"):
			wrows.append({"label": "立嘱时间", "value": "%d 分钟" % int(will["written_minutes"])})
		if not String(will.get("executor_id", "")).is_empty():
			wrows.append({"label": "执行人", "value": _short_id(String(will["executor_id"]))})
		wrows.append({"label": "受益人", "value": str(_items_of(will.get("beneficiaries", [])).size())})
		if will.has("notes"):
			wrows.append({"label": "备注", "value": String(will["notes"])})
		sections.append(_section("遗嘱", wrows))
	if sections.is_empty():
		return _empty("殡葬", "尚未安排殡葬；可预约殡葬服务、登记捐献与建立纪念")
	return _ok(sections)

static func _funeral_sections(fn: Dictionary) -> Array:
	var sections: Array = []
	var f: Dictionary = fn.get("funeral", {})
	if not f.is_empty():
		var rows: Array = [{"label": "方式", "value": String(f.get("method_name", ""))}]
		if not String(f.get("grave_name", "")).is_empty():
			rows.append({"label": "墓位", "value": String(f.get("grave_name", ""))})
		rows.append({"label": "费用", "value": str(int(f.get("cost", 0)))})
		rows.append({"label": "状态", "value": "已执行" if bool(f.get("executed", false)) else "已安排"})
		sections.append(_section("殡葬安排", rows))
	var d: Dictionary = fn.get("donation", {})
	if not d.is_empty():
		var drows: Array = [
			{"label": "登记", "value": "是" if bool(d.get("registered", false)) else "否"},
			{"label": "伦理审查", "value": "通过" if bool(d.get("ethics_approved", false)) else "未通过"},
			{"label": "合法有效", "value": "是" if bool(d.get("legal", false)) else "否"},
			{"label": "已撤销", "value": "是" if bool(d.get("revoked", false)) else "否"},
		]
		if (d.get("organs", []) as Array).size() > 0:
			drows.append({"label": "登记器官", "value": ", ".join(_str_list(d.get("organs", [])))})
		if int(d.get("allocated", 0)) > 0:
			drows.append({"label": "已分配", "value": str(int(d.get("allocated", 0)))})
		sections.append(_section("器官捐献", drows))
	var memorials: Array = fn.get("memorials", [])
	if not memorials.is_empty():
		var mrows: Array = []
		for m in memorials:
			mrows.append({"label": String((m as Dictionary).get("name", "")), "value": "祭扫 %d 次" % int((m as Dictionary).get("visits", 0))})
		sections.append(_section("纪念", mrows))
	var digital: Dictionary = fn.get("digital", {})
	if not digital.is_empty():
		sections.append(_section("数字纪念", [{"label": "访问", "value": str(int(digital.get("visits", 0)))}]))
	var industry: Dictionary = fn.get("industry", {})
	if not industry.is_empty():
		sections.append(_section("殡葬行业", [
			{"label": "经营体", "value": String(industry.get("name", ""))},
			{"label": "结余", "value": str(int(industry.get("balance", 0)))},
			{"label": "累计利润", "value": str(int(industry.get("profit", 0)))},
			{"label": "溢价倍数", "value": str(industry.get("price_mult", 1.0))},
		]))
	return sections


static func metaphysics(player: Dictionary, context: Dictionary, name_resolver: Callable = Callable()) -> Dictionary:
	if player.is_empty():
		return _empty("玄学", "尚未生成角色数据")
	var mt: Dictionary = context.get("metaphysics", {})
	var sections: Array = _metaphysics_sections(mt)
	var talents: Array = _items_of(player.get("talents", []))
	if not talents.is_empty():
		var rows: Array = []
		for t in talents:
			rows.append({"label": _resolve(String(t), name_resolver), "value": "具"})
		sections.append(_section("命理印记", rows))
	if sections.is_empty():
		return _empty("玄学", "未接触玄学；可算命、看风水、求护身符或开办玄学馆")
	return _ok(sections)

static func _metaphysics_sections(mt: Dictionary) -> Array:
	var sections: Array = []
	var client: Dictionary = mt.get("client", {})
	if not client.is_empty():
		var rows: Array = [
			{"label": "心情", "value": str(int(round(float(client.get("mood", 0.0)))))},
			{"label": "信念", "value": "%d%%" % int(round(float(client.get("belief", 0.0)) * 100.0))},
			{"label": "社交", "value": str(int(round(float(client.get("social", 0.0)))))},
		]
		if not String(client.get("last_consult", "")).is_empty():
			rows.append({"label": "上次求测", "value": String(client.get("last_consult", ""))})
		sections.append(_section("求测状态", rows))
	var practitioner: Dictionary = mt.get("practitioner", {})
	if not practitioner.is_empty():
		sections.append(_section("从业者", [
			{"label": "姓名", "value": String(practitioner.get("name", ""))},
			{"label": "真实能力", "value": "有" if bool(practitioner.get("real_ability", false)) else "无"},
			{"label": "诈骗", "value": "是" if bool(practitioner.get("scamming", false)) else "否"},
			{"label": "声誉", "value": "%d%%" % int(round(float(practitioner.get("reputation", 0.0)) * 100.0))},
		]))
	var business: Dictionary = mt.get("business", {})
	if not business.is_empty():
		sections.append(_section("玄学经营", [
			{"label": "名称", "value": String(business.get("name", ""))},
			{"label": "累计收入", "value": str(int(business.get("income", 0)))},
			{"label": "客流量", "value": str(int(business.get("customers", 0)))},
			{"label": "投诉", "value": str(int(business.get("complaints", 0)))},
			{"label": "举报", "value": str(int(business.get("reports", 0)))},
			{"label": "立案调查", "value": "是" if bool(business.get("under_investigation", false)) else "否"},
		]))
	return sections

static func medical(player: Dictionary, context: Dictionary = {}, name_resolver: Callable = Callable()) -> Dictionary:
	if player.is_empty():
		return _empty("医疗", "尚未生成角色数据")
	var health: Dictionary = player.get("health", {})
	var sections: Array = []
	var m: Dictionary = context.get("medical", {})
	sections.append_array(_medical_runtime_sections(m))
	var spec: Array = [
		["diseases", "疾病"], ["mental", "心理"], ["addictions", "成瘾"],
		["treatments", "治疗"], ["injuries", "外伤"],
	]
	for pair in spec:
		var list: Array = _items_of(health.get(String(pair[0]), []))
		if not list.is_empty():
			sections.append(_section(String(pair[1]), _rows_from(list, ["type", "severity", "status"], name_resolver)))
	var records: Array = _items_of(player.get("medical_records", []))
	if not records.is_empty():
		sections.append(_section("就诊记录", _rows_from(records, ["type", "status", "cost"], name_resolver)))
	if sections.is_empty():
		return _empty("医疗", "无病历；建议定期体检并保持良好作息")
	return _ok(sections)

static func _medical_runtime_sections(m: Dictionary) -> Array:
	if m.is_empty():
		return []
	var sections: Array = []
	var active: Array = m.get("active", [])
	var disease_rows: Array = [{"label": "疾病库", "value": "%d 种" % int(m.get("disease_count", 0))}]
	if active.is_empty():
		disease_rows.append({"label": "现行病程", "value": "无"})
	else:
		for name in active:
			disease_rows.append({"label": "病程", "value": String(name)})
	sections.append(_section("疾病与病程", disease_rows))
	var level_rows: Array = []
	for cl in _items_of(m.get("care_levels", [])):
		level_rows.append({"label": String((cl as Dictionary).get("name", "")), "value": String((cl as Dictionary).get("id", ""))})
	if not level_rows.is_empty():
		sections.append(_section("分级诊疗", level_rows))
	var region: Dictionary = m.get("region", {})
	sections.append(_section("区域医疗", [
		{"label": "医疗水平", "value": "%.2f" % float(region.get("medical_level", 0.0))},
		{"label": "治愈率", "value": "%d%%" % int(round(float(region.get("cure_rate", 0.0)) * 100.0))},
		{"label": "人均预期寿命", "value": "%.1f 岁" % float(region.get("life_expectancy", 0.0))},
	]))
	var high: Array = []
	for h in _items_of(m.get("high_end", [])):
		high.append({"label": String((h as Dictionary).get("name", "")), "value": "可开展"})
	if not high.is_empty():
		sections.append(_section("高阶医疗", high))
	if m.get("pharma", null) is Dictionary:
		var ph: Dictionary = m.get("pharma", {})
		sections.append(_section("医药产业", [
			{"label": "公司", "value": String(ph.get("name", ""))},
			{"label": "资金", "value": str(int(ph.get("money", 0)))},
			{"label": "在研药物", "value": str(int(ph.get("drugs", 0)))},
			{"label": "丑闻", "value": "有" if bool(ph.get("scandal", false)) else "无"},
		]))
	return sections

static func mental(player: Dictionary, context: Dictionary, name_resolver: Callable = Callable()) -> Dictionary:
	if player.is_empty():
		return _empty("精神健康", "尚未生成角色数据")
	var d: Dictionary = context.get("mental", {}) if context.get("mental") is Dictionary else {}
	if d.is_empty():
		return _empty("精神健康", "暂无心理状态；随生活起伏情绪与病程会在此呈现")
	var sections: Array = []
	sections.append({
		"title": "情绪与幸福",
		"rows": [
			{"label": "情绪", "value": String(d.get("emotion", "平静"))},
			{"label": "心情", "value": _num(d.get("mood", 0.0))},
			{"label": "压力", "value": _num(d.get("stress", 0.0))},
			{"label": "幸福", "value": _num(d.get("happiness", 0.0))},
			{"label": "意义感", "value": _num(d.get("meaning", 0.0))},
		],
	})
	var dims: Array = d.get("dims", [])
	if not dims.is_empty():
		sections.append(_section("大五人格", dims))
	var tags: Array = d.get("tags", [])
	if not tags.is_empty():
		var rows: Array = []
		for t in tags:
			rows.append({"label": "标签", "value": String(t)})
		sections.append({"title": "性格标签", "rows": rows})
	var cases: Array = d.get("cases", [])
	if not cases.is_empty():
		sections.append(_section("精神疾病病程", cases))
	else:
		sections.append({"title": "精神疾病病程", "rows": [{"label": "状态", "value": "暂无记录"}]})
	return _ok(sections)

static func spirit(player: Dictionary, context: Dictionary, name_resolver: Callable = Callable()) -> Dictionary:
	if player.is_empty():
		return _empty("精神追求", "尚未生成角色数据")
	var d: Dictionary = context.get("spirit", {}) if context.get("spirit") is Dictionary else {}
	if d.is_empty():
		return _empty("精神追求", "暂无精神追求记录；可通过修持、皈依与省思塑造内心世界")
	var sections: Array = []
	var axes: Array = d.get("axes", [])
	if not axes.is_empty():
		sections.append(_section("价值观三轴", axes))
	var faith_rows: Array = []
	if bool(d.get("has_faith", false)):
		faith_rows.append({"label": "信仰", "value": String(d.get("faith", ""))})
		faith_rows.append({"label": "修持境界", "value": "%s · 累计%.1f小时" % [
			String(d.get("faith_realm", "")), float(d.get("faith_depth", 0.0))]})
	else:
		faith_rows.append({"label": "信仰", "value": "未皈依"})
	sections.append({"title": "信仰与修持", "rows": faith_rows})
	var pursuits: Array = d.get("pursuits", [])
	if not pursuits.is_empty():
		sections.append(_section("精神追求", pursuits))
	else:
		sections.append({"title": "精神追求", "rows": [{"label": "状态", "value": "尚未开始任何修持"}]})
	var crisis := String(d.get("crisis", ""))
	if not crisis.is_empty():
		var exits: Array = d.get("crisis_exits", [])
		var names: Array = []
		for e in exits:
			names.append(String((e as Dictionary).get("name", "")))
		sections.append({"title": "精神危机", "rows": [
			{"label": "当前危机", "value": _crisis_name(crisis)},
			{"label": "可选出口", "value": "、".join(names) if not names.is_empty() else "—"},
		]})
	else:
		sections.append({"title": "精神危机", "rows": [{"label": "状态", "value": "心境安稳"}]})
	return _ok(sections)

static func language(player: Dictionary, context: Dictionary, name_resolver: Callable = Callable()) -> Dictionary:
	if player.is_empty():
		return _empty("语言与文化", "尚未生成角色数据")
	var d: Dictionary = context.get("language", {}) if context.get("language") is Dictionary else {}
	if d.is_empty():
		return _empty("语言与文化", "暂无语言档案；可学习外语、参加考试或适应当地文化")
	var sections: Array = []
	var langs: Array = _items_of(d.get("languages", []))
	var lrows: Array = []
	for l in langs:
		if not (l is Dictionary):
			continue
		var ld: Dictionary = l
		lrows.append({
			"label": "%s（综合 %.0f）" % [String(ld.get("name", "?")), float(ld.get("overall", 0.0))],
			"value": "口语 %.0f · 听力 %.0f · 读写 %.0f" % [
				float(ld.get("speaking", 0.0)), float(ld.get("listening", 0.0)), float(ld.get("literacy", 0.0))],
		})
	if not lrows.is_empty():
		sections.append(_section("语言能力", lrows))
	var certs: Array = _items_of(d.get("certificates", []))
	if not certs.is_empty():
		sections.append(_section("语言证书", certs))
	var cults: Array = _items_of(d.get("cultures", []))
	var crows: Array = []
	for c in cults:
		if not (c is Dictionary):
			continue
		var cd: Dictionary = c
		crows.append({"label": String(cd.get("name", "?")), "value": "适应度 %.0f%%" % (float(cd.get("adaptation", 0.0)) * 100.0)})
	if not crows.is_empty():
		crows.append({"label": "文化冲击", "value": "%.0f%%" % (float(d.get("shock", 0.0)) * 100.0)})
		sections.append(_section("文化适应", crows))
	var fest: Dictionary = d.get("festival", {}) if d.get("festival") is Dictionary else {}
	var frows: Array = []
	if bool(fest.get("is_festival", false)):
		var names: Array = []
		for f in _items_of(fest.get("festivals", [])):
			names.append(String((f as Dictionary).get("name", "")))
		frows.append({"label": "今日节日", "value": "、".join(names)})
		frows.append({"label": "衣食住行", "value": "商铺%s · 交通×%.1f · 社交×%.1f · 消费×%.1f" % [
			"开市" if bool(fest.get("shops_open", true)) else "歇业",
			float(fest.get("traffic", 1.0)), float(fest.get("social", 1.0)), float(fest.get("spending", 1.0))]})
	else:
		frows.append({"label": "今日", "value": "非节日"})
	sections.append(_section("节日民俗", frows))
	return _ok(sections)

static func disability(player: Dictionary, context: Dictionary, name_resolver: Callable = Callable()) -> Dictionary:
	if player.is_empty():
		return _empty("残障与养老", "尚未生成角色数据")
	var d: Dictionary = context.get("disability", {}) if context.get("disability") is Dictionary else {}
	if d.is_empty():
		return _empty("残障与养老", "暂无残障/养老记录；如遇伤病致残可申领辅具、康复训练与养老照护")
	var sections: Array = []
	var conds: Array = _items_of(d.get("conditions", []))
	var crows: Array = []
	for c in conds:
		if not (c is Dictionary):
			continue
		var cd: Dictionary = c
		crows.append({"label": "%s · %s" % [String(cd.get("type", "?")), String(cd.get("severity", ""))], "value": "来源%s" % String(cd.get("source", ""))})
	if not crows.is_empty():
		crows.append({"label": "移动能力", "value": "%.0f%%" % (float(d.get("mobility", 1.0)) * 100.0)})
		sections.append(_section("残障状态", crows))
	var devices: Array = _items_of(d.get("devices", []))
	var drows: Array = []
	for dev in devices:
		if dev is Dictionary:
			drows.append({"label": String((dev as Dictionary).get("name", "?")), "value": "已装配"})
	drows.append({"label": "康复进度", "value": "%.0f%%" % (float(d.get("recovery", 0.0)) * 100.0)})
	drows.append({"label": "无障碍改造", "value": "已改造" if bool(d.get("accessible", false)) else "未改造"})
	sections.append(_section("辅具与康复", drows))
	var erows: Array = []
	erows.append({"label": "社保年限", "value": "%.1f 年" % float(d.get("retirement_years", 0.0))})
	erows.append({"label": "养老模式", "value": String(d.get("care_mode", "")) if String(d.get("care_mode", "")) != "" else "未选择"})
	if String(d.get("care_mode", "")) != "":
		erows.append({"label": "照护质量", "value": "%.0f%%" % (float(d.get("care_quality", 0.0)) * 100.0)})
	if bool(d.get("hospice", false)):
		erows.append({"label": "临终关怀", "value": "已安排"})
	sections.append(_section("养老与社保", erows))
	var grows: Array = []
	grows.append({"label": "认知障碍", "value": "有" if bool(d.get("cognitive", false)) else "无"})
	grows.append({"label": "决策能力", "value": "具备" if bool(d.get("decision_capacity", true)) else "丧失"})
	grows.append({"label": "遗嘱效力", "value": "有效" if bool(d.get("will_valid", true)) else "无效（需监护追认）"})
	if String(d.get("guardian", "")) != "":
		grows.append({"label": "监护人", "value": String(d.get("guardian", ""))})
	sections.append(_section("监护与决策", grows))
	return _ok(sections)

static func agriculture(player: Dictionary, context: Dictionary, name_resolver: Callable = Callable()) -> Dictionary:
	if player.is_empty():
		return _empty("农业与乡土", "尚未生成角色数据")
	var d: Dictionary = context.get("agriculture", {}) if context.get("agriculture") is Dictionary else {}
	if d.is_empty():
		return _empty("农业与乡土", "暂无农事记录；可承包/购买土地、播种、养殖与售卖农产")
	var sections: Array = []
	var lands: Array = _items_of(d.get("lands", []))
	var lrows: Array = []
	for l in lands:
		if l is Dictionary:
			var ld: Dictionary = l
			lrows.append({"label": "%s %.1f 亩（%s）" % [String(ld.get("use", "?")), float(ld.get("area", 0.0)), String(ld.get("id", ""))], "value": "地力 %.0f%% · 估值 %d" % [float(ld.get("fertility", 0.0)) * 100.0, int(ld.get("value", 0))]})
	if not lrows.is_empty():
		sections.append(_section("土地", lrows))
	var plots: Array = _items_of(d.get("plots", []))
	var prows: Array = []
	for p in plots:
		if p is Dictionary:
			var pd: Dictionary = p
			prows.append({"label": String(pd.get("name", "?")), "value": "%s · %.0f/%.0f 天" % [String(pd.get("stage", "")), float(pd.get("elapsed", 0.0)), float(pd.get("growth_days", 0.0))]})
	if not prows.is_empty():
		sections.append(_section("在田作物", prows))
	var livestock: Array = _items_of(d.get("livestock", []))
	var vrows: Array = []
	for a in livestock:
		if a is Dictionary:
			var ad: Dictionary = a
			vrows.append({"label": String(ad.get("name", "?")), "value": "%d 头/只" % int(ad.get("count", 0))})
	if not vrows.is_empty():
		sections.append(_section("养殖", vrows))
	var inventory: Array = _items_of(d.get("inventory", []))
	var irows: Array = []
	for it in inventory:
		if it is Dictionary:
			var id: Dictionary = it
			irows.append({"label": String(id.get("name", "?")), "value": "%.1f" % float(id.get("count", 0.0))})
	if not irows.is_empty():
		sections.append(_section("仓储", irows))
	var mrows: Array = []
	mrows.append({"label": "农场资金", "value": "%d" % int(d.get("money", 0))})
	mrows.append({"label": "土地估值", "value": "%d" % int(d.get("land_value", 0))})
	mrows.append({"label": "本年收入", "value": "%d" % int(d.get("year_income", 0))})
	mrows.append({"label": "累计补贴", "value": "%.0f" % float(d.get("subsidy", 0.0))})
	if String(d.get("coop", "")) != "":
		mrows.append({"label": "合作社", "value": String(d.get("coop", ""))})
	sections.append(_section("经营概况", mrows))
	var prim: Dictionary = d.get("primary", {}) if d.get("primary") is Dictionary else {}
	if not prim.is_empty():
		sections.append_array(_primary_sections(prim))
	return _ok(sections)

## 农林牧渔分区：渔场、林场、狩猎、生态。
static func _primary_sections(prim: Dictionary) -> Array:
	var sections: Array = []
	var fishery: Dictionary = prim.get("fishery", {}) if prim.get("fishery") is Dictionary else {}
	if not fishery.is_empty():
		sections.append(_section("渔场", [
			{"label": "渔船", "value": "%d 艘" % int(fishery.get("boats", 0))},
			{"label": "资源比例", "value": "%.2f" % float(fishery.get("resource_ratio", 1.0))},
			{"label": "休渔", "value": ("进行中（余 %.0f 天）" % float(fishery.get("closed_days_left", 0.0))) if bool(fishery.get("closed_season", false)) else "未休渔"},
		]))
	var forest: Dictionary = prim.get("forest", {}) if prim.get("forest") is Dictionary else {}
	if not forest.is_empty():
		sections.append(_section("林场", [
			{"label": "林分", "value": String(forest.get("forest_type_name", ""))},
			{"label": "面积", "value": "%.0f 亩" % float(forest.get("area", 0.0))},
			{"label": "林木", "value": "%.0f 株" % float(forest.get("trees", 0.0))},
			{"label": "木材", "value": "%.1f" % float(forest.get("wood", 0.0))},
			{"label": "火灾风险", "value": "%.2f" % float(forest.get("fire_risk", 0.0))},
		]))
	var hunter: Dictionary = prim.get("hunter", {}) if prim.get("hunter") is Dictionary else {}
	if not hunter.is_empty():
		sections.append(_section("狩猎", [
			{"label": "狩猎许可", "value": ("已取得" if bool(hunter.get("license", false)) else "未取得")},
			{"label": "通缉等级", "value": str(int(hunter.get("wanted_level", 0)))},
			{"label": "资金", "value": str(int(hunter.get("money", 0)))},
		]))
	var ecology: Dictionary = prim.get("ecology", {}) if prim.get("ecology") is Dictionary else {}
	if not ecology.is_empty():
		sections.append(_section("生态", [
			{"label": "资源比例", "value": "%.2f" % float(ecology.get("resource_ratio", 1.0))},
			{"label": "土壤质量", "value": "%.2f" % float(ecology.get("soil_quality", 1.0))},
			{"label": "水土流失", "value": "%.2f" % float(ecology.get("erosion", 0.0))},
		]))
	return sections

static func late_tech(player: Dictionary, context: Dictionary, name_resolver: Callable = Callable()) -> Dictionary:
	if player.is_empty():
		return _empty("后期科技", "尚未生成角色数据")
	var d: Dictionary = context.get("late_tech", {}) if context.get("late_tech") is Dictionary else {}
	if d.is_empty():
		return _empty("后期科技", "科技尚未演进；可解锁信息/智能/星际阶段并应聘新职业")
	var sections: Array = []
	var stage_name: String = String(d.get("stage_name", d.get("stage", "?")))
	var orows: Array = [
		{"label": "当前科技阶段", "value": stage_name},
		{"label": "阶段序号", "value": str(int(d.get("stage_index", 0)) + 1)},
		{"label": "失业率", "value": "%.1f%%" % (float(d.get("unemployment_rate", 0.0)) * 100.0)},
		{"label": "延寿加成", "value": "%.1f 年" % float(d.get("lifespan_bonus", 0.0))},
	]
	var jobs: Array = _items_of(d.get("jobs", []))
	if not jobs.is_empty():
		orows.append({"label": "新兴岗位", "value": ", ".join(PackedStringArray(_to_strings(jobs)))})
	var places: Array = _items_of(d.get("places", []))
	if not places.is_empty():
		orows.append({"label": "新场所", "value": ", ".join(PackedStringArray(_to_strings(places)))})
	sections.append(_section("科技阶段", orows))
	var careers: Array = _items_of(d.get("careers", []))
	var crows: Array = []
	for c in careers:
		if c is Dictionary:
			var cd: Dictionary = c
			var state: String = "可应聘" if bool(cd.get("unlocked", false)) else "未解锁"
			crows.append({"label": String(cd.get("name", "?")), "value": "%s · 门槛 %d · 薪资 %d" % [state, int(cd.get("min_level", 0)), int(cd.get("salary", 0))]})
	if not crows.is_empty():
		sections.append(_section("科技职业", crows))
	var missions: Array = _items_of(d.get("missions", []))
	var mrows: Array = []
	for m in missions:
		if m is Dictionary:
			var md: Dictionary = m
			mrows.append({"label": String(md.get("name", "?")), "value": "技能 %d · 报酬 %d" % [int(md.get("min_skill", 0)), int(md.get("reward", 0))]})
	if not mrows.is_empty():
		sections.append(_section("高风险任务", mrows))
	return _ok(sections)

static func _to_strings(items: Array) -> Array:
	var out: Array = []
	for it in items:
		if it is Dictionary:
			out.append(String((it as Dictionary).get("name", (it as Dictionary).get("id", "?"))))
		else:
			out.append(String(it))
	return out

static func ip_media(player: Dictionary, context: Dictionary, name_resolver: Callable = Callable()) -> Dictionary:
	if player.is_empty():
		return _empty("知识产权与媒体", "尚未生成角色数据")
	var d: Dictionary = context.get("ip_media", {}) if context.get("ip_media") is Dictionary else {}
	var ips: Array = _items_of(d.get("ips", []))
	var outlets: Array = _items_of(d.get("outlets", []))
	if ips.is_empty() and outlets.is_empty():
		return _empty("知识产权与媒体", "尚无 IP 或媒体机构；可登记版权/专利/商标或开办出版社/影视公司")
	var sections: Array = []
	if not ips.is_empty():
		var irows: Array = []
		for it in ips:
			if it is Dictionary:
				var id: Dictionary = it
				var status: String = "已到期(公有领域)" if bool(id.get("public_domain", false)) else ("已质押" if bool(id.get("pledged", false)) else String(id.get("status", "")))
				irows.append({"label": "%s（%s）" % [String(id.get("title", "?")), String(id.get("type_name", ""))], "value": "%s · 授权 %d 次" % [status, int(id.get("licenses", 0))]})
		sections.append(_section("知识产权", irows))
	if not outlets.is_empty():
		var orows: Array = []
		for ot in outlets:
			if ot is Dictionary:
				var od: Dictionary = ot
				orows.append({"label": "%s（%s）" % [String(od.get("name", "?")), String(od.get("type_name", ""))], "value": "声誉 %.0f%% · 现金 %d · 作品 %d" % [float(od.get("reputation", 0.0)) * 100.0, int(od.get("cash", 0)), int(od.get("works", 0))]})
		sections.append(_section("媒体机构", orows))
	return _ok(sections)

static func _crisis_name(key: String) -> String:
	const NAMES: Dictionary = {
		"midlife_crisis": "中年危机", "meaning_loss": "意义丧失",
		"faith_crisis": "信仰动摇", "existential_anxiety": "存在焦虑",
	}
	return String(NAMES.get(key, key))

static func content_industry(player: Dictionary, context: Dictionary = {}, name_resolver: Callable = Callable()) -> Dictionary:
	if player.is_empty():
		return _empty("文娱", "尚未生成角色数据")
	var sections: Array = []
	var c: Dictionary = context.get("content", {})
	sections.append_array(_content_runtime_sections(c))
	var ips: Array = _items_of(_world(context).get("ips", []))
	if not ips.is_empty():
		sections.append(_section("作品与版权", _rows_from(ips, ["type", "status", "royalty", "rating"], name_resolver)))
	if sections.is_empty():
		return _empty("文娱", "尚无作品；可开办工作室、立项创作并发行变现")
	return _ok(sections)

static func _content_runtime_sections(c: Dictionary) -> Array:
	if c.is_empty():
		return []
	var sections: Array = []
	var studio: Dictionary = c.get("studio", {})
	var stage: String = String(studio.get("financing_stage", ""))
	sections.append(_section("工作室", [
		{"label": "名称", "value": String(studio.get("name", ""))},
		{"label": "资金", "value": str(int(studio.get("money", 0)))},
		{"label": "声誉", "value": "%.0f%%" % (float(studio.get("reputation", 0.0)) * 100.0)},
		{"label": "团队", "value": "%d 人" % int(studio.get("team_size", 0))},
		{"label": "融资", "value": stage if not stage.is_empty() else "未融资"},
	]))
	var team: Array = _items_of(c.get("team", []))
	if not team.is_empty():
		var team_rows: Array = []
		for t in team:
			team_rows.append({"label": String((t as Dictionary).get("name", "")), "value": "%d 人 · 技能 %.0f%%" % [int((t as Dictionary).get("count", 0)), float((t as Dictionary).get("skill", 0.0)) * 100.0]})
		sections.append(_section("创作团队", team_rows))
	if c.get("work", null) is Dictionary:
		var w: Dictionary = c.get("work", {})
		sections.append(_section("在研作品", [
			{"label": "标题", "value": String(w.get("title", ""))},
			{"label": "类型", "value": String(w.get("type_name", ""))},
			{"label": "进度", "value": "%.0f/%.0f" % [float(w.get("progress", 0.0)), float(w.get("required", 1.0))]},
			{"label": "质量", "value": "%.0f%%" % (float(w.get("quality", 0.0)) * 100.0)},
			{"label": "状态", "value": String(w.get("status", ""))},
			{"label": "收入", "value": str(int(w.get("revenue", 0)))},
			{"label": "争议", "value": "%.0f%%" % (float(w.get("controversy", 0.0)) * 100.0)},
		]))
	var works: Array = _items_of(c.get("works", []))
	if not works.is_empty():
		var work_rows: Array = []
		for wk in works:
			work_rows.append({"label": String((wk as Dictionary).get("title", "")), "value": "质量 %.0f%% · 表现 %.0f%%" % [float((wk as Dictionary).get("quality", 0.0)) * 100.0, float((wk as Dictionary).get("performance", 0.0)) * 100.0]})
		sections.append(_section("发行作品", work_rows))
	var ip_list: Array = _items_of(c.get("ips", []))
	if not ip_list.is_empty():
		var ip_rows: Array = []
		for ip in ip_list:
			ip_rows.append({"label": String((ip as Dictionary).get("title", "")), "value": "势能 %.0f%% · 改编 %d" % [float((ip as Dictionary).get("power", 0.0)) * 100.0, int((ip as Dictionary).get("adaptations", 0))]})
		sections.append(_section("IP 库", ip_rows))
	var fan: Dictionary = c.get("fandom", {})
	if not fan.is_empty():
		sections.append(_section("粉丝文化", [
			{"label": "粉丝规模", "value": str(int(fan.get("size", 0)))},
			{"label": "毒性", "value": "%.0f%%" % (float(fan.get("toxicity", 0.0)) * 100.0)},
		]))
	return sections

static func engineering(player: Dictionary, context: Dictionary, name_resolver: Callable = Callable()) -> Dictionary:
	if player.is_empty():
		return _empty("工程与基建", "尚未生成角色数据")
	var sections: Array = []
	var e: Dictionary = context.get("engineering", {})
	sections.append_array(_engineering_runtime_sections(e))
	var projects: Array = _items_of(_world(context).get("projects", []))
	if not projects.is_empty():
		sections.append(_section("在建工程", _rows_from(projects, ["type", "stage", "progress", "budget"], name_resolver)))
	if sections.is_empty():
		return _empty("工程与基建", "暂无工程；可办工程公司、承接工程并推进链条")
	return _ok(sections)

static func _engineering_runtime_sections(e: Dictionary) -> Array:
	if e.is_empty():
		return []
	var sections: Array = []
	var c: Dictionary = e.get("contractor", {}) if e.get("contractor", null) is Dictionary else {}
	if not c.is_empty():
		sections.append(_section("施工单位", [
			{"label": "名称", "value": String(c.get("name", ""))},
			{"label": "资质", "value": String(c.get("qualification", ""))},
			{"label": "资本", "value": str(int(c.get("capital", 0)))},
			{"label": "工艺", "value": "%.0f%%" % (float(c.get("workmanship", 0.0)) * 100.0)},
			{"label": "声誉", "value": "%.0f%%" % (float(c.get("reputation", 0.0)) * 100.0)},
		]))
	var p: Dictionary = e.get("project", {}) if e.get("project", null) is Dictionary else {}
	if not p.is_empty():
		var status: String = "已验收" if bool(p.get("accepted", false)) else ("事故" if bool(p.get("accident", false)) else "进行中")
		sections.append(_section("在建工程", [
			{"label": "名称", "value": String(p.get("name", ""))},
			{"label": "阶段", "value": String(p.get("stage_name", p.get("stage", "")))},
			{"label": "进度", "value": "%.0f%%" % (float(p.get("progress", 0.0)) * 100.0)},
			{"label": "质量", "value": "%.0f%%" % (float(p.get("quality", 0.0)) * 100.0)},
			{"label": "预算", "value": str(int(p.get("budget", 0)))},
			{"label": "状态", "value": status},
		]))
	var city: Dictionary = e.get("city", {}) if e.get("city", null) is Dictionary else {}
	if not city.is_empty():
		sections.append(_section("城市规划", [
			{"label": "名称", "value": String(city.get("name", ""))},
			{"label": "人口", "value": str(int(city.get("population", 0)))},
			{"label": "地价", "value": "%.0f" % float(city.get("land_price", 0.0))},
			{"label": "交通", "value": "%.0f%%" % (float(city.get("traffic", 0.0)) * 100.0)},
		]))
		var zones: Array = _items_of(city.get("zones", []))
		if not zones.is_empty():
			var zone_rows: Array = []
			for z in zones:
				zone_rows.append({"label": String((z as Dictionary).get("zone", "")), "value": "%s · 地价 %.0f" % [String((z as Dictionary).get("type_name", "")), float((z as Dictionary).get("land_price", 0.0))]})
			sections.append(_section("功能区", zone_rows))
	var d: Dictionary = e.get("developer", {}) if e.get("developer", null) is Dictionary else {}
	if not d.is_empty():
		sections.append(_section("房地产", [
			{"label": "公司", "value": String(d.get("name", ""))},
			{"label": "现金", "value": str(int(d.get("cash", 0)))},
			{"label": "负债", "value": str(int(d.get("debt", 0)))},
		]))
	return sections

static func services(player: Dictionary, context: Dictionary, name_resolver: Callable = Callable()) -> Dictionary:
	if player.is_empty():
		return _empty("专业与生活服务", "尚未生成角色数据")
	var sections: Array = []
	sections.append_array(_professional_runtime_sections(context.get("professional", {})))
	sections.append_array(_life_service_runtime_sections(context.get("life_services", {})))
	var orders: Array = _items_of(player.get("orders", []))
	if not orders.is_empty():
		sections.append(_section("服务单", _rows_from(orders, ["type", "status", "amount", "rating"], name_resolver)))
	if sections.is_empty():
		return _empty("专业与生活服务", "暂无服务单；可开事务所、承接项目，或预约维修、家政、搬家")
	return _ok(sections)

static func _professional_runtime_sections(p: Dictionary) -> Array:
	if p.is_empty():
		return []
	var sections: Array = []
	var f: Dictionary = p.get("firm", {}) if p.get("firm", null) is Dictionary else {}
	if not f.is_empty():
		var quals: Array = f.get("qualifications", [])
		sections.append(_section("专业事务所", [
			{"label": "名称", "value": String(f.get("name", ""))},
			{"label": "资金", "value": str(int(f.get("money", 0)))},
			{"label": "声誉", "value": "%.0f%%" % (float(f.get("reputation", 0.0)) * 100.0)},
			{"label": "资质", "value": "、".join(PackedStringArray(_str_list(quals))) if not quals.is_empty() else "无"},
			{"label": "合伙人", "value": str(int(f.get("partners", 0)))},
			{"label": "客户", "value": str(int(f.get("clients", 0)))},
			{"label": "违规", "value": str(int(f.get("violations", 0)))},
			{"label": "项目", "value": str(int(f.get("projects", 0)))},
		]))
	var pj: Dictionary = p.get("project", {}) if p.get("project", null) is Dictionary else {}
	if not pj.is_empty():
		sections.append(_section("立项项目", [
			{"label": "类型", "value": String(pj.get("practice_name", pj.get("practice", "")))},
			{"label": "费用", "value": str(int(pj.get("fee", 0)))},
			{"label": "状态", "value": String(pj.get("status", ""))},
			{"label": "发现", "value": str(int(pj.get("findings", 0)))},
		]))
	return sections

static func _life_service_runtime_sections(p: Dictionary) -> Array:
	if p.is_empty():
		return []
	var sections: Array = []
	var pr: Dictionary = p.get("provider", {}) if p.get("provider", null) is Dictionary else {}
	if not pr.is_empty():
		sections.append(_section("生活服务者", [
			{"label": "名称", "value": String(pr.get("name", ""))},
			{"label": "类别", "value": String(pr.get("category_name", pr.get("category", "")))},
			{"label": "评分", "value": "%.0f%%" % (float(pr.get("rating", 0.0)) * 100.0)},
			{"label": "信任", "value": "%.0f%%" % (float(pr.get("trust", 0.0)) * 100.0)},
			{"label": "背景", "value": String(pr.get("background", "unknown"))},
			{"label": "订单", "value": str(int(pr.get("orders", 0)))},
			{"label": "纠纷", "value": str(int(pr.get("disputes", 0)))},
		]))
	var od: Dictionary = p.get("order", {}) if p.get("order", null) is Dictionary else {}
	if not od.is_empty():
		sections.append(_section("服务单", [
			{"label": "服务", "value": String(od.get("service", ""))},
			{"label": "价格", "value": str(int(od.get("price", 0)))},
			{"label": "状态", "value": String(od.get("status", ""))},
		]))
	return sections

static func transport_infra(player: Dictionary, context: Dictionary, name_resolver: Callable = Callable()) -> Dictionary:
	if player.is_empty():
		return _empty("交通基建", "尚未生成角色数据")
	var sections: Array = []
	sections.append_array(_transport_infra_runtime_sections(context.get("transport_infra", {})))
	var trips: Array = _items_of(player.get("itineraries", [])) + _items_of(_world(context).get("itineraries", []))
	if not trips.is_empty():
		sections.append(_section("行程与线路", _rows_from(trips, ["type", "status", "amount", "arrive_minutes"], name_resolver)))
	if sections.is_empty():
		return _empty("交通基建", "暂无线路权限；可立项公路/铁路/港口并运营")
	return _ok(sections)

static func _transport_infra_runtime_sections(t: Dictionary) -> Array:
	if t.is_empty():
		return []
	var sections: Array = []
	var p: Dictionary = t.get("project", {}) if t.get("project", null) is Dictionary else {}
	if not p.is_empty():
		sections.append(_section("基建项目", [
			{"label": "类型", "value": String(p.get("type_name", p.get("type", "")))},
			{"label": "预算", "value": str(int(p.get("cost_estimate", 0)))},
			{"label": "已投入", "value": str(int(p.get("spent", 0)))},
			{"label": "进度", "value": "%.0f%%" % (float(p.get("progress", 0.0)) * 100.0)},
			{"label": "工期", "value": "%.0f 天" % (float(p.get("days_total", 0.0)) + float(p.get("delayed_days", 0.0)))},
			{"label": "状态", "value": String(p.get("status", ""))},
			{"label": "补贴", "value": str(int(p.get("subsidy", 0)))},
			{"label": "事故", "value": "有" if bool(p.get("accident", false)) else "无"},
		]))
	var r: Dictionary = t.get("route", {}) if t.get("route", null) is Dictionary else {}
	if not r.is_empty():
		sections.append(_section("运营线路", [
			{"label": "模式", "value": String(r.get("mode_name", r.get("mode", "")))},
			{"label": "票价", "value": "%.0f" % float(r.get("fare", 0.0))},
			{"label": "盈亏", "value": str(int(r.get("profit", 0)))},
			{"label": "准点率", "value": "%.0f%%" % (float(r.get("on_time_rate", 0.0)) * 100.0)},
			{"label": "状态", "value": "中断" if bool(r.get("suspended", false)) else "正常"},
		]))
	var rg: Dictionary = t.get("region", {}) if t.get("region", null) is Dictionary else {}
	if not rg.is_empty():
		sections.append(_section("区域影响", [
			{"label": "可达性", "value": "%.0f%%" % (float(rg.get("accessibility", 0.0)) * 100.0)},
			{"label": "地价", "value": "%.0f" % float(rg.get("land_price", 0.0))},
			{"label": "GDP", "value": "%.0f" % float(rg.get("gdp", 0.0))},
			{"label": "人口", "value": "%.0f" % float(rg.get("population", 0.0))},
		]))
	return sections

static func household(player: Dictionary, name_resolver: Callable = Callable()) -> Dictionary:
	if player.is_empty():
		return _empty("家庭与宠物", "尚未生成角色数据")
	var fam: Dictionary = player.get("family", {})
	var pets: Array = _items_of(player.get("pets", []))
	var sections: Array = []
	if not fam.is_empty():
		var rows: Array = [
			{"label": "子女", "value": str(_items_of(fam.get("children_ids", [])).size())},
			{"label": "父母", "value": str(_items_of(fam.get("parent_ids", [])).size())},
			{"label": "兄弟姐妹", "value": str(_items_of(fam.get("sibling_ids", [])).size())},
			{"label": "养子女", "value": str(_items_of(fam.get("adopted_ids", [])).size())},
		]
		if not (fam.get("guardian_ids", []) as Array).is_empty():
			rows.append({"label": "指定监护人", "value": str((fam.get("guardian_ids", []) as Array).size())})
		sections.append(_section("家庭成员", rows))
	if not pets.is_empty():
		var prow_rows: Array = []
		for p in pets:
			if not (p is Dictionary):
				continue
			var pname: String = String(p.get("name", ""))
			if pname == "":
				pname = String(p.get("species", p.get("content_key", "宠物")))
			var status: String = "已离世" if not bool(p.get("alive", true)) else ("走失" if bool(p.get("lost", false)) else "在世")
			prow_rows.append({
				"label": pname,
				"value": "%s · %d 岁 · 健康 %s · 心情 %s · 亲近 %s" % [
					status, int(p.get("age", 0)), _num(p.get("health", 0.0)),
					_num(p.get("mood", 0.0)), _num(p.get("bond", 0.0)),
				],
			})
		sections.append(_section("宠物", prow_rows))
	if sections.is_empty():
		return _empty("家庭与宠物", "尚无家庭或宠物；可建立关系、领养并照护")
	return _ok(sections)

static func sports(player: Dictionary, context: Dictionary, name_resolver: Callable = Callable()) -> Dictionary:
	if player.is_empty():
		return _empty("体育", "尚未生成角色数据")
	var sections: Array = []
	var items: Array = _items_of(_world(context).get("sports", []))
	if not items.is_empty():
		sections.append(_section("赛事与球队", _rows_from(items, ["type", "teams", "status", "score"], name_resolver)))
	var my: Dictionary = context.get("sports", {}) if context.get("sports") is Dictionary else {}
	if not my.is_empty():
		sections.append_array(_sports_sections(my))
	if sections.is_empty():
		return _empty("体育", "未涉猎体育；可用「开启球涯」成为职业运动员")
	return _ok(sections)

static func events_panel(player: Dictionary, context: Dictionary, name_resolver: Callable = Callable()) -> Dictionary:
	if player.is_empty():
		return _empty("活动与展会", "尚未生成角色数据")
	var sections: Array = []
	var items: Array = _items_of(_world(context).get("world_events", []))
	if not items.is_empty():
		sections.append(_section("活动与展会", _rows_from(items, ["type", "status", "start_minutes", "venue"], name_resolver)))
	var my: Dictionary = context.get("events", {}) if context.get("events") is Dictionary else {}
	if not my.is_empty():
		sections.append_array(_events_sections(my))
	if sections.is_empty():
		return _empty("活动与展会", "暂无活动；可用「办活动 <类型>」策划并举办")
	return _ok(sections)

## 我的活动分区：活动概况、策划职业。
static func _events_sections(ev: Dictionary) -> Array:
	var sections: Array = []
	if String(ev.get("type", "")) != "":
		sections.append(_section("我的活动", [
			{"label": "名称", "value": String(ev.get("name", ""))},
			{"label": "类型", "value": String(ev.get("type_name", ""))},
			{"label": "阶段", "value": String(ev.get("stage_name", ""))},
			{"label": "容量", "value": str(int(ev.get("capacity", 0)))},
			{"label": "售出", "value": str(int(ev.get("sold", 0)))},
			{"label": "预算", "value": str(int(ev.get("budget", 0)))},
			{"label": "收入", "value": str(int(ev.get("revenue", 0)))},
			{"label": "成本", "value": str(int(ev.get("cost", 0)))},
			{"label": "口碑", "value": "%.0f" % float(ev.get("reputation", 0.0))},
			{"label": "赞助", "value": "%d 家" % int(ev.get("sponsors", 0))},
			{"label": "事故", "value": "%d 起" % int(ev.get("incidents", 0))},
		]))
	if ev.has("planner_level"):
		sections.append(_section("策划职业", [
			{"label": "等级", "value": str(int(ev.get("planner_level", 1)))},
			{"label": "经验", "value": str(int(ev.get("planner_exp", 0)))},
			{"label": "完场", "value": "%d 场" % int(ev.get("planner_events", 0))},
		]))
	return sections

static func awards(player: Dictionary, context: Dictionary, name_resolver: Callable = Callable()) -> Dictionary:
	if player.is_empty():
		return _empty("奖项与荣誉", "尚未生成角色数据")
	var sections: Array = []
	var items: Array = _items_of(player.get("awards", [])) + _items_of(_world(context).get("awards", []))
	if not items.is_empty():
		sections.append(_section("奖项与荣誉", _rows_from(items, ["title", "year", "grade"], name_resolver)))
	var hn: Dictionary = context.get("honors", {}) if context.get("honors") is Dictionary else {}
	if not hn.is_empty():
		sections.append_array(_honors_sections(hn))
	if sections.is_empty():
		return _empty("奖项与荣誉", "尚无奖项；可用「荣誉档案」建立档案并「提名」参评")
	return _ok(sections)

## 荣誉面板分区：荣誉档案、已获荣誉、名人堂。
static func _honors_sections(hn: Dictionary) -> Array:
	var sections: Array = []
	if hn.has("achievement"):
		sections.append(_section("荣誉档案", [
			{"label": "成就", "value": "%.0f" % float(hn.get("achievement", 0.0))},
			{"label": "关系", "value": "%.2f" % float(hn.get("relations", 0.0))},
			{"label": "声望", "value": "%.0f" % float(hn.get("reputation", 0.0))},
			{"label": "特权", "value": "%d 项" % int(hn.get("privileges", 0))},
		]))
	var honors: Array = _items_of(hn.get("honors", []))
	if not honors.is_empty():
		var rows: Array = []
		for h in honors:
			if h is Dictionary:
				var hd: Dictionary = h
				rows.append({"label": String(hd.get("name", "?")), "value": "%s · 威望 %.0f" % [String(hd.get("category", "")), float(hd.get("prestige", 0.0))]})
		sections.append(_section("已获荣誉", rows))
	if hn.has("hall_size"):
		sections.append(_section("名人堂", [
			{"label": "记录", "value": "%d 条" % int(hn.get("hall_size", 0))},
			{"label": "在世荣誉", "value": str(int(hn.get("hall_active", 0)))},
		]))
	return sections

static func digital(player: Dictionary, context: Dictionary = {}, name_resolver: Callable = Callable()) -> Dictionary:
	if player.is_empty():
		return _empty("数字与平台", "尚未生成角色数据")
	var d: Dictionary = context.get("digital", {}) if context.get("digital") is Dictionary else {}
	var sections: Array = []
	if not d.is_empty():
		var irows: Array = []
		irows.append({"label": "实名认证", "value": "已认证" if bool(d.get("real_name_verified", false)) else "未认证"})
		irows.append({"label": "隐私级别", "value": "%.0f%%" % (float(d.get("privacy", 0.0)) * 100.0)})
		irows.append({"label": "暴露热度", "value": "%.1f" % float(d.get("exposure_heat", 0.0))})
		irows.append({"label": "网络成瘾", "value": "%.0f%%" % (float(d.get("addiction", 0.0)) * 100.0)})
		irows.append({"label": "数据条目", "value": "%d（泄露 %d）" % [int(d.get("data_total", 0)), int(d.get("data_leaked", 0))]})
		sections.append(_section("数字身份", irows))
		var arows: Array = []
		for a in (d.get("accounts", []) as Array):
			if a is Dictionary:
				var ad: Dictionary = a
				arows.append({"label": String(ad.get("platform", "")), "value": "实名" if bool(ad.get("real_name", false)) else "匿名"})
		if not arows.is_empty():
			sections.append(_section("平台账号", arows))
		var vrows: Array = []
		for a in (d.get("assets", []) as Array):
			if a is Dictionary:
				var ad2: Dictionary = a
				vrows.append({"label": String(ad2.get("type", "")), "value": "%d%s" % [int(ad2.get("value", 0)), "（被盗）" if bool(ad2.get("stolen", false)) else ""]})
		if not vrows.is_empty():
			sections.append(_section("数字资产", vrows))
		var creator: Dictionary = d.get("creator", {}) if d.get("creator") is Dictionary else {}
		if not creator.is_empty():
			sections.append(_section("内容创作", [
				{"label": "平台", "value": String(creator.get("platform", ""))},
				{"label": "粉丝", "value": str(int(creator.get("fans", 0)))},
				{"label": "打赏累计", "value": str(int(creator.get("tips_total", 0)))},
				{"label": "带货 GMV", "value": str(int(creator.get("delivery_gmv", 0)))},
			]))
		var esp: Dictionary = d.get("esports", {}) if d.get("esports") is Dictionary else {}
		if not esp.is_empty():
			sections.append(_section("电竞生涯", [
				{"label": "战队", "value": String(esp.get("team", ""))},
				{"label": "技能", "value": "%.0f" % float(esp.get("skill", 0.0))},
				{"label": "奖金累计", "value": str(int(esp.get("prize_total", 0)))},
			]))
	if sections.is_empty():
		var items: Array = _items_of(player.get("digital_assets", []))
		if items.is_empty():
			return _empty("数字与平台", "未开通数字资产；可开账号、发布内容或从事网络安全工作")
		sections.append(_section("数字资产", _rows_from(items, ["type", "platform", "balance", "followers"], name_resolver)))
	return _ok(sections)

static func epidemic(player: Dictionary, context: Dictionary, name_resolver: Callable = Callable()) -> Dictionary:
	if player.is_empty():
		return _empty("疫情与公共卫生", "尚未生成角色数据")
	var sections: Array = []
	var ep: Array = _items_of(context.get("epidemic", []))
	if not ep.is_empty():
		sections.append(_section("疫情态势", _rows_from(ep, ["type", "severity", "status", "region"], name_resolver)))
	var diseases: Array = _items_of(player.get("health", {}).get("diseases", []))
	if not diseases.is_empty():
		sections.append(_section("感染与症状", _rows_from(diseases, ["type", "severity", "status"], name_resolver)))
	if sections.is_empty():
		return _empty("疫情与公共卫生", "当前无疫情；可接种、检测并保持常态监测")
	return _ok(sections)

static func war(player: Dictionary, name_resolver: Callable = Callable()) -> Dictionary:
	if player.is_empty():
		return _empty("战争与军旅", "尚未生成角色数据")
	var mil: Dictionary = player.get("military", {})
	if mil.is_empty() or String(mil.get("status", "")) == "":
		return _empty("战争与军旅", "无军籍；可查看征兵条件并参军、请战、晋升或退伍")
	var rows: Array = []
	for pair in [["status", "状态"], ["branch", "军种"], ["rank", "军衔"], ["unit", "部队"]]:
		if mil.has(String(pair[0])):
			rows.append({"label": String(pair[1]), "value": _fmt_value(String(pair[0]), mil[pair[0]])})
	if mil.has("service_start_minutes"):
		rows.append({"label": "入伍", "value": "%d 分钟" % int(mil["service_start_minutes"])})
	rows.append({"label": "勋章", "value": str(_items_of(mil.get("decorations", [])).size())})
	rows.append({"label": "征兵入伍", "value": _yes_no(mil.get("conscripted", false))})
	return _ok([_section("军籍", rows)])

static func market(player: Dictionary, context: Dictionary) -> Dictionary:
	var w: Dictionary = _world(context)
	var macro: Dictionary = context.get("macro", {})
	if not (macro is Dictionary):
		macro = {}
	var economy: Dictionary = w.get("economy", {}) if w.get("economy", {}) is Dictionary else {}
	if macro.is_empty() and economy.is_empty():
		return _empty("宏观行情", "暂无宏观数据；可查看 GDP/通胀/失业/PMI 模型摘要")
	var rows: Array = []
	var labels: Dictionary = {
		"gdp": "GDP", "gdp_growth": "增速", "inflation": "通胀", "base_rate": "基准利率",
		"unemployment": "失业率", "price_index": "物价指数", "pmi": "PMI", "cycle_phase": "周期阶段",
	}
	for key in ["gdp", "gdp_growth", "inflation", "base_rate", "unemployment", "price_index", "pmi", "cycle_phase"]:
		if macro.has(key):
			var v: Variant = macro[key]
			var text: String = str(v) if typeof(v) == TYPE_STRING else ("%.3f" % float(v))
			rows.append({"label": String(labels[key]), "value": text})
		if economy.has(key):
			rows.append({"label": String(labels.get(key, key)), "value": str(economy[key])})
	return _ok([_section("宏观指标", rows)])

static func weather(player: Dictionary, context: Dictionary, name_resolver: Callable = Callable()) -> Dictionary:
	var w: Variant = context.get("weather", {})
	if not (w is Dictionary) or (w as Dictionary).is_empty():
		return _empty("天气预报", "暂无天气数据；按气候带给出近期均值")
	var d: Dictionary = w
	var rows: Array = []
	var labels: Dictionary = {
		"condition": "天气", "temperature": "气温", "humidity": "湿度",
		"wind": "风力", "phase": "昼夜", "warning": "预警",
	}
	for key in ["condition", "temperature", "humidity", "wind", "phase", "warning"]:
		if d.has(key):
			rows.append({"label": String(labels[key]), "value": str(d[key])})
	if rows.is_empty():
		return _empty("天气预报", "暂无天气数据；按气候带给出近期均值")
	var sections: Array = [_section("当前天气", rows)]
	var fc: Variant = d.get("forecast", [])
	if fc is Array and not (fc as Array).is_empty():
		var frows: Array = []
		for item in fc:
			if item is Dictionary:
				frows.append({"label": str((item as Dictionary).get("label", "")), "value": str((item as Dictionary).get("value", ""))})
		if not frows.is_empty():
			sections.append(_section("未来 7 日", frows))
	return _ok(sections)

static func anomaly(player: Dictionary, context: Dictionary, name_resolver: Callable = Callable()) -> Dictionary:
	if player.is_empty():
		return _empty("异常图鉴", "尚未生成角色数据")
	var a: Dictionary = context.get("anomaly", {})
	if not a.is_empty() and bool(a.get("can_enter", false)):
		return _ok(_anomaly_sections(a))
	# 回退：世界事件层异常条目。
	var items: Array = _items_of(_world(context).get("anomalies", []))
	if items.is_empty():
		return _empty("异常图鉴", "未接触异常收容对象")
	return _ok([_section("异常条目", _rows_from(items, ["class", "containment", "faction", "status"], name_resolver))])

static func _anomaly_sections(a: Dictionary) -> Array:
	var tier_names: Dictionary = {
		"contamination": "认知污染", "hunt": "猎杀", "containment": "收容",
		"ban": "封禁", "breakdown": "精神崩溃",
	}
	var tier: String = String(a.get("tier", ""))
	var sections: Array = []
	sections.append(_section("暴露与状态", [
		{"label": "暴露值", "value": str(int(round(float(a.get("exposure", 0.0)))))},
		{"label": "反噬阈值", "value": String(tier_names.get(tier, "未触发"))},
		{"label": "异常世界", "value": "已激活" if bool(a.get("active", false)) else "门闩未启"},
		{"label": "隔离", "value": "隐藏" if bool(a.get("hidden", true)) else "暴露"},
		{"label": "结局", "value": String(a.get("ending", "")) if not String(a.get("ending", "")).is_empty() else "无"},
	]))
	sections.append(_section("权限与阵营", [
		{"label": "权限", "value": "Level %d" % int(a.get("clearance", 0))},
		{"label": "身份", "value": String(a.get("identity_name", "")) if not String(a.get("identity_name", "")).is_empty() else "未定"},
		{"label": "阵营", "value": String(a.get("faction_name", "")) if not String(a.get("faction_name", "")).is_empty() else "无"},
		{"label": "D 级人员", "value": "是" if bool(a.get("is_d_class", false)) else "否"},
	]))
	var ability_rows: Array = []
	for row in _items_of(a.get("abilities", [])):
		ability_rows.append({"label": String((row as Dictionary).get("name", "")), "value": "Lv %d" % int((row as Dictionary).get("level", 0))})
	if not ability_rows.is_empty():
		sections.append(_section("能力线", ability_rows))
	var res: Dictionary = a.get("resources", {})
	sections.append(_section("资源", [
		{"label": "灵力", "value": str(int(round(float(res.get("mana", 0.0)))))},
		{"label": "精神", "value": str(int(round(float(res.get("spirit", 0.0)))))},
		{"label": "理智", "value": str(int(round(float(res.get("sanity", 0.0)))))},
	]))
	var cont: Dictionary = a.get("contamination", {})
	var am: Dictionary = a.get("amnestics", {})
	sections.append(_section("认知污染", [
		{"label": "模因", "value": str(int(round(float(cont.get("meme", 0.0)))))},
		{"label": "认知", "value": str(int(round(float(cont.get("cognition", 0.0)))))},
		{"label": "信息", "value": str(int(round(float(cont.get("info", 0.0)))))},
		{"label": "合计", "value": str(int(round(float(a.get("contamination_total", 0.0)))))},
		{"label": "记忆删除剂", "value": "%d/%d" % [int(am.get("uses", 0)), int(am.get("max", 0))]},
		{"label": "记忆缺口", "value": str(int(am.get("memory_gaps", 0)))},
		{"label": "成瘾", "value": "%d%%" % int(round(float(am.get("addiction", 0.0)) * 100.0))},
	]))
	sections.append(_section("图鉴", [
		{"label": "已收录", "value": "%d 条" % int(a.get("known_count", 0))},
	]))
	return sections

static func goldfinger(player: Dictionary, name_resolver: Callable = Callable()) -> Dictionary:
	if player.is_empty():
		return _empty("金手指", "尚未生成角色数据")
	var gf: Variant = player.get("goldfinger", {})
	if not (gf is Dictionary) or (gf as Dictionary).is_empty() or not bool((gf as Dictionary).get("enabled", false)):
		return _empty("金手指", "未启用金手指模式")
	var g: Dictionary = gf
	var overview: Array = [
		{"label": "积分", "value": str(int(g.get("points", 0)))},
		{"label": "今日获取", "value": str(int(g.get("daily_points_gained", 0)))},
		{"label": "抽取次数", "value": str(int(g.get("draw_count", 0)))},
		{"label": "重抽次数", "value": str(int(g.get("rerolls_used", 0)))},
		{"label": "保底计数", "value": str(int(g.get("pity_counter", 0)))},
	]
	var sections: Array = [_section("系统", overview)]
	var items: Array = _items_of(g.get("items", []))
	if not items.is_empty():
		sections.append(_section("已获得", _rows_from(items, ["type", "level", "status"], name_resolver)))
	return _ok(sections)

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
