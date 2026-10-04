import type { GameState } from './state'
import type { RNG } from './rng'
import { MINUTES_PER_DAY, MINUTES_PER_YEAR } from './state'
import { calendar, isNight, rollWeather } from './time'
import { pushMessage, pushWarning } from './narrate'
import { adjustAttr, addItem, removeItem } from './state-helpers'
import { tickMarket, tickStocks, tickPropertyIndex } from './systems/economy'
import { updateNpcPositions, yearlySocialDecay, yearlyNpcLife } from './systems/social'
import { dailyHealth, dailyMood, dailyReputation, dailyLoan, dailyJail } from './systems/life'
import { tryTriggerEvent } from './events/engine'
import { checkAchievements, checkWishes } from './goals'
import { NEW_YEAR_TEXT, WEATHER_ANNOUNCE } from '../content/texts'
import { jobById } from '../content/jobs'
import { PROPERTY_INDEX } from '../content/properties'

export interface ClockHooks {
  autoSave: (state: GameState) => void
}

export function tick(state: GameState, minutes: number, rng: RNG, hooks: ClockHooks): void {
  if (!state.player.alive) return
  const startTotal = state.time.total
  const endTotal = startTotal + minutes
  let cursor = startTotal

  while (cursor < endTotal) {
    const nextHour = Math.ceil((cursor + 1) / 60) * 60
    const nextDay = (Math.floor(cursor / MINUTES_PER_DAY) + 1) * MINUTES_PER_DAY
    const nextYear = (Math.floor(cursor / MINUTES_PER_YEAR) + 1) * MINUTES_PER_YEAR
    const step = Math.min(endTotal, nextHour, nextDay, nextYear) - cursor
    cursor += step
    state.time.total = cursor

    const c = calendar(state.time)

    // Hourly: NPC movement.
    if (cursor % 60 === 0) updateNpcPositions(state, c.hour)

    // Daily settlement.
    if (cursor % MINUTES_PER_DAY === 0) {
      if (dailyJail(state)) {
        hooks.autoSave(state)
        continue
      }
      dailySettlement(state, rng)
    }

    // Yearly settlement.
    if (cursor % MINUTES_PER_YEAR === 0) {
      yearlySettlement(state, rng)
      if (!state.player.alive) return
    }
  }

  // Random events: expected 1-3 per day.
  const elapsedDays = (endTotal - startTotal) / MINUTES_PER_DAY
  const eventCount = Math.floor(elapsedDays * rng.float(1, 3) + rng.next())
  for (let i = 0; i < eventCount; i++) {
    tryTriggerEvent(state, rng)
  }

  // Death checks.
  checkDeath(state)

  checkAchievements(state)
  checkWishes(state)
  hooks.autoSave(state)
}

export function dailySettlement(state: GameState, rng: RNG): void {
  tickMarket(state)
  tickStocks(state, rng)
  dailyHealth(state)
  dailyMood(state)
  dailyReputation(state)
  dailyLoan(state, (t) => pushWarning(state, t))

  // Monthly rent on the 1st of each month.
  const cal = calendar(state.time)
  if (cal.day === 1 && !state.player.estate.propertyId && state.player.estate.rentedId) {
    const rent = PROPERTY_INDEX.get(state.player.estate.rentedId)?.rent ?? 0
    if (state.player.money >= rent) {
      state.player.money -= rent
      state.player.stats.totalSpent += rent
      pushMessage(state, 'system', `月初自动缴纳房租 ${rent} 元。`)
    } else {
      state.player.estate.rentArrears += 1
      pushWarning(state, `房租 ${rent} 元缴不上了，已拖欠 ${state.player.estate.rentArrears} 个月，房东脸色越来越难看。`)
      if (state.player.estate.rentArrears >= 3) {
        pushWarning(state, '房东忍无可忍，把你扫地出门了！你流落街头……')
        state.player.estate.rentedId = null
        state.player.estate.rentArrears = 0
        state.player.attrs.mood = Math.max(0, state.player.attrs.mood - 25)
        state.player.attrs.health = Math.max(0, state.player.attrs.health - 15)
      }
    }
  }

  // Item expiry.
  const expired: string[] = []
  for (const entry of [...state.player.inventory]) {
    if (entry.expiryDays !== undefined) {
      entry.expiryDays -= 1
      if (entry.expiryDays <= 0) {
        removeItem(state, entry.itemId, entry.count)
        expired.push(entry.itemId)
      }
    }
  }
  for (const id of expired) {
    pushWarning(state, `背包里的「${id}」已经过期变质，被你扔掉了。`)
  }

  // Season & weather refresh each morning.
  const c = calendar(state.time)
  if (state.weatherDaysLeft <= 0 || rng.chance(0.3)) {
    state.weather = rollWeather(c.season, () => rng.next())
    state.weatherDaysLeft = rng.int(1, 4)
    pushMessage(state, 'system', WEATHER_ANNOUNCE[state.weather])
  } else {
    state.weatherDaysLeft -= 1
  }
}

export function yearlySettlement(state: GameState, rng: RNG): void {
  const p = state.player
  const c = calendar(state.time)
  tickPropertyIndex(state, rng)

  // Promotion chance with accumulated performance.
  if (p.job) {
    const def = jobById(p.job.jobId)
    if (def.promotion && p.job.performance >= 240) {
      p.job = { jobId: def.promotion, performance: 0, yearsHeld: 0 }
      const promoted = jobById(def.promotion)
      pushMessage(state, 'system', `恭喜！你的出色表现为你赢得了晋升，现在是「${promoted.title}」，月薪 ${promoted.salary} 元。`)
      p.stats.milestones.push({ year: c.year, text: `升职为${promoted.title}` })
      p.reputation += 5
    } else {
      p.job.yearsHeld += 1
      p.job.performance = Math.floor(p.job.performance * 0.6)
    }
  }

  yearlySocialDecay(state)
  yearlyNpcLife(state, (t) => pushMessage(state, 'narrative', t))
  pushMessage(state, 'system', `${NEW_YEAR_TEXT[0]}（${c.year + 1} 年，你 ${c.age} 岁了）`)
}

export function checkDeath(state: GameState): void {
  const p = state.player
  if (!p.alive) return
  const c = calendar(state.time)
  if (p.attrs.health <= 0) {
    p.alive = false
    p.deathCause = 'health'
    state.finished = true
    pushMessage(state, 'system', '你的身体已油尽灯枯……')
    return
  }
  if (c.age >= 90) {
    p.alive = false
    p.deathCause = 'age'
    state.finished = true
    pushMessage(state, 'system', '九十载春秋，你安详地合上了双眼。')
  }
}

/** Helper used by verbs to fast-forward sleep and skip event spam at night. */
export function isSleepyHour(state: GameState): boolean {
  return isNight(state.time)
}

export function grantStarterItems(state: GameState): void {
  addItem(state, 'food_bread', 2, 7)
  adjustAttr(state, 'satiety', 0)
}
