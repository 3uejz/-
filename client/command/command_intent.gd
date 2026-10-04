class_name CommandIntent
extends RefCounted
## 结构化指令意图：文字输入、动作面板与快捷键统一产出同一形态，
## 保证行为一致、可回放、可测试。见 R27 验收 15、design.md「同源意图」。
## 字段：verb、objects、params、source（text/panel/hotkey）、raw。

var verb: String = ""              ## 归一后的规范动词
var objects: Array = []            ## 已解析对象，元素为 Dictionary（含 type/id/name）
var params: Dictionary = {}        ## 参数：amount/duration/quantity/method 等
var source: String = "text"        ## text / panel / hotkey
var raw: String = ""               ## 原始输入
var ok: bool = false               ## 本次解析是否可直接执行
var error: String = ""             ## 失败原因（对象无效、条件不满足等）
var options: Array = []            ## Array[CommandOption]，多义候选
var parts: Array = []              ## Array[CommandIntent]，复合指令各段

## 取指定类型的首个对象；不存在返回空字典。
func object_of(type: String) -> Dictionary:
	for o in objects:
		if typeof(o) == TYPE_DICTIONARY and String(o.get("type", "")) == type:
			return o
	return {}

func has_object(type: String) -> bool:
	return not object_of(type).is_empty()

## 对象 id 列表，便于同源意图比较。
func object_ids() -> Array:
	var ids: Array = []
	for o in objects:
		if typeof(o) == TYPE_DICTIONARY:
			ids.append(String(o.get("id", "")))
	return ids

func to_dict() -> Dictionary:
	var objs: Array = []
	for o in objects:
		if typeof(o) == TYPE_DICTIONARY:
			objs.append(o.duplicate(true))
	var opts: Array = []
	for op in options:
		opts.append(op.to_dict())
	var ps: Array = []
	for p in parts:
		ps.append(p.to_dict())
	return {
		"verb": verb,
		"objects": objs,
		"params": params.duplicate(true),
		"source": source,
		"raw": raw,
		"ok": ok,
		"error": error,
		"options": opts,
		"parts": ps,
	}
