class_name ThemeTokens
extends RefCounted
## 设计 token 单一真源（R35、R57、R59；任务 47）。
##
## 所有视觉常量集中在此，组件内禁止硬编码（见 theme_lint.gd）。
## 三套无障碍方案（default/high_contrast/colorblind）× 亮/暗双主题，共用语义 token 名；
## 主题色可定制并派生 hover/active/disabled 态。纯逻辑，headless 可测。

const SCHEMES: Array[String] = ["dark", "light"]
const VARIANTS: Array[String] = ["default", "high_contrast", "colorblind"]

## 主色可选名（设置页选择）。
const ACCENTS: Dictionary = {
	"cinnabar": "#C0392B",   # 朱砂
	"daiqing": "#2E6E79",    # 黛青
	"indigo": "#33556E",     # 花青
	"ochre": "#B7791F",      # 赭石
	"jade": "#2F7D5B",       # 石绿
}

## 全部颜色 token 名。组件只能引用这些键。
const COLOR_TOKENS: Array[String] = [
	"color.bg.base", "color.bg.panel", "color.bg.elevated", "color.bg.overlay",
	"color.text.primary", "color.text.secondary", "color.text.disabled", "color.text.inverse",
	"color.border", "color.border.focus",
	"color.accent", "color.accent.hover", "color.accent.active", "color.accent.disabled",
	"color.state.info", "color.state.success", "color.state.warning", "color.state.danger",
]

const SPACE: Dictionary = {"space.xs": 4, "space.sm": 8, "space.md": 16, "space.lg": 24, "space.xl": 40}
const RADIUS: Dictionary = {"radius.sm": 3, "radius.md": 6, "radius.lg": 12}
const SHADOW: Dictionary = {"shadow.panel": 8, "shadow.modal": 24}
const FONT_SIZE: Dictionary = {
	"font.size.caption": 12, "font.size.body": 15, "font.size.title": 20, "font.size.headline": 28,
}
const FONT_FAMILY: Dictionary = {"font.family.body": "思源黑体", "font.family.title": "思源宋体"}

## 正文/大字号 WCAG 对比度下限。
const CONTRAST_BODY_MIN: float = 4.5
const CONTRAST_LARGE_MIN: float = 3.0

const _PALETTES: Dictionary = {
	"dark": {
		"default": {
			"bg.base": "#14161A", "bg.panel": "#1C2026", "bg.elevated": "#242A31", "bg.overlay": "#00000099",
			"text.primary": "#E8EAED", "text.secondary": "#B8BFC8", "text.disabled": "#6B7280", "text.inverse": "#14161A",
			"border": "#3A414B", "border.focus": "#FFB347",
			"accent": "#D9603F",
			"info": "#8AB4F8", "success": "#81C995", "warning": "#FDD663", "danger": "#F28B82",
		},
		"high_contrast": {
			"bg.base": "#000000", "bg.panel": "#000000", "bg.elevated": "#0A0A0A", "bg.overlay": "#000000CC",
			"text.primary": "#FFFFFF", "text.secondary": "#F0F0F0", "text.disabled": "#B0B0B0", "text.inverse": "#000000",
			"border": "#FFFFFF", "border.focus": "#FFFF00",
			"accent": "#FFD400",
			"info": "#66CCFF", "success": "#66FF66", "warning": "#FFFF66", "danger": "#FF6666",
		},
		"colorblind": {
			"bg.base": "#14181C", "bg.panel": "#1B2026", "bg.elevated": "#232A31", "bg.overlay": "#00000099",
			"text.primary": "#F2F2F2", "text.secondary": "#C8CDD2", "text.disabled": "#7A828A", "text.inverse": "#14181C",
			"border": "#4A5560", "border.focus": "#56B4E9",
			"accent": "#E69F00",
			"info": "#56B4E9", "success": "#009E73", "warning": "#F0E442", "danger": "#D55E00",
		},
	},
	"light": {
		"default": {
			"bg.base": "#F5F1E8", "bg.panel": "#FFFDF7", "bg.elevated": "#FFFFFF", "bg.overlay": "#00000059",
			"text.primary": "#1F2328", "text.secondary": "#525A64", "text.disabled": "#9AA1AB", "text.inverse": "#FFFFFF",
			"border": "#D9D2C4", "border.focus": "#B3541E",
			"accent": "#A93226",
			"info": "#1A73E8", "success": "#1E7A3C", "warning": "#8A5A00", "danger": "#C0392B",
		},
		"high_contrast": {
			"bg.base": "#FFFFFF", "bg.panel": "#FFFFFF", "bg.elevated": "#FFFFFF", "bg.overlay": "#00000059",
			"text.primary": "#000000", "text.secondary": "#141414", "text.disabled": "#595959", "text.inverse": "#FFFFFF",
			"border": "#000000", "border.focus": "#0000CC",
			"accent": "#CC0000",
			"info": "#0000CC", "success": "#006600", "warning": "#7A5200", "danger": "#CC0000",
		},
		"colorblind": {
			"bg.base": "#F7F7F2", "bg.panel": "#FFFFFF", "bg.elevated": "#FFFFFF", "bg.overlay": "#00000059",
			"text.primary": "#1A1A1A", "text.secondary": "#4A4F55", "text.disabled": "#8A9098", "text.inverse": "#FFFFFF",
			"border": "#C9CEC4", "border.focus": "#0072B2",
			"accent": "#0072B2",
			"info": "#0072B2", "success": "#009E73", "warning": "#B26A00", "danger": "#D55E00",
		},
	},
}

static func schemes() -> Array:
	return SCHEMES.duplicate()

static func variants() -> Array:
	return VARIANTS.duplicate()

static func accent_names() -> Array:
	var names: Array = ACCENTS.keys()
	names.sort()
	return names

static func is_color_token(name: String) -> bool:
	return COLOR_TOKENS.has(name)

static func color_from(hex: String) -> Color:
	return Color.from_string(hex, Color.MAGENTA)

## 组装给定主题的完整颜色 token 字典（含派生态）。
static func colors(scheme: String = "dark", variant: String = "default", accent: String = "cinnabar") -> Dictionary:
	var s: String = scheme if SCHEMES.has(scheme) else "dark"
	var v: String = variant if VARIANTS.has(variant) else "default"
	var base: Dictionary = _PALETTES[s][v]
	var accent_hex: String = String(ACCENTS.get(accent, ACCENTS["cinnabar"]))
	# 无障碍方案下主色跟随方案语义色而非用户主色，保证对比度。
	if v != "default":
		accent_hex = String(base["accent"])
	var accent_color: Color = color_from(accent_hex)
	var out: Dictionary = {}
	for key in base.keys():
		if key in ["info", "success", "warning", "danger"]:
			out["color.state." + key] = color_from(String(base[key]))
		else:
			out["color." + key] = color_from(String(base[key]))
	out["color.accent"] = accent_color
	out["color.accent.hover"] = accent_color.lightened(0.18)
	out["color.accent.active"] = accent_color.darkened(0.18)
	out["color.accent.disabled"] = accent_color.lerp(color_from(String(base["text.disabled"])), 0.5)
	return out

## 非颜色 token。
static func metrics(reduce_motion: bool = false) -> Dictionary:
	var out: Dictionary = {}
	out.merge(SPACE)
	out.merge(RADIUS)
	out.merge(SHADOW)
	out.merge(FONT_SIZE)
	out.merge(FONT_FAMILY)
	out["motion.fast"] = 0.0 if reduce_motion else 0.12
	out["motion.normal"] = 0.0 if reduce_motion else 0.22
	out["motion.slow"] = 0.0 if reduce_motion else 0.4
	out["motion.ease.out"] = "ease_out"
	out["motion.reduce"] = reduce_motion
	return out

## 完整 token 集（颜色 + 度量）。
static func tokens(scheme: String = "dark", variant: String = "default", accent: String = "cinnabar", reduce_motion: bool = false) -> Dictionary:
	var out: Dictionary = colors(scheme, variant, accent)
	out.merge(metrics(reduce_motion))
	return out

## 对比度校验：正文/次级文本 vs 底色，返回违规列表（空表示通过）。
static func contrast_violations(scheme: String, variant: String, accent: String = "cinnabar") -> Array:
	var c: Dictionary = colors(scheme, variant, accent)
	var bg: Color = c["color.bg.base"]
	var violations: Array = []
	for token in ["color.text.primary", "color.text.secondary"]:
		var ratio: float = AccessibilityPalette.contrast_ratio(c[token], bg)
		if ratio < CONTRAST_BODY_MIN:
			violations.append({"token": token, "ratio": ratio, "min": CONTRAST_BODY_MIN})
	return violations
