extends "res://tests/test_base.gd"
## 战争与征兵测试（任务 27；R60；design D16）。
## 覆盖：关系状态机跃迁与外交、宣战/停战/占领、征兵条件与缓征、抽签、征召与民役、
##       拒征法律后果、前线伤亡与战俘交换、战争经济与战后重建。

const WarScript = preload("res://sim/war.gd")
const RngScript = preload("res://sim/rng.gd")
const MilitaryScript = preload("res://sim/military.gd")


func _suite_name() -> String:
	return "war"


func run_tests() -> void:
	_test_world_and_pair_key()
	_test_stance_escalation()
	_test_diplomacy()
	_test_declare_and_end_war()
	_test_conscription_policy_and_assessment()
	_test_draftee_selection_and_conscript()
	_test_refuse_draft()
	_test_front_and_casualty()
	_test_war_economy_and_recovery()


func _world() -> Dictionary:
	var sys = WarScript.new()
	return sys.new_world(["CN", "US", "JP"])


func _soldier() -> Dictionary:
	return {
		"age": 20,
		"attrs": {"physiological": {"health": 85.0}},
		"education": [{"content_key": "edu.high_school", "status": "graduated"}],
		"skills": [{"content_key": "skill.physique", "level": 5}],
		"legal": {"wanted_level": 0, "criminal_record": false, "in_prison": false},
	}


# --- 世界与关系键 ---

func _test_world_and_pair_key() -> void:
	var sys = WarScript.new()
	var state: Dictionary = _world()
	check_eq(state["relations"].size(), 3, "三国两两成对")
	check_eq(WarScript.pair_key("CN", "US"), WarScript.pair_key("US", "CN"), "关系键与顺序无关")
	check_eq(sys.stance(state, "CN", "US"), "peace", "初始和平")
	check_eq(sys.stance(state, "US", "CN"), "peace", "反向同状态")
	check_eq(sys.relation(state, "CN", "US"), sys.relation(state, "US", "CN"), "正反向同关系对象")


# --- 状态机跃迁 ---

func _test_stance_escalation() -> void:
	var sys = WarScript.new()
	var state: Dictionary = _world()
	var r1: Dictionary = sys.adjust_tension(state, "CN", "US", 25.0)
	check_eq(str(r1["stance"]), "tension", "≥20 转紧张")
	var r2: Dictionary = sys.adjust_tension(state, "CN", "US", 30.0)
	check_eq(str(r2["stance"]), "limited_conflict", "≥50 转局部冲突")
	check(r2["escalated"], "状态应发生跃迁")
	var r3: Dictionary = sys.adjust_tension(state, "CN", "US", 40.0)
	check_near(float(r3["tension"]), 95.0, 1e-6, "张紧度累加")
	check_eq(str(r3["stance"]), "total_war", "≥80 转全面战争")
	# 张紧度夹紧于 [0,100]。
	var r4: Dictionary = sys.adjust_tension(state, "CN", "US", -500.0)
	check_near(float(r4["tension"]), 0.0, 1e-6, "张紧度下限夹紧")
	check_eq(str(r4["stance"]), "peace", "归零回和平")
	# 驱动因子加权 + 随机。
	var r5: Dictionary = sys.apply_drivers(state, "JP", "US", {"territorial": 10.0, "economy": 5.0})
	check(float(r5["tension"]) > 0.0, "驱动因子提升张紧度")


# --- 外交 ---

func _test_diplomacy() -> void:
	var sys = WarScript.new()
	var state: Dictionary = _world()
	var a: Dictionary = sys.form_alliance(state, "CN", "US")
	check(bool(a["alliance"]), "结盟成功")
	check(bool(sys.relation(state, "CN", "US")["alliance"]), "关系记录同盟")
	sys.adjust_tension(state, "CN", "US", 60.0)
	var s: Dictionary = sys.impose_sanction(state, "CN", "US", 1.0)
	check(bool(sys.relation(state, "CN", "US")["sanction"]), "制裁记录")
	check(float(s["tension"]) > 60.0, "制裁提升张紧度")
	var v: Dictionary = sys.sever_relations(state, "CN", "US")
	check(not bool(sys.relation(state, "CN", "US")["alliance"]), "断交解除同盟")
	check(float(v["tension"]) > float(s["tension"]), "断交继续提升")
	check(sys.arms_race(state, "JP", "US", 1.0)["defense_spending"] > 0, "军备竞赛产生军费")
	check(bool(sys.proxy_war(state, "JP", "CN", 1.0)["proxy"]), "代理人战争")


# --- 宣战 / 停战 / 占领 ---

func _test_declare_and_end_war() -> void:
	var sys = WarScript.new()
	var state: Dictionary = _world()
	# 张紧度不足不可宣战。
	var low: Dictionary = sys.declare_war(state, "CN", "US", 0)
	check(not bool(low["ok"]), "低张紧度宣战失败")
	check_eq(str(low["reason"]), "tension_too_low", "原因张紧度不足")
	# 升到门槛后可宣战。
	sys.adjust_tension(state, "CN", "US", 75.0)
	var d: Dictionary = sys.declare_war(state, "CN", "US", 100)
	check(bool(d["ok"]), "张紧度足够可宣战")
	check(bool(sys.relation(state, "CN", "US")["at_war"]), "进入交战")
	check_eq(sys.active_war_count(state), 1, "活跃战争计数")
	check_eq(str(d["stance"]), "limited_conflict", "交战但未全面")
	check(not bool(sys.declare_war(state, "CN", "US", 120)["ok"]), "重复宣战失败")
	# 停战。
	var c: Dictionary = sys.ceasefire(state, "CN", "US", 200)
	check(bool(c["ok"]), "停战成功")
	check_eq(str(c["stance"]), "ceasefire", "进入停战")
	check_eq(sys.active_war_count(state), 0, "停战后无活跃战争")
	# 占领。
	var o: Dictionary = sys.occupy(state, "US", "JP", ["tokyo"], {"new_tax_rate": 0.4})
	check_eq(str(o["occupier"]), "US", "占领方记录")
	check_eq(sys.stance(state, "JP", "US"), "occupation", "进入占领状态")
	check((o["occupied_regions"] as Array).has("tokyo"), "占领区记录")


# --- 征兵政策与评估 ---

func _test_conscription_policy_and_assessment() -> void:
	var sys = WarScript.new()
	var state: Dictionary = _world()
	check(not bool(sys.set_conscription_policy(state, "bogus")["ok"]), "未知政策被拒")
	var p: Dictionary = sys.set_conscription_policy(state, "lottery", {"quota": 10, "deferments": ["student"]})
	check(bool(p["ok"]) and bool(p["active"]), "抽签政策激活")
	check_eq(int(p["quota"]), 10, "配额记录")
	check((p["deferments"] as Array).has("student"), "缓征集合记录")
	# 合格者。
	var ok: Dictionary = sys.draft_assessment(_soldier(), {"age": 20})
	check(bool(ok["eligible"]), "健康适龄可征")
	# 超龄。
	check(not bool(sys.draft_assessment(_soldier(), {"age": 45})["eligible"]), "超龄免征")
	# 健康不足。
	var sick: Dictionary = _soldier()
	sick["attrs"] = {"physiological": {"health": 30.0}}
	check((sys.draft_assessment(sick, {"age": 20})["reasons"] as Array).has("health"), "健康不足缓征")
	# 缓征：在读。
	var student: Dictionary = _soldier()
	student["education"] = [{"content_key": "edu.university", "status": "enrolled"}]
	check((sys.draft_assessment(student, {"age": 20})["reasons"] as Array).has("student"), "在读缓征")
	# 缓征：独生。
	var only: Dictionary = _soldier()
	only["only_child"] = true
	check((sys.draft_assessment(only, {"age": 20})["reasons"] as Array).has("only_child"), "独生缓征")
	# 缓征：关键岗位。
	var doctor: Dictionary = _soldier()
	doctor["job"] = "job.doctor"
	check((sys.draft_assessment(doctor, {"age": 20})["reasons"] as Array).has("key_job"), "关键岗位缓征")


# --- 抽签与征召 ---

func _test_draftee_selection_and_conscript() -> void:
	var sys = WarScript.new()
	var rng = RngScript.new(12345)
	var candidates: Array = []
	for i in 20:
		var c: Dictionary = {"id": i, "age": 20, "attrs": {"physiological": {"health": 80.0}}}
		if i % 5 == 0:
			c["only_child"] = true
		candidates.append(c)
	var sel: Dictionary = sys.select_draftees(candidates, 6, rng, {"age": 20})
	check_eq((sel["selected"] as Array).size(), 6, "按配额选出六人")
	check_eq(int(sel["deferred"]), 4, "独生者被缓征")
	# 同种子可复现。
	var sel2: Dictionary = sys.select_draftees(candidates, 6, RngScript.new(12345), {"age": 20})
	check_eq(sel["selected"], sel2["selected"], "同种子抽签结果一致")
	# 征召入伍（合格者）。
	var soldier: Dictionary = _soldier()
	var r: Dictionary = sys.conscript(soldier, 0, {"age": 20, "branch": "army"})
	check_eq(str(r["assigned"]), "military", "合格者入军籍")
	check(str(soldier["military"]["status"]) == "serving", "军籍在役")
	check(bool(soldier["military"].get("conscripted", false)), "标记为征召")
	# 缓征者转民役。
	var only: Dictionary = _soldier()
	only["only_child"] = true
	var r2: Dictionary = sys.conscript(only, 0, {"age": 20})
	check_eq(str(r2["assigned"]), "alternative_service", "缓征者转替代服役")
	check(only.has("alternative_service"), "民役记录")


func _test_refuse_draft() -> void:
	var sys = WarScript.new()
	var p: Dictionary = _soldier()
	var r: Dictionary = sys.refuse_draft(p, 10)
	check(bool(r["criminal_record"]), "拒征留犯罪记录")
	check(int(r["wanted_level"]) >= 2, "拒征提升通缉度")


# --- 前线与伤亡 ---

func _test_front_and_casualty() -> void:
	var sys = WarScript.new()
	var rng = RngScript.new(777)
	var state: Dictionary = _world()
	sys.adjust_tension(state, "CN", "US", 80.0)
	sys.declare_war(state, "CN", "US", 0)
	var war: Dictionary = (state["wars"] as Array)[0]
	var forces: Dictionary = {
		"a": {"troops": 10000, "power": 1.2, "supply": 1.0},
		"b": {"troops": 5000, "power": 0.9, "supply": 0.8},
	}
	var t: Dictionary = sys.front_tick(war, forces, rng, {"intensity": 1.0})
	check(int(t["loss_a"]) >= 0 and int(t["loss_b"]) >= 0, "双方损失非负")
	check(float(t["advantage_a"]) > 0.0, "优势方为正")
	check(int((t["casualties"] as Dictionary)["CN"]) == int(t["loss_a"]), "伤亡计入战场")
	# 个人前线伤亡（阵亡/负伤/PTSD）。
	var p: Dictionary = _soldier()
	var heavy: Dictionary = sys.front_casualty(p, 1.0, RngScript.new(1), {"minute": 5})
	check(float(p["attrs"]["physiological"]["health"]) < 85.0, "前线伤亡降低健康")
	check(bool(heavy["kia"]) or bool(p.get("ptsd", false)) or heavy["wound"] > 0.0, "伤亡结果有效")
	# 战俘交换。
	var ex: Dictionary = sys.exchange_pow(100, RngScript.new(3), {"rate": 0.6})
	check(int(ex["exchanged"]) > 0, "战俘可交换")
	check_eq(int(ex["exchanged"]) + int(ex["remaining"]), 100, "交换后守恒")


# --- 战争经济与战后重建 ---

func _test_war_economy_and_recovery() -> void:
	var sys = WarScript.new()
	var state: Dictionary = _world()
	sys.adjust_tension(state, "CN", "US", 80.0)
	sys.declare_war(state, "CN", "US", 0)
	sys.set_mobilization(state, 0.8)
	var eff: Dictionary = sys.war_economy_effects(state)
	check(int(eff["defense_jobs"]) > 0, "军工岗位增加")
	check(float(eff["price_shock"]) > 0.0, "物价冲击")
	check(float(eff["black_market"]) > 0.0, "黑市抬头")
	check(bool(eff["rationing"]), "高动员触发配给")
	var eco: Dictionary = sys.tick_economy(state, 2.0, {"war_tax_per_year": 100000000})
	check(int(eco["debt"]) > 0, "国债上升")
	check(int(eco["reconstruction_fund"]) > 0, "重建基金累积")
	check(float(eco["inflation"]) > 0.0, "通胀上升")
	var rec: Dictionary = sys.postwar_recovery({"population": 10000, "buildings": 500}, 5.0, {"reparations": 999})
	check(int(rec["population_recovered"]) > 0, "人口统计快进恢复")
	check(int(rec["buildings_recovered"]) > 0, "建筑恢复")
	check(int(rec["population_recovered"]) <= 10000, "恢复不超损失")
	check_eq(int(rec["reparations"]), 999, "赔款记录")
