extends "res://tests/test_base.gd"
## 军旅生涯测试（任务 13；R47.1-3；design D7）。
## 覆盖：兵种与军衔表、入伍条件（年龄/健康/学历/政审/兵种技能）、训练与驻防军功、
##       任务伤亡掷骰、晋升年限与军功考核、退役金与转业、拒征逃兵法律后果、在役民事限制。

const MilitaryScript = preload("res://sim/military.gd")
const RngScript = preload("res://sim/rng.gd")
const BaselineScript = preload("res://sim/baseline.gd")


func _suite_name() -> String:
	return "military"


func run_tests() -> void:
	BaselineScript.clear_overrides()
	_test_branches_and_ranks()
	_test_enlist_requirements()
	_test_training_garrison_mission()
	_test_promotion()
	_test_discharge_and_desert()
	_test_civil_restrictions()
	BaselineScript.clear_overrides()


func _player() -> Dictionary:
	return {
		"birth_minutes": -10519200,  # 0 时刻 20 岁
		"attrs": {"physiological": {"health": 80.0, "stamina": 80.0}},
		"education": [{"content_key": "edu.high_school", "status": "graduated"}],
		"skills": [{"content_key": "skill.physique", "level": 5}, {"content_key": "skill.technical", "level": 5}],
		"legal": {"wanted_level": 0, "criminal_record": false, "in_prison": false},
	}


# --- 兵种与军衔 ---

func _test_branches_and_ranks() -> void:
	var sys = MilitaryScript.new()
	check_eq(sys.branches().size(), 7, "七个兵种")
	for b in ["army", "navy", "air", "rocket", "logistics", "signal", "special"]:
		check(sys.has_branch(b), "兵种存在: " + b)
	check_eq(sys.rank_count(), 15, "十五级军衔")
	check_eq(str(sys.rank(0)["name"]), "列兵", "首级为列兵")
	check_eq(str(sys.rank(14)["name"]), "上将", "末级为上将")
	check_eq(sys.rank_index_by_key("colonel"), 11, "军衔按键查索引")
	check_eq(str(sys.rank(12)["grade"]), "general", "将官等级")
	# 各级年限与军功门槛单调不减，军饷为正且上将远高于列兵。
	for i in range(1, sys.rank_count()):
		check(float(sys.rank(i)["merit_required"]) >= float(sys.rank(i - 1)["merit_required"]), "军功门槛单调")
	for i in sys.rank_count():
		check(int(sys.rank(i)["pay"]) > 0, "军饷为正")
	check(int(sys.rank(sys.rank_count() - 1)["pay"]) > int(sys.rank(0)["pay"]) * 10, "高级军衔军饷显著更高")


# --- 入伍条件 ---

func _test_enlist_requirements() -> void:
	var sys = MilitaryScript.new()
	var p: Dictionary = _player()
	check(bool(sys.enlist_requirements(p, "army", {"now_minute": 0})["ok"]), "合格者可入伍")
	# 年龄
	var old: Dictionary = _player()
	old["birth_minutes"] = -25 * 525960
	check(not bool(sys.enlist_requirements(old, "army", {"now_minute": 0})["ok"]), "超龄不可入伍")
	# 健康
	var sick: Dictionary = _player()
	sick["attrs"]["physiological"]["health"] = 40.0
	check(not bool(sys.enlist_requirements(sick, "army", {"now_minute": 0})["ok"]), "健康不足不可入伍")
	# 学历
	var uneducated: Dictionary = _player()
	uneducated["education"] = []
	check(not bool(sys.enlist_requirements(uneducated, "army", {"now_minute": 0})["ok"]), "学历不足不可入伍")
	# 政审
	var criminal: Dictionary = _player()
	criminal["legal"]["criminal_record"] = true
	check(not bool(sys.enlist_requirements(criminal, "army", {"now_minute": 0})["ok"]), "政审不通过")
	# 兵种技能（特种需体质 6）
	var weak: Dictionary = _player()
	weak["skills"] = [{"content_key": "skill.physique", "level": 1}]
	var req: Dictionary = sys.enlist_requirements(weak, "special", {"now_minute": 0})
	check(not bool(req["ok"]), "兵种技能不足")
	check((req["missing"] as Array).size() > 0, "列出缺失项")
	# 入伍写入状态并禁止重复入伍。
	var r: Dictionary = sys.enlist(p, "army", 0)
	check(bool(r["ok"]), "入伍成功")
	check(sys.is_serving(p), "在役")
	check_eq(str(p["military"]["rank_key"]), "private", "起始军衔列兵")
	check(not bool(sys.enlist(p, "navy", 0)["ok"]), "在役不可重复入伍")


# --- 军旅循环 ---

func _test_training_garrison_mission() -> void:
	var sys = MilitaryScript.new()
	var p: Dictionary = _player()
	sys.enlist(p, "army", 0)
	sys.train(p, 100.0)
	check_near(float(p["military"]["merits"]), 10.0, 1e-6, "训练累积军功")
	sys.garrison(p, 5.0)
	check_near(float(p["military"]["merits"]), 20.0, 1e-6, "驻防累积军功")
	var rng = RngScript.new(2024)
	var m: Dictionary = sys.mission(p, rng, {"difficulty": 1.0})
	check(bool(m["ok"]), "任务执行成功")
	check(float(m["merits"]) > 20.0, "任务获得军功")
	# 高难度必然伤亡。
	var casualty: Dictionary = sys.mission(p, rng, {"difficulty": 100.0})
	check(bool(casualty["casualty"]), "高难度任务伤亡")
	check(float(p["attrs"]["physiological"]["health"]) < 80.0, "伤亡降低健康")
	check(int(p["military"]["casualties"]) >= 1, "伤亡计数")
	var idle: Dictionary = _player()
	check(not bool(sys.train(idle, 1.0)["ok"]), "非在役不可训练")


# --- 晋升 ---

func _test_promotion() -> void:
	var sys = MilitaryScript.new()
	var p: Dictionary = _player()
	sys.enlist(p, "army", 0)
	p["military"]["merits"] = 200.0
	var minute: int = int(5.0 * 525960.0)
	check(not sys.evaluate_promotion(p, 100), "年限未到不可晋升")
	check(sys.evaluate_promotion(p, minute), "年限与军功达标可晋升")
	var r: Dictionary = sys.promote(p, minute)
	check(bool(r["ok"]), "晋升成功")
	check_eq(int(p["military"]["rank_index"]), 1, "军衔 +1")
	check_eq(str(p["military"]["rank_key"]), "lance_corporal", "晋升为上等兵")
	check_eq(sys.monthly_pay(p), 700000, "军饷随军衔提高")
	# 顶级军衔无更高晋升。
	var top: Dictionary = _player()
	sys.enlist(top, "army", 0)
	top["military"]["rank_index"] = sys.rank_count() - 1
	check(not sys.evaluate_promotion(top, minute), "顶级军衔不可晋升")


# --- 退役与逃兵 ---

func _test_discharge_and_desert() -> void:
	var sys = MilitaryScript.new()
	var p: Dictionary = _player()
	sys.enlist(p, "army", 0)
	var d: Dictionary = sys.discharge(p, int(10.0 * 525960.0))
	check(bool(d["ok"]), "退役成功")
	check(int(d["severance"]) > 0, "退役金为正")
	check_eq(str(p["military"]["status"]), "discharged", "退役状态")
	check(not sys.is_serving(p), "退役后不在役")
	check(not bool(sys.discharge(p, 0)["ok"]), "非在役不可再退役")
	var q: Dictionary = _player()
	sys.enlist(q, "army", 0)
	var des: Dictionary = sys.desert(q, 100)
	check(bool(des["ok"]), "逃兵事件成功")
	check(bool(q["legal"]["criminal_record"]), "逃兵写入犯罪记录")
	check_eq(int(q["legal"]["wanted_level"]), 3, "逃兵通缉等级 +3")
	check_eq(str(q["military"]["status"]), "deserter", "逃兵状态")


# --- 民事限制 ---

func _test_civil_restrictions() -> void:
	var sys = MilitaryScript.new()
	var p: Dictionary = _player()
	sys.enlist(p, "army", 0)
	check(sys.restricts_civil(p, "辞职"), "在役禁用辞职")
	check(sys.restricts_civil(p, "创业"), "在役禁用创业")
	check(not sys.restricts_civil(p, "工作"), "常规工作不禁用")
	check_eq(sys.restricted_verbs(p).size(), MilitaryScript.RESTRICTED_VERBS.size(), "在役返回受限动词表")
	sys.discharge(p, int(2.0 * 525960.0))
	check(not sys.restricts_civil(p, "辞职"), "退役后解除限制")
	check_eq(sys.restricted_verbs(p).size(), 0, "退役后无受限动词")
