extends "res://tests/test_base.gd"
## 职场关系、派系与办公室政治测试（任务 13；R13.8、R47.4-6；design D7）。
## 覆盖：初始化维度、派系加入/自组/骑墙、派系动态、抢功/甩锅/站队/举报掷骰、
##       晋升综合分（绩效+关系+声望+运气）、恶化风险与排挤/调岗/降职/解雇后果。

const WorkplaceScript = preload("res://sim/workplace.gd")
const RelationsScript = preload("res://sim/relations.gd")
const RngScript = preload("res://sim/rng.gd")
const BaselineScript = preload("res://sim/baseline.gd")


func _suite_name() -> String:
	return "workplace"


func run_tests() -> void:
	BaselineScript.clear_overrides()
	_test_init_and_factions()
	_test_faction_dynamics()
	_test_office_politics()
	_test_promotion_score()
	_test_deterioration()
	BaselineScript.clear_overrides()


func _player(conscientiousness: float = 50.0, neuroticism: float = 50.0, luck: float = 50.0) -> Dictionary:
	return {
		"attrs": {
			"personality": {
				"openness": 50.0, "conscientiousness": conscientiousness, "extraversion": 50.0,
				"agreeableness": 50.0, "neuroticism": neuroticism,
			},
			"ability": {"intelligence": 50.0, "charm": 50.0, "physique": 50.0, "willpower": 50.0, "luck": luck},
		},
		"relations": [],
	}


# --- 初始化与派系 ---

func _test_init_and_factions() -> void:
	var sys = WorkplaceScript.new()
	var work: Dictionary = sys.init_workplace("corp.a", "npc.boss", ["npc.a", "npc.b", "npc.c"])
	check_eq(str(work["company_id"]), "corp.a", "公司标识")
	check_eq(float(work["supervisor_favor"]), 50.0, "上级好感初始 50")
	check_eq(float(work["colleague_support"]), 50.0, "同事支持初始 50")
	check_eq(str(work["faction"]), "none", "初始骑墙")
	sys.add_faction(work, "f.reform", "改革派", 40.0)
	sys.add_faction(work, "f.status", "守旧派", 30.0)
	var join: Dictionary = sys.join_faction(work, "f.reform")
	check(bool(join["ok"]), "加入派系成功")
	check_eq(str(work["faction"]), "f.reform", "派系归属更新")
	check_near(sys.faction_power(work, "f.reform"), 45.0, 1e-6, "加入提升派系力量")
	check(not bool(sys.join_faction(work, "no_such")["ok"]), "加入不存在派系失败")
	var found: Dictionary = sys.found_faction(work, "f.own", "自组派")
	check(bool(found["ok"]) and bool(found["founded"]), "自组派系成功")
	check_eq(str(work["faction"]), "f.own", "自组后归属新派系")
	sys.stay_neutral(work)
	check_eq(str(work["faction"]), "none", "可骑墙")


# --- 派系动态 ---

func _test_faction_dynamics() -> void:
	var sys = WorkplaceScript.new()
	var work: Dictionary = sys.init_workplace("corp.a", "npc.boss", [])
	sys.add_faction(work, "f.a", "甲派", 80.0)
	sys.add_faction(work, "f.b", "乙派", 20.0)
	var rng = RngScript.new(42)
	var diff_before: float = absf(sys.faction_power(work, "f.a") - sys.faction_power(work, "f.b"))
	for i in 20:
		sys.settle_factions(work, rng)
	# 向均值回归：强弱差距收敛。
	var diff_after: float = absf(sys.faction_power(work, "f.a") - sys.faction_power(work, "f.b"))
	check(diff_after < diff_before, "多派系差距随时间收敛")


# --- 办公室政治 ---

func _test_office_politics() -> void:
	var sys = WorkplaceScript.new()
	# 强玩家 + 甩锅：玩家必胜（对手上限 95 < 玩家 96.5）。
	var work: Dictionary = sys.init_workplace("corp.a", "npc.boss", ["npc.a", "npc.b"])
	work["performance"] = 100.0
	work["supervisor_favor"] = 90.0
	work["colleague_support"] = 90.0
	var strong: Dictionary = _player(100.0, 0.0, 100.0)
	var rng = RngScript.new(1)
	var win: Dictionary = sys.office_politics(work, strong, null, rng, {"event": "blame"})
	check(bool(win["success"]), "强玩家应对甩锅成功")
	check_near(float(work["colleague_support"]), 93.0, 1e-6, "甩锅成功同事支持 +3")
	check_eq((work["conflicts"] as Array).size(), 1, "冲突被记录")
	# 弱玩家 + 抢功：玩家必败。
	var work2: Dictionary = sys.init_workplace("corp.a", "npc.boss", ["npc.x"])
	work2["performance"] = 0.0
	work2["supervisor_favor"] = 0.0
	work2["colleague_support"] = 50.0
	work2["internal_reputation"] = 50.0
	var weak: Dictionary = _player(0.0, 100.0, 0.0)
	var lose: Dictionary = sys.office_politics(work2, weak, null, rng, {"event": "credit_grab"})
	check(not bool(lose["success"]), "弱玩家抢功失败")
	check_near(float(work2["internal_reputation"]), 46.0, 1e-6, "抢功失败内部声望 -4")
	check_near(float(work2["colleague_support"]), 47.0, 1e-6, "抢功失败同事支持 -3")
	# 事件类型自动选择落在合法集合内。
	var work3: Dictionary = sys.init_workplace("corp.a", "npc.boss", [])
	var rec: Dictionary = sys.office_politics(work3, strong, null, rng, {})
	check(WorkplaceScript.EVENT_WEIGHTS.has(str(rec["event"])), "自动事件类型合法")


# --- 晋升 ---

func _test_promotion_score() -> void:
	var sys = WorkplaceScript.new()
	var rng = RngScript.new(9)
	var high_work: Dictionary = sys.init_workplace("corp.a", "npc.boss", [])
	high_work["performance"] = 100.0
	high_work["supervisor_favor"] = 100.0
	high_work["internal_reputation"] = 100.0
	high_work["industry_reputation"] = 100.0
	var lucky: Dictionary = _player(50.0, 50.0, 100.0)
	check(sys.should_promote(high_work, lucky, null, rng), "高绩效高关系可晋升")
	var low_work: Dictionary = sys.init_workplace("corp.a", "npc.boss", [])
	low_work["performance"] = 0.0
	low_work["supervisor_favor"] = 0.0
	low_work["internal_reputation"] = 0.0
	low_work["industry_reputation"] = 0.0
	var unlucky: Dictionary = _player(50.0, 50.0, 0.0)
	check(not sys.should_promote(low_work, unlucky, null, rng), "低绩效低关系不可晋升")
	# 关系系统注入：高好感提升晋升分。
	var relations = RelationsScript.new()
	var p: Dictionary = _player(50.0, 50.0, 50.0)
	relations.ensure_relation(p, "npc.boss")
	var score_without: float = sys.promotion_score(high_work, p, null, null)
	for i in 3:
		relations.apply_interaction(p, "npc.boss", "party")
	var score_with: float = sys.promotion_score(high_work, p, relations, null)
	check(score_with > score_without, "上级好感提升晋升分")


# --- 恶化与后果 ---

func _test_deterioration() -> void:
	var sys = WorkplaceScript.new()
	var rng = RngScript.new(3)
	var bad: Dictionary = sys.init_workplace("corp.a", "npc.boss", [])
	bad["supervisor_favor"] = 0.0
	bad["colleague_support"] = 0.0
	bad["internal_reputation"] = 0.0
	check_near(sys.deterioration_risk(bad), 1.0, 1e-6, "关系全崩风险为 1")
	var r: Dictionary = sys.apply_repercussion(bad, _player(), rng)
	check(str(r["action"]) != "none", "高风险必产生后果")
	check(WorkplaceScript.ACTIONS.has(str(r["action"])), "后果类型合法")
	var good: Dictionary = sys.init_workplace("corp.a", "npc.boss", [])
	good["supervisor_favor"] = 100.0
	good["colleague_support"] = 100.0
	good["internal_reputation"] = 100.0
	check_near(sys.deterioration_risk(good), 0.0, 1e-6, "关系良好无风险")
	check_eq(str(sys.apply_repercussion(good, _player(), rng)["action"]), "none", "无风险无后果")
	# 派系保护降低风险。
	var protected: Dictionary = sys.init_workplace("corp.a", "npc.boss", [])
	protected["supervisor_favor"] = 0.0
	protected["colleague_support"] = 0.0
	protected["internal_reputation"] = 0.0
	sys.add_faction(protected, "f.big", "大派", 100.0)
	sys.join_faction(protected, "f.big")
	check(sys.deterioration_risk(protected) < 1.0, "派系保护降低风险")
