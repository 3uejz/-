import type { VerbDef, VerbContext } from './registry'
import { registerVerb } from './registry'
import { fail, narrativeCtx } from './basic'
import { pushMessage, pushResult, pushWarning, narrate, contextVars, pickText } from '../narrate'
import { fmtMoney, calendar } from '../time'
import { addMoney, adjustAttrs, addItem, removeItem } from '../state-helpers'
import { CHAT_TEMPLATES } from '../../content/texts'
import { LOCATION_INDEX } from '../../content/locations'
import { ITEM_INDEX } from '../../content/items'

function findNpc(ctx: VerbContext, explicit?: boolean): import('../state').NPC | undefined {
  const token = ctx.args.tokens.find((t: import('../parser/tokenizer').Token) => t.target?.type === 'npc')
  const p = ctx.state.player
  if (token) {
    const npc = ctx.state.npcs.find((n) => n.name === token.value)
    if (npc) return npc
  }
  // Default: any NPC at current location.
  return ctx.state.npcs.find((n) => n.alive && n.currentLocationId === p.locationId && (explicit ? true : n.id !== p.family.spouseNpcId))
}

function npcHere(ctx: VerbContext, npcId: string): boolean {
  const npc = ctx.state.npcs.find((n) => n.id === npcId)
  return !!npc && npc.alive && npc.currentLocationId === ctx.state.player.locationId
}

const chatDef: VerbDef = {
  name: 'chat', aliases: ['聊天', '聊', '交谈'], category: '社交', desc: '与身边的人聊天（+关系）', usage: '聊天 [人名]',
  run: (ctx) => {
    const state = ctx.state
    const npc = findNpc(ctx)
    if (!npc) return fail(ctx, '这里没有可以聊天的人。看看「地图」或换个地方。')
    const bonus = state.player.talents.talents.includes('tal_charm') ? 2 : 0
    const delta = Math.round((2 + state.player.attrs.charm / 25 + bonus) * (0.8 + ctx.rng.next() * 0.5))
    npc.relationship = Math.max(-100, Math.min(100, npc.relationship + delta))
    adjustAttrs(state, { mood: 2, stamina: -2 })
    state.player.stats.milestones.push({ year: 0, text: '聊天' })
    const vars = { ...contextVars(state), npc: npc.name }
    pushResult(state, narrate(CHAT_TEMPLATES, narrativeCtx(ctx), vars, () => ctx.rng.next()) + `（关系 +${delta}）`)
    if (npc.relationship >= 40 && npc.relationship < 40 + delta) pushMessage(state, 'system', `${npc.name}开始把你当朋友了。`)
  },
}

const giftDef: VerbDef = {
  name: 'gift', aliases: ['送礼', '赠送'], category: '社交', desc: '把背包物品送给某人', usage: '送礼 <物品> 给 <人名>',
  run: (ctx) => {
    const state = ctx.state
    const npc = findNpc(ctx, true)
    if (!npc) return fail(ctx, '要送给谁？到对方所在地再试。')
    const itemToken = ctx.args.tokens.find((t) => t.target?.type === 'item')
    const item = itemToken ? ITEM_INDEX.get(itemToken.target!.id) : undefined
    if (!item) return fail(ctx, '要送什么？先在背包里准备好礼物。')
    if (!removeItem(state, item.id, 1)) return fail(ctx, `你没有「${item.name}」。`)
    const value = Math.min(30, Math.max(3, Math.round(item.price / 100)))
    npc.relationship = Math.max(-100, Math.min(100, npc.relationship + value))
    state.player.stats.milestones.push({ year: 0, text: '送礼' })
    pushResult(state, `你把「${item.name}」送给了${npc.name}。（关系 +${value}）`)
  },
}

const treatDef: VerbDef = {
  name: 'treat', aliases: ['请客'], category: '社交', desc: '请某人吃饭（提升关系）', usage: '请客 <人名>',
  run: (ctx) => {
    const state = ctx.state
    const npc = findNpc(ctx, true)
    if (!npc) return fail(ctx, '要请谁？到对方所在地再试。')
    const cost = 150
    if (state.player.money < cost) return fail(ctx, `请客吃饭约需 ${fmtMoney(cost)}，现金不足。`)
    addMoney(state, -cost, 'treat')
    npc.relationship = Math.max(-100, Math.min(100, npc.relationship + 8))
    adjustAttrs(state, { mood: 4, satiety: 20 })
    state.pendingMinutes = 90
    state.player.stats.milestones.push({ year: 0, text: '请客' })
    pushResult(state, `你在餐厅请${npc.name}吃了顿好的，宾主尽欢。（关系 +8）`)
  },
}

const confessDef: VerbDef = {
  name: 'confess', aliases: ['表白'], category: '社交', desc: '向关系亲密的人表白', usage: '表白 <人名>',
  run: (ctx) => {
    const state = ctx.state
    const p = state.player
    if (p.family.spouseNpcId) return fail(ctx, '你已经名花有主了。')
    const npc = findNpc(ctx, true)
    if (!npc) return fail(ctx, '要向谁表白？到对方所在地再试。')
    if (npc.age < 20 || npc.id === 'npc_mother' || npc.id === 'npc_father') return fail(ctx, '这份感情不适合发展。')
    if (npc.relationship < 60) return fail(ctx, `${npc.name}对你的好感还不够（需 60+，当前 ${npc.relationship}）。多聊聊吧。`)
    const successChance = 0.4 + npc.relationship / 200 + p.attrs.charm / 300
    state.pendingMinutes = 30
    if (ctx.rng.next() < successChance) {
      npc.relationship = Math.min(100, npc.relationship + 10)
      p.family.spouseNpcId = npc.id
      p.stats.milestones.push({ year: 0, text: '表白' })
      pushResult(state, `${npc.name}红着脸答应了你的表白！你们开始交往了。`)
    } else {
      npc.relationship -= 5
      adjustAttrs(state, { mood: -10 })
      pushWarning(state, `${npc.name}委婉地拒绝了你。有些事急不来，先做朋友吧。`)
    }
  },
}

const proposeDef: VerbDef = {
  name: 'propose', aliases: ['求婚'], category: '社交', desc: '向恋人求婚', usage: '求婚',
  run: (ctx) => {
    const state = ctx.state
    const spouseId = state.player.family.spouseNpcId
    if (!spouseId) return fail(ctx, '你还没有恋人。')
    const npc = state.npcs.find((n) => n.id === spouseId)!
    if (!npcHere(ctx, npc.id)) return fail(ctx, `${npc.name}不在身边，先找到对方。`)
    if (npc.relationship < 80) return fail(ctx, `${npc.name}觉得你们还需要更多了解（关系需 80+）。`)
    const ring = state.player.inventory.find((e) => e.itemId === 'lux_necklace')
    if (!ring) return fail(ctx, '求婚需要一枚信物（去商场买「项链」）。')
    removeItem(state, 'lux_necklace', 1)
    state.pendingMinutes = 60
    pushResult(state, `单膝跪地，你把项链戴上${npc.name}的指尖——「我愿意！」${npc.name}哭着点头。`)
  },
}

const marryDef: VerbDef = {
  name: 'marry', aliases: ['结婚'], category: '社交', desc: '在民政局登记结婚', usage: '结婚',
  run: (ctx) => {
    const state = ctx.state
    const p = state.player
    if (p.locationId !== 'marriageRegistry') return fail(ctx, '结婚要去民政局登记。输入「去 民政局」。')
    const spouseId = p.family.spouseNpcId
    if (!spouseId) return fail(ctx, '你还没有恋人，先「表白」。')
    const npc = state.npcs.find((n) => n.id === spouseId)!
    if (!npcHere(ctx, npc.id)) return fail(ctx, `${npc.name}要和你一起去民政局才行。先找到对方。`)
    const cost = 500
    if (p.money < cost) return fail(ctx, `婚礼与登记费用约 ${fmtMoney(cost)}，现金不足。`)
    addMoney(state, -cost, 'wedding')
    npc.relationship = 100
    state.pendingMinutes = 180
    p.stats.milestones.push({ year: 0, text: `与${npc.name}结婚` })
    p.attrs.mood = Math.min(100, p.attrs.mood + 20)
    pushResult(state, `红本本盖上了钢印。你和${npc.name}正式结为夫妻！`)
  },
}

const haveChildDef: VerbDef = {
  name: 'haveChild', aliases: ['要孩子', '生孩子'], category: '社交', desc: '与伴侣迎接新生命', usage: '要孩子',
  run: (ctx) => {
    const state = ctx.state
    const p = state.player
    if (!p.family.spouseNpcId) return fail(ctx, '你们还没有结婚。')
    if (p.family.children.length >= 3) return fail(ctx, '家里已经够热闹了。')
    const cost = 20000
    if (p.money + p.bank < cost) return fail(ctx, `养育一个孩子需要约 ${fmtMoney(cost)} 的准备金（现金+存款）。`)
    p.money = Math.max(0, p.money - 5000)
    p.stats.totalSpent += 5000
    const childId = `child_${Date.now() % 1000000}`
    p.family.children.push({ npcId: childId, age: 0 })
    state.pendingMinutes = 120
    p.stats.milestones.push({ year: 0, text: '孩子出生' })
    adjustAttrs(state, { mood: 15, stamina: -10 })
    pushResult(state, '产房外你来回踱步，直到一声啼哭——孩子出生了！你们的生活翻开了新篇章。')
  },
}

const divorceDef: VerbDef = {
  name: 'divorce', aliases: ['离婚'], category: '社交', desc: '结束婚姻关系', usage: '离婚',
  run: (ctx) => {
    const state = ctx.state
    const p = state.player
    if (p.locationId !== 'marriageRegistry') return fail(ctx, '离婚要去民政局办理。')
    const spouseId = p.family.spouseNpcId
    if (!spouseId) return fail(ctx, '你没有结婚。')
    const npc = state.npcs.find((n) => n.id === spouseId)!
    const split = Math.round((p.money + p.bank) * 0.3)
    p.money = Math.max(0, p.money - Math.round(split / 2))
    p.bank = Math.max(0, p.bank - Math.round(split / 2))
    npc.relationship = -40
    p.family.spouseNpcId = null
    adjustAttrs(state, { mood: -25 })
    p.stats.milestones.push({ year: 0, text: '离婚' })
    pushResult(state, `绿本本替换了红本本。财产分割让你损失了 ${fmtMoney(split)}，心情跌到谷底。`)
  },
}

// ---------------- 医疗 ----------------

const treatDef2: VerbDef = {
  name: 'medical', aliases: ['看病', '治疗'], category: '医疗', desc: '在医院治疗伤病', usage: '看病',
  run: (ctx) => {
    const state = ctx.state
    const p = state.player
    if (p.locationId !== 'hospital') return fail(ctx, '看病要去医院。输入「去 医院」。')
    if (p.attrs.health >= 95) return fail(ctx, '你很健康，不需要看病。')
    const cost = 300
    if (p.money < cost) return fail(ctx, `挂号与诊疗费约 ${fmtMoney(cost)}，现金不足。`)
    addMoney(state, -cost, 'medical')
    adjustAttrs(state, { health: 25, mood: 3 })
    state.pendingMinutes = 120
    pushResult(state, `医生给你做了详细检查并开了药（${fmtMoney(cost)}）。健康 +25。`)
  },
}

const checkupDef: VerbDef = {
  name: 'checkup', aliases: ['体检'], category: '医疗', desc: '全面体检（健康+5，预防风险）', usage: '体检',
  run: (ctx) => {
    const state = ctx.state
    const p = state.player
    if (p.locationId !== 'hospital') return fail(ctx, '体检要去医院。')
    const cost = 150
    if (p.money < cost) return fail(ctx, `体检费 ${fmtMoney(cost)}，现金不足。`)
    addMoney(state, -cost, 'medical')
    adjustAttrs(state, { health: 6 })
    state.pendingMinutes = 120
    pushResult(state, '体检各项指标大体正常，医生建议你少熬夜、多运动。（健康 +6）')
  },
}

// ---------------- 休闲 ----------------

const leisureActs: Record<string, { cost: number; minutes: number; mood: number; extra?: Partial<Record<'stamina' | 'health' | 'charm' | 'satiety' | 'hygiene', number>>; texts: string[] }> = {
  stroll: { cost: 0, minutes: 60, mood: 6, extra: { stamina: -5 }, texts: ['你在{place}漫无目的地散步，思绪放空。', '晚风拂面，你在{place}走了很久，心里舒坦多了。'] },
  watchMovie: { cost: 60, minutes: 150, mood: 10, extra: { satiety: -5 }, texts: ['灯光暗下，你在{place}沉浸在别人的故事里。', '散场时你回味良久，值回票价。'] },
  surf: { cost: 15, minutes: 120, mood: 8, extra: { health: -2 }, texts: ['你在{place}开黑三小时，手感火热。', '网络世界的快乐简单又直接。'] },
  sing: { cost: 100, minutes: 180, mood: 12, extra: { stamina: -8 }, texts: ['话筒在手，你在{place}吼出了所有情绪。', '一首接一首，你们唱到嗓子沙哑。'] },
  travel: { cost: 2000, minutes: 2880, mood: 25, extra: { stamina: -15, charm: 2 }, texts: ['你背起行囊，一场说走就走的旅行开始了。', '旅途中的风景与人情，让你重新充满能量。'] },
}

const strollDef: VerbDef = {
  name: 'stroll', aliases: ['散步', '闲逛'], category: '休闲', desc: '在当前场所休闲放松', usage: '散步',
  run: (ctx) => {
    const state = ctx.state
    const act = leisureActs.stroll
    adjustAttrs(state, { mood: act.mood, ...(act.extra ?? {}) })
    state.pendingMinutes = act.minutes
    const loc = LOCATION_INDEX.get(state.player.locationId)
    const vars: Record<string, string> = { ...contextVars(state), place: loc?.name ?? '街头' }
    const template = pickText(act.texts, () => ctx.rng.next())
    pushResult(state, template.replace(/\{(\w+)\}/g, (_m: string, k: string) => vars[k] ?? ''))
  },
}

const movieDef: VerbDef = {
  name: 'watchMovie', aliases: ['看电影', '看剧'], category: '休闲', desc: '看一场电影（￥60）', usage: '看电影',
  run: (ctx) => {
    const state = ctx.state
    if (state.player.locationId !== 'cinema') return fail(ctx, '看电影要去电影院。输入「去 电影院」。')
    const act = leisureActs.watchMovie
    if (state.player.money < act.cost) return fail(ctx, `电影票 ${fmtMoney(act.cost)}，现金不足。`)
    addMoney(state, -act.cost, 'leisure')
    adjustAttrs(state, { mood: act.mood, ...(act.extra ?? {}) })
    state.pendingMinutes = act.minutes
    pushResult(state, pickText(act.texts, () => ctx.rng.next()))
  },
}

const surfDef: VerbDef = {
  name: 'surf', aliases: ['上网', '打游戏'], category: '休闲', desc: '泡网吧（￥15/次）', usage: '上网',
  run: (ctx) => {
    const state = ctx.state
    if (state.player.locationId !== 'netbar') return fail(ctx, '上网要去网吧。')
    const act = leisureActs.surf
    if (state.player.money < act.cost) return fail(ctx, `上网费 ${fmtMoney(act.cost)}，现金不足。`)
    addMoney(state, -act.cost, 'leisure')
    adjustAttrs(state, { mood: act.mood, ...(act.extra ?? {}) })
    state.pendingMinutes = act.minutes
    pushResult(state, pickText(act.texts, () => ctx.rng.next()))
  },
}

const singDef: VerbDef = {
  name: 'sing', aliases: ['唱歌', 'K歌'], category: '休闲', desc: '去 KTV 唱歌（￥100）', usage: '唱歌',
  run: (ctx) => {
    const state = ctx.state
    if (state.player.locationId !== 'ktv') return fail(ctx, '唱歌要去 KTV。')
    const act = leisureActs.sing
    if (state.player.money < act.cost) return fail(ctx, `KTV 消费约 ${fmtMoney(act.cost)}，现金不足。`)
    addMoney(state, -act.cost, 'leisure')
    adjustAttrs(state, { mood: act.mood, ...(act.extra ?? {}) })
    state.pendingMinutes = act.minutes
    pushResult(state, pickText(act.texts, () => ctx.rng.next()))
  },
}

const travelDef: VerbDef = {
  name: 'travel', aliases: ['旅游', '旅行'], category: '休闲', desc: '长途旅行两天（￥2000）', usage: '旅游',
  run: (ctx) => {
    const state = ctx.state
    const okLoc = state.player.locationId === 'travelAgency' || state.player.locationId === 'scenicArea' || state.player.locationId === 'home'
    if (!okLoc) return fail(ctx, '可以去旅行社报团，或从家里出发自助游。')
    const act = leisureActs.travel
    if (state.player.money < act.cost) return fail(ctx, `旅费约 ${fmtMoney(act.cost)}，现金不足。`)
    addMoney(state, -act.cost, 'travel')
    adjustAttrs(state, { mood: act.mood, ...(act.extra ?? {}) })
    state.pendingMinutes = act.minutes
    state.player.stats.milestones.push({ year: 0, text: '旅行' })
    pushResult(state, pickText(act.texts, () => ctx.rng.next()) + '（健康与魅力也提升了）')
  },
}

// ---------------- 犯罪 ----------------

const stealDef: VerbDef = {
  name: 'steal', aliases: ['偷窃', '偷'], category: '风险', desc: '行窃（高风险高代价）', usage: '偷窃',
  run: (ctx) => {
    const state = ctx.state
    const p = state.player
    if (p.jailDaysLeft > 0) return fail(ctx, '你已经在监狱里了……')
    const success = 0.25 + (p.skills['persuasion']?.level ?? 0) * 0.03
    state.pendingMinutes = 30
    if (ctx.rng.next() < success) {
      const gain = ctx.rng.int(50, 400)
      addMoney(state, gain, 'crime')
      p.stats.crimes += 1
      p.reputation -= 8
      pushResult(state, `你鬼使神差地得手了，摸到 ${fmtMoney(gain)}。心跳如鼓，快走。`)
    } else {
      p.reputation -= 15
      p.stats.crimes += 1
      const jail = ctx.rng.int(3, 15)
      p.jailDaysLeft = jail
      p.locationId = 'jail'
      p.stats.milestones.push({ year: 0, text: `入狱${jail}天` })
      pushWarning(state, `失手了！围观群众把你扭送到警局，你被判监禁 ${jail} 天。`)
    }
  },
}

const robDef: VerbDef = {
  name: 'rob', aliases: ['抢劫', '抢'], category: '风险', desc: '抢劫（重罪，重罚）', usage: '抢劫',
  run: (ctx) => {
    const state = ctx.state
    const p = state.player
    if (p.jailDaysLeft > 0) return fail(ctx, '你已经在监狱里了……')
    const success = 0.15 + (p.attrs.stamina / 400) + (p.skills['fitness']?.level ?? 0) * 0.04
    state.pendingMinutes = 60
    if (ctx.rng.next() < success) {
      const gain = ctx.rng.int(500, 3000)
      addMoney(state, gain, 'crime')
      p.stats.crimes += 1
      p.reputation -= 25
      pushResult(state, `你抢到了 ${fmtMoney(gain)}，消失在夜色中。但这个城市开始流传你的恶名。`)
    } else {
      p.reputation -= 40
      p.stats.crimes += 1
      const jail = ctx.rng.int(30, 180)
      p.jailDaysLeft = jail
      p.locationId = 'jail'
      p.stats.milestones.push({ year: 0, text: `入狱${jail}天` })
      pushWarning(state, `抢劫失败！你被当场制服，重判监禁 ${jail} 天。牢饭真难吃。`)
    }
  },
}

const surrenderDef: VerbDef = {
  name: 'surrender', aliases: ['自首'], category: '风险', desc: '向警方自首（减轻处罚）', usage: '自首',
  run: (ctx) => {
    const state = ctx.state
    const p = state.player
    if (p.jailDaysLeft <= 0) return fail(ctx, '你没有在逃罪名。')
    p.reputation += 5
    pushResult(state, '你向警方说明了情况。态度良好，或可获得减刑。')
  },
}

const reflectDef: VerbDef = {
  name: 'reflect', aliases: ['反思', '改造'], category: '风险', desc: '在狱中反思改造（提升智力与心情）', usage: '反思',
  run: (ctx) => {
    adjustAttrs(ctx.state, { intellect: 2, mood: 3 })
    ctx.state.pendingMinutes = 600
    pushResult(ctx.state, '你在铁窗下读了很久的书。时间很慢，但思考很深。')
  },
}

// ---------------- 愿望 ----------------

const wishDef: VerbDef = {
  name: 'wish', aliases: ['愿望', '立愿'], category: '系统', desc: '设立人生愿望（最多 3 个）', usage: '愿望 <攒钱|技能|买房|结婚|开店|声望|长寿> [数值]',
  run: (ctx) => {
    const state = ctx.state
    const p = state.player
    const kindToken = ctx.args.tokens.find((t) => t.target?.type === 'wishKind')
    const text = ctx.args.raw
    let kind: string | null = null
    if (text.includes('钱') || kindToken?.target?.id === 'money') kind = 'money'
    else if (text.includes('技能') || text.includes('学习') || kindToken?.target?.id === 'skill') kind = 'skill'
    else if (text.includes('房')) kind = 'estate'
    else if (text.includes('婚') || text.includes('家')) kind = 'family'
    else if (text.includes('店')) kind = 'business'
    else if (text.includes('声望')) kind = 'reputation'
    else if (text.includes('岁') || text.includes('长寿')) kind = 'age'
    if (!kind) {
      pushMessage(state, 'system', '愿望类型：攒钱 / 技能 / 买房 / 结婚 / 开店 / 声望 / 长寿。例如「愿望 攒钱 100000」。')
      return
    }
    if (p.wishes.length >= 3) return fail(ctx, '同时最多 3 个愿望。先用「查看 愿望」看看，放弃旧的再立新的。')
    const target = kind === 'money' || kind === 'reputation' || kind === 'age' || kind === 'skill' ? Math.max(1, ctx.args.numbers[0] ?? (kind === 'money' ? 100000 : kind === 'skill' ? 5 : 60)) : 1
    const labels: Record<string, string> = {
      money: `攒下 ${fmtMoney(target)}`, skill: `任意技能达到 ${target} 级`, estate: '拥有自己的房子',
      family: '组建家庭', business: '开一家自己的店', reputation: `声望达到 ${target}`, age: `活到 ${target} 岁`,
    }
    const targets: Record<string, number> = { money: target, skill: target, estate: 1, family: 1, business: 1, reputation: target, age: target }
    p.wishes.push({ id: `w_${Date.now() % 1000000}`, kind: kind as never, label: labels[kind], target: targets[kind], progress: 0, done: false })
    pushResult(state, `人生愿望已立下：「${labels[kind]}」。系统会持续追踪进度。`)
  },
}

export function registerLifeVerbs(): void {
  registerVerb(chatDef)
  registerVerb(giftDef)
  registerVerb(treatDef)
  registerVerb(confessDef)
  registerVerb(proposeDef)
  registerVerb(marryDef)
  registerVerb(haveChildDef)
  registerVerb(divorceDef)
  registerVerb(treatDef2)
  registerVerb(checkupDef)
  registerVerb(strollDef)
  registerVerb(movieDef)
  registerVerb(surfDef)
  registerVerb(singDef)
  registerVerb(travelDef)
  registerVerb(stealDef)
  registerVerb(robDef)
  registerVerb(surrenderDef)
  registerVerb(reflectDef)
  registerVerb(wishDef)
}

void calendar
void addItem
