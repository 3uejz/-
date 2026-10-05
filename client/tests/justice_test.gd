extends "res://tests/test_base.gd"
## 刑事司法全流程测试（任务 19；R23；design D12）。

const JusticeScript = preload("res://sim/justice.gd")


class FixedRng:
	var seq: Array
	var i: int = 0
	func _init(s: Array) -> void:
		seq = s
	func next_float() -> float:
		var v: float = float(seq[i % seq.size()])
		i += 1
		return v


func _suite_name() -> String:
	return "justice"


func run_tests() -> void:
	_test_case_and_evidence()
	_test_tamper()
	_test_interrogate()
	_test_trial()
	_test_sentence_types()
	_test_appeal_retrial()


func _test_case_and_evidence() -> void:
	var sys = JusticeScript.new()
	var case: Dictionary = sys.new_case("theft", "p1", "r1")
	check_eq(sys.evidence_score(case), 0.0, "初始零证据")
	check_eq(JusticeScript.EVIDENCE_KINDS.size(), 5, "五维证据")
	var r: Dictionary = sys.investigate(case, 20.0, FixedRng.new([0.0]))
	check(sys.evidence_score(case) > 0.0, "调查采集证据")
	check(int(r["gained"].size()) == 5, "采集全部维度")


func _test_tamper() -> void:
	var sys = JusticeScript.new()
	var case: Dictionary = sys.new_case("fraud", "p1", "r1")
	sys.add_evidence(case, "physical", 1.0)
	var before: float = float(case["evidence"]["physical"])
	var r: Dictionary = sys.tamper(case, "physical", "destroy", 20.0, FixedRng.new([0.0, 0.5]))
	check(bool(r["success"]), "销毁证据成功")
	check(float(case["evidence"]["physical"]) < before, "物证减少")
	var f: Dictionary = sys.tamper(case, "witness", "forge", 20.0, FixedRng.new([0.0, 0.5]))
	check(float(case["evidence"]["witness"]) > 0.0, "伪造证据")


func _test_interrogate() -> void:
	var sys = JusticeScript.new()
	var case: Dictionary = sys.new_case("robbery", "p1", "r1")
	var r: Dictionary = sys.interrogate(case, 0.9, FixedRng.new([0.0, 0.0]))
	check(bool(r["confession"]), "高压取得供词")
	check(bool(r["coercive"]), "逼供")
	check(bool(case["wrongful"]), "逼供造成冤案风险")


func _test_trial() -> void:
	var sys = JusticeScript.new()
	var case: Dictionary = sys.new_case("theft", "p1", "r1")
	for k in JusticeScript.EVIDENCE_KINDS:
		sys.add_evidence(case, k, 1.0)
	var v: Dictionary = sys.trial(case, 5, 1.0, true, FixedRng.new([0.0]))
	check(bool(v["guilty"]), "证据充分定罪")
	check(JusticeScript.SENTENCE_TYPES.has(str(v["sentence"]["type"])), "量刑类型合法")
	check(int(v["sentence"]["days"]) > 0, "判处监禁")
	# 认罪协商。
	var c2: Dictionary = sys.new_case("fraud", "p2", "r1")
	sys.add_evidence(c2, "physical", 0.5)
	sys.plea_bargain(c2)
	var v2: Dictionary = sys.trial(c2, 3, 1.0, true, FixedRng.new([0.5]))
	check(bool(v2["guilty"]), "认罪协商定罪")


func _test_sentence_types() -> void:
	var sys = JusticeScript.new()
	var fine: Dictionary = sys.sentence({"crime": "deceive"}, 1.0, 1.0, true)
	check_eq(str(fine["type"]), "fine", "罚金刑")
	var probation: Dictionary = sys.sentence({"crime": "disturbance"}, 0.5, 1.0, true)
	check_eq(str(probation["type"]), "probation", "缓刑")
	var prison: Dictionary = sys.sentence({"crime": "robbery"}, 1.0, 1.0, true)
	check_eq(str(prison["type"]), "prison", "监禁")
	var life: Dictionary = sys.sentence({"crime": "robbery"}, 1.0, 6.0, false)
	check_eq(str(life["type"]), "life", "无期")
	var death: Dictionary = sys.sentence({"crime": "robbery"}, 1.0, 3.0, true)
	check_eq(str(death["type"]), "death", "死刑（国别允许）")


func _test_appeal_retrial() -> void:
	var sys = JusticeScript.new()
	var case: Dictionary = sys.new_case("theft", "p1", "r1")
	var verdict: Dictionary = {"guilty": true}
	var a: Dictionary = sys.appeal(case, verdict, 5, FixedRng.new([0.0]))
	check(bool(a["overturned"]), "上诉翻案")
	# 再审。
	var wrongful: Dictionary = sys.new_case("injury", "p1", "r1")
	wrongful["wrongful"] = true
	var rt: Dictionary = sys.retrial(wrongful, 0.9, FixedRng.new([0.0]))
	check(bool(rt["exonerated"]), "再审平反")
	check(not bool(sys.retrial(sys.new_case("theft", "p", "r"), 0.9, FixedRng.new([0.0]))["ok"]), "非冤案不可再审")
