extends "res://tests/test_base.gd"
## 玩法接线端到端测试（任务 3/4/23）：真实主壳 + GameState + 指令 → 状态变化。
## 在无 Autoload 的 --script 环境中，手动把 GameState / WorldClock 挂到 root。

const GameStateScript = preload("res://autoload/game_state.gd")
const WorldClockScript = preload("res://autoload/world_clock.gd")
const SaveManagerScript = preload("res://sim/save_manager.gd")

var _main
var _game
var _ran := false

func _suite_name() -> String:
	return "gameplay_wiring"

func _initialize() -> void:
	print("[test] %s" % _suite_name())
	# --script 环境下 Autoload 可能缺失；有则复用，无则手动挂载。
	_game = root.get_node_or_null("GameState")
	if _game == null:
		_game = GameStateScript.new()
		_game.name = "GameState"
		root.add_child(_game)
	_game.new_game(11)
	if root.get_node_or_null("WorldClock") == null:
		var clock = WorldClockScript.new()
		clock.name = "WorldClock"
		root.add_child(clock)
	var packed = load("res://ui/main.tscn")
	if packed == null:
		_fail("main.tscn 无法加载")
		quit(failures)
		return
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
	_test_wait_advances_state_clock()
	_test_panel_command_opens_panel()
	_test_map_panel_mounts_view()
	_test_buy_changes_inventory()
	_test_statusbar_weather()
	_test_marry_command()
	_test_property_commands()
	_test_family_commands()
	_test_save_writes_file()

func _test_wait_advances_state_clock() -> void:
	_main.submit("等待 2 小时")
	check_eq(int(_game.clock.get("absolute_minutes", 0)), 120, "等待后游戏时钟推进 120 分钟")

func _test_panel_command_opens_panel() -> void:
	_main.submit("看自己")
	check(_main.has_panel("character"), "「看自己」打开角色面板")

func _test_map_panel_mounts_view() -> void:
	_main.submit("看地图")
	check(_main.has_panel("map"), "「看地图」打开地图面板")
	var drawer = _main.get_node_or_null("Root/Drawers/Drawer_map")
	check(drawer != null, "地图抽屉已创建")

func _test_buy_changes_inventory() -> void:
	_main.submit("买 苹果 2")
	var inv: Array = _game.player.get("inventory", [])
	var count := 0
	for inst in inv:
		if typeof(inst) == TYPE_DICTIONARY and String(inst.get("def_id", "")) == "item.apple":
			count += int(inst.get("quantity", 0))
	check_eq(count, 2, "「买 苹果 2」入包 2 个")

func _test_statusbar_weather() -> void:
	_main.submit("看天气")
	var label = _main.get_node_or_null("Root/StatusBar/WeatherLabel")
	check(label != null, "状态栏含天气标签")
	if label != null:
		check(label.text.begins_with("天气：") and label.text != "天气：--", "状态栏天气已由世界运行时填充")

func _test_marry_command() -> void:
	var sim = _main._sim
	var npc: Dictionary = sim.acquaintances()[0]
	var pid := String(npc.get("id", ""))
	var name := String(npc.get("name", ""))
	var rel: Dictionary = sim.relations.ensure_relation(_game.player, pid)
	rel["favor"] = 90.0
	rel["intimacy"] = 80.0
	_main.submit("求婚 " + name)
	check_eq(String(_game.player.get("family", {}).get("spouse_id", "")), pid, "「求婚 <人名>」经解析器链接并写入配偶")

func _test_property_commands() -> void:
	var sim = _main._sim
	sim.economy.add_money(sim.account_id(), 1000000000, "test")
	_main.submit("看房")
	var listings: Array = sim.property_listings()
	check(not listings.is_empty(), "存在在售房源")
	if listings.is_empty():
		return
	var pid := String(listings[0].get("id", ""))
	var name := String(listings[0].get("name", ""))
	_main.submit("买房 " + name)
	var owned := false
	for p in sim.property_owned():
		if String(p.get("id", "")) == pid:
			owned = true
	check(owned, "「买房 <房源>」经解析器链接并计入名下资产")

func _test_family_commands() -> void:
	var sim = _main._sim
	var npc: Dictionary = sim.acquaintances()[0]
	sim.marry_with(String(npc.get("id", "")))
	_main.submit("怀孕")
	check(sim.is_pregnant(), "「怀孕」进入妊娠状态")
	_main.submit("立遗嘱")
	check(not (_game.player.get("will", {}) as Dictionary).is_empty(), "「立遗嘱」写入遗嘱")

func _test_save_writes_file() -> void:
	_main.submit("存档")
	var mgr = SaveManagerScript.new("user://saves")
	check(mgr.exists("1"), "「存档」写入槽位 1")
	_main.free()
