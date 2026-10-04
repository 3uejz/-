import type { GameState, NewGameOptions, Message } from './state'
import { MINUTES_PER_DAY } from './state'
import { RNG } from './rng'
import { pushMessage, pushWarning } from './narrate'
import { formatTime, fmtMoney, calendar } from './time'
import { tick, grantStarterItems } from './clock'
import { parseCommand } from './parser/resolver'
import { VERB_REGISTRY, type VerbContext } from './verbs/registry'
import { registerBasicVerbs, VerbAbort } from './verbs/basic'
import { registerCareerVerbs } from './verbs/career'
import { registerWealthVerbs } from './verbs/wealth'
import { registerLifeVerbs } from './verbs/life'
import { chooseEventOption } from './events/engine'
import { checkAchievements, checkWishes } from './goals'
import { saveToStorage, loadFromStorage, saveLegacy, loadLegacy, type LegacyData } from './save'
import { NPC_DEFS, buildSchedule } from '../content/npcs'
import { STOCKS } from '../content/stocks'
import { drawLottery } from './verbs/lottery'

let verbsReady = false
function ensureVerbs(): void {
  if (verbsReady) return
  registerBasicVerbs()
  registerCareerVerbs()
  registerWealthVerbs()
  registerLifeVerbs()
  verbsReady = true
}

export class Game {
  state: GameState
  rng: RNG

  constructor(state: GameState) {
    ensureVerbs()
    this.state = state
    this.rng = new RNG(state.rngState)
  }

  // ---------------- Lifecycle ----------------

  static newGame(options: NewGameOptions): Game {
    ensureVerbs()
    const seed = options.seed ?? Math.floor(Math.random() * 2 ** 31)
    const legacy = loadLegacy() ?? { totalAchievements: [], legacyPoints: 0, runsCompleted: 0 }

    const state: GameState = {
      version: 1,
      seed,
      rngState: seed,
      time: { total: 7 * 60 },
      weather: 'sunny',
      weatherDaysLeft: 2,
      player: {
        name: options.name || '无名氏',
        gender: options.gender,
        attrs: { health: 85, stamina: 80, mood: 70, intellect: 50, charm: 40, satiety: 70, hygiene: 70 },
        money: 3000 + options.startBonusMoney,
        bank: 0,
        loan: null,
        credit: 60,
        job: null,
        skills: {},
        licenses: [],
        education: 'junior',
        educationProgress: 0,
        inventory: [],
        estate: { propertyId: null, rentedId: 'prop_flatsmall', rentArrears: 0 },
        vehicle: { vehicleItemId: null },
        family: { spouseNpcId: null, children: [] },
        stocks: [],
        shop: null,
        reputation: 0,
        locationId: 'home',
        jailDaysLeft: 0,
        wishes: [],
        talents: { talents: options.talents.slice(0, 2), startBonusMoney: options.startBonusMoney },
        stats: {
          totalEarned: 0, totalSpent: 0, crimes: 0, daysInJail: 0,
          milestones: [], jobsHeld: [], coursesLearned: [],
        },
        alive: true,
        deathCause: null,
      },
      npcs: NPC_DEFS.map((def) => ({
        id: def.id,
        name: def.name,
        gender: def.gender,
        age: def.age,
        jobId: def.jobId,
        personality: [...def.personality],
        schedule: buildSchedule(def),
        currentLocationId: def.workLocationId ?? def.homeId,
        relationship: def.startRelationship,
        homeId: def.homeId,
        alive: true,
        spouseNpcId: null,
        childrenCount: 0,
      })),
      market: { categoryFactor: {}, inflation: 0, propertyIndex: 1 },
      stocks: STOCKS.map((s) => ({ stockId: s.id, price: s.basePrice, history: [s.basePrice] })),
      activeEvent: null,
      eventCooldowns: {},
      achievements: [],
      messages: [],
      nextMessageId: 1,
      pendingMinutes: 0,
      pendingSave: false,
      legacy,
      finished: false,
    }

    // Talent effects.
    if (options.talents.includes('tal_charm')) state.player.attrs.charm = Math.min(100, state.player.attrs.charm + 20)
    if (options.talents.includes('tal_money')) state.player.money += 20000

    const game = new Game(state)
    grantStarterItems(state)
    pushMessage(state, 'system', `【浮生录】${state.player.name} 的故事开始了。`)
    pushMessage(state, 'system', '你生活在云州市，18 岁，刚搬进城郊的出租屋，口袋里有 ' + fmtMoney(state.player.money) + '。')
    pushMessage(state, 'system', '输入「帮助」查看全部指令；「地图」看世界；「找工作」开始谋生。也可以直接输入你想做的事。')
    pushMessage(state, 'system', formatTime(state.time))
    checkAchievements(state)
    game.autoSave()
    return game
  }

  static continueGame(): Game | null {
    ensureVerbs()
    const state = loadFromStorage()
    if (!state) return null
    return new Game(state)
  }

  autoSave(): void {
    this.state.rngState = this.rng.state
    saveToStorage(this.state)
    if (this.state.finished) {
      saveLegacy({
        totalAchievements: this.state.legacy.totalAchievements,
        legacyPoints: this.state.legacy.legacyPoints + this.state.achievements.length,
        runsCompleted: this.state.legacy.runsCompleted + 1,
      })
    }
  }

  // ---------------- Command handling ----------------

  submitCommand(raw: string): void {
    const state = this.state
    if (!state.player.alive) {
      pushWarning(state, '故事已经结束。请「重新开档」开始新的人生。')
      return
    }
    if (state.activeEvent) {
      pushWarning(state, '先处理眼前的事件！点击选项做出选择。')
      return
    }

    state.pendingMinutes = 0
    state.pendingSave = false

    const result = parseCommand(raw, state)
    if (!result.ok || !result.command) {
      pushWarning(state, result.error ?? '无法理解这个指令。')
      if (result.suggestions && result.suggestions.length > 0) {
        pushMessage(state, 'system', `你是想输入：${result.suggestions.join('、')} 吗？`)
      }
      return
    }

    const cmd = result.command
    const verbDef = VERB_REGISTRY.get(cmd.verb)
    if (!verbDef) {
      pushWarning(state, '该指令暂不可用。')
      return
    }

    // Jail restriction.
    if (state.player.jailDaysLeft > 0 && !['help', 'look', 'status', 'bag', 'map', 'sleep', 'wait', 'reflect'].includes(verbDef.name)) {
      pushWarning(state, '你正在服刑，只能「睡觉」「反思」「等待」或查看信息。')
      return
    }

    const ctx: VerbContext = { state, args: cmd, rng: this.rng }
    try {
      verbDef.run(ctx)
    } catch (err) {
      if (!(err instanceof VerbAbort)) {
        pushWarning(state, `发生了一点意外（${err instanceof Error ? err.message : '未知错误'}），世界依旧运转。`)
      }
    }

    // Apply time cost.
    const minutes = state.pendingMinutes
    state.pendingMinutes = 0
    if (minutes > 0) {
      // Monthly lottery draw when crossing month boundary during tick.
      this.tickWithLottery(minutes)
    } else {
      checkAchievements(state)
      checkWishes(state)
    }

    if (state.pendingSave || minutes > 0) this.autoSave()
    state.pendingSave = false
  }

  private tickWithLottery(minutes: number): void {
    const state = this.state
    const before = Math.floor(state.time.total / (MINUTES_PER_DAY * 30))
    tick(state, minutes, this.rng, { autoSave: () => this.autoSave() })
    const after = Math.floor(state.time.total / (MINUTES_PER_DAY * 30))
    if (after > before) {
      const result = drawLottery(state, this.rng)
      if (result) pushMessage(state, 'result', result)
    }
  }

  chooseEvent(index: number): void {
    const state = this.state
    if (!state.activeEvent) return
    chooseEventOption(state, index, this.rng)
    checkAchievements(state)
    this.autoSave()
  }

  /** Build life summary for the death screen. */
  lifeSummary(): string {
    const state = this.state
    const p = state.player
    const c = calendar(state.time)
    const lines = [
      `【人生总结】${p.name}（享年 ${c.age} 岁）`,
      `死因：${p.deathCause === 'age' ? '寿终正寝' : '健康耗尽'}`,
      `累计收入 ${fmtMoney(p.stats.totalEarned)}｜累计支出 ${fmtMoney(p.stats.totalSpent)}`,
      `职业轨迹：${p.stats.jobsHeld.map((j) => VERB_REGISTRY.has(j) ? j : j).join(' → ') || '无'}`,
      `学历：${p.education}｜证书：${p.licenses.length} 张`,
      `成就：${state.achievements.length} 项`,
      p.stats.daysInJail > 0 ? `牢狱经历：${p.stats.daysInJail} 天` : '一生清白',
      '',
      '【大事记】',
      ...p.stats.milestones.slice(-12).map((m) => `- ${m.text}`),
    ]
    return lines.join('\n')
  }

  /** Restart with the same world settings (new seed). */
  static restart(options: NewGameOptions): Game {
    return Game.newGame(options)
  }
}

export type { LegacyData, Message }
