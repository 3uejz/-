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

