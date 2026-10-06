extends "res://tests/test_base.gd"
## 应急、消防与灾害救援测试（任务 34、34.1；R80；design D36）。
## 覆盖：数据表与流程、响应时间对伤亡的单调影响、分诊与资源取舍、
##       救援人员伤亡与指挥失当追责、志愿救援组织。

const EmergencyScript = preload("res://sim/emergency.gd")


func _suite_name() -> String:
	return "emergency"


func run_tests() -> void:
	_test_tables()
	_test_flow_and_advance()
	_test_response_time_monotonic()
	_test_triage_and_resources()
	_test_rescuer_and_accountability()
	_test_volunteer_org()


func _test_tables() -> void:
	var sys = EmergencyScript.new()
	check_eq(sys.profession_keys().size(), 6, "六类救援职业")
	for key in sys.profession_keys():
		var def: Dictionary = sys.profession_def(key)
		check(not def.is_empty(), "职业定义: " + str(key))
		check((def["equipment"] as Array).size() > 0, "专业装备: " + str(key))
	check_eq(str(EmergencyScript.STAGES[0]), "alarm", "流程起点为报警")


func _test_flow_and_advance() -> void:
	var sys = EmergencyScript.new()
	var inc: Dictionary = sys.new_incident("ems", {"severity": 0.7, "at_risk": 120, "trapped": 30, "medical_capacity": 40})
	check_eq(str(inc["stage"]), "alarm", "初始报警")
	var a1: Dictionary = sys.advance(inc, {"profession": "ems", "distance_km": 3.0})
	check_eq(str(a1["stage"]), "dispatch", "推进到出警")
	check(float(a1["response_minutes"]) > 0.0, "出警产生响应时间")
	var a2: Dictionary = sys.advance(inc)
	check_eq(str(a2["stage"]), "rescue", "推进到救援")
	check(int(a2["injured"]) > 0, "有伤员")
	var a3: Dictionary = sys.advance(inc)
	check_eq(str(a3["stage"]), "aftermath", "推进到善后")
	check(not bool(sys.advance(inc)["ok"]), "终态拒绝推进")


func _test_response_time_monotonic() -> void:
	var sys = EmergencyScript.new()
	var inc: Dictionary = sys.new_incident("fire", {"severity": 0.9, "at_risk": 300})
	var fast: float = sys.estimate_casualties(inc, 3.0)
	var slow: float = sys.estimate_casualties(inc, 45.0)
	check(fast < slow, "响应越快需救治人数越少")
	var prev: float = -1.0
	for t in [1.0, 5.0, 10.0, 20.0, 40.0, 60.0]:
		var c: float = sys.estimate_casualties(inc, t)
		check(c >= prev - 1e-9, "响应时间增加伤亡单调不降")
		prev = c
	# 实际死亡同样随响应时间上升。
	var fast_case: Dictionary = sys.new_incident("fire", {"severity": 0.9, "at_risk": 300, "trapped": 100, "medical_capacity": 200})
	var rf: Dictionary = sys.rescue(fast_case, {"response_minutes": 3.0})
	var slow_case: Dictionary = sys.new_incident("fire", {"severity": 0.9, "at_risk": 300, "trapped": 100, "medical_capacity": 200})
	var rs: Dictionary = sys.rescue(slow_case, {"response_minutes": 45.0})
	check(int(rf["deaths"]) < int(rs["deaths"]), "响应越快死亡越少")


func _test_triage_and_resources() -> void:
	var sys = EmergencyScript.new()
	var tri_low: Dictionary = sys.triage(100.0, 10)
	check(float(tri_low["untreated"]) > 0.0, "容量不足存在未救治")
	check(float(tri_low["red_treated"]) <= 10.0 + 1e-9, "优先救治红色伤员")
	check(float(tri_low["red_treated"]) > 0.0, "红类得到救治")
	var tri_high: Dictionary = sys.triage(100.0, 200)
	check_near(float(tri_high["untreated"]), 0.0, 1e-9, "容量充足全部救治")
	# 资源多则死亡少。
	var low: Dictionary = sys.new_incident("earthquake_rescue", {"severity": 0.9, "at_risk": 500, "trapped": 300, "medical_capacity": 10})
	var high: Dictionary = sys.new_incident("earthquake_rescue", {"severity": 0.9, "at_risk": 500, "trapped": 300, "medical_capacity": 500})
	var rl: Dictionary = sys.rescue(low, {"response_minutes": 20.0})
	var rh: Dictionary = sys.rescue(high, {"response_minutes": 20.0})
	check(int(rl["deaths"]) > int(rh["deaths"]), "医疗资源充足死亡更少")


func _test_rescuer_and_accountability() -> void:
	var sys = EmergencyScript.new()
	var inc: Dictionary = sys.new_incident("flood_rescue", {
		"severity": 0.9, "at_risk": 300, "command_quality": 0.2, "rescue_teams": 5,
	})
	var ra: int = sys.rescuer_casualties(inc)
	check(ra > 0, "指挥差导致救援人员伤亡")
	var sec: Dictionary = sys.secondary_incident(inc, {"roll": 0.0})
	check(bool(sec["occurred"]), "二次事故触发")
	check(int(sec["deaths"]) > 0, "二次事故增加死亡")
	check(int(sec["responder_casualties"]) > 0, "二次事故救援人员伤亡")
	inc["deaths"] = 10
	var af: Dictionary = sys.aftermath(inc)
	check_eq(str(af["fault"]), "command_fault", "指挥失当被追责")
	check(int(af["penalty"]) > 0, "指挥失当产生处罚")
	check(float(af["psych_trauma"]) > 0.0, "灾后心理创伤")
	# 正常指挥且无伤亡：免责。
	var good: Dictionary = sys.new_incident("fire", {"command_quality": 0.9})
	good["deaths"] = 0
	var af2: Dictionary = sys.aftermath(good)
	check_eq(str(af2["fault"]), "", "无失当不追责")


func _test_volunteer_org() -> void:
	var sys = EmergencyScript.new()
	var org: Dictionary = sys.new_volunteer_org("蓝天救援", {"funds": 100000, "volunteers": 10})
	check(bool(sys.purchase_equipment(org, "life_jacket", 10000)["ok"]), "采购救援设备")
	check_eq(int(org["equipment"]), 1, "设备入库")
	check(not bool(sys.purchase_equipment(org, "boat", 9999999)["ok"]), "资金不足拒绝采购")
	sys.recruit_volunteers(org, 20)
	check_eq(int(org["volunteers"]), 30, "招募志愿者")
	# 志愿支援缩短响应时间。
	var inc1: Dictionary = sys.new_incident("fire", {"equipment_level": 0.3})
	var inc2: Dictionary = sys.new_incident("fire", {"equipment_level": 0.3})
	var d1: Dictionary = sys.dispatch(inc1, {"profession": "fire", "distance_km": 10.0})
	var d2: Dictionary = sys.volunteer_dispatch(org, inc2, {"profession": "fire", "distance_km": 10.0})
	check(float(d2["response_minutes"]) < float(d1["response_minutes"]), "志愿支援缩短响应时间")
