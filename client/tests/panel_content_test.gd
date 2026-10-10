extends "res://tests/test_base.gd"
## 面板内容装配测试（任务 47/51）：角色属性、背包分组、空态与占位。

const PanelContentScript = preload("res://ui/panels/panel_content.gd")
const GameStateScript = preload("res://autoload/game_state.gd")

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
	_test_placeholder()

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

func _test_placeholder() -> void:
	var data: Dictionary = PanelContentScript.build("finance", GameStateScript.default_player())
	check(not bool(data.get("empty", true)), "财务面板有默认数据")
	check_eq(String(data.get("title", "")), "资产与财务", "面板标题")
	var map_data: Dictionary = PanelContentScript.build("map", GameStateScript.default_player())
	check(bool(map_data.get("empty", false)), "地图面板暂为占位")
