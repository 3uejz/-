class_name MedTechSystem
extends RefCounted
## 医疗、生命科技与医药产业（R89；design D45）。
##
## 覆盖：
##   - 就医流程：分科门诊 → 检查（化验/影像/病理/内镜）→ 诊断 → 治疗 → 手术 →
##     住院 → 康复 → 随访；含分级诊疗（基层/二级/三级）与医保报销；
##   - 高阶医疗：器官移植、辅助生殖、基因检测/编辑、靶向治疗、再生医学，
##     全部受伦理审查与法律约束；
##   - 医药产业：研发 → 临床前 → I/II/III 期临床 → 审批 → 专利 → 生产 → 销售，
##     含医药代表路径；
##   - 风险：手术/用药并发症、医疗事故、医患纠纷、药物副作用与耐药、
##     过度医疗与保险欺诈；
##   - 医疗资源与区域差异：区域医疗水平影响治愈率、人均寿命与就医成本；
##   - 边界：器官来源合法性、试验丑闻、假药。
##
## 设计取舍：
##   - 机构与区域均为纯数据 Dictionary，便于存读档与 headless 测试；
##   - 不重复病例引擎（medical.gd）与传染病（epidemic.gd）：病例 key 只作为入参，
##     本系统聚焦机构价值链、医保、产业与风险；
##   - 手术并发症概率对风险因素单调：年龄/合并症/严重度抬高、医护技能/机构等级压低；
##   - 一切随机由外部 roll/rng 注入，缺省确定化。

## 分级诊疗机构：报销比例、成本系数、能力等级与可开展科室。
const CARE_LEVELS: Dictionary = {
	"primary": {"name": "基层", "reimburse": 0.80, "cost_mult": 0.60, "capability": 1,
		"departments": ["internal", "pediatrics", "dermatology"]},
	"secondary": {"name": "二级", "reimburse": 0.60, "cost_mult": 1.00, "capability": 2,
		"departments": ["internal", "surgery", "pediatrics", "obgyn", "orthopedics", "ent"]},
	"tertiary": {"name": "三级", "reimburse": 0.45, "cost_mult": 1.40, "capability": 3,
		"departments": ["internal", "surgery", "pediatrics", "obgyn", "cardiology", "neurology",
			"oncology", "orthopedics", "dermatology", "ophthalmology", "ent", "psychiatry",
			"dental", "emergency"]},
}

const DEPARTMENTS: Dictionary = {
	"internal": "内科", "surgery": "外科", "pediatrics": "儿科", "obgyn": "妇产科",
	"cardiology": "心血管科", "neurology": "神经科", "oncology": "肿瘤科",
	"orthopedics": "骨科", "dermatology": "皮肤科", "ophthalmology": "眼科",
	"ent": "耳鼻喉科", "psychiatry": "精神科", "dental": "口腔科", "emergency": "急诊科",
}

## 检查化验影像：成本与证据价值（证据价值越高越易确诊）。
const EXAMS: Dictionary = {
	"lab": {"name": "化验", "cost": 20000, "value": 0.40},
	"imaging": {"name": "影像", "cost": 60000, "value": 0.60},
	"pathology": {"name": "病理", "cost": 120000, "value": 0.80},
	"endoscopy": {"name": "内镜", "cost": 90000, "value": 0.70},
}

const SERVICE_COSTS: Dictionary = {
	"register": 5000, "consult": 20000, "diagnose": 30000, "treatment": 80000,
	"surgery": 500000, "admission": 200000, "rehabilitation": 60000, "follow_up": 8000,
}

## 就医流程阶段。
const VISIT_STAGES: Array = ["register", "clinic", "examination", "diagnosis", "treatment",
	"surgery", "admission", "rehabilitation", "follow_up"]

## 高阶医疗类目：成本、风险、是否依赖器官来源。
const HIGH_END: Dictionary = {
	"organ_transplant": {"name": "器官移植", "cost": 5000000, "risk": 0.15, "needs_organ_source": true},
	"assisted_reproduction": {"name": "辅助生殖", "cost": 3000000, "risk": 0.05, "needs_organ_source": false},
	"gene_test": {"name": "基因检测", "cost": 500000, "risk": 0.00, "needs_organ_source": false},
	"gene_edit": {"name": "基因编辑", "cost": 8000000, "risk": 0.25, "needs_organ_source": false},
	"targeted_therapy": {"name": "靶向治疗", "cost": 2000000, "risk": 0.10, "needs_organ_source": false},
	"regenerative_medicine": {"name": "再生医学", "cost": 6000000, "risk": 0.20, "needs_organ_source": false},
}

## 器官来源合法性。
const ORGAN_SOURCES: Dictionary = {
	"voluntary_donation": {"name": "自愿捐献", "legal": true},
	"living_related": {"name": "亲属活体", "legal": true},
	"compensated": {"name": "有偿交易", "legal": false},
	"black_market": {"name": "黑市", "legal": false},
}

## 医药产业管线：研发 → 临床前 → I/II/III 期 → 审批 → 专利 → 生产 → 销售。
const PHARMA_PIPELINE: Array = ["discovery", "preclinical", "phase1", "phase2", "phase3",
	"approval", "patent", "production", "sales"]
const PHARMA_STAGE_NAMES: Dictionary = {
	"discovery": "研发", "preclinical": "临床前", "phase1": "I 期临床", "phase2": "II 期临床",
	"phase3": "III 期临床", "approval": "审批", "patent": "专利", "production": "生产",
	"sales": "销售",
}
## 各阶段通过率（失败留在原阶段）。
const PHARMA_PASS: Dictionary = {
	"discovery": 0.60, "preclinical": 0.70, "phase1": 0.60, "phase2": 0.50,
	"phase3": 0.60, "approval": 0.80, "patent": 0.90, "production": 0.95,
}

## 医药产业链角色。
const PHARMA_ROLES: Dictionary = {
	"researcher": {"name": "研发", "wage": 1500000},
	"clinical": {"name": "临床", "wage": 1200000},
	"regulatory": {"name": "注册报批", "wage": 900000},
	"production": {"name": "生产", "wage": 700000},
	"medical_rep": {"name": "医药代表", "wage": 800000, "commission": 0.05},
}


func _roll(forced: float, rng) -> float:
	if forced >= 0.0:
		return clampf(forced, 0.0, 1.0)
	if rng != null:
		return rng.next_float()
	return 0.0


# --- 数据表 ---

func department_keys() -> Array:
	return DEPARTMENTS.keys()


func department_name(key: String) -> String:
	return str(DEPARTMENTS.get(key, key))


func care_level_keys() -> Array:
	return CARE_LEVELS.keys()


func care_level_def(key: String) -> Dictionary:
	if not CARE_LEVELS.has(key):
		return {}
	return (CARE_LEVELS[key] as Dictionary).duplicate(true)


func exam_keys() -> Array:
	return EXAMS.keys()


func exam_def(key: String) -> Dictionary:
	if not EXAMS.has(key):
		return {}
	return (EXAMS[key] as Dictionary).duplicate(true)


func high_end_keys() -> Array:
	return HIGH_END.keys()


func high_end_def(key: String) -> Dictionary:
	if not HIGH_END.has(key):
		return {}
	return (HIGH_END[key] as Dictionary).duplicate(true)


func organ_source_def(key: String) -> Dictionary:
	if not ORGAN_SOURCES.has(key):
		return {}
	return (ORGAN_SOURCES[key] as Dictionary).duplicate(true)


func pharma_stage_names() -> Dictionary:
	return PHARMA_STAGE_NAMES.duplicate(true)


# --- 区域医疗资源与差异 ---

## 新建区域医疗状态。medical_level 越高，治愈率与人均寿命越高、就医成本越高。
func new_region(population: int, opts: Dictionary = {}) -> Dictionary:
	var pop: float = maxf(1.0, float(population))
	var level: float = clampf(float(opts.get("medical_level", 1.0)), 0.3, 3.0)
	return {
		"population": population,
		"medical_level": level,
		"per_capita_income": maxi(0, int(opts.get("per_capita_income", 50000))),
		"beds": int(pop / 1000.0 * level),
		"doctors": int(pop / 500.0 * level),
		"insurance_fund": maxi(0, int(opts.get("insurance_fund", int(pop * 100)))),
		"cure_rate": 0.0, "life_expectancy": 0.0, "cost_index": 0.0,
	}


## 区域医疗指标：治愈率、人均寿命、就医成本指数。均对 medical_level 单调。
func region_metrics(region: Dictionary) -> Dictionary:
	var level: float = clampf(float(region.get("medical_level", 1.0)), 0.3, 3.0)
	var cure_rate: float = clampf(0.45 + 0.18 * level, 0.0, 0.98)
	var life_expectancy: float = clampf(70.0 + 6.0 * level, 55.0, 95.0)
	var cost_index: float = clampf(0.70 + 0.30 * level, 0.3, 2.0)
	region["cure_rate"] = cure_rate
	region["life_expectancy"] = life_expectancy
	region["cost_index"] = cost_index
	return {
		"ok": true, "medical_level": level, "cure_rate": cure_rate,
		"life_expectancy": life_expectancy, "cost_index": cost_index,
	}


# --- 医保报销与分级诊疗 ---

## 医保报销：报销额 = max(0, 费用 − 起付线) × 报销比例 × 参保覆盖系数。
func reimburse(cost: int, care_level: String, opts: Dictionary = {}) -> Dictionary:
	if not CARE_LEVELS.has(care_level):
		return {"ok": false, "reason": "unknown_care_level"}
	var base: float = float((CARE_LEVELS[care_level] as Dictionary)["reimburse"])
	var coverage: float = clampf(float(opts.get("coverage", 1.0)), 0.0, 1.0)
	var deductible: int = maxi(0, int(opts.get("deductible", 0)))
	var total: int = maxi(0, cost)
	var reimbursable: int = maxi(0, total - deductible)
	var reimbursed: int = int(round(float(reimbursable) * base * coverage))
	return {
		"ok": true, "care_level": care_level, "cost": total,
		"reimbursed": reimbursed, "self_pay": total - reimbursed,
		"reimbursement_rate": base,
	}


## 挂号门诊：基层无法直通超出其能力的科室，返回 referral_needed。
func register(region: Dictionary, care_level: String, department: String, opts: Dictionary = {}) -> Dictionary:
	if not CARE_LEVELS.has(care_level):
		return {"ok": false, "reason": "unknown_care_level"}
	if not DEPARTMENTS.has(department):
		return {"ok": false, "reason": "unknown_department"}
	var dept_list: Array = (CARE_LEVELS[care_level] as Dictionary)["departments"]
	var referral_needed: bool = not dept_list.has(department)
	var cost: int = _service_cost("register", care_level)
	var pay: Dictionary = reimburse(cost, care_level, opts)
	return {
		"ok": true, "stage": "register", "care_level": care_level, "department": department,
		"referral_needed": referral_needed, "cost": cost,
		"reimbursed": int(pay["reimbursed"]), "self_pay": int(pay["self_pay"]),
	}


## 转诊：由低层级转向高层级。
func referral(region: Dictionary, from_level: String, to_level: String, department: String) -> Dictionary:
	if not CARE_LEVELS.has(from_level) or not CARE_LEVELS.has(to_level):
		return {"ok": false, "reason": "unknown_care_level"}
	var from_cap: int = int((CARE_LEVELS[from_level] as Dictionary)["capability"])
	var to_cap: int = int((CARE_LEVELS[to_level] as Dictionary)["capability"])
	if to_cap <= from_cap:
		return {"ok": false, "reason": "not_upward_referral"}
	return {"ok": true, "from": from_level, "to": to_level, "department": department, "accepted": true}


## 检查化验影像：证据价值随机构能力提升。
func examine(region: Dictionary, care_level: String, exam: String, opts: Dictionary = {}) -> Dictionary:
	if not CARE_LEVELS.has(care_level):
		return {"ok": false, "reason": "unknown_care_level"}
	if not EXAMS.has(exam):
		return {"ok": false, "reason": "unknown_exam"}
	var cap: int = int((CARE_LEVELS[care_level] as Dictionary)["capability"])
	var cost: int = _service_cost(int((EXAMS[exam] as Dictionary)["cost"]), care_level)
	var value: float = clampf(float((EXAMS[exam] as Dictionary)["value"]) * (0.8 + 0.1 * float(cap)), 0.0, 1.0)
	var pay: Dictionary = reimburse(cost, care_level, opts)
	return {
		"ok": true, "stage": "examination", "exam": exam, "care_level": care_level,
		"evidence": value, "cost": cost,
		"reimbursed": int(pay["reimbursed"]), "self_pay": int(pay["self_pay"]),
	}


## 诊断：证据越强越可能确诊；机构能力提升确诊概率。
func diagnose(region: Dictionary, evidence: float, opts: Dictionary = {}) -> Dictionary:
	var level: float = clampf(float(region.get("medical_level", 1.0)), 0.3, 3.0)
	var ev: float = clampf(evidence, 0.0, 1.0)
	var confidence: float = clampf(0.2 + ev * 0.6 + (level - 1.0) * 0.1, 0.0, 0.98)
	var confirmed: bool = confidence >= float(opts.get("threshold", 0.6))
	return {
		"ok": true, "stage": "diagnosis", "evidence": ev,
		"confidence": confidence, "confirmed": confirmed,
	}


## 治疗：按病种与机构能力结算疗效。disease_key 仅为入参，不托管病例状态。
func treat(region: Dictionary, care_level: String, disease_key: String, opts: Dictionary = {}) -> Dictionary:
	if not CARE_LEVELS.has(care_level):
		return {"ok": false, "reason": "unknown_care_level"}
	var level: float = clampf(float(region.get("medical_level", 1.0)), 0.3, 3.0)
	var cost: int = _service_cost("treatment", care_level)
	var pay: Dictionary = reimburse(cost, care_level, opts)
	var efficacy: float = clampf(0.4 + 0.2 * level + float(opts.get("adherence", 0.5)) * 0.2, 0.0, 0.98)
	return {
		"ok": true, "stage": "treatment", "disease_key": disease_key, "care_level": care_level,
		"efficacy": efficacy, "cost": cost,
		"reimbursed": int(pay["reimbursed"]), "self_pay": int(pay["self_pay"]),
	}


## 住院：按日结算床位与护理成本。
func admit(region: Dictionary, care_level: String, days: float, opts: Dictionary = {}) -> Dictionary:
	if not CARE_LEVELS.has(care_level):
		return {"ok": false, "reason": "unknown_care_level"}
	var d: float = maxf(0.0, days)
	var cost: int = int(round(float(_service_cost("admission", care_level)) * d / 7.0))
	var pay: Dictionary = reimburse(cost, care_level, opts)
	return {
		"ok": true, "stage": "admission", "days": d, "cost": cost,
		"reimbursed": int(pay["reimbursed"]), "self_pay": int(pay["self_pay"]),
	}


## 康复：缩短后续病程，返回康复增益。
func rehab(region: Dictionary, days: float, opts: Dictionary = {}) -> Dictionary:
	var d: float = maxf(0.0, days)
	var level: float = clampf(float(region.get("medical_level", 1.0)), 0.3, 3.0)
	var gain: float = clampf(d / 30.0 * level * 0.1, 0.0, 1.0)
	return {"ok": true, "stage": "rehabilitation", "days": d, "recovery_gain": gain}


## 随访：监测复发风险。
func follow_up(region: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var level: float = clampf(float(region.get("medical_level", 1.0)), 0.3, 3.0)
	var relapse_risk: float = clampf(0.3 - level * 0.1 + float(opts.get("risk", 0.2)), 0.0, 1.0)
	return {"ok": true, "stage": "follow_up", "relapse_risk": relapse_risk, "next_visit_days": float(opts.get("interval_days", 30.0))}


## 完整就医流程封装：按 request 走一遍并汇总费用与报销。
func visit_flow(region: Dictionary, request: Dictionary) -> Dictionary:
	var care_level: String = str(request.get("care_level", "secondary"))
	var department: String = str(request.get("department", "internal"))
	var trace: Array = []
	var total_cost: int = 0
	var total_reimbursed: int = 0
	var reg: Dictionary = register(region, care_level, department, request)
	trace.append("register")
	total_cost += int(reg.get("cost", 0))
	total_reimbursed += int(reg.get("reimbursed", 0))
	var evidence: float = 0.0
	for exam in (request.get("exams", []) as Array):
		var ex: Dictionary = examine(region, care_level, str(exam), request)
		evidence = maxf(evidence, float(ex.get("evidence", 0.0)))
		total_cost += int(ex.get("cost", 0))
		total_reimbursed += int(ex.get("reimbursed", 0))
	trace.append("examination")
	var diag: Dictionary = diagnose(region, evidence, request)
	trace.append("diagnosis")
	var trt: Dictionary = treat(region, care_level, str(request.get("disease_key", "")), request)
	total_cost += int(trt.get("cost", 0))
	total_reimbursed += int(trt.get("reimbursed", 0))
	trace.append("treatment")
	var episode: Dictionary = {}
	if bool(request.get("surgery", false)):
		var surg: Dictionary = perform_surgery(region, request.get("surgery_factors", {}), request, null)
		episode["surgery"] = surg
		trace.append("surgery")
	if float(request.get("admit_days", 0.0)) > 0.0:
		var ad: Dictionary = admit(region, care_level, float(request.get("admit_days", 0.0)), request)
		total_cost += int(ad.get("cost", 0))
		total_reimbursed += int(ad.get("reimbursed", 0))
		trace.append("admission")
	trace.append("rehabilitation")
	trace.append("follow_up")
	return {
		"ok": true, "trace": trace, "diagnosis": diag,
		"cost": total_cost, "reimbursed": total_reimbursed, "self_pay": total_cost - total_reimbursed,
		"episode": episode,
	}


func _service_cost(base: Variant, care_level: String) -> int:
	var mult: float = float((CARE_LEVELS[care_level] as Dictionary)["cost_mult"])
	return int(round(float(base) * mult))


# --- 手术与并发症 ---

## 手术并发症风险：对风险因素单调。
##   age/severity/comorbidity 越高风险越高；surgeon_skill/facility_level 越高风险越低。
func surgery_complication_risk(factors: Dictionary) -> float:
	var base: float = maxf(0.0, float(factors.get("base_risk", 0.05)))
	var procedure_risk: float = clampf(float(factors.get("procedure_risk", 0.2)), 0.0, 1.0)
	var age: float = clampf(float(factors.get("age", 40.0)) / 100.0, 0.0, 1.0)
	var severity: float = clampf(float(factors.get("severity", 0.3)), 0.0, 1.0)
	var comorbidity: float = clampf(float(factors.get("comorbidity", 0.0)), 0.0, 1.0)
	var skill: float = clampf(float(factors.get("surgeon_skill", 0.5)), 0.0, 1.0)
	var facility: float = clampf(float(factors.get("facility_level", 0.5)), 0.0, 1.0)
	var patient_factor: float = age * 0.5 + severity * 0.3 + comorbidity * 0.4
	var mitigation: float = clampf(skill * 0.4 + facility * 0.2, 0.0, 0.6)
	var risk: float = (base + procedure_risk * 0.3) * (1.0 + patient_factor) * (1.0 - mitigation)
	return clampf(risk, 0.0, 0.95)


## 实施手术：按风险掷骰；出现并发症时同步结算责任与赔偿。
func perform_surgery(region: Dictionary, factors: Dictionary, opts: Dictionary = {}, rng = null) -> Dictionary:
	var risk: float = surgery_complication_risk(factors)
	var roll: float = _roll(float(opts.get("roll", -1.0)), rng)
	var complication: bool = roll < risk
	var cost: int = maxi(0, int(opts.get("cost", 500000)))
	var severity: float = clampf(float(opts.get("severity", risk)), 0.0, 1.0)
	var result: Dictionary = {
		"ok": true, "stage": "surgery", "risk": risk, "roll": roll,
		"complication": complication, "cost": cost,
	}
	if complication:
		result["settlement"] = settle_complication(severity, opts)
	return result


## 并发症/医疗事故责任结算：过失越重责任越大，赔偿随责任上升。
func settle_complication(severity: float, opts: Dictionary = {}) -> Dictionary:
	var sev: float = clampf(severity, 0.0, 1.0)
	var negligence: bool = bool(opts.get("negligence", true))
	var liability: float = clampf(sev * (1.0 if negligence else 0.4), 0.0, 1.0)
	var compensation: int = int(round(sev * float(opts.get("base_compensation", 500000.0)) * (0.5 + liability)))
	return {
		"ok": true, "severity": sev, "negligence": negligence,
		"liability": liability, "compensation": compensation,
	}


## 医疗事故：过失与损害程度共同决定责任与损失。
func medical_accident(region: Dictionary, opts: Dictionary = {}, rng = null) -> Dictionary:
	var severity: float = clampf(float(opts.get("severity", 0.5)), 0.0, 1.0)
	var negligence: bool = bool(opts.get("negligence", false))
	var occurred: bool = float(_roll(float(opts.get("roll", -1.0)), rng)) < severity
	var settlement: Dictionary = {}
	if occurred:
		var factors: Dictionary = (opts.get("factors", {}) as Dictionary).duplicate()
		factors["severity"] = severity
		settlement = settle_complication(surgery_complication_risk(factors) + severity * 0.3, {"negligence": negligence})
	return {"ok": true, "occurred": occurred, "severity": severity, "negligence": negligence, "settlement": settlement}


## 医患纠纷：损害与不满共同决定冲突等级；联动司法系统由上层处理。
func doctor_patient_dispute(severity: float, opts: Dictionary = {}) -> Dictionary:
	var sev: float = clampf(severity, 0.0, 1.0)
	var dissatisfaction: float = clampf(float(opts.get("dissatisfaction", 0.5)), 0.0, 1.0)
	var conflict: float = clampf(sev * 0.6 + dissatisfaction * 0.4, 0.0, 1.0)
	return {
		"ok": true, "conflict_level": conflict,
		"litigation": conflict >= float(opts.get("litigation_threshold", 0.5)),
		"compensation": int(round(conflict * float(opts.get("base_compensation", 300000.0)))),
	}


# --- 用药风险 ---

## 药物副作用：剂量与个体易感性越高副作用风险越高。
func drug_side_effect(dosage: float, opts: Dictionary = {}) -> Dictionary:
	var dose: float = clampf(float(dosage), 0.0, 2.0)
	var susceptibility: float = clampf(float(opts.get("susceptibility", 0.3)), 0.0, 1.0)
	var risk: float = clampf(dose * 0.3 * (0.5 + susceptibility), 0.0, 0.95)
	return {"ok": true, "risk": risk, "severity": ("severe" if risk >= 0.6 else ("moderate" if risk >= 0.3 else "mild"))}


## 耐药：长期用药与不规范使用提升耐药度。
func drug_resistance(usage_days: float, opts: Dictionary = {}) -> Dictionary:
	var days: float = maxf(0.0, usage_days)
	var adherence: float = clampf(float(opts.get("adherence", 0.7)), 0.0, 1.0)
	var resistance: float = clampf(days / 365.0 * (1.5 - adherence), 0.0, 1.0)
	return {"ok": true, "resistance": resistance, "effective": resistance < 0.7}


## 过度医疗：不必要项目带来费用虚高，并提高被审计风险。
func over_treatment(cost: int, opts: Dictionary = {}) -> Dictionary:
	var total: int = maxi(0, cost)
	var necessary_ratio: float = clampf(float(opts.get("necessary_ratio", 0.6)), 0.0, 1.0)
	var excess: int = int(round(float(total) * (1.0 - necessary_ratio)))
	var audit_risk: float = clampf((1.0 - necessary_ratio) * 0.8, 0.0, 1.0)
	return {"ok": true, "excess_cost": excess, "audit_risk": audit_risk}


## 保险欺诈：虚报理赔被审计发现则追缴并处罚。
func insurance_fraud(claim: int, opts: Dictionary = {}, rng = null) -> Dictionary:
	var amount: int = maxi(0, claim)
	var fraud_ratio: float = clampf(float(opts.get("fraud_ratio", 0.5)), 0.0, 1.0)
	var detect_prob: float = clampf(float(opts.get("detect_prob", 0.4)) + fraud_ratio * 0.3, 0.0, 0.95)
	var roll: float = _roll(float(opts.get("roll", -1.0)), rng)
	var detected: bool = roll < detect_prob
	var fraudulent: int = int(round(float(amount) * fraud_ratio))
	var penalty: int = int(round(float(fraudulent) * 2.0)) if detected else 0
	return {"ok": true, "fraudulent": fraudulent, "detected": detected, "penalty": penalty}


# --- 伦理与法律约束 ---

## 伦理审查：高风险类目须达到委员会通过阈值。
func review_ethics(kind: String, committee_score: float, opts: Dictionary = {}) -> Dictionary:
	if not HIGH_END.has(kind):
		return {"ok": false, "reason": "unknown_procedure"}
	var score: float = clampf(committee_score, 0.0, 1.0)
	var threshold: float = clampf(float(opts.get("threshold", 0.6)), 0.0, 1.0)
	var approved: bool = score >= threshold
	return {"ok": true, "kind": kind, "approved": approved, "score": score, "threshold": threshold}


## 器官来源合法性校验。
func organ_source_check(source: String, opts: Dictionary = {}) -> Dictionary:
	if not ORGAN_SOURCES.has(source):
		return {"ok": false, "reason": "unknown_organ_source"}
	var legal: bool = bool((ORGAN_SOURCES[source] as Dictionary)["legal"])
	return {"ok": legal, "source": source, "legal": legal, "name": str((ORGAN_SOURCES[source] as Dictionary)["name"])}


## 高阶医疗执行：伦理与法律双门；器官类目还须合法来源。
func high_end_procedure(kind: String, ctx: Dictionary = {}, rng = null) -> Dictionary:
	if not HIGH_END.has(kind):
		return {"ok": false, "reason": "unknown_procedure"}
	if not bool(ctx.get("ethics_cleared", false)):
		return {"ok": false, "reason": "ethics_denied", "kind": kind}
	if not bool(ctx.get("legal_cleared", false)):
		return {"ok": false, "reason": "legal_denied", "kind": kind}
	var def: Dictionary = HIGH_END[kind]
	if bool(def["needs_organ_source"]):
		var source: String = str(ctx.get("organ_source", ""))
		if source == "" or not ORGAN_SOURCES.has(source):
			return {"ok": false, "reason": "no_organ_source", "kind": kind}
		if not bool((ORGAN_SOURCES[source] as Dictionary)["legal"]):
			return {"ok": false, "reason": "illegal_organ_source", "kind": kind, "source": source}
	var technique: float = clampf(float(ctx.get("technique", 0.5)), 0.0, 1.0)
	var risk: float = clampf(float(def["risk"]) * (1.0 - technique * 0.5), 0.0, 0.95)
	var roll: float = _roll(float(ctx.get("roll", -1.0)), rng)
	var success: bool = roll >= risk
	var result: Dictionary = {
		"ok": true, "kind": kind, "name": str(def["name"]), "success": success,
		"risk": risk, "roll": roll, "cost": int(def["cost"]), "ethics_cleared": true,
	}
	if kind == "gene_test":
		result["genetic_risk"] = clampf(float(ctx.get("genetic_risk", 0.3)), 0.0, 1.0)
	return result


# --- 医药产业 ---

## 新建医药公司：资金、管线、团队与合规度。
func new_pharma_company(opts: Dictionary = {}) -> Dictionary:
	var staff: Dictionary = {}
	for r in PHARMA_ROLES.keys():
		staff[r] = 0
	return {
		"name": str(opts.get("name", "医药公司")),
		"money": maxi(0, int(opts.get("money", 10000000))),
		"pipeline": {},
		"staff": staff,
		"compliance": clampf(float(opts.get("compliance", 0.8)), 0.0, 1.0),
		"scandal": false,
	}


func hire_pharma(company: Dictionary, role: String, count: int) -> Dictionary:
	if not PHARMA_ROLES.has(role):
		return {"ok": false, "reason": "unknown_role"}
	var staff: Dictionary = company["staff"]
	staff[role] = int(staff.get(role, 0)) + maxi(0, count)
	return {"ok": true, "role": role, "count": int(staff[role])}


## 立项新药：进入研发阶段，扣除启动经费。
func start_drug(company: Dictionary, drug_id: String, opts: Dictionary = {}) -> Dictionary:
	var pipe: Dictionary = company["pipeline"]
	if pipe.has(drug_id):
		return {"ok": false, "reason": "already_exists"}
	var cost: int = maxi(0, int(opts.get("startup_cost", 1000000)))
	if int(company.get("money", 0)) < cost:
		return {"ok": false, "reason": "insufficient_funds", "cost": cost}
	company["money"] = int(company["money"]) - cost
	pipe[drug_id] = {
		"id": drug_id, "stage": PHARMA_PIPELINE[0], "patent": false,
		"approved": false, "stock": 0.0, "failed_attempts": 0,
		"quality": clampf(float(opts.get("quality", 0.5)), 0.0, 1.0),
	}
	return {"ok": true, "drug_id": drug_id, "stage": PHARMA_PIPELINE[0], "cost": cost}


## 推进管线一步：按阶段通过率掷骰，失败留在原阶段。
func pharma_advance(company: Dictionary, drug_id: String, opts: Dictionary = {}, rng = null) -> Dictionary:
	var pipe: Dictionary = company["pipeline"]
	if not pipe.has(drug_id):
		return {"ok": false, "reason": "unknown_drug"}
	var d: Dictionary = pipe[drug_id]
	var idx: int = PHARMA_PIPELINE.find(str(d["stage"]))
	if idx < 0 or idx >= PHARMA_PIPELINE.size() - 1:
		return {"ok": false, "reason": "terminal", "stage": str(d["stage"])}
	var stage: String = str(d["stage"])
	var pass_rate: float = clampf(float(PHARMA_PASS.get(stage, 0.6)) + (0.1 if bool(d.get("patent", false)) else 0.0), 0.0, 0.99)
	var roll: float = _roll(float(opts.get("roll", -1.0)), rng)
	if roll >= pass_rate:
		d["failed_attempts"] = int(d.get("failed_attempts", 0)) + 1
		return {"ok": true, "stage": stage, "advanced": false, "failed": true, "roll": roll, "pass_rate": pass_rate}
	var nxt: String = str(PHARMA_PIPELINE[idx + 1])
	d["stage"] = nxt
	if nxt == "patent":
		d["patent"] = true
	if nxt == "sales":
		d["approved"] = true
	return {
		"ok": true, "stage": nxt, "advanced": true, "failed": false,
		"roll": roll, "pass_rate": pass_rate,
	}


## 生产：需已获批或进入生产阶段。
func pharma_produce(company: Dictionary, drug_id: String, batches: float, opts: Dictionary = {}) -> Dictionary:
	var pipe: Dictionary = company["pipeline"]
	if not pipe.has(drug_id):
		return {"ok": false, "reason": "unknown_drug"}
	var d: Dictionary = pipe[drug_id]
	var idx: int = PHARMA_PIPELINE.find(str(d["stage"]))
	if idx < PHARMA_PIPELINE.find("production"):
		return {"ok": false, "reason": "not_in_production"}
	var qty: float = maxf(0.0, batches) * clampf(float(opts.get("units_per_batch", 1000.0)), 0.0, 100000.0)
	d["stock"] = float(d.get("stock", 0.0)) + qty
	return {"ok": true, "drug_id": drug_id, "produced": qty, "stock": float(d["stock"])}


## 销售：需进入销售阶段；专利保护期内享有溢价。
func pharma_sell(company: Dictionary, drug_id: String, units: float, unit_price: int, opts: Dictionary = {}) -> Dictionary:
	var pipe: Dictionary = company["pipeline"]
	if not pipe.has(drug_id):
		return {"ok": false, "reason": "unknown_drug"}
	var d: Dictionary = pipe[drug_id]
	if str(d["stage"]) != "sales":
		return {"ok": false, "reason": "not_on_market"}
	var stock: float = float(d.get("stock", 0.0))
	var sold: float = minf(maxf(0.0, units), stock)
	var premium: float = 1.3 if bool(d.get("patent", false)) else 1.0
	var revenue: int = int(round(sold * float(maxi(0, unit_price)) * premium))
	d["stock"] = stock - sold
	company["money"] = int(company.get("money", 0)) + revenue
	return {
		"ok": true, "drug_id": drug_id, "sold": sold, "revenue": revenue,
		"patent_premium": premium, "stock": float(d["stock"]),
	}


## 医药代表路径：提升销量，但激进推广带来合规风险与曝光。
func medical_rep(company: Dictionary, drug_id: String, effort: float, opts: Dictionary = {}, rng = null) -> Dictionary:
	if not (company["pipeline"] as Dictionary).has(drug_id):
		return {"ok": false, "reason": "unknown_drug"}
	var e: float = clampf(effort, 0.0, 1.0)
	var baseline: float = float(opts.get("baseline_units", 1000.0))
	var boost: float = baseline * (0.5 + e * 1.5)
	var compliance_risk: float = clampf(e * 0.4 + (1.0 - float(company.get("compliance", 0.8))) * 0.3, 0.0, 0.95)
	var roll: float = _roll(float(opts.get("roll", -1.0)), rng)
	var bribery_exposed: bool = roll < compliance_risk
	if bribery_exposed:
		company["compliance"] = clampf(float(company.get("compliance", 0.8)) - 0.2, 0.0, 1.0)
		company["scandal"] = true
	return {
		"ok": true, "drug_id": drug_id, "effort": e, "sales_boost": boost,
		"compliance_risk": compliance_risk, "bribery_exposed": bribery_exposed,
	}


## 试验丑闻：数据造假或致死事件曝光，药企声誉与资金受损。
func trial_scandal(company: Dictionary, drug_id: String, opts: Dictionary = {}, rng = null) -> Dictionary:
	var severity: float = clampf(float(opts.get("severity", 0.6)), 0.0, 1.0)
	var detect: float = clampf(float(opts.get("detect_prob", 0.5)), 0.0, 0.95)
	var roll: float = _roll(float(opts.get("roll", -1.0)), rng)
	var exposed: bool = roll < detect
	var fine: int = 0
	if exposed:
		fine = int(round(severity * float(opts.get("max_fine", 5000000.0))))
		company["money"] = maxi(0, int(company.get("money", 0)) - fine)
		company["compliance"] = clampf(float(company.get("compliance", 0.8)) - severity * 0.3, 0.0, 1.0)
		company["scandal"] = true
	return {"ok": true, "drug_id": drug_id, "exposed": exposed, "fine": fine, "severity": severity}


## 假药：非正规渠道药品被查获则没收并处罚。
func counterfeit_drug(opts: Dictionary = {}, rng = null) -> Dictionary:
	var scale: float = clampf(float(opts.get("scale", 0.5)), 0.0, 1.0)
	var detect: float = clampf(float(opts.get("detect_prob", 0.5)) + scale * 0.2, 0.0, 0.95)
	var roll: float = _roll(float(opts.get("roll", -1.0)), rng)
	var seized: bool = roll < detect
	var confiscated: int = int(round(scale * float(opts.get("goods_value", 1000000.0)))) if seized else 0
	var fine: int = confiscated * 2
	return {"ok": true, "seized": seized, "confiscated": confiscated, "fine": fine}


# --- 序列化 ---

func to_dict(state: Dictionary) -> Dictionary:
	return state.duplicate(true)


func from_dict(data: Dictionary) -> Dictionary:
	return data.duplicate(true)
