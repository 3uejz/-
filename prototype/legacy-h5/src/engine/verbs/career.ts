import type { VerbDef } from './registry'
import { registerVerb } from './registry'
import { fail, narrativeCtx } from './basic'
import { pushMessage, pushResult, pushWarning } from '../narrate'
import { fmtMoney } from '../time'
import { addMoney, adjustAttrs, adjustAttr, skillLevel, hasLicense } from '../state-helpers'
import { jobById, SKILL_BY_NAME, EDUCATION_BY_NAME, EDUCATIONS, LICENSE_BY_NAME, LICENSES, JOBS } from '../../content/jobs'
import { WORK_TEMPLATES, STUDY_TEMPLATES, EXERCISE_TEMPLATES } from '../../content/texts'
import { narrate } from '../narrate'
import { calendar } from '../time'

function jobMeetsRequirements(state: import('../state').GameState, jobId: string): { ok: boolean; reason?: string } {
  const def = jobById(jobId)
  const p = state.player
  const eduOrder = ['junior', 'senior', 'college', 'bachelor', 'master']
  if (def.requireEducation && eduOrder.indexOf(p.education) < eduOrder.indexOf(def.requireEducation)) {
    return { ok: false, reason: `学历要求「${EDUCATION_BY_NAME.get(def.requireEducation)?.name}」` }
  }
  for (const [skillId, lv] of Object.entries(def.requireSkills ?? {})) {
    if ((p.skills[skillId]?.level ?? 0) < lv) {
      return { ok: false, reason: `${SKILL_BY_NAME.get(skillId)?.name}需 ${lv} 级` }
    }
  }
  for (const lic of def.requireLicenses ?? []) {
    if (!p.licenses.includes(lic)) return { ok: false, reason: `需要「${LICENSE_BY_NAME.get(lic)?.name}」` }
  }
  if (def.requireCredit && p.credit < def.requireCredit) return { ok: false, reason: `信用需 ${def.requireCredit}` }
  return { ok: true }
}

// ---------------- 工作 ----------------

const workDef: VerbDef = {
  name: 'work', aliases: ['工作', '上班'], category: '工作', desc: '上班一天，赚取工资', usage: '工作',
  run: (ctx) => {
    const state = ctx.state
    const p = state.player
    if (p.jailDaysLeft > 0) return fail(ctx, '你正在服刑，无法工作。')
    if (!p.job) return fail(ctx, '你还没有工作。用「找工作」看看有哪些岗位。')
    const def = jobById(p.job.jobId)
    const c = calendar(state.time)
    if (c.weekday === 6 || c.weekday === 0) {
      if (p.job.performance < 100) {
        pushMessage(state, 'system', '今天是周末，公司休息。想赚钱可以试试加班（需业绩达标）。')
        return
      }
    }
    const hours = def.workHours
    const tired = p.attrs.stamina < 30 || p.attrs.mood < 15
    const wage = Math.round((def.salary / 22) * (tired ? 0.8 : 1))
    addMoney(state, wage, 'salary')
    adjustAttrs(state, { stamina: -hours * 2.2, mood: tired ? -6 : -2, satiety: -hours * 2, hygiene: -10 })
    p.job.performance += 1
    state.pendingMinutes = hours * 60
    const vars = { name: p.name }
    pushResult(state, narrate(WORK_TEMPLATES, narrativeCtx(ctx), vars, () => ctx.rng.next()) + `（今日工资 ${fmtMoney(wage)}）`)
  },
}

const overtimeDef: VerbDef = {
  name: 'overtime', aliases: ['加班'], category: '工作', desc: '加班 3 小时，获得额外报酬', usage: '加班',
  run: (ctx) => {
    const state = ctx.state
    const p = state.player
    if (!p.job) return fail(ctx, '你还没有工作。')
    if (p.attrs.stamina < 25) return fail(ctx, '你太累了，加班会垮掉的。')
    const extra = Math.round(jobById(p.job.jobId).salary / 22 / 8 * 3 * 1.5)
    addMoney(state, extra, 'salary')
    adjustAttrs(state, { stamina: -18, mood: -6, satiety: -10 })
    p.job.performance += 2
    p.stats.milestones.push({ year: 0, text: '加班' })
    state.pendingMinutes = 180
    pushResult(ctx.state, `你加班到深夜，拿到 ${fmtMoney(extra)} 加班费。`)
  },
}

const jobHuntDef: VerbDef = {
  name: 'jobHunt', aliases: ['找工作', '求职'], category: '工作', desc: '查看当前可应聘的岗位', usage: '找工作',
  run: (ctx) => {
    const state = ctx.state
    const lines = ['【招聘信息】（符合条件的岗位）']
    let any = false
    for (const j of JOBS) {
      const check = jobMeetsRequirements(state, j.id)
      if (check.ok) {
        any = true
        lines.push(`- ${j.title}：月薪 ${fmtMoney(j.salary)}，工时 ${j.workHours}h —— ${j.desc}`)
      }
    }
    if (!any) lines.push('（暂时没有符合你条件的岗位，先提升学历或技能吧。）')
    pushMessage(state, 'system', lines.join('\n'))
    pushMessage(state, 'system', '应聘方法：输入「应聘 <职位名>」，如「应聘 程序员」。')
  },
}

const applyDef: VerbDef = {
  name: 'apply', aliases: ['应聘'], category: '工作', desc: '应聘指定岗位', usage: '应聘 <职位>',
  run: (ctx) => {
    const state = ctx.state
    const p = state.player
    if (p.jailDaysLeft > 0) return fail(ctx, '你正在服刑。')
    const jobToken = ctx.args.tokens.find((t) => t.target?.type === 'job')
    if (!jobToken) return fail(ctx, '要应聘什么职位？先用「找工作」看看列表。')
    const job = JOBS.find((j) => j.title === jobToken.value || j.id === jobToken.value)
    if (!job) return fail(ctx, `没有「${jobToken.value}」这个职位。`)
    const check = jobMeetsRequirements(state, job.id)
    if (!check.ok) return fail(ctx, `应聘失败：${check.reason}。`)
    if (p.job) {
      pushMessage(state, 'system', `你辞掉了「${jobById(p.job.jobId).title}」，加入了新公司。`)
    }
    p.job = { jobId: job.id, performance: 0, yearsHeld: 0 }
    if (!p.stats.jobsHeld.includes(job.id)) p.stats.jobsHeld.push(job.id)
    p.locationId = 'company'
    state.pendingMinutes = 120
    pushResult(state, `恭喜！你成功入职「${job.title}」，月薪 ${fmtMoney(job.salary)}。明天开始上班。`)
  },
}

const resignDef: VerbDef = {
  name: 'resign', aliases: ['辞职'], category: '工作', desc: '辞去当前工作', usage: '辞职',
  run: (ctx) => {
    const state = ctx.state
    const p = state.player
    if (!p.job) return fail(ctx, '你本来就没有工作。')
    const title = jobById(p.job.jobId).title
    p.job = null
    p.stats.milestones.push({ year: 0, text: '辞职' })
    pushResult(state, `你辞掉了「${title}」。失去了稳定收入，但自由了。`)
  },
}

// ---------------- 成长 ----------------

function studySkill(ctx: { state: import('../state').GameState; rng: import('../rng').RNG }, skillId: string, hours: number): void {
  const state = ctx.state
  const p = state.player
  const talentBonus = p.talents.talents.includes('tal_study') ? 1.3 : 1
  const atLibrary = p.locationId === 'library' ? 1.25 : 1
  const hasPc = p.inventory.some((e) => e.itemId === 'ap_pc') && skillId === 'programming' ? 1.3 : 1
  const exp = Math.round(hours * (SKILL_BY_NAME.get(skillId)?.expPerHour ?? 8) * talentBonus * atLibrary * hasPc)
  const skill = p.skills[skillId] ?? { level: 0, exp: 0 }
  skill.exp += exp
  while (skill.exp >= skillLevel(state, skillId) * 100 + 100 && skill.level < 10) {
    skill.exp -= skill.level * 100 + 100
    skill.level += 1
    pushMessage(state, 'system', `你的${SKILL_BY_NAME.get(skillId)?.name}提升到了 ${skill.level} 级！`)
  }
  p.skills[skillId] = skill
  adjustAttrs(state, { stamina: -hours * 4, satiety: -hours * 4, intellect: hours >= 2 ? 1 : 0 })
  state.pendingMinutes = hours * 60
  const vars = { name: p.name, skill: SKILL_BY_NAME.get(skillId)?.name ?? skillId }
  pushResult(state, narrate(STUDY_TEMPLATES, narrativeCtx(ctx as never), vars, () => ctx.rng.next()) + `（+${exp} 经验）`)
}

const studyDef: VerbDef = {
  name: 'study', aliases: ['学习', '学'], category: '成长', desc: '学习指定技能 N 小时', usage: '学习 <技能> [小时]',
  run: (ctx) => {
    const state = ctx.state
    if (state.player.jailDaysLeft > 0) return fail(ctx, '你正在服刑。')
    const skillToken = ctx.args.tokens.find((t) => t.target?.type === 'skill')
    if (!skillToken) {
      const names = [...SKILL_BY_NAME.keys()].join('、')
      return fail(ctx, `要学习什么技能？可选：${names}。例如「学习 编程 2」。`)
    }
    const skill = SKILL_BY_NAME.get(skillToken.value)
    if (!skill) return fail(ctx, `没有「${skillToken.value}」这项技能。`)
    const hours = Math.min(8, Math.max(1, ctx.args.numbers[0] ?? 2))
    if (state.player.attrs.stamina < 20) return fail(ctx, '你太累了，先睡觉恢复体力。')
    studySkill(ctx as never, skill.id, hours)
  },
}

const readDef: VerbDef = {
  name: 'read', aliases: ['读', '阅读'], category: '成长', desc: '阅读书籍，提升对应技能', usage: '读 <书名>',
  run: (ctx) => {
    const state = ctx.state
    const bookEntry = state.player.inventory.find((e) => e.itemId.startsWith('tool_book'))
    if (!bookEntry) return fail(ctx, '背包里没有书。可以去书店买（如「买 《编程入门》」）。')
    const map: Record<string, string> = {
      tool_bookProg: 'programming', tool_bookCook: 'cooking', tool_bookFin: 'finance',
      tool_bookLit: 'writing', tool_bookLang: 'language',
    }
    const skillId = map[bookEntry.itemId] ?? 'craft'
    studySkill(ctx as never, skillId, 2)
  },
}

const exerciseDef: VerbDef = {
  name: 'exercise', aliases: ['锻炼', '健身'], category: '成长', desc: '锻炼身体，提升健康与魅力', usage: '锻炼 [小时]',
  run: (ctx) => {
    const state = ctx.state
    const atGym = state.player.locationId === 'gym'
    if (!atGym && state.player.locationId !== 'park' && state.player.locationId !== 'home') {
      return fail(ctx, '锻炼要去健身房、公园，或在家运动。')
    }
    const hours = Math.min(3, Math.max(1, ctx.args.numbers[0] ?? 1))
    let cost = 0
    if (atGym) {
      cost = state.player.inventory.some((e) => e.itemId === 'lux_gymCard') ? 5 : 40
      if (state.player.money < cost) return fail(ctx, `健身房单次门票 ${fmtMoney(cost)}，现金不足。`)
      addMoney(state, -cost, 'gym')
    }
    adjustAttrs(state, { health: 6 * hours, stamina: -10 * hours, charm: 1, mood: 4, satiety: -8 * hours, hygiene: -12 })
    const fit = state.player.skills['fitness'] ?? { level: 0, exp: 0 }
    fit.exp += 12 * hours
    if (fit.exp >= fit.level * 100 + 100 && fit.level < 10) { fit.level += 1; fit.exp = 0; pushMessage(state, 'system', `健身等级提升到 ${fit.level} 级！`) }
    state.player.skills['fitness'] = fit
    state.pendingMinutes = hours * 60
    const vars = { name: state.player.name }
    pushResult(state, narrate(EXERCISE_TEMPLATES, narrativeCtx(ctx), vars, () => ctx.rng.next()) + (cost ? `（门票 ${fmtMoney(cost)}）` : ''))
  },
}

const attendSchoolDef: VerbDef = {
  name: 'attendSchool', aliases: ['上学', '进修'], category: '成长', desc: '在学校进修更高学历', usage: '上学 <学历>',
  run: (ctx) => {
    const state = ctx.state
    const p = state.player
    const eduToken = ctx.args.tokens.find((t) => t.target?.type === 'education')
    const targetName = eduToken?.value ?? [...EDUCATION_BY_NAME.keys()].find((n) => ctx.args.raw.includes(n))
    if (!targetName) return fail(ctx, `要进修什么学历？可选：${EDUCATIONS.map((e) => e.name).join('、')}。`)
    const target = EDUCATION_BY_NAME.get(targetName)
    if (!target) return fail(ctx, `没有「${targetName}」这个学历。`)
    const order = EDUCATIONS.map((e) => e.id)
    if (order.indexOf(target.id) <= order.indexOf(p.education)) return fail(ctx, `你已经是「${EDUCATION_BY_NAME.get(p.education)?.name}」学历了。`)
    if (state.player.locationId !== 'school') return fail(ctx, '要去学校才能进修。输入「去 学校」。')
    if (p.attrs.intellect < target.examIntellect - 10) {
      return fail(ctx, `「${target.name}」入学考试需要智力约 ${target.examIntellect}，先提升智力（多学习）。`)
    }
    if (p.money < target.cost) return fail(ctx, `学费需要 ${fmtMoney(target.cost)}，现金不足。`)
    addMoney(state, -target.cost, 'education')
    p.educationProgress += 1
    state.pendingMinutes = 8 * 60
    pushResult(state, `你报名了「${target.name}」课程，开始进修。学满后参加考试即可毕业（考试用「考试」指令）。`)
  },
}

const takeExamDef: VerbDef = {
  name: 'takeExam', aliases: ['考试'], category: '成长', desc: '参加学历或证书考试', usage: '考试',
  run: (ctx) => {
    const state = ctx.state
    const p = state.player
    if (state.player.locationId !== 'school') return fail(ctx, '考试要去学校。输入「去 学校」。')
    const order = EDUCATIONS.map((e) => e.id)
    const nextEdu = EDUCATIONS.find((e) => order.indexOf(e.id) > order.indexOf(p.education))
    const licenseReady = LICENSES.find((l) => !p.licenses.includes(l.id) && Object.entries(l.requireSkills ?? {}).every(([k, v]) => (p.skills[k]?.level ?? 0) >= v))
    if (p.educationProgress > 0) {
      const next = nextEdu
      if (!next) return fail(ctx, '你已经是最高学历了。')
      const pass = p.attrs.intellect >= next.examIntellect
      p.educationProgress = 0
      if (pass) {
        p.education = next.id
        pushResult(state, `考试通过！你获得了「${next.name}」学历。`)
        p.stats.milestones.push({ year: 0, text: `获得${next.name}学历` })
        p.reputation += 3
      } else {
        pushWarning(state, `考试差了几分（需要智力 ${next.examIntellect}），再准备准备吧。`)
      }
      state.pendingMinutes = 180
      return
    }
    if (licenseReady) {
      const cost = licenseReady.examCost
      if (p.money < cost) return fail(ctx, `考试费 ${fmtMoney(cost)}，现金不足。`)
      addMoney(state, -cost, 'license')
      p.licenses.push(licenseReady.id)
      pushResult(state, `恭喜！你通过了「${licenseReady.name}」考试。`)
      state.pendingMinutes = 120
      return
    }
    if (nextEdu) {
      return fail(ctx, `你还没有进修「${nextEdu.name}」课程（先「上学 ${nextEdu.name}」），或可以考证书。`)
    }
    return fail(ctx, '当前没有可参加的考试。')
  },
}

const getLicenseDef: VerbDef = {
  name: 'getLicense', aliases: ['考证', '考驾照'], category: '成长', desc: '考取证书（需满足技能要求）', usage: '考证 <证书名>',
  run: (ctx) => {
    takeExamDef.run(ctx)
  },
}

export function registerCareerVerbs(): void {
  registerVerb(workDef)
  registerVerb(overtimeDef)
  registerVerb(jobHuntDef)
  registerVerb(applyDef)
  registerVerb(resignDef)
  registerVerb(studyDef)
  registerVerb(readDef)
  registerVerb(exerciseDef)
  registerVerb(attendSchoolDef)
  registerVerb(takeExamDef)
  registerVerb(getLicenseDef)
}

void hasLicense
void adjustAttr
void pushWarning
void LICENSE_BY_NAME
