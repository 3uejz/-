extends "res://tests/test_base.gd"
## 职业树、求职面试、工作结算与晋升退休测试（任务 13；R13、R47.9；design D7）。
## 覆盖：目录无上限、行业分树、学历/技能/证书/年龄/健康准入、面试与入职、
##       工作扣体力心情与心情效率惩罚、按日工资经 EconomySystem 守恒结算、
##       试用转正、晋升链与年结算晋升、辞职与退休。

const JobScript = preload("res://sim/jobs.gd")
const EconomyScript = preload("res://sim/economy.gd")
const RngScript = preload("res://sim/rng.gd")
const BaselineScript = preload("res://sim/baseline.gd")


func _suite_name() -> String:
	return "jobs"


func run_tests() -> void:
	BaselineScript.clear_overrides()
	_test_catalog_extensible()
	_test_requirements()
	_test_interview_and_apply()
	_test_work_and_efficiency()
	_test_settle_day_conservation()
	_test_promotion_chain()
	_test_regularize_resign_retire()
	BaselineScript.clear_overrides()


func _player() -> Dictionary:
	return {
		"birth_minutes": -15778800,  # 0 时刻年龄 30 岁（-30*365.25*1440）
		"age": 30,
		"attrs": {
			"physiological": {"health": 80.0, "stamina": 100.0, "hunger": 50.0, "thirst": 50.0, "cleanliness": 50.0, "sleep_debt": 10.0},
			"psychological": {"mood": 70.0, "stress": 20.0, "happiness": 50.0, "meaning": 50.0},
			"ability": {"intelligence": 50.0, "charm": 60.0, "physique": 50.0, "willpower": 50.0, "luck": 50.0},
		},
		"skills": [],
		"education": [],
		"licenses": [],
		"job": {},
	}


func _educated(strong: bool) -> Dictionary:
	var p: Dictionary = _player()
	p["education"] = [{"content_key": "edu.bachelor", "status": "graduated"}]
	p["licenses"] = [{"content_key": "license.driver_c1", "status": "graduated"}]
	p["skills"] = [{"content_key": "skill.programming", "level": 20 if strong else 0}]
	if strong:
		p["attrs"]["ability"]["charm"] = 100.0
		p["attrs"]["ability"]["luck"] = 100.0
	return p


# --- 目录 ---

func _test_catalog_extensible() -> void:
	var sys = JobScript.new()
	check(sys.register_starter_catalog() >= 30, "起步目录注册成功")
	var base: int = sys.def_count()
	check(sys.register({"name": "缺 id"}) == {}, "缺必填字段拒绝注册")
	check(sys.register({"id": "x", "name": "行业非法", "industry": "nope", "base_salary": 1}) == {}, "非法行业拒绝注册")
	for i in 200:
		sys.register({"id": "job.custom_%d" % i, "name": "自定义%d" % i, "industry": "emerging", "base_salary": 100000})
	check_eq(sys.def_count(), base + 200, "岗位可扩展且无数量上限")
	check(sys.has_def("job.programmer"), "内置岗位存在")
	check(sys.is_military("job.soldier"), "军人岗位标记正确")
	check(sys.by_industry("it").size() >= 4, "按行业分树")


# --- 准入 ---

func _test_requirements() -> void:
	var sys = JobScript.new()
	sys.register_starter_catalog()
	var p: Dictionary = _player()
	var req: Dictionary = sys.matches_requirements(p, "job.programmer")
	check(not bool(req["ok"]), "缺学历与技能不满足")
	check((req["missing"] as Array).size() >= 2, "缺失项被列出")
	p = _educated(true)
	check(bool(sys.matches_requirements(p, "job.programmer")["ok"]), "满足学历技能后合格")
	# 证书
	var p2: Dictionary = _player()
	p2["licenses"] = [{"content_key": "license.driver_c1", "status": "graduated"}]
	check(bool(sys.matches_requirements(p2, "job.driver")["ok"]), "有驾照可应聘司机")
	# 年龄：军人 18..24
	var young: Dictionary = _player()
	young["age"] = 30
	check(not bool(sys.matches_requirements(young, "job.soldier")["ok"]), "超龄不可参军")
	young["age"] = 20
	check(bool(sys.matches_requirements(young, "job.soldier")["ok"]), "适龄可参军")
	# 健康：运动员需 60
	var sick: Dictionary = _player()
	sick["attrs"]["physiological"]["health"] = 40.0
	check(not bool(sys.matches_requirements(sick, "job.athlete")["ok"]), "健康不足拒绝")


# --- 面试与入职 ---

func _test_interview_and_apply() -> void:
	var sys = JobScript.new()
	sys.register_starter_catalog()
	var rng = RngScript.new(12345)
	var strong: Dictionary = _educated(true)
	for i in 40:
		sys.register({"id": "job.fill_%d" % i, "name": "填充%d" % i, "industry": "emerging", "base_salary": 100000})
	var good: Dictionary = sys.apply(strong, "job.programmer", rng, 0, {"hire_difficulty": 0.1})
	check(bool(good["hired"]), "强候选低难度录用")
	check(not str(good["job"]["content_key"]).is_empty(), "入职写入岗位")
	check_eq(str(strong["job"]["status"]), "probation", "入职为试用期")
	var weak: Dictionary = _player()
	var bad: Dictionary = sys.apply(weak, "job.waiter", rng, 0, {"hire_difficulty": 1.0})
	check(bool(bad["ok"]) and not bool(bad["hired"]), "弱候选高难度被拒")
	var unq: Dictionary = sys.apply(_player(), "job.programmer", rng, 0, {})
	check_eq(str(unq["reason"]), "unqualified", "不合格直接拒绝")


# --- 工作与效率 ---

func _test_work_and_efficiency() -> void:
	var sys = JobScript.new()
	sys.register_starter_catalog()
	var p: Dictionary = _educated(true)
	sys.hire(p, "job.programmer", 0)
	check_near(sys.efficiency(p), 1.0, 1e-6, "心情正常效率为 1")
	var before: float = float(p["attrs"]["physiological"]["stamina"])
	var r: Dictionary = sys.work(p, 480.0)
	check(bool(r["ok"]), "工作成功")
	check_near(before - float(p["attrs"]["physiological"]["stamina"]), 48.0, 1e-6, "8 小时扣 48 体力")
	check_near(float(p["job"]["performance"]), 52.0, 1e-6, "绩效累计 +2")
	check_near(float(p["job"]["hours_worked_today"]), 8.0, 1e-6, "工时累计")
	p["attrs"]["psychological"]["mood"] = 20.0
	check_near(sys.efficiency(p), 0.75, 1e-6, "低心情效率降为 0.75")
	var idle: Dictionary = _player()
	check(not bool(sys.work(idle, 60.0)["ok"]), "无业不可工作")


# --- 工资结算 ---

func _test_settle_day_conservation() -> void:
	var sys = JobScript.new()
	sys.register_starter_catalog()
	var econ = EconomyScript.new(1)
	econ.open_account("employer", 100000)
	econ.open_account("worker", 0)
	var budget: int = econ.liquid("employer")
	var p: Dictionary = _player()
	sys.hire(p, "job.waiter", 0)  # 月薪 400000 → 日薪 13333
	var r: Dictionary = sys.settle_day(p, econ, "worker", "employer", 1)
	check(bool(r["ok"]), "当日工资足额发放")
	check_eq(int(r["paid"]), int(400000.0 / 30.0), "日薪 = 月薪/30")
	check_eq(econ.cash("worker"), int(r["paid"]), "员工到账")
	check_eq(econ.total_money(), budget, "转账不改变货币总量")
	var poor = EconomyScript.new(1)
	poor.open_account("employer", 1000)
	poor.open_account("worker", 0)
	var r2: Dictionary = sys.settle_day(p, poor, "worker", "employer", 1)
	check(not bool(r2["ok"]), "雇主资金不足时标记欠薪")
	check_eq(int(r2["arrears"]), int(400000.0 / 30.0) - 1000, "欠薪金额正确")
	check(not sys.settle_day(p, econ, "worker", "no_such", 1)["ok"], "无雇主账户拒绝")


# --- 晋升 ---

func _test_promotion_chain() -> void:
	var sys = JobScript.new()
	sys.register_starter_catalog()
	var p: Dictionary = _educated(true)
	sys.hire(p, "job.programmer", 0)
	check(not sys.eligible_promotion(p), "试用期不可晋升")
	p["job"]["status"] = "regular"
	p["job"]["performance"] = 80.0
	p["job"]["internal_reputation"] = 70.0
	check(sys.eligible_promotion(p), "达标且转正可晋升")
	var r: Dictionary = sys.promote(p, 0)
	check(bool(r["ok"]), "晋升成功")
	check_eq(str(r["to"]), "job.senior_programmer", "晋升到下一岗")
	check_eq(int(p["job"]["salary"]), 3500000, "薪资随岗位更新")
	var rng = RngScript.new(7)
	var top: Dictionary = _educated(true)
	sys.hire(top, "job.architect", 0)
	top["job"]["status"] = "regular"
	top["job"]["performance"] = 90.0
	top["job"]["internal_reputation"] = 90.0
	check_eq(str(sys.promote(top, 0)["reason"]), "max_rank", "顶级岗位无更高晋升")


# --- 转正/辞职/退休 ---

func _test_regularize_resign_retire() -> void:
	var sys = JobScript.new()
	sys.register_starter_catalog()
	var p: Dictionary = _educated(true)
	sys.hire(p, "job.programmer", 0)
	check(not bool(sys.regularize(p, 1000)["ok"]), "试用期未满不可转正")
	check(bool(sys.regularize(p, 91 * 1440)["ok"]), "试用期满转正")
	check_eq(str(p["job"]["status"]), "regular", "状态转正")
	var q: Dictionary = _educated(true)
	sys.hire(q, "job.programmer", 0)
	var r: Dictionary = sys.retire(q, 365 * 1440 * 30)
	check(bool(r["ok"]), "退休成功")
	check(int(r["pension"]) > 0, "退休金为正")
	check_eq(str(q["job"]["status"]), "retired", "退休状态")
	var s: Dictionary = _educated(true)
	sys.hire(s, "job.programmer", 0)
	check(bool(sys.resign(s, 0)["ok"]), "辞职成功")
	check(s["job"].is_empty(), "辞职清空岗位")
