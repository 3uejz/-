package sim

import "fmt"

// 时间常量。epoch：2000-01-01T00:00:00Z 记为 absolute_minutes = 0。
const (
	// EpochUnixDays 是 2000-01-01 距 1970-01-01 的天数。
	EpochUnixDays = 10957
	// MinutesPerDay 每日分钟数。
	MinutesPerDay = 1440
)

// Calendar 是绝对分钟映射出的日历字段。
type Calendar struct {
	Date        string
	Year        int
	Month       int
	Day         int
	Hour        int
	Minute      int
	WeekdayISO  int // 1=周一 .. 7=周日
	SeasonNorth string
}

// FromAbsoluteMinutes 把绝对分钟映射为真实公历字段。
func FromAbsoluteMinutes(totalMinutes int64) Calendar {
	days := totalMinutes / MinutesPerDay
	rem := totalMinutes % MinutesPerDay
	if rem < 0 {
		rem += MinutesPerDay
		days--
	}
	hour := int(rem / 60)
	minute := int(rem % 60)

	unixDays := days + EpochUnixDays
	year, month, day := civilFromUnixDays(unixDays)

	return Calendar{
		Date:        fmt.Sprintf("%04d-%02d-%02d", year, month, day),
		Year:        year,
		Month:       month,
		Day:         day,
		Hour:        hour,
		Minute:      minute,
		WeekdayISO:  weekdayISO(unixDays),
		SeasonNorth: seasonNorth(month),
	}
}

// civilFromUnixDays 使用 Howard Hinnant 的 civil_from_days 算法（proleptic Gregorian）。
func civilFromUnixDays(unixDays int64) (year, month, day int) {
	z := unixDays + 719468
	era := z / 146097
	if z < 0 && z%146097 != 0 {
		era--
	}
	doe := z - era*146097
	yoe := (doe - doe/1460 + doe/36524 - doe/146096) / 365
	y := yoe + era*400
	doy := doe - (365*yoe + yoe/4 - yoe/100)
	mp := (5*doy + 2) / 153
	d := doy - (153*mp+2)/5 + 1
	m := mp + 3
	if mp >= 10 {
		m = mp - 9
	}
	if m <= 2 {
		y++
	}
	return int(y), int(m), int(d)
}

// weekdayISO：1970-01-01 为周四(4)。
func weekdayISO(unixDays int64) int {
	return int(posMod(unixDays+3, 7)) + 1
}

func seasonNorth(month int) string {
	switch {
	case month >= 3 && month <= 5:
		return "spring"
	case month >= 6 && month <= 8:
		return "summer"
	case month >= 9 && month <= 11:
		return "autumn"
	default:
		return "winter"
	}
}

func posMod(a, b int64) int64 {
	m := a % b
	if m < 0 {
		m += b
	}
	return m
}
