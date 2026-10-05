extends "res://tests/test_base.gd"
## 成就与图鉴测试（任务 22；R29）。

const AchScript = preload("res://sim/achievements.gd")


func _suite_name() -> String:
	return "achievements"


func run_tests() -> void:
	_test_catalog()
	_test_unlock()
	_test_codex_crossrun()


func _test_catalog() -> void:
	var sys = AchScript.new()
	check_eq(AchScript.CATEGORIES.size(), 9, "九类成就")
	check(sys.achievement_count() >= 20, "成就库充足")
	for cat in AchScript.CATEGORIES:
		var found: bool = false
		for id in AchScript.ACHIEVEMENTS:
			if str(AchScript.ACHIEVEMENTS[id]["category"]) == cat:
				found = true
				break
		check(found, "类别 %s 有成就" % cat)


func _test_unlock() -> void:
	var sys = AchScript.new()
	var profile: Dictionary = sys.new_profile()
	check(not sys.is_unlocked(profile, "first_10k"), "初始未解锁")
	var r: Dictionary = sys.check(profile, {"money": 1000000})
	check((r["unlocked"] as Array).has("first_10k"), "条件满足即解锁")
	check(sys.is_unlocked(profile, "first_10k"), "已归档")
	check((profile["announcements"] as Array).size() >= 1, "宣告成就")
	var r2: Dictionary = sys.check(profile, {"money": 1000000})
	check((r2["unlocked"] as Array).is_empty(), "不重复解锁")
	var r3: Dictionary = sys.check(profile, {"money": 100000000})
	check((r3["unlocked"] as Array).has("millionaire"), "更高成就解锁")


func _test_codex_crossrun() -> void:
	var sys = AchScript.new()
	var profile: Dictionary = sys.new_profile()
	sys.add_item(profile, "sword")
	sys.add_character(profile, "npc_1")
	check_eq(int(profile["codex"]["items"].size()), 1, "物品图鉴")
	check_eq(int(profile["codex"]["characters"].size()), 1, "人物图鉴")
	sys.check(profile, {"money": 1000000})
	var m: Dictionary = sys.merge_run(profile, {"achievements": {"jailed": true}, "items": {"shield": true}, "characters": {}})
	check_eq(int(m["runs"]), 1, "周目累计")
	check(int(profile["codex"]["achievements"].size()) >= 2, "跨周目成就累计")
	check((profile["codex"]["items"] as Dictionary).has("shield"), "跨周目物品累计")
