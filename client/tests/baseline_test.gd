extends "res://tests/test_base.gd"
## 数值基线与共享规格一致性测试。

const SpeedScript = preload("res://autoload/speed_controller.gd")

func _suite_name() -> String:
	return "baseline"

func run_tests() -> void:
	var data: Dictionary = load_json(vectors_path("baseline.json"))
	if data.is_empty():
		return

	var ranges: Dictionary = data["ranges"]
	var code_ranges: Dictionary = Baseline.ranges()
	for key in ranges.keys():
		var want: Array = []
		for v in ranges[key]:
			want.append(int(v))
		check_eq(code_ranges.get(key), want, "range %s" % key)

	check_near(Baseline.RELATION_ANNUAL_DECAY_K, float(data["defaults"]["relation_annual_decay_k"]), 1e-12, "relation_annual_decay_k")
	check_eq(Baseline.clamp_attribute(150), 100, "clamp attribute high")
	check_eq(Baseline.clamp_attribute(-5), 0, "clamp attribute low")
	check_eq(Baseline.clamp_skill(99), 20, "clamp skill high")
	check_eq(Baseline.clamp_favor(-999), -100, "clamp favor low")
	check_eq(Baseline.clamp_grudge(999), 100, "clamp grudge high")

	# 关系衰减：1 年后约 exp(-0.05) 倍。
	check_near(Baseline.apply_relation_decay(100.0, 1.0), 100.0 * exp(-0.05), 1e-9, "relation decay 1y")

	# 远程配置覆盖默认值。
	Baseline.apply_remote_config({"ranges": {"skill": [0, 30]}, "relation_annual_decay_k": 0.04})
	check_eq(Baseline.effective_range("skill"), [0, 30], "覆盖技能区间")
	check_eq(Baseline.clamp_skill(25), 25, "覆盖后技能 clamp")
	check_near(Baseline.apply_relation_decay(100.0, 1.0), 100.0 * exp(-0.04), 1e-9, "覆盖后衰减系数")
	Baseline.clear_overrides()
	check_eq(Baseline.clamp_skill(25), 20, "清除覆盖恢复默认")

	# 倍速档位与共享规格一致（JSON 数字为 float，转 int 后比较）。
	var want_levels: Array = []
	for v in data["speed_levels"]:
		want_levels.append(int(v))
	check_eq(SpeedScript.LEVELS, want_levels, "speed levels")
