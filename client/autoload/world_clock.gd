extends Node
## 绝对分钟时间真源与日历派生（Autoload）。
## epoch：2000-01-01T00:00:00Z = 0。落盘字段名 clock.total_minutes，见 shared/schemas/save.schema.json。

signal minute_changed(total_minutes: int)
signal hour_changed(total_minutes: int)
signal day_changed(total_minutes: int)
signal season_changed(total_minutes: int)
signal year_changed(total_minutes: int)

var total_minutes: int = 0

## 推进时间；返回本次推进区间。暂停由 SpeedController 负责，不在此处判断。
func advance(minutes: int) -> Dictionary:
	if minutes < 0:
		push_error("WorldClock.advance 不接受负分钟")
		return {}
	var before: int = total_minutes
	total_minutes += minutes
	_dispatch(before, total_minutes)
	return {
		"from": before,
		"to": total_minutes,
		"minutes": minutes,
	}

func set_minutes(value: int) -> void:
	var before: int = total_minutes
	total_minutes = value
	_dispatch(before, total_minutes)

## 当前日历派生（真实公历）。
func calendar() -> Dictionary:
	return Gregorian.from_absolute_minutes(total_minutes)

## 昼夜阶段：dawn/day/dusk/night，边界见 shared/consistency/vectors/baseline.json。
func day_phase() -> String:
	var hour: int = calendar()["hour"]
	if hour >= 5 and hour < 8:
		return "dawn"
	if hour >= 8 and hour < 18:
		return "day"
	if hour >= 18 and hour < 21:
		return "dusk"
	return "night"


func _dispatch(before: int, after: int) -> void:
	if after == before:
		return
	minute_changed.emit(after)
	if before / 60 != after / 60:
		hour_changed.emit(after)
	if before / Gregorian.MINUTES_PER_DAY != after / Gregorian.MINUTES_PER_DAY:
		day_changed.emit(after)
	var cb: Dictionary = Gregorian.from_absolute_minutes(before)
	var ca: Dictionary = Gregorian.from_absolute_minutes(after)
	if cb["season_north"] != ca["season_north"]:
		season_changed.emit(after)
	if cb["year"] != ca["year"]:
		year_changed.emit(after)
