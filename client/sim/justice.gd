class_name JusticeSystem
extends RefCounted
## 刑事司法全流程（R23；design D12）。
##
## 报警→调查→被捕→审讯→保释→委托律师→起诉→庭审→判决→罚款/监禁/缓刑/出狱→上诉→再审；
## 多维证据（物证/人证/监控/电子/供词）强度决定定罪与量刑，允许销毁/伪造/串供；
## 律师水平、关系网、证据充分度与舆论共同影响判决；覆盖罚金/缓刑/监禁/无期/死刑刑种与国别差异；
## 支持认罪协商、自辩、冤假错案与再审。

const BaselineScript = preload("res://sim/baseline.gd")

const CrimeScript = preload("res://sim/crime.gd")

const EVIDENCE_KINDS: Array = ["physical", "witness", "surveillance", "digital", "confession"]
const EVIDENCE_WEIGHTS: Dictionary = {"physical": 0.30, "witness": 0.20, "surveillance": 0.15, "digital": 0.15, "confession": 0.20}
const EVIDENCE_NAMES: Dictionary = {"physical": "物证", "witness": "人证", "surveillance": "监控", "digital": "电子记录", "confession": "供词"}

const STAGES: Array = ["report", "investigate", "arrest", "interrogate", "prosecute", "trial", "sentence", "appeal"]
const SENTENCE_TYPES: Array = ["fine", "probation", "prison", "life", "death"]
const LAWYER_FEE_PER_LEVEL: int = BaselineScript.JUSTICE_LAWYER_FEE_PER_LEVEL


func new_case(crime: String, suspect: String, region: String) -> Dictionary:
	var ev: Dictionary = {}
	for k in EVIDENCE_KINDS:
		ev[k] = 0.0
	return {"crime": crime, "suspect": suspect, "region": region, "evidence": ev, "stage": "report", "detained": false, "lawyer": 0, "public_opinion": 0.0, "plea": false, "wrongful": false}


func report(case: Dictionary) -> Dictionary:
	case["stage"] = "report"
	return {"ok": true, "stage": "report"}


func add_evidence(case: Dictionary, kind: String, strength: float) -> void:
	if not EVIDENCE_KINDS.has(kind):
		return
	var ev: Dictionary = case["evidence"]
	ev[kind] = clampf(float(ev.get(kind, 0.0)) + strength, 0.0, 1.0)


## 调查：按技能采集多维证据（R23.2、R23.8）。
func investigate(case: Dictionary, skill: float, rng = null) -> Dictionary:
	case["stage"] = "investigate"
	var gained: Array = []
	for k in EVIDENCE_KINDS:
		var roll: float = rng.next_float() if rng != null else 0.0
		if roll < clampf(0.3 + skill / 40.0, 0.1, 0.8):
			add_evidence(case, k, 0.1 + (rng.next_float() if rng != null else 0.0) * 0.3)
			gained.append(k)
	return {"ok": true, "gained": gained, "score": evidence_score(case)}


## 证据强度加权 0..1（R23.8）。
func evidence_score(case: Dictionary) -> float:
	var ev: Dictionary = case.get("evidence", {})
	var total: float = 0.0
	for k in EVIDENCE_KINDS:
		total += float(EVIDENCE_WEIGHTS[k]) * float(ev.get(k, 0.0))
	return clampf(total, 0.0, 1.0)


## 干预证据（R23.2）：destroy 销毁 / forge 伪造 / collude 串供。
func tamper(case: Dictionary, kind: String, action: String, skill: float, rng = null) -> Dictionary:
	if not EVIDENCE_KINDS.has(kind):
		return {"ok": false, "reason": "unknown_kind"}
	var prob: float = clampf(0.4 + skill / 40.0, 0.05, 0.95)
	var roll: float = rng.next_float() if rng != null else 1.0
	var success: bool = roll < prob
	var ev: Dictionary = case["evidence"]
	var exposed: bool = (rng.next_float() if rng != null else 1.0) < 0.1
	if success:
		if action == "destroy":
			ev[kind] = clampf(float(ev[kind]) - 0.5, 0.0, 1.0)
		elif action == "forge":
			ev[kind] = clampf(float(ev[kind]) + 0.3, 0.0, 1.0)
		elif action == "collude":
			ev["witness"] = clampf(float(ev["witness"]) - 0.3, 0.0, 1.0)
			ev["confession"] = clampf(float(ev["confession"]) - 0.2, 0.0, 1.0)
	return {"ok": true, "success": success, "exposed": exposed, "score": evidence_score(case)}


func arrest(case: Dictionary, rng = null) -> Dictionary:
	case["stage"] = "arrest"
	case["detained"] = true
	return {"ok": true, "detained": true}


## 审讯（R23.2）：压力越高越易取得供词，但逼供增加冤案风险。
func interrogate(case: Dictionary, pressure: float, rng = null) -> Dictionary:
	case["stage"] = "interrogate"
	var conf_prob: float = clampf(pressure * 0.6, 0.05, 0.95)
	var roll: float = rng.next_float() if rng != null else 1.0
	var got_confession: bool = roll < conf_prob
	if got_confession:
		add_evidence(case, "confession", 0.4)
	var coercive: bool = pressure > 0.7 and (rng.next_float() if rng != null else 1.0) < 0.3
	if coercive:
		case["wrongful"] = true
	return {"ok": true, "confession": got_confession, "coercive": coercive, "score": evidence_score(case)}


## 保释（R23.1）：缴纳保证金，重罪或高风险不批。
func bail(case: Dictionary, wealth: int, severity: float) -> Dictionary:
	var amount: int = int(round(severity * 1000000.0))
	if severity >= 0.8 or wealth < amount:
		return {"ok": true, "granted": false, "amount": amount}
	case["detained"] = false
	return {"ok": true, "granted": true, "amount": amount}


func hire_lawyer(case: Dictionary, level: int) -> Dictionary:
	case["lawyer"] = clampi(level, 0, 5)
	return {"ok": true, "level": int(case["lawyer"]), "cost": int(case["lawyer"]) * LAWYER_FEE_PER_LEVEL}


## 认罪协商（R23.9）：定罪但减轻量刑。
func plea_bargain(case: Dictionary) -> Dictionary:
	case["plea"] = true
	return {"ok": true, "plea": true, "discount": 0.3}


## 庭审（R23.3）：证据、律师、舆论与认罪共同决定判决。
func trial(case: Dictionary, prosecutor_level: int, law_scale: float = 1.0, death_penalty: bool = true, rng = null) -> Dictionary:
	case["stage"] = "trial"
	var score: float = evidence_score(case)
	var lawyer: int = int(case.get("lawyer", 0))
	var convict_prob: float = clampf(score * 0.8 + 0.1 + float(prosecutor_level) * 0.04 - float(lawyer) * 0.06 + float(case.get("public_opinion", 0.0)) * 0.1, 0.02, 0.99)
	if bool(case.get("plea", false)):
		convict_prob = 0.99
	var roll: float = rng.next_float() if rng != null else 0.0
	var guilty: bool = roll < convict_prob
	var verdict: Dictionary = {"guilty": guilty, "convict_probability": convict_prob, "score": score}
	if guilty:
		verdict["sentence"] = sentence(case, score, law_scale, death_penalty)
	case["stage"] = "sentence"
	return verdict


## 量刑（R23.10）：罚金/缓刑/监禁/无期/死刑，国别 law_scale 与认罪/自首修正。
func sentence(case: Dictionary, score: float, law_scale: float = 1.0, death_penalty: bool = true) -> Dictionary:
	var crime: String = str(case.get("crime", ""))
	var c: Dictionary = CrimeScript.CRIMES.get(crime, {})
	var penalty: Dictionary = c.get("penalty", {"days": [0, 0], "fine": [0, 0]})
	var days_range: Array = penalty.get("days", [0, 0])
	var fine_range: Array = penalty.get("fine", [0, 0])
	var mid_days: float = (float(days_range[0]) + float(days_range[1])) / 2.0 * law_scale * (0.5 + score)
	var mid_fine: float = (float(fine_range[0]) + float(fine_range[1])) / 2.0 * (0.5 + score)
	if bool(case.get("plea", false)):
		mid_days *= 0.7
		mid_fine *= 0.8
	var s: Dictionary = {"type": "fine", "days": 0, "fine": int(round(mid_fine))}
	if mid_days <= 0.0:
		return s
	if mid_days <= 30.0:
		s["type"] = "probation"
		s["days"] = int(round(mid_days))
		s["fine"] = int(round(mid_fine * 0.5))
		return s
	if death_penalty and score >= 0.9 and mid_days >= 7300.0:
		s["type"] = "death"
		s["days"] = 0
		s["fine"] = 0
		return s
	if mid_days >= 18250.0:
		s["type"] = "life"
		s["days"] = 0
		return s
	s["type"] = "prison"
	s["days"] = int(round(mid_days))
	return s


## 上诉（R23/ R52.3）。
func appeal(case: Dictionary, verdict: Dictionary, lawyer_level: int, rng = null) -> Dictionary:
	case["stage"] = "appeal"
	var prob: float = clampf(0.25 + clampf(lawyer_level, 0, 5) * 0.08, 0.1, 0.75)
	var roll: float = rng.next_float() if rng != null else 1.0
	if bool(verdict.get("guilty", false)) and roll < prob:
		return {"ok": true, "overturned": true, "verdict": {"guilty": false}}
	return {"ok": true, "overturned": false, "verdict": verdict}


## 再审（冤假错案，R23.12）。
func retrial(case: Dictionary, new_evidence: float, rng = null) -> Dictionary:
	if not bool(case.get("wrongful", false)):
		return {"ok": false, "reason": "not_wrongful"}
	var roll: float = rng.next_float() if rng != null else 0.0
	var exonerated: bool = roll < clampf(new_evidence, 0.0, 1.0)
	return {"ok": true, "exonerated": exonerated}
