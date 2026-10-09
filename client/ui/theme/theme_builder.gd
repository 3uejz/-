class_name ThemeBuilder
extends RefCounted
## 由 token 生成 Godot Theme 资源，运行时切换即时生效（R35、R57、R59；任务 47）。
## 组件统一从当前 Theme 取色，不硬编码。

const TokenScript = preload("res://ui/theme/theme_tokens.gd")

var scheme: String = "dark"
var variant: String = "default"
var accent: String = "cinnabar"
var reduce_motion: bool = false
var font_body_scale: float = 1.0
var ui_scale: float = 1.0

## 缩放档（ui.md 2.3）。
const UI_SCALES: Array[float] = [0.8, 0.9, 1.0, 1.1, 1.25, 1.5]
const BODY_FONT_LEVELS: Array[float] = [0.85, 1.0, 1.15, 1.3]

func _init(p_scheme: String = "dark", p_variant: String = "default") -> void:
	scheme = p_scheme
	variant = p_variant

func tokens() -> Dictionary:
	return TokenScript.tokens(scheme, variant, accent, reduce_motion)

func color(token_name: String) -> Color:
	var t: Dictionary = tokens()
	if t.has(token_name):
		return t[token_name]
	push_error("未定义的 token: %s" % token_name)
	return Color.MAGENTA

func set_ui_scale(value: float) -> bool:
	if not UI_SCALES.has(value):
		return false
	ui_scale = value
	return true

func set_body_font_level(index: int) -> bool:
	if index < 0 or index >= BODY_FONT_LEVELS.size():
		return false
	font_body_scale = BODY_FONT_LEVELS[index]
	return true

func body_font_px() -> int:
	var base: int = int(TokenScript.FONT_SIZE["font.size.body"])
	return int(round(float(base) * font_body_scale))

## 构建 Theme 资源：默认字号、全局色、常用控件的 StyleBox 与焦点样式。
func build() -> Theme:
	var t: Dictionary = tokens()
	var theme := Theme.new()
	theme.default_font_size = int(round(float(TokenScript.FONT_SIZE["font.size.body"]) * font_body_scale))

	# 全局默认字体色。
	theme.set_color("font_color", "Label", t["color.text.primary"])
	theme.set_color("font_color", "Button", t["color.text.primary"])
	theme.set_color("font_color", "LineEdit", t["color.text.primary"])
	theme.set_color("font_placeholder_color", "LineEdit", t["color.text.disabled"])
	theme.set_color("font_color", "RichTextLabel", t["color.text.primary"])

	# 面板/抽屉底。
	var panel := _flat(t["color.bg.panel"], int(t["radius.md"]))
	theme.set_stylebox("panel", "PanelContainer", panel)

	# 按钮三态 + 焦点。
	theme.set_stylebox("normal", "Button", _flat(t["color.bg.elevated"], int(t["radius.sm"])))
	theme.set_stylebox("hover", "Button", _flat(t["color.accent.hover"], int(t["radius.sm"])))
	theme.set_stylebox("pressed", "Button", _flat(t["color.accent.active"], int(t["radius.sm"])))
	theme.set_stylebox("disabled", "Button", _flat(t["color.accent.disabled"], int(t["radius.sm"])))
	theme.set_stylebox("focus", "Button", _focus_box(t["color.border.focus"]))

	# 输入框与焦点环。
	theme.set_stylebox("normal", "LineEdit", _flat(t["color.bg.base"], int(t["radius.sm"]), t["color.border"]))
	theme.set_stylebox("focus", "LineEdit", _focus_box(t["color.border.focus"]))
	return theme

func _flat(bg: Color, radius: int, border: Color = Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = float(TokenScript.SPACE["space.sm"])
	sb.content_margin_right = float(TokenScript.SPACE["space.sm"])
	sb.content_margin_top = float(TokenScript.SPACE["space.xs"])
	sb.content_margin_bottom = float(TokenScript.SPACE["space.xs"])
	if border.a > 0.0:
		sb.set_border_width_all(1)
		sb.border_color = border
	return sb

func _focus_box(color: Color) -> StyleBoxFlat:
	var sb := _flat(Color(0, 0, 0, 0), int(TokenScript.RADIUS["radius.sm"]))
	sb.set_border_width_all(2)
	sb.border_color = color
	return sb
