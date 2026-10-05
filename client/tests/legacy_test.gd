extends "res://tests/test_base.gd"
## 传承轮回测试（任务 22；R31；design「死亡、传承与轮回」）。

const LegacyScript = preload("res://sim/legacy.gd")
const WMScript = preload("res://sim/world_memory.gd")


func _suite_name() -> String:
	return "legacy"


func run_tests() -> void:
	_test_settle()
	_test_carry()
	_test_serialize()


func _test_settle() -> void:
	var sys = LegacyScript.new()
	var legacy: Dictionary = sys.new_legacy()
	check_eq(int(legacy["generation"]), 1, "初代")
	var wm = WMScript.new()
	var store: Dictionary = wm.new_store()
	wm.add_memory(store, "legend", "创立公司", 80.0, 0, ["family_a"])
	var run: Dictionary = {"skills": {"driving": 10, "cooking": 7}, "talents": ["artistic"], "assets": 1000000, "relations": ["npc1"], "world_memory": store}
	var death: Dictionary = {"name": "老王", "age": 80, "cause": "illness", "minute": 0}
	var r: Dictionary = sys.settle(death, run, legacy)
	check(bool(r["ok"]), "结算成功")
	check_eq(int(r["generation"]), 2, "进入第二代")
	check_eq(int((legacy["skills"] as Dictionary)["driving"]), 5, "技能记忆折半")
	check_near(float(legacy["bloodline"]), 0.05, 0.0001, "血脉累积")
	check((legacy["talents"] as Array).has("artistic"), "天赋血脉")
	check_eq(int(legacy["assets"]), 300000, "资产流动部分继承")
	check((legacy["relations"] as Array).has("npc1"), "人脉继承")
	check_eq((legacy["records"] as Array).size(), 1, "家族史记录")
	check_eq((legacy["world_memory"]["memories"] as Array).size(), 1, "世界记忆延续")


func _test_carry() -> void:
	var sys = LegacyScript.new()
	var legacy: Dictionary = sys.new_legacy()
	sys.settle({"name": "老王", "age": 80, "cause": "illness", "minute": 0}, {"skills": {"driving": 10}, "talents": ["artistic", "strong"], "assets": 1000000, "relations": [], "world_memory": WMScript.new().new_store()}, legacy)
	check_near(sys.family_bonus(legacy), 1.05, 0.0001, "血脉加成")
	var carry: Dictionary = sys.new_game_carry(legacy, ["artistic"])
	check(bool(carry["ok"]), "携带传承开档")
	check_eq(int((carry["skills"] as Dictionary)["driving"]), 5, "起始技能记忆")
	var too_many: Dictionary = sys.new_game_carry(legacy, ["artistic", "strong", "artistic", "strong"])
	check_eq(str(too_many["reason"]), "too_many_talents", "天赋槽上限")
	var unknown: Dictionary = sys.new_game_carry(legacy, ["nonexistent"])
	check_eq(str(unknown["reason"]), "talent_not_inherited", "未继承天赋不可携带")


func _test_serialize() -> void:
	var sys = LegacyScript.new()
	var legacy: Dictionary = sys.new_legacy()
	sys.settle({"name": "老王", "age": 80, "cause": "illness", "minute": 0}, {"skills": {"driving": 10}, "talents": ["artistic"], "assets": 0, "relations": [], "world_memory": WMScript.new().new_store()}, legacy)
	var back: Dictionary = sys.from_dict(sys.to_dict(legacy))
	check_eq(int(back["generation"]), 2, "持久化周目")
	check((back["talents"] as Array).has("artistic"), "持久化天赋")
