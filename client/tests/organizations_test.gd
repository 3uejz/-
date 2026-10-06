extends "res://tests/test_base.gd"
## 组织与社团测试（任务 29；R63；design D19）。
## 覆盖：类型/晋升表、加入与会费/任务/晋升、退出成本与叛逃、集体行动与罢工后果、
##       派系斗争、秘密组织暴露清算与内鬼、破产解散。

const OrgScript = preload("res://sim/organizations.gd")


func _suite_name() -> String:
	return "organizations"


func run_tests() -> void:
	_test_type_tables()
	_test_join_dues_task_promotion()
	_test_leave_cost_and_defection()
	_test_collective_action()
	_test_faction_struggle()
	_test_secret_exposure_and_mole()
	_test_bankruptcy()


func _test_type_tables() -> void:
	var sys = OrgScript.new()
	check_eq(sys.type_count(), 8, "八类组织")
	for key in sys.org_types():
		var def: Dictionary = sys.type_def(str(key))
		check(def.has("name") and def.has("goal"), "类型含目标: " + str(key))
		check(def.has("legality") and def.has("base_fee"), "类型含合法性与会费: " + str(key))
		check(float(def["influence"]) > 0.0, "影响力为正: " + str(key))
	check_eq(sys.member_ranks().size(), 4, "四级内部晋升")
	check_eq(sys.legalities().size(), 3, "三种合法性")
	check(not sys.has_type("bogus"), "未知类型被拒")


func _test_join_dues_task_promotion() -> void:
	var sys = OrgScript.new()
	var created: Dictionary = sys.create_org("union", 50)
	check(bool(created["ok"]), "建立工会")
	var org: Dictionary = created["org"]
	var owner: Dictionary = {}
	var joined: Dictionary = sys.join(owner, org, {"minute": 100})
	check(bool(joined["ok"]), "加入组织")
	check_eq(int(joined["dues"]), 50000, "会费按类型")
	check_eq((joined["membership"] as Dictionary)["rank_index"], 0, "初始为成员")
	check_eq(int(org["members"]), 51, "组织人数增加")
	check(not bool(sys.join(owner, org, {})["ok"]), "重复加入被拒")
	var m: Dictionary = sys.membership(owner, str(org["id"]))
	check_eq(int(m["dues_owed"]), 50000, "初始欠缴会费")
	sys.pay_dues(m, 50000)
	check_eq(int(m["dues_owed"]), 0, "缴清会费")
	# 完成任务到晋升门槛。
	for i in 3:
		sys.assign_task(org, m, "task_%d" % i)
		sys.complete_task(org, m, true)
	check_eq(int(m["tasks_completed"]), 3, "任务计数")
	check(sys.evaluate_promotion(org, m), "达到晋升门槛")
	var promoted: Dictionary = sys.promote(org, m)
	check(bool(promoted["ok"]), "晋升成功")
	check_eq(str(promoted["rank_key"]), "core", "晋升为骨干")
	check(sys.stipend(m) > 0, "骨干有津贴")


func _test_leave_cost_and_defection() -> void:
	var sys = OrgScript.new()
	var created: Dictionary = sys.create_org("criminal_gang", 6)
	var org: Dictionary = created["org"]
	var owner: Dictionary = {}
	sys.join(owner, org, {})
	var approved: int = sys.exit_cost(org, true)
	var unapproved: int = sys.exit_cost(org, false)
	check(unapproved > approved, "未获批准退出成本更高")
	check(approved > 0, "非法组织退出非免费")
	var left: Dictionary = sys.leave(owner, org, {"approved": false})
	check(bool(left["ok"]), "退出成功")
	check(int(left["exit_cost"]) > 0, "结算退出成本")
	check(float(left["defection_risk"]) >= 0.6, "非法组织叛逃风险高")
	check(float(left["legal_risk"]) > 0.0, "非法组织有法律风险")
	check(float(org["heat"]) > 0.0, "叛逃秘密组织提高被查热度")
	check(sys.membership(owner, str(org["id"])).is_empty(), "退出后无成员关系")


func _test_collective_action() -> void:
	var sys = OrgScript.new()
	var org: Dictionary = (sys.create_org("union", 200)["org"])
	var high: Dictionary = {"members": 200, "target_members": 100, "external_support": 1.0, "opponent_pressure": 0.0, "public_opinion": 1.0}
	var low: Dictionary = {"members": 0, "target_members": 100, "external_support": 0.0, "opponent_pressure": 1.0, "public_opinion": -1.0}
	check(sys.action_probability(org, "strike", high) > sys.action_probability(org, "strike", low), "规模/支持/舆论提高成功率且压力压低")
	check(sys.action_probability(org, "strike", high) <= 0.95, "成功率封顶")
	check(sys.action_probability(org, "strike", low) >= 0.05, "成功率保底")
	check(not bool(sys.collective_action(org, "bogus", high)["ok"]), "未知行动被拒")
	var act: Dictionary = sys.collective_action(org, "strike", {"members": 200, "target_members": 100, "external_support": 1.0, "opponent_pressure": 0.0, "public_opinion": 1.0, "roll": 0.1})
	check(bool(act["success"]), "罢工成功")
	var cons: Dictionary = act["consequences"]
	check(bool(cons.get("industry_halt", false)), "罢工致行业停摆")
	check(int(cons.get("unemployment", 0)) > 0, "罢工致失业")
	check(float(act["influence"]) > 0.50, "成功提升影响力")


func _test_faction_struggle() -> void:
	var sys = OrgScript.new()
	var org: Dictionary = (sys.create_org("party", 100)["org"])
	sys.form_faction(org, "A", 0.8)
	sys.form_faction(org, "B", 0.3)
	check_near(sys.faction_strength(org, "A"), 0.8, 1e-6, "派系实力记录")
	var split: Dictionary = sys.faction_struggle(org, "B", {"roll": 0.1})
	check_eq(str(split["outcome"]), "split", "弱势派系分裂")
	check(int(org["members"]) < 100, "分裂减少成员")
	var seize: Dictionary = sys.faction_struggle(org, "A", {"roll": 0.1})
	check_eq(str(seize["outcome"]), "seize_power", "强势派系夺权")
	check_eq(str(org["leader_faction"]), "A", "记录掌权派系")
	var purge: Dictionary = sys.faction_struggle(org, "A", {"roll": 0.9})
	check_eq(str(purge["outcome"]), "purge", "清洗结果")
	check(int(org["purge_count"]) >= 1, "清洗计数")


func _test_secret_exposure_and_mole() -> void:
	var sys = OrgScript.new()
	var org: Dictionary = (sys.create_org("secret_society", 20)["org"])
	check(sys.is_secret(org), "秘密组织")
	sys.add_heat(org, 120.0)
	check(not bool(sys.attempt_expose(org, {"roll": 0.0})["exposed"]), "反侦察下未暴露")
	sys.set_counter_intel(org, 0.0)
	var exp: Dictionary = sys.attempt_expose(org, {"roll": 0.0})
	check(bool(exp["exposed"]), "超阈值暴露")
	check(bool(org["exposed"]), "标记已暴露")
	var owner: Dictionary = {"legal": {}, "reputation": {"fame": 50.0}}
	var out: Dictionary = sys.handle_exposure(owner, org)
	check(bool(out["disbanded"]), "暴露即清算解散")
	check(bool((owner["legal"] as Dictionary)["criminal_record"]), "暴露留案底")
	check(int(out["wanted_level"]) > 0, "通缉等级上升")
	check(float((owner["reputation"] as Dictionary)["fame"]) < 50.0, "声望下降")
	check(not bool(sys.handle_exposure(owner, (sys.create_org("club", 3)["org"]))["ok"]), "非暴露组织不可清算")
	# 内鬼机制。
	var org2: Dictionary = (sys.create_org("secret_society", 10)["org"])
	sys.plant_mole(org2, "内鬼甲")
	var found: Dictionary = sys.detect_mole(org2, {"roll": 0.0})
	check(bool(found["found"]), "排查揪出内鬼")
	check_eq(str(found["mole"]), "内鬼甲", "内鬼身份")


func _test_bankruptcy() -> void:
	var sys = OrgScript.new()
	var org: Dictionary = (sys.create_org("club", 0)["org"])
	var fin: Dictionary = sys.tick_finance(org, 0, 1000)
	check(bool(fin["bankrupt"]), "资不抵债且无成员即破产")
	var dis: Dictionary = sys.declare_bankruptcy(org)
	check(bool(dis["disbanded"]), "破产即解散")
	check_eq(int(org["members"]), 0, "解散清空成员")
