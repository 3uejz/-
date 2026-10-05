class_name ResearchSystem
extends RefCounted
## 科研流程与成果转化（R45.4-5；design D5）。
##
## 链路：选题 → 文献 → 实验 → 数据 → 论文 → 同行评审 → 发表 → 引用 → 职称。
## 资源约束：需实验室、仪器、经费与团队；成果质量 = 技能 + 投入 + 创新 + 运气 − 竞争。
## 成果可产出声望、收入与引用，重大成果推动时代解锁；可申请专利。
##
## 设计取舍：
##   - 项目状态存于独立 project 字典；资源、技能与随机源均由调用方注入，便于测试与复现；
##   - 经费以最小货币单位整数从 resources["funding"] 扣减，收入经 EconomySystem 注入。

const STAGES: Array = ["topic", "literature", "experiment", "data", "paper", "peer_review", "published", "rejected"]

const STARTUP_COST: int = 1000000
const EXPERIMENT_COST: int = 500000
const PEER_REVIEW_THRESHOLD: float = 50.0
const PATENT_MIN_QUALITY: float = 70.0
const PUBLISH_PRESTIGE_FACTOR: float = 0.5
const PUBLISH_INCOME_PER_QUALITY: int = 5000
const ERA_UNLOCK_QUALITY: float = 90.0

const SKILL_WEIGHT: float = 0.4
const INVESTMENT_WEIGHT: float = 0.3
const INNOVATION_WEIGHT: float = 0.2
const LUCK_WEIGHT: float = 0.1


func new_project(topic: String) -> Dictionary:
	return {
		"topic": topic, "stage": "topic", "quality": 0.0,
		"published": false, "citations": 0, "patented": false,
		"log": [],
	}


## 立项：校验实验室/仪器/经费/团队，并扣除启动经费。
func start_project(topic: String, resources: Dictionary, opts: Dictionary = {}) -> Dictionary:
	if topic.strip_edges().is_empty():
		return {"ok": false, "reason": "empty_topic"}
	if not bool(resources.get("lab", false)):
		return {"ok": false, "reason": "no_lab"}
	if int(resources.get("equipment", 0)) < 1:
		return {"ok": false, "reason": "no_equipment"}
	if int(resources.get("team", 0)) < 1:
		return {"ok": false, "reason": "no_team"}
	var cost: int = int(opts.get("startup_cost", STARTUP_COST))
	if int(resources.get("funding", 0)) < cost:
		return {"ok": false, "reason": "insufficient_funding"}
	resources["funding"] = int(resources.get("funding", 0)) - cost
	var project: Dictionary = new_project(topic)
	project["log"].append("立项")
	return {"ok": true, "project": project, "spent": cost}


func _skill_score(skills: Array, skill_id: String = "skill.academic") -> float:
	for s in skills:
		if str((s as Dictionary).get("content_key", "")) == skill_id:
			return clampf(float((s as Dictionary).get("level", 0)) / 20.0 * 100.0, 0.0, 100.0)
	return 0.0


## 成果质量 0..100。
func quality(skills: Array, investment: float, innovation: float, luck_roll: float, competition: float = 0.0) -> float:
	var q: float = (
		SKILL_WEIGHT * _skill_score(skills)
		+ INVESTMENT_WEIGHT * clampf(investment, 0.0, 100.0)
		+ INNOVATION_WEIGHT * clampf(innovation, 0.0, 100.0)
		+ LUCK_WEIGHT * clampf(luck_roll, 0.0, 100.0)
		- clampf(competition, 0.0, 100.0)
	)
	return clampf(q, 0.0, 100.0)


## 推进一步。ctx：skills、investment、innovation、competition、rng、now_minute。
func advance(project: Dictionary, resources: Dictionary, ctx: Dictionary = {}) -> Dictionary:
	var stage: String = str(project.get("stage", "topic"))
	if stage == "published" or stage == "rejected":
		return {"ok": false, "reason": "finished", "stage": stage}
	match stage:
		"topic":
			project["stage"] = "literature"
		"literature":
			project["stage"] = "experiment"
		"experiment":
			var cost: int = int(ctx.get("experiment_cost", EXPERIMENT_COST))
			if int(resources.get("funding", 0)) < cost:
				return {"ok": false, "reason": "insufficient_funding", "stage": stage}
			resources["funding"] = int(resources.get("funding", 0)) - cost
			project["stage"] = "data"
		"data":
			var rng = ctx.get("rng", null)
			var luck_roll: float = 50.0
			if rng != null:
				luck_roll = rng.next_float() * 100.0
			project["quality"] = quality(
				ctx.get("skills", []),
				float(ctx.get("investment", 50.0)),
				float(ctx.get("innovation", 50.0)),
				luck_roll,
				float(ctx.get("competition", 0.0)))
			project["stage"] = "paper"
		"paper":
			project["stage"] = "peer_review"
		"peer_review":
			var rng2 = ctx.get("rng", null)
			var roll: float = 0.0
			if rng2 != null:
				roll = rng2.next_float() * 20.0 - 10.0
			if float(project.get("quality", 0.0)) + roll >= PEER_REVIEW_THRESHOLD:
				project["stage"] = "published"
				project["published"] = true
			else:
				project["stage"] = "rejected"
	project["log"].append(project["stage"])
	return {"ok": true, "stage": project["stage"], "quality": float(project.get("quality", 0.0))}


## 发表成果结算：返回声望、收入与引用，供调用方写入玩家与世界。
func collect(project: Dictionary, economy, account: String = "") -> Dictionary:
	if not bool(project.get("published", false)):
		return {"ok": false, "reason": "not_published"}
	var q: float = float(project.get("quality", 0.0))
	var citations: int = int(q / 10.0)
	var prestige: float = q * PUBLISH_PRESTIGE_FACTOR
	var income: int = int(q) * PUBLISH_INCOME_PER_QUALITY
	project["citations"] = int(project.get("citations", 0)) + citations
	if income > 0 and not account.is_empty() and economy != null:
		economy.issue_money(account, income, "research_income")
	return {
		"ok": true, "citations": citations, "prestige": prestige,
		"income": income, "era_unlock": q >= ERA_UNLOCK_QUALITY,
	}


## 申请专利：成果质量达标即可；返回 {ok, reason?, patent}。
func file_patent(project: Dictionary, opts: Dictionary = {}) -> Dictionary:
	if str(project.get("stage", "")) in ["published", "paper", "data", "peer_review"]:
		if float(project.get("quality", 0.0)) < float(opts.get("min_quality", PATENT_MIN_QUALITY)):
			return {"ok": false, "reason": "quality_too_low"}
		project["patented"] = true
		return {
			"ok": true,
			"patent": {"topic": str(project.get("topic", "")), "quality": float(project.get("quality", 0.0))},
		}
	return {"ok": false, "reason": "too_early"}
