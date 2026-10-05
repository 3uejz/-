extends "res://tests/test_base.gd"
## 遗产继承、争产与监护权测试（任务 18；R51.5；design D11、D3）。

const InheritanceScript = preload("res://sim/inheritance.gd")


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
	return "inheritance"


func run_tests() -> void:
	_test_tax()
	_test_intestate()
	_test_will()
	_test_dispute_guardian()


func _test_tax() -> void:
	var sys = InheritanceScript.new()
	check_near(sys.estate_tax(500000.0), 0.0, 1e-6, "起征点内免税")
	check_near(sys.estate_tax(1000000.0), 50000.0, 1e-6, "超额累进")


func _test_intestate() -> void:
	var sys = InheritanceScript.new()
	# 无遗嘱、两名子女 → 均分。
	var r: Dictionary = sys.settle(1000000.0, {"valid": false}, {"children": ["a", "b"]})
	check_near(float(r["tax"]), 50000.0, 1e-6, "遗产税")
	check_near(float(r["net"]), 950000.0, 1e-6, "净遗产")
	check_eq(r["allocations"].size(), 2, "两名继承人")
	check_near(float(r["allocations"][0]["amount"]), 475000.0, 1e-6, "均分")
	check_eq(str(r["allocations"][0]["basis"]), "children", "法定顺序子女")
	# 配偶优先于子女。
	var r2: Dictionary = sys.settle(600000.0, {"valid": false}, {"spouse": ["s"], "children": ["a"]})
	check_eq(r2["allocations"].size(), 1, "配偶优先独得")
	check_eq(str(r2["allocations"][0]["id"]), "s", "归配偶")
	# 无人继承 → 归公。
	var r3: Dictionary = sys.settle(100000.0, {"valid": false}, {})
	check(bool(r3["escheat"]), "无人继承")

func _test_will() -> void:
	var sys = InheritanceScript.new()
	var will: Dictionary = {"valid": true, "beneficiaries": [{"id": "x", "share": 3.0}, {"id": "y", "share": 1.0}]}
	var r: Dictionary = sys.settle(1000000.0, will, {})
	check_eq(r["allocations"].size(), 2, "按遗嘱分配")
	check_near(float(r["allocations"][0]["amount"]), 950000.0 * 0.75, 1e-3, "遗嘱份额")
	check_eq(str(r["allocations"][0]["basis"]), "will", "依据遗嘱")


func _test_dispute_guardian() -> void:
	var sys = InheritanceScript.new()
	check(not bool(sys.dispute([{"id": "a"}], false)["litigation"]), "单一继承无争产")
	var d: Dictionary = sys.dispute([{"id": "a"}, {"id": "b"}], true, FixedRng.new([0.0]))
	check(bool(d["litigation"]), "多子争产触发诉讼")
	check(float(d["probability"]) > 0.0, "争产概率")
	var g: Dictionary = sys.guardianship(["minor1"], [{"id": "u1", "suitability": 0.4}, {"id": "u2", "suitability": 0.9}])
	check_eq(str(g["guardian"]["id"]), "u2", "择适配度最高监护人")
	check(bool(g["ok"]), "监护权判定成功")
