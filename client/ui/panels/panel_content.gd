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
			data = debt(player, name_resolver)
		"consumer":
			data = consumer(player, context, name_resolver)
		"welfare":
			data = welfare(player, name_resolver)
		"funeral":
			data = funeral(player, name_resolver)
		"metaphysics":
			data = metaphysics(player, context, name_resolver)
		"medical":
			data = medical(player, name_resolver)
		"content_industry":
			data = content_industry(player, context, name_resolver)
		"engineering":
			data = engineering(player, context, name_resolver)
		"services":
			data = services(player, name_resolver)
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
			data = digital(player, name_resolver)
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
	if sections.is_empty():
		return _empty("经营", "尚无产业；可通过创业、融资或收购开启经营")
	return _ok(sections)

static func organizations(player: Dictionary, context: Dictionary, name_resolver: Callable = Callable()) -> Dictionary:
	if player.is_empty():
		return _empty("组织", "尚未生成角色数据")
	var orgs: Array = _items_of(_world(context).get("organizations", []))
	if orgs.is_empty():
		return _empty("组织", "尚未加入组织；可加入工会、NGO、俱乐部或阵营")
	return _ok([_section("组织", _rows_from(orgs, ["type", "members", "reputation", "rank"], name_resolver))])

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
	if sections.is_empty():
		return _empty("救援与灾害", "当前无灾害；可关注常态风险与应急演练")
	return _ok(sections)

static func environment(player: Dictionary, context: Dictionary, name_resolver: Callable = Callable()) -> Dictionary:
	if player.is_empty():
		return _empty("环保与碳市场", "尚未生成角色数据")
	var lands: Array = _items_of(player.get("lands", []))
	if lands.is_empty():
		return _empty("环保与碳市场", "未涉猎低碳项目；可从绿色产业、减排项目或碳交易入门")
	return _ok([_section("土地与生态", _rows_from(lands, ["kind", "area", "value"], name_resolver))])

static func municipal(player: Dictionary, context: Dictionary, name_resolver: Callable = Callable()) -> Dictionary:
	if player.is_empty():
		return _empty("市政", "尚未生成角色数据")
	var orders: Array = _items_of(player.get("orders", []))
	if orders.is_empty():
		return _empty("市政", "暂无市政事项；可缴纳公用事业费、参与招投标或听证")
	return _ok([_section("市政事项", _rows_from(orders, ["type", "status", "amount"], name_resolver))])

static func debt(player: Dictionary, name_resolver: Callable = Callable()) -> Dictionary:
	if player.is_empty():
		return _empty("债务与催收", "尚未生成角色数据")
	var fin: Dictionary = player.get("finances", {})
	var loans: Array = _items_of(fin.get("loans", []))
	var leases: Array = _items_of(fin.get("leases", []))
	var debt_amount: float = float(fin.get("debt", 0.0))
	if loans.is_empty() and leases.is_empty() and debt_amount <= 0.0:
		return _empty("债务与催收", "暂无负债；当前可用信用额度 %s" % _money(fin.get("credit_limit", 0.0)))
	var overview: Array = [
		{"label": "负债总额", "value": _money(debt_amount)},
		{"label": "信用分", "value": str(int(player.get("credit_score", 0)))},
	]
	if fin.has("credit_limit"):
		overview.append({"label": "信用额度", "value": _money(fin.get("credit_limit", 0.0))})
	var sections: Array = [_section("负债概览", overview)]
	if not loans.is_empty():
		sections.append(_section("借款明细", _rows_from(loans, ["principal", "rate", "status", "due_minutes"], name_resolver)))
	if not leases.is_empty():
		sections.append(_section("租赁", _rows_from(leases, ["type", "amount", "status", "due_minutes"], name_resolver)))
	return _ok(sections)

static func consumer(player: Dictionary, context: Dictionary, name_resolver: Callable = Callable()) -> Dictionary:
	if player.is_empty():
		return _empty("维权与消费", "尚未生成角色数据")
	var cases: Array = _items_of(player.get("cases", []))
	if cases.is_empty():
		return _empty("维权与消费", "暂无投诉；遇到消费纠纷可投诉、举证并申请调解或仲裁")
	return _ok([_section("投诉与维权", _rows_from(cases, ["type", "stage", "status"], name_resolver))])

static func welfare(player: Dictionary, name_resolver: Callable = Callable()) -> Dictionary:
	if player.is_empty():
		return _empty("救助与福利", "尚未生成角色数据")
	var level: int = int(player.get("disability_level", 0))
	var disabilities: Array = _items_of(player.get("disabilities", []))
	if level <= 0 and disabilities.is_empty():
		return _empty("救助与福利", "暂无救助资格；低保/社保需满足收入与身份准入条件")
	var rows: Array = [
		{"label": "残疾等级", "value": str(level)},
		{"label": "认定项", "value": str(disabilities.size())},
		{"label": "信用分", "value": str(int(player.get("credit_score", 0)))},
	]
	return _ok([_section("资格概览", rows)])

static func funeral(player: Dictionary, name_resolver: Callable = Callable()) -> Dictionary:
	if player.is_empty():
		return _empty("殡葬", "尚未生成角色数据")
	var will: Dictionary = player.get("will", {})
	if will.is_empty():
		return _empty("殡葬", "尚未立遗嘱；可预约殡葬服务、选购墓地与安排祭扫")
	var rows: Array = []
	if will.has("written_minutes"):
		rows.append({"label": "立嘱时间", "value": "%d 分钟" % int(will["written_minutes"])})
	if not String(will.get("executor_id", "")).is_empty():
		rows.append({"label": "执行人", "value": _short_id(String(will["executor_id"]))})
	rows.append({"label": "受益人", "value": str(_items_of(will.get("beneficiaries", [])).size())})
	if will.has("notes"):
		rows.append({"label": "备注", "value": String(will["notes"])})
	return _ok([_section("遗嘱", rows)])

static func metaphysics(player: Dictionary, context: Dictionary, name_resolver: Callable = Callable()) -> Dictionary:
	if player.is_empty():
		return _empty("玄学", "尚未生成角色数据")
	var talents: Array = _items_of(player.get("talents", []))
	if talents.is_empty():
		return _empty("玄学", "未接触玄学；可求签、看相、占卦、请符或开坛")
	var rows: Array = []
	for t in talents:
		rows.append({"label": _resolve(String(t), name_resolver), "value": "具"})
	return _ok([_section("命理印记", rows)])

static func medical(player: Dictionary, name_resolver: Callable = Callable()) -> Dictionary:
	if player.is_empty():
		return _empty("医疗", "尚未生成角色数据")
	var health: Dictionary = player.get("health", {})
	var sections: Array = []
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

static func content_industry(player: Dictionary, context: Dictionary, name_resolver: Callable = Callable()) -> Dictionary:
	if player.is_empty():
		return _empty("文娱", "尚未生成角色数据")
	var ips: Array = _items_of(_world(context).get("ips", []))
	if ips.is_empty():
		return _empty("文娱", "尚无作品；可创作、授权、发行并查看分成")
	return _ok([_section("作品与版权", _rows_from(ips, ["type", "status", "royalty", "rating"], name_resolver))])

static func engineering(player: Dictionary, context: Dictionary, name_resolver: Callable = Callable()) -> Dictionary:
	if player.is_empty():
		return _empty("工程与基建", "尚未生成角色数据")
	var projects: Array = _items_of(_world(context).get("projects", []))
	if projects.is_empty():
		return _empty("工程与基建", "暂无在建项目；可关注招标信息并投标开工")
	return _ok([_section("在建工程", _rows_from(projects, ["type", "stage", "progress", "budget"], name_resolver))])

static func services(player: Dictionary, name_resolver: Callable = Callable()) -> Dictionary:
	if player.is_empty():
		return _empty("专业与生活服务", "尚未生成角色数据")
	var orders: Array = _items_of(player.get("orders", []))
	if orders.is_empty():
		return _empty("专业与生活服务", "暂无服务单；可预约律师、会计、维修、家政或搬家")
	return _ok([_section("服务单", _rows_from(orders, ["type", "status", "amount", "rating"], name_resolver))])

static func transport_infra(player: Dictionary, context: Dictionary, name_resolver: Callable = Callable()) -> Dictionary:
	if player.is_empty():
		return _empty("交通基建", "尚未生成角色数据")
	var trips: Array = _items_of(player.get("itineraries", [])) + _items_of(_world(context).get("itineraries", []))
	if trips.is_empty():
		return _empty("交通基建", "暂无线路权限；可只读查看路网与时刻表")
	return _ok([_section("行程与线路", _rows_from(trips, ["type", "status", "amount", "arrive_minutes"], name_resolver))])

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
		sections.append(_section("家庭成员", rows))
	if not pets.is_empty():
		sections.append(_section("宠物", _rows_from(pets, ["type", "status", "level"], name_resolver)))
	if sections.is_empty():
		return _empty("家庭与宠物", "尚无家庭或宠物；可建立关系、领养并照护")
	return _ok(sections)

static func sports(player: Dictionary, context: Dictionary, name_resolver: Callable = Callable()) -> Dictionary:
	if player.is_empty():
		return _empty("体育", "尚未生成角色数据")
	var items: Array = _items_of(_world(context).get("sports", []))
	if items.is_empty():
		return _empty("体育", "未涉猎体育；可查看赛事日历并报名训练")
	return _ok([_section("赛事与球队", _rows_from(items, ["type", "teams", "status", "score"], name_resolver))])

static func events_panel(player: Dictionary, context: Dictionary, name_resolver: Callable = Callable()) -> Dictionary:
	if player.is_empty():
		return _empty("活动与展会", "尚未生成角色数据")
	var items: Array = _items_of(_world(context).get("world_events", []))
	if items.is_empty():
		return _empty("活动与展会", "暂无活动；可查看预告并报名参展")
	return _ok([_section("活动与展会", _rows_from(items, ["type", "status", "start_minutes", "venue"], name_resolver))])

static func awards(player: Dictionary, context: Dictionary, name_resolver: Callable = Callable()) -> Dictionary:
	if player.is_empty():
		return _empty("奖项与荣誉", "尚未生成角色数据")
	var items: Array = _items_of(player.get("awards", [])) + _items_of(_world(context).get("awards", []))
	if items.is_empty():
		return _empty("奖项与荣誉", "尚无奖项；可申报奖项、拉票并展示荣誉墙")
	return _ok([_section("奖项与荣誉", _rows_from(items, ["title", "year", "grade"], name_resolver))])

static func digital(player: Dictionary, name_resolver: Callable = Callable()) -> Dictionary:
	if player.is_empty():
		return _empty("数字与平台", "尚未生成角色数据")
	var items: Array = _items_of(player.get("digital_assets", []))
	if items.is_empty():
		return _empty("数字与平台", "未开通数字资产；可注册平台、开播、上架与提现")
	return _ok([_section("数字资产", _rows_from(items, ["type", "platform", "balance", "followers"], name_resolver))])

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
	var items: Array = _items_of(_world(context).get("anomalies", []))
	if items.is_empty():
		return _empty("异常图鉴", "未接触异常收容对象")
	return _ok([_section("异常条目", _rows_from(items, ["class", "containment", "faction", "status"], name_resolver))])

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
