extends "res://tests/test_base.gd"
## 环保、碳排与可持续发展测试（任务 34；R81；design D37）。
## 覆盖：市政环保、企业碳排与合规/碳交易、ESG 与碳足迹、污染曝光与环境诉讼、
##       绿色补贴与骗补、偷排与数据造假、环保投入挤压利润、邻避效应与从业项目。

const EnvironmentScript = preload("res://sim/environment.gd")


func _suite_name() -> String:
	return "environment"


func run_tests() -> void:
	_test_tables()
	_test_municipal()
	_test_carbon_and_compliance()
	_test_esg_and_footprint()
	_test_pollution_and_lawsuit()
	_test_boundaries()


func _test_tables() -> void:
	var sys = EnvironmentScript.new()
	check_eq(sys.career_keys().size(), 4, "四类环保从业")
	for key in sys.career_keys():
		check(not (sys.career_def(key) as Dictionary).is_empty(), "从业定义: " + str(key))


func _test_municipal() -> void:
	var sys = EnvironmentScript.new()
	var city: Dictionary = sys.new_city_env(1000000)
	check(float(sys.pollution_index(city)) > 0.0, "初始污染指数为正")
	sys.set_garbage_sorting(city, 0.8)
	var rec: Dictionary = sys.recycle(city, 100.0)
	check(float(rec["recovered"]) > 0.0, "垃圾分类后回收")
	check(float(rec["landfill"]) < 100.0, "填埋量减少")
	var air0: float = float(city["air_quality"])
	sys.air_control(city, 5000000)
	check(float(city["air_quality"]) > air0, "空气治理提升空气质量")
	sys.treat_sewage(city, 0.9)
	check_near(float(city["sewage_treatment"]), 0.9, 1e-9, "污水处理率")
	sys.issue_permit(city, "factory_a", 50.0)
	check((city["permits"] as Dictionary).has("factory_a"), "排污许可登记")
	check(float(sys.pollution_index(city)) >= 0.0, "污染指数非负")


func _test_carbon_and_compliance() -> void:
	var sys = EnvironmentScript.new()
	var ent: Dictionary = sys.new_enterprise("工厂", {"emissions": 150.0, "quota": 100.0})
	check_near(sys.carbon_balance(ent), 50.0, 1e-9, "超出配额 50")
	var comp: Dictionary = sys.compliance(ent, {"mode": "buy", "price": 100})
	check(bool(comp["compliant"]) and int(comp["cost"]) == 5000, "购买配额合规")
	check_near(sys.carbon_balance(ent), 0.0, 1e-9, "配额补平")
	check_eq(int(ent["carbon_cost"]), 5000, "碳成本入账")
	# 罚款路径。
	var ent2: Dictionary = sys.new_enterprise("工厂2", {"emissions": 200.0, "quota": 100.0})
	var fine: Dictionary = sys.compliance(ent2, {"mode": "fine", "price": 100})
	check(not bool(fine["compliant"]) and int(fine["cost"]) > 0, "超标受罚")
	check(int(ent2["fines"]) > 0, "罚款记录")
	# 碳交易。
	var ent3: Dictionary = sys.new_enterprise("工厂3", {"emissions": 100.0, "quota": 100.0})
	sys.carbon_trade(ent3, 20.0, 100)
	check_near(sys.carbon_balance(ent3), -20.0, 1e-9, "买入信用形成盈余")
	sys.carbon_trade(ent3, -30.0, 100)
	check_near(sys.carbon_balance(ent3), 10.0, 1e-9, "卖出后转为超标")
	# 合规企业无需行动。
	var clean: Dictionary = sys.new_enterprise("清洁厂", {"emissions": 80.0, "quota": 100.0})
	check(str(sys.compliance(clean, {})["action"]) == "none", "未超标无需合规操作")


func _test_esg_and_footprint() -> void:
	var sys = EnvironmentScript.new()
	var low: Dictionary = sys.new_enterprise("低排", {"emissions": 20.0, "quota": 100.0})
	var high: Dictionary = sys.new_enterprise("高排", {"emissions": 180.0, "quota": 100.0})
	var rl: Dictionary = sys.esg_rating(low)
	var rh: Dictionary = sys.esg_rating(high)
	check(float(rl["score"]) > float(rh["score"]), "碳排越低 ESG 越高")
	check_eq(str(rl["grade"]), "A", "低排 A 级")
	var base_score: float = float(rl["score"])
	sys.low_carbon_transition(low, 1000000, {})
	check(float(low["emissions"]) < 20.0, "低碳转型减排")
	check(float(sys.esg_rating(low)["score"]) >= base_score, "减排与绿色投入提升 ESG")
	var fp: Dictionary = sys.carbon_footprint(high)
	check_near(float(fp["scope1"]) + float(fp["scope2"]) + float(fp["scope3"]), float(fp["total"]), 1e-9, "碳足迹分范围守恒")


func _test_pollution_and_lawsuit() -> void:
	var sys = EnvironmentScript.new()
	var city: Dictionary = sys.new_city_env(500000)
	sys.pollute(city, 0.9, {"source": "factory"})
	check(float(city["pollution"]) > 0.2, "污染上升")
	check(float(city["health_index"]) < 1.0, "区域健康下降")
	var exp: Dictionary = sys.expose_pollution(city, {"illegal": true})
	check(float(exp["reputation_delta"]) < 0.0, "曝光损失声誉")
	check(bool(exp["legal"]), "触发法律后果")
	check(bool(city["lawsuit_open"]), "环境诉讼立案")
	var law: Dictionary = sys.environmental_lawsuit(city, {})
	check(bool(law["liable"]) and int(law["compensation"]) > 0, "环境诉讼判赔")


func _test_boundaries() -> void:
	var sys = EnvironmentScript.new()
	# 碳数据造假。
	var ent: Dictionary = sys.new_enterprise("造假厂", {"emissions": 120.0, "quota": 100.0})
	var rep: Dictionary = sys.report_carbon(ent, 80.0, {"roll": 0.0, "detect_risk": 0.5})
	check(bool(rep["understated"]) and bool(ent["fraud"]), "低报构成数据造假")
	check(bool(rep["detected"]), "造假被查获")
	# 偷排。
	var ent2: Dictionary = sys.new_enterprise("偷排厂", {"emissions": 100.0, "quota": 100.0})
	var dis: Dictionary = sys.illegal_discharge(ent2, 50.0, {"roll": 0.0, "detect_risk": 0.5})
	check(bool(dis["detected"]), "偷排被查获")
	check(int(dis["fines"]) > 0, "偷排罚款")
	# 环保投入挤压利润。
	var sq: Dictionary = sys.investment_profit_squeeze(0.3, 0.5)
	check(float(sq["margin"]) < 0.3, "环保投入压缩利润率")
	# 骗补与正常补贴。
	var co: Dictionary = sys.new_career_org("env_company", {"funds": 0})
	var org: Dictionary = co["org"]
	var sub: Dictionary = sys.green_subsidy(org, 500000, {"fraud": true, "roll": 0.0, "detect_risk": 0.5})
	check(bool(sub["detected"]) and int(sub["granted"]) == 0, "骗补被查获")
	check(bool(org["fraud"]), "骗补标记")
	var co2: Dictionary = sys.new_career_org("green_energy", {})
	var sub2: Dictionary = sys.green_subsidy(co2["org"], 500000, {})
	check_eq(int(sub2["granted"]), 500000, "正常补贴到账")
	# 从业项目与减排。
	var proj: Dictionary = sys.run_project(co2["org"], "风电项目", 1000000, {"emission_cut": 10.0})
	check(int(proj["profit"]) > 0, "环保项目盈利")
	check(float(co2["org"]["emission_cut"]) > 0.0, "项目带来减排")
	# 邻避效应。
	var city: Dictionary = sys.new_city_env(100000)
	var nim: Dictionary = sys.nimby(city, {"name": "垃圾焚烧厂"}, {"scale": 1.0, "near_residents": 1.0, "reputation": 0.2})
	check(float(nim["opposition"]) > 0.5, "邻避反对强烈")
	check(int(nim["delay_days"]) > 0, "项目延期")
