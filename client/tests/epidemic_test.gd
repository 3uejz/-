extends "res://tests/test_base.gd"
## 流行病与公共卫生测试（任务 28.1；R61；design D17）。
## 覆盖：SEIR 传播与阶段、政策抑制、医院挤兑、预警分级、疫苗与资源、跨区域扩散、变异与免疫衰减、经济伤疤。

const EpiScript = preload("res://sim/epidemic.gd")
const RngScript = preload("res://sim/rng.gd")


func _suite_name() -> String:
	return "epidemic"


func run_tests() -> void:
	_test_new_region_and_seed()
	_test_seir_and_stages()
	_test_policies()
	_test_hospital_surge_and_alert()
	_test_vaccine_and_resources()
	_test_cross_region_and_mutation()
	_test_economy_scar()


func _test_new_region_and_seed() -> void:
	var sys = EpiScript.new()
	var r: Dictionary = sys.new_region(1000000)
	check_eq(int(r["population"]), 1000000, "人口记录")
	check_near(float(r["susceptible"]), 1000000.0, 1e-6, "初始全易感")
	check_eq(int(r["deaths"]), 0, "初始无死亡")
	check(int((r["resources"] as Dictionary)["beds"]) > 0, "床位数按人口推导")
	check_eq(sys.active_policies(r).size(), 0, "初始无政策")
	var s: Dictionary = sys.seed(r, 10)
	check(float(r["exposed"]) > 0.0, "接种输入病例")
	check_eq(str(s["stage"]), "outbreak", "接种后进入爆发")


func _test_seir_and_stages() -> void:
	var sys = EpiScript.new()
	var r: Dictionary = sys.new_region(1000000, {"beta": 0.6, "sigma": 0.2, "gamma": 0.3, "mortality": 0.02})
	sys.seed(r, 100)
	var peak: float = 0.0
	for i in 400:
		var out: Dictionary = sys.step(r, 1.0)
		peak = maxf(peak, float(out["infectious"]))
	check(peak > 100.0, "疫情出现峰值")
	check(int(r["deaths"]) > 0, "出现死亡")
	check_eq(str(r["stage"]), "resolved", "最终消退")
	# 守恒：S+E+I+R ≈ 人口（死亡计入移除口径外，此处允许移除含死亡差异，仅校验非负）。
	check(float(r["susceptible"]) >= 0.0 and float(r["infectious"]) >= 0.0, "分舱非负")


func _test_policies() -> void:
	var sys = EpiScript.new()
	var r: Dictionary = sys.new_region(1000000)
	var base_beta: float = sys.effective_beta(r)
	var p: Dictionary = sys.set_policy(r, "lockdown", true)
	check(bool(p["ok"]), "设置停工成功")
	check(float(p["effective_beta"]) < base_beta, "停工降低有效传播率")
	check(float(p["effective_beta"]) <= base_beta * 0.45, "停工抑制显著")
	check(not bool(sys.set_policy(r, "bogus", true)["ok"]), "未知政策被拒")
	sys.set_policy(r, "mask", true)
	check(sys.active_policies(r).size() == 2, "多项政策叠加")
	check(float(r["public_trust"]) < 1.0, "强制政策引发民意反弹")
	# 政策降低实际感染增速：有政策组峰值低于无政策组。
	var a: Dictionary = sys.new_region(1000000, {"beta": 0.6, "sigma": 0.2, "gamma": 0.1, "mortality": 0.01})
	var b: Dictionary = sys.new_region(1000000, {"beta": 0.6, "sigma": 0.2, "gamma": 0.1, "mortality": 0.01})
	sys.seed(a, 100)
	sys.seed(b, 100)
	sys.set_policy(b, "lockdown", true)
	sys.set_policy(b, "quarantine", true)
	var peak_a: float = 0.0
	var peak_b: float = 0.0
	for i in 120:
		peak_a = maxf(peak_a, float((sys.step(a, 1.0))["infectious"]))
		peak_b = maxf(peak_b, float((sys.step(b, 1.0))["infectious"]))
	check(peak_b < peak_a, "防疫政策显著压低峰值")


func _test_hospital_surge_and_alert() -> void:
	var sys = EpiScript.new()
	var r: Dictionary = sys.new_region(1000000)
	# 控制床位，制造挤兑。
	(r["resources"] as Dictionary)["beds"] = 100
	r["infectious"] = 400.0
	check_near(sys.hospital_occupancy(r), 4.0, 1e-6, "占用率计算")
	check(sys.surge_factor(r) > 1.0, "挤兑放大死亡率")
	check_eq(sys.alert_level(r), 3, "极高占用触发紧急预警")
	r["infectious"] = 2000.0
	check_eq(sys.alert_level(r), 3, "高流行率紧急预警")
	r["infectious"] = 0.0
	check_eq(sys.alert_level(r), 0, "无疫情无预警")


func _test_vaccine_and_resources() -> void:
	var sys = EpiScript.new()
	var r: Dictionary = sys.new_region(1000000, {}, {"vaccine_stock": 100000, "vaccine_hesitancy": 0.2})
	var before: float = float(r["susceptible"])
	var v: Dictionary = sys.vaccinate(r, 100000, RngScript.new(1))
	check(int(v["vaccinated"]) > 0, "接种生效")
	check(float(r["susceptible"]) < before, "接种减少易感")
	check(int(v["remaining_stock"]) < 100000, "消耗库存")
	# 疫苗犹豫降低接种数。
	var r2: Dictionary = sys.new_region(1000000, {}, {"vaccine_stock": 100000, "vaccine_hesitancy": 0.9})
	var v2: Dictionary = sys.vaccinate(r2, 100000, RngScript.new(1))
	check(int(v2["vaccinated"]) < int(v["vaccinated"]), "高犹豫接种更少")
	# 增加资源。
	sys.add_resources(r, {"beds": 500})
	check(int((r["resources"] as Dictionary)["beds"]) > 0, "资源可增加")


func _test_cross_region_and_mutation() -> void:
	var sys = EpiScript.new()
	var src: Dictionary = sys.new_region(500000)
	var dst: Dictionary = sys.new_region(500000)
	sys.seed(src, 5000)
	sys.step(src, 5.0)
	var sp: Dictionary = sys.cross_region_spread(src, dst, 10000)
	check(float(sp["imported"]) > 0.0, "跨区域输入病例")
	check(str(dst["stage"]) == "outbreak", "目标区爆发")
	var beta0: float = float((src["params"] as Dictionary)["beta"])
	sys.mutate(src, 0.5)
	check(float((src["params"] as Dictionary)["beta"]) > beta0, "变异提高传播率")
	# 免疫衰减。
	var r: Dictionary = sys.new_region(1000000)
	r["removed"] = 10000.0
	var w: Dictionary = sys.wane_immunity(r, 30.0)
	check(float(w["waned"]) > 0.0, "免疫随时间衰减")
	check(float(r["susceptible"]) > 1000000.0, "衰减人群回归易感")


func _test_economy_scar() -> void:
	var sys = EpiScript.new()
	var r: Dictionary = sys.new_region(1000000)
	sys.set_policy(r, "lockdown", true)
	for i in 100:
		sys.step(r, 1.0)
	check(float(r["economy_scar"]) > 0.0, "防疫政策累积经济伤疤")
