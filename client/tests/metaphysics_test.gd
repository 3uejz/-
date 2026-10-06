extends "res://tests/test_base.gd"
## 玄学、命理与民俗信仰测试（任务 36；R87；design D43）。
## 核心断言：无真实能力者结果接近随机（概率约 0.5），且绝不改变属性与事件结果；
##           有真实能力者（D44）例外；民俗信仰只影响心情与社交；
##           经营存在投诉举报诈骗追责与人设翻车。

const MetaphysicsScript = preload("res://sim/metaphysics.gd")
const RngScript = preload("res://sim/rng.gd")


func _suite_name() -> String:
	return "metaphysics"


func run_tests() -> void:
	_test_tables()
	_test_fake_is_random_and_causality_neutral()
	_test_real_ability_exception()
	_test_placebo_only_mood()
	_test_business_and_fraud()
	_test_folk_belief()
	_test_boundaries()


func _test_tables() -> void:
	var sys = MetaphysicsScript.new()
	check_eq(sys.services().size(), 7, "七类玄学服务")
	check_eq(str(sys.service_def("fengshui")["name"]), "风水", "风水名称")
	check_eq(sys.modes().size(), 2, "线上/线下两种模式")
	check_eq(sys.folk_practices().size(), 4, "四类民俗信仰活动")


func _test_fake_is_random_and_causality_neutral() -> void:
	var sys = MetaphysicsScript.new()
	var prac: Dictionary = sys.new_practitioner("p1", {"skill": 1.0})
	# 单次成功与否随 roll 变化，但概率恒为 0.5，且不改变因果。
	var r1: Dictionary = sys.consult(prac, "fortune", {}, {"roll": 0.2})
	check(bool(r1["success"]), "低 roll 命中")
	check_near(float(r1["probability"]), 0.5, 1e-9, "无能力者成功率基准为 0.5")
	check(not bool(r1["reality_changed"]), "无能力者不改变现实")
	check(not bool(r1["attributes_changed"]), "无能力者不改变属性")
	check(not bool(r1["event_outcome_changed"]), "无能力者不改变事件结果")
	var r2: Dictionary = sys.consult(prac, "fengshui", {}, {"roll": 0.8})
	check(not bool(r2["success"]), "高 roll 未命中")
	check_near(float(r2["probability"]), 0.5, 1e-9, "成功率仍接近随机")
	# 大样本统计：成功率接近 0.5（确定性种子）。
	var rng = RngScript.new(20261006)
	var hits: int = 0
	var n: int = 600
	for i in n:
		var r: Dictionary = sys.consult(prac, "astrology", {}, {}, rng)
		if bool(r["success"]):
			hits += 1
	var ratio: float = float(hits) / float(n)
	check(ratio > 0.42 and ratio < 0.58, "无能力者成功率接近随机: %.3f" % ratio)


func _test_real_ability_exception() -> void:
	var sys = MetaphysicsScript.new()
	var real: Dictionary = sys.new_practitioner("p2", {"real_ability": true, "skill": 1.0})
	var r: Dictionary = sys.consult(real, "exorcism", {}, {"roll": 0.1, "event_related": true})
	check(float(r["probability"]) > 0.8, "真实能力者成功率显著提高")
	check(bool(r["success"]), "真实能力者成功")
	check(bool(r["reality_changed"]), "真实能力者可改变现实")
	check(bool(r["event_outcome_changed"]), "真实能力者可改变事件结果")
	check(not bool(r["attributes_changed"]), "即便真实能力也不直接改写属性字段")


func _test_placebo_only_mood() -> void:
	var sys = MetaphysicsScript.new()
	var prac: Dictionary = sys.new_practitioner("p3", {"scamming": true})
	var client: Dictionary = sys.new_client()
	var mood0: float = float(client["mood"])
	var r: Dictionary = sys.consult(prac, "luck_opening", client, {"roll": 0.1})
	check(bool(r["scam"]), "诈骗从业被标记")
	check(float(client["mood"]) > mood0, "安慰剂提升心情")
	var placebo: Dictionary = sys.apply_placebo(client, r, {})
	check(not bool(placebo["attributes_changed"]), "安慰剂不改变属性")
	check(not bool(placebo["event_outcome_changed"]), "安慰剂不改变事件结果")
	check(float(placebo["decision_bias"]) > 0.0, "确认偏误影响决策倾向")


func _test_business_and_fraud() -> void:
	var sys = MetaphysicsScript.new()
	var biz: Dictionary = sys.new_business("玄机阁", {})
	var op: Dictionary = sys.operate_business(biz, {"customers": 2, "fee": 20000, "roll": 0.0, "complaint_rate": 0.3})
	check(int(op["earned"]) == 40000, "营业入账")
	check(bool(op["complained"]), "低 roll 触发投诉")
	# 举报累计达阈值后追责。
	for i in 3:
		sys.file_complaint(biz, {"report": true})
	check_eq(int(biz["reports"]), 3, "累计三次举报")
	var fraud: Dictionary = sys.investigate_fraud(biz, {"roll": 0.0, "convict_rate": 0.7, "fine": 300000})
	check(bool(fraud["convicted"]) and int(fraud["fine"]) > 0, "诈骗被追责罚款")
	check(bool(biz["under_investigation"]), "立案调查")
	check(not bool(sys.investigate_fraud(sys.new_business("新店", {}), {})["ok"]), "举报不足不立案")
	# 人设翻车。
	var star: Dictionary = sys.new_business("大师阁", {"reputation": 0.9, "income": 100000})
	var before: float = float(star["reputation"])
	var fall: Dictionary = sys.master_fall(star, {"severity": 0.5})
	check(float(fall["reputation"]) < before, "大师人设翻车降声誉")
	check(int(fall["income_loss"]) > 0, "翻车造成业务损失")


func _test_folk_belief() -> void:
	var sys = MetaphysicsScript.new()
	var client: Dictionary = sys.new_client()
	var p: Dictionary = sys.use_folk_practice(client, "festival_ritual", {})
	check(bool(p["ok"]), "节日仪式可用")
	check(float(p["mood_delta"]) > 0.0 and float(p["social_delta"]) > 0.0, "仪式影响心情与社交")
	check(not bool(p["attributes_changed"]) and not bool(p["event_outcome_changed"]), "民俗不改变属性与事件")
	check(not bool(sys.use_folk_practice(client, "bogus", {})["ok"]), "未知民俗被拒")


func _test_boundaries() -> void:
	var sys = MetaphysicsScript.new()
	var org: Dictionary = sys.organized_superstition(800, {})
	check(float(org["influence"]) > 0.0 and float(org["risk"]) > 0.0, "组织化迷信有影响力与风险")
	var biz: Dictionary = sys.new_business("灰产阁", {})
	var coll: Dictionary = sys.collude_gray_market(biz, {"roll": 0.0, "exposure_risk": 0.3})
	check(bool(coll["entangled"]), "与灰产勾结")
	check(bool(coll["exposed"]) and bool(coll["criminal"]), "勾结被牵连追责")
	var fake: Dictionary = sys.new_practitioner("p4", {"scamming": true})
	var real: Dictionary = sys.new_practitioner("p5", {"real_ability": true})
	check(bool(sys.blur_real_and_fake(fake)["indistinguishable"]), "骗子与能力者外观不可区分")
	check(bool(sys.blur_real_and_fake(real)["indistinguishable"]), "真实能力者同样不可区分")
