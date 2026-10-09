class_name Typewriter
extends RefCounted
## 叙事流打字机（R35、R57；任务 47.3）。
## 默认即时显示；开启后逐字揭示，点击可跳过；减少动态时直接整条显示。

var full_text: String = ""
var revealed_chars: int = 0
var chars_per_second: float = 40.0
var reduce_motion: bool = false
var _accum: float = 0.0

func _init(text: String = "", p_reduce_motion: bool = false) -> void:
	reduce_motion = p_reduce_motion
	start(text)

func start(text: String) -> void:
	full_text = text
	revealed_chars = full_text.length() if reduce_motion else 0
	_accum = 0.0

## 推进 delta 秒，返回当前应显示的文本。
func tick(delta: float) -> String:
	if is_done():
		return full_text
	_accum += delta * chars_per_second
	while _accum >= 1.0 and revealed_chars < full_text.length():
		revealed_chars += 1
		_accum -= 1.0
	return current()

func skip() -> void:
	revealed_chars = full_text.length()

func is_done() -> bool:
	return revealed_chars >= full_text.length()

func current() -> String:
	return full_text.substr(0, revealed_chars)

func progress() -> float:
	if full_text.is_empty():
		return 1.0
	return float(revealed_chars) / float(full_text.length())
