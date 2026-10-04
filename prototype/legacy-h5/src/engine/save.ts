import type { GameState } from './state'

export const SAVE_KEY = 'life-text-sandbox:save'
export const LEGACY_KEY = 'life-text-sandbox:legacy'
export const SAVE_VERSION = 1

type Migration = (raw: Record<string, unknown>) => Record<string, unknown>

const MIGRATIONS: Record<number, Migration> = {}

/** Upgrade an old save blob to the current schema. */
export function migrate(raw: Record<string, unknown>): Record<string, unknown> {
  let version = (raw.version as number) ?? 0
  let data = raw
  while (version < SAVE_VERSION) {
    const next = MIGRATIONS[version]
    if (!next) break
    data = next(data)
    version += 1
  }
  data.version = SAVE_VERSION
  return data
}

export function serialize(state: GameState): string {
  const clone: Record<string, unknown> = JSON.parse(JSON.stringify(state))
  delete clone.pendingMinutes
  delete clone.pendingSave
  clone.version = SAVE_VERSION
  return JSON.stringify(clone)
}

export function deserialize(json: string): GameState | null {
  try {
    const raw = JSON.parse(json) as Record<string, unknown>
    const migrated = migrate(raw)
    const state = migrated as unknown as GameState
    state.pendingMinutes = 0
    state.pendingSave = false
    return state
  } catch {
    return null
  }
}

export function saveToStorage(state: GameState): boolean {
  try {
    localStorage.setItem(SAVE_KEY, serialize(state))
    return true
  } catch {
    return false
  }
}

export function loadFromStorage(): GameState | null {
  try {
    const json = localStorage.getItem(SAVE_KEY)
    if (!json) return null
    return deserialize(json)
  } catch {
    return null
  }
}

export function clearStorage(): void {
  try {
    localStorage.removeItem(SAVE_KEY)
  } catch {
    // ignore
  }
}

export interface LegacyData {
  totalAchievements: string[]
  legacyPoints: number
  runsCompleted: number
}

export function saveLegacy(data: LegacyData): void {
  try {
    localStorage.setItem(LEGACY_KEY, JSON.stringify(data))
  } catch {
    // ignore
  }
}

export function loadLegacy(): LegacyData | null {
  try {
    const json = localStorage.getItem(LEGACY_KEY)
    if (!json) return null
    return JSON.parse(json) as LegacyData
  } catch {
    return null
  }
}
