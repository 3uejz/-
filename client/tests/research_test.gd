extends "res://tests/test_base.gd"
## 科研流程测试（任务 14；R45.4-5；design D5）。
## 覆盖：资源约束立项、阶段推进、成果质量公式、同行评审、发表结算、专利与重大成果时代解锁。

const ResearchScript = preload("res://sim/research.gd")
const EconomyScript = preload("res://sim/economy.gd")
const RngScript = preload("res://sim/rng.gd")
const BaselineScript = preload("res://sim/baseline.gd")


func _suite_name() -> String:
	return "research"


func run_tests() -> void:
	BaselineScript.clear_overrides()
	_test_start_requirements()
	_test_quality()
	_test_pipeline()
	_test_patent_and_unlock()
	BaselineScript.clear_overrides()


func _resources() -> Dictionary:
	return {"lab": true, "equipment": 2, "team": 3, "funding": 5000000}


func _skills() -> Array:
	return [{"content_key": "skill.academic", "level": 20}]


func _ctx(rng) -> Dictionary:
	return {"skills": _skills(), "investment": 100.0, "innovation": 100.0, "competition": 0.0, "rng": rng}


# --- 立项 ---

func _test_start_requirements() -> void:
	var sys = ResearchScript.new()
	check_eq(str(sys.start_project("", _resources())["reason"]), "empty_topic", "空选题拒绝")
	var no_lab: Dictionary = _resources()
	no_lab["lab"] = false
	check_eq(str(sys.start_project("x", no_lab)["reason"]), "no_lab", "缺实验室拒绝")
	var no_eq: Dictionary = _resources()
	no_eq["equipment"] = 0
	check_eq(str(sys.start_project("x", no_eq)["reason"]), "no_equipment", "缺仪器拒绝")
	var no_team: Dictionary = _resources()
	no_team["team"] = 0
	check_eq(str(sys.start_project("x", no_team)["reason"]), "no_team", "缺团队拒绝")
	var poor: Dictionary = _resources()
	poor["funding"] = 1000
	check_eq(str(sys.start_project("x", poor)["reason"]), "insufficient_funding", "经费不足拒绝")
	var res: Dictionary = _resources()
	var r: Dictionary = sys.start_project("可控核聚变", res)
	check(bool(r["ok"]), "满足资源立项成功")
	check_eq(res["funding"], 5000000 - ResearchScript.STARTUP_COST, "扣除启动经费")
	check_eq(str((r["project"] as Dictionary)["stage"]), "topic", "初始阶段为选题")


# --- 质量公式 ---

func _test_quality() -> void:
	var sys = ResearchScript.new()
	check_near(sys.quality(_skills(), 100.0, 100.0, 100.0, 0.0), 100.0, 1e-6, "全满质量 100")
	check_near(sys.quality([], 0.0, 0.0, 0.0, 0.0), 0.0, 1e-6, "全空质量 0")
	check(sys.quality(_skills(), 100.0, 100.0, 100.0, 100.0) < 100.0, "竞争降低质量")


# --- 阶段推进 ---

func _test_pipeline() -> void:
	var sys = ResearchScript.new()
	var res: Dictionary = _resources()
	var project: Dictionary = sys.start_project("可控核聚变", res)["project"]
	var rng = RngScript.new(3)
	var stages: Array = []
	for i in 7:
		var r: Dictionary = sys.advance(project, res, _ctx(rng))
		if not bool(r["ok"]):
			break
		stages.append(str(r["stage"]))
	check(stages.has("literature") and stages.has("experiment"), "推进到实验")
	check(stages.has("data") and stages.has("paper"), "推进到论文")
	check((project["quality"] as float) >= 90.0, "高质量成果")
	check_eq(str(project["stage"]), "published", "同行评审通过发表")
	check_eq(res["funding"], 5000000 - ResearchScript.STARTUP_COST - ResearchScript.EXPERIMENT_COST, "实验经费扣减")
	# 发表结算。
	var econ = EconomyScript.new(1)
	var c: Dictionary = sys.collect(project, econ, "researcher")
	check(bool(c["ok"]), "发表结算成功")
	check(int(c["citations"]) > 0, "获得引用")
	check(float(c["prestige"]) > 0.0, "获得声望")
	check(int(c["income"]) > 0, "获得收入")
	check_eq(econ.liquid("researcher"), int(c["income"]), "收入注入账户")
	check(bool(c["era_unlock"]), "重大成果推动时代解锁")
	# 低质量被拒。
	var low: Dictionary = sys.new_project("灌水论文")
	low["quality"] = 5.0
	low["stage"] = "peer_review"
	var lr: Dictionary = sys.advance(low, _resources(), {"rng": rng})
	check_eq(str(lr["stage"]), "rejected", "低质量被同行评审拒绝")
	check(not bool(sys.collect(low, econ, "researcher")["ok"]), "未发表不可结算")


# --- 专利 ---

func _test_patent_and_unlock() -> void:
	var sys = ResearchScript.new()
	var project: Dictionary = sys.new_project("新型电池")
	project["quality"] = 80.0
	project["stage"] = "data"
	var p: Dictionary = sys.file_patent(project)
	check(bool(p["ok"]), "质量达标可申请专利")
	check(bool(project["patented"]), "专利标记写入")
	var early: Dictionary = sys.new_project("过早")
	early["stage"] = "literature"
	check_eq(str(sys.file_patent(early, {"min_quality": 0.0})["reason"]), "too_early", "过早申请拒绝")
	var lowq: Dictionary = sys.new_project("低质")
	lowq["quality"] = 10.0
	lowq["stage"] = "paper"
	check_eq(str(sys.file_patent(lowq)["reason"]), "quality_too_low", "质量不足拒绝专利")
