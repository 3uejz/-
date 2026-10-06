extends "res://tests/test_base.gd"
## 知识产权与媒体工业测试（任务 30；R69；design D25）。
## 覆盖：IP 登记/授权/许可费/转让/质押、版权到期公有领域、
##       侵权监测、侵权诉讼胜率与赔偿/禁令、媒体作品发行、负面舆论与危机公关/撤稿、
##       内容审查与合规、抢注/恶意诉讼/抄袭/造谣等边界。

const IpMediaScript = preload("res://sim/ip_media.gd")


func _suite_name() -> String:
	return "ip_media"


func run_tests() -> void:
	_test_register_license_transfer()
	_test_expiry_public_domain()
	_test_infringement_lawsuit()
	_test_media_release()
	_test_opinion_and_pr()
	_test_moderation_and_compliance()
	_test_boundary_cases()


func _test_register_license_transfer() -> void:
	var sys = IpMediaScript.new()
	check(not bool(sys.register_ip("bogus", "me", "x")["ok"]), "未知 IP 类型被拒")
	var reg: Dictionary = sys.register_ip("patent", "me", "一种电池", {})
	check(bool(reg["ok"]), "专利登记成功")
	var ip: Dictionary = reg["ip"]
	check_eq(str(ip["type"]), "patent", "记录 IP 类型")
	check_eq(str(ip["owner"]), "me", "记录权利人")
	check(int(ip["expiry_minute"]) > 0, "有限期 IP 有到期时间")
	# 许可费与授权。
	var fee: Dictionary = sys.license_fee(ip, 1000000.0, {})
	check(int(fee["fee"]) > 0, "许可费为正")
	var ex: Dictionary = sys.license_fee(ip, 1000000.0, {"exclusive": true})
	check(int(ex["fee"]) > int(fee["fee"]), "独占许可费率更高")
	var lic: Dictionary = sys.license_ip(ip, "厂A", 1000000.0, {})
	check(bool(lic["ok"]), "授权成功")
	check(int(lic["fee"]) > 0, "授权产生许可费")
	check_eq((ip["licenses"] as Array).size(), 1, "授权记录入账")
	# 转让与质押。
	var tf: Dictionary = sys.transfer_ip(ip, "买家B", 5000000)
	check_eq(str(ip["owner"]), "买家B", "转让变更权利人")
	check_eq(str(tf["from"]), "me", "记录转让人")
	var pl: Dictionary = sys.pledge_ip(ip, 3000000)
	check(bool(pl["pledged"]), "IP 可质押")
	check_eq(int(ip["pledge_amount"]), 3000000, "记录质押金额")


func _test_expiry_public_domain() -> void:
	var sys = IpMediaScript.new()
	var reg: Dictionary = sys.register_ip("copyright", "作者", "小说", {"created_minute": 0, "term_years": 1})
	var ip: Dictionary = reg["ip"]
	var one_year: int = IpMediaScript.MINUTES_PER_YEAR
	check(not bool(sys.expire_ip(ip, one_year - 1)["ok"]), "未到期不进入公有领域")
	var done: Dictionary = sys.expire_ip(ip, one_year + 1)
	check(bool(done["ok"]), "到期判定成功")
	check(bool(done["public_domain"]), "到期进入公有领域")
	check(bool(ip["public_domain"]), "IP 标记公有领域")
	var secret: Dictionary = sys.register_ip("trade_secret", "公司", "配方", {})["ip"]
	check_eq(str(sys.expire_ip(secret, 999999999)["reason"]), "perpetual", "商业秘密无期限")


func _test_infringement_lawsuit() -> void:
	var sys = IpMediaScript.new()
	var ip: Dictionary = sys.register_ip("patent", "me", "专利", {})["ip"]
	var mon: Dictionary = sys.monitor_infringement(ip, "侵权方", {"similarity": 0.9, "forensics": 0.8, "roll": 0.0})
	check(bool(mon["detected"]), "高相似度监测命中")
	check(float(mon["evidence_strength"]) > 0.0, "取证得到证据强度")
	var high: Dictionary = sys.file_lawsuit(ip, {"evidence": 1.0, "lawyer_skill": 1.0, "court_bias": 1.0, "roll": 0.99})
	var low: Dictionary = sys.file_lawsuit(ip, {"evidence": 0.0, "lawyer_skill": 0.0, "court_bias": 0.0, "roll": 0.99})
	check(float(high["probability"]) > float(low["probability"]), "证据/律师/法院提高胜率")
	var win: Dictionary = sys.file_lawsuit(ip, {"evidence": 1.0, "lawyer_skill": 1.0, "court_bias": 1.0, "roll": 0.0})
	check(bool(win["win"]), "高胜率下胜诉")
	check(int(win["compensation"]) > 0, "胜诉获得赔偿")
	check(bool(win["injunction"]), "胜诉获得禁令")
	var lose: Dictionary = sys.file_lawsuit(ip, {"evidence": 0.0, "lawyer_skill": 0.0, "court_bias": 0.0, "roll": 0.99})
	check(not bool(lose["win"]), "低证据败诉")
	check_eq(int(lose["compensation"]), 0, "败诉无赔偿")
	check(not bool(lose["injunction"]), "败诉无禁令")
	# 主动维权组合入口。
	var enf: Dictionary = sys.enforce_ip(ip, "侵权方", {"similarity": 0.9, "forensics": 1.0, "evidence": 1.0, "lawyer_skill": 1.0, "court_bias": 1.0, "roll": 0.0})
	check_eq(str(enf["action"]), "lawsuit", "监测命中后主动诉讼")


func _test_media_release() -> void:
	var sys = IpMediaScript.new()
	check(not bool(sys.new_media_outlet("bogus", {})["ok"]), "未知媒体类型被拒")
	var created: Dictionary = sys.new_media_outlet("film_company", {"name": "光影", "reputation": 0.5})
	check(bool(created["ok"]), "建立影视公司")
	var outlet: Dictionary = created["outlet"]
	var rel: Dictionary = sys.release_work(outlet, {"title": "大片", "quality": 1.0}, {"hype": 1.0, "roll": 0.0, "scale": 10000000.0})
	check(int(rel["revenue"]) > 0, "发行产生收入")
	check(int(rel["box_office"]) > 0, "影视公司计票房")
	check(int(outlet["cash"]) > 0, "收入入账")
	check((outlet["works"] as Array).size() == 1, "作品发行记录")
	check(float(rel["reputation_delta"]) > 0.0, "优质作品提升声誉")


func _test_opinion_and_pr() -> void:
	var sys = IpMediaScript.new()
	var outlet: Dictionary = sys.new_media_outlet("news_agency", {"reputation": 0.5})["outlet"]
	var rep: Dictionary = sys.negative_report(outlet, 1.0, {"credibility": 1.0})
	check(float(rep["reputation_delta"]) < 0.0, "负面报道打击声誉")
	check(bool(rep["crisis"]), "严重负面触发声誉危机")
	check(float(outlet["reputation"]) < 0.5, "声誉下降")
	var pr: Dictionary = sys.crisis_pr(outlet, "apologize", {"budget": 0.0, "roll": 0.0})
	check(bool(pr["success"]), "危机公关成功")
	check(float(pr["reputation_delta"]) > 0.0, "公关修复声誉")
	check(float(outlet["reputation"]) > 0.0, "声誉回升")
	var art: Dictionary = sys.publish_article(outlet, "失实报道", {})["article"]
	var rt: Dictionary = sys.retract(outlet, str(art["id"]), {})
	check(bool(rt["retracted"]), "撤稿成功")
	check(not bool(sys.retract(outlet, str(art["id"]), {})["ok"]), "重复撤稿被拒")


func _test_moderation_and_compliance() -> void:
	var sys = IpMediaScript.new()
	var pass_c: Dictionary = sys.moderate_content("日常分享", {"risk": 0.1, "policy_strictness": 0.2})
	check(bool(pass_c["approved"]), "低风险内容过审")
	var rej: Dictionary = sys.moderate_content("敏感内容", {"risk": 0.9, "policy_strictness": 0.8})
	check(not bool(rej["approved"]), "高风险内容被拒")
	check_eq(str(rej["reason"]), "content_violation", "违规理由")
	var td: Dictionary = sys.moderate_content("盗版影视", {"copyright_infringement": true})
	check_eq(str(td["action"]), "takedown", "版权侵权下架")
	var ip: Dictionary = sys.register_ip("copyright", "作者", "作品", {})["ip"]
	check(bool(sys.copyright_takedown("盗版", ip)["ok"]), "版权下架成功")


func _test_boundary_cases() -> void:
	var sys = IpMediaScript.new()
	# 抢注。
	var squat: Dictionary = sys.trademark_squatting("老字号", "抢注者", {"prior_use": 0.9})
	check(bool(squat["squatting"]), "识别商标抢注")
	check(bool(squat["challenge_wins"]), "高先使用证据可挑战成功")
	# 恶意诉讼。
	var mal: Dictionary = sys.malicious_lawsuit("被告", {"plaintiff_evidence": 0.1, "roll": 0.99, "damage_base": 500000.0})
	check(bool(mal["malicious"]), "识别恶意诉讼")
	check(int(mal["defendant_damages"]) > 0, "恶意诉讼承担赔偿")
	# 抄袭。
	var work: Dictionary = {"title": "作品"}
	var plag: Dictionary = sys.plagiarism_exposed(work, {"severity": 0.8, "damage_base": 1000000.0})
	check(bool(plag["plagiarized"]), "抄袭被揭露")
	check(float(plag["reputation_delta"]) < 0.0, "抄袭损害声誉")
	check(int(plag["damages"]) > 0, "抄袭触发赔偿")
	# 媒体造谣担责。
	var outlet: Dictionary = sys.new_media_outlet("platform", {"reputation": 0.5})["outlet"]
	var def: Dictionary = sys.defamation_liability(outlet, {"proven_false": true, "severity": 0.6})
	check(bool(def["liable"]), "造谣被证伪需担责")
	check(int(def["fine"]) > 0, "造谣承担罚金")
	check(not bool(sys.defamation_liability(outlet, {"proven_false": false})["liable"]), "报道属实不担责")
