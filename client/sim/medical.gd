class_name MedicalSystem
extends RefCounted
## 疾病库、就医流程与高阶医疗（R9；design D45）。
##
## 覆盖：
##   - 25+ 疾病：病因、潜伏期、病程、症状、属性影响、传染性与治疗方案（R9.1）。
##   - 触发患病、状态栏病情与建议（R9.2）。
##   - 医院/诊所/药店/牙科/心理诊所的挂号、看病、住院、手术、买药、体检、医保报销（R9.3）。
##   - 治疗扣费并缩短病程（R9.4）；未治疗超 7 日每日扣健康（R9.5）。
##   - 高阶：分科手术状态机、器官移植、辅助生殖、基因检测、医药研发管线（D45）。
##
## 设计取舍：
##   - 疾病运行时状态保存在本实例 _cases；player.health.diseases 仅写 schema 允许字段。
##   - 医疗水平通过区域系数 medical_level 影响治愈率与成本。

## 疾病库（R9.1）。effects 为病程期间每日属性影响；treatments 为可用治疗方式。
const DISEASES: Dictionary = {
	"cold": {"name": "感冒", "cause": "病毒感染", "incubation_days": 1.0, "course_days": 7.0, "symptoms": ["流涕", "咳嗽", "低热"], "effects": {"health": -0.2}, "contagious": true, "treatments": ["medicine"]},
	"flu": {"name": "流感", "cause": "流感病毒", "incubation_days": 1.0, "course_days": 10.0, "symptoms": ["高热", "酸痛", "乏力"], "effects": {"health": -0.5, "stamina": -0.3}, "contagious": true, "treatments": ["medicine", "hospitalization"]},
	"pneumonia": {"name": "肺炎", "cause": "细菌/病毒感染", "incubation_days": 2.0, "course_days": 21.0, "symptoms": ["高热", "咳嗽", "呼吸困难"], "effects": {"health": -0.8, "stamina": -0.5}, "contagious": true, "treatments": ["medicine", "hospitalization"]},
	"tuberculosis": {"name": "肺结核", "cause": "结核分枝杆菌", "incubation_days": 30.0, "course_days": 180.0, "symptoms": ["咳嗽", "咯血", "盗汗", "消瘦"], "effects": {"health": -0.6, "stamina": -0.4}, "contagious": true, "treatments": ["medicine", "hospitalization"]},
	"hepatitis": {"name": "肝炎", "cause": "病毒/酒精", "incubation_days": 20.0, "course_days": 120.0, "symptoms": ["黄疸", "乏力", "肝区痛"], "effects": {"health": -0.5, "stamina": -0.3}, "contagious": true, "treatments": ["medicine", "hospitalization"]},
	"gastritis": {"name": "胃炎", "cause": "饮食/幽门螺杆菌", "incubation_days": 0.0, "course_days": 30.0, "symptoms": ["胃痛", "反酸", "腹胀"], "effects": {"health": -0.2, "mood": -0.1}, "contagious": false, "treatments": ["medicine"]},
	"appendicitis": {"name": "阑尾炎", "cause": "阑尾梗阻感染", "incubation_days": 0.0, "course_days": 14.0, "symptoms": ["转移性腹痛", "发热"], "effects": {"health": -1.0}, "contagious": false, "treatments": ["surgery", "hospitalization"]},
	"hypertension": {"name": "高血压", "cause": "遗传/生活方式", "incubation_days": 0.0, "course_days": 36500.0, "symptoms": ["头晕", "头痛"], "effects": {"health": -0.1}, "contagious": false, "treatments": ["medicine"]},
	"diabetes": {"name": "糖尿病", "cause": "胰岛素分泌/作用障碍", "incubation_days": 0.0, "course_days": 36500.0, "symptoms": ["多饮", "多尿", "消瘦"], "effects": {"health": -0.12, "stamina": -0.1}, "contagious": false, "treatments": ["medicine"]},
	"coronary": {"name": "冠心病", "cause": "冠状动脉硬化", "incubation_days": 0.0, "course_days": 36500.0, "symptoms": ["胸痛", "气短"], "effects": {"health": -0.15}, "contagious": false, "treatments": ["medicine", "surgery"]},
	"stroke": {"name": "中风", "cause": "脑血管意外", "incubation_days": 0.0, "course_days": 60.0, "symptoms": ["偏瘫", "言语障碍", "意识障碍"], "effects": {"health": -1.2, "stamina": -0.8}, "contagious": false, "treatments": ["hospitalization", "surgery"]},
	"cancer": {"name": "癌症", "cause": "细胞异常增殖", "incubation_days": 60.0, "course_days": 730.0, "symptoms": ["肿块", "消瘦", "疼痛"], "effects": {"health": -0.7, "stamina": -0.5}, "contagious": false, "treatments": ["surgery", "hospitalization"]},
	"asthma": {"name": "哮喘", "cause": "气道高反应", "incubation_days": 0.0, "course_days": 36500.0, "symptoms": ["喘息", "气促"], "effects": {"health": -0.1, "stamina": -0.15}, "contagious": false, "treatments": ["medicine"]},
	"allergy": {"name": "过敏", "cause": "过敏原", "incubation_days": 0.0, "course_days": 7.0, "symptoms": ["皮疹", "瘙痒", "喷嚏"], "effects": {"health": -0.15, "mood": -0.1}, "contagious": false, "treatments": ["medicine"]},
	"fracture": {"name": "骨折", "cause": "外伤", "incubation_days": 0.0, "course_days": 90.0, "symptoms": ["疼痛", "肿胀", "活动受限"], "effects": {"health": -0.3, "stamina": -0.6}, "contagious": false, "treatments": ["surgery", "hospitalization"]},
	"arthritis": {"name": "关节炎", "cause": "退行/免疫", "incubation_days": 0.0, "course_days": 36500.0, "symptoms": ["关节痛", "僵硬"], "effects": {"health": -0.1, "stamina": -0.2}, "contagious": false, "treatments": ["medicine"]},
	"migraine": {"name": "偏头痛", "cause": "神经血管", "incubation_days": 0.0, "course_days": 2.0, "symptoms": ["搏动性头痛", "畏光"], "effects": {"health": -0.1, "mood": -0.3}, "contagious": false, "treatments": ["medicine"]},
	"uti": {"name": "尿路感染", "cause": "细菌感染", "incubation_days": 1.0, "course_days": 14.0, "symptoms": ["尿频", "尿痛"], "effects": {"health": -0.2}, "contagious": false, "treatments": ["medicine"]},
	"anemia": {"name": "贫血", "cause": "营养/失血", "incubation_days": 0.0, "course_days": 90.0, "symptoms": ["乏力", "面色苍白"], "effects": {"health": -0.1, "stamina": -0.3}, "contagious": false, "treatments": ["medicine"]},
	"thyroid": {"name": "甲状腺疾病", "cause": "内分泌紊乱", "incubation_days": 0.0, "course_days": 36500.0, "symptoms": ["心悸", "体重变化", "情绪波动"], "effects": {"health": -0.1, "mood": -0.15}, "contagious": false, "treatments": ["medicine"]},
	"fatty_liver": {"name": "脂肪肝", "cause": "代谢/饮酒", "incubation_days": 0.0, "course_days": 36500.0, "symptoms": ["疲乏", "肝区不适"], "effects": {"health": -0.08}, "contagious": false, "treatments": ["medicine"]},
	"dental_caries": {"name": "龋齿", "cause": "细菌产酸", "incubation_days": 0.0, "course_days": 60.0, "symptoms": ["牙痛", "遇冷热敏感"], "effects": {"health": -0.05, "mood": -0.1}, "contagious": false, "treatments": ["dental"]},
	"periodontitis": {"name": "牙周炎", "cause": "牙周细菌", "incubation_days": 0.0, "course_days": 120.0, "symptoms": ["牙龈出血", "牙齿松动"], "effects": {"health": -0.06}, "contagious": false, "treatments": ["dental"]},
	"myopia": {"name": "近视", "cause": "眼轴变长", "incubation_days": 0.0, "course_days": 36500.0, "symptoms": ["视远模糊"], "effects": {}, "contagious": false, "treatments": ["surgery"]},
	"std": {"name": "性传播疾病", "cause": "病原体", "incubation_days": 7.0, "course_days": 45.0, "symptoms": ["局部症状", "皮疹"], "effects": {"health": -0.3, "mood": -0.2}, "contagious": true, "treatments": ["medicine"]},
}

## 医疗机构与服务（R9.3）。
const BaselineScript = preload("res://sim/baseline.gd")

const FACILITIES: Dictionary = BaselineScript.MEDICAL_FACILITIES

const SERVICE_COST: Dictionary = BaselineScript.MEDICAL_SERVICE_COST

const UNTREATED_FREE_DAYS: float = BaselineScript.MEDICAL_UNTREATED_FREE_DAYS
const UNTREATED_HEALTH_DECAY_PER_DAY: float = BaselineScript.MEDICAL_UNTREATED_HEALTH_DECAY_PER_DAY
const MISDIAGNOSIS_CHANCE: float = BaselineScript.MEDICAL_MISDIAGNOSIS_CHANCE

const SURGERY_PHASES: Array = ["scheduled", "prep", "operating", "recovery", "done"]

var _cases: Dictionary = {}          # disease_key -> runtime state
var _surgeries: Array = []
var _rng = null
var medical_level: float = 1.0


func _init(seed: int = 0) -> void:
	_set_rng(seed)


func _set_rng(seed: int) -> void:
	var RngScript = preload("res://sim/rng.gd")
	_rng = RngScript.new(seed)


func diseases_count() -> int:
	return DISEASES.size()


func case_of(key: String) -> Dictionary:
	return _cases.get(key, {})


func active_cases() -> Array:
	var out: Array = []
	for key in _cases.keys():
		var c: Dictionary = _cases[key]
		if str(c.get("phase", "")) == "incubating" or str(c.get("phase", "")) == "onset":
			out.append(c)
	return out


## 触发患病（R9.2）。
func trigger(key: String, now_minute: int, severity: float = 1.0) -> Dictionary:
	if not DISEASES.has(key):
		return {"ok": false, "reason": "unknown_disease"}
	var d: Dictionary = DISEASES[key]
	_cases[key] = {
		"key": key, "phase": "incubating", "severity": clampf(severity, 0.1, 3.0),
		"incubation_remaining_days": float(d["incubation_days"]),
		"course_remaining_days": float(d["course_days"]),
		"onset_minute": now_minute, "diagnosed": false, "treated": false,
		"untreated_days": 0.0, "started_minute": now_minute,
	}
	return {"ok": true, "key": key, "name": d["name"], "phase": "incubating"}


## 按传染性在接触者间传播。返回是否被感染。
func infect(contact: Dictionary, key: String, now_minute: int, proximity: float = 1.0) -> bool:
	if not DISEASES.has(key):
		return false
	if not bool(DISEASES[key].get("contagious", false)):
		return false
	if float(contact.get("immunity", 0.0)) >= 1.0:
		return false
	var roll: float = _rng.next_float() if _rng != null else 0.0
	if roll < clampf(0.3 * proximity, 0.0, 1.0):
		trigger(key, now_minute)
		return true
	return false


## 推进所有病程（传染病潜伏、转归、未治疗扣健康）。
func advance(player: Dictionary, minutes: int, rng = null) -> Dictionary:
	var days: float = float(minutes) / 1440.0
	var health_loss: float = 0.0
	var recovered: Array = []
	for key in _cases.keys():
		var c: Dictionary = _cases[key]
		var phase: String = str(c["phase"])
		if phase == "incubating":
			c["incubation_remaining_days"] = float(c["incubation_remaining_days"]) - days
			if float(c["incubation_remaining_days"]) <= 0.0:
				c["phase"] = "onset"
				c["onset_minute"] = int(c["started_minute"])
		elif phase == "onset":
			c["course_remaining_days"] = float(c["course_remaining_days"]) - days
			if not bool(c["treated"]):
				c["untreated_days"] = float(c["untreated_days"]) + days
				if float(c["untreated_days"]) > UNTREATED_FREE_DAYS:
					health_loss += (float(c["untreated_days"]) - UNTREATED_FREE_DAYS) * UNTREATED_HEALTH_DECAY_PER_DAY * float(c["severity"])
			if float(c["course_remaining_days"]) <= 0.0:
				c["phase"] = "recovered"
				recovered.append(key)
	if health_loss > 0.0:
		var phys: Dictionary = player["attrs"]["physiological"]
		phys["health"] = clampf(float(phys.get("health", 100.0)) - health_loss, 0.0, 100.0)
	return {"health_loss": health_loss, "recovered": recovered}


## 就医（R9.3、R9.4）：挂号/看病/住院/手术/买药/体检/退款由费用与报销结算。
## service 见 FACILITIES.services；disease 为可选目标病种。返回费用、报销与疗效。
func visit(facility: String, service: String, disease: String = "", now_minute: int = 0, rng = null) -> Dictionary:
	if not FACILITIES.has(facility):
		return {"ok": false, "reason": "unknown_facility"}
	var f: Dictionary = FACILITIES[facility]
	if not (f["services"] as Array).has(service):
		return {"ok": false, "reason": "service_unavailable"}
	var rnd = rng if rng != null else _rng
	var base: int = int(SERVICE_COST.get(service, 0))
	var cost: int = int(round(float(base) * float(f["cost_mult"])))
	var reimburse: int = int(round(float(cost) * float(f["reimburse"])))
	var result: Dictionary = {"ok": true, "facility": facility, "service": service, "cost": cost, "reimbursed": reimburse, "self_pay": cost - reimburse}

	if service == "consult" and disease != "":
		var mis: bool = (rnd.next_float() if rnd != null else 0.0) < (MISDIAGNOSIS_CHANCE / maxf(0.5, float(f["medical_level"])))
		result["misdiagnosis"] = mis
		result["diagnosis"] = "" if mis else disease
		if not mis and _cases.has(disease):
			_cases[disease]["diagnosed"] = true
			result["advice"] = _advice(disease)
	elif service == "medicine" and disease != "":
		if _cases.has(disease):
			_cases[disease]["treated"] = true
			_cases[disease]["course_remaining_days"] = float(_cases[disease]["course_remaining_days"]) * 0.5
			result["treated"] = true
	elif service == "dental" and disease != "":
		if _cases.has(disease):
			_cases[disease]["treated"] = true
			_cases[disease]["course_remaining_days"] = float(_cases[disease]["course_remaining_days"]) * 0.3
			result["treated"] = true
	elif service == "therapy":
		result["therapy"] = true
	elif service == "admit":
		result["admitted"] = true
		if disease != "" and _cases.has(disease):
			_cases[disease]["treated"] = true
	elif service == "surgery":
		result["surgery"] = schedule_surgery(disease, now_minute)
	elif service == "checkup":
		result["findings"] = checkup(rnd)
	return result


func _advice(key: String) -> Array:
	var d: Dictionary = DISEASES[key]
	return d["treatments"]


## 治疗某种疾病（R9.4）：标记已治，缩短病程。
func treat(key: String, method: String) -> Dictionary:
	if not DISEASES.has(key) or not _cases.has(key):
		return {"ok": false, "reason": "no_case"}
	var d: Dictionary = DISEASES[key]
	if not (d["treatments"] as Array).has(method):
		return {"ok": false, "reason": "unsupported"}
	_cases[key]["treated"] = true
	_cases[key]["course_remaining_days"] = float(_cases[key]["course_remaining_days"]) * 0.4
	return {"ok": true, "key": key, "method": method, "remaining_days": float(_cases[key]["course_remaining_days"])}


## 体检（D45）：返回可发现的病种。
func checkup(rng = null) -> Array:
	var rnd = rng if rng != null else _rng
	var found: Array = []
	for key in _cases.keys():
		var c: Dictionary = _cases[key]
		if str(c["phase"]) == "onset":
			found.append(key)
	return found


func schedule_surgery(disease: String, now_minute: int) -> Dictionary:
	var s: Dictionary = {"disease": disease, "phase": "scheduled", "minute": now_minute, "complications": false, "elapsed_minutes": 0}
	_surgeries.append(s)
	return s


## 推进手术状态机（D45）：scheduled→prep→operating→recovery→done，可能并发症。
func advance_surgery(surgery: Dictionary, minutes: int, rng = null) -> void:
	surgery["elapsed_minutes"] = int(surgery.get("elapsed_minutes", 0)) + minutes
	var idx: int = SURGERY_PHASES.find(str(surgery["phase"]))
	if idx < 0:
		return
	var step_minutes: int = [60, 60, 180, 2880, 0][idx]
	if step_minutes > 0 and int(surgery["elapsed_minutes"]) >= step_minutes:
		surgery["elapsed_minutes"] = 0
		surgery["phase"] = SURGERY_PHASES[idx + 1]
		if str(surgery["phase"]) == "operating":
			var roll: float = (rng.next_float() if rng != null else 0.0)
			if roll < 0.08:
				surgery["complications"] = true


func surgeries() -> Array:
	return _surgeries


# --- D45 高阶医疗 ---

## 器官移植：需伦理与法律许可，否则拒绝。
func organ_transplant(ethics_cleared: bool, rng = null) -> Dictionary:
	if not ethics_cleared:
		return {"ok": false, "reason": "ethics_denied"}
	var roll: float = (rng.next_float() if rng != null else 0.0)
	var ok: bool = roll >= 0.15
	return {"ok": true, "success": ok, "cost": 5000000, "rejection": not ok}


## 辅助生殖：受伦理门约束。
func assisted_reproduction(ethics_cleared: bool, rng = null) -> Dictionary:
	if not ethics_cleared:
		return {"ok": false, "reason": "ethics_denied"}
	var roll: float = (rng.next_float() if rng != null else 0.0)
	return {"ok": true, "success": roll < 0.6, "cost": 3000000}


## 基因检测：返回遗传风险等级（0..1）。
func gene_test(risk: float = 0.3) -> Dictionary:
	return {"ok": true, "genetic_risk": clampf(risk, 0.0, 1.0), "level": ("high" if risk >= 0.6 else ("medium" if risk >= 0.3 else "low"))}


## 医药研发管线（D45）：discovery→preclinical→phase1→phase2→phase3→approval→market。
const PHARMA_STAGES: Array = ["discovery", "preclinical", "phase1", "phase2", "phase3", "approval", "market"]


func pharma_advance(stage: String, rng = null) -> Dictionary:
	var idx: int = PHARMA_STAGES.find(stage)
	if idx < 0 or idx >= PHARMA_STAGES.size() - 1:
		return {"ok": false, "reason": "terminal_or_unknown"}
	var roll: float = (rng.next_float() if rng != null else 0.0)
	var pass_rate: float = 0.6
	if roll < pass_rate:
		return {"ok": true, "stage": PHARMA_STAGES[idx + 1], "failed": false}
	return {"ok": true, "stage": stage, "failed": true}
