extends "res://tests/test_base.gd"
## 面板入口与动词注册完整性检查（任务 51.1）。
## 校验：动词规格可解析且无重复；注册表覆盖核心动词且结构完整；12 面板与 ui.md 一致。

const CoverageScript = preload("res://command/verb_coverage.gd")
const RegistryScript = preload("res://command/verb_registry.gd")
const PanelRegistryScript = preload("res://ui/components/panel_registry.gd")

func _suite_name() -> String:
	return "ui_completeness"

func run_tests() -> void:
	_test_verb_spec_parses()
	_test_verb_registry_integrity()
	_test_panel_spec_matches()

func _test_verb_spec_parses() -> void:
	var md: String = CoverageScript.read_spec("verb-registry.md")
	check(md.length() > 0, "可读取 verb-registry.md")
	var verbs: Array = CoverageScript.parse_table_first_column(md)
	check(verbs.size() >= 200, "动词表规模>=200: %d" % verbs.size())
	var seen: Dictionary = {}
	var duplicates: Array = []
	for v in verbs:
		if seen.has(v):
			duplicates.append(v)
		seen[v] = true
	check(duplicates.is_empty(), "动词表无重复: %s" % str(duplicates))

func _test_verb_registry_integrity() -> void:
	var registry = RegistryScript.new()
	var report: Dictionary = CoverageScript.verb_report(registry)
	check(int(report["total"]) >= 200, "报告识别规格动词数")
	check(int(report["registered"]) > 0, "有核心动词已注册")
	check((report["missing"] as Array).size() > 0, "完整基线尚未全部导入（核心种子为准）")
	check(registry.has("帮助"), "核心动词「帮助」已注册")
	check(not registry.has("播种"), "未导入动词「播种」暂缺")
	var issues: Array = CoverageScript.registry_issues(registry, _seed_keys())
	check(issues.is_empty(), "注册表结构完整: %s" % str(issues))

func _seed_keys() -> Array:
	# VerbRegistry 未暴露键列表，借助帮助接口取全部（含隐藏）。
	var registry = RegistryScript.new()
	var out: Array = []
	for row in registry.help("", {"revealed_abnormal": true}):
		out.append(String(row["verb"]))
	return out

func _test_panel_spec_matches() -> void:
	var panel_registry = PanelRegistryScript.new()
	var report: Dictionary = CoverageScript.panel_report(panel_registry)
	var spec: Array = report["spec"]
	check_eq(spec.size(), 12, "ui.md 面板清单 12 项")
	check((report["missing"] as Array).is_empty(), "规格面板均已注册: %s" % str(report["missing"]))
	check((report["extra"] as Array).is_empty(), "注册面板均在规格内: %s" % str(report["extra"]))
