class_name LegacySystem
extends RefCounted
## 传承轮回（R31；design「死亡、传承与轮回」）。
##
## 角色死亡后世界延续：后代继承技能记忆、天赋血脉、资产人脉与世界记忆；不设传承
## 点数货币；家族血脉跨代累积使多周目收益叠加；开新档可携带有限数量传承天赋；
## 传承数据独立持久化（后端 legacy）。

const BaselineScript = preload("res://sim/baseline.gd")

const WorldMemoryScript = preload("res://sim/world_memory.gd")

const SKILL_MEMORY_RATIO: float = BaselineScript.LEGACY_SKILL_MEMORY_RATIO      # 技能记忆折算比例
const ASSET_CARRY_RATIO: float = BaselineScript.LEGACY_ASSET_CARRY_RATIO       # 可继承流动比例（其余走遗嘱与遗产税 D11）
const TALENT_SLOTS: int = BaselineScript.LEGACY_TALENT_SLOTS                # 开新档可携带天赋数
const BLOODLINE_PER_GEN: float = BaselineScript.LEGACY_BLOODLINE_PER_GEN      # 每代血脉加成
const MAX_BLOODLINE: float = BaselineScript.LEGACY_MAX_BLOODLINE


func new_legacy() -> Dictionary:
	return {
		"generation": 1, "bloodline": 0.0, "skills": {}, "talents": [],
		"assets": 0, "relations": [], "world_memory": WorldMemoryScript.new().new_store(),
		"records": [],
	}


## 死亡结算（R31.1、R31.2）：世界延续，后代继承，不产出传承点数。
func settle(death: Dictionary, run: Dictionary, legacy: Dictionary = {}) -> Dictionary:
	if legacy.is_empty():
		legacy = new_legacy()
	legacy["generation"] = int(legacy["generation"]) + 1
	legacy["bloodline"] = clampf(float(legacy["bloodline"]) + BLOODLINE_PER_GEN, 0.0, MAX_BLOODLINE)

	# 技能记忆：折半继承。
	var skills: Dictionary = legacy["skills"]
	for skill_id in run.get("skills", {}):
		var inherited: int = int(floor(float(run["skills"][skill_id]) * SKILL_MEMORY_RATIO))
		skills[skill_id] = maxi(int(skills.get(skill_id, 0)), inherited)

	# 天赋血脉：并入血脉池，去重。
	for t in run.get("talents", []):
		if not (legacy["talents"] as Array).has(t):
			legacy["talents"].append(t)

	# 资产人脉：流动部分可继承。
	legacy["assets"] = int(round(float(run.get("assets", 0)) * ASSET_CARRY_RATIO))
	for r in run.get("relations", []):
		if not (legacy["relations"] as Array).has(r):
			legacy["relations"].append(r)

	# 世界记忆：随世界延续，清理淡出。
	if run.has("world_memory"):
		legacy["world_memory"] = WorldMemoryScript.new().from_dict(run["world_memory"])
	WorldMemoryScript.new().tick(legacy["world_memory"], int(death.get("minute", 0)))

	legacy["records"].append({"generation": int(legacy["generation"]), "name": str(death.get("name", "")), "age": int(death.get("age", 0)), "cause": str(death.get("cause", "")), "minute": int(death.get("minute", 0))})
	return {"ok": true, "legacy": legacy, "generation": int(legacy["generation"]), "bloodline": float(legacy["bloodline"])}


## 血脉加成（R31.3）。
func family_bonus(legacy: Dictionary) -> float:
	return 1.0 + clampf(float(legacy.get("bloodline", 0.0)), 0.0, MAX_BLOODLINE)


## 开新档携带传承（R31.4）：有限天赋槽，无点数兑换。
func new_game_carry(legacy: Dictionary, chosen_talents: Array = []) -> Dictionary:
	if chosen_talents.size() > TALENT_SLOTS:
		return {"ok": false, "reason": "too_many_talents", "max": TALENT_SLOTS}
	var available: Array = legacy.get("talents", [])
	for t in chosen_talents:
		if not available.has(t):
			return {"ok": false, "reason": "talent_not_inherited", "talent": t}
	return {
		"ok": true,
		"skills": (legacy.get("skills", {}) as Dictionary).duplicate(true),
		"talents": chosen_talents.duplicate(),
		"assets": int(legacy.get("assets", 0)),
		"relations": (legacy.get("relations", []) as Array).duplicate(),
		"bloodline_bonus": family_bonus(legacy),
		"world_memory": WorldMemoryScript.new().from_dict(legacy.get("world_memory", {})),
	}


## 独立持久化（R31.5）：仅存传承档案，不做数值兑换。
func to_dict(legacy: Dictionary) -> Dictionary:
	return legacy.duplicate(true)


func from_dict(data: Dictionary) -> Dictionary:
	return {
		"generation": int(data.get("generation", 1)),
		"bloodline": float(data.get("bloodline", 0.0)),
		"skills": (data.get("skills", {}) as Dictionary).duplicate(true),
		"talents": (data.get("talents", []) as Array).duplicate(true),
		"assets": int(data.get("assets", 0)),
		"relations": (data.get("relations", []) as Array).duplicate(true),
		"world_memory": WorldMemoryScript.new().from_dict(data.get("world_memory", {})),
		"records": (data.get("records", []) as Array).duplicate(true),
	}
