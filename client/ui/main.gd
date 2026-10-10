extends Control
## 主界面壳（R35、R57）：顶部状态栏、中部叙事流、底部输入栏与情境动作面板。
## 与 CommandParser / CommandIntent 打通：输入文本 → 解析 → 显示意图/候选/错误。
## 结构与接线为主，模拟逻辑在 sim/ 与 command/，保证 headless 可加载。

const ParserScript = preload("res://command/command_parser.gd")
const NarratorScript = preload("res://sim/narrator.gd")
const PaletteScript = preload("res://ui/settings/accessibility_palette.gd")
const ThemeManagerScript = preload("res://ui/theme/theme_manager.gd")
const PanelContentScript = preload("res://ui/panels/panel_content.gd")
const PanelRegistryScript = preload("res://ui/components/panel_registry.gd")

## 常驻快捷动作：未输入即可游玩（R35.5）。
const QUICK_ACTIONS: Array = [
	{"label": "看自己", "verb": "看自己", "objects": [], "params": {}},
	{"label": "看背包", "verb": "看背包", "objects": [], "params": {}},
	{"label": "睡 8 小时", "verb": "睡", "objects": [], "params": {"duration": 8, "duration_unit": "小时"}},
	{"label": "锻炼", "verb": "锻炼", "objects": [], "params": {}},
	{"label": "求职", "verb": "求职", "objects": [], "params": {}},
	{"label": "看关系", "verb": "看关系", "objects": [], "params": {}},
	{"label": "看资产", "verb": "看资产", "objects": [], "params": {}},
]

@onready var _time_label: Label = $Root/StatusBar/TimeLabel
@onready var _money_label: Label = $Root/StatusBar/MoneyLabel
@onready var _health_label: Label = $Root/StatusBar/HealthLabel
@onready var _mood_label: Label = $Root/StatusBar/MoodLabel
@onready var _weather_label: Label = $Root/StatusBar/WeatherLabel
@onready var _speed_button: Button = $Root/StatusBar/SpeedButton
@onready var _pause_button: Button = $Root/StatusBar/PauseButton
@onready var _message_list: VBoxContainer = $Root/Body/Messages/MessageList
@onready var _action_panel: VBoxContainer = $Root/Body/SidePanel/ActionPanel
@onready var _input: LineEdit = $Root/InputBar/Input
@onready var _send_button: Button = $Root/InputBar/SendButton

var _parser
var _narrator
var _palette
var _command_handler: Callable = Callable()
var _theme_manager
var _panel_registry
var _drawers: Dictionary = {}          ## 面板 id -> 抽屉节点
var _drawer_row: HBoxContainer

## 快捷动词 -> 侧边面板映射，使按钮与文字指令同源打开面板（R35.5）。
const VERB_PANELS: Dictionary = {
	"看自己": "character", "看角色": "character", "属性": "character",
	"看背包": "inventory", "背包": "inventory",
	"看技能": "skills", "技能树": "skills",
	"看关系": "relations", "人脉": "relations",
	"看地图": "map", "地图": "map",
	"看资产": "finance", "财务": "finance",
}

func _ready() -> void:
	_parser = ParserScript.new()
	_narrator = NarratorScript.new()
	_palette = PaletteScript.new()
	_theme_manager = ThemeManagerScript.new()
	_theme_manager.apply_to(self)
	_panel_registry = PanelRegistryScript.new()
	_connect_nodes()
	_build_actions()
	_ensure_drawer_row()
	_build_panel_buttons()
	refresh_status()
	append_message("浮生录：输入中文指令开始你的一生。", "info")

func _connect_nodes() -> void:
	if is_instance_valid(_send_button):
		_send_button.pressed.connect(_on_send)
	if is_instance_valid(_input):
		_input.text_submitted.connect(_on_submit_text)
	if is_instance_valid(_pause_button):
		_pause_button.pressed.connect(_on_pause)

## 外部（如事件结算、面板）可注入执行器；无执行器时仅回显解析意图。
func set_command_handler(handler: Callable) -> void:
	_command_handler = handler

# --- 输入与解析 ---

func _on_submit_text(text: String) -> void:
	submit(text)

func _on_send() -> void:
	if is_instance_valid(_input):
		submit(_input.text)

## 核心接线：文本 → CommandParser → 显示意图/候选/错误。
func submit(text: String) -> void:
	var raw := text.strip_edges()
	if raw.is_empty():
		return
	if is_instance_valid(_input):
		_input.text = ""
	append_message("> %s" % raw, "info")
	var intent = _parser.parse(raw, _context())
	_record_history(raw)
	if not intent.ok:
		_append_intent_failure(intent)
		return
	append_message(_format_intent(intent), "success")
	if _command_handler.is_valid():
		_command_handler.call(intent)

## 动作面板/快捷键入口与文字输入同源（R27 意图同源）。
func dispatch_action(verb: String, objects: Array = [], params: Dictionary = {}, source: String = "panel") -> void:
	var pid: String = String(VERB_PANELS.get(verb, ""))
	if pid != "":
		_toggle_panel(pid)
	var intent = _parser.from_action(verb, objects, params, _context(), source)
	if not intent.ok:
		append_message(intent.error, "danger")
		return
	append_message(_format_intent(intent), "success")
	if _command_handler.is_valid():
		_command_handler.call(intent)

func _append_intent_failure(intent) -> void:
	append_message(intent.error, "danger")
	if intent.options.is_empty():
		return
	var labels := PackedStringArray()
	for op in intent.options:
		labels.append("%d.%s" % [op.index, op.label])
	append_message("候选：%s（可输入序号选择）" % "  ".join(labels), "warning")

func _format_intent(intent) -> String:
	var names := PackedStringArray()
	for o in intent.objects:
		if o is Dictionary:
			names.append(String(o.get("name", o.get("id", ""))))
	var parts := PackedStringArray()
	parts.append("意图：%s" % intent.verb)
	if names.size() > 0:
		parts.append("对象：%s" % "、".join(names))
	if not intent.params.is_empty():
		parts.append("参数：%s" % str(intent.params))
	return "  ".join(parts)

func _record_history(raw: String) -> void:
	if _parser != null:
		_parser.record_history(raw)

## 解析上下文：由面板/GameState 提供；此处给出可用的最小上下文。
func _context() -> Dictionary:
	return {"slots": {}, "recent": []}

# --- 动作面板 ---

func _build_actions() -> void:
	if not is_instance_valid(_action_panel):
		return
	for action in QUICK_ACTIONS:
		var button := Button.new()
		button.text = String(action.get("label", ""))
		button.focus_mode = Control.FOCUS_ALL
		var verb := String(action.get("verb", ""))
		var objects: Array = action.get("objects", [])
		var params: Dictionary = action.get("params", {})
		button.pressed.connect(func() -> void: dispatch_action(verb, objects, params, "panel"))
		_action_panel.add_child(button)

# --- 侧边抽屉面板（任务 47/51） ---

## 面板条件可见：目前仅常驻面板；异常/金手指面板待对应状态接入后开放。
func _panel_conditions() -> Dictionary:
	return {}

func _ensure_drawer_row() -> void:
	if is_instance_valid(_drawer_row):
		return
	var root := get_node_or_null("Root")
	if root == null:
		return
	_drawer_row = HBoxContainer.new()
	_drawer_row.name = "Drawers"
	root.add_child(_drawer_row)
	var body := root.get_node_or_null("Body")
	if body != null:
		root.move_child(_drawer_row, body.get_index() + 1)

func _build_panel_buttons() -> void:
	if not is_instance_valid(_action_panel) or _panel_registry == null:
		return
	var label := Label.new()
	label.text = "面板"
	_action_panel.add_child(label)
	for id in _panel_registry.available(_panel_conditions()):
		var panel_id := String(id)
		var button := Button.new()
		button.text = _panel_registry.title_of(panel_id)
		button.focus_mode = Control.FOCUS_ALL
		button.pressed.connect(func() -> void: _toggle_panel(panel_id))
		_action_panel.add_child(button)

## 打开面板（可多开并排，集中在焦点）。返回是否已打开。
func open_panel(id: String, conditions: Dictionary = {}) -> bool:
	if _panel_registry == null:
		return false
	var cond: Dictionary = conditions if not conditions.is_empty() else _panel_conditions()
	var result: Dictionary = _panel_registry.open(id, cond)
	if not bool(result.get("ok", false)):
		return false
	if _drawers.has(id):
		return true
	_ensure_drawer_row()
	if not is_instance_valid(_drawer_row):
		return false
	var drawer := _build_drawer(id)
	_drawer_row.add_child(drawer)
	_drawers[id] = drawer
	return true

func close_panel(id: String) -> bool:
	if _panel_registry == null or not _panel_registry.close(id):
		return false
	if _drawers.has(id):
		var drawer = _drawers[id]
		if is_instance_valid(drawer):
			drawer.queue_free()
		_drawers.erase(id)
	return true

func _toggle_panel(id: String) -> void:
	if _panel_registry != null and _panel_registry.is_open(id):
		close_panel(id)
	else:
		open_panel(id)

func has_panel(id: String) -> bool:
	return _drawers.has(id)

func panel_count() -> int:
	return _drawers.size()

func _build_drawer(id: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "Drawer_%s" % id
	panel.custom_minimum_size = Vector2(300, 0)
	var column := VBoxContainer.new()
	panel.add_child(column)
	var header := HBoxContainer.new()
	var title := Label.new()
	title.text = _panel_registry.title_of(id)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close_button := Button.new()
	close_button.text = "关闭"
	close_button.pressed.connect(func() -> void: close_panel(id))
	header.add_child(close_button)
	column.add_child(header)
	column.add_child(HSeparator.new())
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 240)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	column.add_child(scroll)
	_fill_panel_content(content, id)
	return panel

func _fill_panel_content(container: VBoxContainer, id: String) -> void:
	var data: Dictionary = PanelContentScript.build(id, _current_player())
	if bool(data.get("empty", false)):
		var hint := Label.new()
		hint.text = String(data.get("empty_hint", ""))
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.add_theme_color_override("font_color", _theme_manager.color("color.text.disabled"))
		container.add_child(hint)
		return
	for section in data.get("sections", []):
		var section_title := Label.new()
		section_title.text = String(section.get("title", ""))
		container.add_child(section_title)
		for row in section.get("rows", []):
			container.add_child(_row_node(String(row.get("label", "")), String(row.get("value", ""))))
		container.add_child(HSeparator.new())

func _row_node(label_text: String, value_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	var left := Label.new()
	left.text = label_text
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var right := Label.new()
	right.text = value_text
	right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(left)
	row.add_child(right)
	return row

func _current_player() -> Dictionary:
	var game = get_node_or_null("/root/GameState")
	if game != null and game.player is Dictionary:
		return game.player
	return {}

# --- 叙事流 ---

## 追加一条消息，按类型着色并附非颜色线索（R35.7、R59.5）。
func append_message(text: String, type: String = "info", markers: Array = []) -> void:
	if not is_instance_valid(_message_list):
		return
	var render := {"text": text, "markers": markers}
	_append_render(render, type)

func _append_render(render: Dictionary, type: String) -> void:
	var style: Dictionary = _palette.style_for(type)
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_color_override("default_color", style["color"])
	var prefix := "%s " % String(style["cue"])
	label.text = prefix + _to_bbcode(render)
	_message_list.add_child(label)

## 把 Narrator 标记转成可点击 bbcode 链接（地点/物品/NPC 名称）。
func _to_bbcode(render: Dictionary) -> String:
	var text := String(render.get("text", ""))
	var markers: Array = render.get("markers", [])
	var sorted: Array = markers.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["start"]) > int(b["start"]))
	for m in sorted:
		var start := int(m["start"])
		var end := int(m["end"])
		if start < 0 or end > text.length() or start > end:
			continue
		var shown := text.substr(start, end - start)
		var target: Dictionary = m.get("target", {})
		var link := "[url=%s:%s]%s[/url]" % [String(target.get("type", "")), String(target.get("id", "")), shown]
		text = text.substr(0, start) + link + text.substr(end)
	return text

# --- 状态栏 ---

func refresh_status() -> void:
	var clock = get_node_or_null("/root/WorldClock")
	if is_instance_valid(_time_label) and clock != null:
		var cal: Dictionary = clock.calendar()
		_time_label.text = "时间：%s" % String(cal.get("date", "----"))
	var game = get_node_or_null("/root/GameState")
	if game != null and game.player is Dictionary:
		var player: Dictionary = game.player
		var attrs: Dictionary = player.get("attrs", {})
		var phys: Dictionary = attrs.get("physiological", {})
		var psy: Dictionary = attrs.get("psychological", {})
		var fin: Dictionary = player.get("finances", {})
		if is_instance_valid(_money_label):
			_money_label.text = "金钱：%.0f" % float(fin.get("cash", 0.0))
		if is_instance_valid(_health_label):
			_health_label.text = "健康：%.0f" % float(phys.get("health", 0.0))
		if is_instance_valid(_mood_label):
			_mood_label.text = "心情：%.0f" % float(psy.get("mood", 0.0))
	var speed = get_node_or_null("/root/SpeedController")
	if is_instance_valid(_speed_button) and speed != null:
		_speed_button.text = "倍速：%dx" % int(speed.get_speed())
	if is_instance_valid(_speed_button):
		if not _speed_button.pressed.is_connected(_on_speed):
			_speed_button.pressed.connect(_on_speed)

func _on_speed() -> void:
	var speed = get_node_or_null("/root/SpeedController")
	if speed == null:
		return
	var levels: Array = [0, 1, 2, 4, 60, 3600, 86400]
	var idx: int = levels.find(int(speed.get_speed()))
	speed.set_speed(int(levels[(idx + 1) % levels.size()]))
	refresh_status()

func _on_pause() -> void:
	var speed = get_node_or_null("/root/SpeedController")
	if speed == null:
		return
	speed.set_speed(0 if not speed.is_paused() else 1)
	refresh_status()
