extends "res://tests/test_base.gd"
## 叙事渲染与主界面壳测试（tasklist 5、5.1）：
## Narrator 变量/标记/条件/确定性、无障碍配色与非颜色线索、设置模型、开档模型，
## 以及关键 UI 场景在 headless 下可加载与实例化。

const NarratorScript = preload("res://sim/narrator.gd")
const TemplateScript = preload("res://sim/narrative_template.gd")
const PaletteScript = preload("res://ui/settings/accessibility_palette.gd")
const SettingsScript = preload("res://ui/settings/settings_model.gd")
const OnboardingScript = preload("res://ui/onboarding/onboarding_model.gd")

func _suite_name() -> String:
	return "narrator"

func run_tests() -> void:
	_test_narrator_variables()
	_test_narrator_markers()
	_test_narrator_conditions()
	_test_narrator_determinism()
	_test_narrative_template_resource()
	_test_palette_non_color_cues()
	_test_palette_colorblind_and_contrast()
	_test_settings_model()
	_test_onboarding_model()
	_test_ui_scenes_load()

# --- Narrator：变量渲染 ---

func _test_narrator_variables() -> void:
	var n = NarratorScript.new()
	var t := {"id": "t1", "conditions": {}, "texts": ["你好，{name}。今天{mood}。"], "variables": {"name": "无名", "mood": "平静"}}
	var r: Dictionary = n.render(t, {}, {"name": "张三"})
	check_eq(r["text"], "你好，张三。今天平静。", "变量渲染并合并模板默认值")
	check_eq(r["template_id"], "t1", "模板 id 回传")
	check_eq(n.render_text(t, {}, {"name": "李四"}), "你好，李四。今天平静。", "render_text 便捷接口")

# --- Narrator：可点击标记 ---

func _test_narrator_markers() -> void:
	var n = NarratorScript.new()
	var t := {"texts": ["你来到[[北京|location:loc_bj]]，遇到[[张三|person:npc_1]]。"], "conditions": {}}
	var r: Dictionary = n.render(t, {}, {})
	check_eq(r["text"], "你来到北京，遇到张三。", "标记文本剥离")
	var markers: Array = r["markers"]
	check_eq(markers.size(), 2, "标记数量")
	check_eq(markers[0]["label"], "北京", "标记一文本")
	check_eq(markers[0]["target"]["type"], "location", "标记一类型")
	check_eq(markers[0]["target"]["id"], "loc_bj", "标记一目标")
	check_eq(r["text"].substr(int(markers[0]["start"]), 2), "北京", "标记一位置正确")
	check_eq(markers[1]["target"]["id"], "npc_1", "标记二目标")

	# 对象变量自动生成标记。
	var obj := {"name": "张三", "type": "person", "id": "npc_9"}
	var r2: Dictionary = n.render({"texts": ["向{who}打招呼"], "conditions": {}}, {}, {"who": obj})
	check_eq(r2["text"], "向张三打招呼", "对象变量渲染为名称")
	check_eq((r2["markers"][0]["target"] as Dictionary)["id"], "npc_9", "对象变量生成标记")

# --- Narrator：条件选择 ---

func _test_narrator_conditions() -> void:
	var n = NarratorScript.new()
	var templates: Array = [
		{"id": "summer", "conditions": {"season": "summer"}, "texts": ["夏日炎炎。"]},
		{"id": "winter", "conditions": {"season": "winter"}, "texts": ["冬日凛冽。"]},
		{"id": "sad", "conditions": {"mood": {"min": 0, "max": 30}}, "texts": ["心情低落。"]},
	]
	check_eq(String(n.select(templates, {"season": "winter"}).get("id")), "winter", "按季节选模板")
	check_eq(String(n.select(templates, {"season": "summer"}).get("id")), "summer", "按季节选模板二")
	check_eq(String(n.select(templates, {"mood": 20}).get("id")), "sad", "数值区间条件")
	check(n.select(templates, {"season": "spring"}) == null, "无匹配返回空")

	# 文本变体内的条件。
	var t := {"conditions": {}, "texts": [
		{"conditions": {"weather": "rain"}, "text": "雨落。"},
		{"conditions": {"weather": "clear"}, "text": "放晴。"},
	]}
	check_eq(n.render_text(t, {"weather": "rain"}), "雨落。", "文本变体条件命中")
	check_eq(n.render_text(t, {"weather": "clear"}), "放晴。", "文本变体条件命中二")

# --- Narrator：确定性 ---

func _test_narrator_determinism() -> void:
	var n = NarratorScript.new()
	var t := {"conditions": {}, "texts": ["变体甲", "变体乙", "变体丙"]}
	var ctx := {"season": "summer", "mood": 50}
	var a: String = n.render_text(t, ctx, {"seed": 42})
	var b: String = n.render_text(t, ctx, {"seed": 42})
	check_eq(a, b, "同 seed 与上下文渲染一致")
	var set_of: Dictionary = {}
	for s in range(20):
		set_of[n.render_text(t, ctx, {"seed": s})] = true
	check(set_of.size() >= 2, "不同 seed 覆盖多个变体")

# --- NarrativeTemplate Resource ---

func _test_narrative_template_resource() -> void:
	var tpl = TemplateScript.new("tpl_login", {"season": "summer"}, ["登录成功。"], {})
	var n = NarratorScript.new()
	check_eq(n.render_text(tpl, {"season": "summer"}), "登录成功。", "Resource 模板可渲染")
	check_eq(String(tpl.to_dict()["id"]), "tpl_login", "Resource 转字典")

# --- 5.1 非颜色线索 ---

func _test_palette_non_color_cues() -> void:
	var p = PaletteScript.new()
	var types: Array = p.types()
	check(types.size() >= 8, "语义类型数量充足")
	var seen: Dictionary = {}
	for t in types:
		var cue: String = p.cue_for(String(t))
		var label: String = p.label_for(String(t))
		check(not cue.is_empty(), "类型 %s 有非颜色符号线索" % t)
		check(not label.is_empty(), "类型 %s 有类型标签" % t)
		check(not seen.has(cue), "非颜色符号线索唯一：%s" % cue)
		seen[cue] = true
	# 成败/警告等关键状态不依赖颜色区分。
	check(p.cue_for("danger") != p.cue_for("success"), "危险与成功线索不同")
	check(p.cue_for("warning") != p.cue_for("danger"), "警告与危险线索不同")

# --- 5.1 色盲配色与对比度 ---

func _test_palette_colorblind_and_contrast() -> void:
	var p = PaletteScript.new()
	check(p.set_mode("colorblind"), "可切换到色盲友好配色")
	var types: Array = p.types()
	for t in types:
		check(p.color_for(String(t)) != p.color_for("info") or String(t) == "info", "色盲配色有区分")
		check(not p.cue_for(String(t)).is_empty(), "色盲模式下仍保留非颜色线索")

	# 色盲方案关键色不应与默认完全一致（降低纯色相依赖，改走明度/蓝橙轴）。
	p.set_mode("default")
	var default_danger: Color = p.color_for("danger")
	p.set_mode("colorblind")
	var cb_danger: Color = p.color_for("danger")
	check(default_danger != cb_danger, "色盲方案替换关键色")

	# 高对比模式文字与背景对比度达到 WCAG AA 正文阈值。
	p.set_mode("high_contrast")
	var bg: Color = p.background()
	for t in types:
		var ratio: float = PaletteScript.contrast_ratio(p.color_for(String(t)), bg)
		check(ratio >= 4.5, "高对比 %s 对比度 %.2f >= 4.5" % [t, ratio])

# --- 设置模型 ---

func _test_settings_model() -> void:
	var s = SettingsScript.new()
	check_eq(s.set_font_scale(99.0), SettingsScript.FONT_SCALE_MAX, "字号上限 clamp")
	check_eq(s.set_font_scale(-1.0), SettingsScript.FONT_SCALE_MIN, "字号下限 clamp")
	check(s.set_theme_mode("colorblind"), "合法配色模式")
	check(not s.set_theme_mode("nope"), "非法配色模式拒绝")

	var conflict: Dictionary = s.bind("open_status", "i")
	check(not conflict["ok"], "键位冲突被拒绝")
	check_eq(String(conflict.get("conflict", "")), "open_backpack", "冲突动作回传")
	var ok: Dictionary = s.bind("open_status", "k")
	check(ok["ok"], "无冲突键位重映射成功")
	check_eq(s.key_for("open_status"), "k", "键位读取")

	check(not s.set_tts_enabled(true)["ok"], "无 TTS 时禁用并提示")
	check_eq(s.tts_status(), "不可用", "TTS 状态不可用")
	s.set_tts_available(true)
	check(s.set_tts_enabled(true)["ok"], "有 TTS 时可开启")
	check_eq(s.tts_status(), "已开启", "TTS 状态已开启")

	var data: Dictionary = s.to_dict()
	var s2 = SettingsScript.new()
	s2.from_dict(data)
	check_eq(s2.font_scale, s.font_scale, "设置往返字号")
	check_eq(s2.theme_mode, s.theme_mode, "设置往返配色")
	check_eq(s2.key_for("open_status"), "k", "设置往返键位")

# --- 开档模型 ---

func _test_onboarding_model() -> void:
	var m = OnboardingScript.new()
	check_eq(m.start_age, 18, "默认成年开局")
	check(m.set_start_mode("birth"), "可从出生开始")
	check_eq(m.start_age, 0, "出生开局年龄 0")
	m.set_start_mode("adult")

	check(m.select_talent("talent.quick_learner")["ok"], "选正特质成功")
	check_eq(m.remaining_points(), 1, "消耗 1 点")
	check(m.select_talent("talent.frail")["ok"], "选负特质成功")
	check_eq(m.remaining_points(), 2, "负特质返还点数")
	m.deselect_talent("talent.frail")
	m.deselect_talent("talent.quick_learner")

	check(m.select_talent("talent.quick_learner")["ok"], "再选正特质")
	check(m.select_talent("talent.strong_body")["ok"], "点数足够")
	check(not m.select_talent("talent.charming")["ok"], "点数不足拒绝")
	check(m.can_confirm(), "可确认开档")

	var t1: String = m.roll_family(12345)
	var t2: String = m.roll_family(12345)
	check_eq(t1, t2, "家境随机可复现")
	check(OnboardingScript.FAMILY_TIERS.has(t1), "家境落在合法档位")
	var b1: String = m.roll_birthplace(777)
	var b2: String = m.roll_birthplace(777)
	check_eq(b1, b2, "出生地随机可复现")
	check(OnboardingScript.BIRTHPLACES.has(b1), "出生地合法")

	check(m.should_show(false), "首个存档显示引导")
	check(not m.should_show(true), "非首档默认跳过")
	m.skipped = true
	check(not m.should_show(false), "跳过后不再显示")
	check(m.to_dict().has("appearance"), "开档模型含外貌占位结构")

# --- UI 场景 headless 加载 ---

func _test_ui_scenes_load() -> void:
	for path in ["res://ui/main.tscn", "res://ui/onboarding/onboarding.tscn", "res://ui/settings/settings.tscn"]:
		var scene = load(path)
		check(scene != null, "场景可加载：%s" % path)
		if scene == null:
			continue
		var inst = scene.instantiate()
		check(inst != null, "场景可实例化：%s" % path)
		if inst != null:
			inst.free()
