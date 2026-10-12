extends "res://tests/test_base.gd"
## 实时时间驱动测试（R1 / M0 挂机实时世界）：纯换算逻辑 + 主壳接线。

const TimeDriverScript = preload("res://sim/time_driver.gd")
const GameStateScript = preload("res://autoload/game_state.gd")
const WorldClockScript = preload("res://autoload/world_clock.gd")
const SpeedControllerScript = preload("res://autoload/speed_controller.gd")

var _main
var _game
var _speed
var _ran := false

func _suite_name() -> String:
	return "time_driver"

func _initialize() -> void:
	print("[test] %s" % _suite_name())
	_game = root.get_node_or_null("GameState")
	if _game == null:
		_game = GameStateScript.new()
		_game.name = "GameState"
		root.add_child(_game)
	_game.new_game(23)
	if root.get_node_or_null("WorldClock") == null:
		var clock = WorldClockScript.new()
		clock.name = "WorldClock"
		root.add_child(clock)
	_speed = root.get_node_or_null("SpeedController")
	if _speed == null:
		_speed = SpeedControllerScript.new()
		_speed.name = "SpeedController"
		root.add_child(_speed)
	var packed = load("res://ui/main.tscn")
	_main = packed.instantiate()
	root.add_child(_main)

func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	run_tests()
	if failures == 0:
		print("[test] %s PASS" % _suite_name())
	else:
		print("[test] %s FAILURES: %d" % [_suite_name(), failures])
	quit(failures)
	return true

func run_tests() -> void:
	_test_pure_accumulation()
	_test_scales()
	_test_batch_cap()
	_test_main_realtime_advance()
	_test_main_pause()

func _test_pure_accumulation() -> void:
	var d = TimeDriverScript.new()
	check_eq(d.consume(0, 60.0), 0, "暂停不推进")
	check_eq(d.consume(1, 59.0), 0, "不足一分钟不推进")
	check_near(d.carry(), 59.0 / 60.0, 1e-9, "余数累积")
	check_eq(d.consume(1, 1.0), 1, "满一分钟推进 1")
	check_near(d.carry(), 0.0, 1e-9, "余数清零")

func _test_scales() -> void:
	var d = TimeDriverScript.new()
	check_eq(d.consume(60, 1.0), 1, "60x：每现实秒 1 分钟")
	d.reset()
	check_eq(d.consume(3600, 1.0), 60, "3600x：每现实秒 60 分钟")
	d.reset()
	check_eq(d.consume(4, 1.0), 0, "4x：一秒不足一分钟")

func _test_batch_cap() -> void:
	var d = TimeDriverScript.new()
	check_eq(d.consume(86400, 2.0), 1440, "快进档单帧封顶 1 天")
	check(d.carry() > 0.0, "超出部分保留在余数中")

func _test_main_realtime_advance() -> void:
	_speed.set_speed(1)
	_main.set_auto_time(true)
	_main._time_driver.reset()
	var before: int = int(_game.clock.get("absolute_minutes", 0))
	_main._process(30.0)
	check_eq(int(_game.clock.get("absolute_minutes", 0)), before, "半分钟不足一分钟")
	_main._process(30.0)
	check_eq(int(_game.clock.get("absolute_minutes", 0)), before + 1, "满一分钟推进 1")

func _test_main_pause() -> void:
	_speed.set_speed(0)
	var before: int = int(_game.clock.get("absolute_minutes", 0))
	_main._process(120.0)
	check_eq(int(_game.clock.get("absolute_minutes", 0)), before, "暂停时不推进")
	_main.set_auto_time(false)
	_main.free()
