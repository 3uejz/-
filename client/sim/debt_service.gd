class_name DebtServiceSystem
extends RefCounted
## 债务服务、当铺与小贷（R83；design D39）。
##
## 覆盖：
##   - 业务：典当/民间借贷/小额信贷/消费金融/众筹/P2P（时代限定），含利率与抵押；
##   - 风控放贷：信用评估、抵押、担保、联保，坏账与催收结算；
##   - 催收双路径：合法催收（提醒/诉讼）不违法；灰色催收（骚扰/上门/暴力）产生
##     违法标记、法律后果与人身风险，并与利率上限、无牌经营等合规边界联动；
##   - 牌照监管：放贷需牌照，无牌经营入违法处理；利率上限合规；
##   - 债务困境：以贷养贷、债务重组、个人破产（若时代允许）；
##   - 边界：跑路、暴力催收致伤、套路贷、非法集资、催收致自杀的法律与道德后果。
##
## 设计取舍：
##   - 借款、放贷人、借款人均为纯数据 Dictionary，便于存读档与 headless 测试；
##   - 合规判定拆分：rate_compliant（利率上限）+ license_status（牌照），合成 compliance_status；
##   - 催收后果为确定性规则：合法路径 illegal=false 且人身风险为 0；灰色路径 illegal=true，
##     法律后果随严重度升级（行政→刑事）；合规瑕疵（无牌/超上限）作为加重系数，
##     使“灰色催收 × 违规放贷”产生更重的法律后果，便于属性测试；
##   - 致伤/致自杀的人身风险由注入 roll 判定，缺省确定化（不触发），便于复现。

const BIZ_PAWN: String = "pawn"
const BIZ_PRIVATE_LENDING: String = "private_lending"
const BIZ_MICRO_LOAN: String = "micro_loan"
const BIZ_CONSUMER_FINANCE: String = "consumer_finance"
const BIZ_CROWDFUNDING: String = "crowdfunding"
const BIZ_P2P: String = "p2p"

const BUSINESSES: Dictionary = {
	"pawn": {"name": "典当", "requires_license": true, "rate_cap": 0.36, "collateral_required": true, "era": "all"},
	"private_lending": {"name": "民间借贷", "requires_license": false, "rate_cap": 0.36, "collateral_required": false, "era": "all"},
	"micro_loan": {"name": "小额信贷", "requires_license": true, "rate_cap": 0.24, "collateral_required": false, "era": "all"},
	"consumer_finance": {"name": "消费金融", "requires_license": true, "rate_cap": 0.24, "collateral_required": false, "era": "all"},
	"crowdfunding": {"name": "众筹", "requires_license": true, "rate_cap": 0.0, "collateral_required": false, "era": "all"},
	"p2p": {"name": "P2P", "requires_license": true, "rate_cap": 0.24, "collateral_required": false, "era": "2013-2020"},
}

## 民间借贷司法保护的利率上限（年化），超出部分不受保护。
const INTEREST_RATE_CAP: float = 0.36
const P2P_ERA_START: int = 2013
const P2P_ERA_END: int = 2020

## 催收方式：合法/灰色、严重度。legal=true 不违法且无强制人身风险。
const COLLECTION_MODES: Dictionary = {
	"reminder": {"name": "短信电话提醒", "legal": true, "severity": 0.10},
	"litigation": {"name": "起诉", "legal": true, "severity": 0.20},
	"harassment": {"name": "骚扰", "legal": false, "severity": 0.40},
	"home_visit": {"name": "上门施压", "legal": false, "severity": 0.65},
	"violence": {"name": "暴力催收", "legal": false, "severity": 0.90},
}
const LEGAL_MODES: Array = ["reminder", "litigation"]
const GRAY_MODES: Array = ["harassment", "home_visit", "violence"]

const CONSEQUENCE_NONE: String = "none"
const CONSEQUENCE_CIVIL: String = "civil"
const CONSEQUENCE_ADMIN: String = "administrative"
const CONSEQUENCE_CRIMINAL: String = "criminal"

const LOAN_ACTIVE: String = "active"
const LOAN_REPAID: String = "repaid"
const LOAN_DEFAULTED: String = "defaulted"
const LOAN_RESTRUCTURED: String = "restructured"
const LOAN_DISCHARGED: String = "discharged"

const BANKRUPTCY_ERA_START: int = 2021  # 个人破产试点时代下限（本地近似）


func _roll(forced: float, rng) -> float:
	if forced >= 0.0:
		return clampf(forced, 0.0, 1.0)
	if rng != null:
		return rng.next_float()
	return 0.0


# --- 数据表 ---

func business_keys() -> Array:
	return BUSINESSES.keys()


func business_def(key: String) -> Dictionary:
	if not BUSINESSES.has(key):
		return {}
	return (BUSINESSES[key] as Dictionary).duplicate(true)


func collection_mode_keys() -> Array:
	return COLLECTION_MODES.keys()


func collection_mode_def(key: String) -> Dictionary:
	if not COLLECTION_MODES.has(key):
		return {}
	return (COLLECTION_MODES[key] as Dictionary).duplicate(true)


func is_legal_collection(mode: String) -> bool:
	return LEGAL_MODES.has(mode)


func is_gray_collection(mode: String) -> bool:
	return GRAY_MODES.has(mode)


## P2P 仅在限定时代可用。
func business_available(key: String, year: int) -> bool:
	if not BUSINESSES.has(key):
		return false
	var era: String = str((BUSINESSES[key] as Dictionary).get("era", "all"))
	if era == "all":
		return true
	var parts: PackedStringArray = era.split("-")
	if parts.size() != 2:
		return true
	return year >= int(parts[0]) and year <= int(parts[1])


# --- 借款与放贷人 ---

## 新建放贷人（机构/个人）。license 为放贷牌照。
func new_lender(id: String, opts: Dictionary = {}) -> Dictionary:
	return {
		"id": id,
		"name": str(opts.get("name", id)),
		"license": bool(opts.get("license", false)),
		"capital": maxi(0, int(opts.get("capital", 0))),
		"reputation": clampf(float(opts.get("reputation", 0.5)), 0.0, 1.0),
		"violations": 0,
	}


## 新建借款。rate 为年化利率，collateral_value 为抵押物估值。
func new_loan(id: String, business: String, principal: int, opts: Dictionary = {}) -> Dictionary:
	var def: Dictionary = BUSINESSES.get(business, {})
	return {
		"id": id,
		"business": business,
		"lender": str(opts.get("lender", "")),
		"borrower": str(opts.get("borrower", "")),
		"principal": maxi(0, principal),
		"outstanding": maxi(0, principal),
		"rate": maxf(0.0, float(opts.get("rate", 0.12))),
		"term_days": maxi(1, int(opts.get("term_days", 365))),
		"collateral": str(opts.get("collateral", "")),
		"collateral_value": maxi(0, int(opts.get("collateral_value", 0))),
		"guarantor": str(opts.get("guarantor", "")),
		"joint_guarantee": [],
		"service_fee": maxi(0, int(opts.get("service_fee", 0))),
		"cut_interest": maxi(0, int(opts.get("cut_interest", 0))),  # 砍头息
		"status": LOAN_ACTIVE,
		"overdue_days": 0,
		"illegal_collection": false,
		"collection_modes": [],
		"predatory": false,
		"compliant": true,
		"requires_license": bool(def.get("requires_license", true)),
	}


func add_collateral(loan: Dictionary, value: int) -> Dictionary:
	loan["collateral_value"] = maxi(0, int(loan.get("collateral_value", 0)) + maxi(0, value))
	return {"ok": true, "collateral_value": int(loan["collateral_value"])}


func add_joint_guarantee(loan: Dictionary, member: String) -> Dictionary:
	var members: Array = loan["joint_guarantee"]
	if not members.has(member):
		members.append(member)
	return {"ok": true, "joint_guarantee": members.duplicate()}


# --- 合规与监管 ---

func interest_cap(business: String) -> float:
	var def: Dictionary = BUSINESSES.get(business, {})
	return float(def.get("rate_cap", INTEREST_RATE_CAP))


## 利率是否合规：不得超过业务对应上限。
func rate_compliant(loan: Dictionary) -> bool:
	return float(loan.get("rate", 0.0)) <= interest_cap(str(loan.get("business", ""))) + 1e-9


## 放贷人是否持牌。民间借贷无需牌照，视为合法。
func license_status(loan: Dictionary, lender: Dictionary = {}) -> bool:
	if not bool(loan.get("requires_license", true)):
		return true
	if lender.is_empty():
		return true
	return bool(lender.get("license", false))


## 合规状态汇总：牌照 + 利率上限 + 抵押要求。
func compliance_status(loan: Dictionary, lender: Dictionary = {}) -> Dictionary:
	var violations: Array = []
	var rate_ok: bool = rate_compliant(loan)
	var licensed: bool = license_status(loan, lender)
	var def: Dictionary = BUSINESSES.get(str(loan.get("business", "")), {})
	var collateral_ok: bool = true
	if bool(def.get("collateral_required", false)):
		collateral_ok = int(loan.get("collateral_value", 0)) > 0 or not str(loan.get("collateral", "")).is_empty()
	if not rate_ok:
		violations.append("interest_over_cap")
	if not licensed:
		violations.append("unlicensed")
	if not collateral_ok:
		violations.append("missing_collateral")
	return {
		"ok": true,
		"licensed": licensed, "rate_ok": rate_ok, "collateral_ok": collateral_ok,
		"compliant": violations.is_empty(), "violations": violations,
	}


## 监管处理：对违规放贷记账并发起违法处理。
func regulate(loan: Dictionary, lender: Dictionary = {}) -> Dictionary:
	var status: Dictionary = compliance_status(loan, lender)
	loan["compliant"] = bool(status["compliant"])
	var legal: bool = not bool(status["compliant"])
	if not lender.is_empty() and legal:
		lender["violations"] = int(lender.get("violations", 0)) + 1
		lender["reputation"] = clampf(float(lender.get("reputation", 0.0)) - 0.1, 0.0, 1.0)
	return {
		"ok": true, "illegal": legal, "violations": status["violations"],
		"compliant": bool(status["compliant"]),
	}


# --- 风控与放贷 ---

## 信用评估：还款能力（收入/负债比）+ 抵押担保 + 历史违约。
func assess_credit(borrower: Dictionary, loan: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var income: float = maxf(0.0, float(borrower.get("income", 0.0)))
	var debt: float = maxf(0.0, float(borrower.get("debt", 0.0)))
	var history: float = clampf(float(borrower.get("credit_history", 0.7)), 0.0, 1.0)
	var ratio: float = clampf(income / maxf(1.0, debt + float(loan.get("principal", 0))), 0.0, 1.0)
	var score: float = ratio * 50.0 + history * 40.0
	if int(loan.get("collateral_value", 0)) > 0:
		score += 5.0
	if not str(loan.get("guarantor", "")).is_empty() or not (loan.get("joint_guarantee", []) as Array).is_empty():
		score += 5.0
	if bool(borrower.get("defaulted", false)):
		score -= 30.0
	score = clampf(score, 0.0, 100.0)
	var min_score: float = float(opts.get("min_score", 40.0))
	var approved: bool = score >= min_score
	var max_amount: int = int(income * float(opts.get("income_multiple", 3.0)))
	return {
		"ok": true, "score": score, "approved": approved,
		"max_amount": maxi(0, max_amount), "reasons": _credit_reasons(score, approved, loan),
	}


func _credit_reasons(score: float, approved: bool, loan: Dictionary) -> Array:
	var reasons: Array = []
	if not approved:
		reasons.append("credit_below_line")
	if int(loan.get("collateral_value", 0)) > 0:
		reasons.append("collateral")
	if not str(loan.get("guarantor", "")).is_empty():
		reasons.append("guarantor")
	if not (loan.get("joint_guarantee", []) as Array).is_empty():
		reasons.append("joint_guarantee")
	return reasons


## 放款：审批通过后入账（外部注入金额结算），登记合规状态。
func disburse(loan: Dictionary, lender: Dictionary = {}, opts: Dictionary = {}) -> Dictionary:
	if str(loan.get("status", LOAN_ACTIVE)) != LOAN_ACTIVE:
		return {"ok": false, "reason": "bad_status"}
	var status: Dictionary = compliance_status(loan, lender)
	loan["compliant"] = bool(status["compliant"])
	var amount: int = int(loan.get("principal", 0)) - int(loan.get("cut_interest", 0))
	return {
		"ok": true, "amount": maxi(0, amount), "status": str(loan.get("status", LOAN_ACTIVE)),
		"compliant": bool(loan["compliant"]), "violations": status["violations"],
	}


## 审批 + 放款一步完成。
func approve_loan(borrower: Dictionary, loan: Dictionary, lender: Dictionary = {}, opts: Dictionary = {}) -> Dictionary:
	var credit: Dictionary = assess_credit(borrower, loan, opts)
	if not bool(credit["approved"]):
		return {"ok": true, "approved": false, "credit": credit}
	var disb: Dictionary = disburse(loan, lender, opts)
	return {"ok": true, "approved": true, "credit": credit, "disbursement": disb}


## 坏账：逾期转入违约，按抵押/担保回收部分损失。
func default_loan(loan: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var recovered: int = mini(int(loan.get("outstanding", 0)), int(loan.get("collateral_value", 0)))
	var guaranteed: int = 0
	if not str(loan.get("guarantor", "")).is_empty():
		guaranteed += int(round(float(loan.get("outstanding", 0)) * 0.5))
	guaranteed += int(round(float(loan.get("outstanding", 0)) * 0.2 * float((loan.get("joint_guarantee", []) as Array).size())))
	var total_recovered: int = mini(int(loan.get("outstanding", 0)), recovered + guaranteed)
	var bad_debt: int = maxi(0, int(loan.get("outstanding", 0)) - total_recovered)
	loan["status"] = LOAN_DEFAULTED
	return {
		"ok": true, "recovered": total_recovered, "bad_debt": bad_debt,
		"secured": int(loan.get("collateral_value", 0)) > 0,
		"guaranteed": guaranteed,
	}


# --- 催收（核心：合法 / 灰色双路径）---

## 催收结算。合法路径不违法、无强制人身风险；灰色路径产生违法标记与人身风险，
## 且当借款本身违规（无牌/超利率上限）时后果加重。
## opts：injury_roll/suicide_roll/severity_scale/force_consequence。
func collect(loan: Dictionary, mode: String, lender: Dictionary = {}, opts: Dictionary = {}, rng = null) -> Dictionary:
	if not COLLECTION_MODES.has(mode):
		return {"ok": false, "reason": "unknown_mode"}
	var def: Dictionary = COLLECTION_MODES[mode]
	var legal: bool = bool(def["legal"])
	var status: Dictionary = compliance_status(loan, lender)
	var compliant: bool = bool(status["compliant"])
	# 合规瑕疵作为灰色催收的加重系数。
	var aggravate: float = 1.0 if compliant else 1.5
	var severity: float = clampf(float(def["severity"]) * float(opts.get("severity_scale", 1.0)) * aggravate, 0.0, 1.0)
	(loan["collection_modes"] as Array).append(mode)
	if legal:
		# 合法催收：不违法、人身风险为 0。
		var enforceable: bool = compliant
		var recoverable: int = int(loan.get("outstanding", 0))
		if not bool(status["rate_ok"]):
			# 超出利率上限部分不受法律保护。
			var cap: float = interest_cap(str(loan.get("business", "")))
			var legal_total: int = int(round(float(loan.get("principal", 0)) * (1.0 + cap * float(loan.get("term_days", 365)) / 365.0)))
			recoverable = mini(recoverable, legal_total)
		return {
			"ok": true, "mode": mode, "legal_collection": true, "illegal": false,
			"personal_risk": 0.0, "injury": false, "suicide": false, "victim_harm": "none",
			"legal_consequence": CONSEQUENCE_NONE, "aggravated": false,
			"enforceable": enforceable, "recoverable": maxi(0, recoverable),
			"violations": status["violations"],
		}
	# 灰色催收：违法标记 + 法律后果 + 人身风险。
	loan["illegal_collection"] = true
	var personal_risk: float = clampf(severity, 0.0, 1.0)
	var injury_risk: float = clampf(severity * (0.6 if mode == "violence" else 0.2), 0.0, 1.0)
	var injury: bool = _roll(float(opts.get("injury_roll", -1.0)), rng) < injury_risk
	var suicide_risk: float = clampf(personal_risk * 0.25, 0.0, 1.0)
	var suicide: bool = _roll(float(opts.get("suicide_roll", -1.0)), rng) < suicide_risk
	var consequence: String = str(opts.get("force_consequence", ""))
	if consequence.is_empty():
		consequence = _consequence_for(mode, severity, injury or suicide)
	var victim_harm: String = "none"
	if suicide:
		victim_harm = "death"
	elif injury:
		victim_harm = "injury"
	elif mode == "harassment":
		victim_harm = "distress"
	return {
		"ok": true, "mode": mode, "legal_collection": false, "illegal": true,
		"personal_risk": personal_risk, "injury": injury, "suicide": suicide,
		"victim_harm": victim_harm, "legal_consequence": consequence,
		"aggravated": not compliant, "enforceable": false, "recoverable": 0,
		"violations": status["violations"],
	}


func _consequence_for(mode: String, severity: float, harmed: bool) -> String:
	if harmed or mode == "violence" or severity >= 0.85:
		return CONSEQUENCE_CRIMINAL
	if mode == "home_visit" or severity >= 0.55:
		return CONSEQUENCE_ADMIN
	return CONSEQUENCE_CIVIL


## 记录催收致自杀事件：涉事放贷人承担刑事与道德后果。
func record_suicide_incident(loan: Dictionary, lender: Dictionary = {}, opts: Dictionary = {}) -> Dictionary:
	loan["suicide_incident"] = true
	if not lender.is_empty():
		lender["violations"] = int(lender.get("violations", 0)) + 1
		lender["reputation"] = clampf(float(lender.get("reputation", 0.0)) - 0.5, 0.0, 1.0)
	return {
		"ok": true, "criminal_liability": true, "civil_compensation": int(opts.get("compensation", 500000)),
		"moral_condemnation": true, "event": "collection_suicide",
	}


# --- 债务困境 ---

## 以贷养贷：借新还旧，债务雪球扩大并被标记。
func borrow_to_repay(old_loan: Dictionary, new_loan: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var old_outstanding: int = int(old_loan.get("outstanding", 0))
	new_loan["borrow_to_repay"] = true
	var snowball: int = old_outstanding + maxi(0, int(new_loan.get("service_fee", 0)))
	return {
		"ok": true, "snowball_debt": snowball, "risk": "escalating",
		"rolled_over": old_outstanding > 0,
	}


## 债务重组：展期/降息/本金减免，缓解还款压力。
func restructure(loan: Dictionary, opts: Dictionary = {}) -> Dictionary:
	if str(loan.get("status", LOAN_ACTIVE)) == LOAN_REPAID:
		return {"ok": false, "reason": "already_repaid"}
	var extend: int = maxi(0, int(opts.get("extend_days", 180)))
	var rate_cut: float = clampf(float(opts.get("rate_cut", 0.05)), 0.0, 1.0)
	var haircut: float = clampf(float(opts.get("haircut", 0.0)), 0.0, 1.0)
	loan["term_days"] = int(loan.get("term_days", 365)) + extend
	loan["rate"] = maxf(0.0, float(loan.get("rate", 0.0)) - rate_cut)
	var reduced: int = int(round(float(loan.get("outstanding", 0)) * haircut))
	loan["outstanding"] = maxi(0, int(loan.get("outstanding", 0)) - reduced)
	loan["status"] = LOAN_RESTRUCTURED
	return {
		"ok": true, "term_days": int(loan["term_days"]), "rate": float(loan["rate"]),
		"haircut": reduced, "outstanding": int(loan["outstanding"]),
	}


## 个人破产（若时代允许）：核销债务但信用严重受损。
func personal_bankruptcy(borrower: Dictionary, loans: Array, year: int, opts: Dictionary = {}) -> Dictionary:
	if year < int(opts.get("era_start", BANKRUPTCY_ERA_START)):
		return {"ok": false, "reason": "era_not_allowed"}
	var discharged: int = 0
	for l in loans:
		var loan: Dictionary = l
		discharged += int(loan.get("outstanding", 0))
		loan["outstanding"] = 0
		loan["status"] = LOAN_DISCHARGED
	borrower["credit_history"] = clampf(float(borrower.get("credit_history", 0.5)) - 0.6, 0.0, 1.0)
	borrower["bankrupt"] = true
	return {"ok": true, "discharged": discharged, "credit_history": float(borrower["credit_history"])}


# --- 边界情况 ---

## 借款人跑路：追偿概率随抵押/担保上升。
func abscond(loan: Dictionary, opts: Dictionary = {}, rng = null) -> Dictionary:
	loan["status"] = LOAN_DEFAULTED
	loan["absconded"] = true
	var recovery_chance: float = clampf(
		0.1 + (0.3 if int(loan.get("collateral_value", 0)) > 0 else 0.0)
		+ (0.2 if not str(loan.get("guarantor", "")).is_empty() else 0.0),
		0.0, 0.9)
	var recovered: bool = _roll(float(opts.get("roll", -1.0)), rng) < recovery_chance
	return {"ok": true, "absconded": true, "recovered": recovered, "recovery_chance": recovery_chance}


## 套路贷：砍头息、虚增债务与服务费即构成套路贷标记。
func predatory_loan(loan: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var cut: int = int(loan.get("cut_interest", 0))
	var fee: int = int(loan.get("service_fee", 0))
	var inflated: int = maxi(0, int(opts.get("inflated_debt", 0)))
	var is_predatory: bool = cut > 0 or inflated > 0 or fee > int(loan.get("principal", 0)) * 0.3
	if is_predatory:
		loan["predatory"] = true
		loan["outstanding"] = int(loan.get("outstanding", 0)) + inflated
	return {
		"ok": true, "predatory": is_predatory, "cut_interest": cut,
		"inflated_debt": inflated, "outstanding": int(loan["outstanding"]),
	}


## 非法集资：无牌照向社会公众募集资金，构成刑事违法。
func illegal_fundraising(lender: Dictionary, amount: int, opts: Dictionary = {}) -> Dictionary:
	var licensed: bool = bool(lender.get("license", false))
	var public_raise: bool = bool(opts.get("public", true))
	var illegal: bool = (not licensed) and public_raise and amount > 0
	if illegal:
		lender["violations"] = int(lender.get("violations", 0)) + 1
		lender["reputation"] = clampf(float(lender.get("reputation", 0.0)) - 0.5, 0.0, 1.0)
	return {
		"ok": true, "illegal": illegal, "amount": maxi(0, amount),
		"legal_consequence": CONSEQUENCE_CRIMINAL if illegal else CONSEQUENCE_NONE,
		"reason": "unlicensed_public_raising" if illegal else "ok",
	}


# --- 序列化 ---

func to_dict(state: Dictionary) -> Dictionary:
	return state.duplicate(true)


func from_dict(data: Dictionary) -> Dictionary:
	return data.duplicate(true)
