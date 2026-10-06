extends "res://tests/test_base.gd"
## 家族史与族谱测试（任务 42；R97；design「世界记忆与家族史」）。

const GenScript = preload("res://sim/genealogy.gd")


func _suite_name() -> String:
	return "genealogy"


func run_tests() -> void:
	_test_tree_and_generations()
	_test_ancestors_descendants()
	_test_death_and_chronicle()
	_test_search_and_summary()
	_test_persistence()


func _test_tree_and_generations() -> void:
	var sys = GenScript.new()
	var tree: Dictionary = sys.new_tree()
	var grand: Dictionary = sys.add_person(tree, {"name": "祖父"})
	var parent: Dictionary = sys.add_person(tree, {"name": "父亲"})
	var child: Dictionary = sys.add_person(tree, {"name": "孙儿"})
	check(bool(grand["ok"]) and bool(parent["ok"]) and bool(child["ok"]), "添加三代人物")
	check_eq(int(tree["persons"].size()), 3, "三人入树")
	check_eq((tree["roots"] as Array).size(), 3, "初始均为根")
	sys.link_parent_child(tree, str(grand["id"]), str(parent["id"]))
	sys.link_parent_child(tree, str(parent["id"]), str(child["id"]))
	check_eq(int(tree["persons"][str(parent["id"])]["generation"]), 2, "子代世代 +1")
	check_eq(int(tree["persons"][str(child["id"])]["generation"]), 3, "孙代世代 +2")
	check_eq((tree["roots"] as Array).size(), 1, "仅祖辈为根")
	check(not bool(sys.link_parent_child(tree, "nobody", str(child["id"]))["ok"]), "未知人物报错")


func _test_ancestors_descendants() -> void:
	var sys = GenScript.new()
	var tree: Dictionary = sys.new_tree()
	var grand: String = str(sys.add_person(tree, {"name": "祖父"})["id"])
	var parent: String = str(sys.add_person(tree, {"name": "父亲"})["id"])
	var child: String = str(sys.add_person(tree, {"name": "孙儿"})["id"])
	var aunt: String = str(sys.add_person(tree, {"name": "姑母"})["id"])
	sys.link_parent_child(tree, grand, parent)
	sys.link_parent_child(tree, grand, aunt)
	sys.link_parent_child(tree, parent, child)
	var anc: Array = sys.ancestors(tree, child)
	check(anc.has(parent) and anc.has(grand), "追溯到父与祖")
	check_eq(anc.size(), 2, "祖先链去重")
	var desc: Array = sys.descendants(tree, grand)
	check(desc.has(parent) and desc.has(aunt) and desc.has(child), "后代含旁系与孙")
	check_eq(desc.size(), 3, "后代链去重")
	check_eq(sys.ancestors(tree, "nobody").size(), 0, "未知人物无祖先")


func _test_death_and_chronicle() -> void:
	var sys = GenScript.new()
	var tree: Dictionary = sys.new_tree()
	var a: String = str(sys.add_person(tree, {"name": "甲"})["id"])
	sys.mark_death(tree, a, 1000, "寿终")
	check_eq(str(tree["persons"][a]["status"]), "dead", "标记死亡")
	check_eq(int(tree["persons"][a]["death_minute"]), 1000, "记录死亡时刻")
	check_eq(sys.chronicle(tree).size(), 1, "死亡写入历代大事")
	check(not bool(sys.mark_death(tree, "nobody", 0, "x")["ok"]), "未知人物报错")


func _test_search_and_summary() -> void:
	var sys = GenScript.new()
	var tree: Dictionary = sys.new_tree()
	var a: String = str(sys.add_person(tree, {"name": "李慕白"})["id"])
	var b: String = str(sys.add_person(tree, {"name": "李清照"})["id"])
	sys.add_person(tree, {"name": "路人甲"})
	sys.link_parent_child(tree, a, b)
	check_eq(sys.search(tree, "李").size(), 2, "跨代检索姓名")
	check_eq(sys.search(tree, "").size(), 0, "空关键字")
	var s: Dictionary = sys.summary(tree)
	check_eq(int(s["total"]), 3, "总人数")
	check_eq(int(s["alive"]), 3, "存活数")
	check_eq(int(s["generations"]), 2, "最大世代")


func _test_persistence() -> void:
	var sys = GenScript.new()
	var tree: Dictionary = sys.new_tree()
	var a: String = str(sys.add_person(tree, {"name": "甲"})["id"])
	var b: String = str(sys.add_person(tree, {"name": "乙"})["id"])
	sys.link_parent_child(tree, a, b)
	sys.mark_death(tree, a, 500, "意外")
	var clone: Dictionary = sys.from_dict(sys.to_dict(tree))
	check_eq((clone["persons"] as Dictionary).size(), 2, "序列化人物往返")
	check_eq(sys.descendants(clone, a).size(), 1, "序列化后关系保持")
	check_eq(sys.chronicle(clone).size(), 1, "序列化历代大事往返")
