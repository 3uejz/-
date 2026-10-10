class_name VerbCoverage
extends RefCounted
## 面板入口与动词注册完整性检查（任务 51.1；对应 gaps.md 系统性问题 4、5）。
## 解析规格文件（verb-registry.md / ui.md）并对照运行时注册表，报告覆盖与缺失。
## 规格在仓库内、UI 资源树之外，故用 globalize_path 读取；纯逻辑，headless 可测。

const SPEC_DIR: String = "../.monkeycode/specs/life-text-sandbox"

## 读取仓库规格文件（相对 res:// 的路径）。
static func read_spec(file_name: String) -> String:
	var path: String = ProjectSettings.globalize_path("res://").path_join(SPEC_DIR).path_join(file_name)
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var text: String = f.get_as_text()
	f.close()
	return text

## 从整篇 markdown 的所有表格中提取第一列（跳过表头与分隔行）。
static func parse_table_first_column(markdown: String) -> Array:
	var out: Array = []
	for line in markdown.split("\n"):
		var trimmed: String = line.strip_edges()
		if not trimmed.begins_with("|"):
			continue
		var cells: Array = _split_row(trimmed)
		if cells.is_empty():
			continue
		var first: String = String(cells[0])
		if first == "动词" or first == "面板" or _is_separator(first):
			continue
		out.append(first)
	return out

## 解析指定「## N.」小节下的表格第一列（如 ui.md 第 4 节的面板清单）。
static func parse_section_first_column(markdown: String, heading_prefix: String) -> Array:
	var out: Array = []
	var in_section: bool = false
	for line in markdown.split("\n"):
		var trimmed: String = line.strip_edges()
		if trimmed.begins_with("## "):
			in_section = trimmed.begins_with(heading_prefix)
			continue
		if not in_section or not trimmed.begins_with("|"):
			continue
		var cells: Array = _split_row(trimmed)
		if cells.is_empty():
			continue
		var first: String = String(cells[0])
		if first == "面板" or first == "动词" or _is_separator(first):
			continue
		out.append(first)
	return out

## 动词覆盖报告：规格动词 vs 注册表。
static func verb_report(registry) -> Dictionary:
	var spec: Array = parse_table_first_column(read_spec("verb-registry.md"))
	var registered: Array = []
	var missing: Array = []
	var seen: Dictionary = {}
	var duplicates: Array = []
	for v in spec:
		var verb: String = String(v)
		if seen.has(verb):
			if not duplicates.has(verb):
				duplicates.append(verb)
			continue
		seen[verb] = true
		if registry.has(verb):
			registered.append(verb)
		else:
			missing.append(verb)
	return {
		"total": seen.size(),
		"registered": registered.size(),
		"coverage": float(registered.size()) / float(max(1, seen.size())),
		"missing": missing,
		"duplicates": duplicates,
	}

## 面板覆盖报告：规格面板标题 vs 注册表。
static func panel_report(registry) -> Dictionary:
	var spec: Array = parse_section_first_column(read_spec("ui.md"), "## 4.")
	var registered: Array = []
	for id in registry.panel_ids():
		registered.append(registry.title_of(id))
	var missing: Array = []
	for title in spec:
		if not registered.has(String(title)):
			missing.append(String(title))
	var extra: Array = []
	for title in registered:
		if not spec.has(String(title)):
			extra.append(String(title))
	return {"spec": spec, "registered": registered, "missing": missing, "extra": extra}

## 注册表结构完整性：每个动词须有非空分类与用法，别名不得与规范名冲突。
static func registry_issues(registry, ids: Array) -> Array:
	var issues: Array = []
	var alias_owner: Dictionary = {}
	for id in ids:
		var d: Dictionary = registry.get_def(String(id))
		if String(d.get("category", "")).is_empty():
			issues.append("%s 缺少分类" % id)
		if String(d.get("usage", "")).is_empty():
			issues.append("%s 缺少用法" % id)
		var names: Array = [String(id)]
		names.append_array(d.get("aliases", []))
		for n in names:
			var name: String = String(n)
			if alias_owner.has(name) and String(alias_owner[name]) != String(id):
				issues.append("别名冲突「%s」：%s 与 %s" % [name, alias_owner[name], id])
			alias_owner[name] = String(id)
	return issues

# --- 内部 ---

static func _split_row(line: String) -> Array:
	var parts: Array = line.split("|")
	if parts.size() < 3:
		return []
	# 去掉首尾因「|」产生的空段。
	var cells: Array = []
	for i in range(1, parts.size() - 1):
		cells.append(String(parts[i]).strip_edges())
	return cells

static func _is_separator(cell: String) -> bool:
	var s: String = cell.replace("-", "").replace(":", "").strip_edges()
	return s.is_empty()
