import type { GameState } from '../state'
import { LOCATIONS, LOCATION_BY_NAME } from '../../content/locations'
import { ITEMS, itemByName } from '../../content/items'
import { JOB_BY_NAME, SKILL_BY_NAME, EDUCATION_BY_NAME, LICENSE_BY_NAME } from '../../content/jobs'
import { STOCK_BY_NAME } from '../../content/stocks'
import { PROPERTY_BY_NAME } from '../../content/properties'
import { NPC_DEFS } from '../../content/npcs'
import { TALENT_BY_NAME } from '../legacy'
import type { WordIndex, WordTarget, Token } from './tokenizer'
import { segmentRemainder, fuzzySuggest } from './tokenizer'
import { VERB_REGISTRY, matchVerbPrefix } from '../verbs/registry'

let cachedIndex: WordIndex | null = null

/** Build (and cache) the merged word index from all content tables. */
export function buildWordIndex(): WordIndex {
  if (cachedIndex) return cachedIndex
  const words = new Map<string, WordTarget>()
  const add = (name: string, type: WordTarget['type'], id: string) => {
    if (name && !words.has(name)) words.set(name, { type, id })
  }
  for (const loc of LOCATIONS) {
    add(loc.name, 'location', loc.id)
    for (const a of loc.aliases) add(a, 'location', loc.id)
  }
  for (const item of ITEMS) add(item.name, 'item', item.id)
  for (const def of NPC_DEFS) add(def.name, 'npc', def.id)
  for (const [name, def] of SKILL_BY_NAME) add(name, 'skill', def.id)
  for (const [name, def] of JOB_BY_NAME) add(name, 'job', def.id)
  for (const [name, def] of STOCK_BY_NAME) add(name, 'stock', def.id)
  for (const [name, def] of PROPERTY_BY_NAME) add(name, 'property', def.id)
  for (const [name, def] of LICENSE_BY_NAME) add(name, 'license', def.id)
  for (const [name, def] of EDUCATION_BY_NAME) add(name, 'education', def.id)
  for (const [name, def] of TALENT_BY_NAME) add(name, 'talent', def.id)
  for (const w of ['money', 'skill', 'reputation', 'age']) add(w, 'wishKind', w)
  for (const k of ['status', 'bag', 'map', 'relations', 'assets', 'shop', 'stocks', 'achievement', 'wish']) add(k, 'stat', k)
  let maxLen = 1
  for (const w of words.keys()) maxLen = Math.max(maxLen, w.length)
  cachedIndex = { words, maxLen }
  return cachedIndex
}

export interface ParsedCommand {
  verb: string
  tokens: Token[]
  targets: Partial<Record<WordTarget['type'], string>>
  numbers: number[]
  raw: string
}

export interface ParseResult {
  ok: boolean
  command?: ParsedCommand
  error?: string
  suggestions?: string[]
}

/** Parse a raw user command string into a structured command. */
export function parseCommand(raw: string, state: GameState): ParseResult {
  const cleaned = raw.replace(/\s+/g, '')
  if (!cleaned) return { ok: false, error: '请输入指令。输入「帮助」查看可用指令。' }

  const { verb, length: remainderStart } = matchVerbPrefix(cleaned)

  if (!verb) {
    // Unknown verb: suggest.
    const idx = buildWordIndex()
    const verbWords = [...VERB_REGISTRY.keys()]
    const suggestions = verbWords
      .filter((v) => cleaned.startsWith(v.slice(0, 1)) || v.includes(cleaned.slice(0, 2)))
      .slice(0, 4)
    const fuzzy = fuzzySuggest(cleaned.slice(0, 2), idx, 2)
    return {
      ok: false,
      error: `无法理解「${raw}」。`,
      suggestions: [...new Set([...suggestions, ...fuzzy])],
    }
  }

  const remainder = cleaned.slice(remainderStart)
  const index = buildWordIndex()
  const tokens = segmentRemainder(remainder, index)
  const targets: ParsedCommand['targets'] = {}
  const numbers: number[] = []
  const textParts: string[] = []
  for (const t of tokens) {
    if (t.kind === 'number') numbers.push(Number(t.value))
    else if (t.kind === 'word' && t.target) {
      // First target of each type wins.
      if (!targets[t.target.type]) targets[t.target.type] = t.target.id
    } else if (t.kind === 'text') textParts.push(t.value)
  }
  void state
  return {
    ok: true,
    command: { verb, tokens, targets, numbers, raw: cleaned },
  }
}

/** Completion candidates for the input bar. */
export function completionCandidates(prefix: string): string[] {
  const cleaned = prefix.replace(/\s+/g, '')
  if (!cleaned) return []
  const index = buildWordIndex()
  const out: string[] = []
  for (const [verbId, def] of VERB_REGISTRY) {
    if (def.hidden) continue
    if (verbId.startsWith(cleaned) || def.aliases.some((a) => a.startsWith(cleaned))) out.push(verbId)
  }
  if (out.length < 6) {
    for (const word of index.words.keys()) {
      if (word.startsWith(cleaned)) out.push(word)
      if (out.length >= 8) break
    }
  }
  return out.slice(0, 8)
}

export { LOCATION_BY_NAME, itemByName }
