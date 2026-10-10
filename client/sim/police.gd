class_name PoliceSystem
extends RefCounted
## 安保、警务与刑侦（R79；design D35）。
##
## 覆盖：
##   - 公职路径：警察/法医/刑侦/经侦/缉毒，专业化分工（各含技能侧重与证据加成）；
##   - 案件状态机：勘查 → 取证 → 追查 → 侦破（未破转冷案），支持审讯、线人、卧底、技术侦查；
##   - 办案约束：搜查令、程序合法、受法律与舆论约束，滥用职权与腐败串通风险；
##   - 民营安保：私家侦探/保镖/安保公司，承接押运、护卫、安防工程、要人保护；
##   - 边界：冤假错案、证据瑕疵（非法取证被排除）、卧底暴露、安保失职担责、腐败串通。
##
## 设计取舍：
##   - 案件为纯数据 Dictionary，按 STAGES 状态机推进，便于存读档与 headless 测试；
##   - 侦破概率 = 证据强度加权 + 线索 + 警官技能 − 程序违法惩罚，对证据强度单调递增；
##   - 非法取证（无搜查令采集监控/技术证据）直接标记程序瑕疵：证据不入链且合法性下降；
##   - 误判由“证据薄弱 + 逼供”共同决定，与司法系统（D12）的冤案概念衔接但不重复其流程。

const BaselineScript = preload("res://sim/baseline.gd")

const ROLE_POLICE: String = "police"
const ROLE_FORENSIC: String = "forensic"
const ROLE_DETECTIVE: String = "detective"
const ROLE_ECONOMIC: String = "economic"
const ROLE_NARCOTICS: String = "narcotics"

## 公职分工：技能侧重与该角色对特定证据的采集加成。
const ROLES: Dictionary = {
	"police": {"name": "警察", "skill": "patrol", "evidence_bonus": {"witness": 0.10}},
	"forensic": {"name": "法医", "skill": "forensic", "evidence_bonus": {"forensic": 0.20, "physical": 0.10}},
	"detective": {"name": "刑侦", "skill": "investigation", "evidence_bonus": {"physical": 0.10, "witness": 0.05}},
	"economic": {"name": "经侦", "skill": "financial", "evidence_bonus": {"digital": 0.15}},
	"narcotics": {"name": "缉毒", "skill": "undercover", "evidence_bonus": {"witness": 0.10, "digital": 0.05}},
}

## 证据种类与权重。
const EVIDENCE_KINDS: Array = ["physical", "witness", "testimony", "surveillance", "digital", "forensic"]
const EVIDENCE_WEIGHTS: Dictionary = {
	"physical": 0.22, "witness": 0.18, "testimony": 0.15,
	"surveillance": 0.15, "digital": 0.15, "forensic": 0.15,
}
const EVIDENCE_NAMES: Dictionary = {
	"physical": "物证", "witness": "人证", "testimony": "供词",
	"surveillance": "监控", "digital": "电子记录", "forensic": "鉴定",
}

## 需搜查令方可合法采集的证据种类。
const WARRANT_REQUIRED: Array = ["surveillance", "digital"]

## 案件状态机。
const STAGE_SURVEY: String = "survey"
const STAGE_FORENSICS: String = "forensics"
const STAGE_TRACE: String = "trace"
const STAGE_SOLVED: String = "solved"
const STAGE_COLD: String = "cold"
const STAGES: Array = ["survey", "forensics", "trace", "solved", "cold"]
const STAGE_NAMES: Dictionary = {
	"survey": "勘查", "forensics": "取证", "trace": "追查", "solved": "侦破", "cold": "冷案",
}

## 民营安保业务。
const SECURITY_SERVICES: Dictionary = {
	"escort": {"name": "押运", "base_fee": 200000, "risk": 0.20, "staff_required": 4},
	"bodyguard": {"name": "护卫", "base_fee": 150000, "risk": 0.15, "staff_required": 2},
	"security_engineering": {"name": "安防工程", "base_fee": 500000, "risk": 0.10, "staff_required": 6},
	"vip_protection": {"name": "要人保护", "base_fee": 800000, "risk": 0.30, "staff_required": 8},
}

const MISJUDGMENT_EVIDENCE_LINE: float = BaselineScript.POLICE_MISJUDGMENT_EVIDENCE_LINE


# --- 数据表 ---

func role_keys() -> Array:
	return ROLES.keys()


func role_def(key: String) -> Dictionary:
	if not ROLES.has(key):
		return {}
	return (ROLES[key] as Dictionary).duplicate(true)


func evidence_kinds() -> Array:
	return EVIDENCE_KINDS.duplicate()


func stage_names() -> Dictionary:
	return STAGE_NAMES.duplicate(true)


func security_service_keys() -> Array:
	return SECURITY_SERVICES.keys()


func security_service_def(key: String) -> Dictionary:
	if not SECURITY_SERVICES.has(key):
		return {}
	return (SECURITY_SERVICES[key] as Dictionary).duplicate(true)


func _roll(forced: float, rng) -> float:
	if forced >= 0.0:
		return clampf(forced, 0.0, 1.0)
	if rng != null:
		return rng.next_float()
	return 0.0


# --- 案件 ---

func new_case(crime: String, region: String, opts: Dictionary = {}) -> Dictionary:
	var ev: Dictionary = {}
	for k in EVIDENCE_KINDS:
		ev[k] = 0.0
	return {
		"crime": crime, "region": region,
		"stage": STAGE_SURVEY,
		"evidence": ev,
		"leads": 0.0,
		"officer_skill": clampf(float(opts.get("officer_skill", 10.0)), 0.0, 20.0),
		"role": str(opts.get("role", ROLE_DETECTIVE)),
		"legal": {"warrant": false, "violations": 0, "procedure_legal": true},
		"coerced": false,
		"wrongful": false,
		"misjudgment_risk": 0.0,
		"informants": [],
		"undercover": {},
		"tech": [],
	}


func add_evidence(case: Dictionary, kind: String, strength: float) -> Dictionary:
	if not EVIDENCE_KINDS.has(kind):
		return {"ok": false, "reason": "unknown_kind"}
	var ev: Dictionary = case["evidence"]
	ev[kind] = clampf(float(ev.get(kind, 0.0)) + maxf(0.0, strength), 0.0, 1.0)
	return {"ok": true, "kind": kind, "value": float(ev[kind]), "score": evidence_score(case)}


## 证据强度加权 0..1。
func evidence_score(case: Dictionary) -> float:
	var ev: Dictionary = case.get("evidence", {})
	var total: float = 0.0
	for k in EVIDENCE_KINDS:
		total += float(EVIDENCE_WEIGHTS[k]) * float(ev.get(k, 0.0))
	return clampf(total, 0.0, 1.0)


# --- 办案流程 ---

## 勘查：采集线索。技能越高线索越多。
func survey(case: Dictionary, opts: Dictionary = {}) -> Dictionary:
	case["stage"] = STAGE_SURVEY
	var skill: float = clampf(float(case.get("officer_skill", 0.0)), 0.0, 20.0)
	var gain: float = clampf(0.2 + skill / 40.0 + float(opts.get("bonus", 0.0)), 0.0, 1.0)
	case["leads"] = clampf(float(case.get("leads", 0.0)) + gain, 0.0, 1.0)
	return {"ok": true, "stage": case["stage"], "leads": float(case["leads"])}


## 取证：按证据种类采集；监控/电子证据须先取得搜查令，否则视为非法取证（证据瑕疵）。
func collect(case: Dictionary, kind: String, strength: float, opts: Dictionary = {}) -> Dictionary:
	if not EVIDENCE_KINDS.has(kind):
		return {"ok": false, "reason": "unknown_kind"}
	case["stage"] = STAGE_FORENSICS
	var requires: bool = WARRANT_REQUIRED.has(kind)
	if requires and not bool((case["legal"] as Dictionary).get("warrant", false)):
		var legal: Dictionary = case["legal"]
		legal["procedure_legal"] = false
		legal["violations"] = int(legal.get("violations", 0)) + 1
		return {
			"ok": false, "reason": "illegal_collection", "illegal": true,
			"kind": kind, "score": evidence_score(case),
		}
	# 角色专业化加成。
	var bonus: float = float((ROLES.get(str(case.get("role", "")), {}) as Dictionary).get("evidence_bonus", {}).get(kind, 0.0))
	var added: float = maxf(0.0, strength) * (1.0 + bonus)
	add_evidence(case, kind, added)
	return {"ok": true, "kind": kind, "added": added, "score": evidence_score(case)}


## 申请搜查令。默认批准，可由 opts.granted 覆盖。
func request_warrant(case: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var granted: bool = bool(opts.get("granted", true))
	(case["legal"] as Dictionary)["warrant"] = granted
	return {"ok": true, "granted": granted, "warrant": granted}


## 审讯：压力越高越易取得供词，但逼供增加冤案风险。
func interrogate(case: Dictionary, pressure: float, opts: Dictionary = {}, rng = null) -> Dictionary:
	case["stage"] = STAGE_FORENSICS
	var p: float = clampf(pressure, 0.0, 1.0)
	var prob: float = clampf(p * 0.6, 0.05, 0.95)
	var roll: float = _roll(float(opts.get("roll", -1.0)), rng)
	var got: bool = roll < prob
	if got:
		add_evidence(case, "testimony", 0.4)
	var coercive: bool = p > 0.7
	if coercive:
		case["coerced"] = true
	return {"ok": true, "confession": got, "coercive": coercive, "score": evidence_score(case)}


## 使用线人：补充线索，存在假情报风险。
func use_informant(case: Dictionary, opts: Dictionary = {}, rng = null) -> Dictionary:
	var roll: float = _roll(float(opts.get("roll", -1.0)), rng)
	var reliable: bool = roll < 0.8
	var leads_gain: float = 0.15 if reliable else -0.05
	case["leads"] = clampf(float(case.get("leads", 0.0)) + leads_gain, 0.0, 1.0)
	(case["informants"] as Array).append({"id": str(opts.get("id", "informant")), "reliable": reliable})
	return {"ok": true, "reliable": reliable, "leads": float(case["leads"])}


## 部署卧底：可能渗透取得关键证据，也可能暴露。
func deploy_undercover(case: Dictionary, opts: Dictionary = {}, rng = null) -> Dictionary:
	var exposure_risk: float = clampf(float(opts.get("exposure_risk", 0.25)), 0.0, 1.0)
	var roll: float = _roll(float(opts.get("roll", -1.0)), rng)
	var exposed: bool = roll < exposure_risk
	if exposed:
		case["undercover"] = {"agent": str(opts.get("agent", "uc_1")), "exposed": true}
		return {"ok": true, "exposed": true, "evidence": 0.0, "score": evidence_score(case)}
	add_evidence(case, "witness", 0.2)
	add_evidence(case, "digital", 0.1)
	case["undercover"] = {"agent": str(opts.get("agent", "uc_1")), "exposed": false}
	return {"ok": true, "exposed": false, "evidence": evidence_score(case), "score": evidence_score(case)}


## 技术侦查：须有搜查令，取得电子/监控证据。
func tech_surveillance(case: Dictionary, opts: Dictionary = {}) -> Dictionary:
	if not bool((case["legal"] as Dictionary).get("warrant", false)):
		(case["legal"] as Dictionary)["procedure_legal"] = false
		(case["legal"] as Dictionary)["violations"] = int((case["legal"] as Dictionary).get("violations", 0)) + 1
		return {"ok": false, "reason": "no_warrant", "illegal": true}
	add_evidence(case, "digital", 0.2)
	(case["tech"] as Array).append(str(opts.get("method", "wiretap")))
	return {"ok": true, "score": evidence_score(case)}


# --- 破案率与误判 ---

## 程序合法度：违法取证与逼供拉低合法性。
func legality_score(case: Dictionary) -> float:
	var legal: Dictionary = case.get("legal", {})
	var violations: int = int(legal.get("violations", 0))
	var score: float = 1.0 - float(violations) * 0.3
	if bool(case.get("coerced", false)):
		score -= 0.2
	return clampf(score, 0.0, 1.0)


## 侦破概率：证据强度 + 线索 + 技能 − 程序违法惩罚。对证据强度单调递增。
func solve_probability(case: Dictionary) -> float:
	var ev: float = evidence_score(case)
	var leads: float = clampf(float(case.get("leads", 0.0)), 0.0, 1.0)
	var skill: float = clampf(float(case.get("officer_skill", 0.0)) / 20.0, 0.0, 1.0)
	var base: float = 0.10 + 0.60 * ev + 0.15 * leads + 0.15 * skill
	var penalty: float = 0.25 * (1.0 - legality_score(case))
	return clampf(base - penalty, 0.02, 0.98)


## 推进一步状态机；追查阶段尝试侦破。
func advance(case: Dictionary, opts: Dictionary = {}, rng = null) -> Dictionary:
	match str(case.get("stage", STAGE_SURVEY)):
		STAGE_SURVEY:
			case["stage"] = STAGE_FORENSICS
			return {"ok": true, "stage": case["stage"], "terminal": false}
		STAGE_FORENSICS:
			case["stage"] = STAGE_TRACE
			return {"ok": true, "stage": case["stage"], "terminal": false}
		STAGE_TRACE:
			return attempt_solve(case, opts, rng)
		_:
			return {"ok": false, "reason": "terminal", "stage": case["stage"], "terminal": true}


## 尝试侦破：按侦破概率判定。证据薄弱 + 逼供 => 即便“侦破”也构成冤假错案。
func attempt_solve(case: Dictionary, opts: Dictionary = {}, rng = null) -> Dictionary:
	var prob: float = solve_probability(case)
	var roll: float = _roll(float(opts.get("roll", -1.0)), rng)
	var solved: bool = roll < prob
	case["stage"] = STAGE_SOLVED if solved else STAGE_COLD
	var risk: float = 0.0
	var wrongful: bool = false
	if solved:
		var weak: bool = evidence_score(case) < MISJUDGMENT_EVIDENCE_LINE
		var coerced: bool = bool(case.get("coerced", false))
		risk = clampf((0.5 if weak else 0.0) + (0.4 if coerced else 0.0), 0.0, 1.0)
		wrongful = weak and coerced
		case["wrongful"] = wrongful
	case["misjudgment_risk"] = risk
	return {
		"ok": true, "solved": solved, "probability": prob, "roll": roll,
		"stage": case["stage"], "misjudgment_risk": risk, "wrongful": wrongful,
		"evidence_score": evidence_score(case), "legality": legality_score(case),
	}


## 滥用职权：记违法并压低合法性，抬高误判风险。
func abuse_power(case: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var legal: Dictionary = case["legal"]
	legal["violations"] = int(legal.get("violations", 0)) + 1
	legal["procedure_legal"] = false
	case["misjudgment_risk"] = clampf(float(case.get("misjudgment_risk", 0.0)) + 0.2, 0.0, 1.0)
	return {"ok": true, "violations": int(legal["violations"]), "legality": legality_score(case)}


## 腐败串通：隐匿关键证据以放水，埋下串通隐患。
func collude(case: Dictionary, opts: Dictionary = {}, rng = null) -> Dictionary:
	var roll: float = _roll(float(opts.get("roll", -1.0)), rng)
	var exposed: bool = roll < 0.2
	var ev: Dictionary = case["evidence"]
	ev["physical"] = clampf(float(ev["physical"]) - 0.3, 0.0, 1.0)
	return {"ok": true, "suppressed": true, "exposed": exposed, "score": evidence_score(case)}


# --- 民营安保 ---

func new_security_firm(name: String, opts: Dictionary = {}) -> Dictionary:
	return {
		"name": name,
		"staff": maxi(0, int(opts.get("staff", 0))),
		"funds": maxi(0, int(opts.get("funds", 0))),
		"reputation": clampf(float(opts.get("reputation", 0.5)), 0.0, 1.0),
		"contracts": [],
	}


func take_contract(firm: Dictionary, kind: String, opts: Dictionary = {}) -> Dictionary:
	if not SECURITY_SERVICES.has(kind):
		return {"ok": false, "reason": "unknown_service"}
	var def: Dictionary = SECURITY_SERVICES[kind]
	var required: int = int(def["staff_required"])
	var staff: int = int(firm.get("staff", 0))
	var understaffed: bool = staff < required
	var contract: Dictionary = {
		"kind": kind, "name": str(def["name"]),
		"fee": int(opts.get("fee", def["base_fee"])),
		"required_staff": required,
		"understaffed": understaffed,
		"risk": clampf(float(def["risk"]) - float(firm.get("reputation", 0.0)) * 0.1, 0.0, 1.0),
		"client": str(opts.get("client", "")),
		"resolved": false,
	}
	(firm["contracts"] as Array).append(contract)
	return {"ok": true, "contract": contract, "understaffed": understaffed}


## 履约结算：人手不足或声誉过低导致安保失职并承担赔偿。
func resolve_contract(firm: Dictionary, contract: Dictionary, opts: Dictionary = {}, rng = null) -> Dictionary:
	var roll: float = _roll(float(opts.get("roll", -1.0)), rng)
	var fail_prob: float = clampf(float(contract.get("risk", 0.0)) + (0.4 if bool(contract.get("understaffed", false)) else 0.0), 0.0, 0.95)
	var failure: bool = roll < fail_prob
	contract["resolved"] = true
	contract["failure"] = failure
	var payment: int = int(contract.get("fee", 0))
	var liability: int = 0
	if failure:
		liability = int(round(float(payment) * 1.5))
		firm["funds"] = int(firm.get("funds", 0)) - liability
		firm["reputation"] = clampf(float(firm.get("reputation", 0.0)) - 0.15, 0.0, 1.0)
	else:
		firm["funds"] = int(firm.get("funds", 0)) + payment
		firm["reputation"] = clampf(float(firm.get("reputation", 0.0)) + 0.02, 0.0, 1.0)
	return {
		"ok": true, "success": not failure, "failure": failure,
		"payment": payment, "liability": liability,
		"reputation": float(firm["reputation"]),
	}


func assign_staff(firm: Dictionary, count: int) -> Dictionary:
	firm["staff"] = maxi(0, int(firm.get("staff", 0)) + count)
	return {"ok": true, "staff": int(firm["staff"])}


# --- 序列化 ---

func to_dict(state: Dictionary) -> Dictionary:
	return state.duplicate(true)


func from_dict(data: Dictionary) -> Dictionary:
	return data.duplicate(true)
