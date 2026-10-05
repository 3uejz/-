extends "res://tests/test_base.gd"
## 领域技能树与成长测试（任务 14；R10、R45.1-3；design D5）。
## 覆盖：7 棵树 × 21 技能目录、经验曲线、实践收益公式、前置解锁、天赋上限、
##       高等级边际收益递减、长期不使用遗忘。

const SkillScript = preload("res://sim/skills.gd")
const BaselineScript = preload("res://sim/baseline.gd")


func _suite_name() -> String:
	return "skills"


func run_tests() -> void:
	BaselineScript.clear_overrides()
	_test_catalog()
	_test_need_xp()
	_test_practice_and_level_up()
	_test_prereq_lock()
	_test_talent_cap()
	_test_diminishing_and_forget()
	BaselineScript.clear_overrides()


func _ctx(extra: Dictionary = {}) -> Dictionary:
	var base: Dictionary = {
		"intelligence": 50.0, "willpower": 50.0, "fatigue": 0.0,
		"talents": [], "guidance": 0.0, "now_minute": 0,
	}
	for k in extra.keys():
		base[k] = extra[k]
	return base


# --- 目录 ---

func _test_catalog() -> void:
	var sys = SkillScript.new()
	check_eq(sys.register_starter_catalog(), 147, "起步目录 147 个技能")
	check_eq(sys.def_count(), 147, "定义数一致")
	check_eq(SkillScript.TREES.size(), 7, "七棵领域树")
	for tree in SkillScript.TREES:
		check(sys.by_tree(tree).size() >= 20, "每棵树至少 20 个技能: " + tree)
	# 与 jobs/军旅口径一致的规范技能 id。
	for id in ["skill.programming", "skill.finance", "skill.management", "skill.academic", "skill.physique", "skill.technical", "skill.willpower"]:
		check(sys.has_def(id), "规范技能存在: " + id)
	# 可扩展。
	var before: int = sys.def_count()
	sys.register({"id": "skill.custom_x", "name": "自定义", "tree": "life"})
	check_eq(sys.def_count(), before + 1, "技能可扩展")
	check(sys.register({"id": "skill.bad", "name": "非法", "tree": "nope"}) == {}, "非法领域拒绝")


func _test_need_xp() -> void:
	check(SkillScript.need_xp(0) > 0.0, "0 级需经验")
	check(SkillScript.need_xp(1) > SkillScript.need_xp(0), "经验需求递增")
	check(SkillScript.need_xp(19) > SkillScript.need_xp(10), "高阶需求更高")


# --- 实践与升级 ---

func _test_practice_and_level_up() -> void:
	var sys = SkillScript.new()
	sys.register_starter_catalog()
	var skills: Array = []
	var r: Dictionary = sys.practice(skills, "skill.cooking", 1.0, _ctx({"intelligence": 100.0, "willpower": 100.0}))
	check(bool(r["ok"]), "实践成功")
	check_near(float(r["xp_gain"]), 1.0 * 10.0 * 2.0 * 2.0, 1e-6, "收益公式")
	check_eq(sys.level_of(skills, "skill.cooking"), 0, "经验未满不升级")
	# 大量实践升级。
	var big: Dictionary = sys.practice(skills, "skill.cooking", 100000.0, _ctx({"intelligence": 100.0, "willpower": 100.0}))
	check(int(big["level"]) >= 5, "累计经验升级")
	check(int(big["level_up"]) >= 5, "一次可多级")
	check(int(sys.level_of(skills, "skill.cooking")) >= 5, "等级写入技能条目")
	# 满级封顶。
	var vocal: Array = [{"content_key": "skill.vocal", "level": 0, "xp": 0.0, "last_used_minute": 0}]
	var capr: Dictionary = sys.practice(vocal, "skill.vocal", 1.0e9, _ctx({"talents": ["talent.music"]}))
	check_eq(int(capr["level"]), SkillScript.MAX_LEVEL, "有天赋可至 20 级")
	check(bool(capr["capped"]), "满级标记")


# --- 前置 ---

func _test_prereq_lock() -> void:
	var sys = SkillScript.new()
	sys.register_starter_catalog()
	var skills: Array = []
	check(not sys.can_learn(skills, "skill.finance_life"), "前置未满足不可学")
	check_eq(str(sys.practice(skills, "skill.finance_life", 1.0, _ctx())["reason"]), "locked", "锁定技能拒绝实践")
	# 把前置练到 5 级。
	sys.practice(skills, "skill.cooking", 100000.0, _ctx({"intelligence": 100.0, "willpower": 100.0}))
	check(sys.level_of(skills, "skill.cooking") >= 5, "前置达到 5 级")
	check(sys.can_learn(skills, "skill.finance_life"), "前置满足后解锁")
	check(bool(sys.practice(skills, "skill.finance_life", 1.0, _ctx())["ok"]), "解锁后可实践")


# --- 天赋上限 ---

func _test_talent_cap() -> void:
	var sys = SkillScript.new()
	sys.register_starter_catalog()
	# 无天赋：声乐上限 8。
	var plain: Array = [{"content_key": "skill.vocal", "level": 0, "xp": 0.0, "last_used_minute": 0}]
	sys.practice(plain, "skill.vocal", 1.0e9, _ctx())
	check_eq(sys.level_of(plain, "skill.vocal"), SkillScript.INNATE_CAP, "无天赋受先天上限")
	check_eq(sys.level_cap("skill.vocal", []), SkillScript.INNATE_CAP, "上限接口")
	check_eq(sys.level_cap("skill.vocal", ["talent.music"]), SkillScript.MAX_LEVEL, "有天赋解除上限")
	# 普通技能不受天赋限制。
	check_eq(sys.level_cap("skill.cooking", []), SkillScript.MAX_LEVEL, "普通技能无天赋限制")


# --- 边际递减与遗忘 ---

func _test_diminishing_and_forget() -> void:
	var sys = SkillScript.new()
	sys.register_starter_catalog()
	var low: Array = [{"content_key": "skill.cooking", "level": 1, "xp": 0.0, "last_used_minute": 0}]
	var high: Array = [{"content_key": "skill.cooking", "level": 15, "xp": 0.0, "last_used_minute": 0}]
	var gl: float = float(sys.practice(low, "skill.cooking", 1.0, _ctx())["xp_gain"])
	var gh: float = float(sys.practice(high, "skill.cooking", 1.0, _ctx())["xp_gain"])
	check(gh < gl, "高等级边际收益递减")
	# 遗忘：100 天不练。
	var idle: Array = [{"content_key": "skill.cooking", "level": 5, "xp": 0.0, "last_used_minute": 0}]
	var affected: Array = sys.forget(idle, 100 * 1440)
	check_eq(affected.size(), 1, "遗忘命中")
	check(sys.level_of(idle, "skill.cooking") < 5, "长期不使用掉级")
	# 宽限期内不遗忘。
	var fresh: Array = [{"content_key": "skill.cooking", "level": 5, "xp": 0.0, "last_used_minute": 0}]
	check_eq(sys.forget(fresh, 10 * 1440).size(), 0, "宽限期内不遗忘")
