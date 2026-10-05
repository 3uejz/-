@tool
extends VBoxContainer
## 内容工具面板：批量校验、构建内容包、重新导入与场所预览（R36.12）。

var _log: RichTextLabel
var _group_input: LineEdit


func _ready() -> void:
	add_child(_make_label("内容工具"))
	add_child(_make_button("校验内容", _on_validate))
	add_child(_make_button("构建内容包", _on_build))
	add_child(_make_button("重新导入资源", _on_reimport))
	var row := HBoxContainer.new()
	_group_input = LineEdit.new()
	_group_input.placeholder_text = "场所分组，如 medical"
	_group_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_group_input)
	row.add_child(_make_button("预览场所", _on_preview))
	add_child(row)
	_log = RichTextLabel.new()
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.custom_minimum_size = Vector2(0, 200)
	add_child(_log)


func _project_root() -> String:
	return ProjectSettings.globalize_path("res://").path_join("..")


func _builder_dir() -> String:
	return _project_root().path_join("tools/contentbuilder")


func _catalog_dir() -> String:
	return _project_root().path_join("content/catalog")


func _run_builder(args: Array) -> void:
	var output: Array = []
	var full: Array = ["-C", _builder_dir()]
	full.append_array(args)
	# OS.execute 无工作目录参数，用 `go -C <dir>` 切换。
	var exit_code := OS.execute("go", full, output, true)
	var text := ""
	for line in output:
		text += str(line) + "\n"
	_append("[%d] %s" % [exit_code, text])


func _on_validate() -> void:
	_append("== 校验内容 ==")
	_run_builder(["run", ".", "validate", "--catalog", _catalog_dir()])


func _on_build() -> void:
	_append("== 构建内容包 ==")
	_run_builder([
		"run", ".", "build",
		"--catalog", _catalog_dir(),
		"--out", _project_root().path_join("build/content"),
	])


func _on_reimport() -> void:
	_append("== 重新导入资源 ==")
	var fs := EditorInterface.get_resource_filesystem()
	if fs != null:
		fs.scan()
		_append("已触发资源重新扫描")


func _on_preview() -> void:
	var group := _group_input.text.strip_edges()
	if group == "":
		group = "medical"
	if not PlaceBindings.has_group(group):
		var names := ""
		for g in PlaceBindings.GROUPS:
			names += str(g) + " "
		_append("未知分组: %s（可用: %s）" % [group, names])
		return
	var path := PlaceBindings.scene_for(group)
	EditorInterface.open_scene_from_path(path)
	_append("预览场所 %s -> %s" % [group, path])


func _append(text: String) -> void:
	if _log != null:
		_log.append_text(text + "\n")


func _make_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label


func _make_button(text: String, handler: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(handler)
	return button
