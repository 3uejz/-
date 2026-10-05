extends "res://tests/test_base.gd"
## 育儿阶段、照护与成长测试（任务 18；R51.1–R51.4、R51.8；design D11）。

const ParentingScript = preload("res://sim/parenting.gd")


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
	return "parenting"


func run_tests() -> void:
	_test_stages()
	_test_care()
	_test_growth()
	_test_events_and_heir()


func _test_stages() -> void:
	var sys = ParentingScript.new()
	check_eq(sys.stage_of(1), "infant", "婴儿")
	check_eq(sys.stage_of(4), "toddler", "幼儿")
	check_eq(sys.stage_of(8), "child", "儿童")
	check_eq(sys.stage_of(15), "teen", "少年")
	check_eq(sys.stage_of(20), "adult", "成年")
	check_eq(str(ParentingScript.STAGE_NAMES["teen"]), "少年", "阶段名")
	var c: Dictionary = sys.daily_cost(1)
	check_eq(int(c["minutes"]), 300, "婴儿照护时间")
	check_eq(int(c["money"]), 15000, "婴儿照护费用")


func _test_care() -> void:
	var sys = ParentingScript.new()
	check_near(sys.care_investment(240.0, 15000.0, 100.0), 100.0, 1e-6, "满额照护")
	check_near(sys.care_investment(0.0, 0.0, 0.0), 0.0, 1e-6, "零照护")
	check(sys.care_investment(120.0, 7500.0, 50.0) < 100.0, "部分照护")


func _test_growth() -> void:
	var sys = ParentingScript.new()
	var child: Dictionary = {"ability": {"intelligence": 50.0, "charm": 50.0, "physique": 50.0, "willpower": 50.0, "luck": 50.0}}
	# 基因 50 + 照护 20 + 教育 20 + 随机 0 = 65。
	var rng = FixedRng.new([0.0])
	sys.raise_child(child, 100.0, 100.0, rng)
	check_near(float(child["ability"]["intelligence"]), 65.0, 1e-6, "成长公式")
	# 随机拉满 → +10。
	var child2: Dictionary = {"ability": {"intelligence": 50.0, "charm": 50.0, "physique": 50.0, "willpower": 50.0, "luck": 50.0}}
	sys.raise_child(child2, 100.0, 100.0, FixedRng.new([0.999]))
	check(float(child2["ability"]["intelligence"]) > 70.0, "随机提高上限")


func _test_events_and_heir() -> void:
	var sys = ParentingScript.new()
	var child: Dictionary = {"ability": {"intelligence": 50.0, "physique": 50.0}, "personality": {"agreeableness": 50.0, "neuroticism": 50.0}}
	sys.apply_event(child, "talent_emerge")
	check_near(float(child["ability"]["intelligence"]), 55.0, 1e-6, "天赋显露")
	sys.apply_event(child, "rebellion")
	check(float(child["personality"]["agreeableness"]) < 50.0, "叛逆降低宜人性")
	check_eq(str(sys.apply_event(child, "bogus")["reason"]), "unknown_event", "未知事件")
	sys.reach_adulthood(child)
	check(bool(child["independent"]), "成年独立")
	var kids: Array = [{"name": "a"}, {"name": "b"}]
	var r: Dictionary = sys.choose_heir(kids, 1)
	check(bool(r["ok"]), "择继承人")
	check_eq(str(r["heir"]["name"]), "b", "选定次子")
	check(bool(kids[0]["auto_run"]), "其余自动运行")
	# 早夭概率可关闭。
	check(not sys.early_death(FixedRng.new([0.0]), false), "关闭早夭")
	check(sys.early_death(FixedRng.new([0.0]), true), "极低概率早夭")
