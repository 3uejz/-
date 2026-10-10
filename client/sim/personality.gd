class_name PersonalitySystem
extends RefCounted
## 大五人格与性格标签（R44.1、R44.2；design D4）。
##
## 五维人格 0..100，出生值 = 父母均值 × 遗传权重 + 基线 + 噪声；一生累计漂移设上限，
## 成年后漂移速率下降；标签由阈值/组合派生，影响对话风格、职业适配与关系变化速度。
##
## 设计取舍：
##   - 人格以普通 Dictionary（键为五维英文名）表示，便于直接嵌入 player["attrs"]["personality"]。
##   - 累计漂移以独立字典跟踪，保证「一生漂移上限」可被多次小幅调整累积后仍受约束。

const BaselineScript = preload("res://sim/baseline.gd")

const BIG_FIVE: Array = ["openness", "conscientiousness", "extraversion", "agreeableness", "neuroticism"]
const DIM_NAMES: Dictionary = {
	"openness": "开放性",
	"conscientiousness": "尽责性",
	"extraversion": "外向性",
	"agreeableness": "宜人性",
	"neuroticism": "神经质",
}

## 遗传权重：父母均值占比，其余为人群基线 50。
const HEREDITY_WEIGHT: float = BaselineScript.PERSONALITY_HEREDITY_WEIGHT
const POPULATION_BASELINE: float = BaselineScript.PERSONALITY_POPULATION_BASELINE
## 出生噪声幅度（±）。
const NOISE_RANGE: float = BaselineScript.PERSONALITY_NOISE_RANGE
## 一生每维累计漂移绝对值上限。
const LIFETIME_DRIFT_CAP: float = BaselineScript.PERSONALITY_LIFETIME_DRIFT_CAP
## 成年年龄与成年后漂移速率。
const ADULT_AGE: float = BaselineScript.PERSONALITY_ADULT_AGE
const ADULT_DRIFT_FACTOR: float = BaselineScript.PERSONALITY_ADULT_DRIFT_FACTOR


func _clamp(v: float) -> float:
	return clampf(v, 0.0, 100.0)


func _dim(parents: Dictionary, dim: String, fallback: float) -> float:
	return float(parents.get(dim, fallback))


## 出生人格：父母均值 × 遗传权重 + 基线 + 噪声（design D4）。
func new_from_parents(father: Dictionary, mother: Dictionary, rng = null) -> Dictionary:
	var out: Dictionary = {}
	for dim in BIG_FIVE:
		var avg: float = (_dim(father, dim, POPULATION_BASELINE) + _dim(mother, dim, POPULATION_BASELINE)) / 2.0
		var v: float = avg * HEREDITY_WEIGHT + POPULATION_BASELINE * (1.0 - HEREDITY_WEIGHT)
		if rng != null:
			v += (rng.next_float() * 2.0 - 1.0) * NOISE_RANGE
		out[dim] = _clamp(v)
	return out


## 默认人群人格。
func default_personality() -> Dictionary:
	var out: Dictionary = {}
	for dim in BIG_FIVE:
		out[dim] = POPULATION_BASELINE
	return out


## 派生性格标签（阈值/组合）。返回排序后的标签键数组，保证确定性。
func derive_tags(p: Dictionary) -> Array:
	var o: float = float(p.get("openness", 50.0))
	var c: float = float(p.get("conscientiousness", 50.0))
	var e: float = float(p.get("extraversion", 50.0))
	var a: float = float(p.get("agreeableness", 50.0))
	var n: float = float(p.get("neuroticism", 50.0))
	var tags: Array = []
	if c >= 70.0 and n >= 60.0:
		tags.append("perfectionist")      # 完美主义
	if e >= 70.0 and a >= 70.0:
		tags.append("social_butterfly")   # 社交达人
	if e <= 30.0 and o >= 70.0:
		tags.append("lone_wolf")          # 独行
	if n >= 70.0:
		tags.append("anxious_type")       # 敏感焦虑
	if o >= 70.0:
		tags.append("open_minded")        # 开放探索
	if a >= 70.0:
		tags.append("agreeable")          # 温和亲和
	if o >= 65.0 and c <= 40.0:
		tags.append("risk_taker")         # 冒险
	if n <= 30.0:
		tags.append("resilient")          # 坚韧稳定
	if c >= 70.0 and n <= 40.0:
		tags.append("achiever")           # 自律成就
	if e >= 60.0 and n >= 60.0:
		tags.append("dramatic")           # 情绪外显
	if o <= 30.0 and c >= 60.0:
		tags.append("traditional")        # 传统守成
	if e <= 40.0 and a <= 40.0:
		tags.append("solitary_cold")      # 孤僻冷淡
	tags.sort()
	return tags


## 标签对关系变化速度的乘子（标签影响关系变化速度，R44.2）。
func relation_rate_multiplier(tags: Array) -> float:
	var m: float = 1.0
	if tags.has("social_butterfly"):
		m += 0.3
	if tags.has("agreeable"):
		m += 0.15
	if tags.has("solitary_cold"):
		m -= 0.3
	if tags.has("anxious_type"):
		m -= 0.1
	return clampf(m, 0.2, 2.0)


## 标签对对话风格键的映射（供叙述层使用）。
func dialogue_style(tags: Array) -> String:
	if tags.has("social_butterfly"):
		return "热情外向"
	if tags.has("lone_wolf"):
		return "简短内敛"
	if tags.has("anxious_type"):
		return "谨慎迟疑"
	if tags.has("traditional"):
		return "稳重客气"
	return "平实"


## 职业适配：profile 为各维权重（可为负），返回 0..100 适配度。
func career_fit(p: Dictionary, profile: Dictionary) -> float:
	if profile.is_empty():
		return 50.0
	var total_w: float = 0.0
	var score: float = 0.0
	for key in profile.keys():
		var w: float = float(profile[key])
		total_w += absf(w)
		var v: float = float(p.get(str(key), POPULATION_BASELINE))
		# 正权重奖励高分，负权重奖励低分。
		if w >= 0.0:
			score += w * v
		else:
			score += (-w) * (100.0 - v)
	if total_w <= 0.0:
		return 50.0
	return clampf(score / total_w, 0.0, 100.0)


## 社交匹配：人格差异越小越合，宜人性提供加成，返回 0..100。
func social_match(a: Dictionary, b: Dictionary) -> float:
	var diff: float = 0.0
	for dim in BIG_FIVE:
		diff += absf(float(a.get(dim, POPULATION_BASELINE)) - float(b.get(dim, POPULATION_BASELINE)))
	diff /= float(BIG_FIVE.size())
	var base: float = 100.0 - diff
	var bonus: float = (float(a.get("agreeableness", 50.0)) + float(b.get("agreeableness", 50.0))) / 2.0 * 0.1
	return clampf(base * 0.9 + bonus, 0.0, 100.0)


## 决策权重：返回该角色在给定决策维度上的偏好权重（越大越倾向该选项）。
func decision_weight(p: Dictionary, tag: String, base: float = 1.0) -> float:
	match tag:
		"risk":
			return clampf(base * (1.0 + (float(p.get("openness", 50.0)) - 50.0) / 100.0 - (float(p.get("conscientiousness", 50.0)) - 50.0) / 150.0), 0.0, 3.0)
		"social":
			return clampf(base * (1.0 + (float(p.get("extraversion", 50.0)) - 50.0) / 100.0 + (float(p.get("agreeableness", 50.0)) - 50.0) / 150.0), 0.0, 3.0)
		"caution":
			return clampf(base * (1.0 + (float(p.get("neuroticism", 50.0)) - 50.0) / 100.0), 0.0, 3.0)
		"virtue":
			return clampf(base * (1.0 + (float(p.get("agreeableness", 50.0)) - 50.0) / 100.0), 0.0, 3.0)
		_:
			return base


## 应用人格漂移。delta 为各维期望变化；cumulative 记录每维已累计漂移量。
## age >= ADULT_AGE 时漂移速率乘以 ADULT_DRIFT_FACTOR；每维一生累计绝对值不超过 LIFETIME_DRIFT_CAP。
## 返回实际应用的变化量。
func drift(p: Dictionary, delta: Dictionary, age: float, cumulative: Dictionary) -> Dictionary:
	var factor: float = ADULT_DRIFT_FACTOR if age >= ADULT_AGE else 1.0
	var applied: Dictionary = {}
	for dim in delta.keys():
		var key: String = str(dim)
		var want: float = float(delta[dim]) * factor
		var used: float = float(cumulative.get(key, 0.0))
		var remaining: float = LIFETIME_DRIFT_CAP - absf(used)
		if remaining <= 0.0:
			applied[key] = 0.0
			continue
		var actual: float = clampf(want, -remaining, remaining)
		cumulative[key] = used + actual
		p[key] = _clamp(float(p.get(key, POPULATION_BASELINE)) + actual)
		applied[key] = actual
	return applied
