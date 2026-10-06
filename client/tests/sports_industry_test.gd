extends "res://tests/test_base.gd"
## 体育产业与赛事测试（任务 33；R76；design D32，与 sports.gd 运动员个人生涯互补）。
## 覆盖：数据表、职业合同与转会、经纪人佣金、联赛赛程积分与升降级、国家队征召、
##       兴奋剂/假球/赌球裁决、伤病与致残、俱乐部经营与破产、球迷冲突与学业冲突。

const SportsIndustryScript = preload("res://sim/sports_industry.gd")


func _suite_name() -> String:
	return "sports_industry"


func run_tests() -> void:
	_test_tables()
	_test_career_and_transfer()
	_test_league_and_promotion()
	_test_national_and_international()
	_test_scandals()
	_test_injuries()
	_test_club_finance_and_bankruptcy()
	_test_edges()


func _test_tables() -> void:
	var sys = SportsIndustryScript.new()
	check_eq(sys.career_stages().size(), 5, "五段职业阶段")
	check_eq(sys.competition_keys().size(), 5, "五类赛事")
	check_eq(sys.division_keys().size(), 3, "三级联赛")
	check_eq(sys.scandal_keys().size(), 4, "四类丑闻")
	check_eq(sys.injury_keys().size(), 4, "四级伤病")
	check_eq(str((sys.scandal_def("doping") as Dictionary)["name"]), "兴奋剂", "兴奋剂丑闻")


func _test_career_and_transfer() -> void:
	var sys = SportsIndustryScript.new()
	var club_a: Dictionary = sys.new_club("A", {"budget": 50000000, "strength": 70.0})
	var club_b: Dictionary = sys.new_club("B", {"budget": 80000000, "strength": 65.0})
	var p: Dictionary = sys.new_pro("p1", "A", {"age": 24, "form": 80.0, "market_value": 10000000})
	check(bool(sys.sign_pro_contract(p, club_a, 2000000, 3.0)["ok"]), "签订职业合同")
	check_eq(str(p["club"]), "A", "归属俱乐部")
	var mv: int = sys.market_value(p)
	check(mv > 0, "身价估值")
	# 转会与经纪人佣金。
	var tr: Dictionary = sys.transfer(p, club_b, 20000000, {"agent_fee_rate": 0.1})
	check(bool(tr["ok"]), "转会成功")
	check_eq(int(tr["agent_fee"]), 2000000, "经纪人佣金 10%")
	check_eq(str(p["club"]), "B", "转入新俱乐部")
	check_eq(str(p["career_stage"]), "transfer", "阶段为转会")
	# 低薪报价被拒。
	var oc: Dictionary = sys.offer_contract(p, 100000, 2.0)
	check(not bool(oc["accepted"]), "低薪报价被拒")
	var ok_offer: Dictionary = sys.offer_contract(p, int(oc["expected_wage"]), 2.0)
	check(bool(ok_offer["accepted"]), "合理报价被接受")
	# 赞助与退役。
	var sp: Dictionary = sys.sponsorship(p, {"brand": "X", "amount": 500000})
	check((p["sponsors"] as Array).size() == 1, "赞助登记")
	var rt: Dictionary = sys.retire(p)
	check_eq(str(rt["stage"]), "retire", "退役")


func _test_league_and_promotion() -> void:
	var sys = SportsIndustryScript.new()
	var top: Dictionary = sys.new_league("T", "top")
	var second: Dictionary = sys.new_league("S", "second")
	var clubs: Dictionary = {}
	for i in range(1, 5):
		var c: Dictionary = sys.new_club("t%d" % i, {"division": "top"})
		clubs["t%d" % i] = c
		sys.register_club(top, c)
	for i in range(1, 5):
		var c: Dictionary = sys.new_club("s%d" % i, {"division": "second"})
		clubs["s%d" % i] = c
		sys.register_club(second, c)
	# 赛程与积分。
	sys.schedule_season(top)
	check_eq((top["fixtures"] as Array).size(), 6, "四队单循环六场")
	var a: Dictionary = clubs["t1"]
	var b: Dictionary = clubs["t2"]
	var m: Dictionary = sys.play_match(top, a, b, null, {"home_score": 3, "away_score": 1})
	check_eq(str(m["winner"]), "t1", "主队取胜")
	var st: Array = sys.standings(top)
	check_eq(str((st[0] as Dictionary)["id"]), "t1", "积分榜头名")
	check_eq(int((st[0] as Dictionary)["points"]), 3, "胜场 3 分")
	var draw: Dictionary = sys.play_match(top, b, a, null, {"home_score": 1, "away_score": 1})
	check_eq(str(draw["winner"]), "draw", "平局")
	# 直接设置积分以验证升降级。
	(top["standings"] as Dictionary)["t1"]["points"] = 12
	(top["standings"] as Dictionary)["t2"]["points"] = 9
	(top["standings"] as Dictionary)["t3"]["points"] = 6
	(top["standings"] as Dictionary)["t4"]["points"] = 3
	(second["standings"] as Dictionary)["s1"]["points"] = 12
	(second["standings"] as Dictionary)["s2"]["points"] = 9
	(second["standings"] as Dictionary)["s3"]["points"] = 6
	(second["standings"] as Dictionary)["s4"]["points"] = 3
	var pr: Dictionary = sys.apply_promotion_relegation(top, second, clubs)
	check_eq((pr["relegated"] as Array).size(), 2, "降级两队")
	check_eq((pr["promoted"] as Array).size(), 2, "升级两队")
	check((pr["relegated"] as Array).has("t4"), "末位降级")
	check((pr["promoted"] as Array).has("s1"), "次级头名升级")
	check_eq(str(clubs["t4"]["division"]), "second", "俱乐部降入次级")
	check_eq(str(clubs["s1"]["division"]), "top", "俱乐部升入顶级")


func _test_national_and_international() -> void:
	var sys = SportsIndustryScript.new()
	var p: Dictionary = sys.new_pro("p", "A", {"form": 80.0})
	var call: Dictionary = sys.national_callup(p, "中国")
	check(bool(call["ok"]) and str(p["national_team"]) == "中国", "国家队征召")
	p["ban_days"] = 100.0
	check(not bool(sys.national_callup(p, "中国")["ok"]), "禁赛期不可征召")
	var low: Dictionary = sys.new_pro("low", "A", {"form": 40.0})
	check(not bool(sys.national_callup(low, "中国")["ok"]), "状态不足不可征召")
	var it: Dictionary = sys.international_tournament("world_cup", [{"id": "cn", "strength": 80.0}, {"id": "br", "strength": 75.0}])
	check_eq(str(it["champion"]), "cn", "世界杯冠军")
	check(not bool(sys.international_tournament("bogus", [])["ok"]), "未知赛事被拒")


func _test_scandals() -> void:
	var sys = SportsIndustryScript.new()
	var p: Dictionary = sys.new_pro("p", "A", {"form": 80.0})
	sys.set_doping(p, true)
	var dt: Dictionary = sys.doping_test(p, 0.1)
	check(bool(dt["positive"]) and float(p["ban_days"]) == 730.0, "药检阳性禁赛两年")
	var clean: Dictionary = sys.new_pro("clean", "A")
	check(not bool(sys.doping_test(clean, 0.1)["positive"]), "未服药药检阴性")
	# 假球裁决（涉法）。
	var cs: Dictionary = sys.commit_scandal(clean, "match_fixing")
	check(bool(cs["legal"]) and float(cs["ban_days"]) == 365.0, "假球禁赛并涉法")
	check(int(cs["fine"]) > 0, "假球罚款")
	check(not bool(sys.commit_scandal(clean, "bogus")["ok"]), "未知丑闻被拒")
	# 调查披露。
	var inv: Dictionary = sys.investigate("gambling", 0.1, {"risk": 0.5})
	check(bool(inv["exposed"]) and bool(inv["legal"]), "赌球被调查披露")
	var inv2: Dictionary = sys.investigate("gambling", 0.9, {"risk": 0.5})
	check(not bool(inv2["exposed"]), "未达调查门槛")
	# 转会黑幕。
	var tf: Dictionary = sys.new_pro("tf", "A")
	var tr: Dictionary = sys.transfer(tf, sys.new_club("B"), 1000000, {"fraud": true})
	check(bool(tr["fraud"]), "转会黑幕标记")


func _test_injuries() -> void:
	var sys = SportsIndustryScript.new()
	var p: Dictionary = sys.new_pro("p", "A", {"form": 80.0})
	var inj: Dictionary = sys.injure(p, "severe")
	check(float(inj["days"]) == 240.0 and float(p["form"]) < 80.0, "重伤停赛与状态下滑")
	var rb: Dictionary = sys.rehab(p, 100.0)
	check(not bool(rb["recovered"]) and float(rb["remaining_days"]) > 0.0, "康复中")
	var rb2: Dictionary = sys.rehab(p, 200.0)
	check(bool(rb2["recovered"]), "康复复出")
	var p2: Dictionary = sys.new_pro("p2", "A", {"form": 80.0})
	var ce: Dictionary = sys.injure(p2, "career_ending")
	check(bool(ce["permanent"]) and bool(p2["disabled"]), "严重伤病致残")
	check_near(sys.player_strength(p2), 5.0, 1e-9, "致残后实力骤降")
	check(not bool(sys.rehab(p2, 10.0)["ok"]), "致残不可康复")
	check(not bool(sys.injure(p, "bogus")["ok"]), "未知伤级被拒")


func _test_club_finance_and_bankruptcy() -> void:
	var sys = SportsIndustryScript.new()
	var club: Dictionary = sys.new_club("C", {
		"budget": 10000000, "attendance": 30000, "ticket_price": 10000,
		"reputation": 70.0, "wage_bill": 5000000, "youth_academy": 0.8,
	})
	var fin: Dictionary = sys.club_finance(club, 1, {"home_matches": 15, "operations": 2000000})
	check(int((fin["income"] as Dictionary)["total"]) > 0, "赛季收入为正")
	check_eq(int(fin["budget"]), 10000000 + int(fin["net"]), "预算结算")
	# 入不敷出破产。
	var poor: Dictionary = sys.new_club("P", {"budget": 1000, "attendance": 0})
	poor["wage_bill"] = 100000000
	var fin2: Dictionary = sys.club_finance(poor, 20, {"home_matches": 0, "operations": 5000000})
	check(bool(fin2["bankrupt"]), "入不敷出破产")
	var bk: Dictionary = sys.club_bankrupt(poor)
	check(bool(bk["ok"]) and str(poor["division"]) == "second", "破产降级")
	# 未破产不可清算。
	var rich: Dictionary = sys.new_club("R", {"budget": 10000000, "bankrupt": false})
	check(not bool(sys.club_bankrupt(rich)["ok"]), "健康俱乐部不可清算")


func _test_edges() -> void:
	var sys = SportsIndustryScript.new()
	var club: Dictionary = sys.new_club("C", {"budget": 10000000, "fans": 50000, "reputation": 60.0})
	var fv: Dictionary = sys.fan_violence(club, 0.0)
	check(bool(fv["incident"]) and int(fv["fine"]) > 0, "球场冲突罚款")
	check(int(club["fans"]) < 50000, "球迷流失")
	var calm: Dictionary = sys.fan_violence(sys.new_club("D"), 0.9)
	check(not bool(calm["incident"]), "高 roll 无冲突")
	var rc: Dictionary = sys.referee_controversy({}, 0.0)
	check(bool(rc["disputed"]) and int(rc["protest_fee"]) > 0, "裁判争议申诉")
	var p: Dictionary = sys.new_pro("p", "A", {"enrolled": true})
	p["gpa"] = 62.0
	var ac: Dictionary = sys.academic_conflict(p, {"gpa_penalty": 10.0})
	check(bool(ac["conflict"]) and not bool(ac["can_continue"]), "学业与训练冲突")
	check(not bool(p["enrolled"]), "成绩过低退学")
	check(bool(sys.to_dict(club).has("budget")), "序列化快照")
