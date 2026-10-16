extends "res://tests/test_base.gd"
## 世界运行时接线测试（R1/R5/R50、D1/D2）：
## 种子确定性地理、所在城市登记为活动区、区域随游戏内时钟演化、天气查询与展示。

const GameStateScript = preload("res://autoload/game_state.gd")
const SimHostScript = preload("res://sim/sim_host.gd")
const GeoDataScript = preload("res://sim/geo.gd")

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
	host.advance(1, {"fatal": true})
	check(host.is_dead(), "致命事件导致死亡")
	check(host.inheritance_settled(), "死亡触发继承结算")
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
	# 诉讼判定返回。
	var sue: Dictionary = host.sue_ip_infringer(ip_id, {"roll": 1.0})
	check(bool(sue.get("ok", false)), "维权诉讼返回判定")
	# 持久化并读档恢复。
	host._persist_ip_media()
	check(state.sim_runtime.get("ip_media", null) is Dictionary, "知识产权运行态写入 sim_runtime")
	var reloaded = SimHostScript.new(state, 88)
	reloaded.bind(state)
	check((reloaded.ip_media_state().get("ips", []) as Array).size() == 1, "读档恢复 IP")
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
	check(bool(host.restaurant_expand("single_shop").get("ok", false)), "扩张校验通过（单店）")
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
	var collab: Dictionary = host.fashion_collab(80.0)
	check(bool(collab.get("ok", false)) and int(collab.get("revenue", 0)) > 0, "联名取得收入")
	var auth: Dictionary = host.fashion_authenticate("handbag")
	check(bool(auth.get("ok", false)), "鉴定真伪成功")
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
	check(bool(host.events_sponsor("title").get("ok", false)), "招商成功")
	check(int(host.events_sell_tickets(5000).get("revenue", 0)) > 0, "售票取得收入")
	check(bool(host.events_set_security(0.8).get("ok", false)), "配置安保成功")
	var hold: Dictionary = host.events_hold()
	check(bool(hold.get("ok", false)) and int(hold.get("attendance", 0)) == 5000, "举办活动到场 5000")
	var rv: Dictionary = host.events_review()
	check(bool(rv.get("ok", false)), "活动复盘成功")
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
	check(bool(host.honors_inherit().get("ok", false)), "传承评价可计算")
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
	check(host.environment_careers_catalog().size() >= 4, "环保职业表含环保企业/NGO等")
	check(bool(host.env_set_garbage_sorting(0.8).get("ok", false)), "设定垃圾分类率")
	check(float(host.env_recycle(1000.0).get("recovered", 0.0)) > 0.0, "回收资源有产出")
	check(bool(host.env_treat_sewage(0.9).get("ok", false)), "设定污水处理率")
	check(bool(host.env_air_control(1000000).get("ok", false)), "空气治理完成")
	check(bool(host.env_issue_permit("factory", 200.0).get("ok", false)), "发放排污许可")
	var acct: Dictionary = host.env_carbon_account()
	check(bool(acct.get("ok", false)), "碳核算完成")
	check(bool(host.env_carbon_trade(-50.0).get("ok", false)), "碳交易完成")
	var comp: Dictionary = host.env_carbon_compliance("buy")
	check(bool(comp.get("ok", false)) and bool(comp.get("compliant", false)), "碳履约合规")
	check(bool(host.env_report_carbon(100.0).get("ok", false)), "碳申报完成")
	# 环保从业组织。
	check(bool(host.start_env_org("env_company").get("ok", false)), "开办环保企业成功")
	check(bool(host.start_env_org("env_ngo").get("reason", "") == "already_org"), "重复开办被拒")
	check(bool(host.env_run_project("污水厂", 1000000).get("ok", false)), "承接环保项目成功")
	check(bool(host.env_green_subsidy(100000).get("ok", false)), "申请绿色补贴完成")
	check(bool(host.env_low_carbon_transition(1000000).get("ok", false)), "低碳转型完成")
	check(bool(host.env_illegal_discharge(20.0).get("ok", false)), "偷排结算完成")
	check(bool(host.env_nimby(0.5).get("ok", false)), "邻避评估完成")
	# 污染与诉讼。
	check(bool(host.env_pollute(0.8).get("ok", false)), "污染事件结算")
	check(bool(host.env_expose_pollution().get("ok", false)), "污染曝光结算")
	check(bool(host.env_lawsuit().get("ok", false)), "环境诉讼完成")
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
	check(bool(host.municipal_government_purchase("park_maintenance", 800000).get("ok", false)), "政府购买服务完成")
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

