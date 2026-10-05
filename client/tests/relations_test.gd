extends "res://tests/test_base.gd"
## 五维关系网络测试（任务 12；R18/R20/R50.1–R50.2；design D10）。
## 覆盖：关系创建/删除、互动五维增减、重大事件跳变与上限、性格修正、
##       分级、解锁阈值与拒绝、年度衰减、行为传播、亲密关系。

const RelScript = preload("res://sim/relations.gd")
const BaselineScript = preload("res://sim/baseline.gd")

func _suite_name() -> String:
	return "relations"

func run_tests() -> void:
	_test_ensure_and_remove()
	_test_interaction_deltas()
	_test_major_interaction()
	_test_personality_modifier()
	_test_classify()
	_test_unlocks_and_reject()
	_test_decay()
	_test_propagate()
	_test_romance()


func _test_ensure_and_remove() -> void:
	var sys = RelScript.new()
	var owner := {}
	var rel: Dictionary = sys.ensure_relation(owner, "npc.a")
	check_eq(str(rel["target_id"]), "npc.a", "target_id")
	check_eq(float(rel["favor"]), 0.0, "默认好感")
	check_eq(float(rel["trust"]), 20.0, "默认信任")
	check_eq(float(rel["grudge"]), 0.0, "默认恩怨")
	check_eq(sys.to_dict(owner).size(), 1, "确保后唯一")
	sys.ensure_relation(owner, "npc.a")
	check_eq(sys.to_dict(owner).size(), 1, "重复确保不新增")
	check(sys.remove_relation(owner, "npc.a"), "删除成功")
	check(sys.get_relation(owner, "npc.a").is_empty(), "删除后为空")
	check(not sys.remove_relation(owner, "npc.a"), "重复删除返回 false")


func _test_interaction_deltas() -> void:
	var sys = RelScript.new()
	var o1 := {}
	sys.apply_interaction(o1, "npc.a", "chat")
	var r1: Dictionary = sys.get_relation(o1, "npc.a")
	check_near(float(r1["favor"]), 1.0, 0.0001, "闲聊好感 +1")
	check_near(float(r1["trust"]), 20.5, 0.0001, "闲聊信任 +0.5")
	check_near(float(r1["intimacy"]), 0.5, 0.0001, "闲聊亲密 +0.5")
	check_eq(int(r1["interactions"]), 1, "互动计数")

	var o2 := {}
	sys.apply_interaction(o2, "npc.b", "help")
	var r2: Dictionary = sys.get_relation(o2, "npc.b")
	check_near(float(r2["favor"]), 6.0, 0.0001, "帮助好感 +6")
	check_near(float(r2["grudge"]), -2.0, 0.0001, "帮助恩怨 -2")


func _test_major_interaction() -> void:
	var sys = RelScript.new()
	var o := {}
	# 救人：重大事件，可大幅跳变，不受普通上限约束。
	var d: Dictionary = sys.apply_interaction(o, "npc.a", "rescue")
	check(bool(d["ok"]), "救人成功")
	var r: Dictionary = sys.get_relation(o, "npc.a")
	check_near(float(r["favor"]), 30.0, 0.0001, "救人好感 +30")
	check_near(float(r["trust"]), 40.0, 0.0001, "救人信任 +20")
	check_near(float(r["intimacy"]), 10.0, 0.0001, "救人亲密 +10")

	# 背叛：信任跌到下限被夹到 0，恩怨 +50。
	var o2 := {}
	sys.apply_interaction(o2, "npc.b", "betray")
	var r2: Dictionary = sys.get_relation(o2, "npc.b")
	check_near(float(r2["favor"]), -40.0, 0.0001, "背叛好感 -40")
	check_near(float(r2["trust"]), 0.0, 0.0001, "背叛信任夹到下限 0")
	check_near(float(r2["grudge"]), 50.0, 0.0001, "背叛恩怨 +50")


func _test_personality_modifier() -> void:
	var sys = RelScript.new()
	# 高亲和 + 外向 + 开放 → 修正系数夹到 1.5。
	var o := {}
	sys.apply_interaction(o, "npc.a", "chat", {
		"personality": {"agreeableness": 100.0, "extraversion": 100.0},
		"values": {"conservative_open": 100.0},
	})
	var r: Dictionary = sys.get_relation(o, "npc.a")
	check_near(float(r["favor"]), 1.5, 0.0001, "高亲和修正后好感 +1.5")

	# 低亲和 → 0.75。
	var o2 := {}
	sys.apply_interaction(o2, "npc.b", "chat", {"personality": {"agreeableness": 0.0}})
	var r2: Dictionary = sys.get_relation(o2, "npc.b")
	check_near(float(r2["favor"]), 0.75, 0.0001, "低亲和修正后好感 +0.75")


func _test_classify() -> void:
	var sys = RelScript.new()
	check_eq(sys.classify({"favor": 0.0, "trust": 20.0, "intimacy": 0.0, "grudge": 0.0}), "stranger", "陌路")
	check_eq(sys.classify({"favor": 10.0, "trust": 50.0, "intimacy": 0.0, "grudge": 0.0}), "acquaintance", "点头")
	check_eq(sys.classify({"favor": 25.0, "trust": 50.0, "intimacy": 0.0, "grudge": 0.0}), "familiar", "熟人")
	check_eq(sys.classify({"favor": 50.0, "trust": 50.0, "intimacy": 0.0, "grudge": 0.0}), "friend", "朋友")
	check_eq(sys.classify({"favor": 75.0, "trust": 50.0, "intimacy": 0.0, "grudge": 0.0}), "best_friend", "挚友")
	check_eq(sys.classify({"favor": 75.0, "trust": 50.0, "intimacy": 70.0, "grudge": 0.0}), "family", "家人")
	check_eq(sys.classify({"favor": -60.0, "trust": 50.0, "intimacy": 0.0, "grudge": 0.0}), "enemy", "低好感仇敌")
	check_eq(sys.classify({"favor": 0.0, "trust": 50.0, "intimacy": 0.0, "grudge": -60.0}), "enemy", "低恩怨仇敌")
	check_eq(sys.classify({"favor": 60.0, "trust": 50.0, "intimacy": 60.0, "grudge": 0.0, "romance": true}), "lover", "恋人")


func _test_unlocks_and_reject() -> void:
	var sys = RelScript.new()
	var r: Dictionary = {"favor": 70.0, "trust": 50.0, "intimacy": 0.0, "grudge": 0.0}
	var acts: Array = sys.unlocked_actions(r)
	check(acts.has("introduce_job"), "70 好感解锁介绍工作")
	check(acts.has("borrow"), "70 好感解锁借钱")
	check(not acts.has("partner"), "70 好感未解锁合伙")

	var lover: Dictionary = {"favor": 90.0, "trust": 50.0, "intimacy": 0.0, "grudge": 0.0, "romance": true}
	var acts2: Array = sys.unlocked_actions(lover)
	check(acts2.has("partner"), "90 好感解锁合伙")
	check(acts2.has("marry"), "恋爱好感 90 解锁求婚")

	check(sys.rejects_interaction({"grudge": -50.0, "favor": 0.0}), "恩怨触底拒绝互动")
	check(sys.rejects_interaction({"grudge": 0.0, "favor": -50.0}), "好感触底拒绝互动")
	check(not sys.rejects_interaction({"grudge": 0.0, "favor": 0.0}), "中性不拒绝")


func _test_decay() -> void:
	var sys = RelScript.new()
	var owner := {}
	var rel: Dictionary = sys.ensure_relation(owner, "npc.a")
	rel["favor"] = 100.0
	rel["trust"] = 100.0
	var n: int = sys.decay_all(owner, 5.0)
	check_eq(n, 1, "衰减一条关系")
	var expected: float = 100.0 * exp(-BaselineScript.effective_relation_decay_k() * 5.0)
	check_near(float(rel["favor"]), expected, 0.01, "好感年度指数衰减")
	check_near(float(rel["trust"]), expected, 0.01, "信任年度指数衰减")
	check(float(rel["favor"]) < 100.0, "衰减后更小")

	# 负向好感同样向 0 收敛。
	var owner2 := {}
	var rel2: Dictionary = sys.ensure_relation(owner2, "npc.b")
	rel2["favor"] = -100.0
	sys.decay_all(owner2, 5.0)
	check_near(float(rel2["favor"]), -expected, 0.01, "负向好感向 0 收敛")


func _test_propagate() -> void:
	var sys = RelScript.new()
	var owner := {}
	var witnesses: Array = [
		{"id": "w1", "strength": 1.0},
		{"id": "w2", "strength": 0.5},
	]
	var res: Dictionary = sys.propagate(owner, witnesses, 1.0, 100.0)
	check_eq(int(res["affected"]), 2, "传播影响 2 人")
	# 单次传播受 INTERACTION_CAP(15) 限制。
	check_near(float(sys.get_relation(owner, "w1")["favor"]), 15.0, 0.0001, "见证者传播好感 +15")
	check_near(float(sys.get_relation(owner, "w2")["favor"]), 15.0, 0.0001, "弱见证者同样受上限")

	var owner2 := {}
	sys.propagate(owner2, [{"id": "x", "strength": 1.0}], -1.0, 10.0)
	check_near(float(sys.get_relation(owner2, "x")["favor"]), -10.0, 0.0001, "负向传播好感 -10")


func _test_romance() -> void:
	var sys = RelScript.new()
	var owner := {}
	sys.apply_interaction(owner, "npc.a", "chat", {"romance": true})
	var rel: Dictionary = sys.get_relation(owner, "npc.a")
	check(bool(rel["romance"]), "亲密行为标记 romance")
	check_eq(sys.level_name("friend"), "朋友", "分级中文名")
