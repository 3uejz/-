extends "res://tests/test_base.gd"
## 恋爱婚姻离婚与繁衍测试（任务 18；R19；design D11）。

const FamilyScript = preload("res://sim/family.gd")


class FixedRng:
	var seq: Array
	var i: int = 0
	func _init(s: Array) -> void:
		seq = s
	func next_float() -> float:
		var v: float = float(seq[i % seq.size()])
		i += 1
		return v


func _suite_name() -> String:
	return "family"


func run_tests() -> void:
	_test_confess()
	_test_marriage()
	_test_divorce()
	_test_birth()
	_test_npc_and_expense()


func _test_confess() -> void:
	var sys = FamilyScript.new(1)
	var good: Dictionary = sys.confess(80.0, 80.0, 80.0, 80.0, FixedRng.new([0.0]))
	check(bool(good["success"]), "高条件表白成功")
	check(float(good["probability"]) > 0.5, "高概率")
	var bad: Dictionary = sys.confess(-50.0, 10.0, 10.0, 10.0, FixedRng.new([0.99]))
	check(not bool(bad["success"]), "低条件表白失败")
	check(float(bad["probability"]) < 0.5, "低概率")


func _test_marriage() -> void:
	var sys = FamilyScript.new(1)
	check(sys.can_marry(80.0, 80.0), "达标可婚")
	check(not sys.can_marry(50.0, 50.0), "未达标不可婚")
	check(not bool(sys.propose(50.0, 50.0, 80.0)["ok"]), "未达标求婚被拒")
	check(bool(sys.propose(80.0, 80.0, 60.0, FixedRng.new([0.0]))["success"]), "达标求婚成功")
	var r: Dictionary = sys.marry({"id": "npc1", "name": "阿珍"})
	check(bool(r["ok"]), "结婚成功")
	check_eq(str(sys.state()["spouse"]["id"]), "npc1", "配偶入册")
	sys.cohabit()
	check(bool(sys.state()["cohabiting"]), "同居")


func _test_divorce() -> void:
	var sys = FamilyScript.new(1)
	sys.marry({"id": "npc1"})
	sys.state()["estate"] = 100000
	sys.state()["mood"] = 60.0
	var r: Dictionary = sys.divorce()
	check(int(r["split"]) == 50000, "财产平分")
	check(int(sys.state()["estate"]) == 50000, "己方保留一半")
	check(float(sys.state()["mood"]) < 60.0, "离婚降低心情")
	check(not bool(sys.state()["married"]), "解除婚约")


func _test_birth() -> void:
	var sys = FamilyScript.new(3)
	var parent: Dictionary = {"intelligence": 80.0, "charm": 60.0}
	var spouse: Dictionary = {"intelligence": 60.0, "charm": 40.0}
	var child: Dictionary = sys.give_birth(parent, spouse, "小明", "male")
	check_eq(str(child["name"]), "小明", "子女姓名")
	check_eq(str(child["stage"]), "infant", "初始婴儿")
	# 基因 50%：intelligence 基线 = (80+60)/4 + 25 = 60，噪声 ±10。
	check(float(child["ability"]["intelligence"]) >= 45.0 and float(child["ability"]["intelligence"]) <= 75.0, "智力遗传")
	check(child["personality"].has("openness"), "人格遗传")
	check_eq(sys.children().size(), 1, "子女入册")
	sys.grow_children(13)
	check_eq(str(sys.children()[0]["stage"]), "teen", "随时钟成长")


func _test_npc_and_expense() -> void:
	var sys = FamilyScript.new(5)
	var flow: Dictionary = sys.npc_auto_family(100, FixedRng.new([0.0]))
	check(int(flow["marriages"]) > 0, "NPC 自发结婚")
	check(int(flow["births"]) > 0, "NPC 自发生育")
	sys.add_elder({"id": "e1"})
	sys.children().append({"name": "c"})
	check_eq(sys.daily_expense(), FamilyScript.CHILD_DAILY_EXPENSE + FamilyScript.ELDER_DAILY_EXPENSE, "家庭日开销")
