extends "res://tests/test_base.gd"
## 宠物生命周期测试（任务 18；R51.6、R51.7；design D11）。

const PetScript = preload("res://sim/pet.gd")


class FixedRng:
	var seq: Array
	var i: int = 0
	func _init(s: Array) -> void:
		seq = s
	func next_float() -> float:
		var v: float = float(seq[i % seq.size()])
		i += 1
		return v


func _suite_name() -> String:
	return "pet"


func run_tests() -> void:
	_test_acquire()
	_test_care_actions()
	_test_lifecycle()
	_test_lost_and_mood()


func _test_acquire() -> void:
	var sys = PetScript.new()
	check_eq(sys.species_count(), 7, "七类宠物")
	var r: Dictionary = sys.acquire("dog", "旺财", 0.0, "male")
	check(bool(r["ok"]), "领养成功")
	var pet: Dictionary = r["pet"]
	check_eq(str(pet["species"]), "dog", "物种")
	check_eq(int(pet["cost"]), 200000, "购买费用")
	check(bool(pet["alive"]), "初始存活")
	check_eq(int(sys.daily_cost(pet)), 3000, "日粮费用")
	check_eq(int(sys.daily_minutes(pet)), 60, "日照护分钟")
	check(not bool(sys.acquire("dragon", "x")["ok"]), "未知物种失败")


func _test_care_actions() -> void:
	var sys = PetScript.new()
	var pet: Dictionary = sys.acquire("cat", "咪咪")["pet"]
	pet["hunger"] = 30.0
	var f: Dictionary = sys.feed(pet, 40.0)
	check(float(f["hunger"]) > 30.0, "喂养补充饥饿")
	pet["health"] = 50.0
	var v: Dictionary = sys.vet(pet, 30.0)
	check(float(v["health"]) > 50.0, "就医提升健康")
	var t: Dictionary = sys.train(pet, 5.0, FixedRng.new([0.5]))
	check(float(t["training"]) > 0.0, "训练提升")
	check(str(pet["species"]) == "cat", "物种不变")


func _test_lifecycle() -> void:
	var sys = PetScript.new()
	var pet: Dictionary = sys.acquire("hamster", "球球")["pet"]
	pet["hunger"] = 0.0
	pet["health"] = 100.0
	var r: Dictionary = sys.advance(pet, 2.0)
	check(float(pet["health"]) < 100.0, "饥饿损耗健康")
	check(float(pet["age"]) > 0.0, "年龄增长")
	# 持续饥饿致死。
	var tries: int = 0
	while bool(pet["alive"]) and tries < 100:
		pet["hunger"] = 0.0
		sys.advance(pet, 5.0)
		tries += 1
	check(not bool(pet["alive"]), "最终死亡")
	var dead: Dictionary = sys.advance(pet, 1.0)
	check(not bool(dead["alive"]), "死后不再推进")
	# 寿命到上限死亡。
	var pet2: Dictionary = sys.acquire("fish", "小金")["pet"]
	pet2["age"] = 10.0
	var r2: Dictionary = sys.advance(pet2, 1.0)
	check(not bool(r2["alive"]), "超寿命死亡")


func _test_lost_and_mood() -> void:
	var sys = PetScript.new()
	var pet: Dictionary = sys.acquire("dog", "来福")["pet"]
	# 存活正向影响。
	var m: Dictionary = sys.mood_effect(pet)
	check(float(m["happiness"]) > 0.0, "宠物提升幸福")
	# 走失：低照护 + 低随机值。
	check(sys.check_lost(pet, 0.0, FixedRng.new([0.0])), "低照护易走失")
	check(bool(pet["lost"]), "走失标记")
	# 死亡情绪事件。
	pet["alive"] = false
	var d: Dictionary = sys.mood_effect(pet)
	check(float(d["mood"]) < 0.0, "宠物死亡降低心情")
	check_eq(str(d["event"]), "pet_death", "死亡情绪事件")
