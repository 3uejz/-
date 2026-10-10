class_name ArtSystem
extends RefCounted
## 艺术独立生涯：音乐、绘画、写作、表演（R45.6；design D5）。
##
## 作品评分 = 技能 + 灵感 + 运气 − 迎合度损失；灵感为中等权重随机项。
## 作品可发行获利、积累声望、获奖与进行 IP 运营。
##
## 设计取舍：
##   - 作品与随机源由调用方注入，本模块不依赖 Autoload，便于测试与复现；
##   - 技能按对应领域技能等级（0..20）折算，也可由调用方直接给出。

const BaselineScript = preload("res://sim/baseline.gd")

const DISCIPLINES: Array = ["music", "painting", "writing", "performance"]
const DISCIPLINE_NAMES: Dictionary = {
	"music": "音乐", "painting": "绘画", "writing": "写作", "performance": "表演",
}
const DISCIPLINE_SKILL: Dictionary = {
	"music": "skill.vocal", "painting": "skill.painting",
	"writing": "skill.creative_writing", "performance": "skill.acting",
}

const SKILL_WEIGHT: float = BaselineScript.ARTS_SKILL_WEIGHT
const INSPIRATION_WEIGHT: float = BaselineScript.ARTS_INSPIRATION_WEIGHT
const LUCK_WEIGHT: float = BaselineScript.ARTS_LUCK_WEIGHT
const PANDER_LOSS: float = BaselineScript.ARTS_PANDER_LOSS
const BASE_INCOME: int = BaselineScript.ARTS_BASE_INCOME
const AWARD_MIN_SCORE: float = BaselineScript.ARTS_AWARD_MIN_SCORE
const AWARD_CHANCE: float = BaselineScript.ARTS_AWARD_CHANCE


func _skill_level(skills: Array, discipline: String) -> float:
	var skill_id: String = str(DISCIPLINE_SKILL.get(discipline, ""))
	for s in skills:
		if str((s as Dictionary).get("content_key", "")) == skill_id:
			return float((s as Dictionary).get("level", 0))
	return 0.0


## 创作作品。skills 为玩家技能数组；rng 决定灵感与运气；opts.inspiration / pandering 可覆盖。
func create_work(discipline: String, skills: Array, rng = null, opts: Dictionary = {}) -> Dictionary:
	if not DISCIPLINES.has(discipline):
		return {"ok": false, "reason": "bad_discipline"}
	var skill_level: float = float(opts.get("skill_level", _skill_level(skills, discipline)))
	var inspiration: float = float(opts.get("inspiration", -1.0))
	var luck: float = float(opts.get("luck", -1.0))
	if inspiration < 0.0:
		inspiration = (rng.next_float() * 100.0) if rng != null else 50.0
	if luck < 0.0:
		luck = (rng.next_float() * 100.0) if rng != null else 50.0
	var pandering: float = clampf(float(opts.get("pandering", 0.0)), 0.0, 1.0)
	var score: float = clampf(
		SKILL_WEIGHT * clampf(skill_level / 20.0 * 100.0, 0.0, 100.0)
		+ INSPIRATION_WEIGHT * clampf(inspiration, 0.0, 100.0)
		+ LUCK_WEIGHT * clampf(luck, 0.0, 100.0)
		- pandering * PANDER_LOSS,
		0.0, 100.0)
	return {
		"ok": true, "discipline": discipline, "score": score,
		"grade": grade_of(score), "inspiration": inspiration, "pandering": pandering,
	}


static func grade_of(score: float) -> String:
	if score >= 85.0:
		return "masterpiece"
	if score >= 70.0:
		return "excellent"
	if score >= 50.0:
		return "competent"
	return "mediocre"


## 发行作品：按评分与触达规模结算收入与声望。
func release(work: Dictionary, opts: Dictionary = {}) -> Dictionary:
	if not bool(work.get("ok", false)):
		return {"ok": false, "reason": "invalid_work"}
	var reach: float = maxf(0.0, float(opts.get("reach", 1.0)))
	var income: int = int(float(work["score"]) * float(BASE_INCOME) * reach)
	var fame: float = float(work["score"]) * 0.5 * reach
	return {"ok": true, "income": income, "fame": fame}


## 评奖：高分作品按概率获奖。
func award(work: Dictionary, rng = null, opts: Dictionary = {}) -> Dictionary:
	if float(work.get("score", 0.0)) < AWARD_MIN_SCORE:
		return {"won": false}
	var roll: float = rng.next_float() if rng != null else 0.0
	var award_name: String = str(opts.get("name", "年度艺术奖"))
	return {"won": roll < AWARD_CHANCE, "name": award_name}
