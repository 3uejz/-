import type { GameState, Message, WeatherKind, Season } from './state'
import { calendar, dayOf } from './time'

export interface TemplateGroup {
  conditions?: {
    night?: boolean
    weather?: WeatherKind
    season?: Season
    moodLow?: boolean
    moodHigh?: boolean
  }
  texts: string[]
}

export interface NarrativeContext {
  night: boolean
  weather: WeatherKind
  season: Season
  mood: number
}

export function narrate(
  groups: TemplateGroup[],
  ctx: NarrativeContext,
  vars: Record<string, string>,
  rand: () => number,
): string {
  const pool: string[] = []
  for (const g of groups) {
    if (!g.conditions || matchConditions(g.conditions, ctx)) {
      pool.push(...g.texts)
    }
  }
  const text = pool.length > 0 ? pool[Math.floor(rand() * pool.length)] : ''
  return render(text, vars)
}

function matchConditions(c: NonNullable<TemplateGroup['conditions']>, ctx: NarrativeContext): boolean {
  if (c.night !== undefined && c.night !== ctx.night) return false
  if (c.weather !== undefined && c.weather !== ctx.weather) return false
  if (c.season !== undefined && c.season !== ctx.season) return false
  if (c.moodLow !== undefined && c.moodLow !== ctx.mood < 30) return false
  if (c.moodHigh !== undefined && c.moodHigh !== ctx.mood >= 70) return false
  return true
}

export function pickText(texts: string[], rand: () => number): string {
  return texts[Math.floor(rand() * texts.length)]
}

export function render(template: string, vars: Record<string, string>): string {
  return template.replace(/\{(\w+)\}/g, (_, key: string) => vars[key] ?? `{${key}}`)
}

export function pushMessage(state: GameState, kind: Message['kind'], text: string): void {
  state.messages.push({ id: state.nextMessageId++, kind, text, day: dayOf(state.time) })
  if (state.messages.length > 500) {
    state.messages.splice(0, state.messages.length - 500)
  }
}

export function pushNarrative(state: GameState, text: string): void {
  pushMessage(state, 'narrative', text)
}

export function pushResult(state: GameState, text: string): void {
  pushMessage(state, 'result', text)
}

export function pushWarning(state: GameState, text: string): void {
  pushMessage(state, 'warning', text)
}

export function contextVars(state: GameState): Record<string, string> {
  const c = calendar(state.time)
  const seasonName = { spring: '春', summer: '夏', autumn: '秋', winter: '冬' }[c.season]
  const weatherName: Record<WeatherKind, string> = {
    sunny: '晴', rain: '雨', snow: '雪', heatwave: '酷热', coldwave: '严寒',
  }
  return {
    name: state.player.name,
    season: seasonName,
    weather: weatherName[state.weather],
    location: state.player.locationId,
    year: String(c.year),
    age: String(c.age),
  }
}
