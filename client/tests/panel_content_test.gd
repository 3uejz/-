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
	"weather", "anomaly", "goldfinger", "mental", "spirit", "language", "disability", "appearance",
	"company",
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
	_test_mental_panel()
	_test_spirit_panel()
	_test_language_panel()
	_test_disability_panel()
	_test_agriculture_panel()
	_test_digital_panel()
	_test_late_tech_panel()
	_test_ip_media_panel()
	_test_manufacturing_panel()
	_test_trade_panel()
	_test_mining_panel()
	_test_primary_panel()
	_test_dining_panel()
	_test_fashion_panel()
	_test_sports_panel()
	_test_events_panel()
	_test_honors_panel()
	_test_police_panel()
	_test_emergency_panel()
	_test_environment_panel()
	_test_municipal_panel()
	_test_debt_panel()
	_test_consumer_panel()
	_test_welfare_panel()
	_test_funeral_panel()
	_test_metaphysics_panel()
	_test_anomaly_panel()
	_test_hidden_anomaly_panel_empty()
	_test_medical_panel()
	_test_content_industry_panel()
	_test_engineering_panel()
	_test_professional_panel()
	_test_life_services_panel()
	_test_transport_infra_panel()
	_test_appearance_panel()
	_test_company_panel()
	_test_workplace_military_panels()

func _test_company_panel() -> void:
	var ctx: Dictionary = {"company": {
		"company": {"name": "测试小店", "status": "open", "shops": [{}]},
		"cash": 5000000, "net_worth": 8000000, "insolvent": false,
		"employees": [{"id": "emp.1"}],
		"products": [{"good": "item.apple", "qty": 20, "unit_cost": 500, "price": 900}],
		"cap_table": {"valuation": 20000000, "holders": [{"id": "founder", "name": "创始人", "equity": 0.7}]},
	}}
	var d: Dictionary = PanelContentScript.build("company", GameStateScript.default_player(), Callable(), ctx)
	check(not bool(d.get("empty", true)), "有公司上下文非空")
	check(_find_section(d, "公司").get("rows", []).size() >= 5, "公司分区有行")
	check(_find_section(d, "商品").get("rows", []).size() >= 1, "商品分区有行")
	check(_find_section(d, "股权与融资").get("rows", []).size() >= 2, "股权分区有行")

func _test_workplace_military_panels() -> void:
	var player: Dictionary = GameStateScript.default_player()
	player["job"] = {"title": "工程师", "industry": "it", "salary": 9000}
	player["military"] = {"status": "serving", "branch": "army", "rank": "private", "unit": "unit.army"}
	var ctx: Dictionary = {
		"workplace": {
			"job_title": "工程师", "performance": 60.0, "internal_reputation": 55.0,
			"supervisor_favor": 40.0, "colleague_support": 50.0, "industry_reputation": 45.0,
			"deterioration_risk": 0.2, "player_faction": "改革派",
			"factions": {"reform": {"name": "改革派", "power": 35.0, "alignment": "reform"}},
		},
		"military": {
			"enlisted": true, "status": "serving", "branch": "army", "branch_name": "陆军",
			"rank_name": "列兵", "rank_grade": "soldier", "merits": 6.0, "casualties": 0,
			"pay": 600000, "eligible": true, "next_rank_name": "上等兵", "next_merit_required": 5.0,
			"restricted_verbs": ["辞职", "注册公司"],
		},
	}
	var career: Dictionary = PanelContentScript.build("career", player, Callable(), ctx)
	check(not bool(career.get("empty", true)), "有职场上下文非空")
	check(_find_section(career, "职场关系").get("rows", []).size() >= 4, "职场关系分区有行")
	check(_find_section(career, "派系").get("rows", []).size() >= 1, "派系分区有行")
	var war: Dictionary = PanelContentScript.build("war", player, Callable(), ctx)
	check(not bool(war.get("empty", true)), "有军旅上下文非空")
	check(_find_section(war, "军籍").get("rows", []).size() >= 6, "军籍分区含军功薪酬")
	check(_find_section(war, "服役限制").get("rows", []).size() == 1, "服役限制分区有行")

func _test_appearance_panel() -> void:
	var ctx: Dictionary = {"appearance": {
		"profile": {"height_cm": 175.0, "weight_kg": 68.0, "bmi": 22.2, "appearance_score": 72.0,
			"temperament": 65.0, "outfit": 80.0, "hairstyle": 70.0, "posture": 60.0,
			"body_fat": 18.0, "muscle": 55.0, "odor": 60.0},
		"charm": 71.5, "body_modifier": 2.0, "voice_modifier": 1.0,
		"count": 2, "stiffness": 0.0, "addicted": false, "recovery_remaining": 120,
		"id_match": false, "id_diff": 42.0, "id_tolerance": 25.0,
		"projects": [{"name": "注射微整", "cost": 300000, "recovery_minutes": 720,
			"success": 0.94, "complication": 0.06, "repeatable": true}],
		"procedures": [{"project": "injection", "outcome": "success", "minute": 60, "cost": 300000}],
	}}
	var d: Dictionary = PanelContentScript.build("appearance", GameStateScript.default_player(), Callable(), ctx)
	check(not bool(d.get("empty", true)), "有形象上下文非空")
	check(_find_section(d, "魅力").get("rows", []).size() >= 4, "魅力分区有行")
	check(_find_section(d, "体型与仪容").get("rows", []).size() >= 6, "体型分区有行")
	check(_find_section(d, "医美状态").get("rows", []).size() >= 3, "医美状态分区有行")
	check(_find_section(d, "证件核验").get("rows", []).size() >= 2, "证件分区有行")
	check(_find_section(d, "医美项目").get("rows", []).size() >= 1, "项目表有行")
	check(_find_section(d, "医美记录").get("rows", []).size() >= 1, "记录有行")

func _test_welfare_panel() -> void:
	var ctx: Dictionary = {"welfare": {
		"application": {"kind": "dibao", "kind_name": "低保", "status": "approved", "approved": true, "amount": 120000, "disbursed": 120000, "reasons": []},
		"fund": {"name": "希望基金", "balance": 300000, "raised": 500000, "spent": 200000, "transparency": 0.9, "reputation": 0.7},
		"worker": {"name": "本人", "cases_closed": 3, "rank_index": 1, "active_cases": 1},
		"case": {"id": "player#1", "family_id": "family-1", "status": "open", "visits": 2, "progress": 0.5},
		"child": {"id": "child", "route": "foster"},
	}}
	var d: Dictionary = PanelContentScript.build("welfare", GameStateScript.default_player(), Callable(), ctx)
	check(not bool(d.get("empty", true)), "有救助上下文非空")
	check(_find_section(d, "申请与资格").get("rows", []).size() >= 1, "申请与资格分区有行")
	check(_find_section(d, "慈善基金").get("rows", []).size() >= 1, "慈善基金分区有行")
	check(_find_section(d, "社工").get("rows", []).size() >= 1, "社工分区有行")
	check(_find_section(d, "个案").get("rows", []).size() >= 1, "个案分区有行")
	check(_find_section(d, "变故儿童").get("rows", []).size() >= 1, "变故儿童分区有行")

func _test_funeral_panel() -> void:
	var ctx: Dictionary = {"funeral": {
		"funeral": {"method": "burial", "method_name": "土葬", "grave": "premium", "grave_name": "高档墓", "cost": 1060000, "affordable": true, "executed": true, "paid": 1060000},
		"donation": {"registered": true, "ethics_approved": true, "legal": true, "revoked": false, "organs": ["heart", "kidney"], "allocated": 2},
		"memorials": [{"kind": "monument", "name": "纪念碑", "visits": 3}],
		"digital": {"created": true, "visits": 5},
		"industry": {"name": "永宁殡仪馆", "balance": 500000, "profit": 200000, "price_mult": 1.2, "reputation": 0.6},
		"meaning": 10.0,
	}}
	var d: Dictionary = PanelContentScript.build("funeral", GameStateScript.default_player(), Callable(), ctx)
	check(not bool(d.get("empty", true)), "有殡葬上下文非空")
	check(_find_section(d, "殡葬安排").get("rows", []).size() >= 1, "殡葬安排分区有行")
	check(_find_section(d, "器官捐献").get("rows", []).size() >= 1, "器官捐献分区有行")
	check(_find_section(d, "纪念").get("rows", []).size() >= 1, "纪念分区有行")
	check(_find_section(d, "数字纪念").get("rows", []).size() >= 1, "数字纪念分区有行")
	check(_find_section(d, "殡葬行业").get("rows", []).size() >= 1, "殡葬行业分区有行")

func _test_metaphysics_panel() -> void:
	var ctx: Dictionary = {"metaphysics": {
		"client": {"mood": 55.0, "belief": 0.3, "social": 2.0, "last_consult": "fortune"},
		"practitioner": {"name": "本人", "real_ability": false, "scamming": true, "reputation": 0.4},
		"business": {"name": "青云观", "income": 200000, "customers": 5, "complaints": 1, "reports": 3, "reputation": 0.4, "under_investigation": true},
	}}
	var d: Dictionary = PanelContentScript.build("metaphysics", GameStateScript.default_player(), Callable(), ctx)
	check(not bool(d.get("empty", true)), "有玄学上下文非空")
	check(_find_section(d, "求测状态").get("rows", []).size() >= 1, "求测状态分区有行")
	check(_find_section(d, "从业者").get("rows", []).size() >= 1, "从业者分区有行")
	check(_find_section(d, "玄学经营").get("rows", []).size() >= 1, "玄学经营分区有行")

func _test_anomaly_panel() -> void:
	var ctx: Dictionary = {"anomaly": {
		"hidden": false, "active": true, "can_enter": true, "exposure": 55.0, "tier": "hunt", "ending": "",
		"clearance": 3, "is_d_class": false, "identity_name": "基金会人员", "faction_name": "基金会",
		"abilities": [{"line": "precognition", "name": "预知与气运", "level": 5, "exp": 50.0}],
		"resources": {"mana": 80.0, "spirit": 70.0, "sanity": 60.0},
		"contamination": {"meme": 10.0, "cognition": 5.0, "info": 0.0}, "contamination_total": 15.0,
		"amnestics": {"uses": 1, "max": 3, "memory_gaps": 5, "addiction": 0.5},
		"known_count": 3,
	}}
	var d: Dictionary = PanelContentScript.build("anomaly", GameStateScript.default_player(), Callable(), ctx)
	check(not bool(d.get("empty", true)), "有异常上下文非空")
	check(_find_section(d, "暴露与状态").get("rows", []).size() >= 1, "暴露与状态分区有行")
	check(_find_section(d, "能力线").get("rows", []).size() >= 1, "能力线分区有行")
	check(_find_section(d, "认知污染").get("rows", []).size() >= 1, "认知污染分区有行")
	check(_find_section(d, "图鉴").get("rows", []).size() >= 1, "图鉴分区有行")

func _test_hidden_anomaly_panel_empty() -> void:
	var d: Dictionary = PanelContentScript.build("anomaly", GameStateScript.default_player(), Callable(), {})
	check(bool(d.get("empty", false)), "无异常接触时面板为空态")

func _test_medical_panel() -> void:
	var ctx: Dictionary = {"medical": {
		"disease_count": 25, "active": ["感冒"],
		"care_levels": [{"id": "secondary", "name": "二级"}],
		"high_end": [{"id": "organ_transplant", "name": "器官移植"}],
		"region": {"medical_level": 1.5, "cure_rate": 0.72, "life_expectancy": 79.0},
		"pharma": {"name": "恒瑞", "money": 1000, "drugs": 1, "scandal": false},
	}}
	var d: Dictionary = PanelContentScript.build("medical", GameStateScript.default_player(), Callable(), ctx)
	check(not bool(d.get("empty", true)), "有医疗上下文非空")
	check(_find_section(d, "疾病与病程").get("rows", []).size() >= 1, "疾病与病程分区有行")
	check(_find_section(d, "分级诊疗").get("rows", []).size() >= 1, "分级诊疗分区有行")
	check(_find_section(d, "区域医疗").get("rows", []).size() >= 1, "区域医疗分区有行")
	check(_find_section(d, "高阶医疗").get("rows", []).size() >= 1, "高阶医疗分区有行")
	check(_find_section(d, "医药产业").get("rows", []).size() >= 1, "医药产业分区有行")

func _test_content_industry_panel() -> void:
	var ctx: Dictionary = {"content": {
		"studio": {"name": "星火", "money": 8000000, "reputation": 0.6, "team_size": 3, "financing_stage": "seed"},
		"team": [{"name": "程序", "count": 2, "skill": 0.8}],
		"work": {"title": "星河传说", "type_name": "游戏研发", "progress": 240.0, "required": 240.0, "quality": 0.75, "status": "ready", "revenue": 0, "controversy": 0.0},
		"works": [{"title": "旧作", "quality": 0.6, "performance": 0.7}],
		"ips": [{"title": "星河传说", "power": 0.75, "universe": "", "adaptations": 1}],
		"fandom": {"size": 120000, "toxicity": 0.1},
	}}
	var d: Dictionary = PanelContentScript.build("content_industry", GameStateScript.default_player(), Callable(), ctx)
	check(not bool(d.get("empty", true)), "有文娱上下文非空")
	check(_find_section(d, "工作室").get("rows", []).size() >= 1, "工作室分区有行")
	check(_find_section(d, "创作团队").get("rows", []).size() >= 1, "创作团队分区有行")
	check(_find_section(d, "在研作品").get("rows", []).size() >= 1, "在研作品分区有行")
	check(_find_section(d, "发行作品").get("rows", []).size() >= 1, "发行作品分区有行")
	check(_find_section(d, "IP 库").get("rows", []).size() >= 1, "IP 库分区有行")
	check(_find_section(d, "粉丝文化").get("rows", []).size() >= 1, "粉丝文化分区有行")

func _test_engineering_panel() -> void:
	var ctx: Dictionary = {"engineering": {
		"contractor": {"name": "宏基建设", "qualification": "一级", "capital": 50000000, "workmanship": 0.7, "reputation": 0.6},
		"project": {"name": "跨江大桥", "stage": "construction", "stage_name": "施工", "progress": 0.5, "quality": 0.6, "budget": 50000000, "accepted": false, "accident": false},
		"city": {"name": "云港", "population": 1200000, "land_price": 18000.0, "traffic": 0.6, "zones": [{"zone": "商业区", "type": "commercial", "type_name": "商业区", "land_price": 18000.0}]},
		"developer": {"name": "宏基地产", "cash": 30000000, "debt": 0},
	}}
	var d: Dictionary = PanelContentScript.build("engineering", GameStateScript.default_player(), Callable(), ctx)
	check(not bool(d.get("empty", true)), "有工程上下文非空")
	check(_find_section(d, "施工单位").get("rows", []).size() >= 1, "施工单位分区有行")
	check(_find_section(d, "在建工程").get("rows", []).size() >= 1, "在建工程分区有行")
	check(_find_section(d, "城市规划").get("rows", []).size() >= 1, "城市规划分区有行")
	check(_find_section(d, "功能区").get("rows", []).size() >= 1, "功能区分区有行")
	check(_find_section(d, "房地产").get("rows", []).size() >= 1, "房地产分区有行")

func _test_professional_panel() -> void:
	var ctx: Dictionary = {"professional": {
		"firm": {"name": "恒信事务所", "money": 5000000, "reputation": 0.6, "qualifications": ["注册会计师"], "partners": 1, "clients": 3, "violations": 0, "projects": 1},
		"project": {"id": "project.1", "practice": "accounting_audit", "practice_name": "会计审计", "fee": 200000, "status": "open", "findings": 1},
	}}
	var d: Dictionary = PanelContentScript.build("services", GameStateScript.default_player(), Callable(), ctx)
	check(not bool(d.get("empty", true)), "有专业服务上下文非空")
	check(_find_section(d, "专业事务所").get("rows", []).size() >= 1, "专业事务所分区有行")
	check(_find_section(d, "立项项目").get("rows", []).size() >= 1, "立项项目分区有行")

func _test_life_services_panel() -> void:
	var ctx: Dictionary = {"life_services": {
		"provider": {"name": "王阿姨", "category": "housekeeping", "category_name": "家政保洁", "rating": 0.6, "trust": 0.5, "background": "clean", "orders": 2, "disputes": 0},
		"order": {"id": "order.1", "service": "housekeeping", "price": 2000, "status": "open"},
	}}
	var d: Dictionary = PanelContentScript.build("services", GameStateScript.default_player(), Callable(), ctx)
	check(not bool(d.get("empty", true)), "有生活服务上下文非空")
	check(_find_section(d, "生活服务者").get("rows", []).size() >= 1, "生活服务者分区有行")
	check(_find_section(d, "服务单").get("rows", []).size() >= 1, "服务单分区有行")

func _test_transport_infra_panel() -> void:
	var ctx: Dictionary = {"transport_infra": {
		"project": {"id": "infra.1", "type": "highway", "type_name": "公路", "cost_estimate": 50000000, "spent": 2000000, "progress": 0.5, "days_total": 180.0, "delayed_days": 10.0, "status": "building", "subsidy": 10000000, "accident": false},
		"route": {"mode": "logistics", "mode_name": "物流", "fare": 50.0, "profit": 120000, "on_time_rate": 0.9, "suspended": false},
		"region": {"accessibility": 0.6, "land_price": 12000.0, "gdp": 1500000.0, "population": 110000.0},
	}}
	var d: Dictionary = PanelContentScript.build("transport_infra", GameStateScript.default_player(), Callable(), ctx)
	check(not bool(d.get("empty", true)), "有交通基建上下文非空")
	check(_find_section(d, "基建项目").get("rows", []).size() >= 1, "基建项目分区有行")
	check(_find_section(d, "运营线路").get("rows", []).size() >= 1, "运营线路分区有行")
	check(_find_section(d, "区域影响").get("rows", []).size() >= 1, "区域影响分区有行")

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
	# 组织面板：注入玩法面板数据时渲染「我的组织 / 可加入组织」。
	var org_ctx: Dictionary = {"organizations": {
		"memberships": [{"id": "org:1:0", "name": "城中工会", "type": "工会", "rank": "骨干", "members": 120, "influence": "52.0%", "dues_owed": 50000}],
		"available": [{"id": "org:1:1", "name": "城市NGO", "type": "NGO", "fee": 30000, "legality": "legal"}],
	}}
	var org2: Dictionary = PanelContentScript.build("organizations", GameStateScript.default_player(), Callable(), org_ctx)
	check(String(_row_value(_find_section(org2, "我的组织"), "城中工会")).find("骨干") >= 0, "组织面板成员行")
	check(not _find_section(org2, "可加入组织").is_empty(), "组织面板可加入分区")
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

func _test_mental_panel() -> void:
	var data: Dictionary = PanelContentScript.build("mental", GameStateScript.default_player(), Callable(), {})
	check(bool(data.get("empty", true)), "无心理上下文为空态")
	var ctx: Dictionary = {"mental": {
		"emotion": "焦虑", "mood": 40.0, "stress": 75.0, "happiness": 45.0, "meaning": 55.0,
		"dims": [{"label": "神经质", "value": "70"}],
		"tags": ["敏感焦虑"],
		"cases": [{"label": "焦虑症", "value": "发作期 · 强度60 · 间隔30天 · 单次10天 · 发作2次"}],
	}}
	var d2: Dictionary = PanelContentScript.build("mental", GameStateScript.default_player(), Callable(), ctx)
	check(not bool(d2.get("empty", true)), "有心理上下文非空")
	check_eq(_row_value(_find_section(d2, "情绪与幸福"), "情绪"), "焦虑", "情绪")
	check_eq(_row_value(_find_section(d2, "大五人格"), "神经质"), "70", "人格维度")
	check_eq(_row_value(_find_section(d2, "精神疾病病程"), "焦虑症"), "发作期 · 强度60 · 间隔30天 · 单次10天 · 发作2次", "病程行")

func _test_spirit_panel() -> void:
	var data: Dictionary = PanelContentScript.build("spirit", GameStateScript.default_player(), Callable(), {})
	check(bool(data.get("empty", true)), "无精神上下文为空态")
	var ctx: Dictionary = {"spirit": {
		"axes": [{"label": "利己-利他", "value": "40"}],
		"faith": "佛教", "has_faith": true, "faith_realm": "小成", "faith_depth": 80.0,
		"pursuits": [{"label": "冥想", "value": "小成 · 累计60.0小时"}],
		"crisis": "meaning_loss",
		"crisis_exits": [{"id": "philosophy", "name": "哲学省思"}],
	}}
	var d2: Dictionary = PanelContentScript.build("spirit", GameStateScript.default_player(), Callable(), ctx)
	check(not bool(d2.get("empty", true)), "有精神上下文非空")
	check_eq(_row_value(_find_section(d2, "价值观三轴"), "利己-利他"), "40", "价值观轴")
	check_eq(_row_value(_find_section(d2, "信仰与修持"), "信仰"), "佛教", "信仰")
	check_eq(_row_value(_find_section(d2, "精神追求"), "冥想"), "小成 · 累计60.0小时", "追求深度")
	check_eq(_row_value(_find_section(d2, "精神危机"), "当前危机"), "意义丧失", "危机名称")

func _test_language_panel() -> void:
	var data: Dictionary = PanelContentScript.build("language", GameStateScript.default_player(), Callable(), {})
	check(bool(data.get("empty", true)), "无语言上下文为空态")
	var ctx: Dictionary = {"language": {
		"languages": [{"name": "英语", "overall": 72.0, "speaking": 70.0, "listening": 68.0, "literacy": 78.0}],
		"certificates": [{"label": "英语等级 60", "value": "已获得"}],
		"cultures": [{"name": "美国", "adaptation": 0.6}],
		"shock": 0.4,
		"festival": {"is_festival": true, "festivals": [{"name": "春节"}], "shops_open": false, "traffic": 0.3, "social": 1.8, "spending": 2.2},
	}}
	var d2: Dictionary = PanelContentScript.build("language", GameStateScript.default_player(), Callable(), ctx)
	check(not bool(d2.get("empty", true)), "有语言上下文非空")
	check_eq(_row_value(_find_section(d2, "语言能力"), "英语（综合 72）"), "口语 70 · 听力 68 · 读写 78", "语言分项能力")
	check_eq(_row_value(_find_section(d2, "文化适应"), "美国"), "适应度 60%", "文化适应度")
	check_eq(_row_value(_find_section(d2, "节日民俗"), "今日节日"), "春节", "节日名称")

func _test_disability_panel() -> void:
	var data: Dictionary = PanelContentScript.build("disability", GameStateScript.default_player(), Callable(), {})
	check(bool(data.get("empty", true)), "无残障上下文为空态")
	var ctx: Dictionary = {"disability": {
		"conditions": [{"type": "肢体", "severity": "重度", "source": "事故"}],
		"mobility": 0.25,
		"devices": [{"name": "轮椅"}],
		"recovery": 0.3,
		"accessible": true,
		"retirement_years": 30.0,
		"care_mode": "机构养老",
		"care_quality": 0.8,
		"cognitive": true,
		"decision_capacity": false,
		"will_valid": false,
		"guardian": "child_1",
		"hospice": false,
	}}
	var d2: Dictionary = PanelContentScript.build("disability", GameStateScript.default_player(), Callable(), ctx)
	check(not bool(d2.get("empty", true)), "有残障上下文非空")
	check_eq(_row_value(_find_section(d2, "残障状态"), "移动能力"), "25%", "移动能力")
	check_eq(_row_value(_find_section(d2, "辅具与康复"), "轮椅"), "已装配", "辅具")
	check_eq(_row_value(_find_section(d2, "养老与社保"), "养老模式"), "机构养老", "养老模式")
	check_eq(_row_value(_find_section(d2, "监护与决策"), "监护人"), "child_1", "监护人")

func _test_agriculture_panel() -> void:
	var data: Dictionary = PanelContentScript.build("agriculture", GameStateScript.default_player(), Callable(), {})
	check(bool(data.get("empty", true)), "无农业上下文为空态")
	var ctx: Dictionary = {"agriculture": {
		"money": 500000,
		"land_value": 300000,
		"lands": [{"id": "land_0", "use": "承包", "area": 5.0, "fertility": 0.8, "value": 300000}],
		"plots": [{"name": "水稻", "stage": "mature", "elapsed": 130.0, "growth_days": 120.0}],
		"livestock": [{"name": "生猪", "count": 10}],
		"inventory": [{"name": "水稻", "count": 500.0}],
		"subsidy": 50000.0,
		"year_income": 120000,
		"coop": "",
	}}
	var d2: Dictionary = PanelContentScript.build("agriculture", GameStateScript.default_player(), Callable(), ctx)
	check(not bool(d2.get("empty", true)), "有农业上下文非空")
	check(_find_section(d2, "土地").get("rows", []).size() >= 1, "土地分区有行")
	check(_find_section(d2, "在田作物").get("rows", []).size() >= 1, "在田作物分区有行")
	check(_find_section(d2, "养殖").get("rows", []).size() >= 1, "养殖分区有行")
	check(_find_section(d2, "经营概况").get("rows", []).size() >= 1, "经营概况分区有行")

func _test_digital_panel() -> void:
	var data: Dictionary = PanelContentScript.build("digital", GameStateScript.default_player(), Callable(), {})
	check(bool(data.get("empty", true)), "无数字上下文为空态")
	var ctx: Dictionary = {"digital": {
		"real_name_verified": true,
		"privacy": 0.4,
		"exposure_heat": 20.0,
		"addiction": 0.1,
		"accounts": [{"platform": "短视频", "real_name": true, "privacy": 0.4}],
		"assets": [{"type": "wallet", "value": 100000, "stolen": false}],
		"data_total": 2,
		"data_leaked": 1,
		"creator": {"platform": "短视频", "fans": 1200, "tips_total": 3000, "delivery_gmv": 0},
		"esports": {},
	}}
	var d2: Dictionary = PanelContentScript.build("digital", GameStateScript.default_player(), Callable(), ctx)
	check(not bool(d2.get("empty", true)), "有数字上下文非空")
	check(_find_section(d2, "数字身份").get("rows", []).size() >= 1, "数字身份分区有行")
	check(_find_section(d2, "平台账号").get("rows", []).size() >= 1, "平台账号分区有行")
	check(_find_section(d2, "数字资产").get("rows", []).size() >= 1, "数字资产分区有行")
	check(_find_section(d2, "内容创作").get("rows", []).size() >= 1, "内容创作分区有行")

func _test_late_tech_panel() -> void:
	var data: Dictionary = PanelContentScript.build("late_tech", GameStateScript.default_player(), Callable(), {})
	check(bool(data.get("empty", true)), "无后期科技上下文为空态")
	var ctx: Dictionary = {"late_tech": {
		"stage": "intelligent",
		"stage_name": "智能",
		"stage_index": 1,
		"unemployment_rate": 0.08,
		"lifespan_bonus": 2.0,
		"jobs": [{"id": "aerospace_astronaut", "name": "宇航员"}],
		"places": [{"id": "spaceport", "name": "太空港"}],
		"careers": [{"id": "aerospace_astronaut", "name": "宇航员", "stage": "intelligent", "unlocked": true, "min_level": 14, "salary": 500000}],
		"missions": [{"id": "space_travel", "name": "太空旅行", "stage": "intelligent", "min_skill": 8, "reward": 1000000}],
		"last_report": {"kind": "automation", "result": {"jobs_lost": 30000, "jobs_created": 10000, "unemployment_rate": 0.18}},
	}}
	var d2: Dictionary = PanelContentScript.build("late_tech", GameStateScript.default_player(), Callable(), ctx)
	check(not bool(d2.get("empty", true)), "有后期科技上下文非空")
	check(_find_section(d2, "科技阶段").get("rows", []).size() >= 1, "科技阶段分区有行")
	check(_find_section(d2, "科技职业").get("rows", []).size() >= 1, "科技职业分区有行")
	check(_find_section(d2, "高风险任务").get("rows", []).size() >= 1, "高风险任务分区有行")
	check(_find_section(d2, "社会与技术风险").get("rows", []).size() >= 1, "社会与技术风险分区有行")

func _test_ip_media_panel() -> void:
	var data: Dictionary = PanelContentScript.build("ip_media", GameStateScript.default_player(), Callable(), {})
	check(bool(data.get("empty", true)), "无知识产权上下文为空态")
	var ctx: Dictionary = {"ip_media": {
		"ips": [{"id": "ip.copyright.1", "type": "copyright", "type_name": "版权", "title": "测试作品", "status": "registered", "licenses": 2, "pledged": false, "public_domain": false}],
		"outlets": [{"id": "media.1", "name": "出版社", "type_name": "出版社", "reputation": 0.6, "cash": 500000, "works": 3}],
	}}
	var d2: Dictionary = PanelContentScript.build("ip_media", GameStateScript.default_player(), Callable(), ctx)
	check(not bool(d2.get("empty", true)), "有知识产权上下文非空")
	check(_find_section(d2, "知识产权").get("rows", []).size() >= 1, "知识产权分区有行")
	check(_find_section(d2, "媒体机构").get("rows", []).size() >= 1, "媒体机构分区有行")

func _test_manufacturing_panel() -> void:
	# 无上下文时经营面板为空态。
	var base: Dictionary = PanelContentScript.build("business", GameStateScript.default_player(), Callable(), {})
	check(bool(base.get("empty", true)), "无产业上下文时经营面板空态")
	var ctx: Dictionary = {"manufacturing": {
		"money": 8000000, "mode": "own_factory", "mode_name": "开厂", "headcount": 12,
		"labor_factor": 0.6, "efficiency": 1.0, "bottleneck": "labor", "effective_capacity": 60.0,
		"safety": 0.5, "automation": 0.0, "active_disruptions": [],
		"staff": [{"id": "unskilled", "name": "普工", "count": 12}],
		"materials": [{"id": "steel", "qty": 180.0}],
		"products": [{"id": "steel_part", "name": "钢制零件", "qty": 82.0}],
		"orders": [{"index": 0, "name": "钢制零件", "quantity": 50.0, "delivered": 50.0, "fulfilled": true}],
	}}
	var d: Dictionary = PanelContentScript.build("business", GameStateScript.default_player(), Callable(), ctx)
	check(not bool(d.get("empty", true)), "有工厂上下文非空")
	check(_find_section(d, "工厂概况").get("rows", []).size() >= 1, "工厂概况分区有行")
	check(_find_section(d, "产线人员").get("rows", []).size() >= 1, "产线人员分区有行")
	check(_find_section(d, "原料库存").get("rows", []).size() >= 1, "原料库存分区有行")
	check(_find_section(d, "成品库存").get("rows", []).size() >= 1, "成品库存分区有行")
	check(_find_section(d, "订单").get("rows", []).size() >= 1, "订单分区有行")

func _test_trade_panel() -> void:
	var ctx: Dictionary = {"trade": {"shipments": [{
		"index": 0, "goods": "钢材", "goods_value": 50000, "stage": "contract",
		"stage_name": "签约", "incoterm": "FOB", "transport": "sea", "freight": 50000, "settled": false,
	}]}}
	var d: Dictionary = PanelContentScript.build("business", GameStateScript.default_player(), Callable(), ctx)
	check(not bool(d.get("empty", true)), "有外贸上下文非空")
	check(_find_section(d, "外贸单据").get("rows", []).size() >= 1, "外贸单据分区有行")

func _test_mining_panel() -> void:
	var ctx: Dictionary = {"mining": {
		"mine": {"mineral": "iron", "mineral_name": "铁矿", "concession": true, "explored": true,
			"reserve": 1200000.0, "grade": 0.4, "workers": 0, "safety": 0.5,
			"stockpile_ore": 500.0, "refined_metal": 120.0, "revenue": 96000, "occupational_disease": "尘肺病"},
		"energy_prices": [{"key": "oil", "name": "石油", "price": 500000}, {"key": "power", "name": "电力", "price": 80000}],
		"projects": [{"name": "光伏", "kind": "solar", "capacity": 100.0}],
		"futures": [{"energy": "oil", "name": "石油", "index": 0, "amount": 100.0, "lock_price": 500000, "settled": false}],
		"contracts": [{"energy": "oil", "name": "石油", "amount": 1000.0, "fixed_price": 500000, "years": 1.0}],
		"last_accident": {"occurred": true, "kind_name": "塌方", "injured": 2, "fine": 100000},
	}}
	var d: Dictionary = PanelContentScript.build("business", GameStateScript.default_player(), Callable(), ctx)
	check(not bool(d.get("empty", true)), "有矿业上下文非空")
	check(_find_section(d, "矿场概况").get("rows", []).size() >= 1, "矿场概况分区有行")
	check(_row_value(_find_section(d, "矿场概况"), "职业病") == "尘肺病", "矿场概况展示职业病")
	check(_find_section(d, "能源价格").get("rows", []).size() >= 1, "能源价格分区有行")
	check(_find_section(d, "新能源项目").get("rows", []).size() >= 1, "新能源项目分区有行")
	check(_find_section(d, "能源期货").get("rows", []).size() >= 1, "能源期货分区有行")
	check(_find_section(d, "能源长约").get("rows", []).size() >= 1, "能源长约分区有行")
	check(_find_section(d, "最近矿难").get("rows", []).size() >= 1, "最近矿难分区有行")

func _test_primary_panel() -> void:
	var ctx: Dictionary = {"agriculture": {"primary": {
		"fishery": {"boats": 2, "resource_ratio": 0.8, "closed_season": false, "overfish": 200.0},
		"forest": {"forest_type_name": "用材林", "area": 100.0, "trees": 9850.0, "wood": 100.0, "fire_risk": 0.05},
		"hunter": {"license": true, "wanted_level": 0, "money": 105600},
		"ecology": {"resource_ratio": 0.9, "soil_quality": 0.95, "erosion": 0.02},
	}}}
	var d: Dictionary = PanelContentScript.build("agriculture", GameStateScript.default_player(), Callable(), ctx)
	check(not bool(d.get("empty", true)), "有农林牧渔上下文非空")
	check(_find_section(d, "渔场").get("rows", []).size() >= 1, "渔场分区有行")
	check(_find_section(d, "林场").get("rows", []).size() >= 1, "林场分区有行")
	check(_find_section(d, "狩猎").get("rows", []).size() >= 1, "狩猎分区有行")
	check(_find_section(d, "生态").get("rows", []).size() >= 1, "生态分区有行")

func _test_dining_panel() -> void:
	var ctx: Dictionary = {"dining": {
		"name": "小馆", "money": 1200000, "mode": "chain", "mode_name": "连锁门店",
		"stores": 3, "reputation": 60.0, "hygiene": 72.0, "brand": 45.0,
		"stars": 4, "stars_name": "四星", "headcount": 5, "turnover": 2.4,
		"menu": [{"key": "home_style", "name": "家常小炒", "price": 4000, "cost": 2100, "margin": 0.475}],
		"staff": [{"role": "chef", "name": "主厨", "count": 1}],
		"products": [{"key": "home_style", "qty": 20.0}],
		"certifications": ["hygiene_a"],
	}}
	var d: Dictionary = PanelContentScript.build("business", GameStateScript.default_player(), Callable(), ctx)
	check(not bool(d.get("empty", true)), "有餐饮上下文非空")
	check(_find_section(d, "餐厅概况").get("rows", []).size() >= 1, "餐厅概况分区有行")
	check(_find_section(d, "菜单").get("rows", []).size() >= 1, "菜单分区有行")
	check(_find_section(d, "员工").get("rows", []).size() >= 1, "员工分区有行")
	check(_find_section(d, "预包装库存").get("rows", []).size() >= 1, "预包装库存分区有行")
	check(_find_section(d, "食安认证").get("rows", []).size() >= 1, "食安认证分区有行")

func _test_fashion_panel() -> void:
	var ctx: Dictionary = {"fashion": {
		"name": "无名品牌", "positioning": "luxury", "positioning_name": "奢侈",
		"money": 1000000, "reputation": 50.0, "fame": 32.0, "relevance": 83.0,
		"brand_value": 1500000, "premium": 3.0, "stores": 1, "age_years": 3.5,
		"trend_phase": "emerging", "trend_phase_name": "新兴", "trend_hot": "服装设计",
		"designs": [{"discipline": "apparel", "discipline_name": "服装设计", "score": 45.0, "grade": "mediocre"}],
		"inventory": [{"key": "handbag", "qty": 10, "price": 60000}],
	}}
	var d: Dictionary = PanelContentScript.build("business", GameStateScript.default_player(), Callable(), ctx)
	check(not bool(d.get("empty", true)), "有时尚上下文非空")
	check(_find_section(d, "品牌概况").get("rows", []).size() >= 1, "品牌概况分区有行")
	check(_find_section(d, "时尚潮流").get("rows", []).size() >= 1, "时尚潮流分区有行")
	check(_find_section(d, "作品").get("rows", []).size() >= 1, "作品分区有行")
	check(_find_section(d, "库存").get("rows", []).size() >= 1, "库存分区有行")

func _test_sports_panel() -> void:
	var ctx: Dictionary = {"sports": {
		"stage": "pro_contract", "age": 24, "form": 62.0, "market_value": 3000000,
		"wage": 500000, "injury_days": 0.0, "ban_days": 0.0,
		"appearances": 10, "goals": 4, "sponsors": 1,
		"club": "本地球会", "club_division": "top", "budget": 12000000, "club_reputation": 42.0,
		"national_team": "中国", "last_tournament": {"competition": "world_cup", "champion": "本地球会", "reward": 30000000},
		"standings": [
			{"id": "home_club", "played": 10, "points": 21, "goals_for": 18, "goals_against": 10},
			{"id": "rival_club", "played": 10, "points": 15, "goals_for": 12, "goals_against": 14},
		],
	}}
	var d: Dictionary = PanelContentScript.build("sports", GameStateScript.default_player(), Callable(), ctx)
	check(not bool(d.get("empty", true)), "有体育上下文非空")
	check(_find_section(d, "球员生涯").get("rows", []).size() >= 1, "球员生涯分区有行")
	check(_find_section(d, "所属球会").get("rows", []).size() >= 1, "所属球会分区有行")
	check(_find_section(d, "积分榜").get("rows", []).size() >= 1, "积分榜分区有行")
	check(_find_section(d, "最近国际赛事").get("rows", []).size() >= 1, "最近国际赛事分区有行")

func _test_events_panel() -> void:
	var ctx: Dictionary = {"events": {
		"type": "concert", "type_name": "演唱会", "name": "演唱会",
		"stage": "live", "stage_name": "现场", "capacity": 20000, "sold": 5000,
		"ticket_price": 6800, "budget": 5000000, "revenue": 34000000, "cost": 2000000,
		"reputation": 55.0, "attendance": 5000, "sponsors": 1, "incidents": 0,
		"planner_level": 2, "planner_exp": 250, "planner_events": 1,
	}}
	var d: Dictionary = PanelContentScript.build("events", GameStateScript.default_player(), Callable(), ctx)
	check(not bool(d.get("empty", true)), "有会展上下文非空")
	check(_find_section(d, "我的活动").get("rows", []).size() >= 1, "我的活动分区有行")
	check(_find_section(d, "策划职业").get("rows", []).size() >= 1, "策划职业分区有行")

func _test_honors_panel() -> void:
	var ctx: Dictionary = {"honors": {
		"achievement": 90.0, "relations": 0.0, "reputation": 12.0, "privileges": 1,
		"honors": [{"name": "学术成就奖", "category": "学术", "prestige": 88.0}],
		"hall_size": 1, "hall_active": 1,
	}}
	var d: Dictionary = PanelContentScript.build("awards", GameStateScript.default_player(), Callable(), ctx)
	check(not bool(d.get("empty", true)), "有荣誉上下文非空")
	check(_find_section(d, "荣誉档案").get("rows", []).size() >= 1, "荣誉档案分区有行")
	check(_find_section(d, "已获荣誉").get("rows", []).size() >= 1, "已获荣誉分区有行")
	check(_find_section(d, "名人堂").get("rows", []).size() >= 1, "名人堂分区有行")

func _test_police_panel() -> void:
	var ctx: Dictionary = {"police": {
		"case": {
			"crime": "theft", "region": "beijing", "stage": "取证", "role": "刑侦",
			"evidence_score": 0.3, "leads": 0.5, "legality": 1.0, "solve_probability": 0.4, "wrongful": false,
			"evidence": [{"name": "物证", "value": 0.3}, {"name": "监控", "value": 0.5}],
		},
		"firm": {
			"name": "测试安保", "staff": 4, "funds": 100000, "reputation": 0.5,
			"contracts": [{"name": "押运", "fee": 200000, "resolved": false, "failure": false}],
		},
	}}
	var d: Dictionary = PanelContentScript.build("legal", GameStateScript.default_player(), Callable(), ctx)
	check(not bool(d.get("empty", true)), "有警务上下文非空")
	check(_find_section(d, "经办案件").get("rows", []).size() >= 1, "经办案件分区有行")
	check(_find_section(d, "证据链").get("rows", []).size() >= 1, "证据链分区有行")
	check(_find_section(d, "安保公司").get("rows", []).size() >= 1, "安保公司分区有行")
	check(_find_section(d, "安保业务").get("rows", []).size() >= 1, "安保业务分区有行")

func _test_emergency_panel() -> void:
	var ctx: Dictionary = {"emergency": {
		"incident": {
			"type": "消防", "stage": "善后", "severity": 0.6, "at_risk": 200, "trapped": 40,
			"response_minutes": 12.5, "deaths": 3, "injured": 20, "rescued": 35, "fault": "command_fault",
			"stress_added": 8.0, "penalty_paid": 30000,
			"triage": {"treated": 15.0, "untreated": 5.0},
		},
		"org": {"name": "测试志愿队", "volunteers": 10, "equipment": 2, "funds": 100000, "reputation": 0.4},
	}}
	var d: Dictionary = PanelContentScript.build("rescue", GameStateScript.default_player(), Callable(), ctx)
	check(not bool(d.get("empty", true)), "有应急上下文非空")
	check(_find_section(d, "处置事件").get("rows", []).size() >= 1, "处置事件分区有行")
	check(_row_value(_find_section(d, "处置事件"), "心理创伤") != "", "处置事件展示心理创伤")
	check(_row_value(_find_section(d, "处置事件"), "已缴罚款") != "", "处置事件展示已缴罚款")
	check(_find_section(d, "检伤分诊").get("rows", []).size() >= 1, "检伤分诊分区有行")
	check(_find_section(d, "志愿救援队").get("rows", []).size() >= 1, "志愿救援队分区有行")

func _test_environment_panel() -> void:
	var ctx: Dictionary = {"environment": {
		"city": {
			"garbage_sorting": 0.8, "recycling_rate": 0.4, "sewage_treatment": 0.9,
			"air_quality": 0.7, "pollution_index": 0.3, "health_index": 0.95,
			"reputation": 0.9, "lawsuit_open": false,
		},
		"enterprise": {
			"name": "我的企业", "emissions": 120.0, "quota": 100.0, "credits": 30.0,
			"balance": -10.0, "esg": 72.0, "fines": 0,
		},
		"org": {"kind": "env_company", "name": "环保企业", "funds": 500000, "reputation": 0.5, "emission_cut": 15.0},
	}}
	var d: Dictionary = PanelContentScript.build("environment", GameStateScript.default_player(), Callable(), ctx)
	check(not bool(d.get("empty", true)), "有环保上下文非空")
	check(_find_section(d, "城市环保").get("rows", []).size() >= 1, "城市环保分区有行")
	check(_find_section(d, "企业碳账户").get("rows", []).size() >= 1, "企业碳账户分区有行")
	check(_find_section(d, "环保组织").get("rows", []).size() >= 1, "环保组织分区有行")

func _test_municipal_panel() -> void:
	var ctx: Dictionary = {"municipal": {
		"city": {
			"facilities": [{"name": "道路", "condition": 0.8, "grade": "合格"}],
			"commute_factor": 1.4, "nuisance": 0.3, "unresolved_complaints": 2, "franchises": 1,
		},
		"hub": {"pending": 3, "processed": 5, "lost": 1, "damaged": 1, "claims_paid": 10000, "overload": 0.5},
		"courier": {"name": "张三", "deliveries": 120, "rank_index": 1, "income": 5000, "reputation": 0.6},
	}}
	var d: Dictionary = PanelContentScript.build("municipal", GameStateScript.default_player(), Callable(), ctx)
	check(not bool(d.get("empty", true)), "有市政上下文非空")
	check(_find_section(d, "市政设施").get("rows", []).size() >= 1, "市政设施分区有行")
	check(_find_section(d, "通行与扰民").get("rows", []).size() >= 1, "通行与扰民分区有行")
	check(_find_section(d, "邮政枢纽").get("rows", []).size() >= 1, "邮政枢纽分区有行")
	check(_find_section(d, "快递员").get("rows", []).size() >= 1, "快递员分区有行")

func _test_debt_panel() -> void:
	var ctx: Dictionary = {"debt": {
		"loan": {"business": "micro_loan", "principal": 100000, "outstanding": 90000, "rate": 0.12, "status": "active", "predatory": false, "compliant": true},
		"lend": {"business": "private_lending", "principal": 500000, "outstanding": 500000, "rate": 0.12, "status": "active", "compliant": true, "illegal_collection": true, "modes": 2},
		"lender": {"license": false, "violations": 1, "reputation": 0.4},
		"pawns": [{"item": "手表", "amount": 500000, "loan": "pawn-1"}],
	}}
	var d: Dictionary = PanelContentScript.build("debt", GameStateScript.default_player(), Callable(), ctx)
	check(not bool(d.get("empty", true)), "有债务上下文非空")
	check(_find_section(d, "负债概览").get("rows", []).size() >= 1, "负债概览分区有行")
	check(_find_section(d, "我的借款").get("rows", []).size() >= 1, "我的借款分区有行")
	check(_find_section(d, "我放出的贷款").get("rows", []).size() >= 1, "我放出的贷款分区有行")
	check(_find_section(d, "放贷人").get("rows", []).size() >= 1, "放贷人分区有行")
	check(_find_section(d, "典当物").get("rows", []).size() >= 1, "典当物分区有行")

func _test_consumer_panel() -> void:
	var ctx: Dictionary = {"consumer": {
		"order": {"amount": 100000, "category": "electronics", "defective": true, "fake": false, "status": "resolved", "refunded": 100000, "complaints": 1},
		"product": {"name": "商品", "price": 500000, "warranty_days": 365, "recalled": false},
		"merchant": {"name": "商家", "reputation": 0.3, "sales": 0.8, "fines": 200000, "compensation_paid": 50000, "delisted": false},
	}}
	var d: Dictionary = PanelContentScript.build("consumer", GameStateScript.default_player(), Callable(), ctx)
	check(not bool(d.get("empty", true)), "有消费者上下文非空")
	check(_find_section(d, "消费订单").get("rows", []).size() >= 1, "消费订单分区有行")
	check(_find_section(d, "商品").get("rows", []).size() >= 1, "商品分区有行")
	check(_find_section(d, "涉事商家").get("rows", []).size() >= 1, "涉事商家分区有行")

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
	var ctx: Dictionary = {"finance": {
		"credit": 720, "demand_rate": 0.012, "fixed_rate": 0.025, "loan_rate": 0.055,
		"debt_minor": 500000,
		"fixed_deposits": [{"principal": 1000000, "rate": 0.025, "term_days": 365, "matured": false}],
		"portfolio": {"items": [{"name": "科技成长", "qty": 10, "value": 600.0, "profit": 120.0}], "value": 600.0, "profit": 120.0},
		"securities": [{"key": "stock.tech", "name": "科技成长", "price": 60.0}],
	}}
	var d2: Dictionary = PanelContentScript.finance(player, Callable(), ctx)
	check_eq(_row_value(_find_section(d2, "信用与利率"), "银行信用"), "720", "信用分展示")
	check_eq(_row_value(_find_section(d2, "信用与利率"), "当前负债"), "5000", "负债主单位换算")
	check_eq(_row_value(_find_section(d2, "定期存款"), "365天 · 年息2.50%"), "10000", "定期存款展示")
	check_eq(_row_value(_find_section(d2, "证券持仓"), "科技成长 ×10"), "600（+120）", "持仓与盈亏")
	check_eq(_row_value(_find_section(d2, "行情"), "科技成长（stock.tech）"), "60.00", "行情报价")

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
