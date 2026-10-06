extends "res://tests/test_base.gd"
## 会展、演出与大型活动测试（任务 33；R77；design D33）。
## 覆盖：数据表、活动全流程（场地→报批→招商→票务→安保→现场→复盘）、
##       赞助与收益、超售踩踏追责、艺人违约与退票潮、票务欺诈与黄牛、策划职业。

const EventsExpoScript = preload("res://sim/events_expo.gd")


func _suite_name() -> String:
	return "events_expo"


func run_tests() -> void:
	_test_tables()
	_test_full_flow()
	_test_sponsors_and_revenue()
	_test_oversell_and_stampede()
	_test_artist_breach_and_refund()
	_test_fraud_scalping_and_liability()
	_test_career()


func _test_tables() -> void:
	var sys = EventsExpoScript.new()
	check_eq(sys.event_type_keys().size(), 7, "七类活动")
	check_eq(EventsExpoScript.STAGES.size(), 7, "七步流程")
	check_eq(sys.sponsor_tier_keys().size(), 4, "四档赞助")
	check_eq(sys.career_role_keys().size(), 4, "四种策划职业")
	check_eq(str(sys.stage_names()["review"]), "复盘", "复盘阶段命名")
	check_eq(str((sys.event_type_def("wedding") as Dictionary)["name"]), "婚礼庆典", "婚礼庆典类型")


func _test_full_flow() -> void:
	var sys = EventsExpoScript.new()
	var ev: Dictionary = sys.new_event("concert", {"budget": 20000000, "reputation": 60.0, "star_power": 80.0})
	check_eq(str(ev["stage"]), "venue", "初始为场地租赁")
	var rv: Dictionary = sys.rent_venue(ev, {"name": "体育馆", "capacity": 20000, "cost": 3000000})
	check(bool(rv["ok"]) and int(ev["capacity"]) == 20000, "场地容量设定")
	check_eq(int(ev["budget"]), 17000000, "场租扣款")
	var ap: Dictionary = sys.apply_approval(ev, true)
	check(bool(ap["approved"]) and str(ev["stage"]) == "sponsor", "报批通过进入招商")
	sys.add_sponsor(ev, "title")
	sys.add_sponsor(ev, "gold")
	var sell: Dictionary = sys.sell_tickets(ev, 18000)
	check(bool(sell["ok"]) and int(ev["sold"]) == 18000, "票务售出")
	check_eq(int(sell["revenue"]), 18000 * 6800, "票面收入")
	check(bool(sys.set_security(ev, 0.9, {"cost": 500000})["ok"]), "安保配置")
	var hold: Dictionary = sys.hold_event(ev, 0.9)
	check_eq(int(hold["attendance"]), 18000, "实际上座")
	check(int(hold["gate"]) > 0, "门票收益")
	check_eq((hold["incidents"] as Array).size(), 0, "高安保无事故")
	var rev: Dictionary = sys.after_action_review(ev)
	check_eq(str(ev["stage"]), "review", "进入复盘")
	check_eq(int(rev["profit"]), int(rev["revenue"]) - int(rev["cost"]), "净利润恒等式")
	# 报批驳回推迟。
	var ev2: Dictionary = sys.new_event("expo", {"budget": 10000000})
	var ap2: Dictionary = sys.apply_approval(ev2, false, {"delay_days": 45.0})
	check(not bool(ap2["approved"]) and float(ev2["approval_delay_days"]) == 45.0, "报批驳回推迟")


func _test_sponsors_and_revenue() -> void:
	var sys = EventsExpoScript.new()
	var ev: Dictionary = sys.new_event("music_festival", {"budget": 10000000})
	sys.rent_venue(ev, {"capacity": 30000, "cost": 1000000})
	sys.apply_approval(ev, true)
	var sp: Dictionary = sys.add_sponsor(ev, "silver")
	check(bool(sp["ok"]) and int(sp["amount"]) == 800000, "银牌赞助金额")
	ev["streaming_deal"] = 2000000
	sys.sell_tickets(ev, 20000)
	var hold: Dictionary = sys.hold_event(ev, 0.9, {"bad_weather": false})
	check(int(hold["merchandise"]) > 0, "周边收益")
	check_eq(int(hold["streaming"]), 2000000, "直播版权收益")
	check(int(ev["revenue"]) > 0, "总收益累计")
	check(not bool(sys.add_sponsor(ev, "bogus")["ok"]), "未知赞助档被拒")


func _test_oversell_and_stampede() -> void:
	var sys = EventsExpoScript.new()
	var ev: Dictionary = sys.new_event("music_festival", {"budget": 20000000})
	sys.rent_venue(ev, {"capacity": 1000, "cost": 0})
	sys.apply_approval(ev, true)
	var sell: Dictionary = sys.sell_tickets(ev, 1200)
	check(bool(sell["oversold"]), "超售判定")
	check((ev["risks"] as Array).has("oversell"), "记录超售风险")
	sys.set_security(ev, 0.2, {"cost": 0})
	var hold: Dictionary = sys.hold_event(ev, 0.0, {"stampede": true})
	var incidents: Array = hold["incidents"]
	check(incidents.has("oversell"), "事故含超售")
	check(incidents.has("stampede"), "事故含踩踏")
	check(incidents.has("security_failure"), "事故含安保失效")
	var liab: Dictionary = sys.accident_liability(ev, 0.9)
	check(int((liab["liability"] as Dictionary)["compensation"]) > 0, "事故赔偿")
	check(float(ev["reputation"]) >= 0.0, "声誉非负")
	# 未知风险处理：合规活动不误伤。
	var good: Dictionary = sys.new_event("comedy_show", {"budget": 1000000})
	check_eq(str(good["type"]), "concert", "未知类型回退演唱会")


func _test_artist_breach_and_refund() -> void:
	var sys = EventsExpoScript.new()
	var ev: Dictionary = sys.new_event("concert", {"budget": 10000000})
	sys.rent_venue(ev, {"capacity": 1000, "cost": 0})
	sys.sell_tickets(ev, 500)
	var ab: Dictionary = sys.artist_breach(ev, 0.0)
	check(bool(ab["breach"]) and bool(ab["cancelled"]), "艺人违约取消")
	check(int(ab["refund"]) > 0, "违约退票")
	check_eq(int(ev["sold"]), 0, "退票后售出清零")
	var rep0: float = float(ev["reputation"])
	check(float(ev["reputation"]) < 100.0, "违约声誉下滑")
	# 退票潮。
	var ev2: Dictionary = sys.new_event("concert", {"budget": 10000000})
	sys.rent_venue(ev2, {"capacity": 1000, "cost": 0})
	sys.sell_tickets(ev2, 1000)
	var rw: Dictionary = sys.refund_wave(ev2, 0.5)
	check_eq(int(rw["refunded_qty"]), 500, "退票潮比例")
	check_eq(int(ev2["sold"]), 500, "退票后余票")
	check(int(rw["refund"]) > 0, "退票返还")


func _test_fraud_scalping_and_liability() -> void:
	var sys = EventsExpoScript.new()
	var ev: Dictionary = sys.new_event("comic_con", {"budget": 10000000})
	sys.rent_venue(ev, {"capacity": 15000, "cost": 0})
	sys.sell_tickets(ev, 10000)
	var sc: Dictionary = sys.scalping(ev, 100, {"premium": 1.5})
	check(int(sc["hoarded"]) == 100 and int(sc["lost_revenue"]) > 0, "黄牛囤票损失")
	var tf: Dictionary = sys.ticket_fraud(ev, 0.0, {"fake_count": 50})
	check(bool(tf["fraud"]) and int(tf["loss"]) > 0, "票务欺诈损失")
	var safe: Dictionary = sys.ticket_fraud(ev, 0.9)
	check(not bool(safe["fraud"]), "高 roll 无欺诈")
	var rep0: float = float(ev["reputation"])
	var al: Dictionary = sys.accident_liability(ev, 0.8)
	check(int((al["liability"] as Dictionary)["compensation"]) > 0, "安全事故追责赔偿")
	check(float(ev["reputation"]) < rep0, "追责后声誉下降")
	check(bool(sys.to_dict(ev).has("incidents")), "序列化快照")


func _test_career() -> void:
	var sys = EventsExpoScript.new()
	var planner: Dictionary = sys.new_planner("planner", {"level": 1, "exp": 0})
	check_eq(str(planner["role"]), "planner", "策划职业")
	var cp: Dictionary = sys.career_progress(planner, {"rating": 70.0})
	check(int(cp["exp"]) > 0 and int(planner["events_done"]) == 1, "从业经验累积")
	for i in range(30):
		sys.career_progress(planner, {"rating": 100.0})
	check(int(planner["level"]) > 1, "经验达标升级")
	var unknown: Dictionary = sys.new_planner("bogus")
	check_eq(str(unknown["role"]), "planner", "未知职业回退策划")
