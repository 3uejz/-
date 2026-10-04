class_name CommandParser
extends RefCounted
## 中文指令解析器：确定性、离线、纯本地。见 R27 与 design.md「指令解析与消歧」。
## 链路：归一 → 最长匹配分词 → 动词识别（别名归一）→ 类型化对象链接 →
## 参数槽填充 → 生成 CommandIntent；支持多义候选、复合指令、多槽上下文与代词还原。
##
## 说明：解析过程无随机；命令历史不影响解析结果（多义排序基于 context.recent）。

const VerbRegistryScript = preload("res://command/verb_registry.gd")
const CommandIntentScript = preload("res://command/command_intent.gd")
const CommandOptionScript = preload("res://command/command_option.gd")

const HISTORY_LIMIT: int = 20

## 助词：在对象解析完成后从残留文本中剥离，避免破坏对象名。
const _PARTICLES := "的了把在给"

## 标点：归一阶段移除；保留 ? 与 ! 以便别名匹配。
const _PUNCT := "，。、；：（）《》【】「」,.!;:()[]{}<>\"'"

const _FULLWIDTH := {
	"０": "0", "１": "1", "２": "2", "３": "3", "４": "4",
	"５": "5", "６": "6", "７": "7", "８": "8", "９": "9",
	"？": "?", "！": "!",
}

const _DIGITS := {"零": 0, "〇": 0, "一": 1, "二": 2, "两": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9}
const _CN_UNITS := {"十": 10, "百": 100, "千": 1000, "万": 10000, "亿": 100000000}
const _INDEX_CHARS := {"一": 1, "二": 2, "两": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9}

const _MONEY_UNITS := ["元", "块", "万元"]
const _DURATION_UNITS := ["秒", "分钟", "小时", "天", "周", "月", "年"]
const _COUNT_UNITS := ["个", "瓶", "斤", "份", "张", "只", "杯", "碗", "包", "件", "台", "部", "本", "支", "双", "公斤", "千克", "克", "千米", "公里", "米"]

const _TYPE_LABELS := {"item": "物品", "location": "地点", "person": "人物", "skill": "技能", "asset": "资产", "event": "事件", "vehicle": "交通工具"}

var _registry
var _number_re: RegEx
var _pending_options: Array = []       ## 待选择的 CommandOption
var _pending_verb: String = ""
var _pending_params: Dictionary = {}
var history: Array = []                ## 最近指令历史，最多 HISTORY_LIMIT 条

func _init() -> void:
	_registry = VerbRegistryScript.new()
	_number_re = RegEx.new()
	# 单位按长优先排列，保证「万元」先于「元」、「分钟」先于「钟」。
	_number_re.compile("([0-9]+|[零〇一二两三四五六七八九十百千万]+)(分钟|小时|万元|公斤|千克|千米|公里|天|年|月|周|秒|元|块|米|克|个|瓶|斤|份|张|只|杯|碗|包|件|台|部|本|支|双)?")

# --- 对外接口 ---

## 解析原始输入，返回 CommandIntent（失败时 ok=false 且给出原因/候选）。
func parse(raw: String, context: Dictionary = {}, source: String = "text"):
	# 上一轮多义未决时，纯序号输入直接选择。
	var selected = _try_select(raw, source)
	if selected != null:
		return selected
	# 复合指令：至多两段「A 然后 B」。
	var segs := _split_compound(raw)
	if segs.size() == 2:
		return _parse_compound(segs, context, source)
	return _parse_single(raw, context, source)

## 面板/快捷键等结构化入口：直接以规范动词与对象构造意图，保证同源。
func from_action(verb: String, objects: Array = [], params: Dictionary = {}, context: Dictionary = {}, source: String = "panel"):
	var it = CommandIntentScript.new()
	it.verb = verb
	for o in objects:
		if typeof(o) == TYPE_DICTIONARY:
			it.objects.append((o as Dictionary).duplicate(true))
	it.params = params.duplicate(true)
	it.source = source
	it.raw = verb
	it.ok = _registry.has(verb)
	if not it.ok:
		it.error = "未注册动词「%s」" % verb
	return it

## 前缀补全：合并动词与上下文对象。
func complete(prefix: String, context: Dictionary = {}) -> Array:
	var out: Array = []
	for v in _registry.complete_prefix(prefix, context):
		out.append({"type": "verb", "value": v, "label": v})
	var catalogs: Dictionary = context.get("catalogs", {})
	for t in catalogs.keys():
		var entries: Array = catalogs[t]
		if not (entries is Array):
			continue
		for e in entries:
			if typeof(e) != TYPE_DICTIONARY:
				continue
			var names: Array = [String(e.get("name", ""))]
			for a in e.get("aliases", []):
				names.append(String(a))
			for nm in names:
				if not nm.is_empty() and nm.begins_with(prefix):
					out.append({"type": String(t), "value": String(e.get("id", "")), "label": nm})
					break
	return out

## 按分类与情境动态生成帮助。
func help(category: String = "", context: Dictionary = {}) -> Array:
	return _registry.help(category, context)

func registry():
	return _registry

## 记录一条指令历史（去重相邻、上限 20）。
func record_history(raw: String) -> void:
	_record(raw)

# --- 单段解析 ---

func _parse_single(raw: String, context: Dictionary, source: String):
	var intent = CommandIntentScript.new()
	intent.raw = raw
	intent.source = source
	var s := _normalize(raw)
	if s.is_empty():
		intent.error = "请输入指令"
		return intent
	var vm: Dictionary = _registry.match_longest(s)
	if vm.is_empty():
		intent.error = _unrecognized_message(s)
		return intent
	var verb := String(vm["canonical"])
	intent.verb = verb
	var def: Dictionary = _registry.get_def(verb)
	var pos := int(vm["pos"])
	var length := int(vm["length"])
	var rest := s.substr(0, pos) + s.substr(pos + length)

	var resolved: Dictionary = _resolve_objects(def, rest, context)

	# 多义：列候选；若本次输入带尾部序号则直接选择。
	if not resolved["ambiguous"].is_empty():
		var options := _make_options(resolved["ambiguous"])
		var ti := _trailing_index(rest)
		if ti > 0 and ti <= options.size():
			_record(raw)
			return _intent_from_option(options, ti, verb, raw, source)
		intent.ok = false
		intent.error = "「%s」有多个含义，请用序号选择" % resolved["ambiguous"]["name"]
		intent.options = options
		_pending_options = options
		_pending_verb = verb
		_pending_params = {}
		return intent

	var residue := _erase_spans(rest, resolved["spans"])
	var ex: Dictionary = _extract_params(residue)
	intent.params = ex["params"]
	var leftover := _strip_particles(String(ex["residue"]))
	var unresolved := _strip_pronoun_tokens(leftover)

	var invalid := false
	var reason := ""
	if not unresolved.is_empty() and resolved["objects"].is_empty():
		invalid = true
		reason = "无法识别对象「%s」" % unresolved
	elif not unresolved.is_empty():
		intent.params["method"] = unresolved

	# 省略补全与代词还原：按动词声明的对象类型填充上下文槽。
	var preferred: Array = def.get("object_types", [])
	for t in preferred:
		if _has_type(resolved["objects"], String(t)):
			continue
		var e := _slot_for_type(String(t), context)
		if not e.is_empty():
			resolved["objects"].append(_object_from_entry(e, String(t)))
		elif not invalid:
			invalid = true
			reason = "请指定%s" % _type_label(String(t))

	intent.objects = resolved["objects"]
	intent.ok = not invalid
	intent.error = reason
	if intent.ok:
		_record(raw)
	return intent

# --- 复合指令 ---

func _parse_compound(segs: Array, context: Dictionary, source: String):
	var it = CommandIntentScript.new()
	it.verb = "然后"
	it.source = source
	it.raw = raw_join(segs)
	var first = _parse_single(String(segs[0]), context, source)
	it.parts.append(first)
	it.objects = first.objects
	it.params = first.params
	if not first.ok:
		it.ok = false
		it.error = "第一段失败：%s" % first.error
		return it
	var second = _parse_single(String(segs[1]), context, source)
	it.parts.append(second)
	if not second.ok:
		it.ok = false
		it.error = "第二段失败：%s" % second.error
		return it
	it.ok = true
	return it

func raw_join(segs: Array) -> String:
	return "%s然后%s" % [segs[0], segs[1]]

func _split_compound(raw: String) -> Array:
	for sep in ["然后", "之后"]:
		var idx := raw.find(sep)
		if idx > 0:
			var a := raw.substr(0, idx).strip_edges()
			var b := raw.substr(idx + sep.length()).strip_edges()
			if not a.is_empty() and not b.is_empty():
				return [a, b]
	return [raw]

# --- 多义候选与序号选择 ---

func _make_options(ambiguous: Dictionary) -> Array:
	var matches: Array = ambiguous["matches"]
	var opts: Array = []
	var limit: int = min(9, matches.size())
	for i in range(limit):
		var m: Dictionary = matches[i]
		opts.append(CommandOptionScript.new(i + 1, String(m["name"]), _object_from(m), "type=%s" % String(m["type"])))
	return opts

func _intent_from_option(options: Array, index: int, verb: String, raw: String, source: String):
	for opt in options:
		if int(opt.index) == index:
			var it = CommandIntentScript.new()
			it.verb = verb
			it.objects = [(opt.target as Dictionary).duplicate(true)]
			it.params = {}
			it.source = source
			it.raw = raw
			it.ok = true
			return it
	return null

func _try_select(raw: String, source: String):
	if _pending_options.is_empty():
		return null
	var s := _normalize(raw)
	var idx := _pure_index(s)
	if idx <= 0:
		_pending_options = []
		_pending_verb = ""
		_pending_params = {}
		return null
	var options: Array = _pending_options
	var verb := _pending_verb
	var params: Dictionary = _pending_params
	_pending_options = []
	_pending_verb = ""
	_pending_params = {}
	var it = _intent_from_option(options, idx, verb, raw, source)
	if it != null:
		it.params = params.duplicate(true)
		_record(raw)
	return it

# --- 对象解析 ---

func _resolve_objects(def: Dictionary, text: String, context: Dictionary) -> Dictionary:
	var catalogs: Dictionary = context.get("catalogs", {})
	var preferred: Array = def.get("object_types", [])
	var objects: Array = []
	var spans: Array = []
	var ambiguous: Dictionary = {}
	if preferred.is_empty():
		var types: Array = catalogs.keys()
		var best: Dictionary = _resolve_best_across(text, types, catalogs, context)
		if not best.is_empty():
			if best["matches"].size() > 1:
				ambiguous = best
			else:
				objects.append(_object_from(best["matches"][0]))
				spans.append({"pos": best["pos"], "length": best["length"]})
	else:
		for t in preferred:
			var r: Dictionary = _resolve_type(text, String(t), catalogs, context)
			if r.is_empty():
				continue
			if r["matches"].size() > 1:
				if ambiguous.is_empty():
					ambiguous = r
				continue
			objects.append(_object_from(r["matches"][0]))
			spans.append({"pos": r["pos"], "length": r["length"]})
	return {"objects": objects, "spans": spans, "ambiguous": ambiguous}

func _resolve_type(text: String, type: String, catalogs: Dictionary, context: Dictionary) -> Dictionary:
	var entries: Array = catalogs.get(type, [])
	if not (entries is Array):
		return {}
	var raw: Array = []
	for i in range(entries.size()):
		var e = entries[i]
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var names: Array = [String(e.get("name", ""))]
		for a in e.get("aliases", []):
			names.append(String(a))
		for nm in names:
			if nm.is_empty():
				continue
			var p := text.find(nm)
			if p < 0:
				continue
			raw.append({
				"entry": e, "type": type, "name": nm,
				"pos": p, "length": nm.length(),
				"rank": _recent_rank(e, context), "order": i,
			})
	if raw.is_empty():
		return {}
	var maxlen := 0
	for m in raw:
		maxlen = max(maxlen, int(m["length"]))
	var top: Array = []
	for m in raw:
		if int(m["length"]) == maxlen:
			top.append(m)
	return _finalize_matches(top, type)

func _resolve_best_across(text: String, types: Array, catalogs: Dictionary, context: Dictionary) -> Dictionary:
	var all: Array = []
	for t in types:
		var r: Dictionary = _resolve_type(text, String(t), catalogs, context)
		if r.is_empty():
			continue
		for m in r["matches"]:
			all.append(m)
	if all.is_empty():
		return {}
	var maxlen := 0
	for m in all:
		maxlen = max(maxlen, int(m["length"]))
	var top: Array = []
	for m in all:
		if int(m["length"]) == maxlen:
			top.append(m)
	return _finalize_matches(top, "")

## 去重（同 type:id）、按「上下文就近 + 稳定次序」排序并组装结果。
func _finalize_matches(top: Array, type: String) -> Dictionary:
	var uniq: Array = []
	var seen: Dictionary = {}
	for m in top:
		var key := String(m["type"]) + ":" + str(m["entry"].get("id", ""))
		if seen.has(key):
			continue
		seen[key] = true
		uniq.append(m)
	uniq.sort_custom(_cmp_candidate)
	return {"matches": uniq, "name": uniq[0]["name"], "pos": uniq[0]["pos"], "length": uniq[0]["length"]}

func _cmp_candidate(a: Variant, b: Variant) -> bool:
	# 上下文就近（rank 小者优先）→ 声明次序 → 类型 → id，保证确定性。
	if int(a["rank"]) != int(b["rank"]):
		return int(a["rank"]) < int(b["rank"])
	if int(a["order"]) != int(b["order"]):
		return int(a["order"]) < int(b["order"])
	if String(a["type"]) != String(b["type"]):
		return String(a["type"]) < String(b["type"])
	return str(a["entry"].get("id", "")) < str(b["entry"].get("id", ""))

func _object_from(m: Dictionary) -> Dictionary:
	var entry: Dictionary = m["entry"]
	var o: Dictionary = entry.duplicate(true)
	o["type"] = String(m["type"])
	if not o.has("name"):
		o["name"] = String(m["name"])
	return o

func _object_from_entry(entry: Dictionary, type: String) -> Dictionary:
	var o: Dictionary = entry.duplicate(true)
	o["type"] = type
	return o

func _recent_rank(entry: Dictionary, context: Dictionary) -> int:
	var recent: Array = context.get("recent", [])
	var id := str(entry.get("id", ""))
	for i in range(recent.size()):
		if typeof(recent[i]) == TYPE_DICTIONARY and str(recent[i].get("id", "")) == id:
			return i
	return 999

func _slot_for_type(type: String, context: Dictionary) -> Dictionary:
	var slots: Dictionary = context.get("slots", {})
	if slots.has(type) and typeof(slots[type]) == TYPE_DICTIONARY and not (slots[type] as Dictionary).is_empty():
		return slots[type]
	var recent: Array = context.get("recent", [])
	for e in recent:
		if typeof(e) == TYPE_DICTIONARY and String(e.get("type", "")) == type:
			return e
	return {}

func _has_type(objects: Array, type: String) -> bool:
	for o in objects:
		if typeof(o) == TYPE_DICTIONARY and String(o.get("type", "")) == type:
			return true
	return false

# --- 参数提取 ---

func _extract_params(text: String) -> Dictionary:
	var params: Dictionary = {}
	var spans: Array = []
	var matches := _number_re.search_all(text)
	for m in matches:
		var num_text := m.get_string(1)
		var unit := m.get_string(2)
		var value := _number_value(num_text)
		if value < 0:
			continue
		spans.append({"pos": m.get_start(0), "length": m.get_end(0) - m.get_start(0)})
		if unit.is_empty():
			if not params.has("number"):
				params["number"] = value
			continue
		var kind := _unit_key(unit)
		if kind == "amount":
			params["amount"] = value
			params["amount_unit"] = unit
		elif kind == "duration":
			params["duration"] = value
			params["duration_unit"] = unit
		elif kind == "quantity":
			params["quantity"] = value
			params["unit"] = unit
		elif not params.has("number"):
			params["number"] = value
	return {"params": params, "residue": _erase_spans(text, spans)}

func _unit_key(unit: String) -> String:
	if _MONEY_UNITS.has(unit):
		return "amount"
	if _DURATION_UNITS.has(unit):
		return "duration"
	if _COUNT_UNITS.has(unit):
		return "quantity"
	return ""

func _number_value(num_text: String) -> int:
	if num_text.is_valid_int():
		return num_text.to_int()
	return _parse_cn_number(num_text)

## 简易中文数字解析：支持「十二/二十/二十三/三百/一万」等常见形式。
func _parse_cn_number(text: String) -> int:
	var total := 0
	var section := 0
	var number := 0
	for ch in text:
		if _DIGITS.has(ch):
			number = int(_DIGITS[ch])
		elif _CN_UNITS.has(ch):
			var unit := int(_CN_UNITS[ch])
			if unit == 10000 or unit == 100000000:
				section = (section + number) * unit
				total += section
				section = 0
				number = 0
			else:
				if number == 0:
					number = 1
				section += number * unit
				number = 0
		else:
			return -1
	return total + section + number

# --- 归一与工具 ---

func _normalize(raw: String) -> String:
	var out := ""
	for ch in raw:
		var c := String(_FULLWIDTH.get(ch, ch))
		if c == " " or c == "\t" or c == "\n" or c == "\r":
			continue
		if _PUNCT.find(c) >= 0:
			continue
		out += c
	return out

func _erase_spans(text: String, spans: Array) -> String:
	if spans.is_empty():
		return text
	var sorted: Array = spans.duplicate()
	sorted.sort_custom(_cmp_span_desc)
	var s := text
	for sp in sorted:
		var p := int(sp["pos"])
		var l := int(sp["length"])
		if p < 0 or p + l > s.length():
			continue
		s = s.substr(0, p) + s.substr(p + l)
	return s

func _cmp_span_desc(a: Variant, b: Variant) -> bool:
	return int(a["pos"]) > int(b["pos"])

func _strip_particles(text: String) -> String:
	var out := ""
	for ch in text:
		if _PARTICLES.find(ch) >= 0:
			continue
		out += ch
	return out

func _strip_pronoun_tokens(text: String) -> String:
	var out := text
	for tok in ["他们", "她们", "这里", "这儿", "那个", "这个", "刚才的", "刚才", "他", "她", "它"]:
		out = out.replace(tok, "")
	return out

func _contains_any(text: String, tokens: Array) -> bool:
	for t in tokens:
		if text.find(String(t)) >= 0:
			return true
	return false

func _char_to_index(ch: String) -> int:
	if ch.length() != 1:
		return 0
	if ch >= "1" and ch <= "9":
		return ch.to_int()
	return int(_INDEX_CHARS.get(ch, 0))

func _pure_index(s: String) -> int:
	if s.length() != 1:
		return 0
	return _char_to_index(s)

func _trailing_index(rest: String) -> int:
	if rest.is_empty():
		return 0
	return _char_to_index(rest.substr(rest.length() - 1, 1))

func _type_label(t: String) -> String:
	return String(_TYPE_LABELS.get(t, t))

func _unrecognized_message(s: String) -> String:
	var sug: Array = _registry.suggest(s, 3)
	if sug.is_empty():
		return "无法识别指令「%s」" % s
	var names := PackedStringArray()
	for v in sug:
		names.append(String(v))
	return "无法识别指令「%s」，也许你想：%s" % [s, "、".join(names)]

func _record(raw: String) -> void:
	var s := raw.strip_edges()
	if s.is_empty():
		return
	if not history.is_empty() and String(history[history.size() - 1]) == s:
		return
	history.append(s)
	while history.size() > HISTORY_LIMIT:
		history.pop_front()
