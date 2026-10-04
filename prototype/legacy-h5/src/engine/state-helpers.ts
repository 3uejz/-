import type { Attrs, AttrKey, GameState } from './state'

/** Central, logged money mutation. Returns the applied delta (clamped at 0 floor). */
export function addMoney(state: GameState, delta: number, source: string): number {
  const p = state.player
  if (delta >= 0) {
    p.money += delta
    if (source !== 'loan' && source !== 'bank-withdraw') p.stats.totalEarned += delta
  } else {
    const applied = Math.max(delta, -p.money)
    p.money += applied
    if (source !== 'bank-deposit' && source !== 'loan-repay') p.stats.totalSpent += -applied
  }
  return delta
}

export function adjustAttr(state: GameState, key: AttrKey, delta: number): void {
  const attrs = state.player.attrs
  attrs[key] = clampAttr(attrs[key] + delta)
}

export function adjustAttrs(state: GameState, delta: Partial<Attrs>): void {
  for (const key of Object.keys(delta) as AttrKey[]) {
    adjustAttr(state, key, delta[key]!)
  }
}

export function clampAttr(v: number): number {
  return Math.max(0, Math.min(100, v))
}

export function skillLevel(state: GameState, skillId: string): number {
  return state.player.skills[skillId]?.level ?? 0
}

export function hasLicense(state: GameState, licenseId: string): boolean {
  return state.player.licenses.includes(licenseId)
}

export function findItem(state: GameState, itemId: string) {
  return state.player.inventory.find((e) => e.itemId === itemId)
}

export function addItem(state: GameState, itemId: string, count = 1, expiryDays?: number): void {
  const entry = state.player.inventory.find((e) => e.itemId === itemId)
  if (entry) {
    entry.count += count
    if (expiryDays !== undefined) entry.expiryDays = expiryDays
  } else {
    state.player.inventory.push({ itemId, count, expiryDays })
  }
}

export function removeItem(state: GameState, itemId: string, count = 1): boolean {
  const entry = findItem(state, itemId)
  if (!entry || entry.count < count) return false
  entry.count -= count
  if (entry.count <= 0) {
    state.player.inventory = state.player.inventory.filter((e) => e !== entry)
  }
  return true
}

export function npcById(state: GameState, npcId: string) {
  return state.npcs.find((n) => n.id === npcId)
}
