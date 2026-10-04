import type { CalendarInfo, Season, WeatherKind, WorldTime } from './state'
import { MINUTES_PER_DAY, DAYS_PER_MONTH, MINUTES_PER_YEAR, START_YEAR, ADULT_AGE } from './state'

export function calendar(t: WorldTime): CalendarInfo {
  const totalDays = Math.floor(t.total / MINUTES_PER_DAY)
  const year = START_YEAR + Math.floor(t.total / MINUTES_PER_YEAR)
  const dayOfYear = totalDays % 360
  const month = Math.floor(dayOfYear / DAYS_PER_MONTH) + 1
  const day = (dayOfYear % DAYS_PER_MONTH) + 1
  const hour = Math.floor((t.total % MINUTES_PER_DAY) / 60)
  const minute = t.total % 60
  const weekday = totalDays % 7
  const age = ADULT_AGE + Math.floor(t.total / MINUTES_PER_YEAR)
  const monthOfYear = month
  let season: Season
  if (monthOfYear <= 3 || monthOfYear === 12) season = 'winter'
  else if (monthOfYear <= 6) season = 'spring'
  else if (monthOfYear <= 9) season = 'summer'
  else season = 'autumn'
  return { year, month, day, hour, minute, weekday, age, season }
}

export function formatTime(t: WorldTime): string {
  const c = calendar(t)
  const hh = String(c.hour).padStart(2, '0')
  const mm = String(c.minute).padStart(2, '0')
  const week = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'][c.weekday]
  return `${c.year}年${c.month}月${c.day}日 ${week} ${hh}:${mm}`
}

export function isNight(t: WorldTime): boolean {
  const hour = Math.floor((t.total % MINUTES_PER_DAY) / 60)
  return hour >= 22 || hour < 6
}

export function dayOf(t: WorldTime): number {
  return Math.floor(t.total / MINUTES_PER_DAY)
}

export function yearOf(t: WorldTime): number {
  return Math.floor(t.total / MINUTES_PER_YEAR)
}

export function addMinutes(t: WorldTime, minutes: number): WorldTime {
  return { total: t.total + minutes }
}

export function clamp(v: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, v))
}

export function fmtMoney(n: number): string {
  return `￥${Math.round(n).toLocaleString('zh-CN')}`
}

const WEATHER_BY_SEASON: Record<Season, WeatherKind[]> = {
  spring: ['sunny', 'sunny', 'rain'],
  summer: ['sunny', 'heatwave', 'rain'],
  autumn: ['sunny', 'sunny', 'rain'],
  winter: ['sunny', 'coldwave', 'snow'],
}

export function rollWeather(season: Season, rand: () => number): WeatherKind {
  const pool = WEATHER_BY_SEASON[season]
  return pool[Math.floor(rand() * pool.length)]
}
