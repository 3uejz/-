extends "res://tests/test_base.gd"
## 声誉与分层传闻测试（任务 12；R21；design D10）。
## 覆盖：三条声誉线增减与夹取、机会解锁、恶名阈值、传闻时延/扩散/失真、
##       分层升级结算、失真文本。

const RepScript = preload("res://sim/reputation.gd")

func _suite_name() -> String:
	return "reputation"

func run_tests() -> void:
	_test_reputation_lines()
	_test_act_clamp()
	_test_unlocks()
	_test_infamy_thresholds()
	_test_rumor_creation()
	_test_rumor_delay_and_spread()
	_test_tier_and_effects()
	_test_distortion()


func _test_reputation_lines() -> void:
	var sys = RepScript.new()
	var owner := {}
	var r: Dictionary = sys.ensure(owner)
	check_near(float(r["fame"]), 0.0, 0.0001, "初始名望 0")
	var d: Dictionary = sys.record_act(owner, "charity")
	check(bool(d["ok"]), "善行成功")
	check_near(float(sys.get_reputation(owner)["fame"]), 3.0, 0.0001, "善行名望 +3")
	check_near(float(sys.get_reputation(owner)["status"]), 1.0, 0.0001, "善行地位 +1")
	sys.record_act(owner, "career_advance")
	check_near(float(sys.get_reputation(owner)["status"]), 5.0, 0.0001, "晋升地位 +4")
	check(not bool(sys.record_act(owner, "nope")["ok"]), "未知行为返回 false")


func _test_act_clamp() -> void:
	var sys = RepScript.new()
	var owner := {}
	# 犯罪：地位已为 0，减 2 被夹到 0。
	var d: Dictionary = sys.record_act(owner, "crime")
	check_near(float(d["deltas"]["status"]), 0.0, 0.0001, "地位不会为负")
	check_near(float(sys.get_reputation(owner)["infamy"]), 5.0, 0.0001, "犯罪恶名 +5")
	# 反复英雄行为名望夹到 100。
	for _i in 20:
		sys.record_act(owner, "heroic")
	check_near(float(sys.get_reputation(owner)["fame"]), 100.0, 0.0001, "名望夹到上限 100")


func _test_unlocks() -> void:
	var sys = RepScript.new()
	var owner := {}
	var r: Dictionary = sys.ensure(owner)
	r["fame"] = 55.0
	r["status"] = 60.0
	var out: Array = sys.unlock_opportunities(owner)
	check(out.has("media_interview"), "名望 55 解锁媒体采访")
	check(not out.has("invite_elite"), "名望 55 未解锁精英邀请")
	check(out.has("guild_master"), "地位 60 解锁行会会长")
	r["fame"] = 85.0
	r["status"] = 75.0
	var out2: Array = sys.unlock_opportunities(owner)
	check(out2.has("public_office"), "名望 85 解锁公职")
	check(out2.has("board_seat"), "地位 75 解锁董事席")


func _test_infamy_thresholds() -> void:
	var sys = RepScript.new()
	var owner := {}
	check(not sys.hostile(owner), "初始无敌意")
	check(not sys.refuses_service(owner), "初始不拒服务")
	var r: Dictionary = sys.ensure(owner)
	r["infamy"] = 40.0
	check(sys.hostile(owner), "恶名 40 触发敌意")
	check(not sys.refuses_service(owner), "恶名 40 尚未拒服务")
	r["infamy"] = 60.0
	check(sys.refuses_service(owner), "恶名 60 触发拒服务")


func _test_rumor_creation() -> void:
	var sys = RepScript.new()
	var rumor: Dictionary = sys.create_rumor("p", "他做了件大事", {"valence": 0.8, "credibility": 0.7, "minute": 100})
	check_eq(str(rumor["subject_id"]), "p", "主体")
	check_near(float(rumor["credibility"]), 0.7, 0.0001, "可信度")
	check_eq(str(rumor["tier"]), "circle", "初始为圈层")
	check_eq(sys.rumor_count(), 1, "传闻计数")
	check_eq(sys.rumors_about("p").size(), 1, "按主体查询")
	check_eq(sys.rumors_about("q").size(), 0, "无关者无传闻")


func _test_rumor_delay_and_spread() -> void:
	var sys = RepScript.new()
	var rumor: Dictionary = sys.create_rumor("p", "content", {"valence": 1.0, "credibility": 1.0, "minute": 0})
	# 时延内（<0.5 天）不扩散。
	sys.propagate(rumor, 600)
	check_near(float(rumor["reach"]), 0.0, 0.0001, "延迟内不扩散")
	# 一天后开始扩散。
	sys.propagate(rumor, 1440)
	check(float(rumor["reach"]) > 0.0, "越过时延后扩散")
	var reach1: float = float(rumor["reach"])
	sys.propagate(rumor, 3 * 1440)
	check(float(rumor["reach"]) > reach1, "扩散随时间增长")
	check(float(rumor["reach"]) <= 1.0, "扩散不超过 1")
	check(float(rumor["credibility"]) < 1.0, "可信度衰减")


func _test_tier_and_effects() -> void:
	var sys = RepScript.new()
	check_eq(sys.tier_of(0.1), "circle", "低 reach 圈层")
	check_eq(sys.tier_of(0.5), "region", "中 reach 区域")
	check_eq(sys.tier_of(0.9), "public", "高 reach 公众")

	var rumor: Dictionary = sys.create_rumor("p", "好事", {"valence": 1.0})
	rumor["tier"] = "region"
	var owner := {}
	sys.apply_rumor_effect(owner, rumor)
	check_near(float(sys.get_reputation(owner)["fame"]), 4.0, 0.0001, "区域级正向传闻名望 +4")
	check_near(float(sys.get_reputation(owner)["status"]), 2.0, 0.0001, "区域级正向传闻地位 +2")
	# 同层重复不重复结算。
	check(sys.apply_rumor_effect(owner, rumor).is_empty(), "同层不重复结算")
	# 升级到公众再结算。
	rumor["tier"] = "public"
	sys.apply_rumor_effect(owner, rumor)
	check_near(float(sys.get_reputation(owner)["fame"]), 6.0, 0.0001, "升公众再 +2")

	# 负向传闻计入恶名。
	var bad: Dictionary = sys.create_rumor("q", "坏事", {"valence": -1.0})
	bad["tier"] = "public"
	var owner2 := {}
	sys.apply_rumor_effect(owner2, bad)
	check_near(float(sys.get_reputation(owner2)["infamy"]), 6.0, 0.0001, "公众级负向传闻恶名 +6")


func _test_distortion() -> void:
	var sys = RepScript.new()
	var rumor: Dictionary = sys.create_rumor("p", "原文", {})
	rumor["distortion"] = 0.1
	check_eq(sys.distorted_content(rumor), "原文", "低失真保持原文")
	rumor["distortion"] = 0.5
	check(sys.distorted_content(rumor).contains("不太一样"), "中度失真")
	rumor["distortion"] = 0.9
	check(sys.distorted_content(rumor).contains("面目全非"), "高度失真")
