class_name Gregorian
extends RefCounted
## 真实公历时间映射（客户端/后端一致性，见 shared/consistency/README.md）。
## epoch：2000-01-01T00:00:00Z 记为 absolute_minutes = 0。

const BaselineScript = preload("res://sim/baseline.gd")

const EPOCH_UNIX_DAYS: int = BaselineScript.CALENDAR_EPOCH_UNIX_DAYS  # 2000-01-01 距 1970-01-01 的天数
const MINUTES_PER_DAY: int = BaselineScript.CALENDAR_MINUTES_PER_DAY

## 把绝对分钟映射为日历字段。
## 返回：date/year/month/day/hour/minute/weekday_iso(1=周一..7=周日)/season_north。
static func from_absolute_minutes(total_minutes: int) -> Dictionary:
	var days: int = total_minutes / MINUTES_PER_DAY
	var rem: int = total_minutes % MINUTES_PER_DAY
	if rem < 0:
		rem += MINUTES_PER_DAY
		days -= 1
	var hour: int = rem / 60
	var minute: int = rem % 60

	var cal: Dictionary = _civil_from_unix_days(days + EPOCH_UNIX_DAYS)
	var month: int = cal["month"]
	var day: int = cal["day"]
	var year: int = cal["year"]

	return {
		"date": "%04d-%02d-%02d" % [year, month, day],
		"year": year,
		"month": month,
		"day": day,
		"hour": hour,
		"minute": minute,
		"weekday_iso": _weekday_iso(days + EPOCH_UNIX_DAYS),
		"season_north": _season_north(month),
	}

## Howard Hinnant 的 civil_from_days 算法（proleptic Gregorian）。
static func _civil_from_unix_days(unix_days: int) -> Dictionary:
	var z: int = unix_days + 719468
	var era: int = z / 146097
	if z < 0 and z % 146097 != 0:
		era -= 1
	var doe: int = z - era * 146097
	var yoe: int = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
	var y: int = yoe + era * 400
	var doy: int = doe - (365 * yoe + yoe / 4 - yoe / 100)
	var mp: int = (5 * doy + 2) / 153
	var d: int = doy - (153 * mp + 2) / 5 + 1
	var m: int = mp + 3 if mp < 10 else mp - 9
	if m <= 2:
		y += 1
	return {"year": y, "month": m, "day": d}

## ISO-8601 星期：1970-01-01 为周四(4)。
static func _weekday_iso(unix_days: int) -> int:
	return posmod(unix_days + 3, 7) + 1

static func _season_north(month: int) -> String:
	if month >= 3 and month <= 5:
		return "spring"
	if month >= 6 and month <= 8:
		return "summer"
	if month >= 9 and month <= 11:
		return "autumn"
	return "winter"
