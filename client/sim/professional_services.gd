class_name ProfessionalServicesSystem
extends RefCounted
## 专业服务业（R92；design D48）。
##
## 覆盖：
##   - 路径：会计审计、管理咨询、投资银行、猎头、公关广告、市场调研、检测认证、法律；
##   - 执业：注册会计师 / 特许金融分析师 / 律师等专业资质与声誉共同决定接单能力；
##   - 经营：开设事务所或咨询公司，合伙人制度，客户开发、项目制、尽职调查与并购顾问；
##   - 风险：虚假报告、内幕交易、商业贿赂触发法律与声誉后果，审计独立性冲突；
##   - 边界：竞业限制、客户流失、合伙人分裂带走客户。
##
## 设计取舍：
##   - 事务所、合伙人、客户、项目均为纯数据 Dictionary，便于存读档与 headless 测试；
##   - 通行判定统一走 _roll(forced, rng)，缺省确定化，测试注入 roll 即可复现；
##   - 与既有系统解耦：法律定罪、公司经营、声誉大盘以结构化返回值交给上层编排。

## 执业类型：名称、必需资质、基准费用、风险度与是否含审计独立性约束。
const PRACTICE_TYPES: Dictionary = {
	"accounting_audit": {"name": "会计审计", "cert": "cpa", "base_fee": 200000, "risk": 0.40, "independence": true},
	"consulting": {"name": "管理咨询", "cert": "", "base_fee": 500000, "risk": 0.20, "independence": false},
	"investment_banking": {"name": "投资银行", "cert": "cfa", "base_fee": 1500000, "risk": 0.50, "independence": true},
	"headhunting": {"name": "猎头", "cert": "", "base_fee": 150000, "risk": 0.15, "independence": false},
	"pr_advertising": {"name": "公关广告", "cert": "", "base_fee": 300000, "risk": 0.35, "independence": false},
	"market_research": {"name": "市场调研", "cert": "", "base_fee": 120000, "risk": 0.25, "independence": false},
	"certification": {"name": "检测认证", "cert": "", "base_fee": 100000, "risk": 0.30, "independence": true},
	"legal": {"name": "法律", "cert": "lawyer", "base_fee": 250000, "risk": 0.30, "independence": true},
}

## 专业资质：名称、考试费、难度与持证声誉加成。
const QUALIFICATIONS: Dictionary = {
	"cpa": {"name": "注册会计师", "exam_fee": 50000, "difficulty": 0.60, "reputation": 0.15},
	"cfa": {"name": "特许金融分析师", "exam_fee": 80000, "difficulty": 0.70, "reputation": 0.20},
	"lawyer": {"name": "律师执业证", "exam_fee": 60000, "difficulty": 0.65, "reputation": 0.18},
}

var _seq: int = 0


func _roll(forced: float, rng) -> float:
	if forced >= 0.0:
		return clampf(forced, 0.0, 1.0)
	if rng != null:
		return rng.next_float()
	return 0.0


# --- 数据表 ---

func practice_type_keys() -> Array:
	return PRACTICE_TYPES.keys()


func practice_type_def(key: String) -> Dictionary:
	if not PRACTICE_TYPES.has(key):
		return {}
	return (PRACTICE_TYPES[key] as Dictionary).duplicate(true)


func practice_type_name(key: String) -> String:
	return str((PRACTICE_TYPES.get(key, {}) as Dictionary).get("name", key))


func qualification_keys() -> Array:
	return QUALIFICATIONS.keys()


func qualification_def(key: String) -> Dictionary:
	if not QUALIFICATIONS.has(key):
		return {}
	return (QUALIFICATIONS[key] as Dictionary).duplicate(true)


func qualification_name(key: String) -> String:
	return str((QUALIFICATIONS.get(key, {}) as Dictionary).get("name", key))


# --- 事务所与合伙人 ---

## 开设事务所 / 咨询公司。
func new_firm(opts: Dictionary = {}) -> Dictionary:
	_seq += 1
	return {
		"id": str(opts.get("id", "firm.%d" % _seq)),
		"name": str(opts.get("name", "专业事务所")),
		"money": maxi(0, int(opts.get("money", 1000000))),
		"reputation": clampf(float(opts.get("reputation", 0.5)), 0.0, 1.0),
		"qualifications": {},
		"partners": {},
		"clients": {},
		"projects": [],
		"violations": [],
	}


## 考取专业资质：付费应试，技能与难度决定通过率，通过则提升声誉。
func acquire_qualification(firm: Dictionary, cert: String, opts: Dictionary = {}, rng = null) -> Dictionary:
	if not QUALIFICATIONS.has(cert):
		return {"ok": false, "reason": "unknown_cert"}
	if (firm["qualifications"] as Dictionary).has(cert):
		return {"ok": false, "reason": "already_qualified"}
	var fee: int = int((QUALIFICATIONS[cert] as Dictionary)["exam_fee"])
	if int(firm["money"]) < fee:
		return {"ok": false, "reason": "insufficient_funds", "fee": fee}
	firm["money"] = int(firm["money"]) - fee
	var skill: float = clampf(float(opts.get("skill", 0.5)), 0.0, 1.0)
	var difficulty: float = float((QUALIFICATIONS[cert] as Dictionary)["difficulty"])
	var pass_prob: float = clampf(skill * 1.2 + 0.2 - difficulty * 0.5, 0.05, 0.95)
	var roll: float = _roll(float(opts.get("roll", -1.0)), rng)
	var passed: bool = roll < pass_prob
	if passed:
		(firm["qualifications"] as Dictionary)[cert] = true
		firm["reputation"] = clampf(float(firm["reputation"]) + float((QUALIFICATIONS[cert] as Dictionary)["reputation"]), 0.0, 1.0)
	return {"ok": true, "cert": cert, "passed": passed, "pass_prob": pass_prob, "fee": fee}


## 接单能力：由资质是否齐备与声誉共同决定，用于上层按能力派单。
func gatekeep_capacity(firm: Dictionary, practice_type: String) -> Dictionary:
	if not PRACTICE_TYPES.has(practice_type):
		return {"ok": false, "reason": "unknown_practice"}
	var req: String = str((PRACTICE_TYPES[practice_type] as Dictionary).get("cert", ""))
	var has_cert: bool = req == "" or (firm["qualifications"] as Dictionary).has(req)
	var rep: float = float(firm["reputation"])
	var capacity: float = clampf(rep * (1.2 if has_cert else 0.4), 0.0, 1.0)
	return {"ok": true, "capacity": capacity, "qualified": has_cert, "required_cert": req, "reputation": rep}


## 吸收合伙人：记录份额，并可带入自有客户。
func add_partner(firm: Dictionary, partner_id: String, opts: Dictionary = {}) -> Dictionary:
	var partners: Dictionary = firm["partners"]
	if partners.has(partner_id):
		return {"ok": false, "reason": "already_partner"}
	var share: float = clampf(float(opts.get("share", 0.2)), 0.0, 0.9)
	var clients: int = maxi(0, int(opts.get("clients", 0)))
	partners[partner_id] = {"share": share, "clients": clients}
	firm["partners"] = partners
	var c: Dictionary = firm["clients"]
	for i in range(clients):
		c["%s.c%d" % [partner_id, i]] = {"size": 1, "satisfaction": 0.6, "origin": partner_id}
	firm["clients"] = c
	return {"ok": true, "partner": partner_id, "share": share, "clients_brought": clients}


## 合伙人分裂：带走自有客户并按其份额比例带走其他客户，冲击声誉。
func partner_split(firm: Dictionary, partner_id: String, opts: Dictionary = {}, rng = null) -> Dictionary:
	var partners: Dictionary = firm["partners"]
	if not partners.has(partner_id):
		return {"ok": false, "reason": "not_partner"}
	var poach_rate: float = clampf(float(opts.get("poach_rate", 0.3)), 0.0, 1.0)
	var c: Dictionary = firm["clients"]
	var own: Array = []
	var others: Array = []
	for cid in c.keys():
		if str((c[cid] as Dictionary).get("origin", "")) == partner_id:
			own.append(cid)
		else:
			others.append(cid)
	others.sort()
	var poach_n: int = int(round(float(others.size()) * poach_rate))
	var carried: Array = own.duplicate()
	for i in range(poach_n):
		carried.append(others[i])
	for cid in carried:
		c.erase(cid)
	partners.erase(partner_id)
	var rep_hit: float = clampf(float(opts.get("reputation_hit", 0.15)), 0.0, 1.0)
	var total: int = maxi(1, carried.size() + c.size())
	firm["reputation"] = clampf(float(firm["reputation"]) - rep_hit * (0.5 + 0.5 * float(carried.size()) / float(total)), 0.0, 1.0)
	firm["partners"] = partners
	firm["clients"] = c
	return {"ok": true, "partner": partner_id, "clients_carried": carried.size(), "reputation": float(firm["reputation"])}


# --- 客户与项目 ---

## 客户开发：声誉决定成败，成功后按声誉与掷骰生成客户规模。
func client_acquisition(firm: Dictionary, opts: Dictionary = {}, rng = null) -> Dictionary:
	var rep: float = float(firm["reputation"])
	var roll: float = _roll(float(opts.get("roll", -1.0)), rng)
	var success_prob: float = clampf(0.2 + rep * 0.7, 0.05, 0.95)
	var success: bool = roll < success_prob
	if not success:
		return {"ok": true, "success": false, "success_prob": success_prob}
	var size: int = maxi(1, int(round(float(opts.get("base_size", 1)) * (0.5 + rep + roll))))
	var cid: String = "client.%s.%d" % [firm["id"], (firm["clients"] as Dictionary).size() + 1]
	(firm["clients"] as Dictionary)[cid] = {"size": size, "satisfaction": 0.6, "origin": "acquisition"}
	return {"ok": true, "success": true, "client": cid, "size": size, "success_prob": success_prob}


## 立项：项目制交付，费用来自执业类型基准。
func new_project(firm: Dictionary, client_id: String, practice_type: String, opts: Dictionary = {}) -> Dictionary:
	if not PRACTICE_TYPES.has(practice_type):
		return {"ok": false, "reason": "unknown_practice"}
	_seq += 1
	var base_fee: int = int((PRACTICE_TYPES[practice_type] as Dictionary)["base_fee"])
	var project: Dictionary = {
		"id": str(opts.get("id", "project.%d" % _seq)),
		"practice": practice_type,
		"client": client_id,
		"fee": maxi(0, int(opts.get("fee", base_fee))),
		"findings": [],
		"risk": clampf(float((PRACTICE_TYPES[practice_type] as Dictionary)["risk"]), 0.0, 1.0),
		"status": "open",
	}
	(firm["projects"] as Array).append(project)
	return {"ok": true, "project": project}


## 尽职调查：核查深度决定发现问题的概率。
func due_diligence(project: Dictionary, opts: Dictionary = {}, rng = null) -> Dictionary:
	var depth: float = clampf(float(opts.get("depth", 0.5)), 0.0, 1.0)
	var roll: float = _roll(float(opts.get("roll", -1.0)), rng)
	var findings: Array = []
	if roll < depth * 0.8:
		findings.append(str(opts.get("finding", "material_issue")))
	if project.has("findings"):
		(project["findings"] as Array).append_array(findings)
	return {"ok": true, "findings": findings, "depth": depth}


## 并购顾问：按交易额抽佣，成败由判定决定。
func ma_advisory(project: Dictionary, opts: Dictionary = {}, rng = null) -> Dictionary:
	var deal_size: int = maxi(0, int(opts.get("deal_size", 0)))
	var rate: float = clampf(float(opts.get("fee_rate", 0.02)), 0.0, 0.2)
	var success_prob: float = clampf(float(opts.get("success_prob", 0.6)), 0.0, 1.0)
	var roll: float = _roll(float(opts.get("roll", -1.0)), rng)
	var success: bool = roll < success_prob
	var fee: int = int(round(float(deal_size) * rate)) if success else 0
	project["status"] = "closed" if success else "open"
	return {"ok": true, "success": success, "fee": fee, "deal_size": deal_size}


## 审计独立性冲突：同一客户同时持有审计与非审计角色即为冲突。
func independence_conflict(client: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var roles: Array = client.get("roles", [])
	var audit: bool = roles.has("audit")
	var non_audit: bool = roles.has("consulting") or roles.has("advisory") or roles.has("tax") or roles.has("bookkeeping")
	var conflict: bool = audit and non_audit
	return {"ok": true, "conflict": conflict, "roles": roles.duplicate(), "reason": str(opts.get("reason", "independence"))}


# --- 执业风险 ---

## 虚假报告：严重度决定罚金，稽查掷骰决定是否被查处。
func false_report(firm: Dictionary, project: Dictionary, opts: Dictionary = {}, rng = null) -> Dictionary:
	var severity: float = clampf(float(opts.get("severity", 0.6)), 0.0, 1.0)
	var detection: float = clampf(float(opts.get("detection", 0.4)), 0.0, 1.0)
	var roll: float = _roll(float(opts.get("roll", -1.0)), rng)
	var exposed: bool = roll < detection
	var fine: int = 0
	var rep_delta: float = -severity * 0.3
	if exposed:
		fine = int(round(severity * float(opts.get("max_fine", 2000000.0))))
		rep_delta = -severity * 0.6
		(firm["violations"] as Array).append({"type": "false_report", "project": str(project.get("id", ""))})
	firm["reputation"] = clampf(float(firm["reputation"]) + rep_delta, 0.0, 1.0)
	return {"ok": true, "exposed": exposed, "fine": fine, "reputation_delta": rep_delta, "legal": exposed, "severity": severity}


## 内幕交易：获利越大处罚越重，超额触刑。
func insider_trading(firm: Dictionary, opts: Dictionary = {}, rng = null) -> Dictionary:
	var profit: int = maxi(0, int(opts.get("profit", 0)))
	var detection: float = clampf(float(opts.get("detection", 0.5)), 0.0, 1.0)
	var roll: float = _roll(float(opts.get("roll", -1.0)), rng)
	var exposed: bool = roll < detection
	var fine: int = int(round(float(profit) * float(opts.get("fine_mult", 2.0)))) if exposed else 0
	var legal: bool = exposed and profit > int(opts.get("criminal_threshold", 500000))
	firm["reputation"] = clampf(float(firm["reputation"]) - (0.4 if exposed else 0.05), 0.0, 1.0)
	if exposed:
		(firm["violations"] as Array).append({"type": "insider_trading"})
	return {"ok": true, "exposed": exposed, "fine": fine, "legal": legal, "profit": profit}


## 商业贿赂：被查处则罚款、声誉受损，达额触刑。
func commercial_bribery(firm: Dictionary, opts: Dictionary = {}, rng = null) -> Dictionary:
	var amount: int = maxi(0, int(opts.get("amount", 0)))
	var detection: float = clampf(float(opts.get("detection", 0.45)), 0.0, 1.0)
	var roll: float = _roll(float(opts.get("roll", -1.0)), rng)
	var exposed: bool = roll < detection
	var fine: int = int(round(float(amount) * float(opts.get("fine_mult", 1.5)))) if exposed else 0
	var legal: bool = exposed and amount >= int(opts.get("criminal_threshold", 100000))
	firm["reputation"] = clampf(float(firm["reputation"]) - (0.35 if exposed else 0.0), 0.0, 1.0)
	if exposed:
		(firm["violations"] as Array).append({"type": "commercial_bribery"})
	return {"ok": true, "exposed": exposed, "fine": fine, "legal": legal}


# --- 边界：竞业与客户流失 ---

## 竞业限制：有竞业条款且跳槽到竞争对手构成违约。
func non_compete_violation(opts: Dictionary = {}) -> Dictionary:
	var has_clause: bool = bool(opts.get("has_clause", true))
	var moved_to_competitor: bool = bool(opts.get("moved_to_competitor", true))
	var violation: bool = has_clause and moved_to_competitor
	return {"ok": true, "violation": violation, "damages": int(opts.get("damages", 500000)) if violation else 0}


## 客户流失：低声誉抬升流失率，按比例流失（取排序后前 N）。
func client_churn(firm: Dictionary, opts: Dictionary = {}, rng = null) -> Dictionary:
	var c: Dictionary = firm["clients"]
	var churn_rate: float = clampf(float(opts.get("churn_rate", 0.1)) + (1.0 - float(firm["reputation"])) * 0.2, 0.0, 1.0)
	var ids: Array = c.keys()
	ids.sort()
	var n: int = int(round(float(ids.size()) * churn_rate))
	var lost: Array = []
	for i in range(n):
		lost.append(ids[i])
	for cid in lost:
		c.erase(cid)
	firm["clients"] = c
	return {"ok": true, "lost": lost.size(), "churn_rate": churn_rate}


# --- 序列化 ---

func to_dict(state: Dictionary) -> Dictionary:
	return state.duplicate(true)


func from_dict(data: Dictionary) -> Dictionary:
	return data.duplicate(true)
