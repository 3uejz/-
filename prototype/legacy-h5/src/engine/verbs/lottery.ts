import type { VerbDef } from './registry'
import type { RNG } from '../rng'
import type { GameState } from '../state'
import { pushMessage, pushResult } from '../narrate'
import { fmtMoney } from '../time'

let pendingTickets = 0

export const LOTTERY: VerbDef = {
  name: 'buyLottery', aliases: ['买彩票', '彩票'], category: '金融', desc: '购买彩票（￥10/张，下月开奖）', usage: '买彩票 [张数]',
  run: (ctx) => {
    const state = ctx.state
    if (state.player.locationId !== 'lottery') return failLottery(ctx.state)
    const count = Math.max(1, Math.min(100, ctx.args.numbers[0] ?? 1))
    const cost = count * 10
    if (state.player.money < cost) {
      pushMessage(state, 'warning', `买 ${count} 张彩票需要 ${fmtMoney(cost)}，现金不足。`)
      return
    }
    state.player.money -= cost
    state.player.stats.totalSpent += cost
    pendingTickets += count
    pushResult(state, `你买下了 ${count} 张彩票。开奖在下月 1 日，祝好运！`)
  },
}

function failLottery(state: GameState): void {
  pushMessage(state, 'warning', '买彩票要去彩票站。输入「去 彩票站」。')
}

/** Called by clock on the 1st of each month. Returns winnings text or null. */
export function drawLottery(state: GameState, rng: RNG): string | null {
  if (pendingTickets <= 0) return null
  const tickets = pendingTickets
  pendingTickets = 0
  if (!rng.chance(0.12)) {
    return `本期彩票开奖，你的 ${tickets} 张彩票全部落空。`
  }
  const prize = rng.weighted(
    [500, 1000, 5000, 20000, 100000, 5000000],
    (v) => (v >= 100000 ? 0.5 : v >= 5000 ? 2 : 20),
  ) ?? 100
  state.player.money += prize
  state.player.stats.totalEarned += prize
  if (prize >= 1000) {
    state.player.stats.milestones.push({ year: 0, text: `彩票中奖${prize}` })
  }
  return `彩票中奖！！你的 ${tickets} 张彩票中了 ${fmtMoney(prize)}！`
}

export function resetLottery(): void {
  pendingTickets = 0
}
