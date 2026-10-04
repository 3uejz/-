class_name OnboardingModel
extends RefCounted
## 开档分步向导模型（R33、R57、design.md「开档与新手引导」）。
## 起始年龄默认成年；天赋点选含负特质（负特质换取额外点数）；
## 家境随机或指定；出生地随机可选；引导仅首档出现、可跳过。
## 纯逻辑，可在 headless 下单测。

const SplitMix64Script = preload("res://sim/rng.gd")

const DEFAULT_ADULT_AGE: int = 18
const BASE_TALENT_POINTS: int = 2

const START_MODES: Array[String] = ["adult", "child", "birth"]
const FAMILY_MODES: Array[String] = ["random", "poor", "welloff", "middle", "rich"]
## 家境按现实分布加权（design.md：默认按基尼系数随机，可指定档位）。
const FAMILY_WEIGHTS: Dictionary = {"poor": 0.30, "welloff": 0.35, "middle": 0.25, "rich": 0.10}
const FAMILY_TIERS: Array[String] = ["poor", "welloff", "middle", "rich"]

const BIRTHPLACES: Array[String] = ["北京", "上海", "广州", "成都", "西安", "武汉", "哈尔滨", "昆明"]

## 天赋池：cost 为正表示消耗点数，为负表示负特质返还点数。
const TALENTS: Dictionary = {
	"talent.quick_learner": {"name": "过目不忘", "cost": 1, "negative": false},
	"talent.strong_body": {"name": "体魄强健", "cost": 1, "negative": false},
	"talent.charming": {"name": "天生丽质", "cost": 1, "negative": false},
	"talent.lucky": {"name": "福星高照", "cost": 1, "negative": false},
	"talent.frail": {"name": "体弱多病", "cost": -1, "negative": true},
	"talent.hot_temper": {"name": "暴躁易怒", "cost": -1, "negative": true},
	"talent.short_sighted": {"name": "目光短浅", "cost": -2, "negative": true},
}

var start_mode: String = "adult"
var start_age: int = DEFAULT_ADULT_AGE
var family_mode: String = "random"
var family_tier: String = ""
var birthplace_mode: String = "random"
var birthplace: String = ""
var selected_talents: Array = []
var skipped: bool = false

# --- 起始年龄 ---

## 成年开局返回 18；从出生/童年开始以快进过渡早期阶段。
func set_start_mode(value: String) -> bool:
	if not START_MODES.has(value):
		return false
	start_mode = value
	if value == "adult":
		start_age = DEFAULT_ADULT_AGE
	elif value == "child":
		start_age = 6
	else:
		start_age = 0
	return true

# --- 天赋点选 ---

func remaining_points() -> int:
	return BASE_TALENT_POINTS - spent_points()

func spent_points() -> int:
	var total := 0
	for id in selected_talents:
		total += int((TALENTS.get(id, {}) as Dictionary).get("cost", 0))
	return total

func select_talent(id: String) -> Dictionary:
	if not TALENTS.has(id):
		return {"ok": false, "error": "未知天赋「%s」" % id}
	if selected_talents.has(id):
		return {"ok": true, "error": ""}
	var cost := int((TALENTS[id] as Dictionary).get("cost", 0))
	# 正特质需消耗点数；负特质返还点数，永不受限。
	if cost > 0 and cost > remaining_points():
		return {"ok": false, "error": "天赋点不足"}
	selected_talents.append(id)
	return {"ok": true, "error": ""}

func deselect_talent(id: String) -> void:
	selected_talents.erase(id)

func can_confirm() -> bool:
	return remaining_points() >= 0

# --- 家境 ---

## 随机家境：用种子走现实加权分布，保证可复现。
func roll_family(seed: int) -> String:
	var r := SplitMix64Script.new(seed)
	var x := r.next_float()
	var acc := 0.0
	for tier in FAMILY_TIERS:
		acc += float(FAMILY_WEIGHTS.get(tier, 0.0))
		if x < acc:
			family_tier = tier
			return tier
	family_tier = FAMILY_TIERS[FAMILY_TIERS.size() - 1]
	return family_tier

func set_family_mode(value: String) -> bool:
	if not FAMILY_MODES.has(value):
		return false
	family_mode = value
	if value != "random":
		family_tier = value
	return true

# --- 出生地 ---

func roll_birthplace(seed: int) -> String:
	var r := SplitMix64Script.new(seed ^ 0x5DA1)
	birthplace = BIRTHPLACES[int(r.next_float() * float(BIRTHPLACES.size()))]
	return birthplace

func set_birthplace_mode(value: String) -> bool:
	if value != "random" and value != "specified":
		return false
	birthplace_mode = value
	if value == "random":
		birthplace = ""
	return true

# --- 一键随机 ---

func randomize_all(seed: int) -> void:
	roll_family(seed)
	roll_birthplace(seed + 1)

# --- 首档判定 ---

## 仅首个存档出现引导；后续开档默认跳过并可手动开启。
func should_show(has_previous_save: bool) -> bool:
	return not has_previous_save and not skipped

# --- 序列化 ---

func to_dict() -> Dictionary:
	return {
		"start_mode": start_mode,
		"start_age": start_age,
		"family_mode": family_mode,
		"family_tier": family_tier,
		"birthplace_mode": birthplace_mode,
		"birthplace": birthplace,
		"selected_talents": selected_talents.duplicate(),
		"remaining_points": remaining_points(),
		"skipped": skipped,
		# 3D 捏脸参数占位：资源见任务 23，此处仅持久化结构。
		"appearance": {"params": {}},
	}
