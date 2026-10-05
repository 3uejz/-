class_name AppearanceSystem
extends RefCounted
## 形象属性与魅力（R46.1–R46.4；design D6）。
##
## 维护身高/体重/BMI/外貌/气质/着装/发型/体态/体脂/肌肉/声音/体味；
## 魅力 = 0.5·外貌 + 0.3·气质 + 0.2·着装 + 体型修正 + 声音修正；
## 外貌受基因、年龄、健康与护理影响，气质受人格、仪态与阅历影响。
##
## 设计取舍：
##   - 形象存于 player["appearance"]（schema 允许附加字段），核心字段用 appearance_score/temperament。
##   - 所有护理/健身指令返回费用与效果，由上层扣费。

const CHARM_WEIGHTS: Dictionary = {"appearance": 0.5, "temperament": 0.3, "outfit": 0.2}
const BMI_NORMAL_MIN: float = 18.5
const BMI_NORMAL_MAX: float = 24.9
const TYPICAL_HEIGHT_M: float = 170.0
const TYPICAL_WEIGHT_KG: float = 62.0


func _clamp100(v: float) -> float:
	return clampf(v, 0.0, 100.0)


func bmi(weight_kg: float, height_cm: float) -> float:
	var h: float = maxf(1.0, height_cm) / 100.0
	return clampf(weight_kg / (h * h), 0.0, 200.0)


## 默认形象：按性别给定身高体重基线，外貌/气质中位。
func default_appearance(gender: String = "male") -> Dictionary:
	var h: float = 175.0 if gender == "male" else 162.0
	var w: float = 68.0 if gender == "male" else 55.0
	return {
		"gender": gender,
		"height_cm": h, "weight_kg": w, "bmi": bmi(w, h),
		"appearance_score": 50.0, "temperament": 50.0,
		"outfit": 50.0, "hairstyle": 50.0, "posture": 50.0,
		"body_fat": 20.0, "muscle": 40.0, "voice": 50.0, "odor": 50.0,
		"stiffness": 0.0, "params": {},
	}


## 体型修正（design D6）。
func body_type_modifier(profile: Dictionary) -> float:
	var b: float = float(profile.get("bmi", bmi(float(profile.get("weight_kg", TYPICAL_WEIGHT_KG)), float(profile.get("height_cm", TYPICAL_HEIGHT_M)))))
	var mod: float = 0.0
	if b < BMI_NORMAL_MIN:
		mod -= 3.0
	elif b > BMI_NORMAL_MAX:
		mod -= 2.0 if b < 30.0 else 5.0
	if float(profile.get("muscle", 40.0)) >= 70.0:
		mod += 2.0
	if float(profile.get("body_fat", 20.0)) >= 30.0:
		mod -= 3.0
	return mod


## 声音修正：0..100 映射到 -5..+5。
func voice_modifier(profile: Dictionary) -> float:
	return (float(profile.get("voice", 50.0)) - 50.0) / 10.0


## 魅力（design D6）：0..100。
func charm(profile: Dictionary) -> float:
	var base: float = 0.0
	for key in CHARM_WEIGHTS.keys():
		base += float(CHARM_WEIGHTS[key]) * _clamp100(float(profile.get(key, 50.0)))
	if "appearance" in profile and not "appearance_score" in profile:
		base = 0.5 * _clamp100(float(profile["appearance"])) + 0.3 * _clamp100(float(profile.get("temperament", 50.0))) + 0.2 * _clamp100(float(profile.get("outfit", 50.0)))
	return _clamp100(base + body_type_modifier(profile) + voice_modifier(profile))


## 面试加成乘子：魅力高于/低于中位数线性增减。
func interview_bonus(charm_value: float) -> float:
	return clampf(1.0 + (charm_value - 50.0) / 200.0, 0.75, 1.25)


## 社交成功率：基础成功率 + 魅力调节。
func social_success(charm_value: float, base: float = 0.5) -> float:
	return clampf(base + (charm_value - 50.0) / 200.0, 0.0, 1.0)


## 场所准入：魅力达标方可进入。
func venue_access(charm_value: float, requirement: float) -> bool:
	return charm_value >= requirement


## 随年龄与健康自然折减外貌、气质变化（design D6）。years 为年数。
func decay(profile: Dictionary, years: float, age: float, health: float = 80.0) -> Dictionary:
	if years <= 0.0:
		return {"appearance": 0.0, "temperament": 0.0}
	var aging: float = maxf(0.0, age - 25.0) / 25.0
	var health_penalty: float = maxf(0.0, 60.0 - health) / 100.0
	var appearance_drop: float = (0.4 + aging + health_penalty) * years
	# 阅历提升气质，但过度医美僵硬会压制。
	var temperament_gain: float = 0.3 * years * (1.0 - clampf(float(profile.get("stiffness", 0.0)) / 100.0, 0.0, 1.0))
	profile["appearance_score"] = _clamp100(float(profile.get("appearance_score", 50.0)) - appearance_drop)
	profile["temperament"] = _clamp100(float(profile.get("temperament", 50.0)) + temperament_gain)
	return {"appearance": -appearance_drop, "temperament": temperament_gain}


## 护理指令（R46.4）：理发/化妆/服装搭配/健身塑形。
## kind: haircut / makeup / outfit / fitness。
func care(profile: Dictionary, kind: String, opts: Dictionary = {}) -> Dictionary:
	match kind:
		"haircut":
			var style: float = clampf(float(opts.get("value", 70.0)), 0.0, 100.0)
			profile["hairstyle"] = style
			profile["appearance_score"] = _clamp100(float(profile.get("appearance_score", 50.0)) + 1.0)
			return {"ok": true, "kind": kind, "cost": int(opts.get("cost", 5000)), "hairstyle": style}
		"makeup":
			profile["appearance_score"] = _clamp100(float(profile.get("appearance_score", 50.0)) + 2.0)
			return {"ok": true, "kind": kind, "cost": int(opts.get("cost", 3000))}
		"outfit":
			var v: float = clampf(float(opts.get("value", 70.0)), 0.0, 100.0)
			profile["outfit"] = v
			return {"ok": true, "kind": kind, "cost": int(opts.get("cost", 20000)), "outfit": v}
		"fitness":
			var hours: float = maxf(0.0, float(opts.get("hours", 1.0)))
			var muscle_gain: float = 0.5 * hours
			var fat_loss: float = 0.3 * hours
			profile["muscle"] = _clamp100(float(profile.get("muscle", 40.0)) + muscle_gain)
			profile["body_fat"] = _clamp100(float(profile.get("body_fat", 20.0)) - fat_loss)
			profile["weight_kg"] = maxf(30.0, float(profile.get("weight_kg", TYPICAL_WEIGHT_KG)) - fat_loss * 0.1)
			profile["bmi"] = bmi(float(profile["weight_kg"]), float(profile.get("height_cm", TYPICAL_HEIGHT_M)))
			return {"ok": true, "kind": kind, "muscle": float(profile["muscle"]), "body_fat": float(profile["body_fat"]), "bmi": float(profile["bmi"])}
		_:
			return {"ok": false, "reason": "unknown_care"}


## 证件人像比对（R46.9）：整容/伪装偏离越大越易失败。返回是否通过。
func id_photo_match(profile: Dictionary, original: Dictionary, tolerance: float = 25.0) -> bool:
	var diff: float = absf(float(profile.get("appearance_score", 50.0)) - float(original.get("appearance_score", 50.0)))
	diff += absf(float(profile.get("height_cm", TYPICAL_HEIGHT_M)) - float(original.get("height_cm", TYPICAL_HEIGHT_M))) * 2.0
	return diff <= tolerance
