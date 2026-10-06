extends "res://tests/test_base.gd"
## 后期科技测试（任务 30；R68；design D24）。
## 覆盖：阶段顺序解锁与时代判定、职业阶段/技能门槛、高风险任务事故与伤亡、
##       自动化失业与社会事件、极端环境健康惩罚、生物科技延寿、气候难民与 AI 伦理失控。

const LateTechScript = preload("res://sim/late_tech.gd")


func _suite_name() -> String:
	return "late_tech"


func run_tests() -> void:
	_test_stage_unlock()
	_test_era_sync()
	_test_career_gating()
	_test_risk_mission()
	_test_automation_impact()
	_test_extreme_environment_and_biotech()
	_test_climate_and_ai()


func _test_stage_unlock() -> void:
	var sys = LateTechScript.new()
	var state: Dictionary = sys.new_state()
	check_eq(sys.stage_count(), 3, "信息/智能/星际三阶段")
	check_eq(str(sys.current_stage(state)), "information", "初始为信息阶段")
	check_eq((state["unlocked_stages"] as Array).size(), 1, "初始仅解锁信息阶段")
	var skip: Dictionary = sys.unlock_stage(state, "interstellar")
	check(not bool(skip["ok"]), "不能跳级解锁")
	check_eq(str(skip["reason"]), "locked", "跳级被拒理由")
	var up1: Dictionary = sys.unlock_stage(state, "intelligent")
	check(bool(up1["ok"]), "顺序解锁智能阶段")
	var up2: Dictionary = sys.unlock_stage(state, "interstellar")
	check(bool(up2["ok"]), "顺序解锁星际阶段")
	check_eq((state["unlocked_stages"] as Array).size(), 3, "全部阶段解锁")
	check(not bool(sys.unlock_stage(state, "information")["ok"]), "重复解锁被拒")
	# 解锁内容查询。
	var info: Dictionary = sys.new_state()
	check(sys.unlocked(info, "jobs", "robot_operator"), "信息阶段含机器人运维")
	check(not sys.unlocked(info, "jobs", "aerospace_astronaut"), "信息阶段无宇航员")
	sys.unlock_stage(info, "intelligent")
	check(sys.unlocked(info, "jobs", "aerospace_astronaut"), "智能阶段解锁宇航员")
	check(sys.unlocked(info, "equipment", "space_station"), "智能阶段解锁空间站")


func _test_era_sync() -> void:
	var sys = LateTechScript.new()
	check_eq(sys.stage_index_for_era("intelligent"), 1, "智能时代映射")
	check_eq(sys.stage_index_for_era("stone"), -1, "早期无后期科技")
	var state: Dictionary = sys.new_state()
	check(not sys.can_unlock_by_era(state, "stone"), "早期时代不可解锁")
	check(sys.can_unlock_by_era(state, "interstellar"), "星际时代可解锁")
	var sync: Dictionary = sys.sync_with_era(state, "interstellar")
	check(bool(sync["ok"]), "按时代同步成功")
	check_eq(int(state["stage_index"]), 2, "同步到星际阶段")
	check(not bool(sys.sync_with_era(state, "stone")["ok"]), "早期时代无法同步")


func _test_career_gating() -> void:
	var sys = LateTechScript.new()
	var state: Dictionary = sys.new_state()
	check(not bool(sys.apply_for_career(state, "aerospace_astronaut", 18)["ok"]), "阶段未解锁不可应聘")
	check_eq(str(sys.apply_for_career(state, "aerospace_astronaut", 18)["reason"]), "stage_locked", "阶段锁定理由")
	sys.unlock_stage(state, "intelligent")
	var low: Dictionary = sys.apply_for_career(state, "aerospace_astronaut", 5)
	check_eq(str(low["reason"]), "skill_too_low", "技能不足被拒")
	var ok: Dictionary = sys.apply_for_career(state, "aerospace_astronaut", 18)
	check(bool(ok["ok"]), "阶段与技能满足可应聘")
	check_eq(int(ok["salary"]), 500000, "宇航员薪资")
	check(not bool(sys.apply_for_career(state, "bogus", 18)["ok"]), "未知职业被拒")
	check_eq(sys.careers_for_stage("interstellar").size(), 2, "星际阶段两个职业")


func _test_risk_mission() -> void:
	var sys = LateTechScript.new()
	var state: Dictionary = sys.new_state()
	check(not bool(sys.risk_mission(state, "space_station_work", 18, {"roll": 0.0})["ok"]), "阶段未解锁不可执行")
	sys.unlock_stage(state, "intelligent")
	check(not bool(sys.risk_mission(state, "space_station_work", 5, {"roll": 0.0})["ok"]), "技能不足不可执行")
	var run: Dictionary = sys.risk_mission(state, "space_station_work", 18, {"roll": 0.0, "casualty_roll": 0.99})
	check(bool(run["accident"]), "低 roll 触发事故")
	check(not bool(run["casualty"]), "事故未致命")
	check(int(run["reward"]) > 0, "平安完成获高额回报")
	check(not (run["environment_effect"] as Dictionary).is_empty(), "事故附带环境健康效应")
	var deadly: Dictionary = sys.risk_mission(state, "space_station_work", 18, {"roll": 0.0, "casualty_roll": 0.0})
	check(bool(deadly["casualty"]), "事故致死判定")
	check_eq(int(deadly["reward"]), 0, "伤亡无回报")


func _test_automation_impact() -> void:
	var sys = LateTechScript.new()
	var state: Dictionary = sys.new_state()
	var impact: Dictionary = sys.automation_impact(state, 1.0, {"traditional_jobs": 100000.0, "new_job_capacity": 10000.0})
	check(int(impact["jobs_lost"]) > 0, "自动化淘汰传统岗位")
	check(int(impact["jobs_created"]) > 0, "自动化创造新岗位")
	check(int(impact["net_jobs"]) < 0, "净岗位减少")
	check(bool(impact["social_security_issue"]), "高失业触发社会保障议题")
	check((impact["events"] as Array).size() > 0, "产生社会事件")
	check(float(state["unemployment_rate"]) > 0.0, "失业率写入状态")


func _test_extreme_environment_and_biotech() -> void:
	var sys = LateTechScript.new()
	check(not bool(sys.extreme_environment_effect("bogus", 1.0)["ok"]), "未知环境被拒")
	var wl: Dictionary = sys.extreme_environment_effect("weightless", 1.0, {})
	check(float(wl["bone_loss"]) > 0.0, "失重导致骨流失")
	check(float(wl["muscle_loss"]) > 0.0, "失重导致肌肉流失")
	var deep: Dictionary = sys.extreme_environment_effect("high_pressure", 1.0, {})
	check(float(deep["pressure_damage"]) > 0.0, "深海高压损伤")
	var tol: Dictionary = sys.extreme_environment_effect("weightless", 1.0, {"tolerance": 0.5})
	check(float(tol["bone_loss"]) < float(wl["bone_loss"]), "适应降低健康惩罚")
	# 延寿。
	var state: Dictionary = sys.new_state()
	var bio: Dictionary = sys.biotech_lifespan(state, 5000000.0, {})
	check(float(bio["lifespan_gain"]) > 0.0, "生物科技获得寿命增益")
	check_near(float(bio["total_bonus"]), float(bio["lifespan_gain"]), 1e-6, "寿命增益累计")
	check(float(bio["side_effect_risk"]) > 0.0, "延寿伴随副作用风险")


func _test_climate_and_ai() -> void:
	var sys = LateTechScript.new()
	var state: Dictionary = sys.new_state()
	var warm: Dictionary = sys.climate_refugees(state, 2.0, {"coastal_population": 1000000.0})
	check(int(warm["refugees"]) > 0, "升温产生气候难民")
	check((warm["events"] as Array).size() > 0, "气候难民记为社会事件")
	var none: Dictionary = sys.climate_refugees(state, 0.5, {"coastal_population": 1000000.0})
	check_eq(int(none["refugees"]), 0, "低温升不产生难民")
	var ai: Dictionary = sys.ai_ethics_incident(state, 1.0, {"roll": 0.0, "critical": true})
	check(bool(ai["loss_of_control"]), "高自主性触发 AI 失控")
	check_eq((ai["chain"] as Array).size(), 2, "关键技术事故连锁")
