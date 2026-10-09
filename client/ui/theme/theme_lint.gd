class_name ThemeLint
extends RefCounted
## token 无硬编码检查（R35、R57；任务 47.1）。
## 扫描 UI 源码，禁止在主题之外出现字面颜色（Color(...)、Color8(...)、#RRGGBB、Color.from_string）。

## 允许定义颜色的白名单文件（token 真源与配色方案）。
const ALLOWLIST: Array[String] = [
	"res://ui/theme/theme_tokens.gd",
	"res://ui/theme/theme_builder.gd",
	"res://ui/theme/theme_lint.gd",
	"res://ui/settings/accessibility_palette.gd",
]

static func is_allowlisted(path: String) -> bool:
	return ALLOWLIST.has(path)

## 扫描单个文件内容，返回违规行（行号从 1 开始）。
static func scan_text(path: String, text: String) -> Array:
	if is_allowlisted(path):
		return []
	var out: Array = []
	var lines: PackedStringArray = text.split("\n")
	for i in lines.size():
		var line: String = lines[i]
		var trimmed: String = line.strip_edges()
		if trimmed.begins_with("#"):   # 注释
			continue
		if _has_literal_color(line):
			out.append({"file": path, "line": i + 1, "text": trimmed})
	return out

static func _has_literal_color(line: String) -> bool:
	if line.find("Color(") >= 0 or line.find("Color8(") >= 0 or line.find("Color.from_string") >= 0:
		return true
	# #RRGGBB / #RRGGBBAA 字面量（避免误伤 # 注释需在上层过滤）。
	var re := RegEx.new()
	re.compile("#[0-9a-fA-F]{6}")
	return re.search(line) != null

## 递归扫描目录下所有 .gd 文件。
static func scan_dir(dir_path: String) -> Array:
	var violations: Array = []
	var files: Array = []
	_collect_gd(dir_path, files)
	files.sort()
	for f in files:
		var text: String = _read_file(f)
		violations.append_array(scan_text(f, text))
	return violations

static func _collect_gd(dir_path: String, out: Array) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		if name.begins_with("."):
			name = dir.get_next()
			continue
		var full: String = dir_path.path_join(name)
		if dir.current_is_dir():
			_collect_gd(full, out)
		elif name.ends_with(".gd"):
			out.append(full)
		name = dir.get_next()
	dir.list_dir_end()

static func _read_file(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var text: String = f.get_as_text()
	f.close()
	return text
