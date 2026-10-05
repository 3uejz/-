extends "res://tests/test_base.gd"
## 疾病库与就医流程测试（任务 17；R9；design D45）。

const MedicalScript = preload("res://sim/medical.gd")


class FixedRng:
	var seq: Array
	var i: int = 0
	func _init(s: Array) -> void:
		seq = s
	func next_float() -> float:
		var v: float = float(seq[i % seq.size()])
		i += 1
		return v


func _new_player() -> Dictionary:
	return {"attrs": {"physiological": {"health": 100.0, "stamina": 80.0}, "psychological": {"mood": 60.0}}}


func _suite_name() -> String:
	return "medical"


func run_tests() -> void:
	_test_catalog()
	_test_trigger_and_course()
	_test_untreated_decay()
	_test_visit()
	_test_surgery_and_high_order()


func _test_catalog() -> void:
	var sys = MedicalScript.new()
	check(sys.diseases_count() >= 25, "至少 25 种疾病")
	for key in ["cold", "flu", "pneumonia", "hepatitis", "diabetes", "cancer", "fracture", "dental_caries"]:
		check(MedicalScript.DISEASES.has(key), "覆盖疾病 %s" % key)
	var d: Dictionary = MedicalScript.DISEASES["cold"]
	for field in ["cause", "incubation_days", "course_days", "symptoms", "effects", "contagious", "treatments"]:
		check(d.has(field), "疾病字段 %s" % field)
	check_eq(MedicalScript.FACILITIES.size(), 5, "五类医疗机构")


func _test_trigger_and_course() -> void:
	var sys = MedicalScript.new()
	var player: Dictionary = _new_player()
	var r: Dictionary = sys.trigger("flu", 0)
	check(bool(r["ok"]), "触发病")
	check_eq(str(sys.case_of("flu")["phase"]), "incubating", "潜伏期")
	sys.advance(player, 1440 * 2)
	check_eq(str(sys.case_of("flu")["phase"]), "onset", "转为发作")
	sys.advance(player, 1440 * 20)
	check_eq(str(sys.case_of("flu")["phase"]), "recovered", "病程结束康复")
	# 传染性。
	check(not sys.infect({"immunity": 0.0}, "gastritis", 0), "非传染病不传播")
	check(not sys.infect({"immunity": 1.0}, "cold", 0), "免疫者不感染")


func _test_untreated_decay() -> void:
	var sys = MedicalScript.new()
	var player: Dictionary = _new_player()
	sys.trigger("appendicitis", 0, 1.0)
	sys.advance(player, 1440)
	check_eq(str(sys.case_of("appendicitis")["phase"]), "onset", "阑尾炎发作")
	sys.advance(player, 1440 * 10)
	check(float(player["attrs"]["physiological"]["health"]) < 100.0, "未治疗超 7 日扣健康")


func _test_visit() -> void:
	var sys = MedicalScript.new()
	sys.trigger("flu", 0)
	sys.advance(_new_player(), 1440 * 2)
	var visit: Dictionary = sys.visit("hospital", "consult", "flu", 0, FixedRng.new([0.99]))
	check(bool(visit["ok"]), "挂号看病成功")
	check_eq(int(visit["cost"]), 20000, "门诊费")
	check_eq(int(visit["reimbursed"]), 14000, "医保报销")
	check_eq(int(visit["self_pay"]), 6000, "自付")
	check(not bool(visit["misdiagnosis"]), "无 RNG 误诊")
	check(bool(sys.case_of("flu")["diagnosed"]), "确诊")
	# 买药缩短病程。
	var before: float = float(sys.case_of("flu")["course_remaining_days"])
	var med: Dictionary = sys.visit("pharmacy", "medicine", "flu", 0, null)
	check(bool(med["treated"]), "买药治疗")
	check(float(sys.case_of("flu")["course_remaining_days"]) < before, "病程缩短")
	# 服务不可用与机构校验。
	check_eq(str(sys.visit("pharmacy", "surgery", "flu")["reason"]), "service_unavailable", "药店无手术")
	check_eq(str(sys.visit("bogus", "consult")["reason"]), "unknown_facility", "未知机构")


func _test_surgery_and_high_order() -> void:
	var sys = MedicalScript.new()
	var s: Dictionary = sys.schedule_surgery("appendicitis", 0)
	check_eq(str(s["phase"]), "scheduled", "手术排期")
	var rng = FixedRng.new([0.99])
	var steps: int = 0
	while str(s["phase"]) != "done" and steps < 10:
		sys.advance_surgery(s, 100000, rng)
		steps += 1
	check_eq(str(s["phase"]), "done", "手术状态机走完")
	check(not bool(s["complications"]), "无并发症")
	# 体检。
	sys.trigger("cold", 0)
	sys.advance(_new_player(), 1440)
	check(sys.checkup().has("cold"), "体检发现病症")
	# 高阶医疗。
	check_eq(str(MedicalScript.new().organ_transplant(false)["reason"]), "ethics_denied", "移植需伦理许可")
	check(bool(MedicalScript.new().organ_transplant(true, FixedRng.new([0.0]))["ok"]), "伦理通过可移植")
	check(MedicalScript.new().assisted_reproduction(true, FixedRng.new([0.0]))["success"], "辅助生殖成功")
	check(MedicalScript.new().gene_test(0.7)["level"] == "high", "基因高风险")
	var ph: Dictionary = MedicalScript.new().pharma_advance("discovery", FixedRng.new([0.0]))
	check_eq(str(ph["stage"]), "preclinical", "研发管线推进")
