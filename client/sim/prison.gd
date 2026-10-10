class_name PrisonSystem
extends RefCounted
## 监狱生活与社会融入（R23.4–R23.6、R52.4–R52.7；design D12）。
##
## 覆盖劳动、探视、狱友关系与帮派博弈、违纪、减刑与假释、越狱尝试；
## 在监时世界继续推进；出狱保留案底并施加长期影响（就业歧视与再犯风险）。

const BaselineScript = preload("res://sim/baseline.gd")

const GANGS: Array = ["none", "order", "brotherhood", "lone"]
const GANG_NAMES: Dictionary = {"none": "中立", "order": "秩序帮", "brotherhood": "兄弟会", "lone": "独行"}

const PAROLE_BEHAVIOR_MIN: float = BaselineScript.PRISON_PAROLE_BEHAVIOR_MIN
const ESCAPE_BASE: float = BaselineScript.PRISON_ESCAPE_BASE
const RECIDIVISM_BASE: float = BaselineScript.PRISON_RECIDIVISM_BASE


func new_inmate(name: String, crime: String, sentence_days: int) -> Dictionary:
	return {
		"name": name, "crime": crime, "sentence_days": sentence_days,
		"days_remaining": sentence_days, "behavior": 50.0, "reduction": 0,
		"gang": "none", "gang_relation": 0.0, "violations": 0,
		"escaped": false, "released": false, "parole": false, "labor_income": 0,
	}


func _clamp100(v: float) -> float:
	return clampf(v, 0.0, 100.0)


## 劳动（R52.5）：提升表现并获得少量报酬。
func labor(inmate: Dictionary, hours: float, wage_per_hour: int = 500) -> Dictionary:
	if bool(inmate["released"]) or bool(inmate["escaped"]):
		return {"ok": false, "reason": "not_inside"}
	var inc: int = int(maxf(0.0, hours) * float(wage_per_hour))
	inmate["labor_income"] = int(inmate["labor_income"]) + inc
	inmate["behavior"] = _clamp100(float(inmate["behavior"]) + 1.0)
	return {"ok": true, "income": inc, "behavior": float(inmate["behavior"])}


## 探视（R52.5）：提振情绪。
func visit(inmate: Dictionary, visitor: String) -> Dictionary:
	inmate["behavior"] = _clamp100(float(inmate["behavior"]) + 2.0)
	return {"ok": true, "visitor": visitor, "behavior": float(inmate["behavior"])}


## 狱友互动与帮派博弈（R52.5）。
func interact(inmate: Dictionary, other: Dictionary, rng = null) -> Dictionary:
	var roll: float = rng.next_float() if rng != null else 0.0
	if roll < 0.5:
		inmate["gang_relation"] = clampf(float(inmate["gang_relation"]) + 5.0, -100.0, 100.0)
		return {"ok": true, "event": "befriend", "gang_relation": float(inmate["gang_relation"])}
	inmate["behavior"] = _clamp100(float(inmate["behavior"]) - 3.0)
	return {"ok": true, "event": "conflict", "behavior": float(inmate["behavior"])}


func join_gang(inmate: Dictionary, gang: String) -> Dictionary:
	if not GANGS.has(gang):
		return {"ok": false, "reason": "unknown_gang"}
	inmate["gang"] = gang
	return {"ok": true, "gang": gang, "name": GANG_NAMES[gang]}


## 违纪（R52.5）：表现下降，减刑受影响。
func violation(inmate: Dictionary) -> Dictionary:
	inmate["violations"] = int(inmate["violations"]) + 1
	inmate["behavior"] = _clamp100(float(inmate["behavior"]) - 15.0)
	return {"ok": true, "violations": int(inmate["violations"]), "behavior": float(inmate["behavior"])}


## 减刑（R23.5、R52.5）：以良好表现折抵。
func reduce_sentence(inmate: Dictionary, days: int) -> Dictionary:
	if float(inmate["behavior"]) < 70.0:
		return {"ok": false, "reason": "behavior_too_low"}
	inmate["reduction"] = int(inmate["reduction"]) + days
	inmate["days_remaining"] = maxi(0, int(inmate["days_remaining"]) - days)
	return {"ok": true, "days_remaining": int(inmate["days_remaining"]), "reduction": int(inmate["reduction"])}


## 假释（R52.5）。
func parole(inmate: Dictionary, served_ratio: float, rng = null) -> Dictionary:
	if float(inmate["behavior"]) < PAROLE_BEHAVIOR_MIN or served_ratio < 0.5:
		return {"ok": true, "granted": false}
	var prob: float = clampf((float(inmate["behavior"]) - PAROLE_BEHAVIOR_MIN) / 40.0, 0.0, 0.9)
	var roll: float = rng.next_float() if rng != null else 1.0
	if roll < prob:
		inmate["parole"] = true
		inmate["released"] = true
		return {"ok": true, "granted": true}
	return {"ok": true, "granted": false}


## 越狱（R23.5）。
func attempt_escape(inmate: Dictionary, skill: float, rng = null) -> Dictionary:
	var prob: float = clampf(ESCAPE_BASE + clampf(skill, 0.0, 20.0) / 100.0, 0.02, 0.6)
	var roll: float = rng.next_float() if rng != null else 1.0
	if roll < prob:
		inmate["escaped"] = true
		return {"ok": true, "escaped": true}
	inmate["behavior"] = _clamp100(float(inmate["behavior"]) - 20.0)
	return {"ok": true, "escaped": false, "behavior": float(inmate["behavior"])}


## 推进刑期。
func advance(inmate: Dictionary, days: int) -> Dictionary:
	if bool(inmate["released"]) or bool(inmate["escaped"]):
		return {"ok": false, "reason": "not_inside"}
	inmate["days_remaining"] = maxi(0, int(inmate["days_remaining"]) - days)
	if int(inmate["days_remaining"]) <= 0:
		inmate["released"] = true
		return {"ok": true, "released": true}
	return {"ok": true, "days_remaining": int(inmate["days_remaining"])}


## 出狱后的社会融入（R23.6、R52.7）：就业歧视与再犯风险。
func reintegrate(inmate: Dictionary, support: float = 0.0, rng = null) -> Dictionary:
	var discrimination: float = clampf(0.5 - clampf(support, 0.0, 100.0) / 200.0, 0.0, 0.5)
	var recidivism: float = clampf(RECIDIVISM_BASE + discrimination * 0.4 - clampf(support, 0.0, 100.0) / 500.0, 0.0, 0.9)
	var roll: float = rng.next_float() if rng != null else 1.0
	return {"employment_discrimination": discrimination, "recidivism_risk": recidivism, "reoffends": roll < recidivism}
