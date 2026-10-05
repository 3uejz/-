extends "res://tests/test_base.gd"
## 医美项目、诊所与身份核验测试（任务 17；R46.5–R46.9；design D6）。

const AestheticScript = preload("res://sim/aesthetics.gd")


class FixedRng:
	var seq: Array
	var i: int = 0
	func _init(s: Array) -> void:
		seq = s
	func next_float() -> float:
		var v: float = float(seq[i % seq.size()])
		i += 1
		return v


func _suite_name() -> String:
	return "aesthetics"


func run_tests() -> void:
	_test_catalog()
	_test_success()
	_test_illegal_and_complication()
	_test_overuse_and_decay()
	_test_identity_and_claim()


func _new_profile() -> Dictionary:
	return {"appearance_score": 50.0, "temperament": 50.0, "outfit": 50.0, "weight_kg": 60.0, "height_cm": 170.0, "body_fat": 20.0, "stiffness": 0.0}


func _test_catalog() -> void:
	check(AestheticScript.PROJECTS.size() >= 10, "至少 10 个医美项目")
	for key in ["double_eyelid", "rhinoplasty", "jaw_shave", "liposuction", "hair_transplant", "orthodontics", "skin_laser", "breast_augmentation", "injection", "anti_aging"]:
		check(AestheticScript.PROJECTS.has(key), "覆盖项目 %s" % key)


func _test_success() -> void:
	var sys = AestheticScript.new()
	var st: Dictionary = sys.new_state()
	var p: Dictionary = _new_profile()
	var r: Dictionary = sys.perform(st, p, "rhinoplasty", true, FixedRng.new([0.0]), 0)
	check(bool(r["ok"]), "手术受理")
	check_eq(str(r["outcome"]), "success", "成功")
	check(float(p["appearance_score"]) > 50.0, "外貌提升")
	check(int(r["cost"]) > 0, "有费用")
	check(not bool(sys.perform(st, p, "bogus", true, FixedRng.new([0.0]), 0)["ok"]), "未知项目失败")


func _test_illegal_and_complication() -> void:
	var sys = AestheticScript.new()
	var p: Dictionary = _new_profile()
	# roll=0.6：合法必成功（成功率 0.85），非法失败（0.85*0.55≈0.47）。
	var r_legal: Dictionary = sys.perform(sys.new_state(), p.duplicate(), "rhinoplasty", true, FixedRng.new([0.6]), 0)
	check_eq(str(r_legal["outcome"]), "success", "合法成功")
	var illegal: Dictionary = sys.perform(sys.new_state(), p.duplicate(), "rhinoplasty", false, FixedRng.new([0.6, 0.5]), 0)
	check(str(illegal["outcome"]) != "success", "非法失败率更高")
	# 并发症：roll 失败 + roll2 命中并发症。
	var p2: Dictionary = _new_profile()
	var comp: Dictionary = sys.perform(sys.new_state(), p2, "jaw_shave", false, FixedRng.new([0.99, 0.0]), 0)
	check_eq(str(comp["outcome"]), "complication", "并发症")
	check(float(comp["health_loss"]) > 0.0, "并发症健康损失")
	check(float(p2["appearance_score"]) < 50.0, "并发症外貌惩罚")


func _test_overuse_and_decay() -> void:
	var sys = AestheticScript.new()
	var st: Dictionary = sys.new_state()
	var p: Dictionary = _new_profile()
	for i in 6:
		sys.perform(st, p, "injection", true, FixedRng.new([0.0]), i)
	check(int(st["count"]) == 6, "项目计数")
	check(float(st["stiffness"]) > 0.0, "过度医美僵硬")
	check(float(p["temperament"]) < 50.0, "僵硬降低气质")
	check(bool(st["addicted"]), "医美成瘾")
	# 限期效果到期回收。
	var st2: Dictionary = sys.new_state()
	var p2: Dictionary = _new_profile()
	sys.perform(st2, p2, "injection", true, FixedRng.new([0.0]), 0)
	check(float(p2["appearance_score"]) > 50.0, "先提升")
	sys.decay_effects(st2, p2, 200.0)
	check_near(float(p2["appearance_score"]), 50.0, 1e-6, "到期回收")


func _test_identity_and_claim() -> void:
	var sys = AestheticScript.new()
	var original: Dictionary = _new_profile()
	var changed: Dictionary = _new_profile()
	changed["appearance_score"] = 90.0
	check(bool(sys.verify_identity(changed, original)["needs_reissue"]), "大变样需重办证件")
	check(not bool(sys.verify_identity(_new_profile(), original)["needs_reissue"]), "未变样通过")
	# 维权。
	var st: Dictionary = sys.new_state()
	var p: Dictionary = _new_profile()
	sys.perform(st, p, "jaw_shave", false, FixedRng.new([0.99, 0.9]), 0)
	check(bool(st["last_failed_illegal"]), "非法失败标记")
	var claim: Dictionary = sys.malpractice_claim(st)
	check(bool(claim["ok"]), "可维权")
	check(int(claim["compensation"]) > 0, "有赔偿")
