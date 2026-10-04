// Legacy system: cross-run progression.
// Talents are defined here to avoid content dependency cycles.

export interface TalentDef {
  id: string
  name: string
  cost: number
  desc: string
}

export const TALENTS: TalentDef[] = [
  { id: 'tal_study', name: '天资聪颖', cost: 10, desc: '学习效率 +30%' },
  { id: 'tal_body', name: '体质过人', cost: 10, desc: '健康下限保护，疾病恢复更快' },
  { id: 'tal_charm', name: '魅力出众', cost: 10, desc: '初始魅力 +20，社交更顺利' },
  { id: 'tal_money', name: '家族资助', cost: 15, desc: '开局获得 ￥20,000 资助' },
  { id: 'tal_lucky', name: '福星高照', cost: 20, desc: '随机事件更容易带来好事' },
  { id: 'tal_business', name: '商业嗅觉', cost: 20, desc: '店铺营收 +25%' },
]

export const TALENT_INDEX = new Map(TALENTS.map((t) => [t.id, t]))
export const TALENT_BY_NAME = new Map(TALENTS.map((t) => [t.name, t]))

/** Legacy points formula based on last run achievements. */
export function computeLegacyPoints(totalAchievements: number, runsCompleted: number): number {
  return Math.floor(totalAchievements * 0.5) + runsCompleted * 2
}
