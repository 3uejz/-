extends "res://tests/test_base.gd"
## 主题系统测试（任务 47.1）：token 覆盖、对比度、主色派生、Theme 构建、无硬编码检查。

const TokensScript = preload("res://ui/theme/theme_tokens.gd")
const BuilderScript = preload("res://ui/theme/theme_builder.gd")
const LintScript = preload("res://ui/theme/theme_lint.gd")

func _suite_name() -> String:
	return "theme"

func run_tests() -> void:
	_test_token_coverage()
	_test_contrast_all_schemes()
	_test_accent_derivation()
	_test_builder_theme()
	_test_no_hardcoded_colors()

func _test_token_coverage() -> void:
	for scheme in TokensScript.schemes():
		for variant in TokensScript.variants():
			var c: Dictionary = TokensScript.colors(scheme, variant)
			for token in TokensScript.COLOR_TOKENS:
				check(c.has(token), "缺少 token %s (%s/%s)" % [token, scheme, variant])
	var m: Dictionary = TokensScript.metrics()
	for key in ["space.md", "radius.md", "font.size.body", "motion.normal"]:
		check(m.has(key), "缺少度量 token %s" % key)

func _test_contrast_all_schemes() -> void:
	for scheme in TokensScript.schemes():
		for variant in TokensScript.variants():
			var v: Array = TokensScript.contrast_violations(scheme, variant)
			check(v.is_empty(), "对比度不足 %s/%s: %s" % [scheme, variant, str(v)])

func _test_accent_derivation() -> void:
	var c1: Dictionary = TokensScript.colors("dark", "default", "cinnabar")
	var c2: Dictionary = TokensScript.colors("dark", "default", "jade")
	check(c1["color.accent"] != c2["color.accent"], "不同主色产生不同 accent")
	check(c1["color.accent.hover"].get_luminance() > c1["color.accent"].get_luminance(), "hover 比基色亮")
	check(c1["color.accent.active"].get_luminance() < c1["color.accent"].get_luminance(), "active 比基色暗")
	# 无障碍方案下主色固定为方案语义色。
	var hc: Dictionary = TokensScript.colors("dark", "high_contrast", "jade")
	check(hc["color.accent"] == TokensScript.colors("dark", "high_contrast", "cinnabar")["color.accent"], "无障碍方案忽略自定义主色")

func _test_builder_theme() -> void:
	var b = BuilderScript.new("light", "default")
	b.set_body_font_level(2)
	check(b.set_ui_scale(1.25), "合法缩放档")
	check(not b.set_ui_scale(1.33), "非法缩放档拒绝")
	var theme: Theme = b.build()
	check(theme != null, "构建 Theme")
	check_eq(theme.default_font_size, b.body_font_px(), "默认字号随正文档")
	check(theme.has_color("font_color", "Label"), "Label 字体色已设置")
	check(b.color("color.text.primary") == b.tokens()["color.text.primary"], "color 取 token")
	# 减少动态时动效时长归零。
	var br = BuilderScript.new()
	br.reduce_motion = true
	check_near(float(br.tokens()["motion.normal"]), 0.0, 1e-9, "减少动态归零")

func _test_no_hardcoded_colors() -> void:
	var violations: Array = LintScript.scan_dir("res://ui")
	var msgs: Array = []
	for v in violations:
		msgs.append("%s:%d %s" % [v["file"], v["line"], v["text"]])
	check(violations.is_empty(), "UI 存在硬编码颜色: %s" % "; ".join(msgs))
	# 白名单文件允许定义颜色。
	check(LintScript.is_allowlisted("res://ui/theme/theme_tokens.gd"), "token 真源在白名单")
	check(LintScript.scan_text("res://ui/x.gd", "var c = Color(1,0,0)").size() == 1, "非白名单检出硬编码")
