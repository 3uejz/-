class_name SaveMigrations
extends RefCounted
## 存档 schema_version 迁移目录（任务 49）。
## 版本历史：
##   v1 初版
##   v2 领域状态大扩展：player 增 family/memory/pets/military/disabilities/
##      lands/digital_assets/cases/credit_score/will/orders/itineraries/awards/
##      medical_records；finances 增 loans/leases/insurances；legal 与 health 细化；
##      world_delta 增案件/灾害/异常/工厂/IP/体育/订单/行程/医疗/工程/奖项。
## 用法：`SaveMigrations.apply_default(save_manager)`。

const CURRENT_SCHEMA_VERSION: int = 2

## 注册全部内置迁移并把 target_schema_version 设为当前版本。
static func apply_default(save_manager) -> void:
	save_manager.target_schema_version = CURRENT_SCHEMA_VERSION
	save_manager.register_migration(1, func(doc: Dictionary) -> Dictionary:
		return migrate_v1_to_v2(doc))

## v1 -> v2：为缺失的领域字段补默认空值，不覆盖已有数据。
static func migrate_v1_to_v2(doc: Dictionary) -> Dictionary:
	if doc.get("world_delta") is Dictionary:
		var wd: Dictionary = doc["world_delta"]
		_ensure(wd, "organizations", [])
		_ensure(wd, "world_events", [])
		_ensure(wd, "news", [])
		for key in [
			"cases", "disasters", "anomalies", "factories", "ips", "sports",
			"orders", "itineraries", "medical_records", "projects", "awards",
		]:
			_ensure(wd, key, [])
	if doc.get("player") is Dictionary:
		var p: Dictionary = doc["player"]
		_ensure(p, "family", {})
		_ensure(p, "memory", [])
		_ensure(p, "pets", [])
		_ensure(p, "disabilities", [])
		_ensure(p, "lands", [])
		_ensure(p, "digital_assets", [])
		_ensure(p, "cases", [])
		_ensure(p, "orders", [])
		_ensure(p, "itineraries", [])
		_ensure(p, "awards", [])
		_ensure(p, "medical_records", [])
		_ensure(p, "credit_score", 650)
		_ensure(p, "military", {})
		_ensure(p, "will", {})
		_ensure(p, "disability_level", 0)
		if p.get("finances") is Dictionary:
			var fin: Dictionary = p["finances"]
			_ensure(fin, "loans", [])
			_ensure(fin, "leases", [])
			_ensure(fin, "insurances", [])
			_ensure(fin, "investments", [])
		if p.get("health") is Dictionary:
			var h: Dictionary = p["health"]
			_ensure(h, "diseases", [])
			_ensure(h, "mental", [])
			_ensure(h, "addictions", [])
			_ensure(h, "treatments", [])
			_ensure(h, "injuries", [])
		if p.get("legal") is Dictionary:
			_ensure(p["legal"], "active_case_ids", [])
			_ensure(p["legal"], "record_entries", [])
	if doc.get("world_delta") is Dictionary and doc["world_delta"].get("npcs") is Array:
		for npc in doc["world_delta"]["npcs"]:
			if npc is Dictionary:
				_ensure(npc, "memory", [])
	return doc

static func _ensure(target: Dictionary, key: String, default_value) -> void:
	if not target.has(key):
		target[key] = default_value
