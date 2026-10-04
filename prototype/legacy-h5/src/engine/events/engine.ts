import type { EventEffect, GameState } from '../state'
import type { RNG } from '../rng'
import type { GameEventDef } from '../../content/events'
import { EVENTS } from '../../content/events'
import { pushMessage, pushWarning } from '../narrate'
import { addMoney, adjustAttr, addItem, npcById } from '../state-helpers'

const EVENT_INDEX = new Map(EVENTS.map((e) => [e.id, e]))

/** Try to trigger a random event, weighted, with per-event cooldown. */
export function tryTriggerEvent(state: GameState, rng: RNG): void {
  if (state.activeEvent || !state.player.alive) return
  const today = Math.floor(state.time.total / 1440)
  const candidates = EVENTS.filter((e) => {
    const cd = state.eventCooldowns[e.id] ?? -999
    return today - cd >= 5
  })
  const chosen = rng.weighted(candidates, (e) => e.weight)
  if (!chosen) return
  state.eventCooldowns[chosen.id] = today
  state.player.stats.milestones.push({ year: 0, text: `事件:${chosen.id}` })

  if (chosen.options && chosen.options.length > 0) {
    state.activeEvent = {
      eventId: chosen.id,
      text: chosen.text,
      options: chosen.options.map((o) => ({ label: o.label, outcomeText: o.outcomeText, effects: o.effects })),
    }
    pushMessage(state, 'event', chosen.text)
  } else {
    applyEffects(state, chosen.effects ?? [], rng)
    pushMessage(state, 'event', chosen.text)
    pushMessage(state, 'result', summarizeEffects(chosen.effects ?? []))
  }
}

export function chooseEventOption(state: GameState, index: number, rng: RNG): void {
  const active = state.activeEvent
  if (!active) return
  const option = active.options[index]
  state.activeEvent = null
  if (!option) return
  applyEffects(state, option.effects, rng)
  pushMessage(state, 'result', option.outcomeText)
}

export function summarizeEffects(effects: EventEffect[]): string {
  if (effects.length === 0) return '（什么也没发生。）'
  const parts: string[] = []
  for (const e of effects) {
    switch (e.kind) {
      case 'money': parts.push(`${e.value >= 0 ? '获得' : '支出'} ￥${Math.abs(e.value)}`); break
      case 'attrs': parts.push(`${attrName(e.target ?? 'mood')}${e.value >= 0 ? '+' : ''}${e.value}`); break
      case 'relationship': parts.push(`关系${e.value >= 0 ? '+' : ''}${e.value}`); break
      case 'reputation': parts.push(`声望${e.value >= 0 ? '+' : ''}${e.value}`); break
      case 'item': parts.push(`获得物品×${e.value}`); break
      case 'marketFactor': parts.push('市场波动'); break
      case 'weather': parts.push('天气变化'); break
    }
  }
  return parts.join('，')
}

function attrName(key: string): string {
  const names: Record<string, string> = {
    health: '健康', stamina: '体力', mood: '心情', intellect: '智力',
    charm: '魅力', satiety: '饱食', hygiene: '清洁',
  }
  return names[key] ?? key
}

export function applyEffects(state: GameState, effects: EventEffect[], rng: RNG): void {
  for (const e of effects) {
    switch (e.kind) {
      case 'money': addMoney(state, e.value, 'event'); break
      case 'attrs': adjustAttr(state, (e.target ?? 'mood') as never, e.value); break
      case 'relationship': {
        const target = e.target === 'random' ? randomAliveNpc(state, rng) : npcById(state, e.target ?? '')
        if (target) target.relationship = Math.max(-100, Math.min(100, target.relationship + e.value))
        break
      }
      case 'reputation': state.player.reputation += e.value; break
      case 'item': if (e.target) addItem(state, e.target, e.value); break
      case 'marketFactor': {
        const key = e.target ?? 'food'
        const cur = state.market.categoryFactor[key] ?? 1
        state.market.categoryFactor[key] = Math.max(0.5, Math.min(2, cur + e.value))
        break
      }
      case 'weather': break
    }
  }
}

function randomAliveNpc(state: GameState, rng: RNG) {
  const alive = state.npcs.filter((n) => n.alive)
  return alive.length > 0 ? rng.pick(alive) : undefined
}

export function eventById(id: string): GameEventDef | undefined {
  return EVENT_INDEX.get(id)
}

export function warnActiveEvent(state: GameState): void {
  pushWarning(state, '有一个事件等待你做出选择！')
}
