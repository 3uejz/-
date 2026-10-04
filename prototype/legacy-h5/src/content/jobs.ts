export interface JobDef {
  id: string
  title: string
  salary: number
  workHours: number
  requireEducation?: string
  requireSkills?: Record<string, number>
  requireLicenses?: string[]
  requireCredit?: number
  promotion?: string
  promotionYears?: number
  desc: string
}

export const JOBS: JobDef[] = [
  { id: 'dishwasher', title: '洗碗工', salary: 2600, workHours: 9, desc: '餐厅后厨，清洗如山碗碟。' },
  { id: 'waiter', title: '服务员', salary: 3200, workHours: 10, promotion: 'restaurantManager', promotionYears: 3, desc: '端茶送水，眼观六路。' },
  { id: 'restaurantManager', title: '餐厅经理', salary: 8500, workHours: 10, requireSkills: { persuasion: 3 }, promotion: 'headChef', promotionYears: 3, desc: '统筹前厅大小事务。' },
  { id: 'chef', title: '厨师', salary: 6000, workHours: 10, requireSkills: { cooking: 4 }, promotion: 'headChef', promotionYears: 3, desc: '锅铲翻飞，五味调和。' },
  { id: 'headChef', title: '主厨', salary: 13000, workHours: 10, requireSkills: { cooking: 7 }, desc: '厨房的最高指挥。' },
  { id: 'courier', title: '外卖员', salary: 4500, workHours: 10, requireSkills: { driving: 1 }, desc: '风里来雨里去，与时间赛跑。' },
  { id: 'driver', title: '司机', salary: 5000, workHours: 9, requireSkills: { driving: 3 }, requireLicenses: ['license_driving'], promotion: 'courier', promotionYears: 2, desc: '方向盘握在手里，路在脚下。' },
  { id: 'security', title: '保安', salary: 3400, workHours: 12, promotion: 'securityHead', promotionYears: 3, desc: '站岗巡逻，守护安宁。' },
  { id: 'securityHead', title: '保安队长', salary: 5200, workHours: 12, desc: '带队执勤，责任更重。' },
  { id: 'cleaner', title: '保洁员', salary: 2800, workHours: 8, desc: '城市的美容师。' },
  { id: 'factoryWorker', title: '工厂工人', salary: 4200, workHours: 11, promotion: 'foreman', promotionYears: 3, desc: '流水线上日复一日。' },
  { id: 'foreman', title: '工头', salary: 6800, workHours: 11, desc: '带班组赶工期。' },
  { id: 'barista', title: '咖啡师', salary: 4500, workHours: 9, requireSkills: { cooking: 2 }, desc: '拉花间满是匠心。' },
  { id: 'cashier', title: '收银员', salary: 3500, workHours: 9, desc: '扫码收钱，细心为本。' },
  { id: 'salesman', title: '销售员', salary: 4000, workHours: 9, requireSkills: { persuasion: 2 }, promotion: 'salesManager', promotionYears: 2, desc: '业绩就是尊严。' },
  { id: 'salesManager', title: '销售经理', salary: 9500, workHours: 10, requireSkills: { persuasion: 5 }, desc: '带领团队冲锋陷阵。' },
  { id: 'programmer', title: '程序员', salary: 9000, workHours: 9, requireEducation: 'college', requireSkills: { programming: 4 }, promotion: 'seniorDev', promotionYears: 2, desc: '代码编织未来。' },
  { id: 'seniorDev', title: '高级开发', salary: 16000, workHours: 9, requireSkills: { programming: 7 }, promotion: 'techLead', promotionYears: 3, desc: '攻克最难的技术关。' },
  { id: 'techLead', title: '技术总监', salary: 30000, workHours: 10, requireSkills: { programming: 9 }, desc: '掌舵技术方向。' },
  { id: 'accountant', title: '会计', salary: 6500, workHours: 8, requireEducation: 'college', requireLicenses: ['license_accounting'], promotion: 'financeManager', promotionYears: 3, desc: '一分一毫都算得明白。' },
  { id: 'financeManager', title: '财务经理', salary: 12000, workHours: 9, requireSkills: { finance: 5 }, desc: '公司的钱袋子管家。' },
  { id: 'stockbroker', title: '证券经纪人', salary: 10000, workHours: 9, requireEducation: 'bachelor', requireSkills: { finance: 5 }, desc: '红绿K线间游走。' },
  { id: 'teacher', title: '教师', salary: 7000, workHours: 8, requireEducation: 'bachelor', requireLicenses: ['license_teaching'], requireSkills: { language: 3 }, desc: '三尺讲台，桃李天下。' },
  { id: 'translator', title: '翻译', salary: 7500, workHours: 8, requireSkills: { language: 5 }, promotion: 'interpreter', promotionYears: 3, desc: '架起语言之间的桥梁。' },
  { id: 'interpreter', title: '高级译员', salary: 14000, workHours: 8, requireSkills: { language: 8 }, desc: '国际会议上的声音。' },
  { id: 'writer', title: '作家', salary: 5500, workHours: 6, requireSkills: { writing: 5 }, desc: '笔尖流淌悲欢。' },
  { id: 'musician', title: '驻唱歌手', salary: 6000, workHours: 6, requireSkills: { music: 4 }, desc: '夜色中唱尽心事。' },
  { id: 'doctor', title: '医生', salary: 18000, workHours: 11, requireEducation: 'master', requireSkills: { medicine: 7 }, requireLicenses: ['license_medical'], desc: '白衣执甲，妙手仁心。' },
  { id: 'nurse', title: '护士', salary: 5800, workHours: 10, requireEducation: 'college', requireSkills: { medicine: 3 }, desc: '打针发药，昼夜倒班。' },
  { id: 'police_officer', title: '警察', salary: 7500, workHours: 10, requireEducation: 'college', requireCredit: 50, desc: '维护正义与秩序。' },
]

export const JOB_INDEX = new Map(JOBS.map((j) => [j.id, j]))
export const JOB_BY_NAME = new Map<string, JobDef>()
for (const job of JOBS) {
  JOB_BY_NAME.set(job.title, job)
  JOB_BY_NAME.set(job.id, job)
}

export function jobById(id: string): JobDef {
  const j = JOB_INDEX.get(id)
  if (!j) throw new Error(`unknown job: ${id}`)
  return j
}

export function jobTitle(id: string | null): string {
  if (!id) return '无业'
  return jobById(id).title
}

// ---------------- Skills / Education / Licenses ----------------

export interface SkillDef {
  id: string
  name: string
  desc: string
  /** Study minutes per exp point at library-optimized conditions. */
  expPerHour: number
}

export const SKILLS: SkillDef[] = [
  { id: 'programming', name: '编程', expPerHour: 10, desc: '与机器对话的艺术。' },
  { id: 'cooking', name: '烹饪', expPerHour: 10, desc: '人间烟火的手艺。' },
  { id: 'driving', name: '驾驶', expPerHour: 12, desc: '人车合一。' },
  { id: 'music', name: '音乐', expPerHour: 9, desc: '旋律与节奏。' },
  { id: 'language', name: '外语', expPerHour: 8, desc: '通往世界的钥匙。' },
  { id: 'writing', name: '写作', expPerHour: 9, desc: '文字的力量。' },
  { id: 'art', name: '绘画', expPerHour: 9, desc: '色彩的魔法。' },
  { id: 'finance', name: '金融', expPerHour: 8, desc: '钱生钱的学问。' },
  { id: 'fitness', name: '健身', expPerHour: 12, desc: '淬炼体魄。' },
  { id: 'medicine', name: '医术', expPerHour: 7, desc: '悬壶济世。' },
  { id: 'persuasion', name: '口才', expPerHour: 10, desc: '三寸不烂之舌。' },
  { id: 'craft', name: '手工', expPerHour: 11, desc: '指尖的匠气。' },
]

export const SKILL_INDEX = new Map(SKILLS.map((s) => [s.id, s]))
export const SKILL_BY_NAME = new Map<string, SkillDef>(SKILLS.map((s) => [s.name, s]))

export interface EducationDef {
  id: string
  name: string
  /** Study days required before exam. */
  studyDays: number
  /** Minimum intellect to pass exam. */
  examIntellect: number
  cost: number
  desc: string
}

export const EDUCATIONS: EducationDef[] = [
  { id: 'junior', name: '初中', studyDays: 0, examIntellect: 0, cost: 0, desc: '义务教育起点。' },
  { id: 'senior', name: '高中', studyDays: 120, examIntellect: 40, cost: 3000, desc: '熬夜刷题的青春。' },
  { id: 'college', name: '大专', studyDays: 150, examIntellect: 50, cost: 8000, desc: '一技之长。' },
  { id: 'bachelor', name: '本科', studyDays: 200, examIntellect: 62, cost: 16000, desc: '象牙塔四年。' },
  { id: 'master', name: '硕士', studyDays: 240, examIntellect: 75, cost: 30000, desc: '学术的深水区。' },
]

export const EDUCATION_INDEX = new Map(EDUCATIONS.map((e) => [e.id, e]))
export const EDUCATION_BY_NAME = new Map(EDUCATIONS.map((e) => [e.name, e]))

export interface LicenseDef {
  id: string
  name: string
  requireSkills?: Record<string, number>
  examCost: number
  unlockJob: boolean
  desc: string
}

export const LICENSES: LicenseDef[] = [
  { id: 'license_driving', name: '驾照', requireSkills: { driving: 2 }, examCost: 3000, unlockJob: true, desc: '合法上路。' },
  { id: 'license_teaching', name: '教师资格证', requireSkills: { language: 3 }, examCost: 800, unlockJob: true, desc: '执教资格。' },
  { id: 'license_accounting', name: '会计证', requireSkills: { finance: 3 }, examCost: 1000, unlockJob: true, desc: '财务入行凭证。' },
  { id: 'license_medical', name: '医师资格证', requireSkills: { medicine: 6 }, examCost: 2000, unlockJob: true, desc: '行医资格。' },
  { id: 'license_cooking', name: '厨师证', requireSkills: { cooking: 4 }, examCost: 600, unlockJob: true, desc: '厨艺认证。' },
]

export const LICENSE_INDEX = new Map(LICENSES.map((l) => [l.id, l]))
export const LICENSE_BY_NAME = new Map(LICENSES.map((l) => [l.name, l]))
