extends "res://tests/test_base.gd"
## 价值观、精神追求、信仰与精神危机测试（任务 16；R55；design D4、D15）。

const SpiritScript = preload("res://sim/spirituality.gd")


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
	return "spirituality"


func run_tests() -> void:
	_test_values()
	_test_pursuit()
	_test_faith()
	_test_crisis()
	_test_cult()


func _test_values() -> void:
	var sys = SpiritScript.new()
	check_eq(SpiritScript.VALUES.size(), 3, "三条价值观轴")
	var values: Dictionary = {"selfish_altruistic": 50.0, "conservative_open": 50.0, "material_spiritual": 50.0}
	var d: float = sys.adjust_values(values, "selfish_altruistic", 20.0)
	check_near(d, 20.0, 1e-6, "价值观微调")
	check_near(float(values["selfish_altruistic"]), 70.0, 1e-6, "更新值")
	check_near(sys.adjust_values(values, "selfish_altruistic", 100.0), 30.0, 1e-6, "上限截断")
	check_eq(sys.adjust_values(values, "bogus", 10.0), 0.0, "未知轴忽略")
	check_near(sys.value_consistency({"selfish_altruistic": 50}, {"selfish_altruistic": 50}), 100.0, 1e-6, "完全一致")
	check(sys.value_consistency({"selfish_altruistic": 0}, {"selfish_altruistic": 100}) < 50.0, "相反一致性低")


func _test_pursuit() -> void:
	var sys = SpiritScript.new()
	var state: Dictionary = sys.new_state()
	var r: Dictionary = sys.pursue(state, "meditation", 60.0)
	check(bool(r["ok"]), "冥想成功")
	check_near(float(r["stress"]), -8.0, 1e-6, "冥想降压力")
	check_near(float(r["happiness"]), 2.0, 1e-6, "冥想提幸福")
	check_near(float(r["meaning"]), 6.0, 1e-6, "冥想提意义")
	# 深度与境界解锁。
	var r2: Dictionary = sys.pursue(state, "meditation", 3000.0)
	check(bool(r2["realm_unlocked"]), "深度解锁境界")
	check_eq(int(r2["realm_index"]), 1, "小成境界")
	check_eq(str(r2["realm"]), "小成", "境界名")
	# 未知追求。
	check(not bool(sys.pursue(state, "bogus", 60.0)["ok"]), "未知追求失败")
	# 人格漂移。
	var personality: Dictionary = {"openness": 50.0, "conscientiousness": 50.0, "extraversion": 50.0, "agreeableness": 50.0, "neuroticism": 50.0}
	var cum: Dictionary = {}
	var r3: Dictionary = sys.pursue(state, "meditation", 60.0, FixedRng.new([0.0]), personality, cum)
	check(bool(r3["personality_drifted"]), "追求导致人格漂移")
	check(float(personality["neuroticism"]) < 50.0, "神经质下降")
	check(not r3["value_drift"].is_empty(), "价值漂移存在")


func _test_faith() -> void:
	var sys = SpiritScript.new()
	var state: Dictionary = sys.new_state()
	check(not bool(sys.deepen_faith(state, 60.0)["ok"]), "无信仰不可深化")
	check(bool(sys.convert(state, "stoicism")["ok"]), "皈依斯多葛")
	check_eq(str(state["faith"]), "stoicism", "信仰写入")
	var r: Dictionary = sys.deepen_faith(state, 3000.0)
	check(bool(r["ok"]), "深化成功")
	check_eq(int(r["realm_index"]), 1, "信仰境界小成")
	check(float(r["meaning"]) > 0.0, "信仰提升意义")
	check(not bool(sys.convert(state, "bogus")["ok"]), "未知信仰失败")


func _test_crisis() -> void:
	var sys = SpiritScript.new()
	var state: Dictionary = sys.new_state()
	var c: Dictionary = sys.check_crisis(state, 50.0, 20.0, 0.0)
	check_eq(str(c["event"]), "meaning_loss", "意义丧失危机")
	check(c["exits"].has("philosophy"), "含哲学出口")
	var mid: Dictionary = sys.check_crisis(state, 50.0, 50.0, 1.0)
	check_eq(str(mid["event"]), "midlife_crisis", "中年危机")
	# 化解。
	var r: Dictionary = sys.resolve_crisis(state, "meaning_loss", "philosophy")
	check(bool(r["ok"]), "哲学出口化解")
	check(float(r["meaning"]) > 0.0, "化解提升意义")
	check(not bool(sys.resolve_crisis(state, "meaning_loss", "bogus")["ok"]), "无效出口拒绝")


func _test_cult() -> void:
	var sys = SpiritScript.new()
	var calm: Dictionary = {"neuroticism": 10.0}
	var volatile: Dictionary = {"neuroticism": 90.0}
	var values: Dictionary = {"material_spiritual": 20.0}
	check(sys.cult_risk(values, volatile, "") > sys.cult_risk(values, calm, "buddhism"), "高神经质无信仰风险更高")
	check(sys.maybe_join_cult(values, volatile, "", FixedRng.new([0.0])), "低随机值卷入")
	check(not sys.maybe_join_cult(values, calm, "buddhism", FixedRng.new([0.99])), "高随机值不卷入")
