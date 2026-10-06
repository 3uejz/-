extends "res://tests/test_base.gd"
## 文娱内容产业测试（任务 38；R90；design D46）。
## 覆盖：工作室与团队、作品创作与项目管理、发行变现、IP 运营、抄袭/违规/翻车下架、
## 融资与爆款扑街、挖角、版号延误与饭圈。

const ContentScript = preload("res://sim/content_industry.gd")
const RngScript = preload("res://sim/rng.gd")


func _suite_name() -> String:
	return "content_industry"


func run_tests() -> void:
	_test_studio_and_team()
	_test_create_and_advance()
	_test_release_and_monetize()
	_test_ip_operations()
	_test_risks_and_takedown()
	_test_business_and_boundaries()


func _test_studio_and_team() -> void:
	var sys = ContentScript.new()
	var studio: Dictionary = sys.new_studio({"name": "星火", "money": 5000000})
	check_eq(str(studio["name"]), "星火", "工作室命名")
	var h1: Dictionary = sys.hire(studio, "engineering", 2, {"skill": 0.9})
	check(bool(h1["ok"]), "雇佣程序成功")
	check_eq(int(h1["count"]), 2, "雇佣人数记录")
	var h2: Dictionary = sys.hire(studio, "art", 1, {"skill": 0.7})
	check(bool(h2["ok"]), "雇佣美术成功")
	check(float(sys.team_skill(studio, "game")) > 0.0, "团队游戏技能为正")
	# 资金不足被拒。
	var poor: Dictionary = sys.new_studio({"money": 0})
	check(not bool(sys.hire(poor, "producer", 1)["ok"]), "资金不足无法雇佣")
	check(not bool(sys.hire(studio, "bogus", 1)["ok"]), "未知角色被拒")
	# 离职。
	var f: Dictionary = sys.fire(studio, "art", 1)
	check_eq(int(f["count"]), 0, "解雇后人数归零")


func _test_create_and_advance() -> void:
	var sys = ContentScript.new()
	var pro: Dictionary = sys.new_studio({"money": 10000000})
	for role in ["producer", "design", "art", "engineering", "audio"]:
		sys.hire(pro, role, 1, {"skill": 1.0})
	var noob: Dictionary = sys.new_studio({"money": 10000000})
	var w_pro: Dictionary = sys.new_work("w1", "game", {})["work"]
	var w_noob: Dictionary = sys.new_work("w2", "game", {})["work"]
	# 相同强制掷骰，团队强者质量更高。
	var r1: Dictionary = sys.advance_project(w_pro, pro, 500.0, {"roll": 0.9})
	var r2: Dictionary = sys.advance_project(w_noob, noob, 500.0, {"roll": 0.9})
	check(bool(r1["ready"]), "作品可开发完成")
	check(float(r1["quality"]) > float(r2["quality"]), "团队技能提升作品质量")
	# 项目管理提升速度与质量。
	var pm: Dictionary = sys.project_management(w_noob, {"management": 1.0})
	check(float(pm["speed_mult"]) > 1.0, "项目管理提升速度")
	check(float(pm["quality_bonus"]) > 0.0, "项目管理提升质量")
	# 不同内容类型。
	var film: Dictionary = sys.new_work("f1", "film", {"title": "长夜"})["work"]
	check_eq(str(film["type"]), "film", "立项影视作品")
	check(not bool(sys.new_work("x", "bogus")["ok"]), "未知内容类型被拒")


func _test_release_and_monetize() -> void:
	var sys = ContentScript.new()
	var studio: Dictionary = sys.new_studio({"money": 10000000})
	var work: Dictionary = sys.new_work("g1", "game", {})["work"]
	sys.advance_project(work, studio, 500.0, {"roll": 1.0})
	work["quality"] = 0.9
	var rel: Dictionary = sys.release_work(studio, work, {"roll": 1.0, "hype": 0.9, "hit_threshold": 0.6})
	check(bool(rel["hit"]), "高表现判定爆款")
	check(float(rel["reputation_delta"]) > 0.0, "爆款提升声誉")
	check(bool(work["released"]), "发行后标记已发行")
	# 渠道变现：平台分成。
	var m1: Dictionary = sys.monetize(work, "platform_share", {"reach": 1000000, "arpu": 10.0})
	check(int(m1["revenue"]) > 0, "平台分成产生收入")
	# 平台抽成降低到手收入。
	var no_cut: Dictionary = sys.monetize(work, "platform_share", {"reach": 1000000, "arpu": 10.0})
	var with_cut: Dictionary = sys.monetize(work, "platform_share", {"reach": 1000000, "arpu": 10.0, "platform": "appstore"})
	check(int(with_cut["revenue"]) < int(no_cut["revenue"]), "平台抽成降低收入")
	# 票务仅适用影视/综艺/音乐。
	var film: Dictionary = sys.new_work("f2", "film", {})["work"]
	film["quality"] = 0.8
	var tick: Dictionary = sys.monetize(film, "ticketing", {"audience": 100000, "ticket_price": 40.0})
	check(int(tick["revenue"]) > 0, "票务变现")
	check(not bool(sys.monetize(work, "ticketing", {})["ok"]), "游戏不适用票务渠道")
	check(not bool(sys.monetize(work, "bogus", {})["ok"]), "未知渠道被拒")


func _test_ip_operations() -> void:
	var sys = ContentScript.new()
	var studio: Dictionary = sys.new_studio({"money": 10000000})
	var work: Dictionary = sys.new_work("g1", "game", {})["work"]
	work["quality"] = 0.8
	var reg: Dictionary = sys.register_ip(studio, work, {"universe": "星海"})
	check(bool(reg["ok"]), "IP 登记成功")
	var ip: Dictionary = reg["ip"]
	check_eq(str(work["ip_id"]), str(ip["id"]), "作品关联 IP")
	check((studio["ip_library"] as Dictionary).has(str(ip["id"])), "IP 纳入工作室库")
	# 改编提升 IP 势能。
	var ad: Dictionary = sys.adapt(ip, "anime", {"fit": 0.9})
	check(bool(ad["ok"]), "IP 改编成功")
	check(float(ad["ip_power"]) >= 0.8, "改编提升 IP 势能")
	# 运营变现。
	var op: Dictionary = sys.operate_ip(ip, "merchandise", 10000000.0, {"roll": 1.0})
	check(int(op["revenue"]) > 0, "IP 周边变现")
	check(not bool(sys.operate_ip(ip, "bogus", 1.0)["ok"]), "未知运营方式被拒")
	# IP 宇宙：多 IP 联动加成。
	var work2: Dictionary = sys.new_work("g2", "game", {})["work"]
	work2["quality"] = 0.7
	var ip2: Dictionary = sys.register_ip(studio, work2, {})["ip"]
	var uni: Dictionary = sys.build_ip_universe([ip, ip2], {"universe": "星海宇宙"})
	check(bool(uni["universe"]), "多 IP 构建宇宙")
	check(float(uni["bonus"]) > 0.0, "IP 宇宙带来加成")
	var single: Dictionary = sys.build_ip_universe([ip], {})
	check(not bool(single["universe"]), "单 IP 不构成宇宙")


func _test_risks_and_takedown() -> void:
	var sys = ContentScript.new()
	var studio: Dictionary = sys.new_studio({"money": 10000000})
	var work: Dictionary = sys.new_work("g1", "game", {})["work"]
	# 抄袭检测：强制低掷骰被揭发。
	var pl: Dictionary = sys.plagiarism_check(work, {"similarity": 0.9, "detect_prob": 0.9, "roll": 0.0})
	check(bool(pl["exposed"]), "抄袭被揭发")
	check(bool(work["plagiarized"]), "作品标记抄袭")
	check(float(work["controversy"]) > 0.0, "抄袭引发争议")
	# 内容合规：高风险内容不通过。
	var bad: Dictionary = sys.content_compliance(work, {"risk": 0.9, "strictness": 0.8})
	check(not bool(bad["approved"]), "高风险内容不合规")
	check((work["violations"] as Array).size() > 0, "记录违规项")
	var good: Dictionary = sys.content_compliance(work, {"risk": 0.1, "strictness": 0.3})
	check(bool(good["approved"]), "低风险内容合规")
	# 下架：罚款、声誉与饭圈受损。
	var rep_before: float = float(studio["reputation"])
	var td: Dictionary = sys.take_down(studio, work, "content_violation", {"severity": 0.8})
	check(int(td["penalty"]) > 0, "下架产生罚款")
	check(float(studio["reputation"]) < rep_before, "下架打击声誉")
	check_eq(str(work["status"]), "taken_down", "作品状态为下架")
	# 翻车事件。
	var scan: Dictionary = sys.scandal_event(studio, {"severity": 0.9, "exposure": 0.9, "roll": 0.0})
	check(bool(scan["occurred"]), "翻车事件发生")
	check(float(scan["reputation_delta"]) < 0.0, "翻车打击声誉")


func _test_business_and_boundaries() -> void:
	var sys = ContentScript.new()
	var studio: Dictionary = sys.new_studio({"money": 1000000, "fandom_size": 100000})
	var before: int = int(studio["money"])
	# 融资。
	var fin: Dictionary = sys.raise_funding(studio, "seed", {"sentiment": 1.2, "equity_pct": 0.15})
	check(bool(fin["ok"]), "种子轮融资成功")
	check(int(studio["money"]) > before, "融资资金入账")
	check(int(fin["investment"]) > 0, "融资金额为正")
	# 爆款与扑街分类。
	check_eq(str(sys.hit_or_flop({}, 0.9)["label"]), "hit", "高表现判定爆款")
	check_eq(str(sys.hit_or_flop({}, 0.1)["label"]), "flop", "低表现判定扑街")
	# 挖角：高待遇 + 低忠诚必成。
	var rival: Dictionary = sys.new_studio({"money": 10000000})
	sys.hire(rival, "design", 1, {"skill": 0.8})
	var po: Dictionary = sys.poach_team(studio, rival, "design", {"offer_mult": 3.0, "target_loyalty": 0.1, "roll": 0.0})
	check(bool(po["success"]), "高待遇挖角成功")
	check_eq(int((rival["team"]["design"] as Dictionary)["count"]), 0, "对手团队流失")
	# 版号/审查延误。
	var delay: Dictionary = sys.approval_delay("game", {"base_days": 30.0, "strictness": 0.5, "roll": 0.5})
	check(float(delay["delay_days"]) > 0.0, "版号审查产生延误")
	var approved: Dictionary = sys.approval_delay("game", {"base_days": 30.0, "strictness": 0.4, "roll": 0.9})
	check(bool(approved["approved"]), "高掷骰获批")
	# 饭圈演化。
	var fan: Dictionary = sys.fandom_dynamics(studio, {"growth": 0.2, "roll": 0.5})
	check(int(fan["fandom_size"]) > 100000, "粉丝规模增长")
	check(float(fan["toxicity"]) > 0.0, "大规模粉丝产生毒性")
