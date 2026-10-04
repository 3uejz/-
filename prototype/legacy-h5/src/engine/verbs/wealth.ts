import type { VerbDef } from './registry'
import { registerVerb } from './registry'
import { fail } from './basic'
import { pushMessage, pushResult, pushWarning } from '../narrate'
import { fmtMoney, calendar } from '../time'
import { addMoney, adjustAttrs } from '../state-helpers'
import { STOCK_BY_NAME, STOCK_INDEX } from '../../content/stocks'
import { PROPERTY_BY_NAME, PROPERTY_INDEX } from '../../content/properties'
import { LOTTERY, drawLottery } from './lottery'
import { propertyValue } from '../systems/economy'

// ---------------- 银行 ----------------

const depositDef: VerbDef = {
  name: 'deposit', aliases: ['存款', '存钱'], category: '金融', desc: '把现金存入银行（可存定期）', usage: '存款 [金额] [定期天数]',
  run: (ctx) => {
    const state = ctx.state
    if (state.player.locationId !== 'bank') return fail(ctx, '要去银行办理。输入「去 银行」。')
    const amount = ctx.args.numbers[0] ?? 0
    if (amount <= 0) return fail(ctx, `要存多少？例如「存款 5000」。你有现金 ${fmtMoney(state.player.money)}。`)
    if (state.player.money < amount) return fail(ctx, '现金不足。')
    const termDays = ctx.args.numbers[1] ?? 0
    addMoney(state, -amount, 'bank-deposit')
    if (termDays > 0) {
      const existing = state.player.depositDue
      if (existing) return fail(ctx, '你已有一笔定期存款，先取出再存。')
      state.player.depositDue = { amount, dueTotal: state.time.total + termDays * 1440 }
      pushResult(state, `你存入定期 ${fmtMoney(amount)}，期限 ${termDays} 天，到期自动结算利息（年化 3%）。`)
    } else {
      state.player.bank += amount
      pushResult(state, `活期存入 ${fmtMoney(amount)}。当前存款 ${fmtMoney(state.player.bank)}。`)
    }
  },
}

const withdrawDef: VerbDef = {
  name: 'withdraw', aliases: ['取款', '取钱'], category: '金融', desc: '从银行取出现金', usage: '取款 [金额]',
  run: (ctx) => {
    const state = ctx.state
    if (state.player.locationId !== 'bank') return fail(ctx, '要去银行办理。输入「去 银行」。')
    if (state.player.depositDue) {
      if (state.time.total >= state.player.depositDue.dueTotal) {
        const interest = Math.round(state.player.depositDue.amount * 0.03 * (1 / 12))
        addMoney(state, state.player.depositDue.amount + interest, 'interest')
        state.player.stats.milestones.push({ year: 0, text: '利息' })
        pushResult(state, `定期到期！本息合计 ${fmtMoney(state.player.depositDue.amount + interest)}（含利息 ${fmtMoney(interest)}）已转入现金。`)
        state.player.depositDue = undefined
      } else {
        pushWarning(state, '你的定期存款还没到期，提前支取将损失利息（暂不支持）。')
      }
    }
    const amount = ctx.args.numbers[0] ?? state.player.bank
    if (amount <= 0 || state.player.bank < amount) return fail(ctx, `存款余额不足（当前 ${fmtMoney(state.player.bank)}）。`)
    state.player.bank -= amount
    addMoney(state, amount, 'bank-withdraw')
    pushResult(state, `取出 ${fmtMoney(amount)}。剩余存款 ${fmtMoney(state.player.bank)}。`)
  },
}

const loanDef: VerbDef = {
  name: 'loan', aliases: ['贷款', '借钱'], category: '金融', desc: '向银行贷款（按日计息）', usage: '贷款 [金额]',
  run: (ctx) => {
    const state = ctx.state
    const p = state.player
    if (p.locationId !== 'bank') return fail(ctx, '要去银行办理。输入「去 银行」。')
    if (p.loan) return fail(ctx, `你已有未还清贷款（本金 ${fmtMoney(p.loan.principal)}）。先「还款」。`)
    const limit = Math.round(50000 + p.credit * 2000 + (p.estate.propertyId ? 200000 : 0))
    const amount = ctx.args.numbers[0] ?? 0
    if (amount <= 0) return fail(ctx, `要贷多少？你的可贷额度 ${fmtMoney(limit)}。例如「贷款 50000」。`)
    if (amount > limit) return fail(ctx, `超出额度。你的可贷额度 ${fmtMoney(limit)}（信用与资产可提高额度）。`)
    p.loan = { principal: amount, dailyRate: 0.0005, overdueDays: 0 }
    addMoney(state, amount, 'loan')
    p.stats.milestones.push({ year: 0, text: `贷款${amount}` })
    pushResult(state, `贷款 ${fmtMoney(amount)} 到账。日利率 0.05%，记得按时还款。`)
  },
}

const repayDef: VerbDef = {
  name: 'repay', aliases: ['还款', '还贷'], category: '金融', desc: '偿还贷款', usage: '还款 [金额]',
  run: (ctx) => {
    const state = ctx.state
    const p = state.player
    if (p.locationId !== 'bank') return fail(ctx, '要去银行办理。输入「去 银行」。')
    if (!p.loan) return fail(ctx, '你没有贷款。')
    const amount = Math.min(ctx.args.numbers[0] ?? p.loan.principal, p.loan.principal)
    if (amount <= 0) return fail(ctx, '要还多少？')
    if (p.money < amount) return fail(ctx, `现金不足（需 ${fmtMoney(amount)}）。`)
    addMoney(state, -amount, 'loan-repay')
    p.loan.principal -= amount
    p.credit = Math.min(100, p.credit + 5)
    if (p.loan.principal <= 0) {
      p.loan = null
      pushResult(state, '贷款已全部还清！信用评分提升。')
    } else {
      pushResult(state, `还款 ${fmtMoney(amount)}，剩余本金 ${fmtMoney(p.loan.principal)}。`)
    }
  },
}

// ---------------- 股票 ----------------

function stockTradeTimeCheck(ctx: { state: import('../state').GameState }): string | null {
  const hour = calendar(ctx.state.time).hour
  if (hour < 9 || hour >= 15) return '交易所交易时间为 9:00-15:00。'
  if (ctx.state.player.locationId !== 'stockExchange') return '要去股票交易所交易。输入「去 股票交易所」。'
  return null
}

const buyStockDef: VerbDef = {
  name: 'buyStock', aliases: ['买股票', '买入'], category: '金融', desc: '买入指定股票 N 股', usage: '买股票 <名称> [股数]',
  run: (ctx) => {
    const err = stockTradeTimeCheck(ctx)
    if (err) return fail(ctx, err)
    const state = ctx.state
    const token = ctx.args.tokens.find((t) => t.target?.type === 'stock')
    if (!token) return fail(ctx, '要买哪支股票？例如「买股票 星辉科技 100」。')
    const def = STOCK_BY_NAME.get(token.value)
    if (!def) return fail(ctx, `没有「${token.value}」这支股票。`)
    const st = state.stocks.find((s) => s.stockId === def.id)!
    const shares = ctx.args.numbers[0] ?? 100
    const cost = Math.round(st.price * shares)
    if (cost <= 0) return fail(ctx, '股数要大于 0。')
    if (state.player.money < cost) return fail(ctx, `需 ${fmtMoney(cost)}（现价 ${st.price}/股 × ${shares}），现金不足。`)
    addMoney(state, -cost, 'stock')
    const pos = state.player.stocks.find((x) => x.stockId === def.id)
    if (pos) {
      pos.avgCost = (pos.avgCost * pos.shares + cost) / (pos.shares + shares)
      pos.shares += shares
    } else {
      state.player.stocks.push({ stockId: def.id, shares, avgCost: st.price })
    }
    pushResult(state, `买入 ${def.name} ${shares} 股 @ ${st.price}，共 ${fmtMoney(cost)}。`)
  },
}

const sellStockDef: VerbDef = {
  name: 'sellStock', aliases: ['卖股票', '卖出'], category: '金融', desc: '卖出指定股票 N 股', usage: '卖股票 <名称> [股数]',
  run: (ctx) => {
    const err = stockTradeTimeCheck(ctx)
    if (err) return fail(ctx, err)
    const state = ctx.state
    const token = ctx.args.tokens.find((t) => t.target?.type === 'stock')
    if (!token) return fail(ctx, '要卖哪支股票？')
    const def = STOCK_BY_NAME.get(token.value)
    if (!def) return fail(ctx, `没有「${token.value}」这支股票。`)
    const pos = state.player.stocks.find((x) => x.stockId === def.id)
    if (!pos) return fail(ctx, `你没有持有 ${def.name}。`)
    const shares = Math.min(ctx.args.numbers[0] ?? pos.shares, pos.shares)
    const st = state.stocks.find((s) => s.stockId === def.id)!
    const gain = Math.round(st.price * shares)
    const pnl = Math.round((st.price - pos.avgCost) * shares)
    addMoney(state, gain, 'stock')
    pos.shares -= shares
    if (pos.shares <= 0) state.player.stocks = state.player.stocks.filter((x) => x !== pos)
    pushResult(state, `卖出 ${def.name} ${shares} 股 @ ${st.price}，回款 ${fmtMoney(gain)}（${pnl >= 0 ? '盈利' : '亏损'} ${fmtMoney(Math.abs(pnl))}）。`)
  },
}

// ---------------- 地产 ----------------

const rentDef: VerbDef = {
  name: 'rent', aliases: ['租房', '租'], category: '地产', desc: '租住指定房屋', usage: '租房 <房屋名>',
  run: (ctx) => {
    const state = ctx.state
    const token = ctx.args.tokens.find((t) => t.target?.type === 'property')
    if (!token) {
      const lines = ['【可租房源】']
      for (const p of PROPERTY_INDEX.values()) lines.push(`- ${p.name}：月租 ${fmtMoney(p.rent)}，舒适度 ${p.comfort}`)
      pushMessage(state, 'system', lines.join('\n'))
      return fail(ctx, '用「租房 <房屋名>」选择房源。')
    }
    const prop = PROPERTY_BY_NAME.get(token.value)
    if (!prop) return fail(ctx, `没有「${token.value}」这套房。`)
    state.player.estate.rentedId = prop.id
    state.player.locationId = 'home'
    state.player.estate.propertyId = null
    pushResult(state, `你搬进了「${prop.name}」，月租 ${fmtMoney(prop.rent)}，日结算时自动扣款。`)
  },
}

const buyHouseDef: VerbDef = {
  name: 'buyHouse', aliases: ['买房', '购房'], category: '地产', desc: '购买指定房产', usage: '买房 <房屋名>',
  run: (ctx) => {
    const state = ctx.state
    const token = ctx.args.tokens.find((t) => t.target?.type === 'property')
    if (!token) {
      const lines = ['【在售房源】']
      for (const p of PROPERTY_INDEX.values()) {
        lines.push(`- ${p.name}：售价 ${fmtMoney(propertyValue(state, p.price))}，月租 ${fmtMoney(p.rent)}，舒适度 ${p.comfort}`)
      }
      pushMessage(state, 'system', lines.join('\n'))
      return fail(ctx, '用「买房 <房屋名>」购买（无需到特定地点）。')
    }
    const prop = PROPERTY_BY_NAME.get(token.value)
    if (!prop) return fail(ctx, `没有「${token.value}」这套房。`)
    if (state.player.estate.propertyId) return fail(ctx, `你已拥有「${PROPERTY_INDEX.get(state.player.estate.propertyId)?.name}」，先卖掉再买。`)
    const price = propertyValue(state, prop.price)
    if (state.player.money < price) return fail(ctx, `「${prop.name}」售价 ${fmtMoney(price)}，现金不足（可先存款或贷款）。`)
    addMoney(state, -price, 'house')
    state.player.estate.propertyId = prop.id
    state.player.estate.rentedId = null
    state.player.locationId = 'home'
    state.player.stats.milestones.push({ year: 0, text: `购入${prop.name}` })
    pushResult(state, `恭喜！你以 ${fmtMoney(price)} 买下了「${prop.name}」！从此有个真正的家了。`)
  },
}

const sellHouseDef: VerbDef = {
  name: 'sellHouse', aliases: ['卖房'], category: '地产', desc: '卖出自有房产', usage: '卖房',
  run: (ctx) => {
    const state = ctx.state
    const pid = state.player.estate.propertyId
    if (!pid) return fail(ctx, '你没有房产。')
    const prop = PROPERTY_INDEX.get(pid)!
    const price = propertyValue(state, prop.price)
    addMoney(state, price, 'house-sell')
    state.player.estate.propertyId = null
    state.player.estate.rentedId = 'prop_flatsmall'
    pushResult(state, `你以 ${fmtMoney(price)} 卖出了「${prop.name}」，搬回了出租屋。`)
  },
}

// ---------------- 店铺经营 ----------------

const SHOPS_FOR_SALE = [
  { typeId: 'food', name: '小吃店', cost: 30000, goods: 'food' },
  { typeId: 'retail', name: '杂货铺', cost: 25000, goods: 'food' },
  { typeId: 'fun', name: '文具娱乐店', cost: 35000, goods: 'luxury' },
]

const openShopDef: VerbDef = {
  name: 'openShop', aliases: ['开店', '创业'], category: '经营', desc: '在商业街开设店铺', usage: '开店 [类型]',
  run: (ctx) => {
    const state = ctx.state
    const p = state.player
    if (p.locationId !== 'businessStreet') return fail(ctx, '开店要去商业街。输入「去 商业街」。')
    if (p.shop) return fail(ctx, `你已经拥有「${p.shop.shopId}」了。`)
    const lines = ['【可加盟店铺】']
    for (const s of SHOPS_FOR_SALE) lines.push(`- ${s.name}：加盟费 ${fmtMoney(s.cost)}`)
    const wanted = ctx.args.tokens.find((t) => t.kind === 'word')?.value ?? ''
    const chosen = SHOPS_FOR_SALE.find((s) => s.name === wanted || wanted.includes(s.typeId)) ?? SHOPS_FOR_SALE[0]
    if (p.money < chosen.cost) {
      pushMessage(state, 'system', lines.join('\n'))
      return fail(ctx, `「${chosen.name}」需要加盟费 ${fmtMoney(chosen.cost)}，现金不足。`)
    }
    addMoney(state, -chosen.cost, 'shop')
    p.shop = { shopId: chosen.name, typeId: chosen.typeId, inventory: [], priceFactor: 1, employees: [], reputation: 20, dailyRevenue: 0, open: true }
    p.stats.milestones.push({ year: 0, text: '创业开店' })
    p.reputation += 3
    pushResult(state, `你的「${chosen.name}」在商业街开张了！用「进货」「定价」「雇佣」经营它。`)
  },
}

const stockUpDef: VerbDef = {
  name: 'stockUp', aliases: ['进货'], category: '经营', desc: '为店铺补货（自动按资金进货）', usage: '进货 [金额]',
  run: (ctx) => {
    const state = ctx.state
    const shop = state.player.shop
    if (!shop) return fail(ctx, '你还没有店铺。')
    const budget = Math.min(ctx.args.numbers[0] ?? 2000, state.player.money)
    if (budget < 100) return fail(ctx, '进货至少需要 100 元。')
    addMoney(state, -budget, 'shop-stock')
    shop.inventory.push({ itemId: 'food_baozi', count: Math.floor(budget / 3), costEach: 3 })
    pushResult(state, `你花了 ${fmtMoney(budget)} 进了一批货。店铺库存充足，等待客源。`)
  },
}

const setPriceDef: VerbDef = {
  name: 'setPrice', aliases: ['定价', '调价'], category: '经营', desc: '调整店铺售价系数', usage: '定价 <0.5~2.0>',
  run: (ctx) => {
    const state = ctx.state
    const shop = state.player.shop
    if (!shop) return fail(ctx, '你还没有店铺。')
    const f = ctx.args.numbers[0] ?? 1
    shop.priceFactor = Math.max(0.5, Math.min(2, f))
    pushResult(state, `店铺定价系数调整为 ${shop.priceFactor}（1.0 为市场价）。`)
  },
}

const hireDef: VerbDef = {
  name: 'hire', aliases: ['雇佣', '招人'], category: '经营', desc: '雇佣 NPC 为店员', usage: '雇佣 <人名>',
  run: (ctx) => {
    const state = ctx.state
    const shop = state.player.shop
    if (!shop) return fail(ctx, '你还没有店铺。')
    if (shop.employees.length >= 3) return fail(ctx, '店员已满 3 人。')
    const npcToken = ctx.args.tokens.find((t) => t.target?.type === 'npc')
    const npc = npcToken ? state.npcs.find((n) => n.name === npcToken.value) : undefined
    if (!npc) return fail(ctx, '要雇佣谁？例如「雇佣 张大壮」。')
    if (!npc.alive) return fail(ctx, '这个人已经不在了。')
    if (shop.employees.includes(npc.id)) return fail(ctx, `${npc.name}已经是你的店员了。`)
    if (npc.relationship < 30) return fail(ctx, `${npc.name}对你的信任不够（关系需 30+）。先多聊聊。`)
    shop.employees.push(npc.id)
    pushResult(state, `${npc.name}加入了你的店铺，日薪 80 元，将在日结算时自动发放。`)
  },
}

const fireDef: VerbDef = {
  name: 'fire', aliases: ['解雇', '辞退'], category: '经营', desc: '解雇店员', usage: '解雇 <人名>',
  run: (ctx) => {
    const state = ctx.state
    const shop = state.player.shop
    if (!shop) return fail(ctx, '你还没有店铺。')
    const npcToken = ctx.args.tokens.find((t) => t.target?.type === 'npc')
    const npc = npcToken ? state.npcs.find((n) => n.name === npcToken.value) : undefined
    if (!npc || !shop.employees.includes(npc.id)) return fail(ctx, '这个人不是你的店员。')
    shop.employees = shop.employees.filter((id) => id !== npc.id)
    npc.relationship -= 15
    pushResult(state, `你解雇了${npc.name}。${npc.name}显得很失望。`)
  },
}

const payWagesDef: VerbDef = {
  name: 'payWages', aliases: ['发工资'], category: '经营', desc: '提前发放店员工资，提升忠诚', usage: '发工资',
  run: (ctx) => {
    const state = ctx.state
    const shop = state.player.shop
    if (!shop) return fail(ctx, '你还没有店铺。')
    if (shop.employees.length === 0) return fail(ctx, '你还没有雇佣店员。')
    const total = shop.employees.length * 80
    if (state.player.money < total) return fail(ctx, `需 ${fmtMoney(total)}，现金不足。`)
    addMoney(state, -total, 'wages')
    for (const id of shop.employees) {
      const npc = state.npcs.find((n) => n.id === id)
      if (npc) npc.relationship += 3
    }
    pushResult(state, `你提前发放了工资（${fmtMoney(total)}），店员们干劲十足。`)
  },
}

export function registerWealthVerbs(): void {
  registerVerb(depositDef)
  registerVerb(withdrawDef)
  registerVerb(loanDef)
  registerVerb(repayDef)
  registerVerb(buyStockDef)
  registerVerb(sellStockDef)
  registerVerb(rentDef)
  registerVerb(buyHouseDef)
  registerVerb(sellHouseDef)
  registerVerb(openShopDef)
  registerVerb(stockUpDef)
  registerVerb(setPriceDef)
  registerVerb(hireDef)
  registerVerb(fireDef)
  registerVerb(payWagesDef)
  registerVerb(LOTTERY)
  void drawLottery
  void STOCK_INDEX
  void pushWarning
  void adjustAttrs
}
