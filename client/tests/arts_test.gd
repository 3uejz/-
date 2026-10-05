extends "res://tests/test_base.gd"
## 艺术生涯测试（任务 14；R45.6；design D5）。
## 覆盖：作品评分公式、灵感与迎合度损失、评级、发行收入与声望、评奖。

const ArtScript = preload("res://sim/arts.gd")
const RngScript = preload("res://sim/rng.gd")
const BaselineScript = preload("res://sim/baseline.gd")


func _suite_name() -> String:
	return "arts"


func run_tests() -> void:
	BaselineScript.clear_overrides()
	_test_create_work()
	_test_pandering()
	_test_release_and_award()
	BaselineScript.clear_overrides()


func _skills(level: int = 20) -> Array:
	return [{"content_key": "skill.vocal", "level": level}]


# --- 创作 ---

func _test_create_work() -> void:
	var sys = ArtScript.new()
	var rng = RngScript.new(1)
	var w: Dictionary = sys.create_work("music", _skills(20), rng, {"inspiration": 100.0, "luck": 100.0})
	check(bool(w["ok"]), "创作成功")
	check_near(float(w["score"]), 100.0, 1e-6, "全满评分 100")
	check_eq(str(w["grade"]), "masterpiece", "传世评级")
	check_eq(str(sys.create_work("nope", _skills(), rng)["reason"]), "bad_discipline", "非法领域拒绝")
	# 技能来自玩家技能树。
	var w2: Dictionary = sys.create_work("music", _skills(0), rng, {"inspiration": 0.0, "luck": 0.0})
	check_near(float(w2["score"]), 0.0, 1e-6, "零技能零灵感评分 0")
	check_eq(ArtScript.grade_of(60.0), "competent", "评级分档")
	check_eq(ArtScript.grade_of(30.0), "mediocre", "低分评级")


func _test_pandering() -> void:
	var sys = ArtScript.new()
	var pure: Dictionary = sys.create_work("music", _skills(20), null, {"inspiration": 100.0, "luck": 100.0, "pandering": 0.0})
	var sold: Dictionary = sys.create_work("music", _skills(20), null, {"inspiration": 100.0, "luck": 100.0, "pandering": 1.0})
	check(float(sold["score"]) < float(pure["score"]), "迎合度降低评分")
	check_near(float(pure["score"]) - float(sold["score"]), ArtScript.PANDER_LOSS, 1e-6, "迎合损失固定")


# --- 发行与评奖 ---

func _test_release_and_award() -> void:
	var sys = ArtScript.new()
	var w: Dictionary = sys.create_work("painting", _skills(20), null, {"inspiration": 100.0, "luck": 100.0})
	var r: Dictionary = sys.release(w, {"reach": 2.0})
	check(bool(r["ok"]), "发行成功")
	check(int(r["income"]) > 0, "发行收入")
	check(float(r["fame"]) > 0.0, "发行声望")
	check(not bool(sys.release({"ok": false})["ok"]), "无效作品不可发行")
	# 低分不获奖。
	check(not bool(sys.award({"score": 40.0})["won"]), "低分不获奖")
	# 高分按概率获奖（确定性：遍历种子）。
	var rng = RngScript.new(0)
	var high: Dictionary = {"score": 95.0}
	var won: bool = false
	for i in 20:
		if bool(sys.award(high, rng)["won"]):
			won = true
			break
	check(won, "高分最终获奖")
