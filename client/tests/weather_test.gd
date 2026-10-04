extends "res://tests/test_base.gd"
## 天气生态与时代演化测试（任务 9；对应 R2、R41）。
## 覆盖：气象变量有界、同种子可复现、预报与实况一致且准确率单调、灾害低频且有预警、
##       时代推进与内容 era_min/era_max 闭区间过滤。

const WeatherScript = preload("res://sim/weather.gd")
const EraScript = preload("res://sim/era.gd")
const BaselineScript = preload("res://sim/baseline.gd")

func _suite_name() -> String:
	return "weather"

func run_tests() -> void:
	BaselineScript.clear_overrides()
	_test_catalog_sizes()
	_test_variables_bounded()
	_test_same_seed_reproducible()
	_test_forecast()
	_test_disasters_low_frequency()
	_test_era_progression()
	_test_era_content_gate()
	_test_remote_override()
	BaselineScript.clear_overrides()


func _make_weather(seed: int = 20261004):
	return WeatherScript.new(seed)


## 气候带 10 类、天气状态 20 类、灾害 10 类、时代 9 阶段。
func _test_catalog_sizes() -> void:
	check_eq(BaselineScript.CLIMATE_ZONE_ORDER.size(), 10, "气候带 10 类")
	check_eq(BaselineScript.WEATHER_STATE_ORDER.size(), 20, "天气状态 20 类")
	check_eq(BaselineScript.WEATHER_DISASTER_ORDER.size(), 10, "灾害 10 类")
	check_eq(BaselineScript.ERA_DEFINITIONS.size(), 9, "时代 9 阶段")


## 各气候带跨季节气象变量均落在 design D1 区间内，且天气状态合法。
func _test_variables_bounded() -> void:
	var ws = _make_weather()
	for zone in BaselineScript.CLIMATE_ZONE_ORDER:
		var rid: String = "r_" + zone
		ws.register_region(rid, zone)
		for day in range(0, 730, 6):
			var st = ws.state_at(rid, day * WeatherScript.MINUTES_PER_DAY + 360)
			check(BaselineScript.WEATHER_STATE_ORDER.has(st.condition), "%s 天气状态合法" % zone)
			check(st.temperature_c >= BaselineScript.WEATHER_TEMP_MIN and st.temperature_c <= BaselineScript.WEATHER_TEMP_MAX, "%s 气温有界" % zone)
			check(st.humidity_pct >= 0.0 and st.humidity_pct <= 100.0, "%s 湿度有界" % zone)
			check(st.pressure_hpa >= BaselineScript.WEATHER_PRESSURE_MIN and st.pressure_hpa <= BaselineScript.WEATHER_PRESSURE_MAX, "%s 气压有界" % zone)
			check(st.wind_ms >= 0.0 and st.wind_ms <= BaselineScript.WEATHER_WIND_MAX, "%s 风速有界" % zone)
			check(st.visibility_km >= 0.0 and st.visibility_km <= BaselineScript.WEATHER_VISIBILITY_MAX, "%s 能见度有界" % zone)
			check(st.precipitation_mm >= 0.0 and st.precipitation_mm <= BaselineScript.WEATHER_PRECIP_MAX, "%s 降水有界" % zone)


## 同种子逐日演化完全一致；不同种子产生差异。
func _test_same_seed_reproducible() -> void:
	var a = _make_weather(4242)
	var b = _make_weather(4242)
	var c = _make_weather(4343)
	for zone in ["tropical_rainforest", "tropical_desert", "subarctic_conifer"]:
		a.register_region(zone, zone)
		b.register_region(zone, zone)
		c.register_region(zone, zone)
	var any_diff: bool = false
	for day in range(0, 400, 3):
		for zone in ["tropical_rainforest", "tropical_desert", "subarctic_conifer"]:
			check_eq(a.condition_for_day(zone, day), b.condition_for_day(zone, day), "同种子天气一致 %s d%d" % [zone, day])
			if a.condition_for_day(zone, day) != c.condition_for_day(zone, day):
				any_diff = true
	check(any_diff, "不同种子产生差异")
	check_eq(a.state_at("tropical_desert", 12345).to_dict(), b.state_at("tropical_desert", 12345).to_dict(), "同种子气象快照一致")


## 预报天数、准确率单调、与实况一致。
func _test_forecast() -> void:
	var ws = _make_weather(777)
	var rid: String = "forecast_city"
	ws.register_region(rid, "temperate_continental")
	var from_day: int = 1200
	var from_minute: int = from_day * WeatherScript.MINUTES_PER_DAY

	var info = ws.forecast(rid, from_minute, 6)
	check_eq(info.size(), BaselineScript.WEATHER_FORECAST_DAYS, "预报 7 日")
	check_eq(info[0]["condition"], ws.condition_for_day(rid, from_day), "当日预报等于实况")
	check_near(float(info[0]["accuracy"]), 1.0, 1e-9, "当日准确率为 1")
	for i in range(1, info.size()):
		check(float(info[i]["accuracy"]) < float(info[i - 1]["accuracy"]), "准确率随预报天数下降")
		check(float(info[i]["accuracy"]) > 0.0, "准确率大于 0")

	# 时代越高预报越准（同一 lead 对比）。
	var stone = ws.forecast(rid, from_minute, 0)
	var interstellar = ws.forecast(rid, from_minute, 8)
	check(float(interstellar[3]["accuracy"]) > float(stone[3]["accuracy"]), "时代越高预报越准")
	# 同种子同输入预报可复现。
	check_eq(ws.forecast(rid, from_minute, 6), ws.forecast(rid, from_minute, 6), "预报可复现")

	# 高准确率时代下，第 1 日预报与实况的吻合率接近其准确率。
	var match_count: int = 0
	var samples: int = 300
	for k in range(samples):
		var d: int = 5000 + k * 13
		var f = ws.forecast(rid, d * WeatherScript.MINUTES_PER_DAY, 8)
		if f[1]["condition"] == ws.condition_for_day(rid, d + 1):
			match_count += 1
	var ratio: float = float(match_count) / float(samples)
	check(ratio >= 0.9, "星际时代第 1 日预报吻合率 ≥ 0.9，实际 %.3f" % ratio)


## 灾害低频偶发，且触发前 1–3 日给出预警。
func _test_disasters_low_frequency() -> void:
	var ws = _make_weather(20261004)
	var rid: String = "disaster_city"
	ws.register_region(rid, "tropical_monsoon")
	var years: int = 120
	var total_days: int = int(years * BaselineScript.WEATHER_DAYS_PER_YEAR)
	var total_events: int = 0
	var first_event: Dictionary = {}
	for day in range(total_days):
		var events: Array = ws.disasters_on(rid, day)
		if events.size() > 0:
			total_events += events.size()
			if first_event.is_empty():
				first_event = events[0]
	var annual: float = float(total_events) / float(years)
	check(total_events > 0, "长期存在灾害触发")
	check(annual < 0.5, "灾害低频（年均 %.3f < 0.5）" % annual)

	# 灾害日为极少数：有灾害的天数远少于总天数。
	check(total_events < total_days / 10, "灾害仅占少数天数")

	if not first_event.is_empty():
		var event_day: int = int(first_event["day"])
		var key: String = str(first_event["key"])
		var warns: Array = ws.disaster_warnings(rid, event_day - 1)
		var found: bool = false
		for w in warns:
			if str(w["key"]) == key and int(w["event_day"]) == event_day:
				found = true
				check(int(w["days_until"]) >= 1 and int(w["days_until"]) <= 3, "预警提前 1–3 日")
		check(found, "触发前 1–3 日存在预警")
		# 超出最大预警窗口的日期不应包含该事件预警。
		var too_early: Array = ws.disaster_warnings(rid, event_day - 4)
		var leaked: bool = false
		for w in too_early:
			if str(w["key"]) == key and int(w["event_day"]) == event_day:
				leaked = true
		check(not leaked, "超出预警窗口不发布")


## 时代按时间线推进、加速不倒退、宣告入消息流。
func _test_era_progression() -> void:
	var era = EraScript.new(-10000)
	check_eq(era.current_index(), 0, "远古起点为石器")
	check_eq(EraScript.era_index_for_year(1700), 4, "1700 进入工业（闭下界）")
	check_eq(EraScript.era_index_for_year(1699), 3, "1699 仍为中世纪")
	check_eq(EraScript.era_index_for_year(-800), 2, "古典起始年闭下界")

	var e2 = EraScript.new(1700)
	check_eq(e2.current_index(), 4, "起点工业")
	var r = e2.advance_to_year(1975)
	check(r["changed"], "时代推进有变化")
	check_eq(e2.current_index(), 6, "1975 进入信息")
	check(e2.announcements().size() >= 1, "时代变化写入宣告")

	e2.accelerate("可控核聚变突破")
	check_eq(e2.current_index(), 7, "加速推进到智能")
	var before: int = e2.current_index()
	e2.advance_to_year(1000)
	check_eq(e2.current_index(), before, "加速后不因时间回溯而倒退")
	check(e2.drain_announcements().size() >= 1, "宣告可消费")

	# 加速下限与解锁标签。
	check(e2.unlocked_tags().size() >= 1, "时代解锁标签非空")
	check(e2.unlocked_tags(8).has("spacefaring"), "星际解锁星际标签")


## 内容 era_min/era_max 门闩为闭区间，缺省无界，min>max 恒不可用。
func _test_era_content_gate() -> void:
	var era = EraScript.new(0)
	var always := {"id": "a"}
	var bounded := {"id": "b", "era_min": 2, "era_max": 4}
	var open_upper := {"id": "c", "era_min": 2}
	var open_lower := {"id": "d", "era_max": 2}
	var by_key := {"id": "e", "era_min": "industrial", "era_max": "electric"}
	var invalid := {"id": "f", "era_min": 5, "era_max": 3}

	# 闭区间：era_min 与 era_max 两端均可取。
	check(era.is_content_available(bounded, 2), "era_min 边界闭（可取）")
	check(era.is_content_available(bounded, 4), "era_max 边界闭（可取）")
	check(not era.is_content_available(bounded, 1), "低于 era_min 不可用")
	check(not era.is_content_available(bounded, 5), "高于 era_max 不可用")

	# 缺省一端为无界。
	check(era.is_content_available(open_upper, 8), "缺省 era_max 无上界")
	check(not era.is_content_available(open_upper, 1), "era_min 仍生效")
	check(era.is_content_available(open_lower, 0), "缺省 era_min 无下界")
	check(not era.is_content_available(open_lower, 3), "era_max 仍生效")
	for i in range(BaselineScript.ERA_COUNT):
		check(era.is_content_available(always, i), "无门闩内容全时代可用")

	# 字符串时代键：工业=4、电气=5，闭区间 [4,5]。
	check(era.is_content_available(by_key, 4), "字符串 era_min 边界")
	check(era.is_content_available(by_key, 5), "字符串 era_max 边界")
	check(not era.is_content_available(by_key, 3), "字符串键下界生效")
	check(not era.is_content_available(by_key, 6), "字符串键上界生效")

	# min > max 恒不可用。
	for i in range(BaselineScript.ERA_COUNT):
		check(not era.is_content_available(invalid, i), "min>max 恒不可用")

	var items: Array = [always, bounded, open_upper, open_lower, by_key, invalid]
	check_eq(era.filter_items(items, 2).size(), 4, "时代 2 过滤结果数")
	check_eq(era.outdated_items(items, 2).size(), 2, "时代 2 被淘汰结果数")


## 远程配置可覆盖气候带、天气状态与时代定义。
func _test_remote_override() -> void:
	BaselineScript.apply_remote_config({
		"climate_zone.polar_highland.base_temp": -40.0,
		"weather_state.gale.wind_mod": 30.0,
		"era.stone.forecast_accuracy": 0.5,
	})
	var zone: Dictionary = BaselineScript.effective_zone("polar_highland")
	check_near(float(zone["base_temp"]), -40.0, 1e-9, "气候带可远程覆盖")
	var st: Dictionary = BaselineScript.effective_weather_state("gale")
	check_near(float(st["wind_mod"]), 30.0, 1e-9, "天气状态可远程覆盖")
	var era_def: Dictionary = BaselineScript.effective_era(0)
	check_near(float(era_def["forecast_accuracy"]), 0.5, 1e-9, "时代定义可远程覆盖")
	BaselineScript.clear_overrides()
	check_near(float(BaselineScript.effective_zone("polar_highland")["base_temp"]), -20.0, 1e-9, "清除覆盖恢复默认")
