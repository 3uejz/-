extends "res://tests/test_base.gd"
## NPC 个体生成与生命周期测试（任务 12；R18/R50；design 三级 LOD）。
## 覆盖：确定性生成、schema 字段、年龄/阶段、属性区间、日程完整性与活动查询、
##       LOD 个体化、生命事件、批量生成。

const NpcScript = preload("res://sim/npc.gd")

const YEAR_MIN: float = 365.25 * 1440.0

func _suite_name() -> String:
	return "npc"

func run_tests() -> void:
	_test_determinism()
	_test_schema_fields()
	_test_age_and_stage()
	_test_attributes_bounds()
	_test_schedule_coverage()
	_test_activity_lookup()
	_test_individualize_lod()
	_test_life_events()
	_test_cohort()


func _opts() -> Dictionary:
	return {"world_seed": 20261005, "region_id": "region.city.a", "now_minute": 1000000}


func _test_determinism() -> void:
	var sys = NpcScript.new()
	var a: Dictionary = sys.generate(7, _opts())
	var b: Dictionary = sys.generate(7, _opts())
	check_eq(str(a["id"]), str(b["id"]), "同索引生成同 ID")
	check_eq(str(a["name"]), str(b["name"]), "同索引生成同名")
	check_eq(int(a["birth_minutes"]), int(b["birth_minutes"]), "同索引生成同生日")
	check_eq(str(a["attributes"]), str(b["attributes"]), "同索引生成同属性")
	var c: Dictionary = sys.generate(8, _opts())
	check(str(a["id"]) != str(c["id"]), "不同索引生成不同 ID")


func _test_schema_fields() -> void:
	var sys = NpcScript.new()
	var n: Dictionary = sys.generate(1, _opts())
	for key in ["id", "name", "gender", "birth_minutes", "alive", "job", "traits",
			"attributes", "home", "schedule", "relations", "individualized", "lod_tier"]:
		check(n.has(key), "包含字段: " + key)
	check(["male", "female", "nonbinary", "other"].has(str(n["gender"])), "性别枚举合法")
	check_eq(str(n["home"]["region_id"]), "region.city.a", "归属区域")
	check(bool(n["alive"]), "默认存活")
	check_eq(int(n["lod_tier"]), 2, "默认 Tier2")
	check(int(n["traits"].size()) >= 3 and int(n["traits"].size()) <= 5, "特质 3..5")

	var female: Dictionary = sys.generate(2, {"gender": "female"})
	check_eq(str(female["gender"]), "female", "性别可覆盖")


func _test_age_and_stage() -> void:
	var sys = NpcScript.new()
	var n: Dictionary = sys.generate(3, {"now_minute": 10 * int(YEAR_MIN), "age": 10})
	check_near(sys.age_years(n, 10 * int(YEAR_MIN)), 10.0, 0.01, "年龄计算")
	check_eq(sys.life_stage(5), "child", "儿童")
	check_eq(sys.life_stage(10), "student", "学生")
	check_eq(sys.life_stage(30), "adult", "成年")
	check_eq(sys.life_stage(70), "senior", "老年")
	# 过世后年龄冻结于死亡时刻。
	sys.apply_life_event(n, "death", {"minute": 12 * int(YEAR_MIN)})
	check_near(sys.age_years(n, 99 * int(YEAR_MIN)), 12.0, 0.01, "死亡的 NPC 年龄冻结")


func _test_attributes_bounds() -> void:
	var sys = NpcScript.new()
	var n: Dictionary = sys.generate(4, _opts())
	var groups: Dictionary = n["attributes"]
	for group_name in groups.keys():
		var group: Dictionary = groups[group_name]
		for key in group.keys():
			var v: float = float(group[key])
			check(v >= 0.0 and v <= 100.0, "属性落在 0..100: %s.%s=%s" % [group_name, key, str(v)])


func _test_schedule_coverage() -> void:
	var sys = NpcScript.new()
	for stage in ["child", "student", "adult", "senior"]:
		var sched: Array = sys.default_schedule(stage)
		var total: int = 0
		var cursor: int = 0
		var contiguous: bool = true
		for seg in sched:
			if int(seg["start_minute_of_day"]) != cursor:
				contiguous = false
			cursor = int(seg["end_minute_of_day"])
			total += int(seg["end_minute_of_day"]) - int(seg["start_minute_of_day"])
		check_eq(total, 1440, "日程覆盖整日: " + stage)
		check(cursor == 1440, "日程结束于 1440: " + stage)
		check(contiguous, "日程连续无缝隙: " + stage)


func _test_activity_lookup() -> void:
	var sys = NpcScript.new()
	var worker: Dictionary = sys.generate(5, {"age": 35})
	var a: Dictionary = sys.activity_at(worker, 600)
	var b: Dictionary = sys.activity_at(worker, 100)
	var c: Dictionary = sys.activity_at(worker, 1400)
	check_eq(str(a.get("activity", "")), "work", "白天在工作")
	check_eq(str(b.get("activity", "")), "sleep", "清晨在睡觉")
	check_eq(str(c.get("activity", "")), "sleep", "深夜在睡觉")
	# 取模：1440 等价 0。
	var e: Dictionary = sys.activity_at(worker, 1440)
	check_eq(str(e.get("activity", "")), "sleep", "1440 取模为 0")


func _test_individualize_lod() -> void:
	var sys = NpcScript.new()
	var n: Dictionary = sys.generate(6, {"age": 40})
	check(not sys.is_individualized(n), "默认未个体化")
	sys.individualize(n)
	check(sys.is_individualized(n), "个体化标记")
	check_eq(int(n["lod_tier"]), 0, "个体化后 Tier0")
	sys.set_lod(n, 2)
	check_eq(int(n["lod_tier"]), 0, "个体化后拒绝降级")
	var m: Dictionary = sys.generate(9, {"age": 40})
	sys.set_lod(m, 1)
	check_eq(int(m["lod_tier"]), 1, "非个体化可设 Tier1")


func _test_life_events() -> void:
	var sys = NpcScript.new()
	var n: Dictionary = sys.generate(10, {"age": 45})
	check(bool(sys.apply_life_event(n, "change_job", {"job": "job.doctor"})["ok"]), "换工作成功")
	check_eq(str(n["job"]), "job.doctor", "职业已更新")
	check(bool(sys.apply_life_event(n, "migrate", {"region_id": "region.city.b"})["ok"]), "迁移成功")
	check_eq(str(n["home"]["region_id"]), "region.city.b", "归属已迁移")
	var hp_before: float = float(n["attributes"]["physiological"]["health"])
	sys.apply_life_event(n, "illness", {"severity": 30.0})
	check_near(float(n["attributes"]["physiological"]["health"]), maxf(0.0, hp_before - 30.0), 0.01, "生病降健康")
	sys.apply_life_event(n, "recover", {"amount": 10.0})
	check(bool(sys.apply_life_event(n, "death", {"minute": 555})["ok"]), "死亡成功")
	check(not bool(n["alive"]), "已死亡")
	check_eq(int(n["death_minutes"]), 555, "死亡时间")
	check(not bool(sys.apply_life_event(n, "death")["ok"]), "不可重复死亡")
	check(not bool(sys.apply_life_event(n, "unknown")["ok"]), "未知事件返回 false")


func _test_cohort() -> void:
	var sys = NpcScript.new()
	var cohort: Array = sys.generate_cohort(20, _opts())
	check_eq(cohort.size(), 20, "批量生成数量")
	var ids: Dictionary = {}
	for n in cohort:
		ids[str(n["id"])] = true
	check_eq(ids.size(), 20, "批量生成 ID 唯一")
