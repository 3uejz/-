extends "res://tests/test_base.gd"
## WorldClock / SpeedController / TickScheduler 测试（任务 2.1）。

const ClockScript = preload("res://autoload/world_clock.gd")
const TickScript = preload("res://autoload/tick_scheduler.gd")
const SpeedScript = preload("res://autoload/speed_controller.gd")

class Counter:
	extends RefCounted
	var minute: int = 0
	var hour: int = 0
	var day: int = 0
	var season: int = 0
	var year: int = 0

	func on_minute(_t: int) -> void:
		minute += 1

	func on_hour(_t: int) -> void:
		hour += 1

	func on_day(_t: int) -> void:
		day += 1

	func on_season(_t: int) -> void:
		season += 1

	func on_year(_t: int) -> void:
		year += 1

func _suite_name() -> String:
	return "world_clock"

func run_tests() -> void:
	_test_monotonic()
	_test_gregorian_boundaries()
	_test_day_phase()
	_test_speed_mapping()
	_test_tick_boundaries()

func _test_monotonic() -> void:
	var clock := ClockScript.new()
	var last: int = clock.total_minutes
	for step in [1, 59, 60, 1439, 1440, 525600]:
		clock.advance(step)
		check(clock.total_minutes > last, "总分钟单调递增（+%d）" % step)
		last = clock.total_minutes
		check_eq(clock.calendar()["date"], Gregorian.from_absolute_minutes(clock.total_minutes)["date"], "日历与总分钟一致")
	clock.free()

func _test_gregorian_boundaries() -> void:
	# 2000 为闰年：2000-02-29 存在；2001 非闰年：2001-02-28 之后是 03-01。
	check_eq(Gregorian.from_absolute_minutes(84960)["date"], "2000-02-29", "闰日 2000-02-29")
	check_eq(Gregorian.from_absolute_minutes(86400)["date"], "2000-03-01", "闰年后 2000-03-01")
	check_eq(Gregorian.from_absolute_minutes(610560)["date"], "2001-02-28", "平年 2001-02-28")
	check_eq(Gregorian.from_absolute_minutes(612000)["date"], "2001-03-01", "平年 2001-03-01")
	check_eq(Gregorian.from_absolute_minutes(0)["weekday_iso"], 6, "2000-01-01 为周六")

func _test_day_phase() -> void:
	var clock := ClockScript.new()
	var phases := {
		0: "night",
		299: "night",
		300: "dawn",
		479: "dawn",
		480: "day",
		1079: "day",
		1080: "dusk",
		1259: "dusk",
		1260: "night",
		1439: "night",
	}
	for minute in phases.keys():
		clock.set_minutes(minute)
		check_eq(clock.day_phase(), phases[minute], "day_phase @%d" % minute)
	clock.free()

func _test_speed_mapping() -> void:
	var sc := SpeedScript.new()
	sc.set_speed(1)
	check_near(sc.minutes_per_real_second(), 1.0 / 60.0, 1e-9, "1x 映射")
	sc.set_speed(60)
	check_near(sc.minutes_per_real_second(), 1.0, 1e-9, "60x 映射")
	sc.set_speed(3600)
	check_near(sc.minutes_per_real_second(), 60.0, 1e-9, "3600x 映射")
	sc.set_speed(86400)
	check_near(sc.minutes_per_real_second(), 1440.0, 1e-9, "86400x 映射")

	sc.set_speed(0)
	check_near(sc.advance(10.0), 0.0, 1e-9, "暂停不推进")
	sc.set_speed(60)
	check_near(sc.advance(2.0), 2.0, 1e-9, "60x 推进 2 秒 = 2 分钟")

	sc.fast_forward_to(100000)
	check(sc.get_speed() >= 60, "快进进入快进档")
	check_eq(sc.target_minutes(), 100000, "快进目标")

	sc.set_interruptible(false)
	sc.interrupt("crisis")
	check(not sc.is_paused(), "不可中断时保持运行")
	sc.set_interruptible(true)
	sc.interrupt("crisis")
	check(sc.is_paused(), "可中断时暂停")
	check_eq(sc.target_minutes(), -1, "中断清除快进目标")
	sc.free()

func _test_tick_boundaries() -> void:
	var clock := ClockScript.new()
	# 小时/日/季节/年：不注册分钟层，验证逐边界派发。
	var coarse := TickScript.new()
	var cc := Counter.new()
	coarse.register(cc, &"on_hour", TickScript.Tier.HOUR)
	coarse.register(cc, &"on_day", TickScript.Tier.DAY)
	coarse.register(cc, &"on_season", TickScript.Tier.SEASON)
	coarse.register(cc, &"on_year", TickScript.Tier.YEAR)
	coarse.tick(0)  # 播种
	coarse.tick(60)
	check_eq(cc.hour, 1, "跨 1 小时")
	coarse.tick(1440, 1000000)
	check_eq(cc.day, 1, "跨 1 日")
	coarse.tick(527040, 1000000)  # 至 2001-01-01
	check_eq(cc.day, 366, "2000 闰年共 366 日")
	check_eq(cc.season, 4, "跨 4 个季节边界")
	check_eq(cc.year, 1, "跨 1 个年边界")
	coarse.free()

	# 分钟层：逐分钟派发。
	var fine := TickScript.new()
	var fc := Counter.new()
	fine.register(fc, &"on_minute", TickScript.Tier.MINUTE)
	fine.tick(0)
	fine.tick(60)
	check_eq(fc.minute, 60, "逐分钟派发 60 次")
	fine.free()

	# 单帧上限：一次 tick 最多推进 cap 分钟。
	var capped := TickScript.new()
	var cp := Counter.new()
	capped.register(cp, &"on_minute", TickScript.Tier.MINUTE)
	capped.tick(0)
	var advanced: int = capped.tick(100, 10)
	check_eq(advanced, 10, "单帧上限生效")
	capped.free()

	clock.free()
