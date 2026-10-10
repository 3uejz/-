class_name ThemeManager
extends RefCounted
## 运行时主题管理器（R35、R57、R59；任务 47）。
## 持有亮/暗 × 无障碍方案、主色、缩放与正文档，生成 Godot Theme 并应用到 UI 根节点。
## 纯逻辑 + 一次性 apply，headless 可测；所有取色经 token，禁止硬编码。

const TokenScript = preload("res://ui/theme/theme_tokens.gd")
const BuilderScript = preload("res://ui/theme/theme_builder.gd")

var builder
var scheme: String = "dark"
var variant: String = "default"
var accent: String = "cinnabar"
var ui_scale: float = 1.0

func _init(p_scheme: String = "dark", p_variant: String = "default", p_accent: String = "cinnabar") -> void:
	scheme = p_scheme if TokenScript.SCHEMES.has(p_scheme) else "dark"
	variant = p_variant if TokenScript.VARIANTS.has(p_variant) else "default"
	accent = p_accent if TokenScript.ACCENTS.has(p_accent) else "cinnabar"
	builder = BuilderScript.new(scheme, variant)
	builder.accent = accent

# --- 主题维度 ---

func set_scheme(value: String) -> bool:
	if not TokenScript.SCHEMES.has(value):
		return false
	scheme = value
	builder.scheme = value
	return true

func set_variant(value: String) -> bool:
	if not TokenScript.VARIANTS.has(value):
		return false
	variant = value
	builder.variant = value
	return true

func set_accent(value: String) -> bool:
	if not TokenScript.ACCENTS.has(value):
		return false
	accent = value
	builder.accent = value
	return true

func set_reduce_motion(value: bool) -> void:
	builder.reduce_motion = value

func reduce_motion() -> bool:
	return builder.reduce_motion

func set_body_font_level(index: int) -> bool:
	return builder.set_body_font_level(index)

func body_font_px() -> int:
	return builder.body_font_px()

func set_ui_scale(value: float) -> bool:
	if not BuilderScript.UI_SCALES.has(value):
		return false
	ui_scale = value
	return true

# --- 取色与构建 ---

## 组件应经此取色，不得出现字面颜色（见 theme_lint.gd）。
func color(token_name: String) -> Color:
	return builder.color(token_name)

func tokens() -> Dictionary:
	return builder.tokens()

## 生成 Theme 资源；缩放档折入默认字号，保证缩放对全局文本生效。
func rebuild() -> Theme:
	var theme: Theme = builder.build()
	theme.default_font_size = int(round(float(builder.body_font_px()) * ui_scale))
	return theme

## 应用到 UI 根 Control，即时生效并向下级联。
func apply_to(root: Control) -> void:
	if root != null:
		root.theme = rebuild()

# --- 序列化 ---

func to_dict() -> Dictionary:
	return {
		"scheme": scheme,
		"variant": variant,
		"accent": accent,
		"ui_scale": ui_scale,
		"reduce_motion": builder.reduce_motion,
	}

func from_dict(data: Dictionary) -> void:
	set_scheme(String(data.get("scheme", "dark")))
	set_variant(String(data.get("variant", "default")))
	set_accent(String(data.get("accent", "cinnabar")))
	set_ui_scale(float(data.get("ui_scale", 1.0)))
	set_reduce_motion(bool(data.get("reduce_motion", false)))
