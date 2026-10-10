class_name ImmigrationSystem
extends RefCounted
## 移民与国籍（R53.6–R53.8、R25.3；design D13/D27）。
##
## 五类签证（工作/投资/亲属/留学/庇护），语言或积分条件；迁移、融入、国籍变更与
## 遣返风险；成功后切换法域（法律/税制/语言/社会关系成本）；处理双重国籍与兵役冲突。

## 国家档案（轻量）：语言、法域、税负、社保、兵役。
const BaselineScript = preload("res://sim/baseline.gd")

const COUNTRIES: Dictionary = {
	"CN": {"name": "中国", "language": "zh-CN", "legal_system": "civil_law", "tax": 0.2, "welfare": 0.4, "military_service": true, "dual_allowed": false},
	"US": {"name": "美国", "language": "en-US", "legal_system": "common_law", "tax": 0.28, "welfare": 0.3, "military_service": false, "dual_allowed": true},
	"JP": {"name": "日本", "language": "ja-JP", "legal_system": "civil_law", "tax": 0.3, "welfare": 0.5, "military_service": false, "dual_allowed": false},
	"GB": {"name": "英国", "language": "en-GB", "legal_system": "common_law", "tax": 0.32, "welfare": 0.55, "military_service": false, "dual_allowed": true},
	"FR": {"name": "法国", "language": "fr-FR", "legal_system": "civil_law", "tax": 0.35, "welfare": 0.6, "military_service": false, "dual_allowed": true},
	"DE": {"name": "德国", "language": "de-DE", "legal_system": "civil_law", "tax": 0.34, "welfare": 0.6, "military_service": true, "dual_allowed": false},
	"SG": {"name": "新加坡", "language": "en-SG", "legal_system": "common_law", "tax": 0.18, "welfare": 0.25, "military_service": true, "dual_allowed": false},
	"AU": {"name": "澳大利亚", "language": "en-AU", "legal_system": "common_law", "tax": 0.3, "welfare": 0.45, "military_service": false, "dual_allowed": true},
	"AE": {"name": "阿联酋", "language": "ar-AE", "legal_system": "islamic_law", "tax": 0.0, "welfare": 0.2, "military_service": true, "dual_allowed": false},
}

## 签证类型及条件：资金、语言等级(0-100)、积分、需学历。
const VISAS: Dictionary = {
	"work": {"name": "工作签证", "min_funds": 500000, "min_language": 40, "min_points": 40, "needs_degree": false},
	"investment": {"name": "投资签证", "min_funds": 5000000, "min_language": 0, "min_points": 20, "needs_degree": false},
	"family": {"name": "亲属签证", "min_funds": 0, "min_language": 0, "min_points": 0, "needs_degree": false},
	"study": {"name": "留学签证", "min_funds": 1000000, "min_language": 30, "min_points": 30, "needs_degree": false},
	"asylum": {"name": "庇护签证", "min_funds": 0, "min_language": 0, "min_points": 0, "needs_degree": false, "needs_persecution": true},
}

const MINUTES_PER_YEAR: int = BaselineScript.IMMIG_MINUTES_PER_YEAR
const NATURALIZE_YEARS: int = BaselineScript.IMMIG_NATURALIZE_YEARS


func countries() -> Array:
	return COUNTRIES.keys()


func country_info(code: String) -> Dictionary:
	return (COUNTRIES.get(code, {}) as Dictionary).duplicate()


func visa_types() -> Array:
	return VISAS.keys()


func new_status(nationality: String = "CN") -> Dictionary:
	return {"nationality": nationality, "residence": nationality, "visas": {}, "language": {}, "resident_years": 0.0, "integration": 0.0, "deported": false}


## 申请签证（R53.6）。profile: {funds, language, points, degree, persecution}。
func apply_visa(status: Dictionary, visa_type: String, profile: Dictionary, rng = null) -> Dictionary:
	if not VISAS.has(visa_type):
		return {"ok": false, "reason": "unknown_visa"}
	var v: Dictionary = VISAS[visa_type]
	if int(profile.get("funds", 0)) < int(v["min_funds"]):
		return {"ok": false, "reason": "insufficient_funds", "required": int(v["min_funds"])}
	if int(profile.get("language", 0)) < int(v["min_language"]):
		return {"ok": false, "reason": "language_below_requirement", "required": int(v["min_language"])}
	if int(profile.get("points", 0)) < int(v["min_points"]):
		return {"ok": false, "reason": "points_below_requirement", "required": int(v["min_points"])}
	if bool(v.get("needs_degree", false)) and not bool(profile.get("degree", false)):
		return {"ok": false, "reason": "degree_required"}
	if bool(v.get("needs_persecution", false)) and not bool(profile.get("persecution", false)):
		return {"ok": false, "reason": "no_persecution_claim"}
	var prob: float = clampf(0.5 + int(profile.get("points", 0)) / 200.0, 0.1, 0.95)
	var roll: float = rng.next_float() if rng != null else 0.0
	if roll < prob:
		status["visas"][visa_type] = {"granted": true, "country": profile.get("target", "")}
		return {"ok": true, "granted": true, "visa": visa_type}
	return {"ok": true, "granted": false, "probability": prob}


## 迁移与法域切换（R53.6、R53.7）。
func migrate(status: Dictionary, country: String) -> Dictionary:
	if not COUNTRIES.has(country):
		return {"ok": false, "reason": "unknown_country"}
	var from: String = str(status["residence"])
	status["residence"] = country
	status["resident_years"] = 0.0
	var info: Dictionary = COUNTRIES[country]
	var language_barrier: float = 1.0 - clampf(float(status.get("language", {}).get(info["language"], 0.0)), 0.0, 100.0) / 100.0
	status["integration"] = clampf(50.0 - language_barrier * 50.0, 0.0, 100.0)
	return {"ok": true, "from": from, "residence": country, "language_barrier": language_barrier, "jurisdiction": country_info(country), "social_cost": language_barrier}


## 融入（R53.6）：语言学习与社交投入降低孤立风险。
func integrate(status: Dictionary, effort: float, rng = null) -> Dictionary:
	status["integration"] = clampf(float(status["integration"]) + effort * 0.5, 0.0, 100.0)
	var roll: float = rng.next_float() if rng != null else 1.0
	var isolated: bool = float(status["integration"]) < 30.0 and roll < 0.5
	var returned: bool = isolated and roll < 0.3
	if returned:
		status["residence"] = str(status["nationality"])
	return {"ok": true, "integration": float(status["integration"]), "isolated": isolated, "returned": returned}


## 国籍变更（R53.6、R53.8）：居住年限 + 融入。
func naturalize(status: Dictionary) -> Dictionary:
	var target: String = str(status["residence"])
	var origin: String = str(status["nationality"])
	if target == origin:
		return {"ok": false, "reason": "already_citizen"}
	if float(status["resident_years"]) < float(NATURALIZE_YEARS):
		return {"ok": false, "reason": "insufficient_residency", "required_years": NATURALIZE_YEARS}
	if float(status["integration"]) < 60.0:
		return {"ok": false, "reason": "integration_too_low", "required": 60.0}
	var target_dual: bool = bool(COUNTRIES[target]["dual_allowed"])
	var origin_dual: bool = bool(COUNTRIES[origin]["dual_allowed"])
	var dual: bool = target_dual and origin_dual
	if not dual:
		status["nationality"] = target
	return {"ok": true, "nationality": status["nationality"], "dual": dual, "former": origin}


## 遣返风险（R53.6）。
func deportation_risk(status: Dictionary, illegal: bool) -> Dictionary:
	var base: float = 0.6 if illegal else 0.0
	var integration: float = clampf(float(status["integration"]), 0.0, 100.0)
	var prob: float = clampf(base * (1.0 - integration / 100.0), 0.0, 0.95)
	return {"risk": prob, "at_risk": prob > 0.3}


## 双重国籍与兵役义务冲突（R53.8）。
func military_conflict(status: Dictionary, age: int, gender: String) -> Dictionary:
	var dual: bool = str(status["nationality"]) != str(status["residence"])
	var origin_service: bool = bool((COUNTRIES.get(str(status["nationality"]), {}) as Dictionary).get("military_service", false))
	var reside_service: bool = bool((COUNTRIES.get(str(status["residence"]), {}) as Dictionary).get("military_service", false))
	var conflict: bool = dual and origin_service and reside_service and age >= 18 and age <= 27 and gender == "male"
	return {"conflict": conflict, "origin_service": origin_service, "residence_service": reside_service}


## 推进居住年限。
func advance(status: Dictionary, years: float) -> Dictionary:
	status["resident_years"] = float(status["resident_years"]) + maxf(0.0, years)
	return {"ok": true, "resident_years": float(status["resident_years"])}
