import type { GameState, NPC } from '../state'
import { pushMessage } from '../narrate'
import { buildSchedule } from '../../content/npcs'

/** Update NPC positions according to their schedules. Runs hourly. */
export function updateNpcPositions(state: GameState, hour: number): void {
  for (const npc of state.npcs) {
    if (!npc.alive) continue
    const slot = npc.schedule.find((s) => hour >= s.from && hour < s.to)
    if (slot && slot.locationId !== npc.currentLocationId) {
      npc.currentLocationId = slot.locationId
    }
  }
}

/** Relationship decay for NPCs not interacted with, plus gossip spread. Yearly. */
export function yearlySocialDecay(state: GameState): void {
  for (const npc of state.npcs) {
    if (!npc.alive) continue
    if (npc.relationship > 0) npc.relationship = Math.max(0, npc.relationship - 3)
    else if (npc.relationship < 0) npc.relationship = Math.min(0, npc.relationship + 3)
  }
}

/** Gossip: player reputation colours first impressions. Called on encounter. */
export function firstImpression(state: GameState): number {
  const rep = state.player.reputation
  return Math.round(rep / 20)
}

/** Age all NPCs one year; apply life events (marriage, children, death). */
export function yearlyNpcLife(state: GameState, messages: (t: string) => void): void {
  for (const npc of state.npcs) {
    if (!npc.alive) continue
    npc.age += 1
    if (npc.age >= 75 && npc.age % 5 === 0) {
      // Elderly pass away with rising probability.
      const p = (npc.age - 75) * 0.03
      if (Math.random() < p) {
        npc.alive = false
        messages(`${npc.name} 安详地离开了这个世界。`)
        if (state.player.family.spouseNpcId === npc.id) {
          state.player.family.spouseNpcId = null
          state.player.attrs.mood = Math.max(0, state.player.attrs.mood - 30)
          messages('你的伴侣永远地离开了你，悲痛涌上心头。')
        }
        continue
      }
    }
    // NPCs may marry each other after 30.
    if (!npc.spouseNpcId && npc.age >= 28 && npc.age <= 45 && npc.id !== state.player.family.spouseNpcId) {
      if (Math.random() < 0.03) {
        const partner = state.npcs.find(
          (o) => o.alive && o.id !== npc.id && !o.spouseNpcId && o.id !== npc.spouseNpcId &&
                 o.gender !== npc.gender && o.age >= 25 && o.age <= 50 && o.homeId !== 'home',
        )
        if (partner) {
          npc.spouseNpcId = partner.id
          partner.spouseNpcId = npc.id
          messages(`${npc.name} 和 ${partner.name} 喜结连理，你在礼金里随了两百。`)
          state.player.money = Math.max(0, state.player.money - 200)
        }
      }
    }
  }
}

/** Rebuild an NPC's schedule after their job changes. */
export function refreshNpcSchedule(npc: NPC): void {
  const workLocation = npc.jobId ? 'company' : null
  const def = { homeId: npc.homeId, workLocationId: workLocation, leisureLocationId: npc.currentLocationId }
  npc.schedule = buildSchedule(def as never)
}

export function npcGreeting(npc: NPC): string {
  if (npc.relationship >= 80) return `${npc.name}老远就朝你挥手："来啦，老朋友！"`
  if (npc.relationship >= 40) return `${npc.name}微笑着和你打招呼。`
  if (npc.relationship >= 0) return `${npc.name}礼貌性地点了点头。`
  return `${npc.name}冷冷地瞥了你一眼。`
}

export function pushNpcLine(state: GameState, text: string): void {
  pushMessage(state, 'narrative', text)
}
