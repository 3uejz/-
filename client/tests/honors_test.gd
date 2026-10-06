extends "res://tests/test_base.gd"
## 荣誉、奖项与名人堂测试（任务 34；R78；design D34）。
## 覆盖：数据表、提名与评审（偏好/关系/政治化）、评定与影响、黑幕揭露与撤销、
##       名人堂跨代传承、并列处理。

const HonorsScript = preload("res://sim/honors.gd")


func _suite_name() -> String:
	return "honors"


func run_tests() -> void:
	_test_tables()
	_test_nominate_and_evaluate()
	_test_award_flow_and_effects()
	_test_scandal_reveal_and_revoke()
	_test_hall_and_inheritance()
	_test_tie_and_politics()


func _test_tables() -> void:
	var sys = HonorsScript.new()
	check_eq(sys.category_count(), 6, "六大领域")
	check_eq(sys.award_count(), 6, "六项奖项")
	for key in sys.award_keys():
		var def: Dictionary = sys.award_def(key)
		check(HonorsScript.CATEGORIES.has(str(def["category"])), "奖项归属领域: " + str(key))
		check(float(def["prestige"]) > 0.0, "奖项声望为正")


func _test_nominate_and_evaluate() -> void:
	var sys = HonorsScript.new()
	var c: Dictionary = sys.new_candidate("c1", {"achievement": 50.0})
	var nom: Dictionary = sys.nominate(c, "academic_prize")
	check(bool(nom["ok"]) and not bool(nom["eligible"]), "成就不足不能提名")
	sys.set_achievement(c, 80.0)
	check(bool(sys.nominate(c, "academic_prize")["eligible"]), "达标可提名")
	check(not bool(sys.nominate(c, "bogus")["ok"]), "未知奖项被拒")
	# 同行评价越高得分越高。
	var low: Dictionary = sys.evaluate(c, "academic_prize", {"id": "j1", "peer_review": 0.0}, {})
	var high: Dictionary = sys.evaluate(c, "academic_prize", {"id": "j1", "peer_review": 1.0}, {})
	check(float(high["score"]) > float(low["score"]), "同行评价提高评分")
	# 关系影响：普通关系与评审私人关系。
	c["relations"] = 0.0
	var r0: Dictionary = sys.evaluate(c, "academic_prize", {"id": "j1", "peer_review": 0.0}, {})
	c["relations"] = 1.0
	var r1: Dictionary = sys.evaluate(c, "academic_prize", {"id": "j1", "peer_review": 0.0}, {})
	check(float(r1["score"]) > float(r0["score"]), "社会关系提高评分")
	sys.set_jury_relation(c, "j1", 1.0)
	c["relations"] = 0.0
	var r2: Dictionary = sys.evaluate(c, "academic_prize", {"id": "j1", "peer_review": 0.0}, {})
	check(float(r2["score"]) > float(r0["score"]), "评审私人关系提高评分")


func _test_award_flow_and_effects() -> void:
	var sys = HonorsScript.new()
	var hall: Dictionary = sys.new_hall()
	var c: Dictionary = sys.new_candidate("c1", {"achievement": 85.0, "relations": 0.8})
	var r: Dictionary = sys.award(c, "academic_prize", {"id": "j1", "peer_review": 0.9}, {"hall": hall})
	check(bool(r["awarded"]), "达标且高评审通过")
	check_eq((c["honors"] as Array).size(), 1, "登记荣誉")
	check_eq(sys.hall_size(hall), 1, "高声望奖项自动入名人堂")
	var eff: Dictionary = sys.honor_effects(c)
	check(float(eff["fame"]) > 0.0, "荣誉提升声望")
	check(float(eff["career_opportunity"]) > 0.0, "荣誉带来职业机会")
	check((eff["privileges"] as Array).has("research_grant"), "解锁学术特权")
	# 成就不足不发奖。
	var low: Dictionary = sys.new_candidate("c2", {"achievement": 30.0})
	var r2: Dictionary = sys.award(low, "academic_prize", {}, {})
	check(not bool(r2["awarded"]) and str(r2["reason"]) == "below_threshold", "成就不足不发奖")
	# 评审未过不发奖。
	var mid: Dictionary = sys.new_candidate("c3", {"achievement": 70.0})
	var r3: Dictionary = sys.award(mid, "academic_prize", {"id": "j1", "peer_review": 0.0}, {})
	check(not bool(r3["awarded"]) and str(r3["reason"]) == "jury_rejected", "评审未过不发奖")


func _test_scandal_reveal_and_revoke() -> void:
	var sys = HonorsScript.new()
	var hall: Dictionary = sys.new_hall()
	var c: Dictionary = sys.new_candidate("c1", {"achievement": 75.0})
	# 无黑幕时评审不通过。
	var base: Dictionary = sys.evaluate(c, "academic_prize", {"id": "j1", "corruption": 0.0, "peer_review": 0.0}, {})
	check(not bool(base["passed"]), "原本评审不通过")
	# 买奖 + 评审腐败抬分通过。
	sys.mark_scandal(c, "bought_award", {"severity": 0.9})
	var rigged: Dictionary = sys.evaluate(c, "academic_prize", {"id": "j1", "corruption": 1.0, "peer_review": 0.0}, {})
	check(float(rigged["score"]) > float(base["score"]), "买奖在腐败评审下抬分")
	check(bool(rigged["passed"]), "买奖使其通过")
	var r: Dictionary = sys.award(c, "academic_prize", {"id": "j1", "corruption": 1.0, "peer_review": 0.0}, {"hall": hall})
	check(bool(r["awarded"]), "买奖颁奖成功")
	check_eq(sys.hall_size(hall), 1, "入名人堂")
	var rep_before: float = float(c["reputation"])
	var exp: Dictionary = sys.expose_scandal(c, {"hall": hall})
	check(bool(exp["exposed"]), "黑幕被揭露")
	check(float(c["reputation"]) <= rep_before, "揭露后声望下降")
	check_eq((c["honors"] as Array).size(), 0, "荣誉被撤销")
	var entries: Array = sys.hall_entries_of(hall, "c1")
	check_eq((entries as Array).size(), 1, "名人堂记录保留")
	check_eq(str((entries[0] as Dictionary)["status"]), "revoked", "名人堂记录被撤销")
	check(not bool(sys.expose_scandal(c, {})["exposed"]), "无更多可曝光黑幕")
	# 学术造假曝光后评审扣分。
	var c2: Dictionary = sys.new_candidate("c2", {"achievement": 85.0})
	sys.mark_scandal(c2, "academic_fraud", {"severity": 1.0})
	var before: Dictionary = sys.evaluate(c2, "academic_prize", {"id": "j1", "peer_review": 0.5}, {})
	sys.expose_scandal(c2, {})
	var after: Dictionary = sys.evaluate(c2, "academic_prize", {"id": "j1", "peer_review": 0.5}, {})
	check(float(after["score"]) < float(before["score"]), "造假曝光后评审扣分")


func _test_hall_and_inheritance() -> void:
	var sys = HonorsScript.new()
	var hall: Dictionary = sys.new_hall()
	var a: Dictionary = sys.new_candidate("a", {"achievement": 90.0})
	sys.award(a, "academic_prize", {"id": "j"}, {"hall": hall, "generation": 0})
	var b: Dictionary = sys.new_candidate("b", {"achievement": 90.0})
	sys.award(b, "military_honor", {"id": "j"}, {"hall": hall, "generation": 0})
	check_eq(sys.hall_size(hall), 2, "两条名人堂记录")
	check_eq((sys.hall_entries_of(hall, "a") as Array).size(), 1, "按人查询名人堂")
	var inh: Dictionary = sys.inherit_evaluation(hall, {})
	check(float(inh["heritage_score"]) > 0.0, "传承评分")
	check(float(inh["start_reputation"]) > 0.0, "后代起点声望")
	check_eq(int(inh["active_honors"]), 2, "统计生效荣誉")
	var inh0: Dictionary = sys.inherit_evaluation(hall, {"generation": 0})
	check_eq(int(inh0["active_honors"]), 2, "第一代统计")


func _test_tie_and_politics() -> void:
	var sys = HonorsScript.new()
	var tied: Dictionary = sys.resolve_tie([
		{"id": "x", "score": 0.80}, {"id": "y", "score": 0.805}, {"id": "z", "score": 0.5},
	], {})
	check(bool(tied["tie"]), "识别并列")
	check_eq((tied["tied"] as Array).size(), 2, "两人并列")
	var unique: Dictionary = sys.resolve_tie([
		{"id": "x", "score": 0.9}, {"id": "y", "score": 0.5},
	], {})
	check(not bool(unique["tie"]) and str(unique["winner"]) == "x", "非并列取最高")
	# 奖项政治化压低评审。
	var c: Dictionary = sys.new_candidate("c", {"achievement": 90.0, "relations": 1.0})
	var p0: Dictionary = sys.evaluate(c, "academic_prize", {"id": "j", "peer_review": 1.0}, {"political_pressure": 0.0})
	var p1: Dictionary = sys.evaluate(c, "academic_prize", {"id": "j", "peer_review": 1.0}, {"political_pressure": 1.0})
	check(float(p1["score"]) < float(p0["score"]), "政治化压低评审得分")
