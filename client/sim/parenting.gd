class_name ParentingSystem
extends RefCounted
## 育儿四阶段、照护投入与子女成长结算（R51.1–R51.4、R51.8；design D11）。
##
## 阶段：婴儿 0–3、幼儿 3–6、儿童 6–12、少年 12–18；照护投入 = 时间 + 金钱 + 陪伴质量。
## 成长模型：属性 = 父母基因 × 0.5 + 照护 × 0.2 + 教育 × 0.2 + 随机 × 0.1；大五人格按父母均值加噪声遗传。
## 突发事件改变成长轨迹；成年后可独立并继承家业；玩家可择一子代切换主角。

const FamilyScript = preload("res://sim/family.gd")
const BaselineScript = preload("res://sim/baseline.gd")

const ABILITY_KEYS: Array = ["intelligence", "charm", "physique", "willpower", "luck"]
const BIG_FIVE: Array = ["openness", "conscientiousness", "extraversion", "agreeableness", "neuroticism"]

## 育儿数值真源：shared/consistency/baseline/parenting.json。
const GENE_WEIGHT: float = BaselineScript.PARENT_GENE_WEIGHT
const CARE_WEIGHT: float = BaselineScript.PARENT_CARE_WEIGHT
const EDU_WEIGHT: float = BaselineScript.PARENT_EDU_WEIGHT
const RANDOM_WEIGHT: float = BaselineScript.PARENT_RANDOM_WEIGHT

const STAGES: Array = ["infant", "toddler", "child", "teen"]
const STAGE_NAMES: Dictionary = {"infant": "婴儿", "toddler": "幼儿", "child": "儿童", "teen": "少年", "adult": "成年"}
const STAGE_RANGE: Dictionary = BaselineScript.PARENT_STAGE_RANGE

## 每日照护成本（分钟、最小货币单位）。数值真源：shared/consistency/baseline/parenting.json。
const DAILY_COST: Dictionary = BaselineScript.PARENT_DAILY_COST

## 突发事件对属性的修正。数值真源：shared/consistency/baseline/parenting.json。
const EVENTS: Dictionary = BaselineScript.PARENT_EVENTS

const EARLY_DEATH_ENABLED_DEFAULT: bool = true
const EARLY_DEATH_RATE: float = BaselineScript.PARENT_EARLY_DEATH_RATE


func _clamp100(v: float) -> float:
	return clampf(v, 0.0, 100.0)


func stage_of(age: int) -> String:
	if age < 3:
		return "infant"
	if age < 6:
		return "toddler"
	if age < 12:
		return "child"
	if age < 18:
		return "teen"
	return "adult"


## 照护投入评分 0..100（R51.2）：时间 + 金钱 + 陪伴质量。
func care_investment(daily_minutes: float, daily_money: float, companionship: float) -> float:
	var time_norm: float = clampf(daily_minutes / 240.0, 0.0, 1.0) * 100.0
	var money_norm: float = clampf(daily_money / 15000.0, 0.0, 1.0) * 100.0
	var comp: float = clampf(companionship, 0.0, 100.0)
	return clampf(time_norm * 0.4 + money_norm * 0.3 + comp * 0.3, 0.0, 100.0)


## 阶段每日照护成本（R51.2）。
func daily_cost(age: int) -> Dictionary:
	var st: String = stage_of(age)
	return DAILY_COST.get(st, {"minutes": 0, "money": 0}).duplicate()


## 年度成长结算（R51.3）：写入子女能力与人格。
func raise_child(child: Dictionary, care: float, education: float, rng = null) -> Dictionary:
	var ability: Dictionary = child.get("ability", {})
	for key in ABILITY_KEYS:
		var gene: float = float(ability.get(key, 50.0))
		var rnd: float = rng.next_float() * 100.0 if rng != null else 50.0
		var v: float = gene * GENE_WEIGHT + clampf(care, 0.0, 100.0) * CARE_WEIGHT + clampf(education, 0.0, 100.0) * EDU_WEIGHT + rnd * RANDOM_WEIGHT
		ability[key] = _clamp100(v)
	child["ability"] = ability
	child["care_quality"] = clampf(care, 0.0, 100.0)
	return child


## 突发事件改变成长轨迹（R51.4）。
func apply_event(child: Dictionary, kind: String) -> Dictionary:
	if not EVENTS.has(kind):
		return {"ok": false, "reason": "unknown_event"}
	var e: Dictionary = EVENTS[kind]
	for group_key in ["ability", "personality"]:
		if not e.has(group_key):
			continue
		var group: Dictionary = child.get(group_key, {})
		for k in (e[group_key] as Dictionary).keys():
			group[str(k)] = _clamp100(float(group.get(str(k), 50.0)) + float(e[group_key][k]))
		child[group_key] = group
	return {"ok": true, "event": kind}


## 成年独立与继承家业（R51.4）。
func reach_adulthood(child: Dictionary) -> Dictionary:
	child["stage"] = "adult"
	child["independent"] = true
	return child


## 择一子代切换为主角，其余自动运行（R51.4）。
func choose_heir(children: Array, index: int) -> Dictionary:
	if index < 0 or index >= children.size():
		return {"ok": false, "reason": "invalid_index"}
	var others: Array = []
	for i in range(children.size()):
		var c: Dictionary = children[i]
		c["auto_run"] = (i != index)
		if i != index:
			others.append(c)
	return {"ok": true, "heir": children[index], "others": others}


## 子女早夭（R51.8）：极低概率，可远程关闭。
func early_death(rng, enabled: bool = EARLY_DEATH_ENABLED_DEFAULT) -> bool:
	if not enabled:
		return false
	return rng.next_float() < EARLY_DEATH_RATE
