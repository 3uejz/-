extends Control
## 设置与无障碍界面（R34、R57、R59）：字号、对比/配色、TTS、倍速与动态过滤帮助。
## 逻辑在 SettingsModel 与 AccessibilityPalette，场景只做结构与接线。

const ModelScript = preload("res://ui/settings/settings_model.gd")

@onready var _font_scale: HSlider = $Panel/FontSection/FontScale
@onready var _font_value: Label = $Panel/FontSection/FontValue
@onready var _theme_option: OptionButton = $Panel/ThemeSection/ThemeOption
@onready var _tts_status: Label = $Panel/TTSSection/TTSStatus
@onready var _tts_button: CheckBox = $Panel/TTSSection/TTSButton
@onready var _speed_option: OptionButton = $Panel/SpeedSection/SpeedOption
@onready var _keys_list: VBoxContainer = $Panel/KeysSection/KeysList
@onready var _help_filter: CheckBox = $Panel/HelpSection/HelpFilter
@onready var _close_button: Button = $Panel/CloseButton

var model

func _ready() -> void:
	model = ModelScript.new()
	_setup()
	_connect_nodes()

func _setup() -> void:
	if is_instance_valid(_font_scale):
		_font_scale.min_value = ModelScript.FONT_SCALE_MIN
		_font_scale.max_value = ModelScript.FONT_SCALE_MAX
		_font_scale.step = 0.05
		_font_scale.value = model.font_scale
	if is_instance_valid(_theme_option):
		_theme_option.clear()
		for mode in ModelScript.PaletteScript.MODES:
			_theme_option.add_item(mode)
	if is_instance_valid(_speed_option):
		_speed_option.clear()
		for level in ModelScript.SPEED_LEVELS:
			_speed_option.add_item("%dx" % level)
		_speed_option.select(1)
	_build_keys()
	_refresh()

func _connect_nodes() -> void:
	if is_instance_valid(_font_scale):
		_font_scale.value_changed.connect(_on_font_changed)
	if is_instance_valid(_theme_option):
		_theme_option.item_selected.connect(_on_theme_selected)
	if is_instance_valid(_tts_button):
		_tts_button.toggled.connect(_on_tts_toggled)
	if is_instance_valid(_speed_option):
		_speed_option.item_selected.connect(_on_speed_selected)
	if is_instance_valid(_help_filter):
		_help_filter.toggled.connect(func(on: bool) -> void: model.set_revealed_abnormal(on))
	if is_instance_valid(_close_button):
		_close_button.pressed.connect(hide)

func _build_keys() -> void:
	if not is_instance_valid(_keys_list):
		return
	for action in model.keybindings.keys():
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = String(action)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var key_edit := LineEdit.new()
		key_edit.text = model.key_for(String(action))
		key_edit.text_submitted.connect(func(text: String) -> void: _on_key_remap(String(action), text))
		row.add_child(label)
		row.add_child(key_edit)
		_keys_list.add_child(row)

func _on_font_changed(value: float) -> void:
	model.set_font_scale(value)
	_refresh()

func _on_theme_selected(index: int) -> void:
	model.set_theme_mode(String(ModelScript.PaletteScript.MODES[index]))

func _on_tts_toggled(on: bool) -> void:
	var result: Dictionary = model.set_tts_enabled(on)
	if not bool(result.get("ok", false)):
		append_hint(String(result.get("message", "")), "warning")
	_refresh()

func _on_speed_selected(index: int) -> void:
	model.set_speed_level(int(ModelScript.SPEED_LEVELS[index]))

func _on_key_remap(action: String, key: String) -> void:
	var result: Dictionary = model.bind(action, key)
	if not result["ok"]:
		append_hint(String(result.get("error", "")), "warning")
	_refresh()

func append_hint(text: String, _type: String = "info") -> void:
	if is_instance_valid(_tts_status):
		_tts_status.tooltip_text = text

func _refresh() -> void:
	if is_instance_valid(_font_value):
		_font_value.text = "%.0f%%" % (model.font_scale * 100.0)
	if is_instance_valid(_tts_status):
		_tts_status.text = "文本朗读：%s" % model.tts_status()
	if is_instance_valid(_tts_button):
		_tts_button.disabled = not model.tts_available
		_tts_button.button_pressed = model.tts_enabled
