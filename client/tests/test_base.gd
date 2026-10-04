class_name TestBase
extends SceneTree
## headless 测试基类。子类覆写 _suite_name() 与 run_tests()。
## 运行：/workspace/.toolchain/godot --headless --path client --script res://tests/<suite>.gd
## 说明：以 --script 运行时 Autoload 不会挂载，测试用 preload(...).new() 直接实例化。

var failures: int = 0

func _initialize() -> void:
	var name := _suite_name()
	print("[test] %s" % name)
	run_tests()
	if failures == 0:
		print("[test] %s PASS" % name)
	else:
		print("[test] %s FAILURES: %d" % [name, failures])
	quit(failures)

func _suite_name() -> String:
	return "suite"

func run_tests() -> void:
	push_error("未实现 run_tests")

# --- 断言 ---

func check(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)

func check_eq(got: Variant, want: Variant, message: String) -> void:
	if got != want:
		_fail("%s: got=%s want=%s" % [message, str(got), str(want)])

func check_near(got: float, want: float, tolerance: float, message: String) -> void:
	if absf(got - want) > tolerance:
		_fail("%s: got=%.12f want=%.12f" % [message, got, want])

func _fail(message: String) -> void:
	failures += 1
	push_error("[%s] %s" % [_suite_name(), message])

# --- 向量加载 ---

func vectors_path(file_name: String) -> String:
	return ProjectSettings.globalize_path("res://").path_join("../shared/consistency/vectors").path_join(file_name)

func load_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		_fail("无法打开文件: %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		_fail("JSON 解析失败: %s" % path)
		return {}
	return parsed

## 解析无符号 64 位（十六进制字符串），按 32 位半段避免符号溢出。
func parse_u64(text: String) -> int:
	var t: String = text
	if t.begins_with("0x") or t.begins_with("0X"):
		t = t.substr(2)
	if t.length() > 8:
		var high: int = t.substr(0, t.length() - 8).hex_to_int()
		var low: int = t.substr(t.length() - 8).hex_to_int()
		return (high << 32) | (low & 0xFFFFFFFF)
	return t.hex_to_int()
