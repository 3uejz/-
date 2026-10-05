extends "res://tests/test_base.gd"
## NPC 记忆条目队列测试（任务 12；R50.5–R50.6；design D10）。
## 覆盖：添加/计数、上限淘汰、半衰期与新鲜度、按情境检索、
##       引用加固、时间衰减、冲突消解、死亡归档。

const MemScript = preload("res://sim/npc_memory.gd")

const YEAR_MIN: int = 525960  # 365.25 * 1440

func _suite_name() -> String:
	return "npc_memory"

func run_tests() -> void:
	_test_add_and_count()
	_test_prune_cap()
	_test_half_life_and_freshness()
	_test_retrieve()
	_test_reinforce()
	_test_decay()
	_test_resolve_conflict()
	_test_archive_on_death()
	_test_dialogue_citations()


func _test_add_and_count() -> void:
	var sys = MemScript.new()
	var npc := {}
	var m: Dictionary = sys.add_memory(npc, {
		"type": "shared_experience", "minute": 100, "subjects": ["npc.a"],
		"weight": 20.0, "severity": 30.0, "visibility": "public",
	})
	check_eq(sys.count(npc), 1, "添加一条")
	check_eq(str(m["type"]), "shared_experience", "类型")
	check_eq(m["subjects"].size(), 1, "涉及对象")
	check_eq(bool(m["archived"]), false, "默认未归档")


func _test_prune_cap() -> void:
	var sys = MemScript.new()
	var npc := {}
	for i in 60:
		sys.add_memory(npc, {"type": "favor", "minute": i, "weight": 10.0, "severity": 0.0})
	check_eq(sys.count(npc), MemScript.MAX_ENTRIES, "超出上限被裁剪至 50")


func _test_half_life_and_freshness() -> void:
	var sys = MemScript.new()
	check_near(sys.half_life_years(0.0), 1.0, 0.0001, "重大度 0 半衰期 1 年")
	check_near(sys.half_life_years(100.0), 10.0, 0.0001, "重大度 100 半衰期 10 年")
	check(sys.half_life_years(80.0) > sys.half_life_years(20.0), "越重大记得越久")

	var low := {"minute": 0, "severity": 0.0}
	var high := {"minute": 0, "severity": 100.0}
	check_near(sys.freshness(low, 5 * YEAR_MIN), pow(0.5, 5.0), 0.0001, "5 年后低重大度新鲜度")
	check_near(sys.freshness(high, 5 * YEAR_MIN), pow(0.5, 0.5), 0.0001, "5 年后高重大度新鲜度")
	check(sys.freshness(high, 5 * YEAR_MIN) > sys.freshness(low, 5 * YEAR_MIN), "高重大度更不易淡忘")


func _test_retrieve() -> void:
	var sys = MemScript.new()
	var npc := {}
	sys.add_memory(npc, {"type": "conflict", "minute": 0, "subjects": ["npc.a"], "weight": -80.0, "severity": 50.0})
	sys.add_memory(npc, {"type": "favor", "minute": 0, "subjects": ["npc.b"], "weight": 10.0, "severity": 10.0})
	sys.add_memory(npc, {"type": "promise", "minute": 0, "subjects": ["npc.a"], "weight": 30.0, "severity": 30.0})
	var got: Array = sys.retrieve(npc, {"subjects": ["npc.a"], "now_minute": 0}, 5)
	check_eq(got.size(), 2, "按涉及对象检索 2 条")
	check_eq(str(got[0]["type"]), "conflict", "按有效强度排序，冲突优先")

	var by_type: Array = sys.retrieve(npc, {"types": ["promise"], "now_minute": 0}, 5)
	check_eq(by_type.size(), 1, "按类型检索")
	check_eq(str(by_type[0]["type"]), "promise", "命中承诺")

	var top1: Array = sys.retrieve(npc, {"subjects": ["npc.a"], "now_minute": 0}, 1)
	check_eq(top1.size(), 1, "k 限制")


func _test_reinforce() -> void:
	var sys = MemScript.new()
	var npc := {}
	var m: Dictionary = sys.add_memory(npc, {"type": "shared_experience", "minute": 0, "weight": 20.0, "severity": 20.0})
	var r: Dictionary = sys.reinforce(npc, str(m["id"]))
	check_near(float(r["weight"]), 25.0, 0.0001, "引用加固权重 +5")
	check_eq(int(r["refs"]), 1, "引用计数 +1")
	# 负向记忆按符号增强。
	var neg: Dictionary = sys.add_memory(npc, {"type": "conflict", "minute": 0, "weight": -20.0, "severity": 20.0})
	var rn: Dictionary = sys.reinforce(npc, str(neg["id"]))
	check_near(float(rn["weight"]), -25.0, 0.0001, "负向记忆更负面")


func _test_decay() -> void:
	var sys = MemScript.new()
	var npc := {}
	var m: Dictionary = sys.add_memory(npc, {"type": "favor", "minute": 0, "weight": 100.0, "severity": 0.0})
	sys.decay_all(npc, 5.0)
	# 重大度 0 → 半衰期 1 年 → 5 年后为 0.5^5。
	check_near(float(m["weight"]), 100.0 * pow(0.5, 5.0), 0.01, "记忆按半衰期淡忘")


func _test_resolve_conflict() -> void:
	var sys = MemScript.new()
	var a: Dictionary = {"id": "a", "weight": 20.0, "severity": 10.0, "minute": 0, "refs": 0}
	var b: Dictionary = {"id": "b", "weight": -80.0, "severity": 10.0, "minute": 0, "refs": 0}
	var win: Dictionary = sys.resolve_conflict([a, b], 0)
	check_eq(str(win["id"]), "b", "冲突取情感权重绝对值高者")


func _test_dialogue_citations() -> void:
	var sys = MemScript.new()
	var npc := {}
	sys.add_memory(npc, {"type": "promise", "content": "答应带他去看海", "minute": 100,
		"subjects": ["npc.a"], "weight": 30.0, "severity": 20.0})
	sys.add_memory(npc, {"type": "favor", "content": "帮他搬过家", "minute": 100,
		"subjects": ["npc.a"], "weight": 20.0, "severity": 10.0})
	var cites: Array = sys.dialogue_citations(npc, {"subjects": ["npc.a"], "now_minute": 100}, 3)
	check_eq(cites.size(), 2, "引用两条记忆")
	check(cites.has("答应带他去看海"), "引用到承诺内容")


func _test_archive_on_death() -> void:
	var sys = MemScript.new()
	var npc := {}
	sys.add_memory(npc, {"type": "favor", "minute": 0, "weight": 5.0, "severity": 10.0, "visibility": "private"})
	sys.add_memory(npc, {"type": "secret", "minute": 0, "weight": 40.0, "severity": 80.0, "visibility": "private"})
	sys.add_memory(npc, {"type": "shared_experience", "minute": 0, "weight": 10.0, "severity": 20.0, "visibility": "public"})
	var archived: Array = sys.archive_on_death(npc)
	check_eq(archived.size(), 2, "公开或重大记忆归档为线索")
	for m in sys.to_dict(npc):
		check(bool(m["archived"]), "全部条目标记归档")
