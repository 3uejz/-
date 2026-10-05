extends "res://tests/test_base.gd"
## 证件与权利测试（任务 20；R24；design D13）。

const DocScript = preload("res://sim/documents.gd")

const YEAR: int = DocScript.MINUTES_PER_YEAR


func _suite_name() -> String:
	return "documents"


func run_tests() -> void:
	_test_catalog()
	_test_issue_and_validate()
	_test_expiry_photo()
	_test_serialize()


func _test_catalog() -> void:
	var sys = DocScript.new()
	check_eq(sys.doc_types().size(), 7, "七类证件")
	for key in ["id_card", "household", "driver_license", "passport", "visa", "property_cert", "business_license"]:
		check(DocScript.DOCUMENTS.has(key), "覆盖证件 %s" % key)


func _test_issue_and_validate() -> void:
	var sys = DocScript.new()
	var reg: Dictionary = sys.new_registry("CN")
	var v0: Dictionary = sys.validate(reg, "open_bank_account", 0)
	check(not bool(v0["ok"]), "无证不可开户")
	check(v0["missing"].has("id_card"), "缺身份证")
	check((v0["guidance"][0] as Dictionary).has("authority"), "给出办理途径")
	check(not bool(sys.issue(reg, "household", 0)["ok"]), "无身份证不能办户口")
	check(bool(sys.issue(reg, "id_card", 0)["ok"]), "办身份证")
	check(sys.has(reg, "id_card", 0), "持有身份证")
	check(bool(sys.issue(reg, "household", 0)["ok"]), "办户口")
	check(bool(sys.issue(reg, "driver_license", 0)["ok"]), "办驾照")
	check(bool(sys.issue(reg, "passport", 0)["ok"]), "办护照")
	check(bool(sys.issue(reg, "visa", 0)["ok"]), "办签证")
	check(bool(sys.validate(reg, "travel_abroad", 0)["ok"]), "可出国")
	check(bool(sys.validate(reg, "buy_house", 0)["ok"]), "可购房")
	check(bool(sys.validate(reg, "drive", 0)["ok"]), "可驾车")


func _test_expiry_photo() -> void:
	var sys = DocScript.new()
	var reg: Dictionary = sys.new_registry("CN")
	sys.issue(reg, "id_card", 0)
	check(sys.has(reg, "id_card", 9 * YEAR), "9 年内有效")
	check(not sys.has(reg, "id_card", 11 * YEAR), "11 年过期")
	sys.renew(reg, "id_card", 11 * YEAR)
	check(sys.has(reg, "id_card", 11 * YEAR + 1), "续办有效")
	var m1: Dictionary = sys.photo_match(reg, "id_card", 0.6)
	check(not bool(m1["match"]), "整容后人像不符")
	check(bool(m1["needs_reissue"]), "需重办")
	check(bool(sys.photo_match(reg, "id_card", 0.9)["match"]), "相似则匹配")


func _test_serialize() -> void:
	var sys = DocScript.new()
	var reg: Dictionary = sys.new_registry("US")
	sys.issue(reg, "id_card", 100)
	var data: Dictionary = sys.to_dict(reg)
	var back: Dictionary = sys.from_dict(data)
	check_eq(str(back["jurisdiction"]), "US", "法域保留")
	check(sys.has(back, "id_card", 100), "证件保留")
