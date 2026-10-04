class_name Narrator
extends RefCounted
## 叙事渲染器（R32）：按 NarrativeTemplate 选择文本、渲染变量，并解析可点击标记。
## 纯逻辑、无 UI 依赖，可在 headless 下单测。
##
## 模板形态（兼容 Dictionary 与 Resource，字段见 design.md Data Models）：
##   conditions: 条件字典，支持等值、数组包含与 {min,max} 数值区间
##   texts:      文本变体数组，元素为 String 或 {conditions, text}
##   variables:  变量默认值字典
##
## 标记语法：`[[显示文本|type:id]]`，渲染后文本仅保留显示文本，
## 标记位置与目标以 markers 返回，供 UI 生成可点击链接。

const SplitMix64Script = preload("res://sim/rng.gd")

const MARK_OPEN := "[["
const MARK_CLOSE := "]]"
const MARK_SEP := "|"
const TARGET_SEP := ":"

var mode: String = "default"

## 在模板数组中按条件挑选一份模板（无匹配返回空）。
## 多份匹配时用 seed 与上下文做确定性选择（R32.2）。
func select(templates: Array, context: Dictionary = {}, seed: int = 0):
	var matched: Array = []
	for i in range(templates.size()):
		var t = templates[i]
		if _match_conditions(_field(t, "conditions", {}), context):
			matched.append(i)
	if matched.is_empty():
		return null
	var pick := _pick_index(matched.size(), context, seed)
	return templates[int(matched[pick])]

## 渲染一份模板（也接受模板数组，自动先选择）。
## 返回 {text, markers, template_id}；markers 元素为 {start, end, label, target:{type,id}}。
func render(template, context: Dictionary = {}, vars: Dictionary = {}) -> Dictionary:
	if template is Array:
		template = select(template, context, int(vars.get("seed", 0)))
	if template == null:
		return _empty_result()

	var defaults: Dictionary = _as_dict(_field(template, "variables", {}))
	var merged: Dictionary = defaults.duplicate(true)
	for k in vars.keys():
		merged[k] = vars[k]

	var texts: Array = _as_array(_field(template, "texts", []))
	if texts.is_empty():
		return _empty_result(String(_field(template, "id", "")))

	var raw: String = _select_text(texts, context, int(vars.get("seed", 0)))
	var filled: String = _substitute(raw, merged)
	var parsed: Dictionary = _parse_markers(filled)
	return {
		"text": String(parsed["text"]),
		"markers": parsed["markers"],
		"template_id": String(_field(template, "id", "")),
	}

## 便捷接口：只取渲染后的纯文本。
func render_text(template, context: Dictionary = {}, vars: Dictionary = {}) -> String:
	return String(render(template, context, vars)["text"])

# --- 文本选择 ---

func _select_text(texts: Array, context: Dictionary, seed: int) -> String:
	var candidates: Array = []
	for entry in texts:
		if entry is String:
			candidates.append(String(entry))
		elif entry is Dictionary:
			var cond: Dictionary = _as_dict(entry.get("conditions", {}))
			if _match_conditions(cond, context):
				candidates.append(String(entry.get("text", "")))
	if candidates.is_empty():
		# 无变体命中时回退到首个可用文本，保证叙事不中断。
		for entry in texts:
			if entry is String:
				return String(entry)
			if entry is Dictionary:
				return String(entry.get("text", ""))
		return ""
	var idx := _pick_index(candidates.size(), context, seed)
	return String(candidates[idx])

# --- 条件匹配 ---

func _match_conditions(conditions: Dictionary, context: Dictionary) -> bool:
	for key in conditions.keys():
		var want: Variant = conditions[key]
		if not context.has(key):
			return false
		var got: Variant = context[key]
		if want is Array:
			if not _in_array(want, got):
				return false
		elif want is Dictionary:
			if not _in_range(want, got):
				return false
		elif String(got) != String(want):
			return false
	return true

func _in_array(arr: Array, got: Variant) -> bool:
	for item in arr:
		if item is Dictionary and got is Dictionary and _dict_eq(item, got):
			return true
		if String(item) == String(got):
			return true
	return false

func _in_range(range: Dictionary, got: Variant) -> bool:
	var v := 0.0
	if got is float or got is int:
		v = float(got)
	else:
		return false
	if range.has("min") and v < float(range["min"]):
		return false
	if range.has("max") and v > float(range["max"]):
		return false
	return true

func _dict_eq(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for k in a.keys():
		if not b.has(k) or String(a[k]) != String(b[k]):
			return false
	return true

# --- 变量替换 ---

func _substitute(text: String, vars: Dictionary) -> String:
	var out := text
	for key in vars.keys():
		var token := "{%s}" % String(key)
		if out.find(token) < 0:
			continue
		out = out.replace(token, _value_token(vars[key]))
	return out

## 对象变量（含 name/type/id）自动转为可点击标记。
func _value_token(value: Variant) -> String:
	if value is Dictionary and value.has("name"):
		var type := String(value.get("type", ""))
		var id := String(value.get("id", ""))
		return "%s%s%s%s%s%s%s" % [MARK_OPEN, String(value["name"]), MARK_SEP, type, TARGET_SEP, id, MARK_CLOSE]
	return String(value)

# --- 标记解析 ---

func _parse_markers(text: String) -> Dictionary:
	var out := ""
	var markers: Array = []
	var i := 0
	var n := text.length()
	while i < n:
		if i + 2 <= n and text.substr(i, 2) == MARK_OPEN:
			var close := text.find(MARK_CLOSE, i + 2)
			if close >= 0:
				var inner := text.substr(i + 2, close - (i + 2))
				var label := inner
				var target_text := ""
				var sep := inner.find(MARK_SEP)
				if sep >= 0:
					label = inner.substr(0, sep)
					target_text = inner.substr(sep + 1)
				var start := out.length()
				out += label
				var end := out.length()
				markers.append({
					"start": start,
					"end": end,
					"label": label,
					"target": _parse_target(target_text),
				})
				i = close + 2
				continue
		out += text[i]
		i += 1
	return {"text": out, "markers": markers}

func _parse_target(text: String) -> Dictionary:
	var pos := text.find(TARGET_SEP)
	if pos < 0:
		return {"type": "", "id": text}
	return {"type": text.substr(0, pos), "id": text.substr(pos + 1)}

# --- 确定性选择 ---

func _pick_index(count: int, context: Dictionary, seed: int) -> int:
	if count <= 1:
		return 0
	var key := "%d|%s" % [seed, _context_key(context)]
	var rng = SplitMix64Script.new(key.hash())
	return int(rng.next_float() * float(count))

func _context_key(context: Dictionary) -> String:
	var keys: Array = context.keys()
	keys.sort()
	var parts: Array = []
	for k in keys:
		parts.append("%s=%s" % [String(k), str(context[k])])
	return ";".join(parts)

# --- 通用取值 ---

func _field(source, key: String, fallback: Variant) -> Variant:
	if source == null:
		return fallback
	if source is Dictionary:
		return (source as Dictionary).get(key, fallback)
	if source is Object and source.get(key) != null:
		return source.get(key)
	return fallback

func _as_dict(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}

func _as_array(value: Variant) -> Array:
	return value if value is Array else []

func _empty_result(id: String = "") -> Dictionary:
	return {"text": "", "markers": [], "template_id": id}
