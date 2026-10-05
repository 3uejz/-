extends "res://tests/test_base.gd"
## 大五人格与标签测试（任务 16；R44.1、R44.2；design D4）。

const PersonalityScript = preload("res://sim/personality.gd")
const RngScript = preload("res://sim/rng.gd")


func _suite_name() -> String:
	return "personality"


func run_tests() -> void:
	_test_birth()
	_test_tags()
	_test_effects()
	_test_drift()


func _test_birth() -> void:
	var sys = PersonalityScript.new()
	check_eq(PersonalityScript.BIG_FIVE.size(), 5, "五维人格")
	var father: Dictionary = sys.default_personality()
	var mother: Dictionary = sys.default_personality()
	father["openness"] = 80.0
	mother["openness"] = 60.0
	var child: Dictionary = sys.new_from_parents(father, mother, null)
	# avg=70 → 70*0.5 + 50*0.5 = 60
	check_near(float(child["openness"]), 60.0, 1e-6, "遗传公式")
	check_near(float(child["extraversion"]), 50.0, 1e-6, "其余维度取基线")
	# 带噪声仍在 0..100。
	var rng = RngScript.new(7)
	for i in 50:
		var c: Dictionary = sys.new_from_parents(father, mother, rng)
		for dim in PersonalityScript.BIG_FIVE:
			check(float(c[dim]) >= 0.0 and float(c[dim]) <= 100.0, "噪声后仍在范围")


func _test_tags() -> void:
	var sys = PersonalityScript.new()
	var p: Dictionary = sys.default_personality()
	p["conscientiousness"] = 80.0
	p["neuroticism"] = 70.0
	var tags: Array = sys.derive_tags(p)
	check(tags.has("perfectionist"), "完美主义标签")
	check(tags.has("anxious_type"), "敏感焦虑标签")
	p["extraversion"] = 80.0
	p["agreeableness"] = 80.0
	tags = sys.derive_tags(p)
	check(tags.has("social_butterfly"), "社交达人标签")
	check(sys.relation_rate_multiplier(tags) > 1.0, "社交达人加速关系")
	var lone: Dictionary = sys.default_personality()
	lone["extraversion"] = 20.0
	lone["openness"] = 80.0
	var lt: Array = sys.derive_tags(lone)
	check(lt.has("lone_wolf"), "独行标签")
	check(sys.relation_rate_multiplier(lt) < 1.0 or not lt.has("social_butterfly"), "独行不加速")


func _test_effects() -> void:
	var sys = PersonalityScript.new()
	var p: Dictionary = sys.default_personality()
	p["openness"] = 80.0
	check_near(sys.career_fit(p, {"openness": 1.0}), 80.0, 1e-6, "正权重职业适配")
	check_near(sys.career_fit(p, {"openness": -1.0}), 20.0, 1e-6, "负权重职业适配")
	var a: Dictionary = sys.default_personality()
	var b: Dictionary = sys.default_personality()
	check(sys.social_match(a, b) > 80.0, "相同人格高匹配")
	b["extraversion"] = 100.0
	b["agreeableness"] = 0.0
	check(sys.social_match(a, b) < sys.social_match(a, sys.default_personality()), "差异降低匹配")
	# 风险决策权重随开放性上升、尽责性下降。
	p["conscientiousness"] = 50.0
	check_near(sys.decision_weight(p, "risk"), 1.3, 1e-6, "风险权重")
	check_near(sys.decision_weight(p, "unknown", 2.0), 2.0, 1e-6, "未知维度原值")


func _test_drift() -> void:
	var sys = PersonalityScript.new()
	var p: Dictionary = sys.default_personality()
	var cum: Dictionary = {}
	var applied: Dictionary = sys.drift(p, {"openness": 100.0}, 20.0, cum)
	check_near(float(applied["openness"]), 20.0, 1e-6, "未成年全量但受上限约束")
	check_near(float(p["openness"]), 70.0, 1e-6, "人格更新")
	# 已用满上限，再漂移不生效。
	applied = sys.drift(p, {"openness": 100.0}, 20.0, cum)
	check_near(float(applied["openness"]), 0.0, 1e-6, "一生漂移上限")
	check_near(float(p["openness"]), 70.0, 1e-6, "上限后不再变化")
	# 成年漂移速率打折。
	var p2: Dictionary = sys.default_personality()
	var applied2: Dictionary = sys.drift(p2, {"openness": 40.0}, 30.0, {})
	check_near(float(applied2["openness"]), 10.0, 1e-6, "成年漂移打折")
