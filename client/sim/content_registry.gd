class_name ContentRegistry
extends RefCounted
## 内容包注册表：加载 manifest.json、校验 sha256 哈希、合并条目并做启动交叉引用校验。
## 与 Go 工具链 tools/contentbuilder 的类别 schema 保持一致（硬阻断式）。

## 跨引用规则：类别 -> { 字段: 目标类别 }。
const CROSS_REFS := {
	"jobs": { "skills": "skills" },
	"skills": { "prereq": "skills" },
	"manufacturing": { "inputs": "items" },
}

var packs: Dictionary = {}          # name -> ContentPack
var entries: Dictionary = {}        # category -> { key -> fields }
var issues: Array = []
var manifest_version: int = 0


static func load_dir(dir_path: String) -> ContentRegistry:
	var registry := ContentRegistry.new()
	registry._load(dir_path)
	return registry


func _load(dir_path: String) -> void:
	var manifest_path := dir_path.path_join("manifest.json")
	var m := _read_json(manifest_path)
	if m.is_empty():
		issues.append("缺少或无法解析内容清单: %s" % manifest_path)
		return
	manifest_version = int(m.get("manifest_version", 0))
	var pack_list: Array = m.get("packs", [])
	for p in pack_list:
		if typeof(p) != TYPE_DICTIONARY:
			issues.append("清单条目格式错误")
			continue
		var name := str(p.get("name", ""))
		var expected_hash := str(p.get("hash", ""))
		var pack_path := dir_path.path_join(name + ".ltpack")
		var data := _read_bytes(pack_path)
		if data.is_empty():
			issues.append("缺少内容包文件: %s" % pack_path)
			continue
		var actual_hash := ContentPack.sha256_hex(data)
		if expected_hash != "" and actual_hash != expected_hash:
			issues.append("哈希校验失败 %s: 期望 %s 实际 %s" % [name, expected_hash, actual_hash])
			continue
		var pack := ContentPack.decode(data, pack_path)
		if pack == null:
			issues.append("内容包解码失败: %s" % pack_path)
			continue
		packs[name] = pack
		register(pack)


func register(pack: ContentPack) -> void:
	if not entries.has(pack.category):
		entries[pack.category] = {}
	for key in pack.entries:
		if entries[pack.category].has(key):
			issues.append("重复 content_key: %s" % key)
		entries[pack.category][key] = pack.entries[key]


## 启动交叉引用校验，返回问题列表（空表示通过）。
func validate() -> Array:
	var found: Array = []
	var global_keys: Dictionary = {}
	for category in entries:
		for key in entries[category]:
			if global_keys.has(key):
				found.append("content_key 跨类别重复: %s" % key)
			global_keys[key] = true
	for category in CROSS_REFS:
		if not entries.has(category):
			continue
		for field in CROSS_REFS[category]:
			var target: String = CROSS_REFS[category][field]
			for key in entries[category]:
				var refs: Variant = entries[category][key].get(field, [])
				if typeof(refs) != TYPE_ARRAY:
					continue
				for ref in refs:
					if not entries.has(target) or not entries[target].has(str(ref)):
						found.append("%s.%s 引用不存在的内容键 %s" % [key, field, str(ref)])
	return found


func get_entry(category: String, key: String) -> Dictionary:
	if entries.has(category) and entries[category].has(key):
		return entries[category][key]
	return {}


func count() -> int:
	var n := 0
	for category in entries:
		n += entries[category].size()
	return n


func _read_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


func _read_bytes(path: String) -> PackedByteArray:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return PackedByteArray()
	var data := f.get_buffer(f.get_length())
	f.close()
	return data
