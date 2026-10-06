extends "res://tests/test_base.gd"
## 残障与养老测试（任务 29；R65；design D21）。
## 覆盖：来源/类型/程度/辅具/养老模式数据表、残障获取与移动修正、辅具与康复、
##       退休金/养老模式/临终关怀、护理成本与护工追责、认知障碍监护、残障歧视。

const DisabilityScript = preload("res://sim/disability_elderly.gd")


func _suite_name() -> String:
	return "disability_elderly"


func run_tests() -> void:
	_test_tables()
	_test_acquire_and_mobility()
	_test_device_and_recovery()
	_test_elderly_care()
	_test_caregiver()
	_test_cognitive_guardianship()
	_test_discrimination()


func _test_tables() -> void:
	var sys = DisabilityScript.new()
	check_eq(DisabilityScript.SOURCES.size(), 4, "四种残障来源")
	check_eq(DisabilityScript.TYPES.size(), 4, "四种残障类型")
	check_eq(DisabilityScript.SEVERITIES.size(), 3, "轻中重三级")
	check_eq(DisabilityScript.DEVICES.size(), 6, "六类辅具")
	check_eq(DisabilityScript.CARE_MODES.size(), 3, "三种养老模式")
	check(DisabilityScript.CARE_MODES.has("home_care"), "含居家护理")
	check(DisabilityScript.CARE_MODES.has("community_care"), "含社区养老")
	check(DisabilityScript.CARE_MODES.has("institution_care"), "含机构养老")


func _test_acquire_and_mobility() -> void:
	var sys = DisabilityScript.new()
	var st: Dictionary = sys.new_state()
	check_near(sys.mobility(st), 1.0, 1e-6, "初始移动能力满值")
	var acq: Dictionary = sys.acquire(st, "physical", "accident", "heavy")
	check(bool(acq["ok"]), "获取肢体残障")
	check_near(sys.mobility(st), 0.25, 1e-6, "重度肢体大幅降低移动")
	check(sys.restricted_verbs(st).has("奔跑"), "重度肢体限制奔跑")
	var base: Array = ["行走", "奔跑", "阅读", "社交"]
	var avail: Array = sys.available_verbs(st, base)
	check(not avail.has("奔跑"), "可用动词剔除受限项")
	check(avail.has("阅读"), "无关动词仍可用")
	check(not bool(sys.acquire(st, "bogus", "accident", "light")["ok"]), "未知类型被拒")
	check(not bool(sys.acquire(st, "physical", "bogus", "light")["ok"]), "未知来源被拒")


func _test_device_and_recovery() -> void:
	var sys = DisabilityScript.new()
	var st: Dictionary = sys.new_state()
	sys.acquire(st, "physical", "war", "heavy")
	var m0: float = sys.mobility(st)
	check(not bool(sys.fit_device(st, "hearing_aid")["ok"]), "不适用辅具被拒")
	var fit: Dictionary = sys.fit_device(st, "wheelchair")
	check(bool(fit["ok"]), "装配轮椅")
	check(int(fit["cost"]) > 0, "辅具花费")
	check(sys.mobility(st) > m0, "辅具提升移动能力")
	var m1: float = sys.mobility(st)
	var rec: Dictionary = sys.surgery_recovery(st, 0.5)
	check(bool(rec["ok"]), "康复训练/手术成功")
	check(float(rec["recovery"]) > 0.0, "记录康复进度")
	check(sys.mobility(st) >= m1, "康复部分恢复能力")
	check(not bool(sys.fit_device(st, "bogus")["ok"]), "未知辅具被拒")


func _test_elderly_care() -> void:
	var sys = DisabilityScript.new()
	var st: Dictionary = sys.new_state()
	var pen: Dictionary = sys.retirement_pension(10000000.0, 40.0)
	check_eq(int(pen["monthly"]), 6000000, "退休金按替代率")
	check_near(float(pen["replacement_rate"]), 0.6, 1e-6, "四十年达六成替代率")
	sys.enroll_social_security(st, 30.0)
	check_near(float(st["retirement_years"]), 30.0, 1e-6, "社保年限")
	check(not bool(sys.choose_care_mode(st, "bogus")["ok"]), "未知养老模式被拒")
	sys.choose_care_mode(st, "institution_care")
	var outcome: Dictionary = sys.care_outcome(st, 12.0)
	check(bool(outcome["ok"]), "机构养老结算")
	check(int(outcome["cost"]) > 0, "养老财务成本")
	var hos: Dictionary = sys.hospice_care(st, 0.9)
	check(bool(hos["ok"]), "临终关怀")
	check(float(hos["comfort"]) > 0.8, "高质量临终舒适")


func _test_caregiver() -> void:
	var sys = DisabilityScript.new()
	var st: Dictionary = sys.new_state()
	var cost: Dictionary = sys.caregiver_cost(st, 365.0, {"mode": "home_care"})
	check(int(cost["financial_cost"]) > 0, "护理财务成本")
	check(float(cost["emotional_cost"]) > 0.0, "护理情感成本")
	var bad: Dictionary = sys.caregiver_event(0.1, {"roll": 0.0})
	check(bool(bad["ok"]), "护工事件结算")
	check(str(bad["incident"]) != "", "低质量触发失职/虐待")
	var held: Dictionary = sys.hold_accountable(bad)
	check(bool(held["ok"]), "追责成立")
	check(int(held["compensation"]) > 0, "追责赔偿")
	var good: Dictionary = sys.caregiver_event(1.0, {"roll": 0.0})
	check_eq(str(good["incident"]), "", "高质量无事故")
	check(not bool(sys.hold_accountable(good)["ok"]), "无事故不追责")


func _test_cognitive_guardianship() -> void:
	var sys = DisabilityScript.new()
	var severe: Dictionary = sys.new_state()
	sys.acquire(severe, "intellectual", "illness", "heavy")
	check(sys.has_cognitive_impairment(severe), "重度智力障碍为认知障碍")
	check(not sys.decision_capacity(severe), "重度丧失决策能力")
	check(not sys.is_will_valid(severe), "丧失决策能力遗嘱无效")
	var guard: Dictionary = sys.establish_guardianship(severe, "child_1")
	check(bool(guard["ok"]), "引入监护制度")
	check_eq(str(severe["guardian"]), "child_1", "记录监护人")
	var mild: Dictionary = sys.new_state()
	sys.acquire(mild, "intellectual", "congenital", "light")
	check(sys.decision_capacity(mild), "轻度保留决策能力")
	check(not bool(sys.establish_guardianship(mild, "child_2")["ok"]), "有决策能力不设监护")


func _test_discrimination() -> void:
	var sys = DisabilityScript.new()
	var st: Dictionary = sys.new_state()
	sys.acquire(st, "physical", "illness", "heavy")
	var emp: float = sys.discrimination_penalty(st, "employment")
	var soc: float = sys.discrimination_penalty(st, "social")
	check(emp > 0.0, "残障影响就业")
	check(soc > 0.0, "残障影响社交")
	check(emp > soc, "就业歧视重于社交歧视")
	sys.set_accessible(st, true)
	check(sys.mobility(st) > 0.25, "无障碍场所减少惩罚")
