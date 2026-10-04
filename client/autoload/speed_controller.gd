extends Node
## 倍速与快进控制（Autoload）。
## 档位：暂停 / 1x / 2x / 4x / 60x / 3600x / 86400x。1x 为 1:1 实时。

signal speed_changed(level: int)
signal interrupted(reason: String)

const PAUSED: int = 0
const LEVELS: Array[int] = [0, 1, 2, 4, 60, 3600, 86400]

var _level: int = 1
var _target_minutes: int = -1
var _interruptible: bool = true

func set_speed(level: int) -> void:
	if not LEVELS.has(level):
		push_error("非法倍速档位: %d" % level)
		return
	_level = level
	if level < 60:
		_target_minutes = -1
	speed_changed.emit(_level)

func get_speed() -> int:
	return _level

func is_paused() -> bool:
	return _level == PAUSED

## 每现实秒推进的游戏秒数（1x = 1:1）。
func time_scale() -> float:
	return float(_level)

## 每现实秒推进的游戏分钟。
func minutes_per_real_second() -> float:
	return time_scale() / 60.0

## 按现实秒增量计算应推进的游戏分钟。
func advance(delta_seconds: float) -> float:
	if _level <= 0:
		return 0.0
	return delta_seconds * minutes_per_real_second()

## 设置「快进到某绝对分钟」，至少进入快进档；到达由调用方判定。
func fast_forward_to(target_total_minutes: int) -> void:
	_target_minutes = target_total_minutes
	if _level < 60:
		set_speed(60)

func target_minutes() -> int:
	return _target_minutes

func clear_target() -> void:
	_target_minutes = -1

func set_interruptible(value: bool) -> void:
	_interruptible = value

func is_interruptible() -> bool:
	return _interruptible

## 关键事件/健康危机中断：暂停并清除快进目标（可配置为不可中断）。
func interrupt(reason: String = "") -> void:
	if not _interruptible:
		return
	_level = PAUSED
	_target_minutes = -1
	speed_changed.emit(_level)
	interrupted.emit(reason)
