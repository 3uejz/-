extends "res://tests/test_base.gd"
## 区域全人口与三级 LOD 接入测试（任务 12；R50.7–R50.9）。
## 覆盖：人口物化与上限、确定性重建、个体化保留、休眠卸载、序列化往返。

const RegionManagerScript = preload("res://sim/region_manager.gd")

func _suite_name() -> String:
	return "region_population"

func run_tests() -> void:
	_test_materialize()
	_test_cap()
	_test_deterministic_rebuild()
	_test_preserve_individualized()
	_test_individualize()
	_test_dematerialize_on_leave()
	_test_serialization_roundtrip()


func _test_materialize() -> void:
	var rm = RegionManagerScript.new(null, 1)
	rm.configure_population(20261005)
	rm.register_region("city.pop", {"population": 40})
	var npcs: Array = rm.materialize_population("city.pop", 1000)
	check_eq(npcs.size(), 40, "物化全人口")
	var ids: Dictionary = {}
	for n in npcs:
		ids[str(n["id"])] = true
		check_eq(int(n["lod_tier"]), 0, "活动区为 Tier0")
	check_eq(ids.size(), 40, "人口 ID 唯一")
	check_eq(rm.population_npcs("city.pop").size(), 40, "查询人口")


func _test_cap() -> void:
	var rm = RegionManagerScript.new(null, 1)
	rm.configure_population(20261005, 10)
	rm.register_region("city.cap", {"population": 100})
	var npcs: Array = rm.materialize_population("city.cap", 0)
	check_eq(npcs.size(), 10, "受活动人口上限约束")
	check_eq(rm.population_cap(), 10, "上限读取")


func _test_deterministic_rebuild() -> void:
	var a = RegionManagerScript.new(null, 1)
	var b = RegionManagerScript.new(null, 1)
	a.configure_population(777)
	b.configure_population(777)
	a.register_region("city.det", {"population": 25})
	b.register_region("city.det", {"population": 25})
	var na: Array = a.materialize_population("city.det", 5000)
	var nb: Array = b.materialize_population("city.det", 5000)
	var same: bool = true
	for i in na.size():
		if str(na[i]["id"]) != str(nb[i]["id"]):
			same = false
	check(same, "同种子重建身份一致")
	# 不同种子身份不同。
	var c = RegionManagerScript.new(null, 1)
	c.configure_population(778)
	c.register_region("city.det", {"population": 25})
	var nc: Array = c.materialize_population("city.det", 5000)
	check(str(nc[0]["id"]) != str(na[0]["id"]), "不同种子身份不同")


func _test_preserve_individualized() -> void:
	var rm = RegionManagerScript.new(null, 1)
	rm.configure_population(555)
	rm.register_region("city.keep", {"population": 20})
	var npcs: Array = rm.materialize_population("city.keep", 0)
	var keep_id: String = str(npcs[0]["id"])
	rm.individualize_npc("city.keep", keep_id)
	var again: Array = rm.materialize_population("city.keep", 0)
	check_eq(again.size(), 20, "重建后人口数量不变")
	var found: bool = false
	for n in again:
		if str(n["id"]) == keep_id:
			found = true
			check(bool(n["individualized"]), "个体化标记保留")
	check(found, "重建保留个体化 NPC")


func _test_individualize() -> void:
	var rm = RegionManagerScript.new(null, 1)
	rm.configure_population(1)
	rm.register_region("city.ind", {"population": 15})
	var npcs: Array = rm.materialize_population("city.ind", 0)
	check_eq(rm.individualize_count("city.ind"), 0, "初始无个体化")
	rm.individualize_npc("city.ind", str(npcs[0]["id"]))
	rm.individualize_npc("city.ind", str(npcs[1]["id"]))
	check_eq(rm.individualize_count("city.ind"), 2, "个体化两名")
	check(rm.individualize_npc("city.ind", "nonexistent").is_empty(), "未知 NPC 返回空")


func _test_dematerialize_on_leave() -> void:
	var rm = RegionManagerScript.new(null, 1)
	rm.configure_population(2)
	rm.register_region("city.leave", {"population": 30})
	rm.enter("city.leave")
	rm.materialize_population("city.leave", 0)
	var npcs: Array = rm.population_npcs("city.leave")
	rm.individualize_npc("city.leave", str(npcs[0]["id"]))
	rm.leave("city.leave")
	check_eq(rm.population_npcs("city.leave").size(), 1, "休眠仅保留个体化 NPC")
	check_eq(int(rm.snapshot("city.leave")["individualized_count"]), 1, "快照记录个体化数")


func _test_serialization_roundtrip() -> void:
	var rm = RegionManagerScript.new(null, 1)
	rm.configure_population(3)
	rm.register_region("city.rt", {"population": 12})
	var npcs: Array = rm.materialize_population("city.rt", 0)
	var keep_id: String = str(npcs[0]["id"])
	rm.individualize_npc("city.rt", keep_id)
	var delta: Dictionary = rm.to_delta("city.rt")
	check_eq((delta["npcs"] as Array).size(), 1, "增量只携带个体化 NPC")

	var rm2 = RegionManagerScript.new(null, 1)
	rm2.load_delta(delta)
	var restored: Array = rm2.population_npcs("city.rt")
	check_eq(restored.size(), 1, "载入恢复个体化 NPC")
	check_eq(str(restored[0]["id"]), keep_id, "恢复身份一致")
	check(bool(restored[0]["individualized"]), "恢复个体化标记")
