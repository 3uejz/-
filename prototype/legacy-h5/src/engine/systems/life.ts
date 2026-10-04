import type { GameState } from '../state'
import { pushMessage, pushWarning } from '../narrate'
import { adjustAttr } from '../state-helpers'

/** Daily health system: starvation, sickness progression, natural recovery. */
export function dailyHealth(state: GameState): void {
  const p = state.player
  const attrs = p.attrs
  // Hunger damages health.
  if (attrs.satiety < 20) {
    adjustAttr(state, 'health', -4)
    pushWarning(state, '你饿得头晕眼花，健康在流失。买点吃的吧。')
  }
  if (attrs.hygiene < 20) {
    adjustAttr(state, 'health', -2)
  }
  // Natural recovery when well fed and rested.
  if (attrs.satiety > 60 && attrs.health < 100) {
    adjustAttr(state, 'health', 2)
  }
  attrs.satiety = Math.max(0, attrs.satiety - 25)
  attrs.hygiene = Math.max(0, attrs.hygiene - 8)
  // Near-death marker achievement hook.
  if (attrs.health >= 60 && p.stats.milestones.some((m) => m.text === '命悬一线')) {
    p.stats.milestones.push({ year: 0, text: '重获新生' })
  }
}

/** Mood drift toward a neutral band influenced by life quality. */
export function dailyMood(state: GameState): void {
  const p = state.player
  let target = 50
  if (p.estate.propertyId) target += 8
  if (p.family.spouseNpcId) target += 6
  if (p.money < 500) target -= 10
  if (p.attrs.health < 40) target -= 10
  const attrs = p.attrs
  attrs.mood = Math.round(attrs.mood + (target - attrs.mood) * 0.15)
  if (attrs.mood < 15) {
    pushMessage(state, 'warning', '你最近情绪低落，做什么都提不起劲。去放松一下吧。')
  }
}

/** Reputation clamp + consequences of extreme reputation. */
export function dailyReputation(state: GameState): void {
  const p = state.player
  p.reputation = Math.max(-100, Math.min(100, p.reputation))
}

/** Bank loan interest and overdue handling. */
export function dailyLoan(state: GameState, push: (t: string) => void): void {
  const loan = state.player.loan
  if (!loan) return
  const interest = Math.round(loan.principal * loan.dailyRate)
  if (state.player.money >= interest) {
    state.player.money -= interest
    state.player.stats.totalSpent += interest
  } else {
    loan.principal += interest
    loan.overdueDays += 1
    if (loan.overdueDays === 30) {
      state.player.credit = Math.max(0, state.player.credit - 30)
      push('贷款逾期 30 天，你的信用评级被下调了。')
    }
  }
}

/** Jail time countdown. */
export function dailyJail(state: GameState): boolean {
  const p = state.player
  if (p.jailDaysLeft > 0) {
    p.jailDaysLeft -= 1
    p.stats.daysInJail += 1
    if (p.jailDaysLeft === 0) {
      p.locationId = 'home'
      pushMessage(state, 'system', '刑满释放。高墙外阳光刺眼，你决定重新做人。')
      p.reputation = Math.max(-100, p.reputation - 10)
      return false
    }
    return true
  }
  return false
}
