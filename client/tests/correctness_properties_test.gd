extends "res://tests/test_base.gd"
## 新增领域不变量属性测试（任务 53；design Correctness Properties）。
## 以多变体循环验证：碳守恒、工程进度单调、救援时间有界、异常暴露单调、班期准点率有界。

const EnvScript = preload("res://sim/environment.gd")
const EngineeringScript = preload("res://sim/engineering.gd")
const EmergencyScript = preload("res://sim/emergency.gd")
const AnomalyScript = preload("res://sim/anomaly.gd")
const TransportInfraScript = preload("res://sim/transport_infra.gd")
const RngScript = preload("res://sim/rng.gd")

func _suite_name() -> String:
	return "correctness_properties"

func run_tests() -> void:
	_test_carbon_conservation()
	_test_engineering_stage_monotonic()
	_test_response_time_bounded()
	_test_anomaly_exposure_monotonic()
	_test_on_time_rate_bounded()

## 碳守恒：碳平衡恒等于 排放 −（配额 + 信用）；合规买入后平衡归零且信用恰好补足差额。
func _test_carbon_conservation() -> void:
	var env = EnvScript.new()
	for i in range(200):
		var emissions: float = float((i * 37) % 500)
		var quota: float = float((i * 13) % 300)
		var credits: float = float((i * 7) % 120)
		var ent: Dictionary = env.new_enterprise("ent.%d" % i, {
			"emissions": emissions, "quota": quota, "credits": credits,
		})
		var balance: float = env.carbon_balance(ent)
		check_near(balance, emissions - (quota + credits), 1e-6, "碳平衡定义 i=%d" % i)
		if balance > 1e-6:
			var before_credits: float = float(ent["credits"])
			var settled: Dictionary = env.compliance(ent, {"mode": "buy", "price": 100})
			check(settled.get("ok", false), "合规结算成功 i=%d" % i)
			check_near(float(ent["credits"]), before_credits + balance, 1e-6, "信用补足差额 i=%d" % i)
			check_near(env.carbon_balance(ent), 0.0, 1e-6, "买入后碳平衡归零 i=%d" % i)

## 工程进度单调：stage_index 只增不减且有界；同一工程反复推进最终到达终态。
func _test_engineering_stage_monotonic() -> void:
	var eng = EngineeringScript.new()
	for i in range(50):
		var proj: Dictionary = eng.new_project({"id": "p.%d" % i, "scale": 1000000})
		var contractor: Dictionary = eng.new_contractor({"qualification": "special", "capital": 1000000000})
		var last_index: int = int(proj["stage_index"])
		var rng = RngScript.new(1000 + i)
		for _step in range(20):
			eng.advance_stage(proj, contractor, {
				"survey_quality": 0.9, "design_quality": 0.9, "cost_quality": 0.9,
				"workmanship": 0.9, "quality": 0.9, "supervision_strength": 0.9,
			}, rng)
			var idx: int = int(proj["stage_index"])
			check(idx >= last_index, "stage_index 单调不减 i=%d" % i)
			check(idx <= EngineeringScript.CHAIN.size(), "stage_index 有界 i=%d" % i)
			last_index = idx
		check_eq(int(proj["stage_index"]), EngineeringScript.CHAIN.size(), "工程最终完成 i=%d" % i)

## 救援时间有界：响应时间落在 [1, 2*cap]；距离越远越慢、支援越多不更慢。
func _test_response_time_bounded() -> void:
	var ems = EmergencyScript.new()
	var cap: float = EmergencyScript.DEFAULT_RESPONSE_CAP
	var prev_by_distance: float = -1.0
	for d in range(0, 50, 2):
		var inc: Dictionary = ems.new_incident("fire", {"severity": 0.5, "at_risk": 10})
		var out: Dictionary = ems.dispatch(inc, {"distance_km": float(d), "training": 0.5, "equipment_level": 0.5})
		var t: float = float(out["response_minutes"])
		check(t >= 1.0 and t <= cap * 2.0, "响应时间有界 d=%d" % d)
		check(t >= prev_by_distance - 1e-6, "距离增加响应不更快 d=%d" % d)
		prev_by_distance = t
	# 志愿者增加不更慢。
	var base: Dictionary = ems.new_incident("fire", {})
	var t0: float = float(ems.dispatch(base, {"distance_km": 10.0, "volunteers": 0})["response_minutes"])
	var t1: float = float(ems.dispatch(base, {"distance_km": 10.0, "volunteers": 20})["response_minutes"])
	check(t1 <= t0 + 1e-6, "志愿者增加不更慢")

## 异常暴露单调：正向暴露累加不减；负向不会降到 0 以下。
func _test_anomaly_exposure_monotonic() -> void:
	var anom = AnomalyScript.new()
	for i in range(30):
		var s: Dictionary = anom.new_state()
		var last: float = anom.exposure(s)
		var rng = RngScript.new(2000 + i)
		for _step in range(15):
			var gain: float = rng.next_float() * 10.0
			anom.add_exposure(s, gain)
			var e: float = anom.exposure(s)
			check(e >= last - 1e-6, "正向暴露不减 i=%d" % i)
			last = e
		anom.add_exposure(s, -99999.0)
		check(anom.exposure(s) >= 0.0, "暴露下限为零 i=%d" % i)

## 班期准点率有界：0..1，且在多变体下均成立。
func _test_on_time_rate_bounded() -> void:
	var ti = TransportInfraScript.new()
	for i in range(100):
		var proj: Dictionary = ti.new_infra_project({"id": "r.%d" % i})
		proj["quality"] = float(i % 11) / 10.0
		proj["capacity"] = 1.0 + float(i % 5)
		var out: Dictionary = ti.operate(proj, {
			"mode": "logistics", "fare": 50.0, "demand": 1.0 + float(i % 4),
			"supply": 1.0 + float(i % 3), "roll": float(i % 20) / 20.0,
		})
		var on_time: float = float(out["on_time_rate"])
		check(on_time >= 0.0 and on_time <= 1.0, "准点率有界 i=%d got=%f" % [i, on_time])
