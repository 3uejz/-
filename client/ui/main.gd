extends Control
## 主界面壳（R35、R57）：顶部状态栏、中部叙事流、底部输入栏与情境动作面板。
## 与 CommandParser / CommandIntent 打通：输入文本 → 解析 → 显示意图/候选/错误。
## 结构与接线为主，模拟逻辑在 sim/ 与 command/，保证 headless 可加载。

const ParserScript = preload("res://command/command_parser.gd")
const SimHostScript = preload("res://sim/sim_host.gd")
const ExecutorScript = preload("res://command/intent_executor.gd")
const TimeDriverScript = preload("res://sim/time_driver.gd")
const SaveManagerScript = preload("res://sim/save_manager.gd")
const NarratorScript = preload("res://sim/narrator.gd")
const PaletteScript = preload("res://ui/settings/accessibility_palette.gd")
const ThemeManagerScript = preload("res://ui/theme/theme_manager.gd")
const PanelContentScript = preload("res://ui/panels/panel_content.gd")
const PanelRegistryScript = preload("res://ui/components/panel_registry.gd")
const DialogRegistryScript = preload("res://ui/components/dialog_registry.gd")
const HistoryViewScript = preload("res://ui/layout/history_view.gd")
const IllustrationScript = preload("res://ui/components/illustration.gd")
const NotificationCenterScript = preload("res://ui/notifications/notification_center.gd")

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
@onready var _messages_scroll: ScrollContainer = $Root/Body/Messages
@onready var _action_panel: VBoxContainer = $Root/Body/SidePanel/ActionPanel
@onready var _input: LineEdit = $Root/InputBar/Input
@onready var _send_button: Button = $Root/InputBar/SendButton

var _parser
var _narrator
var _sim                                  ## SimHost：玩法接线层
var _executor                             ## IntentExecutor：意图 → 模拟
var _time_driver                          ## TimeDriver：挂机实时世界的分钟换算
var _auto_time: bool = false              ## 是否随现实时间推进（真实窗口开，headless 关）
var _save_manager                         ## SaveManager：本地存读档
var _palette
var _command_handler: Callable = Callable()
var _theme_manager
var _panel_registry
var _history
var _notifications
## 超过该行数后叙事流改用窗口化渲染，避免超长会话卡顿（ui.md 第 6 节）。
const VIRTUAL_THRESHOLD: int = 400
const EST_ROW_HEIGHT: float = 26.0
var _dialog_registry
var _drawers: Dictionary = {}          ## 面板 id -> 抽屉节点
var _drawer_row: HBoxContainer
var _dialog_layer: Control
var _dialog_box: PanelContainer

## 快捷动词 -> 侧边面板映射，使按钮与文字指令同源打开面板（R35.5）。
const VERB_PANELS: Dictionary = {
	"看自己": "character", "看角色": "character", "属性": "character",
	"看背包": "inventory", "背包": "inventory",
	"看技能": "skills", "技能树": "skills",
	"看关系": "relations", "人脉": "relations",
	"看地图": "map", "地图": "map",
	"看资产": "finance", "财务": "finance",
	"看工作": "career", "职业": "career",
	"看成就": "achievements", "图鉴": "achievements",
	"看家族史": "family", "族谱": "family",
	"看经营": "business", "经营": "business",
	"看组织": "organizations", "组织": "organizations",
	"看案件": "legal", "法律": "legal",
	"看灾害": "rescue", "救援": "rescue",
	"看环保": "environment", "碳": "environment",
	"看市政": "municipal", "市政": "municipal",
	"看债务": "debt", "催收": "debt",
	"看维权": "consumer", "消费投诉": "consumer",
	"看福利": "welfare", "社保": "welfare",
	"看殡葬": "funeral", "丧葬": "funeral",
	"看玄学": "metaphysics", "命理": "metaphysics",
	"看医疗": "medical", "病历": "medical",
	"看文娱": "content_industry", "版权": "content_industry",
	"看工程": "engineering", "在建": "engineering",
	"看服务": "services", "生活服务": "services",
	"看交通": "transport_infra", "班次": "transport_infra",
	"看家庭": "household", "宠物": "household",
	"看体育": "sports", "赛事": "sports",
	"看活动": "events", "展会": "events",
	"看奖项": "awards", "荣誉": "awards",
	"看数字": "digital", "平台": "digital",
	"看疫情": "epidemic", "公共卫生": "epidemic",
	"看军旅": "war", "前线": "war",
	"看行情": "market", "宏观": "market",
	"看天气": "weather", "预报": "weather",
	"看异常": "anomaly", "异常图鉴": "anomaly",
	"看系统": "goldfinger", "金手指": "goldfinger",
	"看设置": "settings", "设置": "settings",
}

func _ready() -> void:
	_parser = ParserScript.new()
	_narrator = NarratorScript.new()
	_init_simulation()
	_time_driver = TimeDriverScript.new()
	_auto_time = _auto_time_supported()
	_palette = PaletteScript.new()
	_theme_manager = ThemeManagerScript.new()
	_theme_manager.apply_to(self)
	_panel_registry = PanelRegistryScript.new()
	_dialog_registry = DialogRegistryScript.new()
	_history = HistoryViewScript.new()
	_notifications = NotificationCenterScript.new()
	_connect_nodes()
	_build_actions()
	_ensure_drawer_row()
	_build_panel_buttons()
	_ensure_dialog_layer()
	refresh_status()
	append_message("浮生录：输入中文指令开始你的一生。", "info")

func _connect_nodes() -> void:
	if is_instance_valid(_send_button):
		_send_button.pressed.connect(_on_send)
	if is_instance_valid(_input):
		_input.text_submitted.connect(_on_submit_text)
	if is_instance_valid(_pause_button):
		_pause_button.pressed.connect(_on_pause)
	if is_instance_valid(_messages_scroll):
		_messages_scroll.get_v_scroll_bar().value_changed.connect(_on_history_scrolled)

## 外部（如事件结算、面板）可注入执行器；无执行器时仅回显解析意图。
func set_command_handler(handler: Callable) -> void:
	_command_handler = handler

# --- 玩法接线（任务 3/4/23） ---

## 挂载玩法接线层：SimHost 绑定 GameState，IntentExecutor 作为指令执行器。
## Autoload（GameState）缺失时跳过，保证 headless/单元加载不报错。
func _init_simulation() -> void:
	var game = get_node_or_null("/root/GameState")
	if game == null:
		return
	var seed: int = int(game.meta.get("seed", 0)) if game.meta is Dictionary else 0
	_sim = SimHostScript.new(game, seed)
	_executor = ExecutorScript.new(_sim)
	set_command_handler(_on_intent)

# --- 挂机实时世界（R1 / M0） ---

## 实时推进仅在真实窗口运行；headless（测试/CI）下关闭，保证测试确定性。
func _auto_time_supported() -> bool:
	return DisplayServer.get_name() != "headless"

## 供测试或设置显式开关实时推进。
func set_auto_time(enabled: bool) -> void:
	_auto_time = enabled
	if not enabled and _time_driver != null:
		_time_driver.reset()

func auto_time_enabled() -> bool:
	return _auto_time

## 每帧按「现实增量 × 倍速」推进游戏内时钟与生理，并刷新状态栏。
func _process(delta: float) -> void:
	if not _auto_time or _sim == null or _time_driver == null:
		return
	if _sim.is_dead():
		return
	var speed = get_node_or_null("/root/SpeedController")
	if speed == null:
		return
	var minutes: int = _time_driver.consume(int(speed.get_speed()), delta)
	if minutes > 0:
		_advance_realtime(speed, minutes)

## 推进实时分钟；尊重快进目标（到达即停）、派发分层 tick、处理死亡/濒死中断。
func _advance_realtime(speed, minutes: int) -> void:
	var cap: int = minutes
	var target := int(speed.target_minutes())
	if target >= 0:
		var remain: int = target - _sim.now_minutes()
		if remain <= 0:
			speed.clear_target()
			speed.set_speed(1)
			return
		cap = mini(minutes, remain)
	var result: Dictionary = _sim.advance(cap)
	var scheduler = get_node_or_null("/root/TickScheduler")
	if scheduler != null:
		scheduler.tick(_sim.now_minutes())
	_apply_clock()
	_handle_time_events(result, speed)
	if target >= 0 and _sim.now_minutes() >= target:
		speed.clear_target()
		speed.set_speed(1)
	refresh_status()

## 实时推进产生的事件：死亡/濒死即暂停并提示（R1 健康危机中断）。
func _handle_time_events(result: Dictionary, speed) -> void:
	for e in result.get("events", []):
		if typeof(e) != TYPE_DICTIONARY:
			continue
		match String((e as Dictionary).get("type", "")):
			"death":
				append_message("你走到了生命的尽头。", "danger")
				speed.set_speed(0)
			"dying":
				append_message("你已油尽灯枯，随时可能离世。", "warning")
				speed.set_speed(0)

## 指令意图执行：落到模拟系统，回显叙事、推进时钟、打开面板、处理元动作。
func _on_intent(intent) -> void:
	if _executor == null:
		return
	var result: Dictionary = _executor.execute(intent)
	if not bool(result.get("ok", false)):
		append_message(String(result.get("error", "执行失败")), "danger")
		refresh_status()
		return
	for line in result.get("narration", []):
		append_message(String(line), "info")
	if int(result.get("minutes", 0)) > 0:
		_apply_clock()
	var pid := String(result.get("panel", ""))
	if pid != "":
		open_panel(pid)
	var action := String(result.get("action", ""))
	if action != "":
		_handle_action(action)
	refresh_status()

## 把游戏内时钟（GameState.clock.absolute_minutes）镜像到 WorldClock 供日历展示。
func _apply_clock() -> void:
	var game = get_node_or_null("/root/GameState")
	if game == null or not (game.clock is Dictionary):
		return
	var clock = get_node_or_null("/root/WorldClock")
	if clock != null:
		clock.set_minutes(int(game.clock.get("absolute_minutes", 0)))

func _handle_action(action: String) -> void:
	match action:
		"save":
			_do_save()
		"load":
			_do_load()
		"pause":
			_on_pause()
		"speed":
			_on_speed()
		"restart":
			append_message("重开新的一生请在「设置」面板确认。", "warning")
		_:
			pass

func _save_manager_instance():
	if _save_manager == null:
		_save_manager = SaveManagerScript.new("user://saves")
	return _save_manager

func _do_save() -> void:
	var game = get_node_or_null("/root/GameState")
	if game == null:
		append_message("当前无游戏状态，无法存档。", "danger")
		return
	var r: Dictionary = _save_manager_instance().save("1", game.to_dict())
	if bool(r.get("ok", false)):
		append_message("已存档到槽位 1。", "success")
	else:
		append_message("存档失败：%s" % String(r.get("error", "")), "danger")

func _do_load() -> void:
	var r: Dictionary = _save_manager_instance().load("1")
	if not bool(r.get("ok", false)):
		append_message("读档失败：%s" % String(r.get("error", "")), "danger")
		return
	var game = get_node_or_null("/root/GameState")
	if game == null:
		return
	game.from_dict(r["doc"])
	# 重新绑定模拟层到载入后的状态，并同步时钟。
	_init_simulation()
	_apply_clock()
	refresh_status()
	append_message("已读取槽位 1。", "success")

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
		# 未知动词或多义候选：提示用户；其余（对象未链接目录）交给执行器按名称回退处理。
		if not intent.options.is_empty() or String(intent.verb) == "":
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
	return {"slots": {}, "recent": [], "catalogs": _catalogs()}

## 由玩法接线层导出解析目录（物品/技能/岗位），让对象能链接到具体 id。
func _catalogs() -> Dictionary:
	if _sim == null:
		return {}
	return {
		"item": _catalog_entries(_sim.items),
		"skill": _catalog_entries(_sim.skills),
	}

func _catalog_entries(system) -> Array:
	var out: Array = []
	for idv in system.ids():
		var d: Dictionary = system.get_def(String(idv))
		out.append({"id": String(idv), "name": String(d.get("name", ""))})
	return out

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
	_animate_drawer(drawer)
	return true

## 抽屉入场动效；减少动态时直接显示（R59 减少动态）。
func _animate_drawer(panel: Control) -> void:
	if not is_instance_valid(panel):
		return
	if _theme_manager.reduce_motion():
		panel.modulate.a = 1.0
		return
	panel.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(panel, "modulate:a", 1.0, 0.12)

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
	var data: Dictionary = PanelContentScript.build(id, _current_player(), Callable(), _panel_context())
	if bool(data.get("empty", false)):
		var hint := Label.new()
		hint.text = String(data.get("empty_hint", ""))
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.add_theme_color_override("font_color", _theme_manager.color("color.text.disabled"))
		container.add_child(hint)
	else:
		for section in data.get("sections", []):
			var section_title := Label.new()
			section_title.text = String(section.get("title", ""))
			container.add_child(section_title)
			for row in section.get("rows", []):
				container.add_child(_row_node(String(row.get("label", "")), String(row.get("value", ""))))
			container.add_child(HSeparator.new())
	if id == "settings":
		_build_settings_controls(container)

## 设置面板的实时预览控件：切主题/配色/主色即时重生成 Theme 并刷新抽屉（ui.md 10）。
func _build_settings_controls(container: VBoxContainer) -> void:
	container.add_child(HSeparator.new())
	var label := Label.new()
	label.text = "外观调整（实时预览）"
	container.add_child(label)
	container.add_child(_option_row("主题", ["dark", "light"], ["暗色", "亮色"], _theme_manager.scheme, "scheme"))
	container.add_child(_option_row(
		"配色", ["default", "high_contrast", "colorblind"], ["默认", "高对比", "色盲友好"],
		_theme_manager.variant, "variant"))
	container.add_child(_option_row(
		"主色", ["cinnabar", "daiqing", "indigo", "ochre", "jade"], ["朱砂", "黛青", "花青", "赭石", "石绿"],
		_theme_manager.accent, "accent"))
	var motion := CheckButton.new()
	motion.text = "减少动态"
	motion.button_pressed = _theme_manager.reduce_motion()
	motion.toggled.connect(func(on: bool) -> void:
		_theme_manager.set_reduce_motion(on)
		_apply_theme())
	container.add_child(motion)
	var restore := Button.new()
	restore.text = "恢复默认"
	restore.pressed.connect(func() -> void: _restore_defaults())
	container.add_child(restore)

func _restore_defaults() -> void:
	_theme_manager.reset_defaults()
	_apply_theme()

func _option_row(label_text: String, values: Array, titles: Array, current: String, kind: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	row.add_child(label)
	for i in values.size():
		var value: String = String(values[i])
		var button := Button.new()
		button.text = String(titles[i])
		button.toggle_mode = true
		button.button_pressed = value == current
		button.pressed.connect(func() -> void: _apply_theme_setting(kind, value))
		row.add_child(button)
	return row

func _apply_theme_setting(kind: String, value: String) -> void:
	match kind:
		"scheme":
			_theme_manager.set_scheme(value)
		"variant":
			_theme_manager.set_variant(value)
		"accent":
			_theme_manager.set_accent(value)
	_apply_theme()

func _apply_theme() -> void:
	_theme_manager.apply_to(self)
	_refresh_panel("settings")

func _refresh_panel(id: String) -> void:
	if not _drawers.has(id) or not is_instance_valid(_drawer_row):
		return
	var old = _drawers[id]
	if is_instance_valid(old):
		old.queue_free()
	_drawers.erase(id)
	var drawer := _build_drawer(id)
	_drawer_row.add_child(drawer)
	_drawers[id] = drawer

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

## 面板外部上下文：世界增量、宏观行情、天气、疫情、区域/行程（地图）与当前设置摘要。
func _panel_context() -> Dictionary:
	var context: Dictionary = {"settings": _settings_summary()}
	var game = get_node_or_null("/root/GameState")
	if game != null:
		var world: Dictionary = game.world_delta if game.world_delta is Dictionary else {}
		context["world_delta"] = world
		context["regions"] = world.get("regions", [])
		context["epidemic"] = world.get("epidemic", [])
		var player: Dictionary = game.player if game.player is Dictionary else {}
		context["itineraries"] = player.get("itineraries", [])
	if _sim != null:
		if _sim.economy != null:
			context["macro"] = _sim.economy.macro
		var regions_view: Array = _sim.regions_view()
		if not regions_view.is_empty():
			context["regions"] = regions_view
		context["current_region"] = _sim.current_region_id()
		var w: Dictionary = _sim.weather_now()
		if not w.is_empty():
			context["weather"] = w
	return context

func _settings_summary() -> Dictionary:
	return {
		"scheme": _theme_manager.scheme,
		"variant": _theme_manager.variant,
		"accent": _theme_manager.accent,
		"ui_scale": _theme_manager.ui_scale,
		"body_font_scale": _theme_manager.body_font_scale(),
		"reduce_motion": _theme_manager.reduce_motion(),
	}

# --- 关键弹窗（任务 47/51） ---

## 弹窗覆盖层：遮罩 + 居中面板，层级高于侧边抽屉（ui.md 3）。
func _ensure_dialog_layer() -> void:
	if is_instance_valid(_dialog_layer):
		return
	_dialog_layer = Control.new()
	_dialog_layer.name = "DialogLayer"
	_dialog_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dialog_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_dialog_layer)
	var shade := ColorRect.new()
	shade.color = _theme_manager.color("color.bg.overlay")
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	_dialog_layer.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dialog_layer.add_child(center)
	_dialog_box = PanelContainer.new()
	_dialog_box.custom_minimum_size = Vector2(420, 0)
	center.add_child(_dialog_box)
	_dialog_layer.visible = false

func _dialog_title(id: String) -> String:
	return String((DialogRegistryScript.DIALOGS.get(id, {}) as Dictionary).get("title", id))

## 打开关键弹窗。已有模态时返回 modal_busy；危险弹窗返回 needs_confirm。
func open_dialog(id: String, payload: Dictionary = {}) -> Dictionary:
	if _dialog_registry == null:
		return {"ok": false, "reason": "no_registry"}
	var result: Dictionary = _dialog_registry.open(id, payload)
	if not bool(result.get("ok", false)):
		return result
	_ensure_dialog_layer()
	_render_dialog(id, payload)
	return result

func _render_dialog(id: String, payload: Dictionary) -> void:
	for child in _dialog_box.get_children():
		child.queue_free()
	var column := VBoxContainer.new()
	_dialog_box.add_child(column)
	var title := Label.new()
	title.text = _dialog_title(id)
	column.add_child(title)
	column.add_child(HSeparator.new())
	for key in payload.keys():
		column.add_child(_row_node(str(key), str(payload[key])))
	column.add_child(HSeparator.new())
	var actions := HBoxContainer.new()
	column.add_child(actions)
	var needs_confirm := bool((DialogRegistryScript.DIALOGS.get(id, {}) as Dictionary).get("confirm", false))
	if needs_confirm and not _dialog_registry.is_confirmed():
		var confirm_button := Button.new()
		confirm_button.text = "确认"
		confirm_button.pressed.connect(func() -> void: confirm_dialog())
		actions.add_child(confirm_button)
	var dismissible := bool((DialogRegistryScript.DIALOGS.get(id, {}) as Dictionary).get("dismissible", true))
	var close_button := Button.new()
	close_button.text = "关闭"
	close_button.disabled = not dismissible
	close_button.pressed.connect(func() -> void: close_dialog())
	actions.add_child(close_button)
	_dialog_layer.visible = true

func confirm_dialog() -> Dictionary:
	if _dialog_registry == null:
		return {"ok": false, "reason": "no_registry"}
	var result: Dictionary = _dialog_registry.confirm()
	if bool(result.get("ok", false)):
		_dialog_registry.close()
		_hide_dialog()
	return result

func close_dialog(force: bool = false) -> Dictionary:
	if _dialog_registry == null:
		return {"ok": false, "reason": "no_registry"}
	var result: Dictionary = _dialog_registry.close(force)
	if bool(result.get("ok", false)):
		_hide_dialog()
	return result

func _hide_dialog() -> void:
	if is_instance_valid(_dialog_box):
		for child in _dialog_box.get_children():
			child.queue_free()
	if is_instance_valid(_dialog_layer):
		_dialog_layer.visible = false

func has_dialog() -> bool:
	return _dialog_registry != null and _dialog_registry.is_open()

func current_dialog() -> String:
	return "" if _dialog_registry == null else _dialog_registry.current()

# --- 叙事流 ---

## 追加一条消息，按类型着色并附非颜色线索（R35.7、R59.5）。
func append_message(text: String, type: String = "info", markers: Array = []) -> void:
	if not is_instance_valid(_message_list):
		return
	var render := {"text": text, "markers": markers}
	_append_render(render, type)

## 追加一条内联水墨插画（R35、R57）；缺资源时回退占位留白。
func append_illustration(key: String, caption: String = "") -> Dictionary:
	if not is_instance_valid(_message_list):
		return {}
	var info: Dictionary = IllustrationScript.resolve(key, caption)
	var render := {"text": String(info["caption"]), "markers": [], "illustration": info}
	_append_render(render, "illustration" if bool(info["available"]) else "info")
	return info

func _append_render(render: Dictionary, type: String) -> void:
	if _history == null:
		_history = HistoryViewScript.new()
	_history.append({"render": render, "type": type})
	if _history.count() > VIRTUAL_THRESHOLD:
		_render_history_window(true)
	else:
		_message_list.add_child(_make_label(render, type))
		_scroll_to_bottom()

## 构建单条消息控件。
func _make_label(render: Dictionary, type: String) -> RichTextLabel:
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
	return label

## 窗口化渲染：仅实例化当前可见窗口内的行，用上下占位块保持滚动几何（超长会话）。
func _render_history_window(to_bottom: bool = false) -> void:
	if not is_instance_valid(_message_list):
		return
	for c in _message_list.get_children():
		_message_list.remove_child(c)
		c.queue_free()
	var vh: float = _messages_scroll.size.y if is_instance_valid(_messages_scroll) else 400.0
	var top: float = _messages_scroll.get_v_scroll_bar().value if is_instance_valid(_messages_scroll) else 0.0
	if to_bottom:
		top = _history.total_height(EST_ROW_HEIGHT)
	top = _history.clamp_scroll(top, vh, EST_ROW_HEIGHT)
	var win: Dictionary = _history.visible_window(top, vh, EST_ROW_HEIGHT)
	var start: int = int(win["start"])
	var end: int = int(win["end"])
	if start > 0:
		_message_list.add_child(_spacer(float(start) * EST_ROW_HEIGHT))
	for i in range(start, end):
		var row: Dictionary = _history.row_at(i)
		_message_list.add_child(_make_label(row.get("render", {}), String(row.get("type", "info"))))
	var tail: int = _history.count() - end
	if tail > 0:
		_message_list.add_child(_spacer(float(tail) * EST_ROW_HEIGHT))
	if to_bottom and is_instance_valid(_messages_scroll):
		call_deferred("_scroll_to_bottom")

func _spacer(height: float) -> Control:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, height)
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return s

func _scroll_to_bottom() -> void:
	if is_instance_valid(_messages_scroll):
		_messages_scroll.scroll_vertical = int(_messages_scroll.get_v_scroll_bar().max_value)

func _on_history_scrolled(_value: float) -> void:
	if _history != null and _history.count() > VIRTUAL_THRESHOLD:
		_render_history_window(false)

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

# --- 通知与托盘（任务 47 收尾）---

## 触发一条分类通知：投递系统通知；未聚焦时并入游戏内角标（返回结果字典）。
func notify(category: String, title: String, body: String = "", panel: String = "") -> Dictionary:
	if _notifications == null:
		_notifications = NotificationCenterScript.new()
	var r: Dictionary = _notifications.notify(category, title, body, panel)
	if bool(r.get("sent", false)) and bool(r.get("queued", false)):
		append_message("[%s] %s" % [title, body], "info")
	return r

## 应用窗口聚焦状态：聚焦时排空排队通知。
func set_focused(value: bool) -> void:
	if value:
		for item in _notifications.focus():
			append_message("[%s] %s" % [String(item.get("title", "")), String(item.get("body", ""))], "info")
	else:
		_notifications.blur()

func set_tray_enabled(value: bool) -> void:
	_notifications.set_tray_enabled(value)

func tray_enabled() -> bool:
	return bool(_notifications.prefs.tray_enabled)

func notification_center():
	return _notifications

func history():
	return _history

func _on_pause() -> void:
	var speed = get_node_or_null("/root/SpeedController")
	if speed == null:
		return
	speed.set_speed(0 if not speed.is_paused() else 1)
	refresh_status()
