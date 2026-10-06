class_name SocialWelfareSystem
extends RefCounted
## 收养、寄养与社会救助（R85；design D41）。
##
## 覆盖：
##   - 收养寄养：收养/寄养/监护评估流程，资格审查与家庭匹配；
##   - 社会救助：流浪救助、低保申请、医疗救助、临时救助，资格审核与发放；
##   - 家庭变故：孤儿/被遗弃/父母失能时子女进入寄养或救助体系；
##   - 慈善：慈善基金/公益组织，募捐结算、支出透明与声誉；
##   - 社工：职业路径与个案跟进；
##   - 边界：收养资格被拒、虐待举报、善款挪用、救助依赖与脱困。
##
## 设计取舍：
##   - 申请、家庭、基金、个案均为纯数据 Dictionary，便于存读档与 headless 测试；
##   - 与家庭系统（D11）的衔接只通过入参/返回字典表达的“家庭接口”完成，
##     不在本系统内维护家庭成员列表，避免与 FamilySystem 重复；
##   - 资格审核为确定性门槛（年龄/收入/资产/有无犯罪等），拒绝原因逐条可查；
##   - 善款挪用与虐待举报由注入 roll 判定是否被查获/证实，缺省确定化。

const ADOPTION: String = "adoption"
const FOSTER: String = "foster"
const HOMELESS_RELIEF: String = "homeless_relief"
const DIBAO: String = "dibao"
const MEDICAL_AID: String = "medical_aid"
const TEMPORARY_AID: String = "temporary_aid"

const APPLICATION_KINDS: Array = ["adoption", "foster", "homeless_relief", "dibao", "medical_aid", "temporary_aid"]
const APPLICATION_NAMES: Dictionary = {
	"adoption": "收养", "foster": "寄养", "homeless_relief": "流浪救助",
	"dibao": "低保", "medical_aid": "医疗救助", "temporary_aid": "临时救助",
}

## 收养资格门槛。
const ADOPTION_REQUIREMENTS: Dictionary = {
	"min_age": 30, "max_age": 65, "min_income": 80000, "max_asset": 5000000,
	"no_criminal": true, "no_major_illness": true,
}

## 救助发放标准（最小货币单位）。
const ASSISTANCE_STANDARDS: Dictionary = {
	"homeless_relief": {"base_amount": 50000, "max_days": 30},
	"dibao": {"base_amount": 120000, "max_days": 365},
	"medical_aid": {"base_amount": 300000, "max_days": 180},
	"temporary_aid": {"base_amount": 100000, "max_days": 90},
}
## 低保家庭人均收入上限。
const DIBAO_INCOME_CEILING: float = 12000.0

const CRISIS_ORPHAN: String = "orphan"
const CRISIS_ABANDONED: String = "abandoned"
const CRISIS_GUARDIAN_DISABLED: String = "guardian_disabled"
const CRISIS_KINDS: Array = ["orphan", "abandoned", "guardian_disabled"]

## 社工职业路径。
const SOCIAL_WORKER_RANKS: Array = [
	{"key": "assistant", "name": "社工助理", "cases_required": 0, "salary": 4000},
	{"key": "social_worker", "name": "社工", "cases_required": 30, "salary": 6000},
	{"key": "senior", "name": "高级社工", "cases_required": 120, "salary": 9000},
	{"key": "supervisor", "name": "督导", "cases_required": 300, "salary": 14000},
]


func _roll(forced: float, rng) -> float:
	if forced >= 0.0:
		return clampf(forced, 0.0, 1.0)
	if rng != null:
		return rng.next_float()
	return 0.0


# --- 数据表 ---

func application_kinds() -> Array:
	return APPLICATION_KINDS.duplicate()


func application_name(key: String) -> String:
	return str(APPLICATION_NAMES.get(key, key))


func crisis_kinds() -> Array:
	return CRISIS_KINDS.duplicate()


func social_worker_ranks() -> Array:
	return SOCIAL_WORKER_RANKS.duplicate(true)


# --- 申请与资格审核 ---

func new_application(kind: String, applicant: Dictionary, opts: Dictionary = {}) -> Dictionary:
	return {
		"kind": kind,
		"applicant_id": str(applicant.get("id", "")),
		"child_id": str(opts.get("child_id", "")),
		"status": "pending",
		"reasons": [],
		"day": int(opts.get("day", 0)),
		"amount": maxi(0, int(opts.get("amount", 0))),
	}


## 资格审查：不同救助/收养类型走不同门槛，返回通过与否及逐条原因。
func review_qualification(application: Dictionary, applicant: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var kind: String = str(application.get("kind", ""))
	var reasons: Array = []
	match kind:
		ADOPTION:
			reasons = _review_adoption(applicant, opts)
		FOSTER:
			reasons = _review_foster(applicant, opts)
		DIBAO:
			reasons = _review_dibao(applicant, opts)
		MEDICAL_AID, TEMPORARY_AID, HOMELESS_RELIEF:
			reasons = _review_aid(applicant, kind, opts)
		_:
			return {"ok": false, "reason": "unknown_kind"}
	var approved: bool = reasons.is_empty()
	application["status"] = "approved" if approved else "rejected"
	application["reasons"] = reasons
	return {
		"ok": true, "approved": approved, "reasons": reasons,
		"status": str(application["status"]),
	}


func _review_adoption(applicant: Dictionary, opts: Dictionary) -> Array:
	var reasons: Array = []
	var age: int = int(applicant.get("age", 0))
	if age < int(opts.get("min_age", ADOPTION_REQUIREMENTS["min_age"])):
		reasons.append("too_young")
	if age > int(opts.get("max_age", ADOPTION_REQUIREMENTS["max_age"])):
		reasons.append("too_old")
	if float(applicant.get("income", 0.0)) < float(opts.get("min_income", ADOPTION_REQUIREMENTS["min_income"])):
		reasons.append("income_too_low")
	if float(applicant.get("assets", 0.0)) > float(opts.get("max_asset", ADOPTION_REQUIREMENTS["max_asset"])):
		reasons.append("assets_too_high")
	if bool(ADOPTION_REQUIREMENTS["no_criminal"]) and bool(applicant.get("criminal_record", false)):
		reasons.append("criminal_record")
	if bool(ADOPTION_REQUIREMENTS["no_major_illness"]) and bool(applicant.get("major_illness", false)):
		reasons.append("major_illness")
	return reasons


func _review_foster(applicant: Dictionary, opts: Dictionary) -> Array:
	var reasons: Array = []
	if float(applicant.get("income", 0.0)) < float(opts.get("min_income", 40000)):
		reasons.append("income_too_low")
	if int(applicant.get("capacity", 0)) <= 0:
		reasons.append("no_capacity")
	if bool(applicant.get("criminal_record", false)):
		reasons.append("criminal_record")
	if bool(applicant.get("abuse_history", false)):
		reasons.append("abuse_history")
	return reasons


func _review_dibao(applicant: Dictionary, opts: Dictionary) -> Array:
	var reasons: Array = []
	var per_capita: float = float(applicant.get("income", 0.0)) / maxf(1.0, float(applicant.get("household_size", 1)))
	if per_capita > float(opts.get("income_ceiling", DIBAO_INCOME_CEILING)):
		reasons.append("income_above_ceiling")
	if float(applicant.get("assets", 0.0)) > float(opts.get("max_asset", 200000)):
		reasons.append("assets_above_ceiling")
	if not bool(applicant.get("registered_local", true)):
		reasons.append("not_registered_local")
	return reasons


func _review_aid(applicant: Dictionary, kind: String, opts: Dictionary) -> Array:
	var reasons: Array = []
	if kind == MEDICAL_AID and not bool(applicant.get("medical_need", false)):
		reasons.append("no_medical_need")
	if kind == TEMPORARY_AID and not bool(applicant.get("in_crisis", false)):
		reasons.append("not_in_crisis")
	if kind == HOMELESS_RELIEF and not bool(applicant.get("homeless", false)):
		reasons.append("not_homeless")
	return reasons


# --- 家庭匹配与安置（与 D11 家庭以字典接口衔接）---

## 家庭评估：按收入、住房、无犯罪、无虐待等给出适配分 0..100。
func assess_home(applicant: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var score: float = 50.0
	score += clampf(float(applicant.get("income", 0.0)) / 200000.0, 0.0, 1.0) * 20.0
	score += clampf(float(applicant.get("housing_score", 0.5)), 0.0, 1.0) * 20.0
	if bool(applicant.get("criminal_record", false)):
		score -= 40.0
	if bool(applicant.get("abuse_history", false)):
		score -= 50.0
	if bool(applicant.get("major_illness", false)):
		score -= 15.0
	score = clampf(score, 0.0, 100.0)
	return {"ok": true, "score": score, "qualified": score >= float(opts.get("min_score", 50.0))}


## 家庭匹配：从候选家庭中选评估分最高且合格者。
func match_family(child: Dictionary, applicants: Array, opts: Dictionary = {}) -> Dictionary:
	var best: Dictionary = {}
	var best_score: float = -1.0
	for a in applicants:
		var applicant: Dictionary = a
		var assess: Dictionary = assess_home(applicant, opts)
		if not bool(assess["qualified"]):
			continue
		if float(assess["score"]) > best_score:
			best_score = float(assess["score"])
			best = applicant
	if best.is_empty():
		return {"ok": true, "matched": false, "reason": "no_qualified_family"}
	return {
		"ok": true, "matched": true, "family_id": str(best.get("id", "")),
		"score": best_score, "child_id": str(child.get("id", "")),
	}


## 安置子女：返回家庭接口字典，交由 FamilySystem 落地（本系统不维护家庭成员）。
func place_child(child: Dictionary, family: Dictionary, kind: String = ADOPTION, opts: Dictionary = {}) -> Dictionary:
	if family.is_empty():
		return {"ok": false, "reason": "no_family"}
	var custody: String = "adoption" if kind == ADOPTION else "foster"
	return {
		"ok": true,
		"family_interface": {
			"child": child.duplicate(true),
			"guardian_id": str(family.get("id", "")),
			"guardian_name": str(family.get("name", "")),
			"custody": custody,
			"start_day": int(opts.get("day", 0)),
		},
		"family_notified": true,
	}


## 监护评估：监护人是否具备监护能力。
func guardianship_assessment(child: Dictionary, guardian: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var capable: bool = not bool(guardian.get("incapacitated", false)) and not bool(guardian.get("abuse_history", false))
	return {
		"ok": true, "capable": capable,
		"child_id": str(child.get("id", "")), "guardian_id": str(guardian.get("id", "")),
		"reason": "ok" if capable else "guardian_incapable",
	}


# --- 社会救助发放 ---

## 发放救助：按标准与困难程度计算金额。
func disburse_assistance(application: Dictionary, applicant: Dictionary = {}, opts: Dictionary = {}) -> Dictionary:
	if str(application.get("status", "pending")) != "approved":
		return {"ok": false, "reason": "not_approved"}
	var kind: String = str(application.get("kind", ""))
	var standard: Dictionary = ASSISTANCE_STANDARDS.get(kind, {})
	var amount: int = int(opts.get("amount", int(standard.get("base_amount", 0))))
	var days: int = mini(maxi(0, int(opts.get("days", 30))), int(standard.get("max_days", 30)))
	var paid: int = int(round(float(amount) * float(days) / 30.0))
	if not applicant.is_empty():
		applicant["aid_received"] = int(applicant.get("aid_received", 0)) + paid
	application["disbursed"] = paid
	return {"ok": true, "kind": kind, "days": days, "paid": paid}


# --- 家庭变故 ---

## 家庭变故：孤儿/被遗弃/父母失能时，子女进入寄养或救助体系。
func child_in_crisis(child: Dictionary, situation: String, opts: Dictionary = {}) -> Dictionary:
	if not CRISIS_KINDS.has(situation):
		return {"ok": false, "reason": "unknown_situation"}
	var has_relative: bool = bool(opts.get("has_relative", false))
	var route: String = ""
	if situation == CRISIS_GUARDIAN_DISABLED and has_relative:
		route = "kinship_care"
	elif situation == CRISIS_ORPHAN or situation == CRISIS_ABANDONED:
		route = "foster" if bool(opts.get("foster_available", true)) else "institution"
	else:
		route = "relief"
	child["welfare_route"] = route
	return {
		"ok": true, "situation": situation, "route": route,
		"child_id": str(child.get("id", "")), "entered_system": true,
	}


# --- 慈善基金 ---

func new_charity_fund(name: String, opts: Dictionary = {}) -> Dictionary:
	return {
		"name": name,
		"balance": maxi(0, int(opts.get("balance", 0))),
		"raised": 0,
		"spent": 0,
		"donations": 0,
		"donation_count": 0,
		"transparency": clampf(float(opts.get("transparency", 1.0)), 0.0, 1.0),
		"reputation": clampf(float(opts.get("reputation", 0.5)), 0.0, 1.0),
		"misappropriated": false,
		"expenditures": [],
	}


func donate(fund: Dictionary, amount: int, opts: Dictionary = {}) -> Dictionary:
	var a: int = maxi(0, amount)
	fund["balance"] = int(fund.get("balance", 0)) + a
	fund["raised"] = int(fund.get("raised", 0)) + a
	fund["donations"] = int(fund.get("donations", 0)) + a
	fund["donation_count"] = int(fund.get("donation_count", 0)) + 1
	return {"ok": true, "balance": int(fund["balance"]), "raised": int(fund["raised"])}


## 募捐结算：返回已募捐、已支出、管理费比例与结余。
func settle_fund(fund: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var raised: int = int(fund.get("raised", 0))
	var spent: int = int(fund.get("spent", 0))
	var overhead_rate: float = clampf(float(opts.get("overhead_rate", 0.1)), 0.0, 1.0)
	var overhead: int = int(round(float(raised) * overhead_rate))
	var to_cause: int = maxi(0, raised - overhead)
	return {
		"ok": true, "raised": raised, "spent": spent, "overhead": overhead,
		"to_cause": to_cause, "balance": int(fund.get("balance", 0)),
	}


## 支出：用于公益目的，并计入透明度记录。
func spend_fund(fund: Dictionary, purpose: String, amount: int, opts: Dictionary = {}) -> Dictionary:
	var a: int = maxi(0, amount)
	if a > int(fund.get("balance", 0)):
		return {"ok": false, "reason": "insufficient_balance", "balance": int(fund.get("balance", 0))}
	fund["balance"] = int(fund.get("balance", 0)) - a
	fund["spent"] = int(fund.get("spent", 0)) + a
	(fund["expenditures"] as Array).append({"purpose": purpose, "amount": a, "day": int(opts.get("day", 0))})
	return {"ok": true, "balance": int(fund["balance"]), "spent": int(fund["spent"])}


## 透明度审计：支出披露越充分、挪用越少，透明度越高、声誉越好。
func audit_transparency(fund: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var spent: int = int(fund.get("spent", 0))
	var disclosed: int = int(opts.get("disclosed", spent))
	var coverage: float = clampf(float(disclosed) / maxf(1.0, float(spent)), 0.0, 1.0)
	var score: float = coverage * 100.0
	if bool(fund.get("misappropriated", false)):
		score -= 60.0
	score = clampf(score, 0.0, 100.0)
	fund["transparency"] = score / 100.0
	fund["reputation"] = clampf(float(fund.get("reputation", 0.5)) + (score / 100.0 - 0.5) * 0.2, 0.0, 1.0)
	return {"ok": true, "transparency": score, "grade": "A" if score >= 80.0 else ("B" if score >= 60.0 else "C")}


## 善款挪用：隐蔽标记，可能被审计查获并反噬声誉。
func misappropriate(fund: Dictionary, amount: int, opts: Dictionary = {}, rng = null) -> Dictionary:
	var a: int = maxi(0, amount)
	fund["misappropriated"] = true
	fund["balance"] = maxi(0, int(fund.get("balance", 0)) - a)
	var detected: bool = _roll(float(opts.get("roll", -1.0)), rng) < clampf(float(opts.get("detect_risk", 0.4)), 0.0, 1.0)
	if detected:
		fund["reputation"] = clampf(float(fund.get("reputation", 0.0)) - 0.6, 0.0, 1.0)
		fund["transparency"] = clampf(float(fund.get("transparency", 0.0)) - 0.6, 0.0, 1.0)
	return {"ok": true, "amount": a, "detected": detected, "criminal": detected, "reputation": float(fund["reputation"])}


# --- 社工与个案 ---

func new_social_worker(id: String, opts: Dictionary = {}) -> Dictionary:
	return {
		"id": id,
		"name": str(opts.get("name", id)),
		"cases_closed": maxi(0, int(opts.get("cases_closed", 0))),
		"rank_index": 0,
		"salary": int((SOCIAL_WORKER_RANKS[0] as Dictionary)["salary"]),
		"active_cases": [],
	}


func new_case(worker: Dictionary, family_id: String, opts: Dictionary = {}) -> Dictionary:
	var case: Dictionary = {
		"id": str(opts.get("id", "%s#%d" % [str(worker.get("id", "")), (worker.get("active_cases", []) as Array).size() + 1])),
		"family_id": family_id,
		"kind": str(opts.get("kind", "general")),
		"status": "open",
		"visits": 0,
		"notes": [],
		"progress": 0.0,
		"closed": false,
	}
	(worker["active_cases"] as Array).append(case)
	return case


## 个案跟进：记录家访与进展；进展达标后可结案并累计业绩。
func follow_up(case: Dictionary, note: String, opts: Dictionary = {}) -> Dictionary:
	case["visits"] = int(case.get("visits", 0)) + 1
	(case["notes"] as Array).append(note)
	case["progress"] = clampf(float(case.get("progress", 0.0)) + float(opts.get("progress_gain", 0.25)), 0.0, 1.0)
	var closed: bool = float(case["progress"]) >= 1.0 or bool(opts.get("force_close", false))
	if closed:
		case["closed"] = true
		case["status"] = "closed"
	return {"ok": true, "visits": int(case["visits"]), "progress": float(case["progress"]), "closed": closed}


## 结案：从社工在办个案中移除并累计业绩。
func close_case(worker: Dictionary, case: Dictionary) -> Dictionary:
	var active: Array = worker["active_cases"]
	if active.has(case):
		active.erase(case)
		worker["cases_closed"] = int(worker.get("cases_closed", 0)) + 1
	case["closed"] = true
	case["status"] = "closed"
	var promoted: Dictionary = promote_social_worker(worker)
	return {"ok": true, "cases_closed": int(worker["cases_closed"]), "promoted": bool(promoted["promoted"])}


func promote_social_worker(worker: Dictionary) -> Dictionary:
	var count: int = int(worker.get("cases_closed", 0))
	var target: int = 0
	for i in range(SOCIAL_WORKER_RANKS.size()):
		if count >= int((SOCIAL_WORKER_RANKS[i] as Dictionary)["cases_required"]):
			target = i
	worker["rank_index"] = target
	worker["salary"] = int((SOCIAL_WORKER_RANKS[target] as Dictionary)["salary"])
	return {"ok": true, "promoted": target > 0, "rank_index": target, "salary": int(worker["salary"])}


# --- 边界情况 ---

## 虐待举报：调查并判定是否属实；属实则撤销监护、转介寄养。
func report_abuse(child: Dictionary, guardian: Dictionary, opts: Dictionary = {}, rng = null) -> Dictionary:
	var evidence: float = clampf(float(opts.get("evidence", 0.5)), 0.0, 1.0)
	var substantiated: bool = _roll(float(opts.get("roll", -1.0)), rng) < evidence
	var action: String = "none"
	if substantiated:
		action = "remove_custody"
		child["welfare_route"] = "foster"
		if not guardian.is_empty():
			guardian["abuse_history"] = true
	return {
		"ok": true, "reported": true, "substantiated": substantiated,
		"action": action, "child_id": str(child.get("id", "")),
	}


## 救助依赖与脱困：长期受助会形成依赖；就业/技能提升帮助脱困。
func welfare_dependency(recipient: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var months: int = maxi(0, int(recipient.get("aid_months", 0)))
	var dependency: float = clampf(float(months) / 60.0 - float(recipient.get("employable", 0.0)) * 0.3, 0.0, 1.0)
	var escaped: bool = bool(opts.get("employed", false)) or float(recipient.get("employable", 0.0)) >= float(opts.get("escape_threshold", 0.7))
	return {
		"ok": true, "dependency": dependency, "escaped": escaped,
		"route_out": "employment" if escaped else "continued_relief",
	}


# --- 序列化 ---

func to_dict(state: Dictionary) -> Dictionary:
	return state.duplicate(true)


func from_dict(data: Dictionary) -> Dictionary:
	return data.duplicate(true)
