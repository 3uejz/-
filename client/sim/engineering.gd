class_name EngineeringSystem
extends RefCounted
## 建筑、工程与城市规划（R91；design D47）。
##
## 覆盖：
##   - 工程链条：勘察 → 设计 → 造价 → 施工 → 监理 → 验收；资质分级（特级/一级/二级）
##     与挂靠/转包；
##   - 承接：私人工程与政府招投标；中标由资质、报价、关系与围标决定，含招投标腐败；
##   - 风险：工程事故、偷工减料、欠款、三角债触发追责与损失（联动 D12、R21）；
##   - 城市规划：规划改变地价、交通、人口流动、功能区（联动 D9、D50），含规划腐败；
##   - 房地产：开发商、楼盘、预售、烂尾（联动 D9）；
##   - 边界：烂尾、三角债、安全事故致死（联动 R9）、规划变更与拆迁。
##
## 设计取舍：
##   - 工程/城市/开发商均为纯数据 Dictionary，便于存读档与 headless 测试；
##   - 事故风险对风险因素单调：偷工减料/转包深度/资质缺口抬高，监理力度/安全投入压低；
##   - 招投标以分数加权并可用注入 roll 断言，围标与腐败作为可拆解的独立入口；
##   - 三角债用有序债权链模拟违约传染，简单可解释；
##   - 一切随机由外部 roll/rng 注入，缺省确定化。

## 资质分级：可承接工程规模上限、注册资本门槛与投标加成。
const QUALIFICATIONS: Dictionary = {
	"special": {"name": "特级", "max_scale": 1000000000, "min_capital": 50000000, "bid_bonus": 0.15},
	"first": {"name": "一级", "max_scale": 300000000, "min_capital": 10000000, "bid_bonus": 0.08},
	"second": {"name": "二级", "max_scale": 80000000, "min_capital": 2000000, "bid_bonus": 0.00},
}

## 工程链条阶段：费用占比、工期占比与质量权重。
const STAGES: Dictionary = {
	"survey": {"name": "勘察", "cost_ratio": 0.03, "duration_ratio": 0.08, "quality_weight": 0.10},
	"design": {"name": "设计", "cost_ratio": 0.07, "duration_ratio": 0.15, "quality_weight": 0.20},
	"cost_estimation": {"name": "造价", "cost_ratio": 0.02, "duration_ratio": 0.04, "quality_weight": 0.05},
	"construction": {"name": "施工", "cost_ratio": 0.70, "duration_ratio": 0.55, "quality_weight": 0.40},
	"supervision": {"name": "监理", "cost_ratio": 0.03, "duration_ratio": 0.10, "quality_weight": 0.15},
	"acceptance": {"name": "验收", "cost_ratio": 0.01, "duration_ratio": 0.03, "quality_weight": 0.10},
}

## 链条执行顺序。
const CHAIN: Array = ["survey", "design", "cost_estimation", "construction", "supervision", "acceptance"]

## 承接方式。
const PROCUREMENT_MODES: Dictionary = {
	"private": {"name": "私人工程"},
	"government_tender": {"name": "政府招投标"},
}

## 城市规划功能区：基准地价系数、人口吸引与交通需求。
const ZONE_TYPES: Dictionary = {
	"residential": {"name": "居住区", "land_mult": 1.0, "population_pull": 1.0, "traffic_demand": 0.6},
	"commercial": {"name": "商业区", "land_mult": 1.8, "population_pull": 0.3, "traffic_demand": 1.0},
	"industrial": {"name": "工业区", "land_mult": 0.7, "population_pull": 0.4, "traffic_demand": 0.8},
	"mixed": {"name": "综合区", "land_mult": 1.3, "population_pull": 0.8, "traffic_demand": 0.9},
	"green": {"name": "绿地", "land_mult": 0.5, "population_pull": 0.2, "traffic_demand": 0.2},
}

## 验收合格所需的工程质量门槛。
const ACCEPTANCE_QUALITY_THRESHOLD: float = 0.6

var _seq: int = 0


func _roll(forced: float, rng) -> float:
	if forced >= 0.0:
		return clampf(forced, 0.0, 1.0)
	if rng != null:
		return rng.next_float()
	return 0.0


# --- 数据表 ---

func qualification_keys() -> Array:
	return QUALIFICATIONS.keys()


func qualification_def(key: String) -> Dictionary:
	if not QUALIFICATIONS.has(key):
		return {}
	return (QUALIFICATIONS[key] as Dictionary).duplicate(true)


func qualification_name(key: String) -> String:
	return str((QUALIFICATIONS.get(key, {}) as Dictionary).get("name", key))


func stage_keys() -> Array:
	return STAGES.keys()


func stage_def(key: String) -> Dictionary:
	if not STAGES.has(key):
		return {}
	return (STAGES[key] as Dictionary).duplicate(true)


func zone_type_keys() -> Array:
	return ZONE_TYPES.keys()


func zone_type_def(key: String) -> Dictionary:
	if not ZONE_TYPES.has(key):
		return {}
	return (ZONE_TYPES[key] as Dictionary).duplicate(true)


func procurement_name(key: String) -> String:
	return str((PROCUREMENT_MODES.get(key, {}) as Dictionary).get("name", key))


# --- 工程主体与项目 ---

## 新建承包商/施工单位。
func new_contractor(opts: Dictionary = {}) -> Dictionary:
	_seq += 1
	return {
		"id": str(opts.get("id", "contractor.%d" % _seq)),
		"name": str(opts.get("name", "施工单位")),
		"qualification": str(opts.get("qualification", "second")),
		"capital": maxi(0, int(opts.get("capital", 5000000))),
		"workmanship": clampf(float(opts.get("workmanship", 0.6)), 0.0, 1.0),
		"relationship": clampf(float(opts.get("relationship", 0.3)), 0.0, 1.0),
		"reputation": clampf(float(opts.get("reputation", 0.6)), 0.0, 1.0),
	}


## 新建工程项目。required_qualification 缺省按规模推导。
func new_project(opts: Dictionary = {}) -> Dictionary:
	_seq += 1
	var scale: int = maxi(1, int(opts.get("scale", 50000000)))
	return {
		"id": str(opts.get("id", "project.%d" % _seq)),
		"name": str(opts.get("name", "工程项目")),
		"scale": scale,
		"budget": maxi(0, int(opts.get("budget", scale))),
		"required_qualification": str(opts.get("required_qualification", _required_qualification(scale))),
		"procurement": str(opts.get("procurement", "private")),
		"stage": CHAIN[0],
		"stage_index": 0,
		"quality": 0.0,
		"quality_weight_sum": 0.0,
		"cut_corners": clampf(float(opts.get("cut_corners", 0.0)), 0.0, 1.0),
		"subcontract_depth": maxi(0, int(opts.get("subcontract_depth", 0))),
		"illegal_subcontract": false,
		"supervision_strength": 0.0,
		"contractor": "",
		"progress": 0.0,
		"accepted": false,
		"rework_count": 0,
		"accident": false,
	}


func _required_qualification(scale: int) -> String:
	if scale > int((QUALIFICATIONS["first"] as Dictionary)["max_scale"]):
		return "special"
	if scale > int((QUALIFICATIONS["second"] as Dictionary)["max_scale"]):
		return "first"
	return "second"


## 资质校验：可承接规模上限与注册资本门槛。
func can_undertake(contractor: Dictionary, project: Dictionary) -> Dictionary:
	var q: String = str(contractor.get("qualification", ""))
	if not QUALIFICATIONS.has(q):
		return {"ok": false, "reason": "unknown_qualification"}
	var max_scale: int = int((QUALIFICATIONS[q] as Dictionary)["max_scale"])
	var min_cap: int = int((QUALIFICATIONS[q] as Dictionary)["min_capital"])
	if int(project.get("scale", 0)) > max_scale:
		return {"ok": false, "reason": "scale_exceeds_qualification", "max_scale": max_scale}
	if int(contractor.get("capital", 0)) < min_cap:
		return {"ok": false, "reason": "insufficient_capital", "min_capital": min_cap}
	return {"ok": true, "qualification": q}


# --- 工程链条 ---

## 挂靠/转包判定：借用他人资质或超次数转包即违法。
func assess_subcontract(project: Dictionary, contractor: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var depth: int = maxi(0, int(opts.get("subcontract_depth", project.get("subcontract_depth", 0))))
	var borrowed: bool = bool(opts.get("borrowed_qualification", false))
	var max_depth: int = maxi(0, int(opts.get("max_depth", 1)))
	var illegal: bool = borrowed or depth > max_depth
	# 资质是否满足项目要求（挂靠即资质不足而借用）。
	var actual_q: String = str(contractor.get("qualification", "second"))
	var required_q: String = str(project.get("required_qualification", "second"))
	var q_gap: int = maxi(0, int(_qualification_rank(required_q)) - int(_qualification_rank(actual_q)))
	project["subcontract_depth"] = depth
	project["illegal_subcontract"] = illegal
	return {
		"ok": true, "borrowed_qualification": borrowed, "depth": depth,
		"illegal": illegal, "qualification_gap": q_gap,
	}


func _qualification_rank(q: String) -> int:
	match q:
		"special": return 3
		"first": return 2
		"second": return 1
		_: return 0


## 施工：质量随工艺、监理、偷工减料与转包变化；累计进度与安全水平。
func construct(project: Dictionary, contractor: Dictionary, opts: Dictionary = {}, rng = null) -> Dictionary:
	var can: Dictionary = can_undertake(contractor, project)
	var borrowed: bool = bool(opts.get("borrowed_qualification", false))
	if not bool(can["ok"]) and not borrowed:
		return {"ok": false, "reason": str(can.get("reason", "unqualified"))}
	var sub: Dictionary = assess_subcontract(project, contractor, opts)
	var workmanship: float = clampf(float(contractor.get("workmanship", 0.6)), 0.0, 1.0)
	var supervision: float = clampf(float(project.get("supervision_strength", opts.get("supervision_strength", 0.3))), 0.0, 1.0)
	var cut: float = clampf(float(opts.get("cut_corners", project.get("cut_corners", 0.0))), 0.0, 1.0)
	var gap: int = int(sub["qualification_gap"])
	var depth: int = int(sub["depth"])
	var stage_quality: float = clampf(
		0.20 + workmanship * 0.50 + supervision * 0.20
		- cut * 0.55 - float(gap) * 0.15 - float(depth) * 0.05, 0.0, 1.0)
	project["cut_corners"] = cut
	project["supervision_strength"] = supervision
	project["contractor"] = str(contractor.get("id", ""))
	project["quality"] = _blend_quality(project, "construction", stage_quality)
	var pace: float = clampf(float(opts.get("pace", 1.0)), 0.0, 2.0)
	project["progress"] = clampf(float(project.get("progress", 0.0)) + pace / maxf(1.0, float(CHAIN.size())), 0.0, 1.0)
	return {
		"ok": true, "stage": "construction", "stage_quality": stage_quality,
		"quality": float(project["quality"]), "illegal_subcontract": bool(project["illegal_subcontract"]),
		"qualification_gap": gap, "progress": float(project["progress"]),
	}


## 监理：监理力度与投入决定能否发现质量缺陷；质检不合格需整改。
func supervise(project: Dictionary, opts: Dictionary = {}, rng = null) -> Dictionary:
	var strength: float = clampf(float(opts.get("supervision_strength", project.get("supervision_strength", 0.3))), 0.0, 1.0)
	project["supervision_strength"] = strength
	var quality: float = clampf(float(project.get("quality", 0.5)), 0.0, 1.0)
	var shortfall: float = clampf(1.0 - quality, 0.0, 1.0)
	var roll: float = _roll(float(opts.get("roll", -1.0)), rng)
	var found: bool = roll < clampf(strength + shortfall * 0.3, 0.0, 0.95)
	return {
		"ok": true, "stage": "supervision", "strength": strength,
		"found_defect": found, "shortfall": shortfall,
	}


## 质量加权融合：各阶段按权重累积。
func _blend_quality(project: Dictionary, stage: String, stage_quality: float) -> float:
	var weight: float = float((STAGES[stage] as Dictionary)["quality_weight"])
	var prev: float = float(project.get("quality", 0.0))
	var prev_sum: float = float(project.get("quality_weight_sum", 0.0))
	var new_sum: float = prev_sum + weight
	var blended: float = 0.0
	if new_sum > 0.0:
		blended = (prev * prev_sum + stage_quality * weight) / new_sum
	project["quality"] = clampf(blended, 0.0, 1.0)
	project["quality_weight_sum"] = new_sum
	return float(project["quality"])


## 验收：质量不达标则拒绝验收，触发整改或返工。
func accept(project: Dictionary, opts: Dictionary = {}, rng = null) -> Dictionary:
	var threshold: float = clampf(float(opts.get("threshold", ACCEPTANCE_QUALITY_THRESHOLD)), 0.0, 1.0)
	var quality: float = clampf(float(project.get("quality", 0.5)), 0.0, 1.0)
	var passed: bool = quality >= threshold
	if passed:
		project["accepted"] = true
		return {"ok": true, "passed": true, "quality": quality, "threshold": threshold, "accepted": true}
	var rework: bool = bool(opts.get("rework", true))
	if rework:
		var improve: float = clampf(float(opts.get("rework_gain", 0.15)), 0.0, 1.0)
		project["quality"] = clampf(quality + improve, 0.0, 1.0)
		project["rework_count"] = int(project.get("rework_count", 0)) + 1
	return {
		"ok": true, "passed": false, "quality": quality, "threshold": threshold,
		"accepted": false, "rework": rework, "rework_count": int(project.get("rework_count", 0)),
	}


## 通用推进：按链条顺序执行下一个阶段，成功后进入下一阶段。
func advance_stage(project: Dictionary, contractor: Dictionary, opts: Dictionary = {}, rng = null) -> Dictionary:
	var idx: int = int(project.get("stage_index", 0))
	if idx >= CHAIN.size():
		return {"ok": false, "reason": "completed"}
	var stage: String = str(CHAIN[idx])
	var out: Dictionary
	match stage:
		"survey":
			out = _survey(project, opts)
		"design":
			out = _design(project, opts)
		"cost_estimation":
			out = _cost_estimation(project, opts)
		"construction":
			out = construct(project, contractor, opts, rng)
		"supervision":
			out = supervise(project, opts, rng)
		"acceptance":
			out = accept(project, opts, rng)
		_:
			out = {"ok": false, "reason": "unknown_stage"}
	if bool(out.get("ok", false)):
		project["stage_index"] = idx + 1
		project["stage"] = str(CHAIN[idx + 1]) if idx + 1 < CHAIN.size() else "completed"
	return out


func _survey(project: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var q: float = clampf(float(opts.get("survey_quality", 0.5)), 0.0, 1.0)
	project["quality"] = _blend_quality(project, "survey", q)
	return {"ok": true, "stage": "survey", "quality": float(project["quality"])}


func _design(project: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var q: float = clampf(float(opts.get("design_quality", 0.5)), 0.0, 1.0)
	project["quality"] = _blend_quality(project, "design", q)
	return {"ok": true, "stage": "design", "quality": float(project["quality"])}


func _cost_estimation(project: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var q: float = clampf(float(opts.get("estimate_quality", 0.6)), 0.0, 1.0)
	if opts.has("budget"):
		project["budget"] = maxi(0, int(opts["budget"]))
	project["quality"] = _blend_quality(project, "cost_estimation", q)
	return {"ok": true, "stage": "cost_estimation", "budget": int(project["budget"]), "quality": float(project["quality"])}


# --- 招投标 ---

## 投标评分：资质匹配、报价、关系、声誉与围标加成。
## 资质不足的直接出局（返回 disqualified）。
func bid_score(contractor: Dictionary, project: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var q: String = str(contractor.get("qualification", "second"))
	if not QUALIFICATIONS.has(q):
		return {"ok": false, "reason": "unknown_qualification"}
	var max_scale: int = int((QUALIFICATIONS[q] as Dictionary)["max_scale"])
	if int(project.get("scale", 0)) > max_scale:
		return {"ok": true, "disqualified": true, "score": 0.0, "reason": "scale_exceeds_qualification"}
	var price: int = maxi(1, int(opts.get("price", int(project.get("budget", 0)))))
	var budget: float = maxf(1.0, float(project.get("budget", price)))
	var price_score: float = clampf(2.0 - float(price) / budget, 0.0, 1.0)
	var relationship: float = clampf(float(contractor.get("relationship", 0.3)), 0.0, 1.0)
	var reputation: float = clampf(float(contractor.get("reputation", 0.6)), 0.0, 1.0)
	var bid_bonus: float = float((QUALIFICATIONS[q] as Dictionary)["bid_bonus"])
	var collusion: float = clampf(float(opts.get("collusion_bonus", 0.0)), 0.0, 1.0)
	var corruption: float = clampf(float(opts.get("corruption_bonus", 0.0)), 0.0, 1.0)
	var score: float = clampf(
		price_score * 0.35 + relationship * 0.25 + reputation * 0.15
		+ bid_bonus + collusion * 0.15 + corruption * 0.20, 0.0, 2.0)
	return {
		"ok": true, "disqualified": false, "score": score, "price_score": price_score,
		"quality": q, "bid_bonus": bid_bonus,
	}


## 招投标：合格投标人按评分加权随机定标；围标与腐败提高指定者中标率。
## bidders 元素：{id, qualification, price, relationship, reputation, collusion_bonus, corruption_bonus}
func tender(project: Dictionary, bidders: Array, opts: Dictionary = {}, rng = null) -> Dictionary:
	var scored: Array = []
	var total: float = 0.0
	for b in bidders:
		var cand: Dictionary = b
		var s: Dictionary = bid_score(cand, project, cand)
		var entry: Dictionary = {"id": str(cand.get("id", "")), "score": float(s.get("score", 0.0)), "disqualified": bool(s.get("disqualified", false))}
		scored.append(entry)
		if not bool(entry["disqualified"]):
			total += float(entry["score"])
	if total <= 0.0:
		return {"ok": false, "reason": "no_qualified_bidder", "scores": scored}
	var roll: float = _roll(float(opts.get("roll", -1.0)), rng) * total
	var acc: float = 0.0
	var winner: String = ""
	for e in scored:
		if bool(e["disqualified"]):
			continue
		acc += float(e["score"])
		if roll < acc:
			winner = str(e["id"])
			break
	if winner == "":
		for e in scored:
			if not bool(e["disqualified"]):
				winner = str(e["id"])
	return {"ok": true, "winner": winner, "scores": scored, "pool": total}


## 围标：若干投标人结成同盟，抬高指定中标人的加成并压低陪标报价。
func rig_bids(bidders: Array, winner_id: String, opts: Dictionary = {}) -> Dictionary:
	var boost: float = clampf(float(opts.get("collusion_bonus", 0.4)), 0.0, 1.0)
	var marked: Array = []
	for b in bidders:
		var cand: Dictionary = b
		var is_winner: bool = str(cand.get("id", "")) == winner_id
		cand["collusion_bonus"] = boost if is_winner else float(opts.get("accomplice_bonus", 0.0))
		if not is_winner:
			cand["price"] = int(round(float(cand.get("price", 0)) * float(opts.get("accomplice_price_mult", 1.2))))
		marked.append(cand)
	return {"ok": true, "winner_id": winner_id, "bidders": marked, "collusion_bonus": boost}


## 招投标腐败：贿赂提高中标率，但有被查处风险。
func tender_corruption(project: Dictionary, opts: Dictionary = {}, rng = null) -> Dictionary:
	var bribe: int = maxi(0, int(opts.get("bribe", 0)))
	var detect_prob: float = clampf(float(opts.get("detect_prob", 0.3)) + float(bribe) / 100000000.0, 0.0, 0.95)
	var roll: float = _roll(float(opts.get("roll", -1.0)), rng)
	var exposed: bool = roll < detect_prob
	var bonus: float = clampf(float(bribe) / 20000000.0, 0.0, 0.6)
	var fine: int = int(round(float(bribe) * 3.0)) if exposed else 0
	var criminal: bool = exposed and bribe >= int(opts.get("criminal_threshold", 10000000))
	return {"ok": true, "bribe": bribe, "collusion_bonus": bonus, "exposed": exposed, "fine": fine, "criminal": criminal}


# --- 工程风险 ---

## 工程事故风险：对风险因素单调。
##   cut_corners/subcontract_depth/qualification_gap 越高风险越高；
##   supervision_strength/workmanship 越高风险越低。
func accident_risk(project: Dictionary, opts: Dictionary = {}) -> float:
	var base: float = maxf(0.0, float(opts.get("base_risk", 0.02)))
	var cut: float = clampf(float(opts.get("cut_corners", project.get("cut_corners", 0.0))), 0.0, 1.0)
	var depth: int = maxi(0, int(opts.get("subcontract_depth", project.get("subcontract_depth", 0))))
	var gap: int = maxi(0, int(opts.get("qualification_gap", 0)))
	var supervision: float = clampf(float(opts.get("supervision_strength", project.get("supervision_strength", 0.3))), 0.0, 1.0)
	var workmanship: float = clampf(float(opts.get("workmanship", 0.6)), 0.0, 1.0)
	var illegal: float = 1.0 if bool(project.get("illegal_subcontract", false)) else 0.0
	var hazard: float = 0.3 + cut * 1.2 + float(depth) * 0.25 + float(gap) * 0.5 + illegal * 0.3
	var mitigation: float = clampf(supervision * 0.4 + workmanship * 0.3, 0.0, 0.7)
	var risk: float = (base + 0.04 * hazard) * (1.0 - mitigation)
	return clampf(risk, 0.0, 0.95)


## 工程事故：按事故风险掷骰；发生则结算损失、致死与追责。
func engineering_accident(project: Dictionary, opts: Dictionary = {}, rng = null) -> Dictionary:
	var risk: float = accident_risk(project, opts)
	var roll: float = _roll(float(opts.get("roll", -1.0)), rng)
	var occurred: bool = roll < risk
	if not occurred:
		return {"ok": true, "occurred": false, "risk": risk, "roll": roll}
	project["accident"] = true
	var severity: float = clampf(risk * clampf(float(opts.get("severity_mult", 1.5)), 0.0, 3.0), 0.0, 1.0)
	var scale_factor: float = clampf(float(project.get("scale", 0)) / 100000000.0, 0.0, 3.0)
	var deaths: int = mini(9, int(round(severity * (1.0 + scale_factor))))
	var loss: int = int(round(severity * float(project.get("budget", 0)) * 0.2 + float(deaths) * 1000000.0))
	var accountability: Dictionary = assign_accountability(project, {"severity": severity, "deaths": deaths})
	return {
		"ok": true, "occurred": true, "risk": risk, "roll": roll,
		"severity": severity, "deaths": deaths, "loss": loss, "accountability": accountability,
	}


## 事故追责：过失越重、违法转包越明显，责任与处罚越大；致死者刑事责任。
func assign_accountability(project: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var severity: float = clampf(float(opts.get("severity", 0.5)), 0.0, 1.0)
	var deaths: int = maxi(0, int(opts.get("deaths", 0)))
	var negligent: bool = bool(opts.get("negligent", true))
	var cut: float = clampf(float(project.get("cut_corners", 0.0)), 0.0, 1.0)
	var illegal: bool = bool(project.get("illegal_subcontract", false))
	var liability: float = clampf(severity * (1.0 if negligent else 0.4) + cut * 0.3 + (0.2 if illegal else 0.0), 0.0, 1.0)
	var fine: int = int(round(liability * float(opts.get("max_fine", 5000000.0))))
	var compensation: int = int(round(liability * (0.5 + float(deaths)) * float(opts.get("per_victim", 2000000.0))))
	var criminal: bool = deaths >= 1 and (illegal or cut > 0.4 or liability > 0.6)
	return {
		"ok": true, "liability": liability, "fine": fine,
		"compensation": compensation, "criminal": criminal, "deaths": deaths,
	}


## 偷工减料：直接降低质量并抬高事故风险。
func cut_corners(project: Dictionary, degree: float, opts: Dictionary = {}) -> Dictionary:
	var d: float = clampf(degree, 0.0, 1.0)
	var saved: int = int(round(float(project.get("budget", 0)) * d * 0.2))
	project["cut_corners"] = d
	project["quality"] = clampf(float(project.get("quality", 0.6)) - d * 0.3, 0.0, 1.0)
	return {
		"ok": true, "degree": d, "saved": saved,
		"quality": float(project["quality"]), "accident_risk": accident_risk(project, opts),
	}


# --- 欠款与三角债 ---

## 欠款：业主拖欠承包商，承包商无力垫付则停工并累积利息。
func arrears(contractor: Dictionary, amount: int, opts: Dictionary = {}) -> Dictionary:
	var owed: int = maxi(0, amount)
	var liquidity: float = clampf(float(contractor.get("capital", 0)) / maxf(1.0, float(owed)), 0.0, 1.0)
	var stop_work: bool = liquidity < clampf(float(opts.get("stop_threshold", 0.5)), 0.0, 1.0)
	var interest: int = int(round(float(owed) * clampf(float(opts.get("interest_rate", 0.1)), 0.0, 1.0)))
	return {
		"ok": true, "owed": owed, "liquidity": liquidity,
		"stop_work": stop_work, "interest": interest,
	}


## 三角债：有序债权链中一处违约向下游传染。
## chain 元素为实体标识（字符串），形如 A 欠 B、B 欠 C、C 欠 A。
func debt_chain(chain: Array, amount: int, opts: Dictionary = {}) -> Dictionary:
	var n: int = chain.size()
	if n < 2:
		return {"ok": false, "reason": "chain_too_short"}
	var contagion: float = clampf(float(opts.get("contagion", 0.6)), 0.0, 1.0)
	var start: int = clampi(int(opts.get("start_default", 0)), 0, n - 1)
	var links: Array = []
	var defaults: Array = []
	var total_arrears: int = 0
	var remaining: int = maxi(0, amount)
	for i in n:
		var from_id: String = str(chain[i])
		var to_id: String = str(chain[(i + 1) % n])
		var link: Dictionary = {"from": from_id, "to": to_id, "amount": remaining}
		if i >= start:
			link["paid"] = 0
			link["defaulted"] = true
			defaults.append(from_id)
			total_arrears += remaining
			remaining = int(round(float(remaining) * contagion))
		else:
			link["paid"] = remaining
			link["defaulted"] = false
		links.append(link)
	return {
		"ok": true, "links": links, "defaults": defaults,
		"default_count": defaults.size(), "total_arrears": total_arrears, "residual": remaining,
	}


# --- 城市规划 ---

## 新建城市：地价、交通、人口与各功能区。
func new_city(opts: Dictionary = {}) -> Dictionary:
	_seq += 1
	return {
		"id": str(opts.get("id", "city.%d" % _seq)),
		"name": str(opts.get("name", "新城")),
		"population": maxi(0, int(opts.get("population", 1000000))),
		"land_price": maxf(1.0, float(opts.get("land_price", 10000.0))),
		"traffic": clampf(float(opts.get("traffic", 0.5)), 0.0, 1.0),
		"zones": {},
		"corruption": 0.0,
	}


## 功能区定义与当前地价。zones 存 {zone_id: {type, land_price, traffic_demand}}。
func land_value(city: Dictionary, zone_id: String = "") -> Dictionary:
	if zone_id == "":
		return {"ok": true, "city_land_price": float(city.get("land_price", 0.0))}
	var zones: Dictionary = city.get("zones", {})
	if not zones.has(zone_id):
		return {"ok": false, "reason": "unknown_zone"}
	return {"ok": true, "land_price": float((zones[zone_id] as Dictionary).get("land_price", 0.0))}


## 规划变更（rezone）：改变功能区类型，联动地价、交通与人口流动。
func rezone(city: Dictionary, zone_id: String, new_type: String, opts: Dictionary = {}) -> Dictionary:
	if not ZONE_TYPES.has(new_type):
		return {"ok": false, "reason": "unknown_zone_type"}
	var zones: Dictionary = city.get("zones", {})
	var zone: Dictionary = zones.get(zone_id, {"type": "residential", "land_price": float(city.get("land_price", 0.0))})
	var def: Dictionary = ZONE_TYPES[new_type]
	var old_price: float = float(zone.get("land_price", city.get("land_price", 0.0)))
	var base_price: float = maxf(1.0, float(city.get("land_price", 10000.0)))
	var new_price: float = base_price * float(def["land_mult"])
	# 交通需求上升则改善交通，供给不足则拥堵下降。
	var traffic_pull: float = float(def["traffic_demand"])
	var old_traffic: float = float(city.get("traffic", 0.5))
	var investment: float = clampf(float(opts.get("transport_investment", 0.0)), 0.0, 1.0)
	var new_traffic: float = clampf(old_traffic + investment * 0.3 - maxf(0.0, traffic_pull - 0.6) * 0.1, 0.0, 1.0)
	city["traffic"] = new_traffic
	# 人口流动。
	var pop: int = int(city.get("population", 0))
	var pull: float = float(def["population_pull"]) - 0.5
	var delta: int = int(round(float(pop) * pull * clampf(float(opts.get("migration_rate", 0.05)), 0.0, 1.0)))
	city["population"] = maxi(0, pop + delta)
	zone["type"] = new_type
	zone["land_price"] = new_price
	zone["traffic_demand"] = traffic_pull
	zones[zone_id] = zone
	city["zones"] = zones
	# 全城地价按功能区加权轻微联动。
	city["land_price"] = maxf(1.0, (city["land_price"] as float) * 0.95 + new_price * 0.05)
	return {
		"ok": true, "zone_id": zone_id, "type": new_type,
		"old_land_price": old_price, "new_land_price": new_price,
		"land_delta": new_price - old_price, "traffic": new_traffic,
		"population": int(city["population"]), "population_delta": delta,
	}


## 交通工程：改善交通并抬升沿线地价。
func transport_project(city: Dictionary, zone_id: String, opts: Dictionary = {}) -> Dictionary:
	var improvement: float = clampf(float(opts.get("improvement", 0.2)), 0.0, 1.0)
	city["traffic"] = clampf(float(city.get("traffic", 0.5)) + improvement, 0.0, 1.0)
	var zones: Dictionary = city.get("zones", {})
	var land_delta: float = 0.0
	if zones.has(zone_id):
		var zone: Dictionary = zones[zone_id]
		var old: float = float(zone.get("land_price", 0.0))
		zone["land_price"] = old * (1.0 + improvement * 0.5)
		land_delta = float(zone["land_price"]) - old
		zones[zone_id] = zone
	city["zones"] = zones
	return {"ok": true, "traffic": float(city["traffic"]), "land_delta": land_delta}


## 规划腐败：违规调规或提高容积率换取好处，地价虚高但存在查处风险。
func planning_corruption(city: Dictionary, opts: Dictionary = {}, rng = null) -> Dictionary:
	var bribe: int = maxi(0, int(opts.get("bribe", 0)))
	var detect_prob: float = clampf(float(opts.get("detect_prob", 0.3)) + float(bribe) / 100000000.0, 0.0, 0.95)
	var roll: float = _roll(float(opts.get("roll", -1.0)), rng)
	var exposed: bool = roll < detect_prob
	var land_bubble: float = clampf(float(bribe) / 50000000.0, 0.0, 0.5)
	city["land_price"] = maxf(1.0, float(city["land_price"]) * (1.0 + land_bubble))
	city["corruption"] = clampf(float(city.get("corruption", 0.0)) + (0.0 if exposed else land_bubble * 0.5), 0.0, 1.0)
	var fine: int = int(round(float(bribe) * 3.0)) if exposed else 0
	return {"ok": true, "land_bubble": land_bubble, "exposed": exposed, "fine": fine, "land_price": float(city["land_price"])}


## 拆迁：征收某功能区，支付补偿并迁移人口；补偿不足引发纠纷。
func demolition(city: Dictionary, zone_id: String, opts: Dictionary = {}) -> Dictionary:
	var zones: Dictionary = city.get("zones", {})
	if not zones.has(zone_id):
		return {"ok": false, "reason": "unknown_zone"}
	var residents: int = maxi(0, int(opts.get("residents", 1000)))
	var compensation_per: int = maxi(0, int(opts.get("compensation_per", 200000)))
	var fair_value: int = int(round(float((zones[zone_id] as Dictionary).get("land_price", 0.0)) * 0.1))
	var fair: bool = compensation_per >= fair_value
	var total: int = residents * compensation_per
	var disputes: int = 0 if fair else int(round(float(residents) * 0.3))
	city["population"] = maxi(0, int(city.get("population", 0)) - residents)
	return {
		"ok": true, "residents": residents, "compensation": total,
		"fair": fair, "disputes": disputes, "population": int(city["population"]),
	}


# --- 房地产 ---

## 新建开发商。
func new_developer(opts: Dictionary = {}) -> Dictionary:
	_seq += 1
	return {
		"id": str(opts.get("id", "developer.%d" % _seq)),
		"name": str(opts.get("name", "开发商")),
		"cash": maxi(0, int(opts.get("cash", 50000000))),
		"debt": maxi(0, int(opts.get("debt", 0))),
		"projects": [],
	}


## 预售：回笼资金，但形成交付义务。
func pre_sale(developer: Dictionary, project: Dictionary, units: int, unit_price: int, opts: Dictionary = {}) -> Dictionary:
	var n: int = maxi(0, units)
	var income: int = n * maxi(0, unit_price)
	developer["cash"] = int(developer.get("cash", 0)) + income
	project["pre_sold"] = int(project.get("pre_sold", 0)) + n
	return {"ok": true, "units": n, "income": income, "cash": int(developer["cash"])}


## 楼盘施工：消耗资金推进进度。
func develop_project(developer: Dictionary, project: Dictionary, cost: int, opts: Dictionary = {}) -> Dictionary:
	var spend: int = maxi(0, cost)
	if int(developer.get("cash", 0)) < spend:
		return {"ok": false, "reason": "insufficient_funds", "cost": spend}
	developer["cash"] = int(developer["cash"]) - spend
	var pace: float = clampf(float(opts.get("pace", 0.2)), 0.0, 1.0)
	project["progress"] = clampf(float(project.get("progress", 0.0)) + pace, 0.0, 1.0)
	project["completed"] = float(project["progress"]) >= 1.0
	return {"ok": true, "cost": spend, "progress": float(project["progress"]), "completed": bool(project["completed"]), "cash": int(developer["cash"])}


## 烂尾：资金链断裂导致项目停滞，预售买家受损。
func unfinished(developer: Dictionary, project: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var deficit: int = maxi(0, int(project.get("remaining_cost", 0)) - int(developer.get("cash", 0)))
	var stalled: bool = deficit > 0
	if stalled:
		project["unfinished"] = true
		project["completed"] = false
	var buyers_lost: int = int(project.get("pre_sold", 0)) * maxi(0, int(project.get("unit_price", 0))) if stalled else 0
	return {"ok": true, "stalled": stalled, "deficit": deficit, "buyers_lost": buyers_lost}


# --- 序列化 ---

func to_dict(state: Dictionary) -> Dictionary:
	return state.duplicate(true)


func from_dict(data: Dictionary) -> Dictionary:
	return data.duplicate(true)
