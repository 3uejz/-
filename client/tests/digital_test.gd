extends "res://tests/test_base.gd"
## 数字生活与黑客测试（任务 30；R67；design D23）。
## 覆盖：黑客技能判定收益/暴露/法律后果、数字身份与数据泄露牵连、数字资产被盗与追回、
##       网络安全职业、电竞训练/赛事/伤病、内容平台结算与翻车掉粉、算法茧房与网络成瘾。

const DigitalScript = preload("res://sim/digital.gd")


func _suite_name() -> String:
	return "digital"


func run_tests() -> void:
	_test_identity_and_data_leak()
	_test_asset_theft_and_recovery()
	_test_security_jobs()
	_test_hacker_judgement()
	_test_esports()
	_test_content_platform()
	_test_algorithm_and_addiction()


func _test_identity_and_data_leak() -> void:
	var sys = DigitalScript.new()
	var idn: Dictionary = sys.new_identity("player")
	sys.verify_real_name(idn, true)
	check(bool(idn["real_name_verified"]), "实名认证写入")
	check(float(idn["privacy"]) < 0.5, "实名降低隐私")
	var acct: Dictionary = sys.create_account(idn, "short_video", {})
	check(bool(acct["ok"]), "创建平台账号")
	check(bool((idn["accounts"] as Dictionary).has("short_video")), "账号入账")
	sys.add_data(idn, "id_card", 1000.0, {"sensitivity": 0.5})
	sys.add_data(idn, "bank", 1000.0, {"sensitivity": 0.5})
	sys.add_contact(idn, "friend_a")
	sys.add_contact(idn, "friend_b")
	var leak: Dictionary = sys.leak_data(idn, {"sale_ratio": 0.3})
	check_eq(int(leak["leaked_count"]), 2, "数据全部泄露")
	check(int(leak["sale_price"]) > 0, "泄露数据被买卖计价")
	check_eq((leak["implicated"] as Array).size(), 2, "数据泄露牵连联系人")
	for d in (idn["data"] as Array):
		check(bool((d as Dictionary)["leaked"]), "逐条标记已泄露")


func _test_asset_theft_and_recovery() -> void:
	var sys = DigitalScript.new()
	var idn: Dictionary = sys.new_identity("player", {"privacy": 0.5})
	var asset: Dictionary = sys.add_asset(idn, "crypto_wallet", 100000, {})["asset"]
	var asset_id: String = str(asset["id"])
	check_eq(str(asset["type"]), "crypto_wallet", "记录加密钱包")
	var steal: Dictionary = sys.steal_asset(idn, asset_id, {"defense": 0.0, "roll": 0.0})
	check(bool(steal["success"]), "低防护下资产被盗")
	check(bool(asset["stolen"]), "资产标记失窃")
	var rec: Dictionary = sys.recover_asset(idn, asset_id, {"police": 1.0, "roll": 0.0})
	check(bool(rec["recovered"]), "高警力协助追回")
	check(not bool(asset["stolen"]), "追回后解除失窃")
	check(not bool(sys.steal_asset(idn, "asset.999", {})["ok"]), "未知资产被拒")


func _test_security_jobs() -> void:
	var sys = DigitalScript.new()
	check(not bool(sys.security_job("bogus", 10.0, {})["ok"]), "未知网安岗被拒")
	var job: Dictionary = sys.security_job("pentest", 18.0, {"roll": 0.0})
	check(bool(job["success"]), "高技能渗透测试成功")
	check(int(job["income"]) > 0, "网安职业有收入")
	check_near(float(job["legal_risk"]), 0.0, 1e-6, "合法方向无法律风险")
	var breach: Dictionary = sys.handle_breach({"severity": 0.8, "records_lost": 10000}, 18.0, {"roll": 0.0})
	check(bool(breach["contained"]), "高技能控制泄露")
	check(int(breach["records_affected"]) < 10000, "遏制减少受影响记录")


func _test_hacker_judgement() -> void:
	var sys = DigitalScript.new()
	check(not bool(sys.hack("bogus", 10.0, {})["ok"]), "未知目标被拒")
	# 高技能打低难度：成功且低暴露。
	var good: Dictionary = sys.hack("personal", 18.0, {"roll": 0.0, "exposure_roll": 0.99})
	check(bool(good["success"]), "高技能入侵个人成功")
	check(int(good["gain"]) > 0, "成功获得收益")
	check(not bool(good["exposed"]), "高技能低暴露")
	# 低技能打高难度：失败。
	var bad: Dictionary = sys.hack("government", 2.0, {"roll": 0.99, "exposure_roll": 0.99})
	check(not bool(bad["success"]), "低技能打政府失败")
	check_eq(int(bad["gain"]), 0, "失败无收益")
	# 被暴露触发法律后果。
	var caught: Dictionary = sys.hack("government", 18.0, {"roll": 0.0, "exposure_roll": 0.0})
	check(bool(caught["exposed"]), "暴露判定命中")
	var legal: Dictionary = caught["legal_consequence"]
	check(bool(legal["criminal_record"]), "暴露留案底")
	check(int(legal["wanted_level"]) > 0, "暴露触发通缉")
	check(int(legal["fine"]) > 0, "暴露附带罚金")


func _test_esports() -> void:
	var sys = DigitalScript.new()
	var career: Dictionary = sys.new_esports_career({"skill": 10.0, "fitness": 1.0})
	var tr: Dictionary = sys.train(career, 20.0, {})
	check(float(tr["skill"]) > 10.0, "训练提升技能")
	check(float(tr["fatigue"]) > 0.0, "训练累积疲劳")
	sys.join_team(career, "战队A", {})
	var match: Dictionary = sys.play_match(career, {"prize": 100000, "roll": 0.0})
	check(bool(match["win"]), "强制胜出")
	check(int(career["prize_total"]) > 0, "赛事奖金入账")
	var tf: Dictionary = sys.transfer(career, "战队B", 500000, {})
	check_eq(str(tf["to"]), "战队B", "转会成功")
	check_eq(str(career["team"]), "战队B", "球队更新")
	# 伤病：低体能 + 高疲劳提高受伤概率。
	var fragile: Dictionary = sys.new_esports_career({"skill": 10.0, "fitness": 0.3, "fatigue": 0.5})
	var inj: Dictionary = sys.career_injury(fragile, {"roll": 0.0, "severity": 1.0})
	check(bool(inj["injured"]), "低体能触发伤病")
	check(float(fragile["fitness"]) < 0.3, "伤病损耗体能")
	check_eq((fragile["injuries"] as Array).size(), 1, "记录伤病史")


func _test_content_platform() -> void:
	var sys = DigitalScript.new()
	var creator: Dictionary = sys.new_creator("star", "short_video", {"fans": 100000})
	var pub: Dictionary = sys.publish_content(creator, {"virality_roll": 0.5, "delivery": true, "unit_price": 100.0}, null)
	check(int(pub["views"]) > 0, "发布获得播放")
	check(int(pub["tips"]) > 0, "获得打赏")
	check(int(pub["platform_cut"]) > 0, "平台分成")
	check(int(pub["delivery_gmv"]) > 0, "带货产生 GMV")
	check(int(creator["fans"]) > 100000, "涨粉")
	# 翻车掉粉与处罚。
	var sc: Dictionary = sys.scandal(creator, 1.0, {"roll": 0.0, "max_penalty": 500000})
	check(int(sc["fan_loss"]) > 0, "翻车掉粉")
	check(int(creator["fans"]) < 100000, "粉丝数下降")
	check(float(sc["reputation_delta"]) < 0.0, "声誉受损")
	check(int(sc["penalty"]) > 0, "违规处罚")
	check(not bool(creator["banned"]), "首次违规未封号")
	# 累计违规触发封号。
	sys.scandal(creator, 1.0, {"roll": 0.0})
	var ban: Dictionary = sys.scandal(creator, 1.0, {"roll": 0.0, "ban_threshold": 3})
	check(bool(ban["banned"]), "累计违规触发封号")
	check(not bool(sys.publish_content(creator, {})["ok"]), "封号后不可发布")


func _test_algorithm_and_addiction() -> void:
	var sys = DigitalScript.new()
	var feed: Dictionary = sys.algorithm_feed(0.7, {"engagement": 1.0, "diversity": 0.0, "bias": 0.5})
	check(float(feed["filter_bubble"]) > 0.0, "算法推荐形成信息茧房")
	check(float(feed["cognition_delta"]) < 0.0, "茧房收窄认知")
	check(float(feed["opinion_shift"]) > 0.0, "茧房放大舆论偏移")
	var add: Dictionary = sys.internet_addiction(10.0, {"dependence": 1.0})
	check(float(add["addiction"]) > 0.0, "长时间上网形成成瘾")
	check(float(add["health_delta"]) < 0.0, "成瘾损害健康")
	check(float(add["social_delta"]) < 0.0, "成瘾影响社交")
