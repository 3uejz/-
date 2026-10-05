extends "res://tests/test_base.gd"
## 心理状态与精神疾病测试（任务 16；R8、R44；design D4）。

const MHScript = preload("res://sim/mental_health.gd")
const RngScript = preload("res://sim/rng.gd")


## 固定序列随机源，保证治疗结果可预期。
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
	return "mental_health"


func run_tests() -> void:
	_test_emotion()
	_test_events()
	_test_catalog_and_risk()
	_test_course()
	_test_treatment()
	_test_relapse()


func _test_emotion() -> void:
	var sys = MHScript.new()
	check_eq(sys.emotion_state(20.0, 70.0), "depressed", "抑郁状态")
	check_eq(sys.emotion_state(60.0, 70.0), "anxious", "焦虑状态")
	check_eq(sys.emotion_state(90.0, 20.0), "manic", "亢奋状态")
	check_eq(sys.emotion_state(60.0, 40.0), "calm", "平静状态")
	check_near(sys.efficiency_factor("depressed"), 0.6, 1e-6, "抑郁降低效率")
	check(sys.social_restricted("depressed"), "抑郁限制社交")
	check(not sys.social_restricted("calm"), "平静不限制社交")


func _test_events() -> void:
	var sys = MHScript.new()
	var player: Dictionary = {"attrs": {"psychological": {"mood": 60.0, "stress": 40.0, "happiness": 50.0, "meaning": 50.0}}}
	var r: Dictionary = sys.adjust_mood_stress(player, "unemployment")
	check_near(float(r["mood"]), 48.0, 1e-6, "失业降低心情")
	check_near(float(r["stress"]), 58.0, 1e-6, "失业提升压力")
	sys.adjust_mood_stress(player, "marriage")
	check(float(player["attrs"]["psychological"]["mood"]) > 48.0, "结婚提升心情")
	# 压力乘子。
	check_near(sys.stress_risk_multiplier(70.0), 1.0, 1e-6, "未超阈不增风险")
	check_near(sys.stress_risk_multiplier(100.0), 1.3, 1e-6, "高压力提高风险")


func _test_catalog_and_risk() -> void:
	var sys = MHScript.new()
	check(sys.disorders_count() >= 20, "至少 20 种精神疾病")
	for key in ["anxiety", "depression", "bipolar", "ptsd", "ocd", "social_phobia", "panic", "eating", "schizophrenia", "adhd", "bpd", "substance"]:
		check(MHScript.DISORDERS.has(key), "覆盖病种 %s" % key)
	var high: Dictionary = {"neuroticism": 95.0}
	var low: Dictionary = {"neuroticism": 5.0}
	check(sys.susceptibility("anxiety", high) > sys.susceptibility("anxiety", low), "高神经质更易感")
	check(sys.susceptibility("anxiety", high, 80.0, true) > sys.susceptibility("anxiety", high), "创伤与家族史提升易感")
	var s1: float = sys.trigger_probability("anxiety", 0.8, 40.0, "")
	var s2: float = sys.trigger_probability("anxiety", 0.8, 100.0, "stress")
	check(s2 > s1, "压力与触发提升发生概率")


func _test_course() -> void:
	var sys = MHScript.new()
	var p: Dictionary = {"neuroticism": 90.0, "extraversion": 20.0}
	var rng = RngScript.new(0)
	var triggered: bool = false
	var now: int = 0
	for i in 300:
		now += 1440
		var r: Dictionary = sys.maybe_trigger("depression", p, 90.0, "loss", now, rng, 60.0, true)
		if bool(r["triggered"]):
			triggered = true
			break
	check(triggered, "高易感最终发作")
	check(sys.has_active(), "存在活动病程")
	var case: Dictionary = sys.case_of("depression")
	check(str(case["phase"]) == "episode", "发作阶段")
	check(float(case["intensity"]) > 0.0, "强度非零")
	check(float(case["frequency_days"]) > 0.0, "频率非零")
	check(float(case["duration_minutes"]) > 0.0, "持续时长非零")
	# 推进至缓解（固定随机使其不慢性化）。
	sys.advance(200000, FixedRng.new([0.99]))
	check_eq(str(sys.case_of("depression")["phase"]), "remission", "缓解阶段")
	check(not sys.has_active(), "缓解后无活动病程")


func _test_treatment() -> void:
	# 根治。
	var sys1 = MHScript.new()
	_force_case(sys1)
	var r1: Dictionary = sys1.treat("depression", "cbt", FixedRng.new([0.0, 0.1, 0.0]), true)
	check_eq(str(r1["outcome"]), "cured", "CBT 根治")
	check_eq(sys1.case_of("depression").size(), 0, "根治后移除病程")
	# 缓解。
	var sys2 = MHScript.new()
	_force_case(sys2)
	var r2: Dictionary = sys2.treat("depression", "cbt", FixedRng.new([0.0, 0.3, 0.9]), true)
	check_eq(str(r2["outcome"]), "remitted", "CBT 缓解")
	check_eq(str(sys2.case_of("depression")["phase"]), "remission", "缓解阶段写入")
	# 无效。
	var sys3 = MHScript.new()
	_force_case(sys3)
	var r3: Dictionary = sys3.treat("depression", "cbt", FixedRng.new([0.0, 0.99, 0.99]), true)
	check_eq(str(r3["outcome"]), "ineffective", "无效")
	# 误诊（未确诊时）。
	var sys4 = MHScript.new()
	_force_case(sys4)
	var r4: Dictionary = sys4.treat("depression", "medication", FixedRng.new([0.1, 0.9, 0.9]), false)
	check(bool(r4["misdiagnosed"]), "未确诊可误诊")
	check(int(r4["cost"]) > 0, "治疗有费用")


func _test_relapse() -> void:
	var sys = MHScript.new()
	_force_case(sys)
	sys.advance(200000, FixedRng.new([0.99]))
	check_eq(str(sys.case_of("depression")["phase"]), "remission", "先缓解")
	check(sys.maybe_relapse("depression", FixedRng.new([0.0])), "缓解后复发")
	check_eq(str(sys.case_of("depression")["phase"]), "episode", "复发回到发作")
	check(int(sys.case_of("depression")["episodes"]) >= 2, "发作次数累加")


func _force_case(sys) -> void:
	var p: Dictionary = {"neuroticism": 95.0}
	var rng = RngScript.new(0)
	var now: int = 0
	for i in 500:
		now += 1440
		if bool(sys.maybe_trigger("depression", p, 95.0, "loss", now, rng, 80.0, true)["triggered"]):
			return
