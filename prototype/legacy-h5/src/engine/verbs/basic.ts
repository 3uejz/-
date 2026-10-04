import type { VerbDef, VerbContext } from './registry'
import { registerVerb } from './registry'
import { LOCATION_INDEX, LOCATION_BY_NAME, DISTRICT_DISTANCE, DISTRICT_NAMES } from '../../content/locations'
import { itemByName, itemById, ITEMS } from '../../content/items'
import { pushMessage, pushResult, pushWarning, narrate, pickText, contextVars } from '../narrate'
import { calendar, formatTime, isNight, fmtMoney } from '../time'
import { addMoney, adjustAttrs, removeItem, addItem } from '../state-helpers'
import { itemPrice } from '../systems/economy'
import { MOVE_TEMPLATES, SLEEP_TEMPLATES, EAT_TEMPLATES, BUY_TEMPLATES } from '../../content/texts'
import type { NarrativeContext } from '../narrate'
import { verbsByCategory } from './registry'

export class VerbAbort extends Error {}

function fail(ctx: VerbContext, msg: string): never {
  pushWarning(ctx.state, msg)
  throw new VerbAbort()
}

function narrativeCtx(ctx: VerbContext): NarrativeContext {
  const c = calendar(ctx.state.time)
  return {
    night: isNight(ctx.state.time),
    weather: ctx.state.weather,
    season: c.season,
    mood: ctx.state.player.attrs.mood,
  }
}

// ---------------- 移动 ----------------

function travelTime(ctx: VerbContext, destId: string, mode: 'walk' | 'bus' | 'taxi' | 'drive'): { minutes: number; cost: number } {
  const dest = LOCATION_INDEX.get(destId)!
  const cur = LOCATION_INDEX.get(ctx.state.player.locationId)!
  const base = Math.abs(DISTRICT_DISTANCE[dest.district] - DISTRICT_DISTANCE[cur.district]) + 10
  const factor: Record<string, number> = { walk: 1, bus: 0.5, taxi: 0.35, drive: 0.3 }
  const costMap: Record<string, number> = { walk: 0, bus: 2, taxi: 15, drive: 5 }
  const vehicle = ctx.state.player.vehicle.vehicleItemId
  const eff = vehicle === 'veh_ebike' ? 0.7 : vehicle === 'veh_usedCar' || vehicle === 'veh_newCar' || vehicle === 'veh_luxury' ? 0.3 : 1
  return {
    minutes: Math.max(5, Math.round(base * factor[mode] * eff)),
    cost: costMap[mode],
  }
}

function doGo(ctx: VerbContext, mode: 'walk' | 'bus' | 'taxi' | 'drive'): void {
  const state = ctx.state
  const destId = ctx.args.targets.location
  if (!destId) return fail(ctx, `你要去哪里？输入「去 地点名」，例如「去 公园」。`)
  const dest = LOCATION_INDEX.get(destId)
  if (!dest) return fail(ctx, '那个地方似乎不存在。')
  if (destId === state.player.locationId) return fail(ctx, `你已经在这里了（${dest.name}）。`)
  if (state.player.jailDaysLeft > 0) return fail(ctx, '你正在服刑，无法离开监狱。')
  const destDistrict = dest.district
  if (mode === 'walk' && Math.abs(DISTRICT_DISTANCE[destDistrict] - DISTRICT_DISTANCE[LOCATION_INDEX.get(state.player.locationId)!.district]) > 40) {
    return fail(ctx, `${dest.name}太远了，步行无法到达，试试「坐公交」或「打车」。`)
  }
  const { minutes, cost } = travelTime(ctx, destId, mode)
  if (state.player.money < cost) return fail(ctx, `${mode === 'taxi' ? '打车' : '乘车'}需要 ${fmtMoney(cost)}，你的现金不够。`)
  addMoney(state, -cost, 'transport')
  adjustAttrs(state, { stamina: mode === 'walk' ? -8 : -2, satiety: -3 })
  state.player.locationId = destId
  state.pendingMinutes = minutes
  const vars = { ...contextVars(state), dest: dest.name }
  const text = narrate(MOVE_TEMPLATES, narrativeCtx(ctx), vars, () => ctx.rng.next())
  pushResult(state, `「${dest.name}」(${DISTRICT_NAMES[dest.district]}) — ${text}`)
  pushMessage(state, 'system', formatTime(state.time))
}

const goDef: VerbDef = {
  name: 'go', aliases: ['去', '前往', 'g'], category: '移动', desc: '步行前往某地', usage: '去 <地点>',
  run: (ctx) => doGo(ctx, 'walk'),
}

const busDef: VerbDef = {
  name: 'bus', aliases: ['坐公交', '公交'], category: '移动', desc: '乘公交前往某地（￥2）', usage: '坐公交 <地点>',
  run: (ctx) => doGo(ctx, 'bus'),
}

const taxiDef: VerbDef = {
  name: 'taxi', aliases: ['打车', '坐出租'], category: '移动', desc: '打车前往某地（￥15）', usage: '打车 <地点>',
  run: (ctx) => doGo(ctx, 'taxi'),
}

const driveDef: VerbDef = {
  name: 'drive', aliases: ['开车'], category: '移动', desc: '开车前往某地（需自有车辆）', usage: '开车去 <地点>',
  run: (ctx) => {
    if (!ctx.state.player.vehicle.vehicleItemId) return fail(ctx, '你还没有车。先去车行买一辆吧。')
    doGo(ctx, 'drive')
  },
}

// ---------------- 生存 ----------------

const sleepDef: VerbDef = {
  name: 'sleep', aliases: ['睡觉', '睡'], category: '生存', desc: '睡 8 小时，恢复体力与健康', usage: '睡觉',
  run: (ctx) => {
    const state = ctx.state
    if (state.player.locationId !== 'home' && state.player.locationId !== 'jail') {
      return fail(ctx, '只能在家里睡觉。先「回家」吧。')
    }
    const vars = contextVars(state)
    pushResult(state, narrate(SLEEP_TEMPLATES, narrativeCtx(ctx), vars, () => ctx.rng.next()))
    adjustAttrs(state, { stamina: 70, health: 10, mood: 5, satiety: -20 })
    state.pendingMinutes = 8 * 60
    pushMessage(state, 'system', '一觉醒来，又是新的一天。')
  },
}

const waitDef: VerbDef = {
  name: 'wait', aliases: ['等待', '等'], category: '生存', desc: '消磨 N 小时时间', usage: '等待 <小时数>',
  run: (ctx) => {
    const hours = Math.min(12, Math.max(1, ctx.args.numbers[0] ?? 1))
    adjustAttrs(ctx.state, { stamina: -hours * 3, satiety: -hours * 3 })
    ctx.state.pendingMinutes = hours * 60
    pushResult(ctx.state, `你消磨了 ${hours} 个小时。`)
  },
}

const eatDef: VerbDef = {
  name: 'eat', aliases: ['吃', '用餐'], category: '生存', desc: '吃背包里的食物，或就地用餐', usage: '吃 <食物>',
  run: (ctx) => {
    const state = ctx.state
    const itemName = [...ctx.args.tokens].find((t) => t.kind === 'text' || t.kind === 'word')
    const foodName = ctx.args.tokens.find((t) => t.target?.type === 'item')?.value
    let item = foodName ? itemByName(foodName) : undefined
    if (!item) {
      // Find any food in inventory.
      const entry = state.player.inventory.find((e) => itemById(e.itemId).category === 'food')
      if (entry) item = itemById(entry.itemId)
    }
    if (!item) {
      // Dine out at current location.
      const loc = LOCATION_INDEX.get(state.player.locationId)
      if (loc?.shop && ['restaurant', 'fastFood', 'cafe', 'nightMarket'].includes(loc.shop)) {
        return fail(ctx, '你背包里没有食物。可以用「买 <食物>」在这里点餐。')
      }
      return fail(ctx, '你背包里没有食物。去超市买点吃的吧。')
    }
    void itemName
    const price = item.price
    if (!removeItem(state, item.id, 1)) return fail(ctx, `你没有「${item.name}」。`)
    const effect = item.effect ?? { satiety: 15 }
    adjustAttrs(state, effect)
    const vars = { ...contextVars(state), item: item.name }
    pushResult(state, narrate(EAT_TEMPLATES, narrativeCtx(ctx), vars, () => ctx.rng.next()))
    void price
  },
}

const cookDef: VerbDef = {
  name: 'cook', aliases: ['做饭'], category: '生存', desc: '在家做饭（需食材，省钱的吃法）', usage: '做饭',
  run: (ctx) => {
    const state = ctx.state
    if (state.player.locationId !== 'home') return fail(ctx, '只有在家的厨房才能做饭。')
    const cooking = state.player.skills['cooking']?.level ?? 0
    const cost = Math.max(3, 12 - cooking)
    if (state.player.money < cost) return fail(ctx, `家里的食材不够了，采购需要约 ${fmtMoney(cost)}。`)
    addMoney(state, -cost, 'food')
    const satiety = 35 + cooking * 3
    adjustAttrs(state, { satiety, mood: 4 + Math.floor(cooking / 2) })
    ctx.state.pendingMinutes = 60
    pushResult(state, `你在厨房忙活了一阵，做了一顿可口的家常饭（花费 ${fmtMoney(cost)}）。`)
  },
}

const useDef: VerbDef = {
  name: 'use', aliases: ['用', '使用', '吃掉'], category: '生存', desc: '使用药品/阅读书籍等', usage: '用 <物品>',
  run: (ctx) => {
    const state = ctx.state
    const itemToken = ctx.args.tokens.find((t) => t.target?.type === 'item')
    if (!itemToken) {
      const hasMed = state.player.inventory.some((e) => itemById(e.itemId).category === 'medicine')
      const hasBook = state.player.inventory.some((e) => e.itemId.startsWith('tool_book'))
      if (hasMed) return fail(ctx, '背包里有药，可以用「吃 感冒药」这样指定。')
      if (hasBook) return fail(ctx, '可以用「读 《编程入门》」阅读书籍。')
      return fail(ctx, '背包里没有可使用的物品。')
    }
    const item = itemByName(itemToken.value)
    if (!item) return fail(ctx, `没有「${itemToken.value}」这个东西。`)
    if (!removeItem(state, item.id, 1)) return fail(ctx, `你没有「${item.name}」。`)
    if (item.category === 'medicine') {
      adjustAttrs(state, item.effect ?? { health: 8 })
      state.pendingMinutes = 15
      pushResult(state, `你服下了${item.name}，感觉好了一些。`)
    } else if (item.id.startsWith('tool_book')) {
      state.pendingMinutes = 120
      const map: Record<string, string> = {
        tool_bookProg: 'programming', tool_bookCook: 'cooking', tool_bookFin: 'finance',
        tool_bookLit: 'writing', tool_bookLang: 'language',
      }
      const skillId = map[item.id] ?? 'craft'
      const cur = state.player.skills[skillId] ?? { level: 0, exp: 0 }
      cur.exp += 30
      state.player.skills[skillId] = cur
      adjustAttrs(state, { intellect: 1, stamina: -5 })
      pushResult(state, `你专注地阅读了《${item.name.replace('《', '').replace('》', '')}》，${'收获颇丰'}。（${skillId} +30 经验）`)
    } else {
      adjustAttrs(state, item.effect ?? { mood: 3 })
      pushResult(state, `你使用了${item.name}。`)
    }
  },
}

const buyDef: VerbDef = {
  name: 'buy', aliases: ['买', '购买'], category: '生存', desc: '在当前地点购买物品', usage: '买 <物品> [数量]',
  run: (ctx) => {
    const state = ctx.state
    const loc = LOCATION_INDEX.get(state.player.locationId)
    if (!loc?.shop) return fail(ctx, '这里没有可买的东西。去超市、商场或商店吧。')
    if (loc.openHours[0] >= calendar(state.time).hour || calendar(state.time).hour >= loc.openHours[1]) {
      if (!(loc.openHours[0] === 0 && loc.openHours[1] === 24)) {
        return fail(ctx, `${loc.name}现在还没开门（营业时间 ${loc.openHours[0]}:00-${loc.openHours[1]}:00）。`)
      }
    }
    const itemToken = ctx.args.tokens.find((t) => t.target?.type === 'item')
    if (!itemToken) return fail(ctx, '要买什么？例如「买 苹果 3」。')
    const item = itemByName(itemToken.value)
    if (!item) return fail(ctx, `找不到「${itemToken.value}」。`)
    const count = Math.max(1, Math.min(99, ctx.args.numbers[0] ?? 1))
    const unit = itemPrice(state, item.id)
    const total = unit * count
    if (state.player.money < total) return fail(ctx, `${item.name}单价 ${fmtMoney(unit)}，共需 ${fmtMoney(total)}，你的现金不够。`)
    addMoney(state, -total, 'shopping')
    addItem(state, item.id, count, item.expiryDays)
    if (item.instant) adjustAttrs(state, item.instant)
    if (item.category === 'vehicle') {
      state.player.vehicle.vehicleItemId = item.id
      state.player.inventory = state.player.inventory.filter((e) => e.itemId !== item.id)
    }
    const vars = { ...contextVars(state), item: item.name }
    pushResult(state, narrate(BUY_TEMPLATES, narrativeCtx(ctx), vars, () => ctx.rng.next()) + `（${item.name} ×${count}，${fmtMoney(total)}）`)
  },
}

// ---------------- 系统 ----------------

const helpDef: VerbDef = {
  name: 'help', aliases: ['帮助', '说明'], category: '系统', desc: '查看全部指令分类与用法', usage: '帮助',
  run: (ctx) => {
    const lines: string[] = ['【指令分类】']
    for (const [cat, defs] of verbsByCategory()) {
      lines.push(`◆ ${cat}：${defs.map((d) => d.name).join('、')}`)
    }
    lines.push('提示：指令支持「动词 + 对象 + 数量」，如「买 苹果 3」「学习 编程 2」。输入动词可查看该类指令详情。')
    pushMessage(ctx.state, 'system', lines.join('\n'))
  },
}

const lookDef: VerbDef = {
  name: 'look', aliases: ['查看', '看'], category: '系统', desc: '查看状态/背包/地图/关系/资产等', usage: '查看 <状态|背包|地图|关系|资产>',
  run: (ctx) => {
    const state = ctx.state
    const what = ctx.args.targets.stat ?? ctx.args.tokens.find((t) => t.kind === 'word')?.value ?? 'status'
    const p = state.player
    const c = calendar(state.time)
    if (what === 'status' || what === '状态') {
      pushMessage(state, 'system', [
        `【状态】${p.name}（${c.age}岁 ${p.gender === 'm' ? '男' : '女'}）`,
        `健康${Math.round(p.attrs.health)} 体力${Math.round(p.attrs.stamina)} 心情${Math.round(p.attrs.mood)} 智力${Math.round(p.attrs.intellect)} 魅力${Math.round(p.attrs.charm)}`,
        `饱食${Math.round(p.attrs.satiety)} 清洁${Math.round(p.attrs.hygiene)}`,
        `现金${fmtMoney(p.money)} 存款${fmtMoney(p.bank)} 声望${p.reputation} 信用${p.credit}`,
      ].join('\n'))
    } else if (what === 'bag' || what === '背包') {
      const lines = p.inventory.length === 0 ? ['背包空空如也。'] :
        [`【背包】容量 ${p.inventory.length}/20`]
      for (const e of p.inventory) {
        const item = itemById(e.itemId)
        lines.push(`- ${item.name} ×${e.count}${e.expiryDays !== undefined ? `（剩${e.expiryDays}天）` : ''}：${item.desc}`)
      }
      pushMessage(state, 'system', lines.join('\n'))
    } else if (what === 'map' || what === '地图') {
      const byDistrict = new Map<string, string[]>()
      for (const loc of LOCATION_INDEX.values()) {
        if (loc.id === 'jail') continue
        const list = byDistrict.get(loc.district) ?? []
        list.push(loc.name)
        byDistrict.set(loc.district, list)
      }
      const lines = ['【云州市地图】']
      for (const [d, names] of byDistrict) lines.push(`◆ ${DISTRICT_NAMES[d]}：${names.join('、')}`)
      pushMessage(state, 'system', lines.join('\n'))
    } else if (what === 'relations' || what === '关系') {
      const lines = ['【人际关系】']
      for (const npc of state.npcs) {
        if (!npc.alive) { lines.push(`- ${npc.name}（已故）`); continue }
        const here = npc.currentLocationId === p.locationId ? '（在这里）' : ''
        lines.push(`- ${npc.name}：关系${npc.relationship} ${here}——${npc.personality.join('、')}`)
      }
      pushMessage(state, 'system', lines.join('\n'))
    } else if (what === 'assets' || what === '资产') {
      const lines = ['【资产总览】',
        `现金 ${fmtMoney(p.money)}｜存款 ${fmtMoney(p.bank)}｜信用 ${p.credit}`,
        p.job ? `职业：${p.job.jobId}（月薪见「查看 状态」）` : '职业：无业',
        `房产：${p.estate.propertyId ?? '无'}｜租住：${p.estate.rentedId ?? '无'}`,
        `车辆：${p.vehicle.vehicleItemId ?? '无'}`,
        `股票：${p.stocks.map((s) => `${s.stockId}×${s.shares}`).join('、') || '无'}`,
        `店铺：${p.shop ? p.shop.shopId : '无'}`,
      ]
      pushMessage(state, 'system', lines.join('\n'))
    } else {
      pushMessage(state, 'system', '可查看：状态、背包、地图、关系、资产。')
    }
  },
}

const statusDef: VerbDef = {
  name: 'status', aliases: ['状态'], category: '系统', desc: '查看角色状态', hidden: true,
  run: (ctx) => lookDef.run({ ...ctx, args: { ...ctx.args, targets: { ...ctx.args.targets, stat: 'status' } } }),
}

const bagDef: VerbDef = {
  name: 'bag', aliases: ['背包'], category: '系统', desc: '查看背包', hidden: true,
  run: (ctx) => lookDef.run({ ...ctx, args: { ...ctx.args, targets: { ...ctx.args.targets, stat: 'bag' } } }),
}

const mapDef: VerbDef = {
  name: 'map', aliases: ['地图'], category: '系统', desc: '查看地图', hidden: true,
  run: (ctx) => lookDef.run({ ...ctx, args: { ...ctx.args, targets: { ...ctx.args.targets, stat: 'map' } } }),
}

const saveDef: VerbDef = {
  name: 'save', aliases: ['存档'], category: '系统', desc: '立即保存游戏', usage: '存档',
  run: (ctx) => {
    ctx.state.pendingSave = true
    pushResult(ctx.state, '游戏已保存。')
  },
}

const homeDef: VerbDef = {
  name: 'goHome', aliases: ['回家'], category: '移动', desc: '回家', usage: '回家',
  run: (ctx) => {
    ctx.args.targets.location = 'home'
    doGo(ctx, 'walk')
  },
}

export function registerBasicVerbs(): void {
  registerVerb(goDef)
  registerVerb(busDef)
  registerVerb(taxiDef)
  registerVerb(driveDef)
  registerVerb(homeDef)
  registerVerb(sleepDef)
  registerVerb(waitDef)
  registerVerb(eatDef)
  registerVerb(cookDef)
  registerVerb(useDef)
  registerVerb(buyDef)
  registerVerb(helpDef)
  registerVerb(lookDef)
  registerVerb(statusDef)
  registerVerb(bagDef)
  registerVerb(mapDef)
  registerVerb(saveDef)
}

export { fail, narrativeCtx }

// silence unused imports for optional texts
void pickText
void ITEMS
void LOCATION_BY_NAME
