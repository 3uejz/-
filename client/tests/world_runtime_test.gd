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

