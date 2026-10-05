extends "res://tests/test_base.gd"
## 教育学历与证书测试（任务 14；R11；design D5）。
## 覆盖：学历体系与顺序比较、入学前置、学习进度与考试毕业、证书报考条件与费用、
##       考试评分、以及与职业准入的学历解锁联动。

const EduScript = preload("res://sim/education.gd")
const JobScript = preload("res://sim/jobs.gd")
const EconomyScript = preload("res://sim/economy.gd")
const RngScript = preload("res://sim/rng.gd")
const BaselineScript = preload("res://sim/baseline.gd")


func _suite_name() -> String:
	return "education"


func run_tests() -> void:
	BaselineScript.clear_overrides()
	_test_catalog_and_degree_order()
	_test_enroll()
	_test_study_and_graduate()
	_test_certificate()
	_test_jobs_unlock()
	BaselineScript.clear_overrides()


func _player() -> Dictionary:
	return {
		"age": 30,
		"attrs": {"ability": {"intelligence": 50.0, "charm": 50.0, "physique": 50.0, "willpower": 50.0, "luck": 50.0}},
		"education": [], "licenses": [], "skills": [],
	}


func _degree(id: String, status: String = "graduated") -> Dictionary:
	return {"content_key": id, "status": status}


# --- 目录与顺序 ---

func _test_catalog_and_degree_order() -> void:
	var sys = EduScript.new()
	check_eq(sys.register_starter_catalog(), 38, "8 学历 + 30 证书")
	check_eq(sys.degree_count(), 8, "八个学历")
	check(sys.cert_count() >= 30, "证书不少于 30")
	check_eq(sys.degree_order("edu.kindergarten"), 0, "幼儿园序号 0")
	check_eq(sys.degree_order("edu.doctor"), 7, "博士序号 7")
	var p: Dictionary = _player()
	p["education"] = [_degree("edu.bachelor")]
	check(sys.has_degree_at_least(p, "edu.college"), "本科满足大专")
	check(sys.has_degree_at_least(p, "edu.bachelor"), "满足同级")
	check(not sys.has_degree_at_least(p, "edu.master"), "不满足更高学历")
	p["education"] = [_degree("edu.bachelor", "in_progress")]
	check(not sys.has_degree_at_least(p, "edu.bachelor"), "在读不算已获学历")


# --- 入学 ---

func _test_enroll() -> void:
	var sys = EduScript.new()
	sys.register_starter_catalog()
	var p: Dictionary = _player()
	check_eq(str(sys.enroll(p, "edu.master", 0)["reason"]), "prereq", "缺前置学历无法入学")
	check(bool(sys.enroll(p, "edu.kindergarten", 0)["ok"]), "无前置可入幼儿园")
	check_eq(str(sys.enroll(p, "edu.kindergarten", 0)["reason"]), "already_enrolled", "重复入学拒绝")
	# 补齐前置后可入学。
	p["education"] = [_degree("edu.junior")]
	check(bool(sys.enroll(p, "edu.high_school", 0)["ok"]), "有前置可升高中学")
	check_eq(str(sys.enroll(p, "edu.nope", 0)["reason"]), "unknown_degree", "未知学历拒绝")


# --- 学习与毕业 ---

func _test_study_and_graduate() -> void:
	var sys = EduScript.new()
	sys.register_starter_catalog()
	var p: Dictionary = _player()
	p["education"] = [_degree("edu.junior")]
	sys.enroll(p, "edu.high_school", 0)
	var cred: Dictionary = sys.credential_key(p, "education", "edu.high_school")
	check(not cred.is_empty(), "入学写入凭据")
	var progress: float = sys.study(cred, 100.0, 100.0)
	check_near(progress, 100.0, 1e-6, "学习进度封顶 100")
	var rng = RngScript.new(1)
	p["attrs"]["ability"]["intelligence"] = 100.0
	p["attrs"]["ability"]["luck"] = 100.0
	var r: Dictionary = sys.take_degree_exam(p, "edu.high_school", rng, {"now_minute": 5000})
	check(bool(r["passed"]), "强能力 + 满进度通过考试")
	check_eq(str(cred["status"]), "graduated", "考试通过即毕业")
	check_eq(int(cred["obtained_minutes"]), 5000, "记录毕业时间")
	# 未入学考试。
	check_eq(str(sys.take_degree_exam(_player(), "edu.high_school", rng)["reason"]), "not_enrolled", "未入学不可考试")


# --- 证书 ---

func _test_certificate() -> void:
	var sys = EduScript.new()
	sys.register_starter_catalog()
	var econ = EconomyScript.new(1)
	econ.open_account("owner", 1000000)
	var rng = RngScript.new(7)
	var p: Dictionary = _player()
	# 无学历要求、需缴费。
	var r: Dictionary = sys.obtain_certificate(p, "license.driver_c1", econ, "owner", rng, {})
	check(bool(r["passed"]), "报考 C1 驾照通过")
	check_eq(econ.liquid("owner"), 500000, "报考费从账户扣除")
	check(not sys.credential_key(p, "licenses", "license.driver_c1").is_empty(), "证书写入 licenses")
	check_eq(str(sys.obtain_certificate(p, "license.driver_c1", econ, "owner", rng)["reason"]), "already_have", "重复报考拒绝")
	# 学历门槛。
	var p2: Dictionary = _player()
	check_eq(str(sys.obtain_certificate(p2, "license.doctor", econ, "owner", rng)["reason"]), "education", "缺学历拒绝报考医师")
	# 资金不足。
	var poor: Dictionary = _player()
	var econ2 = EconomyScript.new(1)
	econ2.open_account("owner", 0)
	check_eq(str(sys.obtain_certificate(poor, "license.driver_c1", econ2, "owner", rng)["reason"]), "insufficient_funds", "资金不足拒绝报考")
	# 满足学历后可报考。
	var p3: Dictionary = _player()
	p3["education"] = [_degree("edu.bachelor")]
	p3["attrs"]["ability"]["intelligence"] = 100.0
	p3["attrs"]["ability"]["luck"] = 100.0
	check(bool(sys.obtain_certificate(p3, "license.doctor", econ, "owner", rng, {"progress": 100.0})["passed"]), "满足学历可报考医师")


# --- 与职业准入联动 ---

func _test_jobs_unlock() -> void:
	var jobs = JobScript.new()
	jobs.register_starter_catalog()
	var p: Dictionary = _player()
	# 仅有硕士学历（高学历满足本科要求）+ 编程技能。
	p["education"] = [_degree("edu.master")]
	p["skills"] = [{"content_key": "skill.programming", "level": 10}]
	var req: Dictionary = jobs.matches_requirements(p, "job.programmer")
	check(bool(req["ok"]), "高学历满足岗位学历要求")
	# 在读学历不满足。
	p["education"] = [_degree("edu.bachelor", "in_progress")]
	check(not bool(jobs.matches_requirements(p, "job.programmer")["ok"]), "在读学历不作为准入凭证")
