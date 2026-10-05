extends "res://tests/test_base.gd"
## 世界记忆测试（任务 22；R29/R31；design「世界记忆与家族史」）。

const WMScript = preload("res://sim/world_memory.gd")

const HALF_LIFE_80: float = 30.0 * (1.0 + 80.0 / 20.0)


func _suite_name() -> String:
	return "world_memory"


func run_tests() -> void:
	_test_catalog()
	_test_decay()
	_test_reference_attitude()
	_test_fade()


func _test_catalog() -> void:
	var sys = WMScript.new()
	check_eq(sys.carriers().size(), 4, "四类载体")
	var store: Dictionary = sys.new_store()
	check_eq((store["memories"] as Array).size(), 0, "初始空")
	var r: Dictionary = sys.add_memory(store, "legend", "创立公司", 80.0, 0, ["family_a"])
	check(bool(r["ok"]), "生成传说事件")
	check(not bool(sys.add_memory(store, "bogus", "x", 10.0, 0)["ok"]), "未知载体")


func _test_decay() -> void:
	var sys = WMScript.new()
	var store: Dictionary = sys.new_store()
	sys.add_memory(store, "legend", "创立公司", 80.0, 0, ["family_a"])
	var mem: Dictionary = store["memories"][0]
	check_near(sys.current_weight(mem, 0), 80.0, 0.001, "初始权重")
	var at_half: int = int(HALF_LIFE_80 * 1440.0)
	check_near(sys.current_weight(mem, at_half), 40.0, 0.01, "半衰期衰减一半")


func _test_reference_attitude() -> void:
	var sys = WMScript.new()
	var store: Dictionary = sys.new_store()
	sys.add_memory(store, "legend", "创立公司", 80.0, 0, ["family_a"])
	var mem: Dictionary = store["memories"][0]
	var at_half: int = int(HALF_LIFE_80 * 1440.0)
	var before: float = sys.current_weight(mem, at_half)
	sys.cite_memory(store, str(mem["id"]))
	var after: float = sys.current_weight(mem, at_half)
	check(after > before, "被引用减缓衰减")
	check(float(sys.attitude_modifier(store, "family_a", 0)) > 0.0, "影响后代态度")
	check_eq(sys.top_memories(store, 0, 10).size(), 1, "家族史检索")


func _test_fade() -> void:
	var sys = WMScript.new()
	var store: Dictionary = sys.new_store()
	sys.add_memory(store, "hidden", "小道消息", 5.0, 0, [])
	var far: int = int(5000.0 * 1440.0)
	var t: Dictionary = sys.tick(store, far)
	check(int(t["faded"]) >= 1, "低重大度记忆淡出")
	check_eq((store["memories"] as Array).size(), 0, "淡出后清除")
