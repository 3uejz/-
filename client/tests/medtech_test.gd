extends "res://tests/test_base.gd"
## 医疗、生命科技与医药产业测试（任务 38.1；R89；design D45）。
## 覆盖：医保与分级诊疗、手术并发症风险因素单调、并发症/事故责任赔偿、
## 伦理与法律约束、医药管线、用药风险与欺诈、区域医疗差异。

const MedScript = preload("res://sim/medtech.gd")
const RngScript = preload("res://sim/rng.gd")


func _suite_name() -> String:
	return "medtech"


func run_tests() -> void:
	_test_region_and_insurance()
	_test_care_levels_and_referral()
	_test_visit_flow()
	_test_surgery_risk_monotonic()
	_test_complication_settlement()
	_test_medical_accident()
	_test_ethics_and_legal()
	_test_pharma_pipeline()
	_test_drug_risks()


func _test_region_and_insurance() -> void:
	var sys = MedScript.new()
	var low: Dictionary = sys.new_region(1000000, {"medical_level": 0.5})
	var high: Dictionary = sys.new_region(1000000, {"medical_level": 3.0})
	var ml: Dictionary = sys.region_metrics(low)
	var mh: Dictionary = sys.region_metrics(high)
	check(float(mh["cure_rate"]) > float(ml["cure_rate"]), "医疗水平提升治愈率")
	check(float(mh["life_expectancy"]) > float(ml["life_expectancy"]), "医疗水平提升人均寿命")
	check(float(mh["cost_index"]) > float(ml["cost_index"]), "医疗水平提升就医成本")
	# 医保：基层报销比例高于三级。
	var p: Dictionary = sys.reimburse(100000, "primary")
	var t: Dictionary = sys.reimburse(100000, "tertiary")
	check(int(p["reimbursed"]) > int(t["reimbursed"]), "基层报销高于三级")
	check_eq(int(p["cost"]) - int(p["reimbursed"]), int(p["self_pay"]), "自付 = 费用 - 报销")
	var ded: Dictionary = sys.reimburse(100000, "secondary", {"deductible": 20000})
	check(int(ded["reimbursed"]) < int(sys.reimburse(100000, "secondary")["reimbursed"]), "起付线降低报销")
	check(not bool(sys.reimburse(1, "bogus")["ok"]), "未知分级被拒")


func _test_care_levels_and_referral() -> void:
	var sys = MedScript.new()
	var region: Dictionary = sys.new_region(500000)
	# 基层无心血管科，需转诊。
	var reg: Dictionary = sys.register(region, "primary", "cardiology")
	check(bool(reg["referral_needed"]), "基层超能力科室需转诊")
	var reg2: Dictionary = sys.register(region, "tertiary", "cardiology")
	check(not bool(reg2["referral_needed"]), "三级可直接挂号心血管科")
	var up: Dictionary = sys.referral(region, "primary", "tertiary", "cardiology")
	check(bool(up["ok"]) and bool(up["accepted"]), "向上转诊被接受")
	check(not bool(sys.referral(region, "tertiary", "primary", "internal")["ok"]), "向下不算转诊")
	check(not bool(sys.register(region, "primary", "bogus")["ok"]), "未知科室被拒")


func _test_visit_flow() -> void:
	var sys = MedScript.new()
	var region: Dictionary = sys.new_region(1000000, {"medical_level": 2.0})
	var flow: Dictionary = sys.visit_flow(region, {
		"care_level": "secondary", "department": "internal", "exams": ["lab", "imaging"],
		"disease_key": "flu", "admit_days": 3.0,
	})
	var trace: Array = flow["trace"]
	check(trace.has("register") and trace.has("diagnosis") and trace.has("treatment"), "就医流程含挂号诊断治疗")
	check(int(flow["cost"]) > 0, "就医产生费用")
	check(int(flow["reimbursed"]) > 0, "就医产生报销")
	check_eq(int(flow["cost"]) - int(flow["reimbursed"]), int(flow["self_pay"]), "自付守恒")
	# 证据越强确诊概率越高。
	var d_low: Dictionary = sys.diagnose(region, 0.1)
	var d_high: Dictionary = sys.diagnose(region, 0.9)
	check(float(d_high["confidence"]) > float(d_low["confidence"]), "证据提升确诊概率")


func _test_surgery_risk_monotonic() -> void:
	var sys = MedScript.new()
	var base: float = sys.surgery_complication_risk({})
	# 患者因素抬高风险。
	check(sys.surgery_complication_risk({"age": 90.0}) > base, "高龄提升并发症风险")
	check(sys.surgery_complication_risk({"severity": 0.9}) > base, "重症提升并发症风险")
	check(sys.surgery_complication_risk({"comorbidity": 0.9}) > base, "合并症提升并发症风险")
	# 医护因素压低风险。
	check(sys.surgery_complication_risk({"surgeon_skill": 1.0}) < base, "主刀技能降低并发症风险")
	check(sys.surgery_complication_risk({"facility_level": 1.0}) < base, "机构等级降低并发症风险")
	# 综合：高危患者 + 高技能主刀，仍低于同等患者 + 低技能主刀。
	var high_risk_low_skill: float = sys.surgery_complication_risk({"age": 80.0, "severity": 0.8, "surgeon_skill": 0.1})
	var high_risk_high_skill: float = sys.surgery_complication_risk({"age": 80.0, "severity": 0.8, "surgeon_skill": 0.9})
	check(high_risk_high_skill < high_risk_low_skill, "同患者下高技能主刀风险更低")


func _test_complication_settlement() -> void:
	var sys = MedScript.new()
	var region: Dictionary = sys.new_region(1000000)
	var factors: Dictionary = {"age": 85.0, "severity": 0.9, "surgeon_skill": 0.1}
	var risk: float = sys.surgery_complication_risk(factors)
	check(risk > 0.0, "并发症风险为正")
	# 强制掷骰必定低于风险 → 出现并发症并结算赔偿。
	var worse: Dictionary = sys.perform_surgery(region, factors, {"roll": 0.0, "cost": 500000})
	check(bool(worse["complication"]), "低掷骰触发并发症")
	var settlement: Dictionary = worse.get("settlement", {})
	check(int(settlement.get("compensation", 0)) > 0, "并发症触发责任赔偿")
	check(float(settlement.get("liability", 0.0)) > 0.0, "并发症产生责任")
	# 强制高掷骰不出现并发症。
	var safe: Dictionary = sys.perform_surgery(region, factors, {"roll": 0.999})
	check(not bool(safe["complication"]), "高掷骰无并发症")
	check(not safe.has("settlement"), "无并发症无赔偿")
	# 过失越重赔偿越高。
	var light: Dictionary = sys.settle_complication(0.2, {"negligence": false})
	var heavy: Dictionary = sys.settle_complication(0.9, {"negligence": true})
	check(int(heavy["compensation"]) > int(light["compensation"]), "过失越重赔偿越高")


func _test_medical_accident() -> void:
	var sys = MedScript.new()
	var region: Dictionary = sys.new_region(1000000)
	var acc: Dictionary = sys.medical_accident(region, {"roll": 0.0, "severity": 0.6, "negligence": true})
	check(bool(acc["occurred"]), "低掷骰判定医疗事故发生")
	var settlement: Dictionary = acc.get("settlement", {})
	check(int(settlement.get("compensation", 0)) > 0, "医疗事故触发赔偿")
	check(bool(settlement.get("negligence", false)), "重大过失被认定")
	var no_acc: Dictionary = sys.medical_accident(region, {"roll": 0.999, "severity": 0.6})
	check(not bool(no_acc["occurred"]), "高掷骰不认定事故")
	# 医患纠纷：损害与不满越高冲突越强。
	var d1: Dictionary = sys.doctor_patient_dispute(0.2, {"dissatisfaction": 0.1})
	var d2: Dictionary = sys.doctor_patient_dispute(0.9, {"dissatisfaction": 0.9})
	check(float(d2["conflict_level"]) > float(d1["conflict_level"]), "损害不满提升冲突")
	check(bool(d2["litigation"]), "高冲突触发诉讼")


func _test_ethics_and_legal() -> void:
	var sys = MedScript.new()
	# 未过伦理不得移植。
	var denied: Dictionary = sys.high_end_procedure("organ_transplant", {"ethics_cleared": false, "legal_cleared": true})
	check(not bool(denied["ok"]), "未过伦理禁止器官移植")
	check_eq(str(denied["reason"]), "ethics_denied", "拒绝原因为伦理未过")
	# 未过法律不得基因编辑。
	var legal_denied: Dictionary = sys.high_end_procedure("gene_edit", {"ethics_cleared": true, "legal_cleared": false})
	check(not bool(legal_denied["ok"]), "未过法律禁止基因编辑")
	check_eq(str(legal_denied["reason"]), "legal_denied", "拒绝原因为法律未过")
	# 非法器官来源被拒。
	var illegal: Dictionary = sys.high_end_procedure("organ_transplant", {
		"ethics_cleared": true, "legal_cleared": true, "organ_source": "black_market"})
	check(not bool(illegal["ok"]), "非法器官来源被拒")
	check_eq(str(illegal["reason"]), "illegal_organ_source", "拒绝原因为非法来源")
	# 合法来源 + 双门通过 → 放行。
	var ok: Dictionary = sys.high_end_procedure("organ_transplant", {
		"ethics_cleared": true, "legal_cleared": true, "organ_source": "voluntary_donation", "roll": 0.999})
	check(bool(ok["ok"]), "合法合规器官移植放行")
	check(bool(ok["success"]), "高掷骰手术成功")
	check(not bool(sys.organ_source_check("compensated")["legal"]), "有偿交易器官不合法")
	check(bool(sys.organ_source_check("voluntary_donation")["legal"]), "自愿捐献合法")
	# 伦理审查阈值。
	check(not bool(sys.review_ethics("gene_edit", 0.3)["approved"]), "低分未通过伦理")
	check(bool(sys.review_ethics("gene_edit", 0.9)["approved"]), "高分通过伦理")


func _test_pharma_pipeline() -> void:
	var sys = MedScript.new()
	var co: Dictionary = sys.new_pharma_company({"money": 20000000})
	var start: Dictionary = sys.start_drug(co, "drug_a", {"startup_cost": 1000000})
	check(bool(start["ok"]), "新药立项成功")
	check_eq(str(start["stage"]), "discovery", "立项进入研发阶段")
	# 逐步推进至上市（强制低掷骰全部通过）。
	var stages: Array = []
	for i in 8:
		var adv: Dictionary = sys.pharma_advance(co, "drug_a", {"roll": 0.0})
		stages.append(str(adv["stage"]))
	check(stages.has("sales"), "管线可推进至销售阶段")
	var pipe: Dictionary = co["pipeline"]["drug_a"]
	check(bool(pipe["patent"]), "获批后取得专利")
	check(bool(pipe["approved"]), "上市即获批")
	# 生产与销售。
	var prod: Dictionary = sys.pharma_produce(co, "drug_a", 10.0, {"units_per_batch": 1000.0})
	check(int(prod["produced"]) > 0, "生产药品")
	var before: int = int(co["money"])
	var sell: Dictionary = sys.pharma_sell(co, "drug_a", 5000.0, 100)
	check(int(sell["revenue"]) > 0, "销售产生收入")
	check(int(co["money"]) > before, "销售收入入账")
	check(float(sell["patent_premium"]) > 1.0, "专利期内享有溢价")
	# 未上市药品不可销售。
	var co2: Dictionary = sys.new_pharma_company({})
	sys.start_drug(co2, "drug_b")
	check(not bool(sys.pharma_sell(co2, "drug_b", 1.0, 1)["ok"]), "未上市不可销售")


func _test_drug_risks() -> void:
	var sys = MedScript.new()
	# 耐药随用药天数上升。
	var r0: Dictionary = sys.drug_resistance(0.0)
	var r1: Dictionary = sys.drug_resistance(365.0, {"adherence": 0.5})
	check(float(r1["resistance"]) > float(r0["resistance"]), "用药越久耐药越高")
	check(not bool(r1["effective"]), "高耐药失效")
	# 副作用随剂量上升。
	var se_low: Dictionary = sys.drug_side_effect(0.1)
	var se_high: Dictionary = sys.drug_side_effect(2.0, {"susceptibility": 0.9})
	check(float(se_high["risk"]) > float(se_low["risk"]), "剂量提升副作用风险")
	check_eq(str(se_high["severity"]), "severe", "高剂量副作用严重")
	# 过度医疗。
	var over: Dictionary = sys.over_treatment(1000000, {"necessary_ratio": 0.5})
	check_eq(int(over["excess_cost"]), 500000, "过度医疗费用虚高")
	check(float(over["audit_risk"]) > 0.0, "过度医疗提高审计风险")
	# 保险欺诈：强制低掷骰被查处。
	var fraud: Dictionary = sys.insurance_fraud(1000000, {"fraud_ratio": 0.5, "roll": 0.0})
	check(bool(fraud["detected"]), "保险欺诈被查处")
	check(int(fraud["penalty"]) > 0, "欺诈被追缴处罚")
	# 试验丑闻。
	var co: Dictionary = sys.new_pharma_company({})
	sys.start_drug(co, "d")
	var scan: Dictionary = sys.trial_scandal(co, "d", {"severity": 0.8, "roll": 0.0})
	check(bool(scan["exposed"]), "试验丑闻曝光")
	check(int(scan["fine"]) > 0, "丑闻罚款")
