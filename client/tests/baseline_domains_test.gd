extends "res://tests/test_base.gd"
## 迁移域数值基线跨语言对齐测试（任务 48）。
##
## 读取 shared/consistency/vectors/baseline_domains.json 的共享期望值，
## 与生成的按域全量常量映射 Baseline.BASELINE_DOMAINS 逐值比对。
## 新增迁移域时只需扩 baseline_domains 向量，无需改动本测试。

const TOLERANCE: float = 1e-9


func _suite_name() -> String:
	return "baseline_domains"


func run_tests() -> void:
	var data: Dictionary = load_json(vectors_path("baseline_domains.json"))
	if data.is_empty():
		return
	var domains: Dictionary = data.get("domains", {})
	var code: Dictionary = Baseline.BASELINE_DOMAINS
	for domain in domains.keys():
		check(code.has(domain), "代码可见域 %s" % domain)
		if not code.has(domain):
			continue
		var expected: Dictionary = domains[domain]
		for key in expected.keys():
			check((code[domain] as Dictionary).has(key), "%s.%s 常量存在" % [domain, key])
			if (code[domain] as Dictionary).has(key):
				_match((code[domain] as Dictionary)[key], expected[key], "%s.%s" % [domain, key])


func _match(got: Variant, want: Variant, label: String) -> void:
	if want is Array:
		check(got is Array, "%s 应为数组" % label)
		if not (got is Array):
			return
		check_eq((got as Array).size(), (want as Array).size(), "%s 数组长度" % label)
		for i in mini((got as Array).size(), (want as Array).size()):
			_match((got as Array)[i], (want as Array)[i], "%s[%d]" % [label, i])
	elif want is Dictionary:
		check(got is Dictionary, "%s 应为字典" % label)
		if not (got is Dictionary):
			return
		var gd: Dictionary = got
		for key in (want as Dictionary).keys():
			check(gd.has(key), "%s.%s 存在" % [label, key])
			if gd.has(key):
				_match(gd[key], (want as Dictionary)[key], "%s.%s" % [label, key])
	elif got is int:
		check_eq(int(got), int(want), label)
	elif got is float:
		check_near(float(got), float(want), TOLERANCE, label)
	else:
		check_eq(got, want, label)
