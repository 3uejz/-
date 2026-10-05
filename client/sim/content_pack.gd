class_name ContentPack
extends RefCounted
## 轻量二进制内容包容器（.ltpack）。
## 格式与 Go 工具链 tools/contentbuilder 保持一致：
##   magic "LTPK" | version u16 | kindLen u16 | kind | categoryLen u16 | category
##   | entryCount u32 | (keyLen u16 | key | payloadLen u32 | payloadJSON)*
## 本类负责解码与哈希校验；编码在同进程内仅用于测试与 Editor 预览。

const MAGIC := "LTPK"
const FORMAT_VERSION := 1

var category: String = ""
var kind: String = ""
var entries: Dictionary = {}
var source_path: String = ""


static func load_file(path: String) -> ContentPack:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("无法打开内容包: %s" % path)
		return null
	var data := f.get_buffer(f.get_length())
	f.close()
	return decode(data, path)


static func decode(data: PackedByteArray, source_path: String = "") -> ContentPack:
	if data.size() < 12 or data.slice(0, 4).get_string_from_utf8() != MAGIC:
		push_error("非法的内容包 magic: %s" % source_path)
		return null
	var pack := ContentPack.new()
	pack.source_path = source_path
	var off := 4
	var version := data.decode_u16(off)
	off += 2
	if version != FORMAT_VERSION:
		push_error("不支持的内容包版本 %d: %s" % [version, source_path])
		return null
	var kind := _read_str(data, off)
	off = kind[1]
	var category := _read_str(data, off)
	off = category[1]
	pack.kind = kind[0]
	pack.category = category[0]
	if off + 4 > data.size():
		push_error("内容包头损坏: %s" % source_path)
		return null
	var count := data.decode_u32(off)
	off += 4
	for _i in range(count):
		if off + 2 > data.size():
			push_error("内容包条目损坏: %s" % source_path)
			return null
		var key := _read_str(data, off)
		off = key[1]
		if off + 4 > data.size():
			push_error("内容包条目载荷损坏: %s" % source_path)
			return null
		var plen := data.decode_u32(off)
		off += 4
		if off + plen > data.size():
			push_error("内容包条目载荷越界: %s" % source_path)
			return null
		var payload := data.slice(off, off + plen).get_string_from_utf8()
		off += plen
		var parsed: Variant = JSON.parse_string(payload)
		pack.entries[key[0]] = parsed if typeof(parsed) == TYPE_DICTIONARY else {}
	return pack


## 仅测试/Editor 使用：把条目编码为内容包字节。
static func encode_bytes(category: String, kind: String, entries: Dictionary) -> PackedByteArray:
	var buf := PackedByteArray()
	buf.append_array(MAGIC.to_utf8_buffer())
	_put_u16(buf, FORMAT_VERSION)
	_put_str(buf, kind)
	_put_str(buf, category)
	var keys: Array = entries.keys()
	keys.sort()
	_put_u32(buf, keys.size())
	for key in keys:
		_put_str(buf, key)
		var payload := JSON.stringify(entries[key])
		var payload_bytes := payload.to_utf8_buffer()
		_put_u32(buf, payload_bytes.size())
		buf.append_array(payload_bytes)
	return buf


static func sha256_hex(data: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(data)
	return "sha256:" + ctx.finish().hex_encode()


static func _read_str(data: PackedByteArray, off: int) -> Array:
	if off + 2 > data.size():
		return ["", off]
	var n := data.decode_u16(off)
	off += 2
	if off + n > data.size():
		return ["", off]
	var s := data.slice(off, off + n).get_string_from_utf8()
	return [s, off + n]


static func _put_u16(buf: PackedByteArray, v: int) -> void:
	var at := buf.size()
	buf.resize(at + 2)
	buf.encode_u16(at, v)


static func _put_u32(buf: PackedByteArray, v: int) -> void:
	var at := buf.size()
	buf.resize(at + 4)
	buf.encode_u32(at, v)


static func _put_str(buf: PackedByteArray, s: String) -> void:
	var b := s.to_utf8_buffer()
	_put_u16(buf, b.size())
	buf.append_array(b)
