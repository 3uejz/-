extends "res://tests/test_base.gd"
## 世界运行时接线测试（R1/R5/R50、D1/D2）：
## 种子确定性地理、所在城市登记为活动区、区域随游戏内时钟演化、天气查询与展示。

const GameStateScript = preload("res://autoload/game_state.gd")
const SimHostScript = preload("res://sim/sim_host.gd")
const GeoDataScript = preload("res://sim/geo.gd")
const BaselineScript = preload("res://sim/baseline.gd")

func _suite_name() -> String:
	return "world_runtime"

func _setup(seed: int = 5):
	var state = GameStateScript.new()
	state.new_game(seed)
	return SimHostScript.new(state, seed)

func run_tests() -> void:
	_test_home_region_registered()
	_test_regions_view()
	_test_weather_now()
	_test_advance_evolves_region()
	_test_deterministic()
	_test_set_home_region()
	_test_weather_forecast()
	_test_persist_and_reload()
	_test_travel_persists()
	_test_domain_wake_advances()
	_test_domain_wake_bindings()
	_test_mfg_trade_and_research_bindings()
	_test_consumer_civil_bindings()
	_test_appearance_aesthetics_bindings()
	_test_military_bindings()
	_test_workplace_bindings()
	_test_company_financing_bindings()
	_test_finance_runtime()
	_test_acquaintances_and_marriage()
	_test_property_market_and_purchase()
	_test_inheritance_settles()
	_test_childbirth()
	_test_property_monthly_settlement()
	_test_death_summary()
	_test_sibling_linking()
	_test_pet_adoption_and_care()
	_test_survival_runtime_persistence()
	_test_adoption_and_guardianship()
	_test_child_growth_and_mortality()
	_test_mental_runtime()
	_test_spirit_runtime()
	_test_org_runtime()
	_test_language_runtime()
	_test_disability_runtime()
	_test_agriculture_runtime()
	_test_digital_runtime()
	_test_late_tech_runtime()
	_test_ip_media_runtime()
	_test_manufacturing_runtime()
	_test_trade_runtime()
	_test_mining_runtime()
	_test_primary_runtime()
	_test_dining_runtime()
	_test_fashion_runtime()
	_test_sports_runtime()
	_test_events_runtime()
	_test_honors_runtime()
	_test_police_runtime()
	_test_emergency_runtime()
	_test_environment_runtime()
	_test_municipal_runtime()
	_test_debt_runtime()
	_test_consumer_runtime()
	_test_welfare_runtime()
	_test_funeral_runtime()
	_test_metaphysics_runtime()
	_test_anomaly_runtime()
	_test_medical_runtime()
	_test_content_industry_runtime()
	_test_engineering_runtime()
	_test_professional_runtime()
	_test_life_services_runtime()
	_test_transport_infra_runtime()
	_test_social_runtime()

## 逐块推进并重置基本需求，避免长周期模拟中饿死/渴死，用于隔离被测系统。
func _advance_alive(host, days: int) -> void:
	var chunk := 180
	var steps := (days * 1440) / chunk
	for _i in steps:
		var ph: Dictionary = host.player()["attrs"]["physiological"]
		ph["hunger"] = 100.0
		ph["thirst"] = 100.0
		ph["health"] = 100.0
		host.advance(chunk)

func _test_home_region_registered() -> void:
	var host = _setup()
	check(host.geo.count() > 0, "地理已按种子生成")
	check_eq(host.current_region_id(), "cn.beijing", "无有效 nation 时降级首发国家 CN 的首个核心城市")
	check(host.regions.has_region("cn.beijing"), "所在区域已登记")
	check(host.regions.is_active("cn.beijing"), "所在区域为活动区")
	check(host.weather.has_region("cn.beijing"), "所在区域已绑定气候带")

func _test_regions_view() -> void:
	var host = _setup()
	var view: Array = host.regions_view()
	check_eq(view.size(), 1, "仅所在区域在视图中")
	check_eq(String(view[0]["region_key"]), "cn.beijing", "视图含所在区域键")
	check(int(view[0]["population"]) > 0, "视图人口为正")

func _test_weather_now() -> void:
	var host = _setup()
	var w: Dictionary = host.weather_now()
	check(not w.is_empty(), "天气快照非空")
	for key in ["condition", "temperature", "humidity", "wind", "phase"]:
		check(w.has(key), "天气含字段 %s" % key)

func _test_advance_evolves_region() -> void:
	var host = _setup()
	var before = host.regions.get_region("cn.beijing")
	var econ0: float = before.economy
	var last0: int = before.last_simulated_minute
	host.advance(1440)
	var after = host.regions.get_region("cn.beijing")
	check_eq(after.last_simulated_minute, last0 + 1440, "区域推进到当前时刻")
	check(after.economy > econ0, "区域经济随日增长")
	check_eq(host.now_minutes(), 1440, "游戏内时钟同步推进")

func _test_deterministic() -> void:
	var a = _setup(9)
	var b = _setup(9)
	check_eq(a.current_region_id(), b.current_region_id(), "同种子所在区域一致")
	a.advance(1440)
	b.advance(1440)
	check_eq(str(a.regions_view()), str(b.regions_view()), "同种子区域演化一致")
	check_eq(str(a.weather_now()), str(b.weather_now()), "同种子天气一致")

func _test_set_home_region() -> void:
	var host = _setup()
	check(host.set_home_region("cn.shanghai"), "切换到上海成功")
	check_eq(host.current_region_id(), "cn.shanghai", "所在区域更新")
	check(host.regions.is_active("cn.shanghai"), "新所在区域为活动区")
	check(host.regions.get_region("cn.shanghai").population > 0, "新所在区域人口取自地理")
	check(not host.set_home_region("xx.nowhere"), "未知区域被拒绝")

func _test_weather_forecast() -> void:
	var state = GameStateScript.new()
	state.new_game(13)
	var host = SimHostScript.new(state, 13)
	var data: Dictionary = host.weather_panel_data()
	check(data.has("condition"), "面板数据含当前天气")
	var fc: Array = data.get("forecast", [])
	check_eq(fc.size(), 7, "预报 7 日")
	if not fc.is_empty():
		check_eq(String(fc[0]["label"]), "今日", "首日标记为今日")
		check(String(fc[0]["value"]).contains("°C"), "预报含气温区间")

func _test_persist_and_reload() -> void:
	var state = GameStateScript.new()
	state.new_game(13)
	var host = SimHostScript.new(state, 13)
	host.advance(2880)
	var saved: Array = state.world_delta.get("regions", [])
	check_eq(saved.size(), 1, "区域增量写入 world_delta.regions")
	check_eq(String(saved[0]["region_key"]), "cn.beijing", "增量含所在区域键")
	var allowed: Array = ["region_key", "population", "price_index", "safety", "last_simulated_minute", "snapshot"]
	for k in saved[0].keys():
		check(allowed.has(String(k)), "字段符合 region_delta 契约：%s" % k)
	var before = host.regions.get_region("cn.beijing")
	var pop_before: int = before.population
	var last_before: int = before.last_simulated_minute
	# 模拟读档：同一状态对象新建 SimHost，应从 world_delta 恢复区域。
	var reloaded = SimHostScript.new(state, 13)
	var r2 = reloaded.regions.get_region("cn.beijing")
	check(r2 != null, "读档后所在区域已恢复")
	if r2 != null:
		check_eq(r2.last_simulated_minute, last_before, "读档保留模拟时刻")
		check_eq(r2.population, pop_before, "读档保留人口")
	check(reloaded.weather.has_region("cn.beijing"), "读档后重新绑定气候带")

func _test_travel_persists() -> void:
	var state = GameStateScript.new()
	state.new_game(13)
	var host = SimHostScript.new(state, 13)
	var cities: Array = host.geo.nodes_at_level(GeoDataScript.GeographicLevel.CITY)
	var target: String = ""
	for c in cities:
		if String(c) != host.current_region_id():
			target = String(c)
			break
	check(target != "", "存在可搬迁的其它城市")
	if target == "":
		return
	check(host.set_home_region(target), "搬迁成功")
	check_eq(String(state.player.get("region_id", "")), target, "所在区域写入玩家存档字段")
	var reloaded = SimHostScript.new(state, 13)
	check_eq(reloaded.current_region_id(), target, "读档保留搬迁后的所在区域")
	check(reloaded.regions.has_region(target), "读档后目的是地区域已登记")

func _test_domain_wake_advances() -> void:
	var state = GameStateScript.new()
	state.new_game(13)
	var host = SimHostScript.new(state, 13)
	host.domain_register("proj:1", "project", {"region_id": "cn.beijing", "rate": 1.0, "total": 60.0})
	check_eq(host.domain_wake.entry_count(), 1, "领域实体已注册")
	host.advance(60)
	check(host.domain_wake.is_resolved("proj:1"), "游戏内时钟推进后在建工程补算至完成")
	host.advance(60)
	check(host.domain_wake.is_resolved("proj:1"), "已完成条目再次推进保持完成（幂等）")

func _test_domain_wake_bindings() -> void:
	var state = GameStateScript.new()
	state.new_game(312)
	var host = SimHostScript.new(state, 312)
	host.bind(state)
	# 工程：承接即注册，休眠期满回写为完成。
	check(bool(host.eng_new_contractor("休眠建设", "first").get("ok", false)), "成立工程公司")
	check(bool(host.eng_take_project("休眠工程", 50000000).get("ok", false)), "承接工程")
	var pid: String = String(host._eng_project.get("id", ""))
	var chain_len: int = host.engineering.CHAIN.size()
	var stage_minutes: int = chain_len * BaselineScript.WAKE_PROJECT_STAGE_DAYS * BaselineScript.WAKE_MINUTES_PER_DAY
	host.domain_wake.advance_to(host.domain_wake.now_minute() + stage_minutes)
	check_eq(host._apply_wake_results().size(), 1, "工程完成回写一次")
	check_eq(String(host._eng_project.get("stage", "")), "completed", "工程休眠后回写完成")
	check(bool(host.domain_wake.get_entry("eng:%s" % pid).get("result", {}).get("applied", false)), "工程结果标记已消费")
	check_eq(host._apply_wake_results().size(), 0, "工程结果重复回写为幂等空集")
	# 案件：过审限未破则转冷案。
	host.police_start_case("theft", "detective")
	var case_entry_id: String = ""
	for eid in host.domain_wake.all_entries():
		if String(host.domain_wake.get_entry(String(eid)).get("kind", "")) == "case":
			case_entry_id = String(eid)
	check(not case_entry_id.is_empty(), "案件已登记休眠补算")
	host.domain_wake.advance_to(host.domain_wake.now_minute() + BaselineScript.WAKE_CASE_LIMIT_DAYS * BaselineScript.WAKE_MINUTES_PER_DAY + 1)
	host._apply_wake_results()
	check_eq(String(host._police_case.get("stage", "")), host.police.STAGE_COLD, "案件过审限转冷案")
	# 放贷：休眠期间按年利率累计逾期利息。
	check(bool(host.debt_lend("private_lending", 100000, 0.1).get("ok", false)), "放贷登记")
	var lend_id: String = String(host._debt_lend.get("id", ""))
	host.domain_wake.advance_to(host.domain_wake.now_minute() + 365 * BaselineScript.WAKE_MINUTES_PER_DAY)
	host._apply_wake_results()
	check(float(host._debt_lend.get("accrued_interest", 0.0)) > 0.0, "放贷利息随休眠累计")
	check(bool(host.domain_wake.get_entry("loan:%s" % lend_id).get("result", {}).has("interest")), "贷款条目含利息结果")
	# 灾害：72 小时后进入善后。
	check(bool(host.emergency_new_incident("flood", 0.6).get("ok", false)), "创建灾害事件")
	host.domain_wake.advance_to(host.domain_wake.now_minute() + BaselineScript.WAKE_DISASTER_HOURS * 60 + 1)
	host._apply_wake_results()
	check_eq(String(host._incident.get("stage", "")), host.emergency.STAGE_AFTERMATH, "灾害结束转善后")
	# 读档：补算运行态与已完成/已登记领域状态均可恢复。
	var reloaded = SimHostScript.new(state, 312)
	reloaded.bind(state)
	check(not reloaded.domain_wake.get_entry("eng:%s" % pid).is_empty(), "读档恢复工程补算条目")
	check_eq(String(reloaded._eng_project.get("stage", "")), "completed", "读档恢复工程完成状态")
	check_eq(String(reloaded._police_case.get("stage", "")), reloaded.police.STAGE_COLD, "读档恢复冷案")
	check(float(reloaded._debt_lend.get("accrued_interest", 0.0)) > 0.0, "读档恢复贷款利息")
	check_eq(String(reloaded._incident.get("stage", "")), reloaded.emergency.STAGE_AFTERMATH, "读档恢复灾害善后")


func _test_mfg_trade_and_research_bindings() -> void:
	var state = GameStateScript.new()
	state.new_game(313)
	var host = SimHostScript.new(state, 313)
	host.bind(state)
	host.economy.add_money(host.account_id(), 200000000, "test")
	# 工厂生产：原料→成品，碳排进入企业碳账户。
	check(bool(host.found_factory("own_factory").get("ok", false)), "开办工厂")
	check(bool(host.mfg_purchase("steel", 100.0).get("ok", false)), "采购钢材")
	check(bool(host.mfg_hire("unskilled", 20).get("ok", false)), "招募产线工人")
	var emissions0: float = float(host._env_enterprise.get("emissions", 0.0))
	var pr: Dictionary = host.mfg_produce("steel_part", 10.0)
	check(bool(pr.get("ok", false)), "生产钢制零件")
	check(float(host._env_enterprise.get("emissions", 0.0)) > emissions0, "生产碳排计入企业账户")
	# 成品出口：扣成品库存并生成含吨位的外贸单据。
	var stock: float = float(host._factory["products"].get("steel_part", 0.0))
	check(stock > 5.0, "成品入库")
	var ex: Dictionary = host.mfg_export("steel_part", 5.0, "新加坡")
	check(bool(ex.get("ok", false)), "成品出口建单")
	check_eq(int(host._shipments.size()), 1, "外贸单据入列")
	check(int(ex.get("goods_value", 0)) > 0, "单据含货值")
	check_near(float(ex.get("quantity_ton", 0.0)), 5.0 * BaselineScript.MFG_TONS_PER_UNIT, 0.0001, "按单位吨位折算")
	check_near(float(host._factory["products"].get("steel_part", 0.0)), stock - 5.0, 0.0001, "成品库存扣减")
	check(not host._shipments.is_empty() and String(host._shipments[0].get("goods", "")) == "钢制零件", "单据商品名取配方")
	# 工资：欠薪触发罢工，补足后复工。
	check(bool(host.mfg_hire("unskilled", 2).get("ok", false)), "招募工人")
	var now: int = host.now_minutes()
	var payroll: int = host.manufacturing.payroll_cost(host._factory)
	host._factory["money"] = maxi(0, payroll - 1)
	host._mfg_tick(now, now + 31 * 1440)
	check(host.manufacturing.has_disruption(host._factory, "strike"), "欠薪触发罢工")
	host._factory["money"] = payroll * 2
	host._mfg_tick(now + 31 * 1440, now + 62 * 1440)
	check(not host.manufacturing.has_disruption(host._factory, "strike"), "补足工资后复工")
	# 科研：经费→立项→推进→发表→专利登记。
	check(bool(host.research_fund(5000000).get("ok", false)), "注入科研经费")
	host.player()["skills"] = [{"content_key": "skill.academic", "level": 20}]
	check(bool(host.research_start("固态电池界面").get("ok", false)), "科研立项")
	for _i in 8:
		var ar: Dictionary = host.research_advance()
		if not bool(ar.get("ok", false)):
			break
		if String(ar.get("stage", "")) in ["published", "rejected"]:
			break
	check(bool(host._research.get("project", {}).get("published", false)), "科研成果发表")
	var cr: Dictionary = host.research_collect()
	check(bool(cr.get("ok", false)), "成果结算")
	check(float(host._research.get("prestige", 0.0)) > 0.0, "累计声望入账")
	check(int(host._research.get("income", 0)) > 0, "成果收入入账")
	check(not bool(host.research_collect().get("ok", false)), "成果不可重复结算")
	host._research["project"]["quality"] = 80.0
	var ptr: Dictionary = host.research_file_patent()
	check(bool(ptr.get("ok", false)), "科研专利登记")
	check(not String((ptr.get("ip", {}) as Dictionary).get("id", "")).is_empty(), "专利生成知识产权")
	check_eq(host._ips.size(), 1, "知识产权库含专利")
	# 读档恢复：工厂/单据/科研/专利。
	var reloaded = SimHostScript.new(state, 313)
	reloaded.bind(state)
	check(not reloaded._factory.is_empty(), "读档恢复工厂")
	check_eq(reloaded._shipments.size(), 1, "读档恢复外贸单据")
	check(not reloaded._research.is_empty(), "读档恢复科研运行态")
	check(bool(reloaded._research.get("project", {}).get("patented", false)), "读档恢复专利标记")
	check_eq(reloaded._ips.size(), 1, "读档恢复知识产权")


func _test_consumer_civil_bindings() -> void:
	var state = GameStateScript.new()
	state.new_game(314)
	var host = SimHostScript.new(state, 314)
	host.bind(state)
	host.economy.add_money(host.account_id(), 100000000, "test")
	# 消费纠纷立案：缺陷商品按三倍标的。
	check(bool(host.consumer_new_order(100000, "general", true, false).get("ok", false)), "创建消费订单")
	var cash0: int = int(host.economy.cash(host.account_id()))
	var sr: Dictionary = host.consumer_sue(0.8)
	check(bool(sr.get("ok", false)), "消费起诉立案")
	var claim: Dictionary = sr.get("claim", {})
	check_eq(int(claim.get("amount", 0)), 300000, "缺陷商品三倍标的")
	check(not host.civil_panel_data().is_empty(), "民事面板数据非空")
	check(not host.police_panel_data().has("case"), "民事立案不占用刑事案件位")
	# 开庭：强制掷点保证胜诉并完成判赔与执行。
	var lr: Dictionary = host.civil_litigate(1.0, 5, 0, 0.0)
	check(bool(lr.get("ok", false)), "民事开庭")
	check(bool((lr.get("judgment", {}) as Dictionary).get("won", false)), "强制掷点胜诉")
	check(int(lr.get("compensation", 0)) > 0, "判赔入账")
	check(int(host.economy.cash(host.account_id())) == cash0, "判决未执行前不入账")
	var er: Dictionary = host.civil_enforce()
	check(bool(er.get("ok", false)), "判决执行")
	check(int(er.get("recovered", 0)) > 0, "执行回收判赔")
	check(int(host.economy.cash(host.account_id())) > cash0, "执行后判赔入账")
	check(not bool(host.civil_enforce().get("ok", true)), "执行不可重复")
	# 逾期未开庭转冷案。
	var state2 = GameStateScript.new()
	state2.new_game(315)
	var host2 = SimHostScript.new(state2, 315)
	host2.bind(state2)
	host2.economy.add_money(host2.account_id(), 100000000, "test")
	host2.consumer_new_order(50000, "general", false, false)
	var sr2: Dictionary = host2.consumer_sue(0.5)
	check(bool(sr2.get("ok", false)), "第二案立案")
	host2.domain_wake.advance_to(host2.domain_wake.now_minute() + BaselineScript.WAKE_CASE_LIMIT_DAYS * BaselineScript.WAKE_MINUTES_PER_DAY + 1)
	host2._apply_wake_results()
	check_eq(String(host2._civil.get("claim", {}).get("stage", "")), "cold", "民事案件过审限转冷案")
	# 读档恢复民事运行态。
	var reloaded = SimHostScript.new(state, 314)
	reloaded.bind(state)
	check(not reloaded.civil_state().is_empty(), "读档恢复民事案件")
	check(bool(reloaded._civil.get("enforced", false)), "读档恢复执行状态")
	check_eq(int(reloaded._civil.get("judgment", {}).get("award", 0)), int(host._civil.get("judgment", {}).get("award", 0)), "读档恢复判赔")


func _test_appearance_aesthetics_bindings() -> void:
	var host = _setup(11)
	var panel: Dictionary = host.appearance_panel_data()
	check(not (panel.get("profile", {}) as Dictionary).is_empty(), "形象面板有档案")
	var charm0: float = float(panel.get("charm", 0.0))
	check_near(float(host.player()["attrs"]["ability"]["charm"]), charm0, 1e-6, "魅力同步到能力")
	host.economy.add_money(host.account_id(), 20000000, "test_appearance")
	var cash0: int = int(host.economy.cash(host.account_id()))
	var care: Dictionary = host.appearance_care("outfit", {"value": 90.0})
	check(bool(care.get("ok", false)), "形象护理成功")
	check(float(care.get("charm", 0.0)) > charm0, "穿搭提升魅力")
	check(int(host.economy.cash(host.account_id())) < cash0, "形象护理扣费")
	var cash1: int = int(host.economy.cash(host.account_id()))
	var ast: Dictionary = host.aesthetic_perform("injection", true)
	check(bool(ast.get("ok", false)), "医美成功立案")
	check(int(ast.get("remaining_minutes", 0)) > 0, "进入恢复期")
	check(int(host.economy.cash(host.account_id())) < cash1, "医美扣费")
	check(not bool(host.aesthetic_perform("injection", true).get("ok", true)), "恢复期拦截再次医美")
	host._aesthetic["last_failed_illegal"] = true
	var claim: Dictionary = host.aesthetic_claim()
	check(bool(claim.get("ok", false)), "医美失败可维权")
	check_eq(String((host._civil.get("claim", {}) as Dictionary).get("type", "")), "tort", "医美维权立案为侵权")
	var id0: Dictionary = host.appearance_verify_id()
	check(bool(id0.get("matched", false)), "未整形前证件匹配")
	host._appearance["height_cm"] = float(host._appearance.get("height_cm", 170.0)) + 20.0
	check(not bool(host.appearance_verify_id().get("matched", true)), "形象变化后证件不匹配")
	var re: Dictionary = host.appearance_reissue_id()
	check(bool(re.get("ok", false)), "可重办证件")
	check(bool(host.appearance_verify_id().get("matched", false)), "重办后证件匹配")
	var host2 = SimHostScript.new(host.state)
	var panel2: Dictionary = host2.appearance_panel_data()
	check(not (panel2.get("profile", {}) as Dictionary).is_empty(), "读档恢复形象档案")
	check_eq(String((host2._civil.get("claim", {}) as Dictionary).get("type", "")), "tort", "读档恢复医美诉讼")

func _test_military_bindings() -> void:
	var host = _setup(31)
	var p: Dictionary = host.player()
	p["birth_minutes"] = host.now_minutes() - int(21.0 * SimHostScript.MINUTES_PER_YEAR)
	p["education"] = [{"content_key": "edu.high_school", "status": "graduated"}]
	p["attrs"]["physiological"]["health"] = 100.0
	p["skills"] = [{"content_key": "skill.physique", "level": 10}, {"content_key": "skill.technical", "level": 10}]
	var er: Dictionary = host.military_enlist("army")
	check(bool(er.get("ok", false)), "符合条件可参军: %s" % str(er.get("missing", [])))
	check(bool(host.military_panel_data().get("enlisted", false)), "军籍面板生效")
	check(bool(host.military_train(10.0).get("ok", false)), "军训成功")
	p["military"]["merits"] = 6.0
	p["military"]["rank_started_minutes"] = host.now_minutes() - int(3.0 * SimHostScript.MINUTES_PER_YEAR)
	var pr: Dictionary = host.military_promote()
	check(bool(pr.get("ok", false)), "满足年限与军功可晋升")
	check_eq(String(pr.get("rank_name", "")), "上等兵", "晋升到上等兵")
	check(host.military_restricts("辞职"), "服役期间限制民事指令")
	var cash0: int = int(host.economy.cash(host.account_id()))
	p["military"]["enlisted_minutes"] = host.now_minutes() - int(4.0 * SimHostScript.MINUTES_PER_YEAR)
	var dis: Dictionary = host.military_discharge()
	check(bool(dis.get("ok", false)), "可退伍")
	check(int(dis.get("severance", 0)) > 0, "退伍发放退役金")
	check(int(host.economy.cash(host.account_id())) > cash0, "退役金入账")
	check(String(p["military"]["status"]) == "discharged", "军籍状态转为退伍")
	var host2 = SimHostScript.new(host.state, 31)
	check_eq(String((host2.player().get("military", {}) as Dictionary).get("status", "")), "discharged", "读档恢复军籍")
	host2.player()["military"]["status"] = "serving"
	var de: Dictionary = host2.military_desert()
	check(bool(de.get("ok", false)), "可当逃兵")
	check_eq(String((host2.player().get("military", {}) as Dictionary).get("status", "")), "deserter", "逃兵状态落档")


func _test_workplace_bindings() -> void:
	var host = _setup(32)
	host.player()["job"] = {
		"content_key": "job.engineer", "title": "工程师", "industry": "it",
		"salary": 9000, "performance": 60.0, "internal_reputation": 55.0, "status": "regular",
	}
	check(bool(host.workplace_join("reform").get("ok", false)), "可加入改革派")
	check(bool(host.workplace_found_faction("技术派").get("ok", false)), "可自立派系")
	check(bool(host.workplace_stay_neutral().get("ok", false)), "可保持中立")
	var pol: Dictionary = host.workplace_politics("credit_grab")
	check(pol.has("event") or pol.has("ok"), "办公室政治返回事件")
	var panel: Dictionary = host.workplace_panel_data()
	check(not panel.is_empty(), "职场面板有数据")
	check((panel.get("factions", {}) as Dictionary).size() >= 2, "职场面板含派系")
	var host2 = SimHostScript.new(host.state, 32)
	var panel2: Dictionary = host2.workplace_panel_data()
	check(not panel2.is_empty(), "读档恢复职场状态")
	check((panel2.get("factions", {}) as Dictionary).size() >= 2, "读档恢复派系")


func _test_company_financing_bindings() -> void:
	var host = _setup(33)
	host.economy.add_money(host.account_id(), 200000000, "test_company")
	var reg: Dictionary = host.company_register("sole_proprietor", "测试小店", 1000000)
	check(bool(reg.get("ok", false)), "注册个体户成功")
	check(bool(host.company_choose_site(60.0, 120000).get("ok", false)), "选址成功")
	check(bool(host.company_set_status(true).get("ok", false)), "开业成功")
	check(bool(host.company_stock("item.apple", 500, 500).get("ok", false)), "进货成功")
	check(bool(host.company_set_price("item.apple", 900).get("ok", false)), "定价成功")
	check(bool(host.company_hire(300000).get("ok", false)), "雇人成功")
	var finance: Dictionary = host.company_finance_raise("seed")
	check(bool(finance.get("ok", false)), "种子轮融资成功")
	check(float(finance.get("founder_equity", 0.0)) > 0.0, "融资后创始人有股权")
	var day0: int = host.day_index()
	host.advance(SimHostScript.MINUTES_PER_DAY)
	check(host.day_index() > day0, "时间推进一天")
	var panel: Dictionary = host.company_panel_data()
	check(not panel.is_empty(), "公司面板有数据")
	check(not (panel.get("products", []) as Array).is_empty(), "面板列出商品")
	check(bool(host.company_expand(1000000).get("ok", false)), "扩张成功")
	check(bool(host.company_tax().get("ok", false)), "纳税结算成功")
	var vam: Dictionary = host.company_settle_vam(100000)
	check(vam.has("passed"), "对赌结算返回结果")
	var ex: Dictionary = host.company_exit("ipo")
	check(bool(ex.get("ok", false)), "IPO 退出成功")
	var host2 = SimHostScript.new(host.state, 33)
	var panel2: Dictionary = host2.company_panel_data()
	check(not panel2.is_empty(), "读档恢复公司")
	check(bool((panel2.get("cap_table", {}) as Dictionary).get("exited", false)), "读档恢复退出状态")


## D8 金融运行态：证券买卖经主机写入 sim_runtime，读档恢复持仓与报价。
func _test_finance_runtime() -> void:
	var h = _setup(121)
	h.economy.issue_money(h.account_id(), 5000000, "test_fund")
	h.sync_finances()
	var r: Dictionary = h.buy_security("科技成长", 4)
	check(bool(r.get("ok", false)), "主机买入证券成功")
	check_eq(h.bank.holding_qty("stock.tech"), 4, "主机持仓正确")
	check(h.state.sim_runtime.get("finance", {}) is Dictionary, "金融运行态写入 sim_runtime")
	var price_before: float = float(h.bank.security_quote("stock.tech")["price"])
	h.advance(30 * 24 * 60)
	check(float(h.bank.security_quote("stock.tech")["price"]) != price_before, "时间推进后报价变化")
	var price_after: float = float(h.bank.security_quote("stock.tech")["price"])
	var reloaded = SimHostScript.new(h.state, 121)
	check_eq(reloaded.bank.holding_qty("stock.tech"), 4, "读档恢复证券持仓")
	check(abs(float(reloaded.bank.security_quote("stock.tech")["price"]) - price_after) < 1e-9, "读档恢复证券报价")
	var sell: Dictionary = reloaded.sell_security("科技成长", 4)
	check(bool(sell.get("ok", false)), "读档后卖出成功")
	check_eq(reloaded.bank.holding_qty("stock.tech"), 0, "卖出后清仓")
	# 贷款按日计息：跨日后负债增长，结算日随存档恢复。
	var loan: Dictionary = reloaded.bank_loan(100000, 365)
	check(bool(loan.get("ok", false)), "读档后贷款成功")
	var debt0: int = reloaded.economy.debt(reloaded.account_id())
	reloaded.advance(10 * 24 * 60)
	check(reloaded.economy.debt(reloaded.account_id()) > debt0, "跨日贷款计息")
	check(int(reloaded._last_finance_day) > 0, "结算日已记录")

func _test_acquaintances_and_marriage() -> void:
	var state = GameStateScript.new()
	state.new_game(13)
	var host = SimHostScript.new(state, 13)
	check_eq(host.acquaintances().size(), 8, "生成 8 名熟人")
	var npc: Dictionary = host.acquaintances()[0]
	var pid := String(npc.get("id", ""))
	check(not pid.is_empty(), "熟人含 id")
	check(not String(npc.get("name", "")).is_empty(), "熟人含姓名")
	check(not host.find_person(pid).is_empty(), "可按 id 找到熟人")
	check(not host.relations.get_relation(state.player, pid).is_empty(), "熟人已建立关系条目")
	check(bool(host.marry_with(pid).get("ok", false)), "结婚成功")
	check_eq(String(state.player.get("family", {}).get("spouse_id", "")), pid, "配偶写入存档字段")
	var reloaded = SimHostScript.new(state, 13)
	check_eq(String(reloaded.spouse().get("id", "")), pid, "读档恢复配偶档案")
	check(bool(reloaded.divorce().get("ok", false)), "离婚成功")
	check_eq(String(state.player.get("family", {}).get("spouse_id", "")), "", "离婚清除配偶字段")

func _test_property_market_and_purchase() -> void:
	var state = GameStateScript.new()
	state.new_game(21)
	var host = SimHostScript.new(state, 21)
	check(not host.property_listings().is_empty(), "所在城市有在售房源")
	host.economy.add_money(host.account_id(), 1000000000, "test")
	var lid := String(host.property_listings()[0].get("id", ""))
	check(bool(host.property_purchase(lid).get("ok", false)), "购房成功")
	check(not host.find_owned(lid).is_empty(), "购房后计入名下资产")
	var reloaded = SimHostScript.new(state, 21)
	check(not reloaded.find_owned(lid).is_empty(), "读档恢复名下房产")
	var still_listed := false
	for l in reloaded.property_listings():
		if String(l.get("id", "")) == lid:
			still_listed = true
	check(not still_listed, "已售房源不再挂牌")

func _test_inheritance_settles() -> void:
	var state = GameStateScript.new()
	state.new_game(34)
	var host = SimHostScript.new(state, 34)
	var npc: Dictionary = host.acquaintances()[0]
	host.marry_with(String(npc.get("id", "")))
	host.economy.add_money(host.account_id(), 500000, "test")
	var r = host.settle_inheritance()
	check(host.inheritance_settled(), "死亡结算已完成")
	check(float(r.get("net", 0.0)) >= 0.0, "遗产净额非负")
	check(not (r.get("allocations", []) as Array).is_empty(), "有配偶时按法定继承分配")
	var hist: Array = state.legacy.get("history", [])
	check(hist.size() >= 1 and String(hist[hist.size() - 1].get("kind", "")) == "death", "家族史记入死亡条目")

func _test_childbirth() -> void:
	var state = GameStateScript.new()
	state.new_game(55)
	var host = SimHostScript.new(state, 55)
	var npc: Dictionary = host.acquaintances()[0]
	host.marry_with(String(npc.get("id", "")))
	check(bool(host.try_conceive().get("ok", false)), "已婚可受孕")
	check(host.is_pregnant(), "进入妊娠状态")
	check(not bool(host.try_conceive().get("ok", true)), "妊娠中不可重复受孕")
	_advance_alive(host, 281)
	check(not host.is_pregnant(), "到期分娩后清除妊娠")
	check_eq(host.children().size(), 1, "分娩得到一名子女")
	check_eq((state.player.get("family", {}).get("children_ids", []) as Array).size(), 1, "子女 id 落档")
	check((state.world_delta.get("npcs", []) as Array).size() >= 1, "子女进入世界人口")
	check((state.legacy.get("lineage", []) as Array).size() >= 1, "族谱记入出生")

func _test_property_monthly_settlement() -> void:
	var state = GameStateScript.new()
	state.new_game(66)
	var host = SimHostScript.new(state, 66)
	host.economy.add_money(host.account_id(), 1000000000, "test")
	var lid := String(host.property_listings()[0].get("id", ""))
	check(bool(host.property_purchase(lid).get("ok", false)), "购房成功")
	var prop: Dictionary = host.find_owned(lid)
	check(not (prop.get("mortgage", {}) as Dictionary).is_empty(), "首套房形成房贷")
	var before := int((prop.get("mortgage", {}) as Dictionary).get("months_paid", 0))
	_advance_alive(host, 31)
	var after := int((prop.get("mortgage", {}) as Dictionary).get("months_paid", 0))
	check(after > before, "跨月结算推进房贷还款")

func _test_death_summary() -> void:
	var state = GameStateScript.new()
	state.new_game(77)
	var host = SimHostScript.new(state, 77)
	var npc: Dictionary = host.acquaintances()[0]
	host.marry_with(String(npc.get("id", "")))
	host.funeral_arrange("cremation", "", 1000000)
	host.advance(1, {"fatal": true})
	check(host.is_dead(), "致命事件导致死亡")
	check(host.inheritance_settled(), "死亡触发继承结算")
	var fst: Dictionary = (host.funeral_state().get("state", {}) as Dictionary).get("funeral", {})
	check(bool(fst.get("executed", false)), "死亡自动执行生前殡葬安排")
	var s: Dictionary = host.death_summary()
	check(String(s.get("name", "")) != "", "人生结算含姓名")
	check(float(s.get("estate_minor", 0.0)) >= 0.0, "人生结算含遗产估算")
	check(not (s.get("heirs", {}) as Dictionary).is_empty(), "人生结算含继承人")

func _test_sibling_linking() -> void:
	var state = GameStateScript.new()
	state.new_game(91)
	var host = SimHostScript.new(state, 91)
	var npc: Dictionary = host.acquaintances()[0]
	var partner_id := String(npc.get("id", ""))
	host.marry_with(partner_id)
	check(bool(host.try_conceive().get("ok", false)), "第一次受孕")
	_advance_alive(host, 281)
	check(bool(host.try_conceive().get("ok", false)), "第二次受孕")
	_advance_alive(host, 281)
	var kids: Array = host.children()
	check_eq(kids.size(), 2, "得到两名子女")
	var a: Dictionary = kids[0]
	var b: Dictionary = kids[1]
	check((a.get("family", {}).get("sibling_ids", []) as Array).has(String(b.get("id", ""))), "长子反查到幼弟")
	check((b.get("family", {}).get("sibling_ids", []) as Array).has(String(a.get("id", ""))), "幼弟反查到长子")
	# 配偶名下也应挂到子女。
	var partner: Dictionary = host.find_person(partner_id)
	var pkids: Array = partner.get("family", {}).get("children_ids", [])
	check(pkids.has(String(a.get("id", ""))) and pkids.has(String(b.get("id", ""))), "配偶名下登记两名子女")

func _test_pet_adoption_and_care() -> void:
	var state = GameStateScript.new()
	state.new_game(93)
	var host = SimHostScript.new(state, 93)
	check(host.pet_species_catalog().size() >= 5, "宠物物种目录非空")
	host.economy.add_money(host.account_id(), 100000000, "test")
	check(bool(host.adopt_pet("dog", "旺财").get("ok", false)), "领养狗成功")
	check_eq(host.pets().size(), 1, "宠物写入 player.pets")
	var rec: Dictionary = host.pets()[0]
	check(not String(rec.get("id", "")).is_empty(), "宠物含 id")
	check_eq(String(rec.get("content_key", "")), "pet.dog", "宠物 content_key 对齐")
	check_eq(String(rec.get("species", "")), "dog", "宠物 species 对齐")
	check(bool(rec.get("alive", false)), "新宠物在世")
	check_eq(host.feed_pets().size(), 1, "喂养成功")
	var reloaded = SimHostScript.new(state, 93)
	check_eq(reloaded.pets().size(), 1, "读档恢复宠物")

func _test_survival_runtime_persistence() -> void:
	var state = GameStateScript.new()
	state.new_game(95)
	var host = SimHostScript.new(state, 95)
	host.advance(120)
	check(state.sim_runtime.get("survival", {}) is Dictionary, "生存运行时写入 sim_runtime")
	var saved: Dictionary = (state.sim_runtime["survival"] as Dictionary)
	check(saved.has("now_minute") and saved.has("excess_days"), "生存运行时含时刻与过量天数")
	check_eq(int(saved.get("now_minute", -1)), host.now_minutes(), "生存时钟与主机一致")
	# 读档恢复：新主机从 sim_runtime 还原生存时钟。
	var reloaded = SimHostScript.new(state, 95)
	check_eq(reloaded.survival._now_minute, host.now_minutes(), "读档恢复生存时钟")

func _test_adoption_and_guardianship() -> void:
	var state = GameStateScript.new()
	state.new_game(97)
	var host = SimHostScript.new(state, 97)
	var r: Dictionary = host.adopt_child("养子小明", 4)
	check(bool(r.get("ok", false)), "收养子女成功")
	var child: Dictionary = r.get("child", {})
	var cid := String(child.get("id", ""))
	check((state.player.get("family", {}).get("children_ids", []) as Array).has(cid), "养子女计入法定子女")
	check((state.player.get("family", {}).get("adopted_ids", []) as Array).has(cid), "养子女计入养子女")
	check_eq(String(child.get("stage", "")), "toddler", "4 岁为幼儿阶段")
	check(bool(child.get("adopted", false)), "标记为收养")
	check_eq(host.adopted_children().size(), 1, "养子女档案可反查")
	# 指定监护人。
	var npc: Dictionary = host.acquaintances()[0]
	var gid := String(npc.get("id", ""))
	check(bool(host.assign_guardian(gid).get("ok", false)), "指定监护人成功")
	check_eq(host.guardians().size(), 1, "监护人可反查")
	# 法定监护归属：已指定者优先级最高。
	var lg: Dictionary = host.legal_guardian()
	check(bool(lg.get("ok", false)), "存在可托付的监护人")
	check_eq(String((lg.get("guardian", {}) as Dictionary).get("id", "")), gid, "优先已指定的监护人")
	check((lg.get("minors", []) as Array).has(cid), "未成年子女纳入监护范围")

func _test_child_growth_and_mortality() -> void:
	var state = GameStateScript.new()
	state.new_game(98)
	var host = SimHostScript.new(state, 98)
	var r: Dictionary = host.adopt_child("养女小华", 5)
	var child: Dictionary = r.get("child", {})
	var mpy: float = host.MINUTES_PER_YEAR
	# 回拨出生时刻到 6 岁，推进一日触发年度成长结算。
	child["birth_minutes"] = -int(6.0 * mpy)
	_advance_alive(host, 1)
	check_eq(String(child.get("stage", "")), "child", "6 岁进入儿童阶段")
	check(int(child.get("grown_age", -1)) >= 6, "成长结算推进年龄")
	check(float(child.get("care_quality", -1.0)) >= 0.0, "成长写入照护评分")
	check(not child.has("ability"), "成长不产生非 schema 的顶层 ability")
	check(child.get("attributes", {}).has("ability"), "成长回写 attributes.ability")
	# 回拨到 18 岁，推进一日触发成年独立。
	child["birth_minutes"] = -int(18.0 * mpy)
	_advance_alive(host, 1)
	check(bool(child.get("independent", false)), "成年后独立")
	check_eq(String(child.get("stage", "")), "adult", "成年阶段")
	# 早夭检查不改变在世成年子女状态。
	check(host._check_child_mortality(1440).is_empty(), "成年子女不计入早夭")

func _test_mental_runtime() -> void:
	var state = GameStateScript.new()
	state.new_game(99)
	var host = SimHostScript.new(state, 99)
	# 默认情绪平静、人格标签由阈值派生。
	check_eq(host.emotion_state(), "calm", "默认情绪平静")
	check(host.personality_tags() is Array, "人格标签为数组")
	check(host.mental.disorders_count() >= 20, "精神疾病库覆盖 20+ 病种")
	# 强制发作：写入活跃病程并同步到 player.health.mental。
	var r: Dictionary = host.mental_onset("depression")
	check(bool(r.get("ok", false)), "强制发作精神疾病")
	check(host.mental.has_active(), "存在活跃病程")
	var mental_arr: Array = state.player.get("health", {}).get("mental", [])
	check_eq(mental_arr.size(), 1, "病程回写 health.mental")
	check_eq(String((mental_arr[0] as Dictionary).get("phase", "")), "acute", "发作期映射为 acute")
	check(float((mental_arr[0] as Dictionary).get("severity", 0.0)) > 0.0, "严重度非零")
	# 治疗：扣费并给出三态结果。
	var money_before: float = float(state.player.get("finances", {}).get("cash", 0.0))
	var tr: Dictionary = host.mental_treat("psychotherapy")
	check(bool(tr.get("ok", false)), "心理咨询执行成功")
	check(["cured", "remitted", "ineffective"].has(String(tr.get("outcome", ""))), "结果三态之一")
	check(float(state.player.get("finances", {}).get("cash", 0.0)) <= money_before, "治疗扣费")
	# 放松缓解压力。
	state.player["attrs"]["psychological"]["stress"] = 80.0
	host.relax()
	check(float(state.player["attrs"]["psychological"]["stress"]) < 80.0, "放松降低压力")
	# 持久化与读档恢复。
	host.mental_onset("anxiety")
	host._persist_mental()
	check(state.sim_runtime.get("mental", {}) is Dictionary, "精神运行时写入 sim_runtime")
	var reloaded = SimHostScript.new(state, 99)
	check(reloaded.mental.has_active(), "读档恢复活跃病程")
	check_eq(reloaded.mental.all_cases().size(), host.mental.all_cases().size(), "病程数量一致")

func _test_spirit_runtime() -> void:
	var state = GameStateScript.new()
	state.new_game(77)
	var host = SimHostScript.new(state, 77)
	# 默认无信仰、无追求深度。
	check_eq(String(host.spirit_state().get("faith", "")), "", "默认无信仰")
	# 修持：投入冥想，压力下降且追求深度累计。
	state.player["attrs"]["psychological"]["stress"] = 70.0
	var r: Dictionary = host.pursue_spirit("meditation", 120)
	check(bool(r.get("ok", false)), "执行精神追求成功")
	check(float(host.spirit_state()["depth"]["meditation"]) > 0.0, "追求深度累计")
	check(float(state.player["attrs"]["psychological"]["stress"]) < 70.0, "修持降低压力")
	# 皈依与深化信仰。
	check(bool(host.convert_faith("buddhism").get("ok", false)), "皈依佛教成功")
	check_eq(String(host.spirit_state().get("faith", "")), "buddhism", "信仰写入运行时")
	check(bool(host.deepen_faith(120).get("ok", false)), "深化信仰成功")
	check(float(host.spirit_state().get("faith_depth", 0.0)) > 0.0, "信仰深度累计")
	# 精神危机与出口化解。
	host.spirit_state()["crisis"] = "meaning_loss"
	var res: Dictionary = host.resolve_spirit_crisis("philosophy")
	check(bool(res.get("ok", false)), "出口化解危机成功")
	check_eq(String(host.spirit_state().get("crisis", "")), "", "危机已清空")
	# 持久化与读档恢复。
	host.pursue_spirit("writing", 60)
	host._persist_spirituality()
	check(state.sim_runtime.get("spirituality", {}) is Dictionary, "精神追求运行时写入 sim_runtime")
	var reloaded = SimHostScript.new(state, 77)
	check_eq(String(reloaded.spirit_state().get("faith", "")), "buddhism", "读档恢复信仰")
	check(float(reloaded.spirit_state()["depth"].get("meditation", 0.0)) > 0.0, "读档恢复追求深度")

func _test_org_runtime() -> void:
	var state = GameStateScript.new()
	state.new_game(88)
	var host = SimHostScript.new(state, 88)
	host.bind(state)
	var catalog: Array = host.organizations_catalog()
	check(not catalog.is_empty(), "确定性生成可加入组织")
	if catalog.is_empty():
		return
	var oid := String((catalog[0] as Dictionary).get("id", ""))
	state.player["finances"]["cash"] = 100000000.0
	host.economy.add_money(host.account_id(), 1000000000, "test")
	# 加入并写入玩家成员资格。
	var j: Dictionary = host.join_organization(oid)
	check(bool(j.get("ok", false)), "加入组织成功")
	check(not host.organizations.membership(state.player, oid).is_empty(), "成员资格写入 player.org_memberships")
	# 完成任务并晋升。
	host.organizations.membership(state.player, oid)["tasks_completed"] = 3
	var t: Dictionary = host.do_org_task(oid)
	check(bool(t.get("ok", false)), "承接组织任务成功")
	# 退出并持久化。
	host.leave_organization(oid, false)
	host._persist_organizations()
	check(state.sim_runtime.get("organizations", null) is Array, "组织运行态写入 sim_runtime")
	var reloaded = SimHostScript.new(state, 88)
	reloaded.bind(state)
	check(not reloaded.find_org(oid).is_empty(), "读档恢复组织运行态")


func _test_language_runtime() -> void:
	var state = GameStateScript.new()
	state.new_game(88)
	var host = SimHostScript.new(state, 88)
	host.bind(state)
	var catalog: Array = host.languages_catalog()
	check(catalog.size() >= 5, "语言目录含 5 种语言")
	# 学习提升综合等级。
	var before: float = float(host.language.overall(host.language_state(), "en"))
	var s: Dictionary = host.study_language("en", "course", 100.0)
	check(bool(s.get("ok", false)), "学习英语成功")
	var after: float = float(host.language.overall(host.language_state(), "en"))
	check(after > before, "学习后综合等级提升")
	# 考试达标发证。
	host.language.set_level(host.language_state(), "en", 90.0, 90.0, 90.0)
	var e: Dictionary = host.take_language_exam("en", 60.0)
	check(bool(e.get("passed", false)), "等级达标通过语言考试")
	check(host.language.has_certificate(host.language_state(), "en", 60.0), "考试通过颁发证书")
	# 文化适应。
	var a: Dictionary = host.adapt_culture("us", 365.0)
	check(bool(a.get("ok", false)), "适应美国文化成功")
	check(float(a.get("adaptation", 0.0)) > 0.0, "适应度提升")
	# 持久化并读档恢复。
	var expect: float = float(host.language.overall(host.language_state(), "en"))
	host._persist_language()
	check(state.sim_runtime.get("language", null) is Dictionary, "语言档案写入 sim_runtime")
	check(state.sim_runtime.get("culture", null) is Dictionary, "文化状态写入 sim_runtime")
	var reloaded = SimHostScript.new(state, 88)
	reloaded.bind(state)
	check(reloaded.language.overall(reloaded.language_state(), "en") >= expect - 0.01, "读档恢复语言等级")


func _test_disability_runtime() -> void:
	var state = GameStateScript.new()
	state.new_game(88)
	var host = SimHostScript.new(state, 88)
	host.bind(state)
	host.economy.add_money(host.account_id(), 1000000000, "test")
	# 获得残障降低移动能力。
	var acq: Dictionary = host.acquire_disability("physical", "accident", "heavy")
	check(bool(acq.get("ok", false)), "获得残障成功")
	check(host.disability.mobility(host.disability_state()) < 1.0, "残障降低移动能力")
	# 装配辅具提升移动能力。
	var before: float = host.disability.mobility(host.disability_state())
	var fit: Dictionary = host.fit_disability_device("wheelchair")
	check(bool(fit.get("ok", false)), "装配轮椅成功")
	check(host.disability.mobility(host.disability_state()) > before, "辅具提升移动能力")
	# 选择养老模式并结算。
	var cm: Dictionary = host.choose_care_mode("institution_care")
	check(bool(cm.get("ok", false)), "选择机构养老")
	var settle: Dictionary = host.settle_care(12.0)
	check(bool(settle.get("ok", false)), "养老结算成功")
	# 认知障碍与监护。
	host.acquire_disability("intellectual", "illness", "heavy")
	check(not host.disability.decision_capacity(host.disability_state()), "重度智力障碍丧失决策能力")
	var guard: Dictionary = host.establish_guardianship("child_1")
	check(bool(guard.get("ok", false)), "设立监护成功")
	# 持久化并读档恢复。
	host._persist_disability()
	check(state.sim_runtime.get("disability", null) is Dictionary, "残障运行态写入 sim_runtime")
	var reloaded = SimHostScript.new(state, 88)
	reloaded.bind(state)
	check(not (reloaded.disability_state().get("conditions", []) as Array).is_empty(), "读档恢复残障状态")
	check_eq(str(reloaded.disability_state().get("guardian", "")), "child_1", "读档恢复监护人")


func _test_agriculture_runtime() -> void:
	var state = GameStateScript.new()
	state.new_game(88)
	var host = SimHostScript.new(state, 88)
	host.bind(state)
	var crops: Array = host.agri_crops_catalog()
	check(crops.size() >= 6, "作物目录含 6 种作物")
	# 承包土地。
	var land: Dictionary = host.acquire_farm_land(5.0, "grain", "contract", 100000)
	check(bool(land.get("ok", false)), "承包土地成功")
	# 播种并推进至成熟。
	var sow: Dictionary = host.plant_crop(0, "rice")
	check(bool(sow.get("ok", false)), "播种水稻成功")
	host.grow_farm(130.0)
	var stage: String = String((host.farm_state().get("plots", [])[0] as Dictionary).get("stage", ""))
	check_eq(stage, "mature", "生长 130 天水稻成熟")
	# 收割入仓。
	var hv: Dictionary = host.harvest_crop(0)
	check(bool(hv.get("ok", false)), "收割成功")
	check(float(hv.get("yield", 0.0)) > 0.0, "收割产量为正")
	# 售卖。
	var money_before: int = int(host.farm_state().get("money", 0))
	var sell: Dictionary = host.sell_produce("rice", 100.0, "market")
	check(bool(sell.get("ok", false)), "售卖水稻成功")
	check(int(host.farm_state().get("money", 0)) > money_before, "售卖后资金增加")
	# 养殖与补贴。
	var add: Dictionary = host.add_farm_livestock("pig", 10)
	check(bool(add.get("ok", false)), "增加生猪存栏")
	var sub: Dictionary = host.apply_farm_subsidy(50000)
	check(bool(sub.get("ok", false)), "申领农业补贴成功")
	# 持久化并读档恢复。
	host._persist_farm()
	check(state.sim_runtime.get("farm", null) is Dictionary, "农场运行态写入 sim_runtime")
	var reloaded = SimHostScript.new(state, 88)
	reloaded.bind(state)
	check((reloaded.farm_state().get("land", []) as Array).size() >= 1, "读档恢复土地")
	check((reloaded.farm_state().get("livestock", []) as Array).size() >= 1, "读档恢复牲畜")


func _test_digital_runtime() -> void:
	var state = GameStateScript.new()
	state.new_game(88)
	var host = SimHostScript.new(state, 88)
	host.bind(state)
	# 开账号与实名认证。
	var acct: Dictionary = host.open_digital_account("short_video")
	check(bool(acct.get("ok", false)), "开通短视频账号成功")
	var vr: Dictionary = host.verify_digital_identity()
	check(bool(vr.get("real_name_verified", false)), "实名认证成功")
	# 数字资产。
	host.add_digital_asset("wallet", 100000)
	check((host.digital_state().get("assets", []) as Array).size() >= 1, "新增数字资产")
	# 网络安全工作（合法，确定性成功）。
	var money_before: int = host.economy.cash(host.account_id())
	var job: Dictionary = host.digital_security_work("pentest")
	check(bool(job.get("ok", false)) and bool(job.get("success", false)), "网络安全工作成功")
	check(host.economy.cash(host.account_id()) > money_before, "网络安全工作带来收入")
	# 黑客（抽象判定）。
	var hack: Dictionary = host.digital_hack("personal")
	check(bool(hack.get("ok", false)), "黑客判定返回")
	# 发布内容。
	var pub: Dictionary = host.publish_digital_content("short_video")
	check(bool(pub.get("ok", false)), "发布内容成功")
	check(not host.digital_panel_data().get("creator", {}).is_empty(), "创作者数据非空")
	# 持久化并读档恢复。
	host._persist_digital()
	check(state.sim_runtime.get("digital", null) is Dictionary, "数字运行态写入 sim_runtime")
	var reloaded = SimHostScript.new(state, 88)
	reloaded.bind(state)
	check(bool(reloaded.digital_state().get("real_name_verified", false)), "读档恢复实名状态")
	check((reloaded.digital_state().get("accounts", {}) as Dictionary).has("short_video"), "读档恢复平台账号")


func _test_late_tech_runtime() -> void:
	var state = GameStateScript.new()
	state.new_game(88)
	var host = SimHostScript.new(state, 88)
	host.bind(state)
	# 目录与初始阶段。
	check(host.late_tech_stages_catalog().size() >= 3, "科技阶段目录含信息/智能/星际")
	check(not host.late_tech_careers_catalog().is_empty(), "科技职业目录非空")
	check(not host.late_tech_missions_catalog().is_empty(), "科技任务目录非空")
	check_eq(String(host.late_tech_panel_data().get("stage", "")), "information", "初始科技阶段为信息")
	# 解锁智能化阶段。
	var unlock: Dictionary = host.unlock_late_tech_stage()
	check(bool(unlock.get("ok", false)), "解锁智能阶段成功")
	check_eq(String(host.late_tech_panel_data().get("stage", "")), "intelligent", "阶段推进到智能")
	# 高技能后应聘职业（机器人运维门槛 6）。
	var entry: Dictionary = host.skills._ensure(host.player()["skills"], "skill.programming")
	entry["level"] = 10
	var career: Dictionary = host.apply_late_tech_career("robot_operator")
	check(bool(career.get("ok", false)), "应聘机器人运维成功")
	# 低技能被拒。
	var reject: Dictionary = host.apply_late_tech_career("aerospace_astronaut")
	check(not bool(reject.get("ok", false)), "技能不足时拒绝应聘")
	# 生物延寿。
	var before: float = float(host.late_tech_state().get("lifespan_bonus", 0.0))
	var bio: Dictionary = host.invest_biotech_lifespan(1000000.0)
	check(bool(bio.get("ok", false)), "生物延寿投资成功")
	check(float(host.late_tech_state().get("lifespan_bonus", 0.0)) > before, "延寿加成累积")
	# 高风险任务（技能 10 满足太空旅行门槛 8）。
	var mission: Dictionary = host.risk_late_tech_mission("space_travel")
	check(bool(mission.get("ok", false)), "执行太空旅行任务返回")
	# 持久化并读档恢复。
	host._persist_late_tech()
	check(state.sim_runtime.get("late_tech", null) is Dictionary, "后期科技运行态写入 sim_runtime")
	var reloaded = SimHostScript.new(state, 88)
	reloaded.bind(state)
	check_eq(String(reloaded.late_tech_panel_data().get("stage", "")), "intelligent", "读档恢复科技阶段")
	check(float(reloaded.late_tech_state().get("lifespan_bonus", 0.0)) > 0.0, "读档恢复延寿加成")


func _test_ip_media_runtime() -> void:
	var state = GameStateScript.new()
	state.new_game(88)
	var host = SimHostScript.new(state, 88)
	host.bind(state)
	check(host.ip_types_catalog().size() >= 4, "知识产权类型含版权/专利/商标/商业秘密")
	check(host.media_types_catalog().size() >= 5, "媒体类型含新闻社/出版社/影视/MCN/平台")
	# 登记版权并扣费。
	var money_before: int = host.economy.cash(host.account_id())
	var reg: Dictionary = host.register_ip_asset("copyright", "测试作品")
	check(bool(reg.get("ok", false)), "登记版权成功")
	check(host.economy.cash(host.account_id()) < money_before, "登记扣除登记费")
	var ips: Array = host.ip_media_state().get("ips", [])
	check_eq(ips.size(), 1, "IP 列表含 1 项")
	var ip_id: String = String((ips[0] as Dictionary).get("id", ""))
	# 授权收取许可费。
	var lic: Dictionary = host.license_ip_asset(ip_id, 1000000.0, true)
	check(bool(lic.get("ok", false)) and int(lic.get("fee", 0)) > 0, "授权收取许可费")
	# 开办媒体并发行作品。
	var outlet: Dictionary = host.register_media_outlet("publisher")
	check(bool(outlet.get("ok", false)), "开办出版社成功")
	var outlets: Array = host.ip_media_state().get("outlets", [])
	check_eq(outlets.size(), 1, "媒体机构列表含 1 项")
	var oid: String = String((outlets[0] as Dictionary).get("id", ""))
	var rel: Dictionary = host.release_media_work(oid, "试作", 0.9, 10000000.0)
	check(bool(rel.get("ok", false)) and int(rel.get("revenue", 0)) > 0, "发行作品产生营收")
	check(bool(host.audit_media_content("正常稿件", 0.1).get("approved", false)), "低风险内容审核放行")
	var rejected: Dictionary = host.audit_media_content("盗版片段", 0.2, true)
	check(not bool(rejected.get("approved", true)) and String(rejected.get("action", "")) == "takedown", "版权侵权内容下架")
	# 诉讼判定返回。
	var sue: Dictionary = host.sue_ip_infringer(ip_id, {"roll": 1.0})
	check(bool(sue.get("ok", false)), "维权诉讼返回判定")
	# 职务发明：费用与许可收益归公司账户。
	host.economy.add_money(host.account_id(), 2000000, "test_company_ip")
	check(bool(host.company_register("company", "职务发明公司", 1000000).get("ok", false)), "注册公司用于职务发明")
	var company_account: String = String(host._company.get("account", ""))
	var company_cash_before: int = int(host.economy.cash(company_account))
	var cip: Dictionary = host.company_file_ip("patent")
	check(bool(cip.get("ok", false)), "公司登记职务发明专利")
	check(String((cip.get("ip", {}) as Dictionary).get("owner", "")).begins_with("company:"), "职务发明权属归公司")
	check(int(host.economy.cash(company_account)) < company_cash_before, "职务发明登记费由公司承担")
	var company_ip_id: String = String((cip.get("ip", {}) as Dictionary).get("id", ""))
	var company_cash_after_reg: int = int(host.economy.cash(company_account))
	var player_cash_before: int = int(host.economy.cash(host.account_id()))
	var co_lic: Dictionary = host.license_ip_asset(company_ip_id, 1000000.0, true)
	check(bool(co_lic.get("ok", false)), "公司 IP 可对外授权")
	check(int(host.economy.cash(company_account)) > company_cash_after_reg, "公司 IP 许可费入公司账户")
	check(int(host.economy.cash(host.account_id())) == player_cash_before, "公司 IP 许可费不进个人账户")
	# 持久化并读档恢复。
	host._persist_ip_media()
	check(state.sim_runtime.get("ip_media", null) is Dictionary, "知识产权运行态写入 sim_runtime")
	var reloaded = SimHostScript.new(state, 88)
	reloaded.bind(state)
	check((reloaded.ip_media_state().get("ips", []) as Array).size() == 2, "读档恢复 IP")
	check((reloaded.ip_media_state().get("outlets", []) as Array).size() == 1, "读档恢复媒体机构")


func _test_manufacturing_runtime() -> void:
	var state = GameStateScript.new()
	state.new_game(99)
	var host = SimHostScript.new(state, 99)
	host.bind(state)
	check(host.mfg_roles_catalog().size() >= 7, "制造业岗位含普工/技工/工程师等")
	check(host.mfg_modes_catalog().size() >= 4, "经营模式含开厂/代工/自建品牌/技术授权")
	check(host.mfg_recipes_catalog().size() >= 3, "配方含钢制零件/塑料件/电路板")
	# 开办工厂。
	var found: Dictionary = host.found_factory("own_factory")
	check(bool(found.get("ok", false)), "开办工厂成功")
	# 招工。
	var hire: Dictionary = host.mfg_hire("unskilled", 20)
	check(bool(hire.get("ok", false)), "招入普工成功")
	check_eq(host.manufacturing.headcount(host.manufacturing_state()), 20, "在册 20 人")
	# 采购与生产。
	host.mfg_add_supplier("steel")
	var buy: Dictionary = host.mfg_purchase("steel", 200.0)
	check(bool(buy.get("ok", false)) and float(buy.get("delivered", 0.0)) > 0.0, "采购钢材到货")
	var prod: Dictionary = host.mfg_produce("steel_part", 100.0)
	check(bool(prod.get("ok", false)) and float(prod.get("good_output", 0.0)) > 0.0, "生产出良品")
	# 接单与交付。
	var order: Dictionary = host.mfg_accept_order("steel_part", 50.0)
	check(bool(order.get("ok", false)), "承接订单成功")
	var deliver: Dictionary = host.mfg_deliver_order(0)
	check(bool(deliver.get("ok", false)) and int(deliver.get("revenue", 0)) > 0, "交付订单结算收入")
	# 缺料时生产被原料约束。
	var prod2: Dictionary = host.mfg_produce("circuit_board", 10.0)
	check(bool(prod2.get("ok", false)) and String(prod2.get("bottleneck", "")) == "material", "缺料时以原料为瓶颈")
	# 持久化与读档恢复。
	host._persist_manufacturing()
	check(state.sim_runtime.get("manufacturing", null) is Dictionary, "制造业运行态写入 sim_runtime")
	var reloaded = SimHostScript.new(state, 99)
	reloaded.bind(state)
	check_eq(int(reloaded.manufacturing.headcount(reloaded.manufacturing_state())), 20, "读档恢复工厂人员")
	check(not reloaded.factory_panel_data().is_empty(), "面板数据非空")


func _test_trade_runtime() -> void:
	var state = GameStateScript.new()
	state.new_game(77)
	var host = SimHostScript.new(state, 77)
	host.bind(state)
	check(host.trade_transport_modes_catalog().size() >= 5, "运输方式含海运/空运/铁路/快递/管道")
	check(host.trade_incoterms_catalog().size() >= 6, "贸易术语含 EXW/FOB/CFR/CIF/DAP/DDP")
	check(host.trade_settlements_catalog().size() >= 4, "结算方式含信用证/汇付/保理/赊销")
	# 建出口单据
	var ex: Dictionary = host.export_shipment("钢材", 50000)
	check(bool(ex.get("ok", false)), "建立出口单据成功")
	check_eq((host.trade_state().get("shipments", []) as Array).size(), 1, "外贸单据列表含 1 项")
	# 规划运输
	var plan: Dictionary = host.plan_trade_transport(-1, "sea")
	check(bool(plan.get("ok", false)) and int(plan.get("freight", 0)) > 0, "规划海运并报价")
	# 签约
	var sign: Dictionary = host.sign_trade_contract(-1, "FOB", "letter_of_credit")
	check(bool(sign.get("ok", false)), "签订外贸合同成功")
	# 报关扣税
	var cash_before: int = host.economy.cash(host.account_id())
	var dec: Dictionary = host.declare_shipment(-1)
	check(bool(dec.get("ok", false)) and int(dec.get("total_tax", 0)) > 0, "报关计算关税与增值税")
	check(host.economy.cash(host.account_id()) < cash_before, "报关扣除税费")
	# 清关
	check(bool(host.clear_shipment(-1).get("ok", false)), "清关成功")
	# 交付结算收入
	var del: Dictionary = host.deliver_shipment(-1)
	check(bool(del.get("ok", false)) and int(del.get("revenue", 0)) > 0, "交付结算出口收入")
	# 结汇手续费
	var setl: Dictionary = host.settle_shipment(-1)
	check(bool(setl.get("ok", false)) and int(setl.get("fee", 0)) > 0, "结汇收取手续费")
	# 持久化与读档恢复
	host._persist_trade()
	check(state.sim_runtime.get("trade", null) is Dictionary, "国际贸易运行态写入 sim_runtime")
	var reloaded = SimHostScript.new(state, 77)
	reloaded.bind(state)
	check_eq((reloaded.trade_state().get("shipments", []) as Array).size(), 1, "读档恢复外贸单据")


func _test_mining_runtime() -> void:
	var state = GameStateScript.new()
	state.new_game(55)
	var host = SimHostScript.new(state, 55)
	host.bind(state)
	check(host.mining_minerals_catalog().size() >= 4, "矿种含铁矿/铜矿/煤矿/金矿")
	check(host.mining_energy_catalog().size() >= 5, "能源品种含石油/天然气/煤炭/电力/新能源")
	check(host.mining_energy_kinds_catalog().size() >= 4, "新能源含风电/光伏/核电/储能")
	# 开办矿场。
	var mine: Dictionary = host.open_mine("iron")
	check(bool(mine.get("ok", false)), "开办铁矿场成功")
	# 未取得矿权不可开采。
	check(not bool(host.extract_ore(100.0).get("ok", false)), "未取得矿权不可开采")
	# 取得矿权与勘探。
	check(bool(host.acquire_mine_concession().get("ok", false)), "取得矿权成功")
	var ex: Dictionary = host.explore_mine(1000000)
	check(bool(ex.get("ok", false)) and float(ex.get("reserve", 0.0)) > 0.0, "勘探揭示储量")
	# 开采→冶炼→出售链条。
	var ore: Dictionary = host.extract_ore(1000.0)
	check(bool(ore.get("ok", false)) and float(ore.get("ore", 0.0)) > 0.0, "开采产出矿石")
	var smelt: Dictionary = host.smelt_ore(1000.0)
	check(bool(smelt.get("ok", false)) and float(smelt.get("metal", 0.0)) > 0.0, "冶炼产出金属")
	var sell: Dictionary = host.sell_metal(1000.0)
	check(bool(sell.get("ok", false)) and int(sell.get("revenue", 0)) > 0, "出售金属获得收入")
	# 新能源项目。
	var proj: Dictionary = host.build_energy_project("solar", 100.0)
	check(bool(proj.get("ok", false)), "建设光伏项目成功")
	var decline: Dictionary = host.mining_city_decline()
	check(bool(decline.get("ok", false)) and float((decline.get("macro", {}) as Dictionary).get("unemployment", 0.0)) > 0.0, "资源城市衰退传导宏观")
	check(bool(host.mining_strategic_control("coal", 0.6).get("ok", false)), "战略资源管制")
	check(float(host.mining_stockpile("coal", 500.0).get("stockpile", 0.0)) > 0.0, "战略资源囤积")
	# 矿难刑事追责：低安全 + 大量工人时强制触发一次事故。
	host._mine["safety"] = 0.0
	host._mine["workers"] = 300
	var accident: Dictionary = {}
	for _i in range(200):
		accident = host.check_mine_accident()
		if bool(accident.get("occurred", false)) and int(accident.get("injured", 0)) >= 3:
			break
	check(bool(accident.get("occurred", false)), "低安全矿场发生矿难")
	check(bool(accident.get("criminal_record", false)), "重大矿难追究刑事责任")
	check(host.crime_sys.has_record(host._crime_state), "矿难写入案底")
	check(int(host.crime_sys.wanted_level(host._crime_state, host.current_region_id())) >= 2, "矿难产生通缉")
	# 能源价格按年演化。
	host.advance(525960)
	var energy: Dictionary = host.mining_state().get("energy", {})
	check(float(energy.get("clock", 0.0)) > 0.0, "推进一年后能源时钟前进")
	# 持久化与读档恢复。
	host._persist_mining()
	check(state.sim_runtime.get("mining", null) is Dictionary, "矿业运行态写入 sim_runtime")
	var reloaded = SimHostScript.new(state, 55)
	reloaded.bind(state)
	check(not (reloaded.mining_state().get("mine", {}) as Dictionary).is_empty(), "读档恢复矿场")
	check(not reloaded.mining_panel_data().is_empty(), "矿业面板数据非空")


func _test_primary_runtime() -> void:
	var state = GameStateScript.new()
	state.new_game(31)
	var host = SimHostScript.new(state, 31)
	host.bind(state)
	check(host.fish_species_catalog().size() >= 3, "鱼种含鳕鱼/金枪鱼/虾")
	check(host.game_species_catalog().size() >= 3, "猎物含鹿/野猪/野兔")
	check(host.forest_types_catalog().size() >= 3, "林分含用材林/防护林/经济林")
	# 渔场。
	check(bool(host.new_fishery().get("ok", false)), "开办渔场成功")
	var catch1: Dictionary = host.fish_catch("cod", 100.0)
	check(bool(catch1.get("ok", false)) and float(catch1.get("caught", 0.0)) > 0.0, "捕捞产出渔获")
	check(bool(host.start_closed_season().get("ok", false)), "进入休渔期")
	check(not bool(host.fish_catch("cod", 10.0).get("ok", false)), "休渔期禁止捕捞")
	# 林场。
	check(bool(host.new_forest("timber").get("ok", false)), "承包林场成功")
	var log_r: Dictionary = host.log_trees(100.0)
	check(bool(log_r.get("ok", false)) and float(log_r.get("timber", 0.0)) > 0.0, "采伐产出木材")
	check(bool(host.reforest(50.0).get("ok", false)), "造林成功")
	var cash_carbon: int = int(host.economy.cash(host.account_id()))
	var sink: Dictionary = host.forest_carbon_sink(1.0)
	check(bool(sink.get("ok", false)) and float(sink.get("credits", 0.0)) > 0.0, "林业碳汇核证")
	check(int(host.economy.cash(host.account_id())) > cash_carbon, "碳汇收入入账")
	# 狩猎。
	check(bool(host.apply_hunting_license().get("ok", false)), "申请狩猎许可成功")
	var hunt_r: Dictionary = host.hunt("deer", 1.0)
	check(bool(hunt_r.get("ok", false)) and bool(hunt_r.get("legal", false)), "持证合法狩猎")
	# 持久化与读档恢复。
	host._persist_primary()
	check(state.sim_runtime.get("primary", null) is Dictionary, "农林牧渔运行态写入 sim_runtime")
	var reloaded = SimHostScript.new(state, 31)
	reloaded.bind(state)
	check(not (reloaded.primary_state().get("fishery", {}) as Dictionary).is_empty(), "读档恢复渔场")
	check(not reloaded.primary_panel_data().is_empty(), "农林牧渔面板数据非空")


func _test_dining_runtime() -> void:
	var state = GameStateScript.new()
	state.new_game(41)
	var host = SimHostScript.new(state, 41)
	host.bind(state)
	check(host.dining_recipes_catalog().size() >= 4, "菜谱表含家常小炒等")
	check(host.dining_channels_catalog().size() >= 4, "渠道表含堂食/外卖")
	check(bool(host.open_restaurant().get("ok", false)), "开办餐厅成功")
	check(bool(host.restaurant_add_menu("home_style").get("ok", false)), "加菜成功")
	check(bool(host.restaurant_set_price("home_style", 4000).get("ok", false)), "定菜价成功")
	var sell: Dictionary = host.restaurant_sell_day("dine_in")
	check(bool(sell.get("ok", false)) and int(sell.get("revenue", 0)) > 0, "营业取得营收")
	check(bool(host.restaurant_hire("chef", 1).get("ok", false)), "聘用主厨成功")
	var cert: Dictionary = host.restaurant_certify("hygiene_a")
	check(bool(cert.get("ok", false)), "取得卫生 A 级认证")
	var rep_before_incident: float = float(host.dining_state().get("reputation", 0.0))
	var food_incident: Dictionary = host.consumer_incident("food_safety", 0.8, 50)
	check(bool(food_incident.get("ok", false)) and food_incident.has("restaurant_incident"), "食安事故联动餐厅处罚")
	check(float(host.dining_state().get("reputation", 0.0)) < rep_before_incident, "餐厅声誉因食安事故下降")
	check(bool(host.restaurant_expand("single_shop").get("ok", false)), "扩张校验通过（单店）")
	# 中央厨房 ↔ D26 食品产线：工厂产出直接补餐厅预包装库存。
	host._factory = host.manufacturing.new_factory(10000000, {"mode": "obm"})
	host._factory["staff"]["unskilled"] = 20
	for mat in ["rice", "meat", "vegetable"]:
		host.manufacturing.add_material(host._factory, mat, 50.0)
	var line_run: Dictionary = host.manufacturing.produce(host._factory, "home_style", 5.0)
	check(bool(line_run.get("ok", false)), "食品产线生产速食家常菜")
	host._restaurant["mode"] = "central_kitchen"
	host._restaurant["central_kitchen"] = true
	var supply: Dictionary = host.restaurant_industrial_supply("home_style", 2.0)
	check(bool(supply.get("ok", false)) and float(supply.get("moved", 0.0)) == 2.0, "产线成品转入中央厨房")
	check(float((host._factory["products"] as Dictionary).get("home_style", 0.0)) < float(line_run.get("good_output", 0.0)), "工厂库存同步扣减")
	# 持久化与读档恢复。
	host._persist_dining()
	check(state.sim_runtime.get("dining", null) is Dictionary, "餐饮运行态写入 sim_runtime")
	var reloaded = SimHostScript.new(state, 41)
	reloaded.bind(state)
	check(not reloaded.dining_state().is_empty(), "读档恢复餐厅")
	check(not reloaded.dining_panel_data().is_empty(), "餐饮面板数据非空")


func _test_fashion_runtime() -> void:
	var state = GameStateScript.new()
	state.new_game(51)
	var host = SimHostScript.new(state, 51)
	host.bind(state)
	check(host.fashion_disciplines_catalog().size() >= 5, "学科表含服装/珠宝等")
	check(host.fashion_luxury_catalog().size() >= 5, "奢侈品类目含手袋/腕表等")
	check(bool(host.new_brand("luxury").get("ok", false)), "创立奢侈品牌成功")
	var design: Dictionary = host.fashion_design("apparel")
	check(bool(design.get("ok", false)) and float(design.get("score", 0.0)) >= 0.0, "创作设计成功")
	var fw: Dictionary = host.fashion_week("aw")
	check(bool(fw.get("ok", false)) and int(fw.get("orders", 0)) >= 0, "时装周结算成功")
	var lim: Dictionary = host.fashion_limited_edition("handbag", 10)
	check(bool(lim.get("ok", false)) and int(lim.get("price", 0)) > 0, "限量发售成功")
	var money_before: int = int((host.fashion_state().get("brand", {}) as Dictionary).get("money", 0))
	var resale: Dictionary = host.fashion_resell("handbag", 0.8)
	check(bool(resale.get("ok", false)) and int(resale.get("price", 0)) > 0, "二手寄售成交")
	check(int((host.fashion_state().get("brand", {}) as Dictionary).get("money", 0)) > money_before, "寄售货款入账")
	var auc: Dictionary = host.fashion_auction("handbag", 1)
	check(bool(auc.get("sold", false)), "奢侈品拍卖成交")
	var collab: Dictionary = host.fashion_collab(80.0)
	check(bool(collab.get("ok", false)) and int(collab.get("revenue", 0)) > 0, "联名取得收入")
	var auth: Dictionary = host.fashion_authenticate("handbag")
	check(bool(auth.get("ok", false)), "鉴定真伪成功")
	(host.player()["family"] as Dictionary)["children_ids"] = ["child-1"]
	var inherit: Dictionary = host.fashion_inherit("")
	check(bool(inherit.get("ok", false)) and int(inherit.get("generation", 0)) == 2, "品牌跨代传承")
	var rep_before_fake: float = float((host.fashion_state().get("brand", {}) as Dictionary).get("reputation", 0.0))
	check(bool(host.register_ip_asset("trademark", "品牌商标").get("ok", false)), "注册商标用于仿品维权")
	var fake: Dictionary = host.fashion_counterfeit(500000)
	check(bool(fake.get("ok", false)) and fake.has("lawsuit"), "仿品侵权联动 IP 诉讼")
	check(float((host.fashion_state().get("brand", {}) as Dictionary).get("reputation", 0.0)) < rep_before_fake, "仿品拉低品牌声誉")
	# 持久化与读档恢复。
	host._persist_fashion()
	check(state.sim_runtime.get("fashion", null) is Dictionary, "时尚运行态写入 sim_runtime")
	var reloaded = SimHostScript.new(state, 51)
	reloaded.bind(state)
	check(not (reloaded.fashion_state().get("brand", {}) as Dictionary).is_empty(), "读档恢复品牌")
	check(not reloaded.fashion_panel_data().is_empty(), "时尚面板数据非空")

func _test_sports_runtime() -> void:
	var state = GameStateScript.new()
	state.new_game(61)
	var host = SimHostScript.new(state, 61)
	host.bind(state)
	check(host.sports_injuries_catalog().size() >= 4, "伤病表含轻伤/重伤等")
	check(host.sports_scandals_catalog().size() >= 4, "丑闻表含兴奋剂/假球等")
	check(bool(host.start_sports_career().get("ok", false)), "开启运动生涯成功")
	check(not host.sports_state().get("player", {}).is_empty(), "球员生涯非空")
	var m: Dictionary = host.sports_play_match()
	check(bool(m.get("ok", false)) and int(m.get("home_score", -1)) >= 0, "出战一场联赛成功")
	check(int(host.sports_state()["player"].get("appearances", 0)) == 1, "出场数计入")
	var tr: Dictionary = host.sports_transfer(5000000)
	check(bool(tr.get("ok", false)) and int(tr.get("fee", 0)) == 5000000, "转会结算成功")
	var sp: Dictionary = host.sports_sponsorship("测试品牌", 800000)
	check(bool(sp.get("ok", false)), "签订代言合同成功")
	check(bool(host.sports_national_callup("中国").get("ok", false)), "入选国家队成功")
	var form_before_camp: float = float(host.sports_state()["player"].get("form", 0.0))
	var camp: Dictionary = host.sports_national_camp(10.0)
	check(bool(camp.get("ok", false)) and float(camp.get("gain", 0.0)) > 0.0, "国家队集训提升状态")
	check(float(host.sports_state()["player"].get("form", 0.0)) > form_before_camp, "集训后状态上升")
	var inj: Dictionary = host.sports_injure("minor")
	check(bool(inj.get("ok", false)) and float(host.sports_state()["player"].get("injury_days", 0.0)) > 0.0, "伤病施加成功")
	var no_play: Dictionary = host.sports_play_match()
	check(not bool(no_play.get("ok", false)), "伤病期间无法出战")
	var rh: Dictionary = host.sports_rehab(100.0)
	check(bool(rh.get("ok", false)) and bool(rh.get("recovered", false)), "康复后痊愈")
	var rt: Dictionary = host.sports_retire()
	check(bool(rt.get("ok", false)) and String(host.sports_state()["player"].get("career_stage", "")) == "retire", "退役成功")
	# 持久化与读档恢复。
	host._persist_sports()
	check(state.sim_runtime.get("sports", null) is Dictionary, "体育运行态写入 sim_runtime")
	var reloaded = SimHostScript.new(state, 61)
	reloaded.bind(state)
	check(not (reloaded.sports_state().get("player", {}) as Dictionary).is_empty(), "读档恢复生涯")
	check(not reloaded.sports_panel_data().is_empty(), "体育面板数据非空")

func _test_events_runtime() -> void:
	var state = GameStateScript.new()
	state.new_game(71)
	var host = SimHostScript.new(state, 71)
	host.bind(state)
	check(host.events_types_catalog().size() >= 7, "活动类型表含演唱会/漫展等")
	check(bool(host.start_event_career("planner").get("ok", false)), "开启活动策划职业成功")
	check(bool(host.events_new("concert").get("ok", false)), "筹办演唱会成功")
	check(bool(host.events_rent_venue(2000000).get("ok", false)), "租赁场地成功")
	check(bool(host.events_approval().get("ok", false)), "报批通过")
	check(bool(host.events_sign_artist("林夏", 70.0).get("ok", false)), "签约艺人")
	check(bool(host.events_book_artist("林夏").get("ok", false)), "艺人排期")
	check(String((host.events_state().get("event", {}) as Dictionary).get("artist_name", "")) == "林夏", "艺人写入当前活动")
	check(bool(host.events_sponsor("title").get("ok", false)), "招商成功")
	check(int(host.events_sell_tickets(5000).get("revenue", 0)) > 0, "售票取得收入")
	var resale: Dictionary = host.events_secondary_market(1000)
	check(bool(resale.get("ok", false)) and int(resale.get("commission", 0)) > 0, "二级市场平台抽佣")
	check(int((host.events_state().get("event", {}) as Dictionary).get("resales", 0)) == 1000, "转售数量登记")
	check(bool(host.events_set_security(0.8).get("ok", false)), "配置安保成功")
	var cash_before_event: int = int(host.economy.cash(host.account_id()))
	var hold: Dictionary = host.events_hold()
	check(bool(hold.get("ok", false)) and int(hold.get("attendance", 0)) == 5000, "举办活动到场 5000")
	check(float(hold.get("nuisance", 0.0)) > 0.0, "大型活动计入市政扰动")
	var rv: Dictionary = host.events_review()
	check(bool(rv.get("ok", false)), "活动复盘成功")
	check(int(host.economy.cash(host.account_id())) != cash_before_event, "活动净利回写现金")
	check(bool((rv.get("planner", {}) as Dictionary).get("ok", false)), "策划职业累计经验")
	# 持久化与读档恢复。
	host._persist_events()
	check(state.sim_runtime.get("events", null) is Dictionary, "会展运行态写入 sim_runtime")
	var reloaded = SimHostScript.new(state, 71)
	reloaded.bind(state)
	check(not (reloaded.events_state().get("event", {}) as Dictionary).is_empty(), "读档恢复活动")
	check(not reloaded.events_panel_data().is_empty(), "会展面板数据非空")

func _test_honors_runtime() -> void:
	var state = GameStateScript.new()
	state.new_game(81)
	var host = SimHostScript.new(state, 81)
	host.bind(state)
	check(host.honors_categories_catalog().size() >= 6, "荣誉类别表含学术/艺术等")
	check(host.honors_awards_catalog().size() >= 6, "奖项表含学术成就奖等")
	check(bool(host.start_honor_profile(90.0).get("ok", false)), "建立荣誉档案成功")
	check(bool(host.honors_nominate("academic_prize").get("eligible", false)), "提名达标")
	check(bool(host.honors_evaluate("academic_prize").get("passed", false)), "评审通过")
	var aw: Dictionary = host.honors_award("academic_prize")
	check(bool(aw.get("awarded", false)), "领奖成功")
	check((host.honors_state()["candidate"].get("honors", []) as Array).size() == 1, "荣誉登记")
	check(aw.get("enshrined", null) is Dictionary, "入选名人堂")
	check(bool(host.honors_buy("arts_prize").get("awarded", false)), "买奖运作成功")
	var exp: Dictionary = host.honors_expose()
	check(bool(exp.get("exposed", false)), "黑幕可揭露")
	check((host.honors_state()["candidate"].get("honors", []) as Array).is_empty(), "揭露后荣誉撤销")
	var score_before: float = float(host.honors_evaluate("academic_prize").get("score", 0.0))
	check(bool(host.honors_pressure(0.5).get("ok", false)), "奖项舆论施压")
	check(float(host.honors_evaluate("academic_prize").get("score", 0.0)) < score_before, "政治化压力压低评审得分")
	var vote: Dictionary = host.honors_panel_vote("academic_prize")
	check(bool(vote.get("ok", false)) and (vote.get("ranked", []) as Array).size() == 4, "评委会多主体投票")
	check(not String(vote.get("winner", "")).is_empty(), "投票产生胜出者")
	check(not (host.honors_panel_data().get("last_vote", {}) as Dictionary).is_empty(), "投票进入荣誉面板")
	check(bool(host.honors_inherit().get("ok", false)), "传承评价可计算")
	state.legacy["generation"] = 2
	state.legacy["lineage"] = [{"name": "长子", "summary": "出生于本地"}]
	state.legacy["history"] = [{"kind": "birth", "name": "长子", "birth_minutes": 10}]
	var fam: Dictionary = host.honors_family_legacy()
	check(bool(fam.get("ok", false)) and int(fam.get("generations", 0)) >= 2, "家族荣誉跨代聚合")
	check((fam.get("stories", []) as Array).size() > 0, "家族传承叙事非空")
	# 持久化与读档恢复。
	host._persist_honors()
	check(state.sim_runtime.get("honors", null) is Dictionary, "荣誉运行态写入 sim_runtime")
	var reloaded = SimHostScript.new(state, 81)
	reloaded.bind(state)
	check(not (reloaded.honors_state().get("candidate", {}) as Dictionary).is_empty(), "读档恢复荣誉档案")
	check(not reloaded.honors_panel_data().is_empty(), "荣誉面板数据非空")

func _test_police_runtime() -> void:
	var state = GameStateScript.new()
	state.new_game(91)
	var host = SimHostScript.new(state, 91)
	host.bind(state)
	check(host.police_crimes_catalog().size() >= 8, "罪名表含盗窃/诈骗等")
	check(host.police_evidence_catalog().size() >= 6, "证据种类表非空")
	check(host.police_services_catalog().size() >= 4, "安保业务表非空")
	check(bool(host.police_start_case("theft", "detective").get("ok", false)), "立案成功")
	check(bool(host.police_survey().get("ok", false)), "勘查取证线索")
	# 无搜查令采集监控证据应判非法。
	check(bool(host.police_collect("surveillance", 0.5).get("illegal", false)), "无搜查令取证非法")
	check(bool(host.police_tech().get("reason", "") == "no_warrant"), "无搜查令技侦被拒")
	check(bool(host.police_warrant().get("granted", false)), "搜查令获批")
	check(bool(host.police_collect("surveillance", 0.5).get("ok", false)), "持令取监控证据成功")
	check(bool(host.police_tech().get("ok", false)), "持令技侦成功")
	check(bool(host.police_interrogate(0.4).get("ok", false)), "审讯完成")
	check(bool(host.police_informant().get("ok", false)), "启用线人完成")
	check(bool(host.police_undercover().get("ok", false)), "部署卧底完成")
	check(bool(host.police_advance().get("ok", false)), "案件推进至追查")
	var sol: Dictionary = host.police_advance()
	check(bool(sol.get("ok", false)) and sol.has("solved"), "追查阶段侦破判定")
	# 民营安保。
	check(bool(host.start_security_firm("测试安保").get("ok", false)), "开办安保公司成功")
	check(bool(host.start_security_firm("再次").get("reason", "") == "already_firm"), "重复开办被拒")
	check(bool(host.security_take_contract("escort").get("ok", false)), "承接押运业务成功")
	check(bool(host.security_resolve_contract().get("ok", false)), "履约结算完成")
	# 持久化与读档恢复。
	host._persist_police()
	check(state.sim_runtime.get("police", null) is Dictionary, "警务运行态写入 sim_runtime")
	var reloaded = SimHostScript.new(state, 91)
	reloaded.bind(state)
	check(not (reloaded.police_state().get("case", {}) as Dictionary).is_empty(), "读档恢复案件")
	check(not (reloaded.police_state().get("firm", {}) as Dictionary).is_empty(), "读档恢复安保公司")
	check(not reloaded.police_panel_data().is_empty(), "警务面板数据非空")

func _test_emergency_runtime() -> void:
	var state = GameStateScript.new()
	state.new_game(101)
	var host = SimHostScript.new(state, 101)
	host.bind(state)
	check(host.emergency_professions_catalog().size() >= 6, "应急职业表含消防/急救等")
	check(bool(host.emergency_new_incident("fire", 0.6).get("ok", false)), "接警建立事件")
	check(float(host.emergency_dispatch(5.0).get("response_minutes", 0.0)) > 0.0, "出警计算响应时间")
	host.economy.add_money(host.account_id(), 1000000, "test")
	var cash_before_aid: int = int(host.economy.cash(host.account_id()))
	var aid: Dictionary = host.emergency_mutual_aid(30.0, 2)
	check(bool(aid.get("ok", false)) and int(aid.get("rescue_teams", 0)) > 1, "跨区增援补充救援队")
	check(int(host.economy.cash(host.account_id())) < cash_before_aid, "增援费用从玩家账户扣除")
	var rs: Dictionary = host.emergency_rescue()
	check(bool(rs.get("ok", false)) and int(rs.get("injured", 0)) >= 0, "现场救援结算")
	check(bool(host.emergency_secondary().get("ok", false)), "二次事故评估")
	check(bool(host.emergency_aftermath().get("ok", false)), "善后处理完成")
	# 志愿救援组织。
	check(bool(host.start_volunteer_org("测试志愿队").get("ok", false)), "组建志愿队成功")
	check(bool(host.start_volunteer_org("再次").get("reason", "") == "already_org"), "重复组建被拒")
	check(bool(host.volunteer_recruit(10).get("ok", false)), "招募志愿者成功")
	check(bool(host.volunteer_purchase("救援装备", 100).get("ok", false)), "采购装备成功")
	check(bool(host.volunteer_dispatch_incident().get("ok", false)), "志愿出警成功")
	check(float(host._volunteer_org.get("wear", 0.0)) > 0.0, "出警造成装备损耗")
	var wear_before: float = float(host._volunteer_org.get("wear", 0.0))
	check(bool(host.volunteer_maintain(50000).get("ok", false)), "装备维护成功")
	check(float(host._volunteer_org.get("wear", 1.0)) < wear_before, "维护降低装备损耗")
	# 天气灾害：找到当前区域未来确有灾害的一日，触发 D19→D36/D18/D1 联动。
	check(bool(host.found_factory("own_factory").get("ok", false)), "灾害前已办厂")
	var rid: String = host.current_region_id()
	if not host.weather.has_region(rid):
		host.weather.register_region(rid, host._zone_for_region(rid))
	var disaster_day: int = -1
	for d in range(1, 100000):
		if not host.weather.disasters_on(rid, d).is_empty():
			disaster_day = d
			break
	check(disaster_day > 0, "未来存在天气灾害日")
	if disaster_day > 0:
		state.clock["absolute_minutes"] = disaster_day * 1440 + 720
		var road_before: float = host.municipal.facility_condition(host._city_municipal, "road")
		var health_before: float = float(host.player().get("attrs", {}).get("physiological", {}).get("health", 100.0))
		var wd: Dictionary = host.emergency_weather_disaster()
		check(bool(wd.get("ok", false)), "天气灾害接警成功")
		check(String(host._incident.get("disaster", "")) != "", "事件记录灾种")
		check(host.municipal.facility_condition(host._city_municipal, "road") < road_before, "灾害损毁市政设施")
		check(float(host.player().get("attrs", {}).get("physiological", {}).get("health", 100.0)) < health_before, "灾害造成人身伤害")
		if bool(wd.get("power_outage", false)):
			check(host.manufacturing.has_disruption(host._factory, "power_outage"), "灾害导致工厂停电停产")
			_advance_alive(host, 3)
			check(not host.manufacturing.has_disruption(host._factory, "power_outage"), "停电在 2 天后恢复")
	# 持久化与读档恢复。
	host._persist_emergency()
	check(state.sim_runtime.get("emergency", null) is Dictionary, "应急运行态写入 sim_runtime")
	var reloaded = SimHostScript.new(state, 101)
	reloaded.bind(state)
	check(not (reloaded.emergency_state().get("incident", {}) as Dictionary).is_empty(), "读档恢复事件")
	check(not (reloaded.emergency_state().get("org", {}) as Dictionary).is_empty(), "读档恢复志愿队")
	check(not reloaded.emergency_panel_data().is_empty(), "应急面板数据非空")

func _test_environment_runtime() -> void:
	var state = GameStateScript.new()
	state.new_game(111)
	var host = SimHostScript.new(state, 111)
	host.bind(state)
	host.economy.add_money(host.account_id(), 5000000, "test")
	check(host.environment_careers_catalog().size() >= 4, "环保职业表含环保企业/NGO等")
	check(bool(host.env_set_garbage_sorting(0.8).get("ok", false)), "设定垃圾分类率")
	check(float(host.env_recycle(1000.0).get("recovered", 0.0)) > 0.0, "回收资源有产出")
	check(bool(host.env_treat_sewage(0.9).get("ok", false)), "设定污水处理率")
	check(bool(host.env_air_control(1000000).get("ok", false)), "空气治理完成")
	check(bool(host.env_issue_permit("factory", 200.0).get("ok", false)), "发放排污许可")
	var acct: Dictionary = host.env_carbon_account()
	check(bool(acct.get("ok", false)), "碳核算完成")
	var cash_before: int = int(host.economy.cash(host.account_id()))
	check(bool(host.env_carbon_trade(-50.0).get("ok", false)), "碳交易完成")
	check_eq(int(host.economy.cash(host.account_id())), cash_before + 5000, "碳信用卖出资金入账")
	var comp: Dictionary = host.env_carbon_compliance("buy")
	check(bool(comp.get("ok", false)) and bool(comp.get("compliant", false)), "碳履约合规")
	check_eq(int(host.economy.cash(host.account_id())), cash_before, "碳履约购配额扣款")
	check(bool(host.env_report_carbon(100.0).get("ok", false)), "碳申报完成")
	var auction: Dictionary = host.env_carbon_auction(100.0, 160)
	check(bool(auction.get("ok", false)) and float(auction.get("filled", 0.0)) > 0.0, "碳配额拍卖成交")
	check(int(auction.get("clearing_price", 0)) >= 80, "拍卖出清价在区间内")
	host.env_carbon_trade(200.0)
	var market: Dictionary = host.env_carbon_market()
	check(bool(market.get("ok", false)) and (market.get("trades", []) as Array).size() > 0, "跨企业碳市场撮合")
	# 环保从业组织。
	check(bool(host.start_env_org("env_company").get("ok", false)), "开办环保企业成功")
	check(bool(host.start_env_org("env_ngo").get("reason", "") == "already_org"), "重复开办被拒")
	check(bool(host.env_run_project("污水厂", 1000000).get("ok", false)), "承接环保项目成功")
	check(bool(host.env_green_subsidy(100000).get("ok", false)), "申请绿色补贴完成")
	var cash_green: int = int(host.economy.cash(host.account_id()))
	check(bool(host.env_low_carbon_transition(1000000).get("ok", false)), "低碳转型完成")
	check_eq(int(host.economy.cash(host.account_id())), cash_green - 1000000, "低碳转型投入扣款")
	check(bool(host.env_illegal_discharge(20.0).get("ok", false)), "偷排结算完成")
	check(bool(host.env_nimby(0.5).get("ok", false)), "邻避评估完成")
	# 污染与诉讼。
	check(bool(host.env_pollute(0.8).get("ok", false)), "污染事件结算")
	check(bool(host.env_expose_pollution().get("ok", false)), "污染曝光结算")
	var cash_suit: int = int(host.economy.cash(host.account_id()))
	var suit: Dictionary = host.env_lawsuit()
	check(bool(suit.get("ok", false)), "环境诉讼完成")
	if bool(suit.get("liable", false)):
		check_eq(int(host.economy.cash(host.account_id())), cash_suit - int(suit.get("compensation", 0)), "环境赔偿扣款")
	# 持久化与读档恢复。
	host._persist_environment()
	check(state.sim_runtime.get("environment", null) is Dictionary, "环保运行态写入 sim_runtime")
	var reloaded = SimHostScript.new(state, 111)
	reloaded.bind(state)
	check(not (reloaded.environment_state().get("city", {}) as Dictionary).is_empty(), "读档恢复城市环保")
	check(not (reloaded.environment_state().get("enterprise", {}) as Dictionary).is_empty(), "读档恢复企业碳账户")
	check(not (reloaded.environment_state().get("org", {}) as Dictionary).is_empty(), "读档恢复环保组织")
	check(not reloaded.environment_panel_data().is_empty(), "环保面板数据非空")


func _test_municipal_runtime() -> void:
	var state = GameStateScript.new()
	state.new_game(121)
	var host = SimHostScript.new(state, 121)
	host.bind(state)
	check(host.municipal_facilities_catalog().size() >= 7, "市政设施表含道路/桥梁/公园等")
	check(host.municipal_franchise_catalog().size() >= 5, "特许服务表含供水/公交等")
	# 养护与巡检。
	var m: Dictionary = host.municipal_maintain("park", 3000000)
	check(bool(m.get("ok", false)), "养护公园完成")
	check(bool(host.municipal_inspect().get("ok", false)), "设施巡检完成")
	# 施工与推进。
	check(bool(host.municipal_construct("road", 30.0).get("ok", false)), "市政施工开始")
	check(bool(host.municipal_construct("road", 30.0).get("reason", "") == "already_under_construction"), "重复施工被拒")
	var adv: Dictionary = host.municipal_advance_construction(40.0)
	check(bool(adv.get("ok", false)) and (adv.get("completed", []) as Array).size() == 1, "施工完工结算")
	# 开挖与投诉。
	check(bool(host.municipal_excavate("bridge").get("ok", false)), "道路开挖登记")
	var c: Dictionary = host.municipal_complain("扰民")
	check(bool(c.get("ok", false)), "市政投诉登记")
	check(bool(host.municipal_inspect().get("unresolved_complaints", 0) >= 1), "存在未处理投诉")
	check(bool(host.municipal_resolve_complaint(0).get("ok", false)), "投诉处理完成")
	# 邮政快递。
	check(bool(host.postal_accept("p1", 1.0, 100.0).get("ok", false)), "收寄包裹")
	check(bool(host.postal_ship().get("ok", false)), "包裹发运完成")
	check(bool(host.postal_claim().get("ok", false)), "包裹理赔受理")
	# 快递员职业。
	check(bool(host.start_courier_career().get("ok", false)), "成为快递员")
	check(bool(host.start_courier_career().get("reason", "") == "already_career"), "重复入行被拒")
	check(bool(host.courier_deliver().get("ok", false)), "揽投一件")
	# 特许经营与政府购买。
	check(bool(host.municipal_grant_franchise("street_cleaning").get("ok", false)), "取得道路保洁特许")
	check(bool(host.municipal_assess_quality(0.9).get("ok", false)), "服务考核完成")
	var utility: Dictionary = host.municipal_utility_report(30.0)
	check(bool(utility.get("ok", false)) and int(utility.get("revenue", 0)) > 0, "公用事业报表结算营收")
	check(bool(host.municipal_government_purchase("park_maintenance", 800000).get("ok", false)), "政府购买服务完成")
	check(bool(host.municipal_tender("滨江步道", 5000000).get("ok", false)), "市政项目招标定标")
	check(bool(host.municipal_hearing("滨江步道", 0.7).get("ok", false)), "市政项目听证")
	check(not host.municipal_panel_data().get("tender", {}).is_empty(), "招标结果进入市政面板")
	# 持久化与读档恢复。
	host._persist_municipal()
	check(state.sim_runtime.get("municipal", null) is Dictionary, "市政运行态写入 sim_runtime")
	var reloaded = SimHostScript.new(state, 121)
	reloaded.bind(state)
	check(not (reloaded.municipal_state().get("city", {}) as Dictionary).is_empty(), "读档恢复城市市政")
	check(not (reloaded.municipal_state().get("hub", {}) as Dictionary).is_empty(), "读档恢复邮政枢纽")
	check(not (reloaded.municipal_state().get("courier", {}) as Dictionary).is_empty(), "读档恢复快递员")
	check(not reloaded.municipal_panel_data().is_empty(), "市政面板数据非空")


func _test_debt_runtime() -> void:
	var state = GameStateScript.new()
	state.new_game(131)
	var host = SimHostScript.new(state, 131)
	host.bind(state)
	check(host.debt_businesses_catalog().size() >= 6, "放贷业务表含典当/民间借贷等")
	check(host.debt_collection_modes_catalog().size() >= 5, "催收方式表含合法/灰色")
	# 典当与赎回。
	check(bool(host.debt_pawn("手表", 500000, 0.12).get("ok", false)), "典当成功")
	check(bool(host.debt_redeem().get("ok", false)), "赎回成功")
	# 借贷（抬高收入与信用以通过审批）。
	host.player()["income"] = 10000000
	host.player()["credit_history"] = 1.0
	var b: Dictionary = host.debt_borrow("micro_loan", 100000, 0.12)
	check(bool(b.get("ok", false)) and bool(b.get("approved", false)), "借贷获批")
	var b2: Dictionary = host.debt_borrow("consumer_finance", 80000, 0.10, "bank_b")
	check(bool(b2.get("ok", false)) and bool(b2.get("approved", false)), "第二笔跨机构借贷获批")
	var ledger: Dictionary = host.debt_ledger()
	check(int(ledger.get("borrow_count", 0)) >= 2, "多笔贷款台账逐笔登记")
	var report: Dictionary = host.debt_credit_report()
	check(int(report.get("institutions", 0)) >= 2 and bool(report.get("multi_institution", false)), "跨机构征信汇总")
	host.economy.add_money(host.account_id(), 500000, "test")
	check(bool(host.debt_repay(50000).get("ok", false)), "按笔还款成功")
	check(bool(host.debt_assess_credit().get("approved", false)), "信用评估通过")
	# 放贷与双路径催收。
	check(bool(host.debt_lend("private_lending", 500000, 0.12).get("ok", false)), "放贷登记")
	var legal: Dictionary = host.debt_collect("reminder")
	check(bool(legal.get("ok", false)) and not bool(legal.get("illegal", false)), "合法催收不违法")
	var gray: Dictionary = host.debt_collect("violence")
	check(bool(gray.get("ok", false)) and bool(gray.get("illegal", false)), "暴力催收违法")
	# 债务困境与边界。
	check(bool(host.debt_restructure().get("ok", false)), "债务重组完成")
	check(bool(host.debt_predatory(300000).get("ok", false)), "套路贷办理")
	host._debt_lender["license"] = false
	check(bool(host.debt_illegal_fundraising(1000000).get("illegal", false)), "无牌集资违法")
	check(bool(host.debt_abscond().get("ok", false)), "跑路结算")
	var bk: Dictionary = host.debt_bankruptcy()
	check(not bool(bk.get("ok", false)) and String(bk.get("reason", "")) == "era_not_allowed", "早期时代禁止个人破产")
	# 持久化与读档恢复。
	host._persist_debt()
	check(state.sim_runtime.get("debt", null) is Dictionary, "债务运行态写入 sim_runtime")
	var reloaded = SimHostScript.new(state, 131)
	reloaded.bind(state)
	check(not (reloaded.debt_state().get("loan", {}) as Dictionary).is_empty(), "读档恢复借入贷款")
	check(not (reloaded.debt_state().get("lend", {}) as Dictionary).is_empty(), "读档恢复放出贷款")
	check(not reloaded.debt_panel_data().is_empty(), "债务面板数据非空")


func _test_consumer_runtime() -> void:
	var state = GameStateScript.new()
	state.new_game(141)
	var host = SimHostScript.new(state, 141)
	host.bind(state)
	check(host.consumer_channels_catalog().size() >= 6, "维权渠道表含协商/平台/12315等")
	check(host.consumer_incident_kinds_catalog().size() >= 2, "事故类型含食安/质量")
	# 下单与退换（质量原因不受窗口限制）。
	host.consumer_new_order(100000, "electronics", true, false)
	var ret: Dictionary = host.consumer_return(100, "quality")
	check(bool(ret.get("ok", false)) and bool(ret.get("accepted", false)), "质量问题退货受理")
	# 三包。
	host.consumer_new_order(200000, "appliance", true, false)
	check(bool(host.consumer_three_guarantee(2).get("eligible", false)), "三包退换成立")
	# 保修。
	host.consumer_new_product(500000, 365)
	check(bool(host.consumer_warranty(30).get("covered", false)), "质保期内保修免费")
	check(not bool(host.consumer_warranty(1000).get("covered", true)), "超保修期收费")
	# 举证责任倒置。
	host.consumer_new_order(300000, "appliance", true, false)
	check(String(host.consumer_burden(30).get("bearer", "")) == "merchant", "耐用商品举证责任在商家")
	# 维权路径与集体维权。
	check(bool(host.consumer_dispute("platform", 0.9).get("ok", false)), "平台投诉受理")
	var hotline: Dictionary = host.consumer_12315(0.8)
	check(bool(hotline.get("accepted", false)) and String(hotline.get("case_no", "")) != "", "12315 受理并生成案号")
	var counter: Dictionary = host.consumer_12315(0.1, true)
	check(bool(counter.get("counterclaim_risk", false)), "低证据恶意投诉触发商家反诉风险")
	check(bool(host.consumer_class_action(0.9).get("ok", false)), "集体维权受理")
	# 监管事故与召回。
	var inc: Dictionary = host.consumer_incident("food_safety", 0.9, 5)
	check(bool(inc.get("ok", false)) and bool(inc.get("delisted", false)), "食安事故下架")
	check(bool(host.consumer_recall(100).get("ok", false)), "召回结算")
	# 职业打假与恶意索赔。
	host.consumer_new_order(100000, "general", true, false)
	check(bool(host.consumer_professional_fraud().get("ok", false)), "职业打假结算")
	host.consumer_new_order(100000, "general", false, false)
	check(bool(host.consumer_malicious_claim().get("malicious", false)), "恶意索赔标记")
	# 持久化与读档恢复。
	host._persist_consumer()
	check(state.sim_runtime.get("consumer", null) is Dictionary, "消费者运行态写入 sim_runtime")
	var reloaded = SimHostScript.new(state, 141)
	reloaded.bind(state)
	check(not (reloaded.consumer_state().get("order", {}) as Dictionary).is_empty(), "读档恢复消费订单")
	check(not reloaded.consumer_panel_data().is_empty(), "消费者面板数据非空")


func _test_welfare_runtime() -> void:
	var state = GameStateScript.new()
	state.new_game(151)
	var host = SimHostScript.new(state, 151)
	host.bind(state)
	check(host.welfare_application_kinds_catalog().size() >= 6, "救助类型含收养/寄养/低保等")
	check(host.welfare_crisis_kinds_catalog().size() >= 3, "变故情形含孤儿/遗弃/监护人失能")
	# 收养资格（满足门槛）。
	var p: Dictionary = host.player()
	p["age"] = 35
	p["income"] = 200000.0
	p["assets"] = 100000.0
	p["criminal_record"] = false
	p["major_illness"] = false
	check(bool(host.welfare_apply("adoption").get("approved", false)), "收养资格通过")
	var recog: Dictionary = host.welfare_recognize("region-a")
	check(bool(recog.get("ok", false)) and String((recog.get("certificate", {}) as Dictionary).get("target", "")) != "", "跨区资格互认生成凭证")
	# 不符合门槛被拒，原因逐条可查。
	p["age"] = 20
	var rej: Dictionary = host.welfare_apply("adoption")
	check(not bool(rej.get("approved", true)), "低龄收养被拒")
	check((rej.get("reasons", []) as Array).size() > 0, "驳回原因逐条可查")
	# 收养等待期、生效与撤销。
	p["age"] = 40
	check(bool(host.welfare_apply("adoption").get("approved", false)), "收养资格再次通过")
	check(not bool(host.welfare_finalize_placement().get("ok", false)), "等待期内不可生效")
	state.clock["absolute_minutes"] = int(state.clock.get("absolute_minutes", 0)) + 31 * 1440
	check(bool(host.welfare_finalize_placement().get("ok", false)), "等待期满收养生效")
	check(bool(host.welfare_revoke_placement().get("ok", false)), "生效后可撤销收养")
	# 低保资格与救助发放。
	p["age"] = 40
	p["income"] = 6000.0
	p["household_size"] = 3
	p["registered_local"] = true
	check(bool(host.welfare_apply("dibao").get("approved", false)), "低保资格通过")
	check(int(host.welfare_disburse(30).get("paid", 0)) > 0, "救助金发放")
	# 家庭变故安置。
	check(String(host.welfare_crisis("orphan", false).get("route", "")) != "", "孤儿进入安置体系")
	# 慈善基金：设立、捐赠、结算、支出、审计、挪用。
	check(bool(host.welfare_fund_new("希望基金").get("ok", false)), "设立慈善基金")
	host.welfare_fund_donate(500000)
	check(int(host.welfare_fund_settle().get("to_cause", 0)) > 0, "募捐结算")
	check(bool(host.welfare_fund_spend("助学", 100000).get("ok", false)), "公益支出")
	check(int(host.welfare_fund_audit().get("transparency", 0)) >= 0, "善款审计")
	check(bool(host.welfare_fund_misappropriate(50000).get("ok", false)), "善款挪用登记")
	# 社工与个案。
	check(bool(host.welfare_worker_start().get("ok", false)), "社工入职")
	check(bool(host.welfare_case_open("family-1").get("ok", false)), "开立个案")
	var follow: Dictionary = {}
	for i in range(4):
		follow = host.welfare_follow_up("家访%d" % (i + 1))
	check(bool(follow.get("closed", false)), "进展达标结案")
	check(bool(host.welfare_close_case().get("ok", false)), "结案累计业绩")
	# 虐待举报与救助依赖。
	check(bool(host.welfare_report_abuse().get("ok", false)), "虐待举报受理")
	check(bool(host.welfare_dependency().get("ok", false)), "救助依赖评估")
	# 持久化与读档恢复。
	host._persist_welfare()
	check(state.sim_runtime.get("welfare", null) is Dictionary, "救助运行态写入 sim_runtime")
	var reloaded = SimHostScript.new(state, 151)
	reloaded.bind(state)
	check(not (reloaded.welfare_state().get("application", {}) as Dictionary).is_empty(), "读档恢复救助申请")
	check(not reloaded.welfare_panel_data().is_empty(), "救助面板数据非空")


func _test_funeral_runtime() -> void:
	var state = GameStateScript.new()
	state.new_game(161)
	var host = SimHostScript.new(state, 161)
	host.bind(state)
	check(host.funeral_methods_catalog().size() >= 5, "殡葬方式表含火化/土葬/海葬等")
	check(host.funeral_grave_types_catalog().size() >= 3, "墓位类型表")
	check(host.funeral_memorial_kinds_catalog().size() >= 4, "纪念形式表")
	# 安排与执行（遗产充足）。
	var arr: Dictionary = host.funeral_arrange("cremation", "", 1000000)
	check(bool(arr.get("ok", false)) and bool(arr.get("affordable", false)), "殡葬安排可行")
	check(bool(host.funeral_execute(false).get("ok", false)), "殡葬执行成功")
	# 遗产不足时拒绝下葬，公益救助可兜底。
	host.funeral_arrange("burial", "premium", 0)
	check(not bool(host.funeral_execute(false).get("ok", true)), "遗产不足拒绝下葬")
	check(bool(host.funeral_execute(true).get("ok", false)), "公益救助下葬")
	# 器官捐献：登记、伦理、分配、移植、撤销。
	check(bool(host.funeral_register_donation().get("ok", false)), "登记器官捐献")
	check(bool(host.funeral_review_ethics().get("approved", false)), "伦理审查通过")
	var organ_alloc: Dictionary = host.funeral_allocate_organs()
	check(bool(organ_alloc.get("ok", false)), "器官分配")
	check((organ_alloc.get("allocated", []) as Array).size() >= 2, "器官分配覆盖多受体")
	check(bool(host.funeral_transplant("heart").get("ok", false)), "器官移植结算")
	check(bool(host.funeral_revoke_donation(true).get("ok", false)), "家属撤销捐献")
	# 纪念：立碑、祭扫、数字纪念。
	check(bool(host.funeral_build_memorial("monument").get("ok", false)), "立纪念碑")
	check(bool(host.funeral_tomb_sweeping("monument").get("ok", false)), "祭扫纪念")
	check(bool(host.funeral_digital_memorial().get("ok", false)), "数字纪念")
	host.economy.add_money(host.account_id(), 500000, "test")
	var platform: Dictionary = host.funeral_digital_platform(100, 1000)
	check(bool(platform.get("ok", false)) and int(platform.get("net", 0)) > 0, "数字纪念平台订阅结算")
	check(int(platform.get("fund", 0)) > 0, "平台公益基金入账")
	# 遗嘱执行（无效遗嘱仅建议）。
	check(bool(host.funeral_execute_will().get("ok", false)), "遗嘱执行结算")
	# 殡葬行业：开办、报价、成交、监管、改革。
	check(bool(host.funeral_new_home("永宁殡仪馆").get("ok", false)), "开办殡仪馆")
	check(int(host.funeral_quote("cremation").get("price", 0)) > 0, "殡葬报价")
	check(bool(host.funeral_sale("burial").get("ok", false)), "殡葬成交")
	check(bool(host.funeral_regulate().get("ok", false)), "殡葬监管")
	check(bool(host.funeral_reform().get("ok", false)), "殡葬改革")
	# 边界：无人认领、捐献争议。
	check(bool(host.funeral_unclaimed().get("ok", false)), "无人认领遗体处置")
	check(bool(host.funeral_dispute().get("ok", false)), "捐献争议流程")
	# 持久化与读档恢复。
	host._persist_funeral()
	check(state.sim_runtime.get("funeral", null) is Dictionary, "殡葬运行态写入 sim_runtime")
	var reloaded = SimHostScript.new(state, 161)
	reloaded.bind(state)
	check(not (reloaded.funeral_state().get("state", {}) as Dictionary).is_empty(), "读档恢复殡葬状态")
	check(not reloaded.funeral_panel_data().is_empty(), "殡葬面板数据非空")


func _test_metaphysics_runtime() -> void:
	var state = GameStateScript.new()
	state.new_game(171)
	var host = SimHostScript.new(state, 171)
	host.bind(state)
	check(host.metaphysics_phrases_catalog().size() >= 56, "玄学话术库按服务/结果分档")
	check(host.metaphysics_services_catalog().size() >= 7, "玄学服务表含算命/风水等")
	check(host.metaphysics_modes_catalog().size() >= 2, "线上/线下模式")
	check(host.metaphysics_folk_practices_catalog().size() >= 8, "民俗活动表")
	# 咨询不改变属性与事件结果（硬约束）。
	var c: Dictionary = host.metaphysics_consult("fortune", "online")
	check(bool(c.get("ok", false)), "玄学咨询结算")
	check(not bool(c.get("attributes_changed", true)), "咨询不改变属性")
	check(not bool(c.get("event_outcome_changed", true)), "咨询不改变事件结果")
	# 民俗信仰。
	check(bool(host.metaphysics_folk("festival_ritual").get("ok", false)), "民俗仪式")
	check(bool(host.metaphysics_folk("ancestor_worship").get("ok", false)), "祭祖仪式")
	check(bool(host.metaphysics_folk("temple_fair").get("ok", false)), "庙会活动")
	# 经营与风险。
	check(bool(host.metaphysics_new_business("青云观").get("ok", false)), "开办玄学馆")
	check(int(host.metaphysics_operate().get("earned", 0)) > 0, "玄学营业入账")
	host.metaphysics_complaint(true)
	host.metaphysics_complaint(true)
	host.metaphysics_complaint(true)
	check(bool(host.metaphysics_investigate().get("ok", false)), "诈骗查处")
	check(bool(host.metaphysics_master_fall().get("ok", false)), "人设翻车")
	# 边界。
	check(float(host.metaphysics_superstition(500).get("influence", 0.0)) > 0.0, "组织化迷信影响力")
	check(bool(host.metaphysics_collude().get("ok", false)), "勾结灰产")
	check(bool(host.metaphysics_blur().get("indistinguishable", false)), "真假不可区分")
	# 持久化与读档恢复。
	host._persist_metaphysics()
	check(state.sim_runtime.get("metaphysics", null) is Dictionary, "玄学运行态写入 sim_runtime")
	var reloaded = SimHostScript.new(state, 171)
	reloaded.bind(state)
	check(not (reloaded.metaphysics_state().get("business", {}) as Dictionary).is_empty(), "读档恢复玄学经营")
	check(not reloaded.metaphysics_panel_data().is_empty(), "玄学面板数据非空")


func _test_anomaly_runtime() -> void:
	var state = GameStateScript.new()
	state.new_game(181)
	var host = SimHostScript.new(state, 181)
	host.bind(state)
	# 默认隔离：隐藏、不激活、不参与常规结算。
	check(bool(host.anomaly_state().get("hidden", false)), "异常默认隐藏")
	check(not host.anomaly_revealed(), "异常默认不可见")
	check(host.anomaly.regular_effects(host.anomaly_state()).is_empty(), "隐藏时不产生常规结算影响")
	# 分级与目录。
	check(host.anomaly_gate_catalog().size() >= 5, "门闩途径≥5")
	check(host.anomaly_entry_catalog().size() >= 13, "核心异常条目≥13")
	check(host.anomaly_catalog_validate(50).get("ok", false), "异常生成目录抽样校验")
	check(host.anomaly_mission_catalog().size() >= 12, "异常阵营任务线目录")
	check(bool(host.anomaly_join_faction("foundation").get("ok", false)), "加入基金会")
	host.anomaly.add_exposure(host.anomaly_state(), 10.0)
	check(bool(host.anomaly_accept_mission("fd-01", "foundation").get("ok", false)), "接取阵营任务")
	var done: Dictionary = host.anomaly_complete_mission("fd-01", true)
	check(bool(done.get("ok", false)), "完成阵营任务")
	check(host.anomaly.exposure(host.anomaly_state()) < 10.0, "基金会任务降低暴露")
	var crime_before: int = int(host.regions.get_region(host.current_region_id()).snapshot.get("crime_rate", 0))
	check(bool(host.anomaly_join_faction("black_lab").get("ok", false)), "脱离基金会加入黑实验室")
	host.anomaly_accept_mission("bl-01", "black_lab")
	host.anomaly_complete_mission("bl-01", true)
	check(int(host.regions.get_region(host.current_region_id()).snapshot.get("crime_rate", 0)) == crime_before + 2, "黑实验室任务推高区域犯罪率")
	check(String(host._police_case.get("crime", "")) == "illegal_experiment", "黑实验室任务触发警方立案")
	check(int(state.legacy.get("history", []).size()) > 0, "任务完成写入家族史")
	check(host.anomaly_ability_catalog().size() >= 4, "能力线≥4")
	check(host.anomaly_faction_catalog().size() >= 4, "阵营≥4")
	check(host.anomaly_identity_catalog().size() >= 5, "身份≥5")
	# 门闩与激活。
	check(bool(host.anomaly_open_gate("bloodline").get("ok", false)), "开启血脉门闩")
	check(bool(host.anomaly_state().get("active", true)) == true, "门闩开启后激活")
	check(host.anomaly_revealed(), "异常世界可见")
	# 权限与图鉴。
	host.anomaly_set_clearance(2)
	var enc: Dictionary = host.anomaly_encounter("异-002")
	check(bool(enc.get("ok", false)), "按权限查阅条目")
	check(bool(enc.get("known", false)), "查阅后写入图鉴")
	# 能力使用。
	check(bool(host.anomaly_use_ability("cultivation").get("ok", false)), "施展修炼能力")
	# 暴露反噬。
	host.anomaly.add_exposure(host.anomaly_state(), 80.0)
	var bl: Dictionary = host.anomaly.check_backlash(host.anomaly_state())
	check(bool(bl.get("triggered", false)), "暴露达阈值触发反噬")
	check(not String(bl.get("type", "")).is_empty(), "反噬类型非空")
	# 认知污染与记忆删除剂。
	host.anomaly.contact_hazard(host.anomaly_state(), "meme", 20.0)
	var am: Dictionary = host.anomaly_amnestics(0.5)
	check(bool(am.get("ok", false)), "施用记忆删除剂")
	check(int(am.get("memory_gaps", 0)) > 0, "记忆删除剂副作用（记忆缺口）")
	# 对抗与收容失效。
	var cb: Dictionary = host.anomaly_combat()
	check(cb.has("attacker_wins"), "认知对抗结算")
	var before_exp: float = float(host.anomaly.exposure(host.anomaly_state()))
	host.anomaly_breach()
	check(float(host.anomaly.exposure(host.anomaly_state())) > before_exp, "收容失效抬升暴露")
	# 传承与社会事件交叉。
	var heir: Dictionary = host.anomaly.new_state()["anomaly"]
	check(bool(host.anomaly.inherit(host.anomaly_state(), heir).get("ok", false)), "异常传承结算")
	var mj: Dictionary = host.anomaly.misjudged_as_crime(host.anomaly_state(), {"anomaly_caused": true})
	check(String(mj.get("flag", "")) == "anomaly_override", "异常触发犯罪误判抑制标记")
	# 持久化与读档恢复。
	host._persist_anomaly()
	check(state.sim_runtime.get("anomaly", null) is Dictionary, "异常运行态写入 sim_runtime")
	var reloaded = SimHostScript.new(state, 181)
	reloaded.bind(state)
	check(reloaded.anomaly_revealed(), "读档恢复异常可见性")
	check(not (reloaded.anomaly_state().get("known_entries", {}) as Dictionary).is_empty(), "读档恢复异常图鉴")


func _test_medical_runtime() -> void:
	var state = GameStateScript.new()
	state.new_game(191)
	var host = SimHostScript.new(state, 191)
	host.bind(state)
	check(host.medical_diseases_catalog().size() >= 25, "疾病库≥25")
	check(host.medical_facilities_catalog().size() >= 4, "医疗机构≥4")
	check(host.medtech_care_levels_catalog().size() >= 3, "分级诊疗≥3")
	check(host.medtech_departments_catalog().size() >= 10, "科室≥10")
	check(host.medtech_exams_catalog().size() >= 4, "检查项目≥4")
	check(host.medtech_high_end_catalog().size() >= 6, "高阶医疗≥6")
	check(host.medtech_organ_source_catalog().size() >= 4, "器官来源≥4")
	# 就医与治疗。
	host.economy.add_money(host.account_id(), 5000000, "test")
	# 年度预算跨年重置。
	host._medical_region["fiscal_year"] = host._current_year() - 1
	host._medical_region["annual_budget"] = 500000
	host._medical_region["insurance_fund"] = 0
	host._medical_region["budget_spent"] = 500000
	host._medical_ensure_fiscal_year()
	check(int(host._medical_region.get("insurance_fund", 0)) == 500000, "医保年度预算跨年重置")
	check(int(host._medical_region.get("budget_spent", -1)) == 0, "年度支出清零")
	var fund_before: int = int(host._medical_region.get("insurance_fund", 0))
	var visit: Dictionary = host.medical_visit("hospital", "surgery", "")
	check(bool(visit.get("ok", false)), "手术结算")
	check(int(host._medical_region.get("insurance_fund", 0)) <= fund_before, "医保基金按报销扣减")
	check(int(host.regions.get_region(host.current_region_id()).snapshot.get("medical_spending", 0)) > 0, "医保支出回写区域统计")
	var drug: Dictionary = host.medical_drug_course(180, 0.5)
	check(bool(drug.get("ok", false)) and float(drug.get("resistance", 0.0)) > 0.0, "长期用药累计耐药")
	check(bool(host.medical_visit("hospital", "register").get("ok", false)), "挂号结算")
	host.medical.trigger("cold", 0)
	check(bool(host.medical_treat("cold", "medicine").get("ok", false)), "治疗感冒")
	# 分级诊疗与检查。
	check(bool(host.medtech_register("secondary", "surgery").get("ok", false)), "二级挂号外科")
	check(bool(host.medtech_register("primary", "surgery").get("referral_needed", false)), "基层外科需转诊")
	check(bool(host.medtech_examine("tertiary", "pathology").get("ok", false)), "三级病理检查")
	# 高阶医疗与伦理法律门。
	check(bool(host.medtech_high_end("organ_transplant", "voluntary_donation").get("ok", false)), "合法器官移植")
	var illegal: Dictionary = host.medtech.high_end_procedure("organ_transplant", {"ethics_cleared": true, "legal_cleared": true, "organ_source": "black_market", "roll": 0.5})
	check(String(illegal.get("reason", "")) == "illegal_organ_source", "黑市器官来源被拒")
	check(bool(host.medtech_review_ethics("gene_edit", 0.8).get("approved", false)), "伦理审查通过")
	# 医药产业。
	check(bool(host.medtech_pharma_new("恒瑞").get("ok", false)), "开办医药公司")
	check(bool(host.medtech_pharma_start("药A").get("ok", false)), "新药立项")
	check(host.medtech_pharma_advance("药A").has("advanced"), "推进管线结算")
	(host._pharma_company["pipeline"]["药A"] as Dictionary)["stage"] = "production"
	check(bool(host.medtech_pharma_produce("药A", 2.0).get("ok", false)), "药品生产")
	(host._pharma_company["pipeline"]["药A"] as Dictionary)["stage"] = "sales"
	check(int(host.medtech_pharma_sell("药A", 100.0, 1000).get("revenue", 0)) > 0, "药品销售营收")
	check(bool(host.medtech_medical_rep("药A", 0.2).get("ok", false)), "医药代表推广")
	# 风险与边界。
	check(host.medtech_counterfeit(0.5).has("seized"), "假药查缉结算")
	check(host.medtech_over_treatment(100000).has("excess_cost"), "过度医疗结算")
	check(host.medtech_insurance_fraud(100000).has("detected"), "医保欺诈结算")
	check(bool(host.medtech_trial_scandal("药A").get("ok", false)), "试验丑闻结算")
	# 医患纠纷：达到诉讼阈值即进入民事侵权案件。
	host._civil = {}
	var disp: Dictionary = host.medtech_dispute(0.9)
	check(bool(disp.get("litigation", false)), "医患纠纷达到诉讼阈值")
	check(bool(disp.get("civil_filed", false)), "医患纠纷自动立案")
	check_eq(String((host._civil.get("claim", {}) as Dictionary).get("type_name", "")), "医疗纠纷", "民事案件类型为医疗纠纷")
	check(bool(state.sim_runtime.get("civil", {}).get("claim", {}).has("title")), "医患诉讼写入 sim_runtime.civil")
	# 持久化与读档恢复。
	host._persist_medical()
	check(state.sim_runtime.get("medical", null) is Dictionary, "医疗运行态写入 sim_runtime")
	var reloaded = SimHostScript.new(state, 191)
	reloaded.bind(state)
	check(String(reloaded._pharma_company.get("name", "")) != "", "读档恢复医药公司")
	check(not reloaded.medical_panel_data().is_empty(), "医疗面板数据非空")


func _test_content_industry_runtime() -> void:
	var state = GameStateScript.new()
	state.new_game(201)
	var host = SimHostScript.new(state, 201)
	host.bind(state)
	check(host.content_types_catalog().size() >= 6, "内容类型≥6")
	check(host.content_roles_catalog().size() >= 6, "创作角色≥6")
	check(host.content_channels_catalog().size() >= 5, "变现渠道≥5")
	check(host.content_ip_operations_catalog().size() >= 4, "IP 运营方式≥4")
	check(host.content_funding_stages_catalog().size() >= 5, "融资轮次≥5")
	# 工作室与团队。
	check(bool(host.content_new_studio("星火").get("ok", false)), "开办工作室")
	check(bool(host.content_hire("engineering", 2).get("ok", false)), "招募程序")
	check(bool(host.content_hire("art", 1).get("ok", false)), "招募美术")
	check(host._content_studio["team"].has("engineering"), "团队含程序")
	# 作品创作。
	check(bool(host.content_new_work("game", "星河传说").get("ok", false)), "立项游戏")
	check(not host._content_work.is_empty(), "在研作品非空")
	host.content_manage(0.8)
	var adv: Dictionary = host.content_advance(600.0)
	check(bool(adv.get("ready", false)), "推进后可发行")
	# 发行与变现。
	check(bool(host.content_release().get("ok", false)), "作品发行")
	check(bool(host.content_monetize("platform_share").get("ok", false)), "平台分成")
	# IP 运营。
	var ipr: Dictionary = host.content_register_ip()
	check(bool(ipr.get("ok", false)), "登记版权")
	check(String((ipr.get("ip", {}) as Dictionary).get("legal_ip_id", "")).begins_with("ip.media."), "作品版权同步登记知识产权")
	check(bool(host.content_adapt("anime").get("ok", false)), "IP 改编")
	check(bool(host.content_operate_ip("merchandise", 1000000.0).get("ok", false)), "IP 运营")
	# 专业服务经纪联动：未给交易额时按工作室估值撮合。
	host.economy.add_money(host.account_id(), 50000000, "test")
	check(bool(host.prof_new_firm("星火经纪").get("ok", false)), "文娱经纪事务所")
	check(bool(host.prof_new_project("investment_banking", "studio.player").get("ok", false)), "文娱并购项目")
	var ma: Dictionary = host.prof_ma_advisory(0)
	check(String(ma.get("target", "")) == "content_studio", "并购顾问识别文娱工作室")
	check(int(ma.get("deal_size", 0)) > 0, "文娱并购交易额由工作室估值生成")
	# 风险。
	check(host.content_plagiarism(0.9, 0.9).has("exposed"), "抄袭检测结算")
	var compliance: Dictionary = host.content_compliance(0.9, 0.9)
	check(compliance.has("approved"), "内容合规结算")
	check(compliance.has("platform_action"), "内容合规联动平台审查")
	check(host.content_scandal(0.9, 0.9).has("occurred"), "翻车事件结算")
	# 经营边界。
	check(bool(host.content_funding("seed").get("ok", false)), "种子轮融资")
	var fandom: Dictionary = host.content_fandom(0.3)
	check(fandom.has("fandom_size"), "粉丝演化结算")
	check(not String(fandom.get("social_post_id", "")).is_empty(), "饭圈舆情写入社交平台")
	check(host.content_approval("game").has("approved"), "版号审批结算")
	check(bool(host.content_poach("design", 3.0).get("ok", false)), "挖角结算")
	# 下架。
	check(bool(host.content_takedown("content_violation", 0.7).get("ok", false)), "作品下架")
	# 持久化与读档恢复。
	host._persist_content()
	check(state.sim_runtime.get("content", null) is Dictionary, "文娱运行态写入 sim_runtime")
	var reloaded = SimHostScript.new(state, 201)
	reloaded.bind(state)
	check(String(reloaded._content_studio.get("name", "")) == "星火", "读档恢复工作室")
	check(not reloaded.content_panel_data().is_empty(), "文娱面板数据非空")
	check(not reloaded._content_work.is_empty(), "读档恢复在研作品")


func _test_engineering_runtime() -> void:
	var state = GameStateScript.new()
	state.new_game(211)
	var host = SimHostScript.new(state, 211)
	host.bind(state)
	check(host.engineering_qualifications_catalog().size() >= 3, "资质等级≥3")
	check(host.engineering_stages_catalog().size() >= 6, "工程链条≥6 阶段")
	check(host.engineering_zone_types_catalog().size() >= 5, "功能区类型≥5")
	# 工程公司与承接。
	check(bool(host.eng_new_contractor("宏基建设", "first").get("ok", false)), "成立工程公司")
	check(not host._eng_contractor.is_empty(), "工程公司非空")
	check(bool(host.eng_take_project("跨江大桥", 50000000).get("ok", false)), "承接工程")
	check(not host._eng_project.is_empty(), "在建工程非空")
	# 链条推进：勘察→设计→造价→施工→监理→验收。
	for _i in 6:
		host.eng_advance()
	check(String(host._eng_project.get("stage", "")) == "completed", "链条推完")
	check(int(host._eng_project.get("stage_index", 0)) >= 6, "链条阶段走满")
	# 验收：高质量工程方可验收。
	host._eng_project["quality"] = 0.9
	check(bool(host.engineering.accept(host._eng_project, {"threshold": 0.6}).get("passed", false)), "优质工程验收通过")
	# 监理。
	check(bool(host.eng_supervise(0.8).get("ok", false)), "工程监理")
	# 招投标与风险。
	check(bool(host.eng_tender().has("winner")), "招标")
	check(bool(host.eng_rig().get("ok", false)), "围标")
	check(bool(host.eng_bribe(20000000).has("exposed")), "招标行贿")
	check(bool(host.eng_cut_corners(0.5).get("ok", false)), "偷工减料")
	check(bool(host.eng_accident().has("occurred")), "工程事故结算")
	check(bool(host.eng_arrears(10000000).get("ok", false)), "欠款结算")
	check(bool(host.eng_debt_chain(10000000).get("ok", false)), "三角债结算")
	# 城市规划。
	var region = host.regions.get_region(host.current_region_id())
	var snap_before: Dictionary = region.snapshot.duplicate(true)
	check(bool(host.eng_new_city("云港", 1200000).get("ok", false)), "规划新城")
	check(bool(host.eng_rezone("商业区", "commercial").get("ok", false)), "变更用地")
	check(int(region.snapshot.get("population", 0)) == int(host._eng_city.get("population", -1)), "规划人口回写区域")
	check(float(region.snapshot.get("land_price", 0.0)) != float(snap_before.get("land_price", 0.0)), "规划地价回写区域快照")
	check(bool(host.eng_transport("商业区").get("ok", false)), "城建交通")
	check(bool(host.eng_planning_corruption(20000000).has("exposed")), "规划腐败")
	check(bool(host.eng_demolition("商业区", 1000, 500000).get("ok", false)), "房屋拆迁")
	# 房地产。
	check(bool(host.eng_new_developer("宏基地产", 50000000).get("ok", false)), "成立地产公司")
	check(bool(host.eng_pre_sale(10, 1000000).get("ok", false)), "楼盘预售")
	check(bool(host.eng_develop(5000000).get("ok", false)), "楼盘施工")
	check(bool(host.eng_unfinished().has("stalled")), "楼盘烂尾结算")
	# 持久化与读档恢复。
	host._persist_engineering()
	check(state.sim_runtime.get("engineering", null) is Dictionary, "工程运行态写入 sim_runtime")
	var reloaded = SimHostScript.new(state, 211)
	reloaded.bind(state)
	check(String(reloaded._eng_contractor.get("name", "")) == "宏基建设", "读档恢复工程公司")
	check(String(reloaded._eng_city.get("name", "")) == "云港", "读档恢复城市")
	check(not reloaded.engineering_panel_data().is_empty(), "工程面板数据非空")


func _test_professional_runtime() -> void:
	var state = GameStateScript.new()
	state.new_game(221)
	var host = SimHostScript.new(state, 221)
	host.bind(state)
	check(host.prof_practice_types_catalog().size() >= 8, "执业类型≥8")
	check(host.prof_qualifications_catalog().size() >= 3, "专业资质≥3")
	# 开事务所与资质。
	check(bool(host.prof_new_firm("恒信事务所").get("ok", false)), "开办事务所")
	check(not host._prof_firm.is_empty(), "事务所非空")
	check(bool(host.prof_acquire("cpa").get("ok", false)), "考取 CPA")
	check(bool(host.prof_acquire("cpa").get("reason", "") == "already_qualified"), "重复考取被拒")
	check(bool(host.prof_acquire("nope").get("reason", "") == "unknown_cert"), "未知资质被拒")
	# 客户与项目。
	var ca: Dictionary = host.prof_client()
	check(bool(ca.get("ok", false)), "开发客户结算")
	check(bool(host.prof_new_project("accounting_audit", "客户甲").get("ok", false)), "立项项目")
	check(int(host.regions.get_region(host.current_region_id()).snapshot.get("professional_projects", 0)) > 0, "专业项目回写区域统计")
	check(not host._prof_project.is_empty(), "立项项目非空")
	# 尽调与并购。
	check(bool(host.prof_due_diligence(0.9).has("findings")), "尽职调查")
	check(bool(host.prof_ma_advisory(10000000).has("success")), "并购顾问")
	# 独立性审查。
	check(bool(host.prof_independence(["audit", "consulting"]).get("conflict", false)), "审计独立性冲突")
	check(not bool(host.prof_independence(["audit"]).get("conflict", false)), "单一角色无冲突")
	# 执业风险。
	check(bool(host.prof_false_report(0.6).get("ok", false)), "虚假报告结算")
	check(bool(host.prof_insider(1000000).has("exposed")), "内幕交易结算")
	check(bool(host.prof_bribery(500000).has("exposed")), "商业贿赂结算")
	# 合伙人。
	check(bool(host.prof_add_partner("王会计", 0.2, 3).get("ok", false)), "吸收合伙人")
	check(bool(host.prof_add_partner("王会计").get("reason", "") == "already_partner"), "重复合伙人被拒")
	check(bool(host.prof_partner_split("王会计").get("ok", false)), "合伙人分裂")
	check(bool(host.prof_partner_split("王会计").get("reason", "") == "not_partner"), "查无合伙人被拒")
	# 边界。
	check(bool(host.prof_non_compete().has("violation")), "竞业限制结算")
	check(bool(host.prof_churn().get("ok", false)), "客户流失结算")
	# 持久化与读档恢复。
	host._persist_professional()
	check(state.sim_runtime.get("professional", null) is Dictionary, "专业服务运行态写入 sim_runtime")
	var reloaded = SimHostScript.new(state, 221)
	reloaded.bind(state)
	check(String(reloaded._prof_firm.get("name", "")) == "恒信事务所", "读档恢复事务所")
	check(not reloaded.professional_panel_data().is_empty(), "专业服务面板数据非空")


func _test_life_services_runtime() -> void:
	var state = GameStateScript.new()
	state.new_game(231)
	var host = SimHostScript.new(state, 231)
	host.bind(state)
	check(host.life_service_categories_catalog().size() >= 8, "服务类别≥8")
	check(host.life_pet_service_catalog().size() >= 5, "宠物服务链≥5")
	check(bool(host.life_new_provider("王阿姨", "housekeeping").get("ok", false)), "登记服务者")
	check(not host._life_provider.is_empty(), "服务者非空")
	check(bool(host.life_new_provider("甲", "nope").get("reason", "") == "unknown_category"), "未知类别被拒")
	check(bool(host.life_background_check().has("flagged")), "背景核查")
	check(bool(host.life_new_order("housekeeping", 2000).get("ok", false)), "预约服务")
	check(int(host.regions.get_region(host.current_region_id()).snapshot.get("life_orders", 0)) > 0, "生活服务订单回写区域统计")
	check(not host._life_order.is_empty(), "服务单非空")
	check(bool(host.life_housekeeping().get("ok", false)), "家政服务")
	host.economy.add_money(host.account_id(), 500000, "test")
	host.player()["family"] = {"spouse_id": "npc.spouse"}
	var wedding: Dictionary = host.life_wedding(50000, 0.6)
	check(bool(wedding.get("ok", false)), "婚礼策划")
	check(String(wedding.get("spouse_id", "")) == "npc.spouse", "婚礼关联配偶")
	check(host.player()["family"].has("wedding"), "婚礼记录写入家庭档案")
	check(float(host.relations.ensure_relation(host.player(), "npc.spouse").get("intimacy", 0.0)) > 0.0, "婚礼提升配偶亲密度")
	check(bool(host.life_matchmaking().get("ok", false)), "相亲婚介")
	host.economy.add_money(host.account_id(), 500000, "test")
	check(bool(host.adopt_pet("dog", "旺财").get("ok", false)), "领养宠物供服务")
	var pet_mood_before: float = float((host.pets()[0] as Dictionary).get("mood", 0.0))
	host._life_order["service"] = "boarding"
	var pet_svc: Dictionary = host.life_pet_service("boarding")
	check(bool(pet_svc.get("ok", false)), "宠物服务")
	check(String(pet_svc.get("pet_name", "")) == "旺财", "宠物服务绑定实际宠物")
	check(float((host.pets()[0] as Dictionary).get("mood", 0.0)) >= pet_mood_before, "寄养改善宠物情绪")
	check(bool(host.life_pet_service("nope").get("reason", "") == "unknown_pet_stage"), "未知宠物环节被拒")
	check(bool(host.life_incident(0.5).has("occurred")), "服务事故结算")
	check(bool(host.life_resolve_dispute(10000, 0.5).get("ok", false)), "纠纷处理")
	check(bool(host.life_commission(10000).has("commission")), "平台抽成")
	check(bool(host.life_standardize(100000, 0.5).get("ok", false)), "服务标准化")
	host._persist_life_services()
	check(state.sim_runtime.get("life_services", null) is Dictionary, "生活服务运行态写入 sim_runtime")
	var reloaded = SimHostScript.new(state, 231)
	reloaded.bind(state)
	check(String(reloaded._life_provider.get("name", "")) == "王阿姨", "读档恢复服务者")
	check(not reloaded.life_services_panel_data().is_empty(), "生活服务面板数据非空")


func _test_social_runtime() -> void:
	var state = GameStateScript.new()
	state.new_game(251)
	var host = SimHostScript.new(state, 251)
	host.bind(state)
	check(host.social_platforms_catalog().size() >= 8, "社交平台≥8")
	var platforms: Dictionary = host.social_followers()
	check(platforms.has("short_video"), "关注表含短视频平台")
	var pub: Dictionary = host.social_publish("short_video", "今天记录生活。", 0.2, false)
	check(bool(pub.get("ok", false)), "发布动态")
	check(int(host.social_feed(5).size()) == 1, "动态流含新动态")
	check(int(host.social_followers().get("short_video", 0)) != 0, "关注数随动态变化")
	check(bool(host.social_publish("nope").get("reason", "") == "unknown_platform"), "未知平台被拒")
	host._persist_social()
	check(state.sim_runtime.get("social_network", null) is Dictionary, "社交运行态写入 sim_runtime")
	var reloaded = SimHostScript.new(state, 251)
	reloaded.bind(state)
	check(reloaded.social_feed(5).size() == 1, "读档恢复动态")
	check(not reloaded.social_panel_data().is_empty(), "社交面板数据非空")


func _test_transport_infra_runtime() -> void:
	var state = GameStateScript.new()
	state.new_game(241)
	var host = SimHostScript.new(state, 241)
	host.bind(state)
	check(host.tin_infra_types_catalog().size() >= 7, "基建类型≥7")
	check(host.tin_modes_catalog().size() >= 3, "运营模式≥3")
	check(bool(host.tin_new_project("highway", 1.0).get("ok", false)), "基建立项")
	check(not host._tin_project.is_empty(), "基建项目非空")
	check(bool(host.tin_new_project("railway", 1.0).get("ok", false)), "铁路立项")
	check(bool(host.tin_tender().has("winner")), "基建招标定标")
	check(bool(host.tin_build(0.5).get("ok", false)), "基建推进")
	check(bool(host.tin_operate("logistics", 50.0).get("ok", false)), "线路运营")
	check(not host._tin_route.is_empty(), "运营线路非空")
	check(bool(host.tin_operate("nope").get("reason", "") == "unknown_tin_mode"), "未知模式被拒")
	var pop_before: int = int(host.regions.get_region(host.current_region_id()).population)
	var impact: Dictionary = host.tin_regional_impact()
	check(bool(impact.has("population_delta")), "区域影响")
	check(int(host.regions.get_region(host.current_region_id()).population) >= pop_before, "区域影响回写人口")
	check(float(host.regions.get_region(host.current_region_id()).snapshot.get("accessibility", 0.0)) > 0.5, "可达性写入区域快照")
	host.eng_new_city("测试城", 500000)
	host._eng_city["traffic"] = 0.8
	host.tin_regional_impact()
	check(float(host._eng_city.get("traffic", 1.0)) < 0.8, "交通运力缓解城市规划拥堵")
	check(bool(host.tin_network().has("connectivity")), "路网效应")
	check(bool(host.tin_subsidy(-1).has("granted")), "线路补贴")
	check(bool(host.tin_settle().has("construction_days")), "基建结算")
	check(bool(host.tin_accident(0.5).has("occurred")), "基建事故结算")
	check(bool(host.tin_monopoly(0.8, 100.0).get("action", "") == "price_cap"), "定价监管触发")
	check(bool(host.tin_disruption(0.5).has("disrupted")), "国际扰动结算")
	host._persist_transport_infra()
	check(state.sim_runtime.get("transport_infra", null) is Dictionary, "交通基建运行态写入 sim_runtime")
	var reloaded = SimHostScript.new(state, 241)
	reloaded.bind(state)
	check(String(reloaded._tin_project.get("type", "")) == "railway", "读档恢复基建项目")
	check(not reloaded.tin_panel_data().is_empty(), "交通基建面板数据非空")




