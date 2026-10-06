extends "res://tests/test_base.gd"
## 宏观/微观权威边界测试（R37/OI-2，任务 24.4）：
## 离线用同一确定性模型从 server_tick 锚点近似推进；上线后全球宏观以服务端为准。

func _suite_name() -> String:
	return "macro"

func run_tests() -> void:
	_test_offline_advance_from_anchor()
	_test_server_merge_overrides_global()
	_test_population_monotonic()

func _test_offline_advance_from_anchor() -> void:
	var m := MacroSimulator.new(99, 1000000)
	m.set_server_anchor(0)
	var ticks: int = m.advance_to(int(round(MacroSimulator.MINUTES_PER_QUARTER)) * 3)
	check_eq(ticks, 3, "离线应从锚点推进 3 个季度")
	check_eq(m.absolute_minute, int(round(MacroSimulator.MINUTES_PER_QUARTER)) * 3, "绝对分钟应与推进一致")
	check_eq(m.server_tick, 0, "server_tick 锚点应保持为服务端下发值")

func _test_server_merge_overrides_global() -> void:
	var m := MacroSimulator.new(1, 1000000)
	m.tick()
	m.tick()
	var before_version: int = m.version
	var server := {
		"population": 2000000,
		"inflation_rate": 0.5,
		"unemployment_rate": 0.2,
		"gdp_est": 123.0,
		"absolute_minutes": 525960,
	}
	var merged: Dictionary = m.merge_from_server(server)
	check_eq(int(merged["population"]), 2000000, "全球人口应以服务端为准")
	check_near(m.inflation, 0.5, 1e-12, "通胀应以服务端为准")
	check_near(m.unemployment, 0.2, 1e-12, "失业率应以服务端为准")
	check_eq(m.server_tick, 525960, "应记录服务端 tick 锚点")
	check_eq(m.absolute_minute, 525960, "本地宏观时钟应对齐服务端锚点")
	check_eq(m.version, before_version + 1, "合并后版本应递增")

func _test_population_monotonic() -> void:
	var m := MacroSimulator.new(7, 500000)
	var prev: int = m.population
	for i in 4:
		m.tick()
		check(m.population >= prev, "低死亡高出生下人口应不下降")
		prev = m.population
