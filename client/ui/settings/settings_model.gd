class_name SettingsModel
extends RefCounted
## 设置与无障碍模型（R34、R57、R59）：字号、对比/配色、键位重映射、
## 文本朗读（TTS）、倍速与动态过滤帮助。纯逻辑，可在 headless 下单测。

const PaletteScript = preload("res://ui/settings/accessibility_palette.gd")

const FONT_SCALE_MIN: float = 0.75
const FONT_SCALE_MAX: float = 2.0
const FONT_SCALE_DEFAULT: float = 1.0

const SPEED_LEVELS: Array[int] = [0, 1, 2, 4, 60, 3600, 86400]

## 动作 -> 默认按键，作为键位重映射基线。
const DEFAULT_KEYS: Dictionary = {
	"toggle_pause": "space",
	"open_backpack": "i",
	"open_status": "c",
	"toggle_help": "f1",
	"send_command": "enter",
}

var font_scale: float = FONT_SCALE_DEFAULT
var theme_mode: String = "default"
var speed_level: int = 1
var revealed_abnormal: bool = false
var tts_enabled: bool = false
var tts_available: bool = false
var keybindings: Dictionary = {}
var last_message: String = ""

func _init() -> void:
	keybindings = DEFAULT_KEYS.duplicate(true)

# --- 字号 ---

func set_font_scale(value: float) -> float:
	font_scale = clampf(value, FONT_SCALE_MIN, FONT_SCALE_MAX)
	return font_scale

# --- 主题 / 配色 ---

func set_theme_mode(value: String) -> bool:
	var palette = PaletteScript.new()
	if not palette.set_mode(value):
		return false
	theme_mode = value
	return true

func palette():
	return PaletteScript.new(theme_mode)

func cycle_theme() -> String:
	var mode_list: Array = PaletteScript.MODES
	var idx: int = mode_list.find(theme_mode)
	theme_mode = String(mode_list[(idx + 1) % mode_list.size()])
	return theme_mode

# --- 倍速 ---

func set_speed_level(value: int) -> bool:
	if not SPEED_LEVELS.has(value):
		return false
	speed_level = value
	return true

# --- 动态过滤帮助 ---

func set_revealed_abnormal(value: bool) -> void:
	revealed_abnormal = value

func help_filter() -> Dictionary:
	return {"revealed_abnormal": revealed_abnormal}

# --- 键位重映射 ---

## 绑定动作到按键；若该键已被其他动作占用则拒绝并给出冲突动作。
func bind(action: String, key: String) -> Dictionary:
	var normalized := key.to_lower()
	if normalized.is_empty():
		return {"ok": false, "error": "按键不能为空"}
	for other in keybindings.keys():
		if String(keybindings[other]) == normalized and other != action:
			return {"ok": false, "error": "按键「%s」已绑定到「%s」" % [key, other], "conflict": other}
	keybindings[action] = normalized
	return {"ok": true, "error": ""}

func key_for(action: String) -> String:
	return String(keybindings.get(action, ""))

func reset_keys() -> void:
	keybindings = DEFAULT_KEYS.duplicate(true)

# --- 文本朗读（TTS） ---

func set_tts_available(value: bool) -> void:
	tts_available = value
	if not value:
		tts_enabled = false

## 平台无 TTS 时禁用并提示；可用时按需开关。
func set_tts_enabled(value: bool) -> Dictionary:
	if value and not tts_available:
		tts_enabled = false
		last_message = "当前平台未提供文本朗读（TTS），已保持关闭"
		return {"ok": false, "message": last_message}
	tts_enabled = value
	last_message = "文本朗读已开启" if value else "文本朗读已关闭"
	return {"ok": true, "message": last_message}

func tts_status() -> String:
	if not tts_available:
		return "不可用"
	return "已开启" if tts_enabled else "可开启"

# --- 序列化 ---

func to_dict() -> Dictionary:
	return {
		"font_scale": font_scale,
		"theme_mode": theme_mode,
		"speed_level": speed_level,
		"revealed_abnormal": revealed_abnormal,
		"tts_enabled": tts_enabled,
		"tts_available": tts_available,
		"keybindings": keybindings.duplicate(true),
	}

func from_dict(data: Dictionary) -> void:
	set_font_scale(float(data.get("font_scale", FONT_SCALE_DEFAULT)))
	set_theme_mode(String(data.get("theme_mode", "default")))
	set_speed_level(int(data.get("speed_level", 1)))
	revealed_abnormal = bool(data.get("revealed_abnormal", false))
	set_tts_available(bool(data.get("tts_available", false)))
	tts_enabled = bool(data.get("tts_enabled", false)) and tts_available
	var keys: Dictionary = data.get("keybindings", {})
	keybindings = DEFAULT_KEYS.duplicate(true)
	for k in keys.keys():
		keybindings[String(k)] = String(keys[k]).to_lower()
