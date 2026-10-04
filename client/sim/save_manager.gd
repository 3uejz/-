class_name SaveManager
extends RefCounted
## 本地存档读写：版本化 schema、迁移流水线、滚动备份、导出导入、分块存储。
## 存档结构与哈希规则见 shared/schemas/save.schema.json 与 shared/conventions.md。

const MAX_BACKUPS: int = 3
const CHUNK_KEYS: Array[String] = ["player", "world_delta"]

var base_dir: String
var target_schema_version: int = 1
var _migrations: Dictionary = {}  # from_version(int) -> Callable(doc) -> doc

func _init(dir: String) -> void:
	base_dir = dir
	DirAccess.make_dir_recursive_absolute(base_dir)

## 注册 v -> v+1 的迁移函数。
func register_migration(from_version: int, fn: Callable) -> void:
	_migrations[from_version] = fn

func main_path(slot: String) -> String:
	return base_dir.path_join("slot_%s.json" % slot)

func backup_path(slot: String, index: int) -> String:
	return base_dir.path_join("slot_%s.bak%d.json" % [slot, index])

func chunk_path(slot: String, key: String) -> String:
	return base_dir.path_join("slot_%s.chunk.%s.json" % [slot, key])

func exists(slot: String) -> bool:
	return FileAccess.file_exists(main_path(slot))

# --- 保存 ---

func save(slot: String, doc: Dictionary, chunked: bool = false) -> Dictionary:
	var missing: Array = SaveCodec.validate(doc)
	if not missing.is_empty():
		return {"ok": false, "error": "缺少必需字段: %s" % str(missing)}
	if not (doc.get("meta") is Dictionary):
		return {"ok": false, "error": "meta 缺失或类型错误"}

	var stored: Dictionary = doc.duplicate(true)
	var meta: Dictionary = stored["meta"]
	meta["schema_version"] = int(meta.get("schema_version", target_schema_version))
	meta["updated_at"] = _now_iso()
	if not meta.has("created_at"):
		meta["created_at"] = meta["updated_at"]
	meta["hash"] = ""

	# 哈希始终覆盖「完整」逻辑文档（排除 meta.hash），与是否分块无关。
	var full_hash: String = SaveCodec.compute_hash(stored)

	if chunked:
		var chunks: Dictionary = {}
		for key in CHUNK_KEYS:
			if not stored.has(key):
				continue
			var payload: Variant = stored[key]
			var chunk_text: String = SaveCodec.canonical_json(payload if payload is Dictionary else {"value": payload})
			if not _write_text(chunk_path(slot, key), chunk_text):
				return {"ok": false, "error": "写入分块失败: %s" % key}
			chunks[key] = {"hash": SaveCodec.sha256_hex(chunk_text)}
			stored.erase(key)
		stored["chunks"] = chunks

	meta["hash"] = full_hash
	if not _rotate_backups(slot):
		return {"ok": false, "error": "备份轮转失败"}
	if not _write_text(main_path(slot), SaveCodec.canonical_json(stored)):
		return {"ok": false, "error": "写入存档失败"}
	return {"ok": true, "hash": full_hash}

# --- 读取 ---

func load(slot: String) -> Dictionary:
	var path: String = main_path(slot)
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "存档不存在: %s" % slot}
	var text: String = _read_text(path)
	if text.is_empty():
		return {"ok": false, "error": "存档为空或不可读"}

	var parsed: Dictionary = SaveCodec.parse(text)
	if not parsed["ok"]:
		return parsed
	var doc: Dictionary = parsed["doc"]

	if doc.has("chunks") and doc["chunks"] is Dictionary:
		var chunk_result: Dictionary = _load_chunks(slot, doc)
		if not chunk_result["ok"]:
			return chunk_result
		doc = chunk_result["doc"]

	# 完整性校验在迁移前进行：哈希覆盖磁盘上的原始逻辑文档，迁移会改变内容。
	if doc.get("meta") is Dictionary:
		var want_hash: String = str((doc["meta"] as Dictionary).get("hash", ""))
		if want_hash != "" and SaveCodec.compute_hash(doc) != want_hash:
			return {"ok": false, "error": "存档哈希校验失败（可能已损坏）"}

	var migrated: Dictionary = _migrate(doc)
	if not migrated["ok"]:
		return migrated
	doc = migrated["doc"]

	var missing: Array = SaveCodec.validate(doc)
	if not missing.is_empty():
		return {"ok": false, "error": "缺少必需字段: %s" % str(missing)}

	return {"ok": true, "doc": doc}

# --- 导出 / 导入 ---

func export_save(slot: String, dest_path: String) -> Dictionary:
	if not exists(slot):
		return {"ok": false, "error": "存档不存在"}
	DirAccess.make_dir_recursive_absolute(dest_path.get_base_dir())
	var text: String = _read_text(main_path(slot))
	if text.is_empty() or not _write_text(dest_path, text):
		return {"ok": false, "error": "导出失败"}
	for key in CHUNK_KEYS:
		var cpath: String = chunk_path(slot, key)
		if FileAccess.file_exists(cpath):
			if not _write_text("%s.chunk.%s.json" % [dest_path, key], _read_text(cpath)):
				return {"ok": false, "error": "导出分块失败: %s" % key}
	return {"ok": true}

func import_save(src_path: String, slot: String) -> Dictionary:
	if not FileAccess.file_exists(src_path):
		return {"ok": false, "error": "源文件不存在"}
	var text: String = _read_text(src_path)
	if text.is_empty():
		return {"ok": false, "error": "源文件不可读"}
	_rotate_backups(slot)
	if not _write_text(main_path(slot), text):
		return {"ok": false, "error": "导入失败"}
	for key in CHUNK_KEYS:
		var csrc: String = "%s.chunk.%s.json" % [src_path, key]
		if FileAccess.file_exists(csrc):
			_write_text(chunk_path(slot, key), _read_text(csrc))
	return self.load(slot)

# --- 内部 ---

func _migrate(doc: Dictionary) -> Dictionary:
	var meta: Dictionary = doc.get("meta", {}) if doc.get("meta") is Dictionary else {}
	var version: int = int(meta.get("schema_version", 1))
	while version < target_schema_version:
		if not _migrations.has(version):
			return {"ok": false, "error": "缺少从版本 %d 的迁移" % version}
		var fn: Callable = _migrations[version]
		var result: Variant = fn.call(doc)
		if result is Dictionary:
			doc = result
		version += 1
		if not (doc.get("meta") is Dictionary):
			doc["meta"] = {}
		(doc["meta"] as Dictionary)["schema_version"] = version
	return {"ok": true, "doc": doc}

func _load_chunks(slot: String, doc: Dictionary) -> Dictionary:
	var manifest: Dictionary = doc["chunks"]
	for key in manifest.keys():
		var cpath: String = chunk_path(slot, key)
		if not FileAccess.file_exists(cpath):
			return {"ok": false, "error": "分块丢失: %s" % key}
		var ctext: String = _read_text(cpath)
		var cparse: Dictionary = SaveCodec.parse(ctext)
		if not cparse["ok"]:
			return cparse
		var expected: String = str((manifest[key] as Dictionary).get("hash", ""))
		if expected != "" and SaveCodec.sha256_hex(ctext) != expected:
			return {"ok": false, "error": "分块哈希校验失败: %s" % key}
		var payload: Dictionary = cparse["doc"]
		doc[key] = payload.get("value", payload) if payload.has("value") and payload.size() == 1 else payload
	doc.erase("chunks")
	return {"ok": true, "doc": doc}

func _rotate_backups(slot: String) -> bool:
	var oldest: String = backup_path(slot, MAX_BACKUPS - 1)
	if FileAccess.file_exists(oldest):
		DirAccess.remove_absolute(oldest)
	for i in range(MAX_BACKUPS - 2, -1, -1):
		var src: String = backup_path(slot, i)
		if FileAccess.file_exists(src):
			if DirAccess.rename_absolute(src, backup_path(slot, i + 1)) != OK:
				return false
	if FileAccess.file_exists(main_path(slot)):
		if DirAccess.rename_absolute(main_path(slot), backup_path(slot, 0)) != OK:
			return false
	return true

func _read_text(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	return f.get_as_text()

func _write_text(path: String, text: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	f.close()
	return true

func _now_iso() -> String:
	return Time.get_datetime_string_from_system(true, true) + "Z"
