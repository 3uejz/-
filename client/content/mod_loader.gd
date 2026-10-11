class_name ModLoader
extends RefCounted
## 外部内容包（MOD）预留接口（R36.10；任务 23）。
##
## 首发不启用：`enable_mods` 默认 false，未启用时不扫描、不加载任何外部包，
## 因而不会绕过平台对内容与安全的控制。启用时再补沙箱/签名/兼容校验；
## 本类已预留全部挂钩点：
##   - 目录发现：`<dir>/<id>/mod.json`（含 packs/keys/api_version/signature）
##   - 兼容性校验：`api_version` 必须与内容协议一致
##   - 签名校验：注入 `signature_verifier`，默认拒绝未签名（`allow_unsigned` 可放宽）
##   - 加载顺序与冲突检测：按 id 稳定排序，content_key 冲突则整体拒绝该 mod
## 全部逻辑纯化（无 Autoload 依赖），可 headless 测试。

const API_VERSION: int = 1
const MANIFEST_NAME: String = "mod.json"

var dir: String = "user://mods"
var enable_mods: bool = false
var allow_unsigned: bool = false
var api_version: int = API_VERSION
## 签名校验器：func(desc: Dictionary) -> bool。
var signature_verifier: Callable = Callable()

var _discovered: Array = []
var _loaded: Dictionary = {}   # id -> descriptor


func _init(mods_dir: String = "user://mods") -> void:
	dir = mods_dir


func enabled() -> bool:
	return enable_mods

func set_enabled(value: bool) -> void:
	enable_mods = value


## 扫描外部目录，返回 {ok, reason, mods}。未启用时返回空列表与理由。
func discover() -> Dictionary:
	_discovered.clear()
	if not enable_mods:
		return {"ok": false, "reason": "mods_disabled", "mods": []}
	var d := DirAccess.open(dir)
	if d == null:
		return {"ok": true, "reason": "no_mods_dir", "mods": []}
	for sub in d.get_directories():
		var desc := _read_manifest(sub)
		if not desc.is_empty():
			_discovered.append(desc)
	_discovered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a["id"]) < String(b["id"]))
	return {"ok": true, "reason": "ok", "mods": _discovered.duplicate(true)}


func discovered() -> Array:
	return _discovered.duplicate(true)

func loaded_ids() -> Array:
	var ids: Array = _loaded.keys()
	ids.sort()
	return ids


## 校验单个 MOD：启用状态、api 兼容、签名。
func validate(desc: Dictionary) -> Dictionary:
	if not enable_mods:
		return {"ok": false, "reason": "mods_disabled"}
	if int(desc.get("api_version", -1)) != api_version:
		return {"ok": false, "reason": "api_mismatch"}
	if signature_verifier.is_valid():
		if not bool(signature_verifier.call(desc)):
			return {"ok": false, "reason": "bad_signature"}
	elif not allow_unsigned:
		return {"ok": false, "reason": "unsigned"}
	return {"ok": true, "reason": "ok"}


## 载入全部通过校验的 MOD；与既有 base 内容键冲突的 MOD 整体拒绝。
## 返回 {ok, reason, loaded:[id], rejected:[{id, reason}], conflicts:[{key, from, mod}]}。
func load_all(existing_keys: Array = []) -> Dictionary:
	if not enable_mods:
		return {"ok": false, "reason": "mods_disabled", "loaded": [], "rejected": [], "conflicts": []}
	discover()
	var owner: Dictionary = {}
	for k in existing_keys:
		owner[String(k)] = "base"
	var loaded: Array = []
	var rejected: Array = []
	var conflicts: Array = []
	var claimed: Dictionary = {}
	for desc in _discovered:
		var v: Dictionary = validate(desc)
		if not v["ok"]:
			rejected.append({"id": desc["id"], "reason": String(v["reason"])})
			continue
		var local_conflict: Array = []
		for key in desc.get("keys", []):
			var k := String(key)
			if owner.has(k) or claimed.has(k):
				local_conflict.append({"key": k, "from": String(owner.get(k, claimed.get(k, ""))), "mod": String(desc["id"])})
		if not local_conflict.is_empty():
			conflicts.append_array(local_conflict)
			rejected.append({"id": desc["id"], "reason": "key_conflict"})
			continue
		for key in desc.get("keys", []):
			claimed[String(key)] = desc["id"]
		_loaded[desc["id"]] = desc
		loaded.append(desc["id"])
	return {"ok": true, "reason": "ok", "loaded": loaded, "rejected": rejected, "conflicts": conflicts}


func _read_manifest(id: String) -> Dictionary:
	var path := dir.path_join(id).path_join(MANIFEST_NAME)
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var m: Dictionary = parsed
	var keys: Array = []
	for k in m.get("keys", []):
		keys.append(String(k))
	return {
		"id": id,
		"name": String(m.get("name", id)),
		"api_version": int(m.get("api_version", 0)),
		"min_game_version": String(m.get("min_game_version", "")),
		"signature": String(m.get("signature", "")),
		"packs": m.get("packs", []),
		"keys": keys,
		"path": dir.path_join(id),
	}
