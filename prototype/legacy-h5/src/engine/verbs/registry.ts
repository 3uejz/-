import type { GameState } from '../state'
import type { RNG } from '../rng'
import type { ParsedCommand } from '../parser/resolver'

export interface VerbContext {
  state: GameState
  args: ParsedCommand
  rng: RNG
}

export interface VerbDef {
  name: string
  aliases: string[]
  category: '移动' | '生存' | '成长' | '工作' | '金融' | '地产' | '经营' | '社交' | '医疗' | '休闲' | '风险' | '系统'
  desc: string
  usage?: string
  hidden?: boolean
  run: (ctx: VerbContext) => void
}

export const VERB_REGISTRY = new Map<string, VerbDef>()

export function registerVerb(def: VerbDef): void {
  VERB_REGISTRY.set(def.name, def)
}

export function matchVerbPrefix(input: string): { verb: string | null; length: number } {
  let best: { verb: string | null; length: number } = { verb: null, length: 0 }
  for (const [name, def] of VERB_REGISTRY) {
    if (input.startsWith(name) && name.length > best.length) best = { verb: name, length: name.length }
    for (const alias of def.aliases) {
      if (input.startsWith(alias) && alias.length > best.length) best = { verb: name, length: alias.length }
    }
  }
  return best
}

export function verbsByCategory(): Map<string, VerbDef[]> {
  const map = new Map<string, VerbDef[]>()
  for (const def of VERB_REGISTRY.values()) {
    if (def.hidden) continue
    const list = map.get(def.category) ?? []
    list.push(def)
    map.set(def.category, list)
  }
  return map
}
