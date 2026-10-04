import type { GameState, Wish, WishKind } from './state'
import { ACHIEVEMENTS } from '../content/achievements'
import { pushMessage } from './narrate'

/** Check all un-earned achievements; unlock newly satisfied ones. */
export function checkAchievements(state: GameState): void {
  for (const a of ACHIEVEMENTS) {
    if (state.achievements.includes(a.id)) continue
    let ok = false
    try {
      ok = a.check(state)
    } catch {
      ok = false
    }
    if (ok) {
      state.achievements.push(a.id)
      if (!state.legacy.totalAchievements.includes(a.id)) {
        state.legacy.totalAchievements.push(a.id)
        state.legacy.legacyPoints += 1
      }
      pushMessage(state, 'system', `成就解锁「${a.name}」：${a.desc}`)
    }
  }
}

let wishSeq = 1

export function makeWish(kind: WishKind, target: number): Wish | null {
  const labels: Record<WishKind, (t: number) => string> = {
    money: (t) => `攒下 ￥${t.toLocaleString('zh-CN')}`,
    skill: (t) => `任意技能达到 ${t} 级`,
    job: () => '找到一份工作',
    family: () => '组建家庭',
    estate: () => '拥有自己的房子',
    reputation: (t) => `声望达到 ${t}`,
    age: (t) => `健康活到 ${t} 岁`,
    business: () => '拥有一家自己的店铺',
  }
  if (!labels[kind]) return null
  return {
    id: `wish_${wishSeq++}_${Date.now() % 100000}`,
    kind,
    label: labels[kind](target),
    target,
    progress: 0,
    done: false,
  }
}

export function wishProgress(state: GameState, w: Wish): number {
  const p = state.player
  switch (w.kind) {
    case 'money': return p.money + p.bank
    case 'skill': return Math.max(0, ...Object.values(p.skills).map((s) => s.level))
    case 'job': return p.job ? 1 : 0
    case 'family': return p.family.spouseNpcId ? 1 : 0
    case 'estate': return p.estate.propertyId ? 1 : 0
    case 'reputation': return Math.max(0, p.reputation)
    case 'age': return w.progress
    case 'business': return p.shop ? 1 : 0
    default: return 0
  }
}

/** Update wish progress and celebrate newly completed wishes. */
export function checkWishes(state: GameState): void {
  for (const w of state.player.wishes) {
    if (w.done) continue
    const progress = wishProgress(state, w)
    w.progress = progress
    if (progress >= w.target) {
      w.done = true
      state.player.attrs.mood = Math.min(100, state.player.attrs.mood + 15)
      pushMessage(state, 'system', `人生愿望达成「${w.label}」！为自己骄傲一下吧。`)
    }
  }
}
