extends "res://tests/test_base.gd"
## 面板内容装配测试（任务 47/51）：角色属性、背包分组、空态与占位。

const PanelContentScript = preload("res://ui/panels/panel_content.gd")
const GameStateScript = preload("res://autoload/game_state.gd")

## 本轮补齐的领域摘要面板 id（与 panel_registry.PANELS 对齐）。
const NEW_PANEL_IDS: Array[String] = [
	"business", "organizations", "legal", "rescue", "environment", "municipal",
	"debt", "consumer", "welfare", "funeral", "metaphysics", "medical",
	"content_industry", "engineering", "services", "transport_infra", "household",
	"sports", "events", "awards", "digital", "epidemic", "war", "market",
	"weather", "anomaly", "goldfinger",
]

func _suite_name() -> String:
	return "panel_content"

func run_tests() -> void:
	_test_character_empty()
	_test_character_default()
	_test_inventory_empty()
	_test_inventory_grouped()
	_test_skills()
	_test_career()
	_test_finance()
	_test_relations()
	_test_achievements()
	_test_family()
	_test_map()
	_test_settings()
	_test_placeholder()
	_test_domain_panels_render()
	_test_domain_panels_content()
	_test_ending_panel()

func _test_domain_panels_render() -> void:
	var player: Dictionary = GameStateScript.default_player()
	for id in NEW_PANEL_IDS:
		var data: Dictionary = PanelContentScript.build(id, player, Callable(), {})
		check(data.has("sections"), "%s 返回 sections" % id)
		check(data.has("empty"), "%s 含 empty 标志" % id)
		check(String(data.get("title", "")) != "", "%s 有标题" % id)
		check(data.get("sections") is Array, "%s sections 为数组" % id)

func _test_domain_panels_content() -> void:
	var player: Dictionary = GameStateScript.default_player()
	# 债务：默认无负债 → 空态；注入借款后有明细。
	check(bool(PanelContentScript.build("debt", player).get("empty", false)), "默认无负债空态")
	player["finances"]["debt"] = 5000.0
	player["finances"]["loans"] = [{"name": "房贷", "principal": 300000.0, "rate": 0.045, "status": "repaying"}]
	var debt_data: Dictionary = PanelContentScript.build("debt", player)
	check(not bool(debt_data.get("empty", true)), "有负债非空")
	check_eq(_row_value(_find_section(debt_data, "负债概览"), "负债总额"), "5000", "负债总额")
	check_eq(_row_value(_find_section(debt_data, "借款明细"), "房贷"), "本金300000 · 利率4.50% · 状态repaying", "借款明细")
	# 医疗：注入疾病。
	var hp: Dictionary = GameStateScript.default_player()
	hp["health"]["diseases"] = [{"name": "感冒", "severity": 2, "status": "treating"}]
	var med: Dictionary = PanelContentScript.build("medical", hp)
	check(not bool(med.get("empty", true)), "有疾病非空")
	check_eq(_row_value(_find_section(med, "疾病"), "感冒"), "严重度2 · 状态treating", "疾病行")
	# 金手指：启用后展示系统概览。
	var gf: Dictionary = GameStateScript.default_player()
	gf["goldfinger"] = {"enabled": true, "points": 120, "daily_points_gained": 8, "rerolls_used": 1, "pity_counter": 3, "draw_count": 5, "items": []}
	var gf_data: Dictionary = PanelContentScript.build("goldfinger", gf)
	check(not bool(gf_data.get("empty", true)), "金手指启用非空")
	check_eq(_row_value(_find_section(gf_data, "系统"), "积分"), "120", "金手指积分")
	# 宏观行情：注入 macro。
	var market: Dictionary = PanelContentScript.build("market", GameStateScript.default_player(), Callable(), {
		"macro": {"gdp": 100.0, "gdp_growth": 0.02, "inflation": 0.03, "cycle_phase": "recovery"},
	})
	check(not bool(market.get("empty", true)), "有宏观数据非空")
	check_eq(_row_value(_find_section(market, "宏观指标"), "周期阶段"), "recovery", "周期阶段")
	check(String(_row_value(_find_section(market, "宏观指标"), "GDP")).begins_with("100"), "GDP 数值")
	# 世界驱动面板：公司/组织/项目等经 world_delta 注入。
	var world_context: Dictionary = {"world_delta": {
		"factories": [{"name": "一号厂", "industry": "industry.mfg", "stock": 120, "capacity": 200}],
		"organizations": [{"name": "工会", "type": "union", "members": 42, "reputation": 66}],
		"anomalies": [{"name": "收容物-7", "class": "euclid", "containment": 3}],
	}}
	var biz: Dictionary = PanelContentScript.build("business", GameStateScript.default_player(), Callable(), world_context)
	check(not bool(biz.get("empty", true)), "有工厂非空")
	check(String(_row_value(_find_section(biz, "工厂与产线"), "一号厂")).find("产能200") >= 0, "工厂产线行")
	var org: Dictionary = PanelContentScript.build("organizations", GameStateScript.default_player(), Callable(), world_context)
	check(not bool(org.get("empty", true)), "有组织非空")
	check(String(_row_value(_find_section(org, "组织"), "工会")).find("成员42") >= 0, "组织成员行")
	var ano: Dictionary = PanelContentScript.build("anomaly", GameStateScript.default_player(), Callable(), world_context)
	check(not bool(ano.get("empty", true)), "有异常非空")
	check(String(_row_value(_find_section(ano, "异常条目"), "收容物-7")).find("收容等级3") >= 0, "异常行")
	# 天气：注入天气摘要。
	var weather: Dictionary = PanelContentScript.build("weather", GameStateScript.default_player(), Callable(), {
		"weather": {"condition": "小雨", "temperature": "18°C", "wind": "3级"},
	})
	check(not bool(weather.get("empty", true)), "有天气非空")
	check_eq(_row_value(_find_section(weather, "当前天气"), "天气"), "小雨", "天气状况")
	# 天气：注入 7 日预报时新增预报分区。
	var weather_fc: Dictionary = PanelContentScript.build("weather", GameStateScript.default_player(), Callable(), {
		"weather": {
			"condition": "晴", "temperature": "20°C",
			"forecast": [{"label": "今日", "value": "晴 12~22°C 降水0.0mm"}],
		},
	})
	var fc_section: Dictionary = _find_section(weather_fc, "未来 7 日")
	check(not fc_section.is_empty(), "预报分区存在")
	check_eq(_row_value(fc_section, "今日"), "晴 12~22°C 降水0.0mm", "预报行")

func _test_ending_panel() -> void:
	check(bool(PanelContentScript.build("ending", GameStateScript.default_player(), Callable(), {}).get("empty", true)), "无结算数据为空态")
	var data: Dictionary = PanelContentScript.build("ending", GameStateScript.default_player(), Callable(), {
		"death": {
			"name": "张三", "gender": "male", "age_years": 80.0, "final_title": "教师",
			"has_will": true, "estate_minor": 1200000.0,
			"heirs": {"spouse": ["a"], "children": ["b", "c"], "parents": [], "siblings": []},
			"timeline": ["出生于某年"],
		},
	})
	check(not bool(data.get("empty", true)), "有结算数据非空")
	check_eq(_row_value(_find_section(data, "生平"), "姓名"), "张三", "生平姓名")
	check_eq(_row_value(_find_section(data, "法定继承人"), "子女"), "2 位", "继承人子女数")
	check_eq(_row_value(_find_section(data, "遗产"), "净额"), "1.2 万元", "遗产净额")

func _find_section(data: Dictionary, title: String) -> Dictionary:
	for s in data.get("sections", []):
		if String(s.get("title", "")) == title:
			return s
	return {}

func _row_value(section: Dictionary, label: String) -> String:
	for r in section.get("rows", []):
		if String(r.get("label", "")) == label:
			return String(r.get("value", ""))
	return ""

func _test_character_empty() -> void:
	var data: Dictionary = PanelContentScript.character({})
	check(bool(data.get("empty", false)), "空玩家返回空态")
	check(String(data.get("empty_hint", "")) != "", "空态含提示")

func _test_character_default() -> void:
	var data: Dictionary = PanelContentScript.character(GameStateScript.default_player())
	check(not bool(data.get("empty", true)), "默认玩家非空")
	var basic: Dictionary = _find_section(data, "基本")
	check(not basic.is_empty(), "含基本分区")
	check_eq(_row_value(basic, "性别"), "非二元", "性别中文化")
	var phys: Dictionary = _find_section(data, "生理")
	check_eq(phys.get("rows", []).size(), 6, "生理六项")
	check_eq(_row_value(phys, "健康"), "100", "数值格式化")
	var values: Dictionary = _find_section(data, "价值观")
	check_eq(_row_value(values, "利己—利他"), "50", "价值观项存在")

func _test_inventory_empty() -> void:
	var data: Dictionary = PanelContentScript.inventory(GameStateScript.default_player())
	check(bool(data.get("empty", false)), "空背包返回空态")
	check(String(data.get("empty_hint", "")).find("获取") >= 0, "空态引导获取途径")

func _test_inventory_grouped() -> void:
	var player: Dictionary = GameStateScript.default_player()
	player["inventory"] = [
		{"content_key": "item.apple", "quantity": 3, "quality": "common"},
		{"content_key": "item.gem", "quantity": 1, "quality": "rare"},
		{"content_key": "item.relic", "quantity": 1, "quality": "legendary", "durability": 87.0},
	]
	player["equipment"] = ["item.ring"]
	var data: Dictionary = PanelContentScript.inventory(player)
	check(not bool(data.get("empty", true)), "有物品非空")
	var common: Dictionary = _find_section(data, "物品 · 普通")
	check_eq(_row_value(common, "apple"), "x3", "普通物品数量")
	var rare: Dictionary = _find_section(data, "物品 · 稀有")
	check_eq(_row_value(rare, "gem"), "x1", "稀有物品数量")
	var legend: Dictionary = _find_section(data, "物品 · 传说")
	check(String(_row_value(legend, "relic")).find("耐久87") >= 0, "耐久显示")
	var equip: Dictionary = _find_section(data, "装备")
	check_eq(_row_value(equip, "ring"), "已装备", "装备项")
	# 名称解析注入。
	var resolver := func(key: String) -> String:
		return "苹果" if key == "item.apple" else ""
	var named: Dictionary = PanelContentScript.inventory(player, resolver)
	check_eq(_row_value(_find_section(named, "物品 · 普通"), "苹果"), "x3", "名称解析生效")

func _test_skills() -> void:
	check(bool(PanelContentScript.skills(GameStateScript.default_player()).get("empty", false)), "空技能返回空态")
	var player: Dictionary = GameStateScript.default_player()
	player["skills"] = [{"content_key": "skill.cooking", "level": 7, "xp": 40.0}]
	var sec: Dictionary = _find_section(PanelContentScript.skills(player), "技能")
	check_eq(_row_value(sec, "cooking"), "Lv7 · 经验40", "技能等级与经验")

func _test_career() -> void:
	check(bool(PanelContentScript.career(GameStateScript.default_player()).get("empty", false)), "无业空态")
	var player: Dictionary = GameStateScript.default_player()
	player["job"] = {"title": "会计", "industry": "industry.finance", "salary": 8000.0, "performance": 72.0}
	player["licenses"] = [{"content_key": "license.driver", "status": "graduated"}]
	var data: Dictionary = PanelContentScript.career(player)
	var job_sec: Dictionary = _find_section(data, "职业")
	check_eq(_row_value(job_sec, "职位"), "会计", "职位标题")
	check_eq(_row_value(job_sec, "月薪"), "8000", "月薪")
	var lic: Dictionary = _find_section(data, "执照")
	check_eq(_row_value(lic, "driver"), "已毕业", "执照状态中文化")

func _test_finance() -> void:
	var data: Dictionary = PanelContentScript.finance(GameStateScript.default_player())
	var sec: Dictionary = _find_section(data, "资金")
	check_eq(_row_value(sec, "现金"), "1000", "默认现金")
	var player: Dictionary = GameStateScript.default_player()
	player["assets"] = [{"content_key": "asset.house", "kind": "real_estate", "value": 500000.0, "mortgaged": true}]
	var asset_sec: Dictionary = _find_section(PanelContentScript.finance(player), "资产")
	check_eq(_row_value(asset_sec, "house"), "500000 · 已抵押", "资产与抵押")

func _test_relations() -> void:
	check(bool(PanelContentScript.relations(GameStateScript.default_player()).get("empty", false)), "无关系空态")
	var player: Dictionary = GameStateScript.default_player()
	player["relations"] = [{"target_id": "0123456789abcdef", "favor": 30, "trust": 55, "circle": "friend"}]
	var sec: Dictionary = _find_section(PanelContentScript.relations(player), "关系")
	check_eq(_row_value(sec, "89abcdef"), "朋友 · 好感30 · 信任55", "关系摘要")

func _test_achievements() -> void:
	check(bool(PanelContentScript.achievements(GameStateScript.default_player()).get("empty", false)), "无成就空态")
	var player: Dictionary = GameStateScript.default_player()
	player["achievements"] = ["achv.first_job"]
	var sec: Dictionary = _find_section(PanelContentScript.achievements(player), "成就")
	check_eq(_row_value(sec, "first_job"), "已达成", "成就项")

func _test_family() -> void:
	check(bool(PanelContentScript.family(GameStateScript.default_player()).get("empty", false)), "首代家族空态")
	var player: Dictionary = GameStateScript.default_player()
	player["family"] = {"children_ids": ["a", "b"], "parent_ids": ["c"]}
	var sec: Dictionary = _find_section(PanelContentScript.family(player), "家庭")
	check_eq(_row_value(sec, "子女"), "2", "子女数")
	check_eq(_row_value(sec, "父母"), "1", "父母数")
	# 指定监护人：非空时展示。
	player["family"]["guardian_ids"] = ["g"]
	var sec2: Dictionary = _find_section(PanelContentScript.family(player), "家庭")
	check_eq(_row_value(sec2, "指定监护人"), "1", "监护人显示")

func _test_placeholder() -> void:
	var data: Dictionary = PanelContentScript.build("finance", GameStateScript.default_player())
	check(not bool(data.get("empty", true)), "财务面板有默认数据")
	check_eq(String(data.get("title", "")), "资产与财务", "面板标题")
	var map_data: Dictionary = PanelContentScript.build("map", GameStateScript.default_player())
	check(bool(map_data.get("empty", false)), "地图面板无上下文时占位")
	var anomaly: Dictionary = PanelContentScript.build("anomaly", GameStateScript.default_player())
	check(bool(anomaly.get("empty", false)), "异常面板暂为占位")

func _test_map() -> void:
	var context: Dictionary = {
		"current_region": "map.beijing",
		"regions": [{"region_key": "map.beijing", "population": 1200, "price_index": 1.25, "safety": 70}],
		"itineraries": [{"destination": {"region_id": "map.shanghai"}, "mode": "train", "arrive_minutes": 480}],
	}
	var data: Dictionary = PanelContentScript.build("map", GameStateScript.default_player(), Callable(), context)
	check(not bool(data.get("empty", true)), "有区域数据非空")
	check_eq(_row_value(_find_section(data, "当前区域"), "beijing"), "所在", "当前区域")
	var region_sec: Dictionary = _find_section(data, "已到访区域")
	check(String(_row_value(region_sec, "beijing")).find("人口1200") >= 0, "区域摘要")
	var trip_sec: Dictionary = _find_section(data, "行程")
	check(String(_row_value(trip_sec, "shanghai")).find("train") >= 0, "行程目的地")

func _test_settings() -> void:
	var context: Dictionary = {"settings": {
		"scheme": "light", "variant": "colorblind", "accent": "jade",
		"ui_scale": 1.25, "body_font_scale": 1.15,
		"reduce_motion": true, "tts_enabled": false, "speed_level": 4, "tray_enabled": true,
	}}
	var data: Dictionary = PanelContentScript.build("settings", {}, Callable(), context)
	check(not bool(data.get("empty", true)), "设置摘要非空")
	var appearance: Dictionary = _find_section(data, "外观")
	check_eq(_row_value(appearance, "主题"), "亮色", "主题中文化")
	check_eq(_row_value(appearance, "配色方案"), "色盲友好", "配色方案中文化")
	check_eq(_row_value(appearance, "主题色"), "石绿", "主色中文化")
	check_eq(_row_value(appearance, "界面缩放"), "125%", "缩放百分比")
	var access: Dictionary = _find_section(data, "无障碍")
	check_eq(_row_value(access, "减少动态"), "开启", "减少动态")
	check_eq(_row_value(access, "文本朗读"), "关闭", "朗读开关")
	check_eq(_row_value(_find_section(data, "其他"), "推进倍速"), "4x", "倍速")
