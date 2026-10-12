extends "res://tests/test_base.gd"
## 文案变化层测试：时段划分、变体确定性、场景化时间线。

const FlavorScript = preload("res://sim/flavor.gd")

const PARTS: Array[String] = [
	"凌晨", "清晨", "上午", "中午", "下午", "傍晚", "夜晚", "深夜",
]

func _suite_name() -> String:
	return "flavor"

func run_tests() -> void:
	_test_day_parts()
	_test_pick_deterministic()
	_test_pick_fills_part()
	_test_variety_across_parts()
	_test_time_line()
	_test_unknown_pool()

func _test_day_parts() -> void:
	check_eq(FlavorScript.day_part(0), "凌晨", "0 分钟为凌晨")
	check_eq(FlavorScript.day_part(330), "清晨", "330 分钟为清晨")
	check_eq(FlavorScript.day_part(600), "上午", "600 分钟为上午")
	check_eq(FlavorScript.day_part(720), "中午", "正午为中午")
	check_eq(FlavorScript.day_part(900), "下午", "900 分钟为下午")
	check_eq(FlavorScript.day_part(1080), "傍晚", "1080 分钟为傍晚")
	check_eq(FlavorScript.day_part(1200), "夜晚", "1200 分钟为夜晚")
	check_eq(FlavorScript.day_part(1380), "深夜", "1380 分钟为深夜")
	check_eq(FlavorScript.day_part(1440), "凌晨", "跨日为凌晨")
	check_eq(FlavorScript.day_part(-60), "深夜", "负值环绕仍返回合法时段")

func _test_pick_deterministic() -> void:
	var a: String = FlavorScript.pick("wait", 600, "k")
	var b: String = FlavorScript.pick("wait", 600, "k")
	check_eq(a, b, "同输入变体恒定")
	check(a != "", "变体非空")

func _test_pick_fills_part() -> void:
	var text: String = FlavorScript.pick("sleep", 1230, "x")
	check(text.find("{part}") < 0, "占位符被填充")
	check(text.find("夜晚") >= 0, "含当前时段描述")

func _test_variety_across_parts() -> void:
	var seen: Dictionary = {}
	for m in range(0, 1440, 120):
		seen[FlavorScript.pick("wait", m, "")] = true
	check(seen.size() > 1, "不同时段产生不同措辞")

func _test_time_line() -> void:
	for key in ["wait", "sleep", "eat", "exercise", "work", "study"]:
		var line: String = FlavorScript.time_line(key, 480, "")
		check(line != "", "%s 时间线非空" % key)

func _test_unknown_pool() -> void:
	check_eq(FlavorScript.pick("不存在", 0, ""), "", "未知池返回空串")
	check(FlavorScript.time_line("不存在", 0, "") != "", "未知池时间线仍回退可读文本")
