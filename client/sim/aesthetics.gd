class_name AestheticSystem
extends RefCounted
## 医美项目、合法/非法诊所、效果衰减与证件比对（R46.5–R46.9；design D6）。
##
## 每个项目定义费用、恢复期、成功率、并发症率、效果与时效。效果随年龄与健康自然衰减；
## 过度医美造成面部僵硬并降低气质；非法诊所显著提高失败率；失败/并发症结算健康与外貌损失。

const AppearanceScript = preload("res://sim/appearance.gd")
const BaselineScript = preload("res://sim/baseline.gd")

## 医美项目表（R46.5）。effect 为施加到形象档案的增量；decay_days=0 表示长期维持。
const PROJECTS: Dictionary = {
	"double_eyelid": {"name": "割双眼皮", "cost": 500000, "recovery_minutes": 4320, "success": 0.92, "complication": 0.05, "repeatable": false, "effect": {"appearance_score": 5.0}, "decay_days": 0},
	"rhinoplasty": {"name": "隆鼻", "cost": 2000000, "recovery_minutes": 10080, "success": 0.85, "complication": 0.10, "repeatable": true, "effect": {"appearance_score": 8.0}, "decay_days": 0},
	"jaw_shave": {"name": "削骨", "cost": 8000000, "recovery_minutes": 20160, "success": 0.78, "complication": 0.18, "repeatable": false, "effect": {"appearance_score": 12.0, "temperament": -2.0}, "decay_days": 0},
	"liposuction": {"name": "抽脂", "cost": 1500000, "recovery_minutes": 7200, "success": 0.9, "complication": 0.08, "repeatable": true, "effect": {"appearance_score": 4.0, "body_fat": -5.0}, "decay_days": 365 * 3},
	"hair_transplant": {"name": "植发", "cost": 3000000, "recovery_minutes": 10080, "success": 0.88, "complication": 0.07, "repeatable": true, "effect": {"appearance_score": 6.0}, "decay_days": 365 * 5},
	"orthodontics": {"name": "牙齿矫正", "cost": 2000000, "recovery_minutes": 43200, "success": 0.95, "complication": 0.04, "repeatable": false, "effect": {"appearance_score": 5.0}, "decay_days": 0},
	"skin_laser": {"name": "皮肤激光", "cost": 800000, "recovery_minutes": 4320, "success": 0.9, "complication": 0.09, "repeatable": true, "effect": {"appearance_score": 4.0}, "decay_days": 365},
	"breast_augmentation": {"name": "隆胸", "cost": 4000000, "recovery_minutes": 14400, "success": 0.86, "complication": 0.14, "repeatable": true, "effect": {"appearance_score": 6.0}, "decay_days": 365 * 10},
	"injection": {"name": "注射微整", "cost": 300000, "recovery_minutes": 720, "success": 0.94, "complication": 0.06, "repeatable": true, "effect": {"appearance_score": 3.0}, "decay_days": 180},
	"anti_aging": {"name": "抗衰", "cost": 600000, "recovery_minutes": 2880, "success": 0.9, "complication": 0.07, "repeatable": true, "effect": {"appearance_score": 4.0}, "decay_days": 365},
}

const OVER_MEDICALIZATION_THRESHOLD: int = BaselineScript.AESTHETICS_OVER_MEDICALIZATION_THRESHOLD
const STIFFNESS_PER_PROCEDURE: float = BaselineScript.AESTHETICS_STIFFNESS_PER_PROCEDURE
const ILLEGAL_SUCCESS_MULT: float = BaselineScript.AESTHETICS_ILLEGAL_SUCCESS_MULT
const ILLEGAL_COMPLICATION_MULT: float = BaselineScript.AESTHETICS_ILLEGAL_COMPLICATION_MULT
const MALPRACTICE_COMPENSATION: int = BaselineScript.AESTHETICS_MALPRACTICE_COMPENSATION


func new_state() -> Dictionary:
	return {"procedures": [], "count": 0, "stiffness": 0.0, "addicted": false, "last_failed_illegal": false}


## 执行一次医美（R46.5、R46.6、R46.8）。clinic_legal=false 表示非法诊所。
func perform(state: Dictionary, profile: Dictionary, project: String, clinic_legal: bool, rng, now_minute: int) -> Dictionary:
	if not PROJECTS.has(project):
		return {"ok": false, "reason": "unknown_project"}
	var p: Dictionary = PROJECTS[project]
	var success_rate: float = float(p["success"]) * (1.0 if clinic_legal else ILLEGAL_SUCCESS_MULT)
	var complication_rate: float = float(p["complication"]) * (1.0 if clinic_legal else ILLEGAL_COMPLICATION_MULT)
	var roll: float = rng.next_float() if rng != null else 0.0
	var outcome: String = "success"
	var applied: Dictionary = {}
	var health_loss: float = 0.0
	if roll < success_rate:
		outcome = "success"
		for k in p["effect"].keys():
			var key: String = str(k)
			applied[key] = float(p["effect"][k])
			profile[key] = clampf(float(profile.get(key, 50.0)) + float(p["effect"][k]), 0.0, 100.0)
		if applied.has("body_fat"):
			profile["bmi"] = AppearanceScript.new().bmi(float(profile.get("weight_kg", 60.0)), float(profile.get("height_cm", 170.0)))
	else:
		var roll2: float = rng.next_float() if rng != null else 1.0
		if roll2 < complication_rate:
			outcome = "complication"
			health_loss = 8.0
			profile["appearance_score"] = clampf(float(profile.get("appearance_score", 50.0)) - 10.0, 0.0, 100.0)
			profile["temperament"] = clampf(float(profile.get("temperament", 50.0)) - 3.0, 0.0, 100.0)
		else:
			outcome = "failure"
			profile["appearance_score"] = clampf(float(profile.get("appearance_score", 50.0)) - 5.0, 0.0, 100.0)

	# 过度医美：面部僵硬累积并压低气质（R46.7）。
	state["count"] = int(state.get("count", 0)) + 1
	if int(state["count"]) > OVER_MEDICALIZATION_THRESHOLD:
		var old_t: float = float(profile.get("temperament", 50.0))
		state["stiffness"] = float(state.get("stiffness", 0.0)) + STIFFNESS_PER_PROCEDURE
		profile["stiffness"] = state["stiffness"]
		profile["temperament"] = clampf(old_t - STIFFNESS_PER_PROCEDURE * 0.5, 0.0, 100.0)
	# 医美成瘾风险（R46 边界情况）。
	if int(state["count"]) >= OVER_MEDICALIZATION_THRESHOLD:
		state["addicted"] = true
	if outcome != "success" and not clinic_legal:
		state["last_failed_illegal"] = true

	var record: Dictionary = {
		"project": project, "outcome": outcome, "minute": now_minute,
		"applied": applied, "remaining_days": float(p.get("decay_days", 0)),
	}
	var procs: Array = state.get("procedures", [])
	procs.append(record)
	state["procedures"] = procs
	return {
		"ok": true, "project": project, "outcome": outcome,
		"cost": int(p["cost"]), "recovery_minutes": int(p["recovery_minutes"]),
		"applied": applied, "health_loss": health_loss, "legal": clinic_legal,
	}


## 效果自然衰减（R46.7）：限期项目到期后回收其外貌加成。
func decay_effects(state: Dictionary, profile: Dictionary, days: float) -> Dictionary:
	var reverted: float = 0.0
	var procs: Array = state.get("procedures", [])
	for rec in procs:
		if float(rec.get("remaining_days", 0.0)) <= 0.0:
			continue
		rec["remaining_days"] = float(rec["remaining_days"]) - days
		if float(rec["remaining_days"]) <= 0.0:
			var applied: Dictionary = rec.get("applied", {})
			for k in applied.keys():
				var key: String = str(k)
				var delta: float = float(applied[key])
				if key == "appearance_score":
					profile["appearance_score"] = clampf(float(profile.get("appearance_score", 50.0)) - delta, 0.0, 100.0)
					reverted += delta
				elif key != "body_fat":
					profile[key] = clampf(float(profile.get(key, 50.0)) - delta, 0.0, 100.0)
	return {"reverted_appearance": reverted}


## 证件人像比对（R46.9）：返回是否匹配；不匹配需重办证件，也可识破冒用。
func verify_identity(profile: Dictionary, document_profile: Dictionary, tolerance: float = 25.0) -> Dictionary:
	var matched: bool = AppearanceScript.new().id_photo_match(profile, document_profile, tolerance)
	return {"matched": matched, "needs_reissue": not matched}


## 医美失败维权（R46.6，联动 D12）。
func malpractice_claim(state: Dictionary) -> Dictionary:
	if not bool(state.get("last_failed_illegal", false)):
		return {"ok": false, "reason": "no_grounds"}
	state["last_failed_illegal"] = false
	return {"ok": true, "supported": true, "compensation": MALPRACTICE_COMPENSATION}
