class_name HonorsSystem
extends RefCounted
## 荣誉、奖项与名人堂（R78；design D34）。
##
## 覆盖：
##   - 六大领域奖项：学术/艺术/体育/商业/公共/军事，各设评审规则、门槛与评选周期；
##   - 评定流程：成就达标 → 提名 → 评审 → 颁奖 → 入名人堂，评审偏好与关系影响结果；
##   - 黑幕：买奖、学术造假、评审腐败作为隐蔽标记，可被揭露并反噬；
##   - 影响：提升声望、职业机会、婚恋与传承评价，并解锁特权；
##   - 名人堂：永久记录并可跨代传承评价；
##   - 边界：奖项争议、并列、被撤销与奖项政治化。
##
## 设计取舍：
##   - 候选人与名人堂均为纯数据 Dictionary，便于存读档与 headless 测试；
##   - 评审得分为确定性的加权和（成就/关系/同行 + 偏好加成 + 黑幕/政治化修正），
##     便于属性测试验证“成就越高、关系越强、政治压力越大”等单调关系；
##   - 黑幕以 hidden/revealed 双态标记，未被揭露不影响评审（甚至加分成全买奖），
##     揭露时统一清算声望与荣誉，形成“隐蔽—曝光—反噬”闭环。

const BaselineScript = preload("res://sim/baseline.gd")

const CATEGORY_ACADEMIC: String = "academic"
const CATEGORY_ARTS: String = "arts"
const CATEGORY_SPORTS: String = "sports"
const CATEGORY_BUSINESS: String = "business"
const CATEGORY_PUBLIC: String = "public"
const CATEGORY_MILITARY: String = "military"

const CATEGORIES: Array = ["academic", "arts", "sports", "business", "public", "military"]

const CATEGORY_NAMES: Dictionary = {
	"academic": "学术", "arts": "艺术", "sports": "体育",
	"business": "商业", "public": "公共", "military": "军事",
}

## 奖项表。threshold 为成就门槛（0..100）；period_days 为评选周期；
## pass_line 为评审通过线（0..1）；bias 为评审偏好维度；jury_weights 为评审权重。
const AWARDS: Dictionary = {
	"academic_prize": {
		"name": "学术成就奖", "category": "academic", "threshold": 70.0, "period_days": 365,
		"prestige": 88.0, "pass_line": 0.60, "bias": "achievement",
		"jury_weights": {"achievement": 0.60, "relations": 0.20, "peer": 0.20},
	},
	"arts_prize": {
		"name": "艺术大奖", "category": "arts", "threshold": 65.0, "period_days": 365,
		"prestige": 82.0, "pass_line": 0.58, "bias": "relations",
		"jury_weights": {"achievement": 0.50, "relations": 0.30, "peer": 0.20},
	},
	"sports_title": {
		"name": "体育冠军称号", "category": "sports", "threshold": 75.0, "period_days": 730,
		"prestige": 85.0, "pass_line": 0.62, "bias": "peer",
		"jury_weights": {"achievement": 0.65, "relations": 0.10, "peer": 0.25},
	},
	"business_award": {
		"name": "年度商业人物", "category": "business", "threshold": 60.0, "period_days": 365,
		"prestige": 78.0, "pass_line": 0.56, "bias": "relations",
		"jury_weights": {"achievement": 0.45, "relations": 0.35, "peer": 0.20},
	},
	"public_service_medal": {
		"name": "公共服务勋章", "category": "public", "threshold": 55.0, "period_days": 365,
		"prestige": 80.0, "pass_line": 0.55, "bias": "peer",
		"jury_weights": {"achievement": 0.40, "relations": 0.25, "peer": 0.35},
	},
	"military_honor": {
		"name": "军事荣誉勋章", "category": "military", "threshold": 80.0, "period_days": 1095,
		"prestige": 92.0, "pass_line": 0.65, "bias": "achievement",
		"jury_weights": {"achievement": 0.70, "relations": 0.10, "peer": 0.20},
	},
}

const SCANDAL_BOUGHT_AWARD: String = "bought_award"
const SCANDAL_ACADEMIC_FRAUD: String = "academic_fraud"
const SCANDAL_JURY_CORRUPTION: String = "jury_corruption"
const SCANDAL_KINDS: Array = ["bought_award", "academic_fraud", "jury_corruption"]

const BIAS_BONUS: float = BaselineScript.HONOR_BIAS_BONUS
const TIE_EPSILON: float = BaselineScript.HONOR_TIE_EPSILON
const ENSHRINE_MIN_PRESTIGE: float = BaselineScript.HONOR_ENSHRINE_MIN_PRESTIGE


# --- 数据表 ---

func categories() -> Array:
	return CATEGORIES.duplicate()


func category_count() -> int:
	return CATEGORIES.size()


func category_name(key: String) -> String:
	return str(CATEGORY_NAMES.get(key, key))


func award_keys() -> Array:
	return AWARDS.keys()


func award_count() -> int:
	return AWARDS.size()


func award_def(key: String) -> Dictionary:
	if not AWARDS.has(key):
		return {}
	return (AWARDS[key] as Dictionary).duplicate(true)


# --- 候选人 ---

## 新建候选人档案。achievement/relations 为 0..100 与 0..1。
func new_candidate(id: String, opts: Dictionary = {}) -> Dictionary:
	return {
		"id": id,
		"name": str(opts.get("name", id)),
		"achievement": clampf(float(opts.get("achievement", 0.0)), 0.0, 100.0),
		"relations": clampf(float(opts.get("relations", 0.0)), 0.0, 1.0),
		"reputation": clampf(float(opts.get("reputation", 0.0)), 0.0, 100.0),
		"honors": [],
		"scandals": [],
		"jury_relations": {},
		"privileges": [],
	}


func set_achievement(candidate: Dictionary, value: float) -> Dictionary:
	candidate["achievement"] = clampf(value, 0.0, 100.0)
	return {"ok": true, "achievement": float(candidate["achievement"])}


## 建立与某评审的关系（0..1），影响评审偏好结果。
func set_jury_relation(candidate: Dictionary, jury_id: String, value: float) -> Dictionary:
	var table: Dictionary = candidate["jury_relations"]
	table[jury_id] = clampf(value, 0.0, 1.0)
	candidate["jury_relations"] = table
	return {"ok": true, "jury_id": jury_id, "relation": float(table[jury_id])}


# --- 提名与评审 ---

## 提名：成就达到奖项门槛方可进入评审。
func nominate(candidate: Dictionary, award_key: String, opts: Dictionary = {}) -> Dictionary:
	if not AWARDS.has(award_key):
		return {"ok": false, "reason": "unknown_award"}
	var def: Dictionary = AWARDS[award_key]
	var threshold: float = float(def["threshold"])
	var ach: float = float(candidate.get("achievement", 0.0))
	var eligible: bool = ach >= threshold
	return {
		"ok": true, "eligible": eligible, "award": award_key,
		"category": str(def["category"]), "threshold": threshold,
		"achievement": ach, "gap": maxf(0.0, threshold - ach),
	}


## 评审：确定性加权得分。关系（含评审私人关系）与评审偏好影响通过与否；
## 未揭露的买奖/评审腐败在腐败评审下会抬分；政治化压力会压低得分。
func evaluate(candidate: Dictionary, award_key: String, jury: Dictionary = {}, opts: Dictionary = {}) -> Dictionary:
	if not AWARDS.has(award_key):
		return {"ok": false, "reason": "unknown_award"}
	var def: Dictionary = AWARDS[award_key]
	var weights: Dictionary = def["jury_weights"]
	var bias: String = str(def["bias"])
	var jury_id: String = str(jury.get("id", ""))
	var ach: float = clampf(float(candidate.get("achievement", 0.0)) / 100.0, 0.0, 1.0)
	var rel: float = clampf(float(candidate.get("relations", 0.0)), 0.0, 1.0)
	var jury_rel: float = clampf(float((candidate.get("jury_relations", {}) as Dictionary).get(jury_id, 0.0)), 0.0, 1.0)
	var peer: float = clampf(float(jury.get("peer_review", ach)), 0.0, 1.0)
	var dims: Dictionary = {
		"achievement": ach,
		"relations": rel * 0.5 + jury_rel * 0.5,
		"peer": peer,
	}
	var score: float = 0.0
	for k in weights.keys():
		score += float(weights[k]) * float(dims.get(k, 0.0))
	# 评审偏好：偏好维度获得额外加成。
	if dims.has(bias):
		score += BIAS_BONUS * float(dims[bias])
	# 黑幕：买奖 + 评审腐败共同抬分（隐蔽，未揭露）。
	var corruption: float = clampf(float(jury.get("corruption", 0.0)), 0.0, 1.0)
	if has_scandal(candidate, SCANDAL_BOUGHT_AWARD):
		score += 0.25 * corruption
	if has_scandal(candidate, SCANDAL_JURY_CORRUPTION):
		score += 0.15
	# 已揭露的学术造假直接扣分。
	if has_revealed_scandal(candidate, SCANDAL_ACADEMIC_FRAUD):
		score -= 0.30
	# 奖项政治化：外部压力压低评审得分。
	var political: float = clampf(float(opts.get("political_pressure", 0.0)), 0.0, 1.0)
	score *= 1.0 - 0.35 * political
	score = clampf(score, 0.0, 1.0)
	return {
		"ok": true, "award": award_key, "score": score,
		"pass_line": float(def["pass_line"]), "passed": score >= float(def["pass_line"]),
		"bias": bias, "corruption": corruption, "political_pressure": political,
	}


## 完整评定：提名 → 评审 → 颁奖；通过则登记荣誉并提升声望。
## opts: jury/corruption/political_pressure/enshrine/hall/minute/generation。
func award(candidate: Dictionary, award_key: String, jury: Dictionary = {}, opts: Dictionary = {}) -> Dictionary:
	var nom: Dictionary = nominate(candidate, award_key, opts)
	if not bool(nom.get("ok", false)):
		return nom
	if not bool(nom["eligible"]):
		return {"ok": true, "awarded": false, "reason": "below_threshold", "nomination": nom}
	var ev: Dictionary = evaluate(candidate, award_key, jury, opts)
	if not bool(ev["passed"]):
		return {"ok": true, "awarded": false, "reason": "jury_rejected", "nomination": nom, "evaluation": ev}
	var def: Dictionary = AWARDS[award_key]
	var honor: Dictionary = {
		"id": "%s.%s.%d" % [str(candidate.get("id", "")), award_key, (candidate["honors"] as Array).size()],
		"award": award_key, "name": str(def["name"]), "category": str(def["category"]),
		"prestige": float(def["prestige"]), "minute": int(opts.get("minute", 0)),
		"generation": int(opts.get("generation", 0)), "revoked": false,
	}
	(candidate["honors"] as Array).append(honor)
	candidate["reputation"] = clampf(float(candidate.get("reputation", 0.0)) + float(def["prestige"]) * 0.1, 0.0, 100.0)
	var result: Dictionary = {"ok": true, "awarded": true, "honor": honor, "nomination": nom, "evaluation": ev}
	var hall: Variant = opts.get("hall", null)
	if bool(opts.get("enshrine", true)) and hall is Dictionary and float(def["prestige"]) >= ENSHRINE_MIN_PRESTIGE:
		result["enshrined"] = enshrine(hall as Dictionary, candidate, honor, opts)
	return result


# --- 黑幕 ---

## 打上隐蔽黑幕标记。kind: bought_award/academic_fraud/jury_corruption。
func mark_scandal(candidate: Dictionary, kind: String, opts: Dictionary = {}) -> Dictionary:
	if not SCANDAL_KINDS.has(kind):
		return {"ok": false, "reason": "unknown_scandal"}
	var scandal: Dictionary = {
		"kind": kind, "hidden": true, "revealed": false,
		"severity": clampf(float(opts.get("severity", 0.7)), 0.0, 1.0),
		"minute": int(opts.get("minute", 0)),
	}
	(candidate["scandals"] as Array).append(scandal)
	return {"ok": true, "scandal": scandal}


func has_scandal(candidate: Dictionary, kind: String) -> bool:
	for s in (candidate.get("scandals", []) as Array):
		if str((s as Dictionary).get("kind", "")) == kind and bool((s as Dictionary).get("hidden", false)):
			return true
	return false


func has_revealed_scandal(candidate: Dictionary, kind: String) -> bool:
	for s in (candidate.get("scandals", []) as Array):
		if str((s as Dictionary).get("kind", "")) == kind and bool((s as Dictionary).get("revealed", false)):
			return true
	return false


## 揭露一桩隐蔽黑幕：登记为已曝光，扣除荣誉与声望；可同步撤销名人堂记录。
## opts: hall/kind。
func expose_scandal(candidate: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var scandals: Array = candidate["scandals"]
	var target: Dictionary = {}
	var want_kind: String = str(opts.get("kind", ""))
	for s in scandals:
		var d: Dictionary = s
		if bool(d.get("hidden", false)) and (want_kind.is_empty() or str(d.get("kind", "")) == want_kind):
			target = d
			break
	if target.is_empty():
		return {"ok": true, "exposed": false, "reason": "no_hidden_scandal"}
	target["hidden"] = false
	target["revealed"] = true
	var severity: float = float(target.get("severity", 0.7))
	var reputation_delta: float = -round(severity * 40.0)
	candidate["reputation"] = clampf(float(candidate.get("reputation", 0.0)) + reputation_delta, 0.0, 100.0)
	# 身败名裂：现有荣誉一并撤销（名人堂记录由 revoke 处理）。
	var revoked_honors: int = (candidate["honors"] as Array).size()
	candidate["honors"] = []
	candidate["privileges"] = []
	var revoked_hall: int = 0
	var hall: Variant = opts.get("hall", null)
	if hall is Dictionary:
		revoked_hall = int(revoke(hall as Dictionary, str(candidate.get("id", "")), {"reason": "scandal"})["revoked"])
	return {
		"ok": true, "exposed": true, "kind": str(target.get("kind", "")),
		"reputation_delta": reputation_delta, "revoked_honors": revoked_honors,
		"revoked_hall": revoked_hall,
	}


# --- 名人堂与传承 ---

func new_hall() -> Dictionary:
	return {"entries": []}


## 入名人堂：永久记录（可被 revoke 标记撤销）。
func enshrine(hall: Dictionary, candidate: Dictionary, honor: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var entries: Array = hall["entries"]
	var entry: Dictionary = {
		"id": "%s#%d" % [str(honor.get("id", "honor")), entries.size()],
		"candidate_id": str(candidate.get("id", "")),
		"candidate_name": str(candidate.get("name", "")),
		"award": str(honor.get("award", "")), "category": str(honor.get("category", "")),
		"prestige": float(honor.get("prestige", 0.0)),
		"generation": int(opts.get("generation", honor.get("generation", 0))),
		"minute": int(opts.get("minute", honor.get("minute", 0))),
		"status": "active",
	}
	entries.append(entry)
	return {"ok": true, "entry": entry, "hall_size": entries.size()}


func hall_size(hall: Dictionary) -> int:
	return (hall.get("entries", []) as Array).size()


func hall_entries_of(hall: Dictionary, candidate_id: String) -> Array:
	var out: Array = []
	for e in (hall.get("entries", []) as Array):
		if str((e as Dictionary).get("candidate_id", "")) == candidate_id:
			out.append(e)
	return out


## 撤销名人堂记录（奖项争议/被撤销）。opts: reason。
func revoke(hall: Dictionary, candidate_id: String, opts: Dictionary = {}) -> Dictionary:
	var count: int = 0
	for e in (hall.get("entries", []) as Array):
		var d: Dictionary = e
		if str(d.get("candidate_id", "")) == candidate_id and str(d.get("status", "active")) == "active":
			d["status"] = "revoked"
			d["revoke_reason"] = str(opts.get("reason", "dispute"))
			count += 1
	return {"ok": true, "revoked": count}


## 跨代传承评价：汇总在世与已故祖先的名人堂荣誉，折算后代起点声望与加成。
## opts: generation（仅统计该代及更早，缺省统计全部）。
func inherit_evaluation(hall: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var max_gen: int = int(opts.get("generation", 9999))
	var heritage_score: float = 0.0
	var active_count: int = 0
	for e in (hall.get("entries", []) as Array):
		var d: Dictionary = e
		if str(d.get("status", "active")) != "active":
			continue
		if int(d.get("generation", 0)) > max_gen:
			continue
		heritage_score += float(d.get("prestige", 0.0))
		active_count += 1
	heritage_score = clampf(heritage_score, 0.0, 300.0)
	return {
		"ok": true, "heritage_score": heritage_score,
		"start_reputation": clampf(heritage_score * 0.05, 0.0, 15.0),
		"active_honors": active_count,
		"career_bonus": clampf(heritage_score / 300.0, 0.0, 1.0) * 0.1,
	}


# --- 并列与影响 ---

## 处理评审并列：eps 内并列则共享、决选或由评委会定夺。
func resolve_tie(candidates: Array, opts: Dictionary = {}) -> Dictionary:
	var eps: float = float(opts.get("epsilon", TIE_EPSILON))
	var best: float = -1.0
	for c in candidates:
		best = maxf(best, float((c as Dictionary).get("score", 0.0)))
	var tied: Array = []
	for c in candidates:
		if absf(float((c as Dictionary).get("score", 0.0)) - best) <= eps:
			tied.append(str((c as Dictionary).get("id", "")))
	if tied.size() <= 1:
		return {"ok": true, "tie": false, "winner": tied[0] if not tied.is_empty() else ""}
	return {
		"ok": true, "tie": true, "tied": tied, "top_score": best,
		"resolution": str(opts.get("resolution", "shared")),
	}


## 荣誉带来的综合影响：声望、职业机会、婚恋与传承评价、解锁特权。
func honor_effects(candidate: Dictionary) -> Dictionary:
	var fame: float = 0.0
	var career: float = 0.0
	var marriage: float = 0.0
	var privileges: Array = []
	for h in (candidate.get("honors", []) as Array):
		var d: Dictionary = h
		if bool(d.get("revoked", false)):
			continue
		var prestige: float = float(d.get("prestige", 0.0))
		fame += prestige * 0.1
		career += prestige * 0.02
		marriage += prestige * 0.01
		var category: String = str(d.get("category", ""))
		if category == CATEGORY_ACADEMIC and not privileges.has("research_grant"):
			privileges.append("research_grant")
		elif category == CATEGORY_BUSINESS and not privileges.has("elite_club"):
			privileges.append("elite_club")
		elif category == CATEGORY_PUBLIC and not privileges.has("public_office"):
			privileges.append("public_office")
		elif category == CATEGORY_MILITARY and not privileges.has("state_funeral"):
			privileges.append("state_funeral")
	candidate["privileges"] = privileges.duplicate()
	return {
		"ok": true, "fame": fame, "career_opportunity": career,
		"marriage_appraisal": marriage, "inheritance_appraisal": fame * 0.5,
		"privileges": privileges,
	}


# --- 序列化 ---

func to_dict(state: Dictionary) -> Dictionary:
	return state.duplicate(true)


func from_dict(data: Dictionary) -> Dictionary:
	return data.duplicate(true)
