extends "res://tests/test_base.gd"
## 外部内容包（MOD）预留接口测试（任务 23，R36.10）：默认不启用、兼容/签名校验、冲突拒绝。

const ModLoaderScript = preload("res://content/mod_loader.gd")
const MODS_DIR := "user://lt_mod_test"

var _keep: Array = []


func _suite_name() -> String:
	return "mod_loader"


func run_tests() -> void:
	_reset()
	_test_disabled_by_default()
	_test_discover_and_validate()
	_test_load_and_conflict()


func _reset() -> void:
	var abs := ProjectSettings.globalize_path(MODS_DIR)
	var d := DirAccess.open(abs)
	if d == null:
		DirAccess.make_dir_recursive_absolute(abs)
		return
	for f in d.get_files():
		d.remove(f)
	for sub in d.get_directories():
		var dd := DirAccess.open(abs.path_join(sub))
		if dd != null:
			for f in dd.get_files():
				dd.remove(f)
		d.remove(sub)


func _write_mod(id: String, manifest: Dictionary) -> void:
	var dir := ProjectSettings.globalize_path(MODS_DIR).path_join(id)
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(dir.path_join("mod.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(manifest))
	f.close()


func _test_disabled_by_default() -> void:
	var m = ModLoaderScript.new(MODS_DIR)
	check(not m.enabled(), "默认不启用")
	check_eq(String(m.discover()["reason"]), "mods_disabled", "未启用不扫描")
	check_eq(String(m.load_all()["reason"]), "mods_disabled", "未启用不加载")


func _test_discover_and_validate() -> void:
	_write_mod("alpha", {"name": "甲", "api_version": 1, "signature": "sig", "keys": ["item.a"]})
	_write_mod("beta", {"name": "乙", "api_version": 2, "signature": "sig", "keys": []})
	_write_mod("gamma", {"name": "丙", "api_version": 1, "keys": []})
	var m = ModLoaderScript.new(MODS_DIR)
	m.set_enabled(true)
	var verifier := func(desc: Dictionary) -> bool: return String(desc.get("signature", "")) == "sig"
	m.signature_verifier = verifier
	_keep.append(verifier)
	var disc: Dictionary = m.discover()
	check(bool(disc["ok"]), "发现成功")
	check_eq((disc["mods"] as Array).size(), 3, "发现 3 个 MOD")
	check_eq(String((disc["mods"] as Array)[0]["id"]), "alpha", "按 id 排序")
	check(bool(m.validate(m.discovered()[0])["ok"]), "签名通过")
	var beta: Dictionary = _find(m.discovered(), "beta")
	check_eq(String(m.validate(beta)["reason"]), "api_mismatch", "api 不兼容")
	var gamma: Dictionary = _find(m.discovered(), "gamma")
	check_eq(String(m.validate(gamma)["reason"]), "bad_signature", "有校验器时未签名视为签名失败")
	# 无校验器且不允许未签名时，理由为 unsigned。
	var m2 = ModLoaderScript.new(MODS_DIR)
	m2.set_enabled(true)
	check_eq(String(m2.validate(gamma)["reason"]), "unsigned", "无校验器时拒绝未签名")


func _test_load_and_conflict() -> void:
	var m = ModLoaderScript.new(MODS_DIR)
	m.set_enabled(true)
	var verifier := func(desc: Dictionary) -> bool: return String(desc.get("signature", "")) == "sig"
	m.signature_verifier = verifier
	_keep.append(verifier)
	var res: Dictionary = m.load_all(["item.a"])
	check(bool(res["ok"]), "加载流程完成")
	check(not (res["loaded"] as Array).has("alpha"), "与 base 冲突的 MOD 被拒")
	check(_rejected_has(res, "alpha", "key_conflict"), "记录键冲突")
	check(_rejected_has(res, "beta", "api_mismatch"), "记录 api 不兼容")
	check(_rejected_has(res, "gamma", "bad_signature"), "记录签名失败")

	# 无冲突时正常载入。
	_write_mod("delta", {"name": "丁", "api_version": 1, "signature": "sig", "keys": ["item.z"]})
	var m2 = ModLoaderScript.new(MODS_DIR)
	m2.set_enabled(true)
	m2.signature_verifier = verifier
	var res2: Dictionary = m2.load_all(["item.a"])
	check((res2["loaded"] as Array).has("delta"), "无冲突载入")
	check_eq(m2.loaded_ids(), ["delta"], "已载入清单")


func _find(mods: Array, id: String) -> Dictionary:
	for m in mods:
		if String(m["id"]) == id:
			return m
	return {}


func _rejected_has(res: Dictionary, id: String, reason: String) -> bool:
	for r in res.get("rejected", []):
		if String(r["id"]) == id and String(r["reason"]) == reason:
			return true
	return false
