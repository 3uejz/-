class_name AccessibilityPalette
extends RefCounted
## 无障碍配色方案（R35、R57、R59）：默认 / 高对比 / 色盲友好三套。
## 每种语义消息除颜色外都带非颜色线索（符号 + 类型标签 + 字重），
## 保证不依赖色相也能区分（design.md「分级/状态等信息附非颜色线索」）。
## 纯逻辑，可在 headless 下单测。

const MODES: Array[String] = ["default", "high_contrast", "colorblind"]

## 语义类型及其非颜色线索（符号与中文标签，均唯一）。
const CUES: Dictionary = {
	"info": {"symbol": "※", "label": "信息", "weight": "normal"},
	"success": {"symbol": "√", "label": "成功", "weight": "normal"},
	"warning": {"symbol": "!", "label": "警告", "weight": "bold"},
	"danger": {"symbol": "×", "label": "危险", "weight": "bold"},
	"event": {"symbol": "★", "label": "事件", "weight": "normal"},
	"dialogue": {"symbol": "”", "label": "对话", "weight": "normal"},
	"money": {"symbol": "¥", "label": "金钱", "weight": "normal"},
	"health": {"symbol": "♥", "label": "健康", "weight": "bold"},
	"relation": {"symbol": "＆", "label": "关系", "weight": "normal"},
	"location": {"symbol": "◎", "label": "地点", "weight": "normal"},
}

const _COLORS: Dictionary = {
	"default": {
		"info": "#8ab4f8", "success": "#81c995", "warning": "#fdd663", "danger": "#f28b82",
		"event": "#c58af9", "dialogue": "#e8eaed", "money": "#fdd663", "health": "#f28b82",
		"relation": "#f8bbd0", "location": "#aecbfa",
	},
	"high_contrast": {
		"info": "#7fd4ff", "success": "#7dff7d", "warning": "#ffe066", "danger": "#ff6b6b",
		"event": "#d0a0ff", "dialogue": "#ffffff", "money": "#ffe066", "health": "#ff6b6b",
		"relation": "#ffb3d9", "location": "#a8d8ff",
	},
	# Okabe-Ito 色盲友好配色：以蓝-橙/明度轴为主，避免红绿对立。
	"colorblind": {
		"info": "#56b4e9", "success": "#009e73", "warning": "#f0e442", "danger": "#d55e00",
		"event": "#cc79a7", "dialogue": "#f2f2f2", "money": "#e69f00", "health": "#d55e00",
		"relation": "#cc79a7", "location": "#0072b2",
	},
}

const _BACKGROUNDS: Dictionary = {
	"default": "#1e1e1e",
	"high_contrast": "#000000",
	"colorblind": "#14181c",
}

var mode: String = "default"

func _init(p_mode: String = "default") -> void:
	set_mode(p_mode)

func modes() -> Array:
	return MODES.duplicate()

func set_mode(value: String) -> bool:
	if not MODES.has(value):
		return false
	mode = value
	return true

func background() -> Color:
	return Color.from_string(String(_BACKGROUNDS.get(mode, _BACKGROUNDS["default"])), Color.BLACK)

func color_for(type: String) -> Color:
	var table: Dictionary = _COLORS.get(mode, _COLORS["default"])
	var hex := String(table.get(type, _COLORS["default"].get("info", "#ffffff")))
	return Color.from_string(hex, Color.WHITE)

func cue_for(type: String) -> String:
	return String((CUES.get(type, {}) as Dictionary).get("symbol", ""))

func label_for(type: String) -> String:
	return String((CUES.get(type, {}) as Dictionary).get("label", type))

func weight_for(type: String) -> String:
	return String((CUES.get(type, {}) as Dictionary).get("weight", "normal"))

func types() -> Array:
	var keys: Array = CUES.keys()
	keys.sort()
	return keys

## 汇总样式：UI 直接消费颜色 + 非颜色线索，避免只用颜色表达状态。
func style_for(type: String) -> Dictionary:
	return {
		"type": type,
		"color": color_for(type),
		"background": background(),
		"cue": cue_for(type),
		"label": label_for(type),
		"weight": weight_for(type),
	}

# --- 对比度计算（WCAG 相对亮度） ---

static func relative_luminance(color: Color) -> float:
	return 0.2126 * _lin(color.r) + 0.7152 * _lin(color.g) + 0.0722 * _lin(color.b)

static func _lin(c: float) -> float:
	if c <= 0.03928:
		return c / 12.92
	return pow((c + 0.055) / 1.055, 2.4)

static func contrast_ratio(a: Color, b: Color) -> float:
	var la := relative_luminance(a)
	var lb := relative_luminance(b)
	var hi := maxf(la, lb)
	var lo := minf(la, lb)
	return (hi + 0.05) / (lo + 0.05)
