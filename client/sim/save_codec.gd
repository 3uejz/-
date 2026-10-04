class_name SaveCodec
extends RefCounted
## 存档编解码：规范化 JSON、sha256 校验、结构校验。
## 哈希覆盖的文档会移除 meta.hash 后再规范化，便于完整性校验。

const REQUIRED_TOP_LEVEL: Array[String] = ["meta", "clock", "player", "world_delta", "rng"]

## 规范化 JSON（键排序、全精度），保证同一文档稳定序列化。
## JSON 解析会把所有数字读成 float，因此先归一化：整数值统一写成 int，避免
## 同一文档在「保存前」与「读取后」序列化出不同文本而导致哈希漂移。
static func canonical_json(doc: Dictionary) -> String:
	return JSON.stringify(_normalize(doc), "", true, true)

static func _normalize(value: Variant) -> Variant:
	match typeof(value):
		TYPE_FLOAT:
			var f: float = value
			if is_finite(f) and f == floor(f) and absf(f) <= 9007199254740992.0:
				return int(f)
			return f
		TYPE_DICTIONARY:
			var out: Dictionary = {}
			for k in value:
				out[k] = _normalize(value[k])
			return out
		TYPE_ARRAY:
			var arr: Array = []
			for item in value:
				arr.append(_normalize(item))
			return arr
		_:
			return value

static func sha256_hex(text: String) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(text.to_utf8_buffer())
	return ctx.finish().hex_encode()

## 计算文档哈希（排除 meta.hash）。
static func compute_hash(doc: Dictionary) -> String:
	var copy: Dictionary = doc.duplicate(true)
	if copy.has("meta") and copy["meta"] is Dictionary:
		(copy["meta"] as Dictionary).erase("hash")
	return sha256_hex(canonical_json(copy))

## 校验顶层必需字段，返回缺失字段列表。
static func validate(doc: Dictionary) -> Array:
	var missing: Array = []
	for key in REQUIRED_TOP_LEVEL:
		if not doc.has(key):
			missing.append(key)
	return missing

## 解析 JSON 文本；失败返回 {ok=false, error=...}。
static func parse(text: String) -> Dictionary:
	var json := JSON.new()
	var err: int = json.parse(text)
	if err != OK:
		return {"ok": false, "error": "JSON 解析失败（行 %d）：%s" % [json.get_error_line(), json.get_error_message()]}
	var data: Variant = json.data
	if typeof(data) != TYPE_DICTIONARY:
		return {"ok": false, "error": "存档顶层不是对象"}
	return {"ok": true, "doc": data}
