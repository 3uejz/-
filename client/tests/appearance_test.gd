extends "res://tests/test_base.gd"
## 形象与魅力测试（任务 17；R46.1–R46.4；design D6）。

const AppearanceScript = preload("res://sim/appearance.gd")


func _suite_name() -> String:
	return "appearance"


func run_tests() -> void:
	_test_profile()
	_test_charm()
	_test_effects()
	_test_care_and_decay()


func _test_profile() -> void:
	var sys = AppearanceScript.new()
	var p: Dictionary = sys.default_appearance("male")
	check_near(float(p["height_cm"]), 175.0, 1e-6, "男性身高基线")
	check_near(float(p["bmi"]), 68.0 / (1.75 * 1.75), 1e-3, "BMI 计算")
	check_near(sys.bmi(62.0, 170.0), 62.0 / (1.7 * 1.7), 1e-6, "BMI 函数")
	check(sys.bmi(50.0, 0.0) > 0.0, "身高兜底")


func _test_charm() -> void:
	var sys = AppearanceScript.new()
	var p: Dictionary = sys.default_appearance("female")
	# 各项中位且体型正常、声音中性 → 50。
	check_near(sys.charm(p), 50.0, 1e-6, "中位魅力")
	p["appearance_score"] = 100.0
	p["temperament"] = 100.0
	p["outfit"] = 100.0
	p["voice"] = 100.0
	p["muscle"] = 80.0
	check(sys.charm(p) <= 100.0, "魅力上限")
	# 体型修正。
	var fat: Dictionary = sys.default_appearance("male")
	fat["bmi"] = 32.0
	check_near(sys.body_type_modifier(fat), -5.0, 1e-6, "肥胖修正")
	var slim: Dictionary = sys.default_appearance("male")
	slim["bmi"] = 17.0
	check_near(sys.body_type_modifier(slim), -3.0, 1e-6, "偏瘦修正")
	check_near(sys.voice_modifier({"voice": 100.0}), 5.0, 1e-6, "声音修正")


func _test_effects() -> void:
	var sys = AppearanceScript.new()
	check_near(sys.interview_bonus(100.0), 1.25, 1e-6, "高魅力面试加成")
	check_near(sys.interview_bonus(0.0), 0.75, 1e-6, "低魅力面试折扣")
	check_near(sys.social_success(100.0, 0.5), 0.75, 1e-6, "魅力提升社交")
	check(sys.venue_access(80.0, 70.0), "达标准入")
	check(not sys.venue_access(60.0, 70.0), "未达标拒绝准入")


func _test_care_and_decay() -> void:
	var sys = AppearanceScript.new()
	var p: Dictionary = sys.default_appearance("male")
	var r: Dictionary = sys.care(p, "haircut", {"value": 90.0, "cost": 5000})
	check(bool(r["ok"]), "理发成功")
	check_near(float(p["hairstyle"]), 90.0, 1e-6, "发型写入")
	var rf: Dictionary = sys.care(p, "fitness", {"hours": 10.0})
	check(float(rf["muscle"]) > 40.0, "健身增肌")
	check(float(rf["body_fat"]) < 20.0, "健身减脂")
	check(not bool(sys.care(p, "bogus", {})["ok"]), "未知护理失败")
	# 衰老衰减。
	var old: Dictionary = sys.default_appearance("male")
	old["appearance_score"] = 80.0
	var d: Dictionary = sys.decay(old, 5.0, 45.0, 60.0)
	check(float(d["appearance"]) < 0.0, "衰老降低外貌")
	check(float(old["appearance_score"]) < 80.0, "外貌更新")
	# 证件比对。
	check(sys.id_photo_match({"appearance_score": 50.0, "height_cm": 175.0}, {"appearance_score": 50.0, "height_cm": 175.0}), "同貌通过")
	check(not sys.id_photo_match({"appearance_score": 90.0, "height_cm": 175.0}, {"appearance_score": 50.0, "height_cm": 175.0}), "大变样比对失败")
