import type { GameState } from '../engine/state'
import { calendar } from '../engine/time'
import { SKILL_INDEX, JOB_INDEX } from './jobs'

export interface AchievementDef {
  id: string
  name: string
  category: 'wealth' | 'career' | 'skill' | 'social' | 'family' | 'explore' | 'fortune'
  desc: string
  check: (s: GameState) => boolean
}

const money = (s: GameState) => s.player.money + s.player.bank
const earned = (s: GameState) => s.player.stats.totalEarned
const skill = (s: GameState, id: string) => s.player.skills[id]?.level ?? 0
const jobSalary = (s: GameState) => (s.player.job ? JOB_INDEX.get(s.player.job.jobId)?.salary ?? 0 : 0)

const WEALTH: AchievementDef[] = [
  { id: 'w_1k', name: '第一桶金', category: 'wealth', desc: '总资产达到 1,000 元', check: (s) => money(s) >= 1000 },
  { id: 'w_10k', name: '万元户', category: 'wealth', desc: '总资产达到 10,000 元', check: (s) => money(s) >= 10000 },
  { id: 'w_100k', name: '小有积蓄', category: 'wealth', desc: '总资产达到 100,000 元', check: (s) => money(s) >= 100000 },
  { id: 'w_1m', name: '百万富翁', category: 'wealth', desc: '总资产达到 1,000,000 元', check: (s) => money(s) >= 1000000 },
  { id: 'w_10m', name: '千万俱乐部', category: 'wealth', desc: '总资产达到 10,000,000 元', check: (s) => money(s) >= 10000000 },
  { id: 'w_100m', name: '亿万人家', category: 'wealth', desc: '总资产达到 100,000,000 元', check: (s) => money(s) >= 100000000 },
  { id: 'w_earn10k', name: '劳动所得', category: 'wealth', desc: '累计收入达到 10,000 元', check: (s) => earned(s) >= 10000 },
  { id: 'w_earn100k', name: '稳定进账', category: 'wealth', desc: '累计收入达到 100,000 元', check: (s) => earned(s) >= 100000 },
  { id: 'w_earn1m', name: '收入破百万', category: 'wealth', desc: '累计收入达到 1,000,000 元', check: (s) => earned(s) >= 1000000 },
  { id: 'w_earn5m', name: '财富自由', category: 'wealth', desc: '累计收入达到 5,000,000 元', check: (s) => earned(s) >= 5000000 },
  { id: 'w_firstStock', name: '初入股海', category: 'wealth', desc: '买入第一支股票', check: (s) => s.player.stocks.length > 0 },
  { id: 'w_stockAll', name: '投资组合', category: 'wealth', desc: '同时持有 5 支以上股票', check: (s) => s.player.stocks.length >= 5 },
  { id: 'w_stockRich', name: '股海弄潮', category: 'wealth', desc: '单支股票盈利超过 50,000 元', check: (s) => s.player.stocks.some((p) => (p.shares * s.stocks.find((x) => x.stockId === p.stockId)!.price) - p.shares * p.avgCost >= 50000) },
  { id: 'w_buyHouse', name: '安家立业', category: 'wealth', desc: '买下第一套房产', check: (s) => s.player.estate.propertyId !== null },
  { id: 'w_villa', name: '湖畔人生', category: 'wealth', desc: '拥有湖畔别墅', check: (s) => s.player.estate.propertyId === 'prop_villaLux' },
  { id: 'w_openShop', name: '自主创业', category: 'wealth', desc: '开设自己的店铺', check: (s) => s.player.shop !== null },
  { id: 'w_shopRich', name: '日进斗金', category: 'wealth', desc: '店铺单日营收超过 5,000 元', check: (s) => (s.player.shop?.dailyRevenue ?? 0) >= 5000 },
  { id: 'w_debtFree', name: '无债一身轻', category: 'wealth', desc: '还清全部贷款', check: (s) => s.player.loan === null && s.player.stats.milestones.some((m) => m.text.includes('贷款')) },
  { id: 'w_car', name: '有车一族', category: 'wealth', desc: '购买第一辆汽车', check: (s) => s.player.vehicle.vehicleItemId !== null && s.player.vehicle.vehicleItemId !== 'veh_ebike' },
  { id: 'w_supercar', name: '豪车梦', category: 'wealth', desc: '拥有豪华跑车', check: (s) => s.player.vehicle.vehicleItemId === 'veh_luxury' },
  { id: 'w_spend100k', name: '消费达人', category: 'wealth', desc: '累计支出达到 100,000 元', check: (s) => s.player.stats.totalSpent >= 100000 },
  { id: 'w_bank100k', name: '储蓄高手', category: 'wealth', desc: '银行存款达到 100,000 元', check: (s) => s.player.bank >= 100000 },
  { id: 'w_lottery', name: '天降横财', category: 'wealth', desc: '彩票中奖金额超过 1,000 元', check: (s) => s.player.stats.milestones.some((m) => m.text.includes('彩票中奖')) },
  { id: 'w_foodie', name: '美食家', category: 'wealth', desc: '累计用餐 100 次', check: (s) => s.player.stats.milestones.filter((m) => m.text.includes('用餐')).length >= 100 },
  { id: 'w_rent', name: '包租公婆', category: 'wealth', desc: '持有房产并同时开店', check: (s) => s.player.estate.propertyId !== null && s.player.shop !== null },
  { id: 'w_inflation', name: '理财觉醒', category: 'wealth', desc: '定期存款到期并领取利息', check: (s) => s.player.stats.milestones.some((m) => m.text.includes('利息')) },
]

const CAREER: AchievementDef[] = [
  { id: 'c_firstJob', name: '初入职场', category: 'career', desc: '获得第一份工作', check: (s) => s.player.stats.jobsHeld.length >= 1 },
  { id: 'c_twoJobs', name: '职业轨迹', category: 'career', desc: '累计从事过 2 份工作', check: (s) => s.player.stats.jobsHeld.length >= 2 },
  { id: 'c_fourJobs', name: '职场老手', category: 'career', desc: '累计从事过 4 份工作', check: (s) => s.player.stats.jobsHeld.length >= 4 },
  { id: 'c_promoted', name: '步步高升', category: 'career', desc: '获得第一次升职', check: (s) => s.player.job !== null && s.player.job.performance >= 1 },
  { id: 'c_dev', name: '码农上岸', category: 'career', desc: '成为程序员', check: (s) => s.player.stats.jobsHeld.includes('programmer') },
  { id: 'c_techLead', name: '技术之巅', category: 'career', desc: '成为技术总监', check: (s) => s.player.stats.jobsHeld.includes('techLead') },
  { id: 'c_doctor', name: '白衣天使', category: 'career', desc: '成为医生', check: (s) => s.player.stats.jobsHeld.includes('doctor') },
  { id: 'c_chef', name: '厨房之魂', category: 'career', desc: '成为主厨', check: (s) => s.player.stats.jobsHeld.includes('headChef') },
  { id: 'c_salesMgr', name: '销售之王', category: 'career', desc: '成为销售经理', check: (s) => s.player.stats.jobsHeld.includes('salesManager') },
  { id: 'c_financeMgr', name: '金库掌门', category: 'career', desc: '成为财务经理', check: (s) => s.player.stats.jobsHeld.includes('financeManager') },
  { id: 'c_highSalary', name: '高薪人士', category: 'career', desc: '月薪超过 15,000 元', check: (s) => jobSalary(s) >= 15000 },
  { id: 'c_topSalary', name: '人生赢家', category: 'career', desc: '月薪超过 30,000 元', check: (s) => jobSalary(s) >= 30000 },
  { id: 'c_overtime', name: '卷王', category: 'career', desc: '累计加班 30 次', check: (s) => s.player.stats.milestones.filter((m) => m.text.includes('加班')).length >= 30 },
  { id: 'c_resign', name: '世界很大', category: 'career', desc: '主动辞掉一次工作', check: (s) => s.player.stats.milestones.some((m) => m.text.includes('辞职')) },
  { id: 'c_boss', name: '老板娘/老板', category: 'career', desc: '拥有自己的店铺并雇佣 2 名员工', check: (s) => (s.player.shop?.employees.length ?? 0) >= 2 },
]

const SKILL: AchievementDef[] = [
  { id: 's_prog5', name: '代码入门', category: 'skill', desc: '编程达到 5 级', check: (s) => skill(s, 'programming') >= 5 },
  { id: 's_prog10', name: '编程大师', category: 'skill', desc: '编程达到 10 级', check: (s) => skill(s, 'programming') >= 10 },
  { id: 's_cook5', name: '家常菜神', category: 'skill', desc: '烹饪达到 5 级', check: (s) => skill(s, 'cooking') >= 5 },
  { id: 's_music5', name: '业余歌手', category: 'skill', desc: '音乐达到 5 级', check: (s) => skill(s, 'music') >= 5 },
  { id: 's_lang5', name: '多语者', category: 'skill', desc: '外语达到 5 级', check: (s) => skill(s, 'language') >= 5 },
  { id: 's_write5', name: '笔耕不辍', category: 'skill', desc: '写作达到 5 级', check: (s) => skill(s, 'writing') >= 5 },
  { id: 's_fin5', name: '理财能手', category: 'skill', desc: '金融达到 5 级', check: (s) => skill(s, 'finance') >= 5 },
  { id: 's_med5', name: '医术小成', category: 'skill', desc: '医术达到 5 级', check: (s) => skill(s, 'medicine') >= 5 },
  { id: 's_all1', name: '样样通', category: 'skill', desc: '所有技能都达到 1 级', check: (s) => SKILL_INDEX.size > 0 && [...SKILL_INDEX.keys()].every((k) => skill(s, k) >= 1) },
  { id: 's_any10', name: '登峰造极', category: 'skill', desc: '任意一项技能达到 10 级', check: (s) => Object.values(s.player.skills).some((x) => x.level >= 10) },
  { id: 's_senior', name: '高中毕业', category: 'skill', desc: '取得高中学历', check: (s) => ['senior', 'college', 'bachelor', 'master'].includes(s.player.education) },
  { id: 's_college', name: '大专毕业', category: 'skill', desc: '取得大专学历', check: (s) => ['college', 'bachelor', 'master'].includes(s.player.education) },
  { id: 's_bachelor', name: '本科毕业', category: 'skill', desc: '取得本科学历', check: (s) => ['bachelor', 'master'].includes(s.player.education) },
  { id: 's_master', name: '硕士毕业', category: 'skill', desc: '取得硕士学历', check: (s) => s.player.education === 'master' },
  { id: 's_lic1', name: '持证上岗', category: 'skill', desc: '取得第一张证书', check: (s) => s.player.licenses.length >= 1 },
  { id: 's_lic3', name: '考证达人', category: 'skill', desc: '取得 3 张证书', check: (s) => s.player.licenses.length >= 3 },
  { id: 's_lic5', name: '证王', category: 'skill', desc: '取得全部 5 张证书', check: (s) => s.player.licenses.length >= 5 },
  { id: 's_fit', name: '自律人生', category: 'skill', desc: '健身达到 7 级', check: (s) => skill(s, 'fitness') >= 7 },
  { id: 's_charm90', name: '气质出众', category: 'skill', desc: '魅力达到 90', check: (s) => s.player.attrs.charm >= 90 },
  { id: 's_intel90', name: '学霸附体', category: 'skill', desc: '智力达到 90', check: (s) => s.player.attrs.intellect >= 90 },
]

const SOCIAL: AchievementDef[] = [
  { id: 'so_friend60', name: '知心好友', category: 'social', desc: '任意 NPC 关系达到 60', check: (s) => s.npcs.some((n) => n.relationship >= 60) },
  { id: 'so_friend90', name: '莫逆之交', category: 'social', desc: '任意 NPC 关系达到 90', check: (s) => s.npcs.some((n) => n.relationship >= 90) },
  { id: 'so_circle', name: '人脉广泛', category: 'social', desc: '5 名以上 NPC 关系达到 60', check: (s) => s.npcs.filter((n) => n.relationship >= 60).length >= 5 },
  { id: 'so_love', name: '心有所属', category: 'social', desc: '成功表白', check: (s) => s.player.stats.milestones.some((m) => m.text.includes('表白')) },
  { id: 'so_repu50', name: '口碑载道', category: 'social', desc: '声望达到 50', check: (s) => s.player.reputation >= 50 },
  { id: 'so_repu100', name: '城市名人', category: 'social', desc: '声望达到 100', check: (s) => s.player.reputation >= 100 },
  { id: 'so_chat100', name: '社交达人', category: 'social', desc: '累计聊天 100 次', check: (s) => s.player.stats.milestones.filter((m) => m.text.includes('聊天')).length >= 100 },
  { id: 'so_gift', name: '礼尚往来', category: 'social', desc: '送出 20 份礼物', check: (s) => s.player.stats.milestones.filter((m) => m.text.includes('送礼')).length >= 20 },
  { id: 'so_help', name: '热心肠', category: 'social', desc: '声望与任意 NPC 关系同时超过 60', check: (s) => s.player.reputation >= 60 && s.npcs.some((n) => n.relationship >= 60) },
  { id: 'so_enemy', name: '树敌者', category: 'social', desc: '任意 NPC 关系低于 -60', check: (s) => s.npcs.some((n) => n.relationship <= -60) },
  { id: 'so_lover50', name: '爱意满满', category: 'social', desc: '与伴侣的关系值达到 95', check: (s) => s.npcs.some((n) => n.id === s.player.family.spouseNpcId && n.relationship >= 95) },
  { id: 'so_introvert', name: '独行者', category: 'social', desc: '一整年没有和任何 NPC 交流', check: (s) => s.player.stats.milestones.some((m) => m.text.includes('与世隔绝')) },
]

const FAMILY: AchievementDef[] = [
  { id: 'f_marry', name: '喜结连理', category: 'family', desc: '结婚', check: (s) => s.player.family.spouseNpcId !== null },
  { id: 'f_child1', name: '初为人父母', category: 'family', desc: '迎来第一个孩子', check: (s) => s.player.family.children.length >= 1 },
  { id: 'f_child2', name: '儿女双全', category: 'family', desc: '拥有两个孩子', check: (s) => s.player.family.children.length >= 2 },
  { id: 'f_child3', name: '多子多福', category: 'family', desc: '拥有三个孩子', check: (s) => s.player.family.children.length >= 3 },
  { id: 'f_home', name: '家庭港湾', category: 'family', desc: '已婚且拥有自购房', check: (s) => s.player.family.spouseNpcId !== null && s.player.estate.propertyId !== null },
  { id: 'f_richHome', name: '富贵之家', category: 'family', desc: '已婚且总资产超过 200 万', check: (s) => s.player.family.spouseNpcId !== null && money(s) >= 2000000 },
  { id: 'f_happy', name: '家和万事兴', category: 'family', desc: '已婚且心情超过 85', check: (s) => s.player.family.spouseNpcId !== null && s.player.attrs.mood >= 85 },
  { id: 'f_divorce', name: '一别两宽', category: 'family', desc: '经历离婚', check: (s) => s.player.stats.milestones.some((m) => m.text.includes('离婚')) },
]

const EXPLORE: AchievementDef[] = [
  { id: 'e_ebike', name: '两轮自由', category: 'explore', desc: '购买电动车', check: (s) => s.player.vehicle.vehicleItemId === 'veh_ebike' },
  { id: 'e_travel', name: '说走就走', category: 'explore', desc: '完成一次长途旅行', check: (s) => s.player.stats.milestones.some((m) => m.text.includes('旅行')) },
  { id: 'e_travel3', name: '旅行家', category: 'explore', desc: '完成三次长途旅行', check: (s) => s.player.stats.milestones.filter((m) => m.text.includes('旅行')).length >= 3 },
  { id: 'e_pc', name: '数码生活', category: 'explore', desc: '拥有电脑', check: (s) => s.player.inventory.some((e) => e.itemId === 'ap_pc') },
  { id: 'e_pet', name: '铲屎官', category: 'explore', desc: '养一只宠物', check: (s) => s.player.inventory.some((e) => e.itemId === 'lux_cat' || e.itemId === 'lux_dog') },
  { id: 'e_gymCard', name: '健身年卡', category: 'explore', desc: '办理健身年卡', check: (s) => s.player.inventory.some((e) => e.itemId === 'lux_gymCard') },
  { id: 'e_book4', name: '书虫', category: 'explore', desc: '集齐 5 本不同的书', check: (s) => s.player.inventory.filter((e) => e.itemId.startsWith('tool_book')).length >= 5 },
  { id: 'e_watch', name: '一表人才', category: 'explore', desc: '拥有名表', check: (s) => s.player.inventory.some((e) => e.itemId === 'lux_watch') },
  { id: 'e_jail', name: '铁窗泪', category: 'explore', desc: '经历一次牢狱之灾', check: (s) => s.player.stats.daysInJail > 0 },
  { id: 'e_cop', name: '常客', category: 'explore', desc: '在警察局留下 3 次案底', check: (s) => s.player.stats.crimes >= 3 },
]

const FORTUNE: AchievementDef[] = [
  { id: 'ft_60', name: '花甲之年', category: 'fortune', desc: '活到 60 岁', check: (s) => calendar(s.time).age >= 60 },
  { id: 'ft_75', name: '古稀在望', category: 'fortune', desc: '活到 75 岁', check: (s) => calendar(s.time).age >= 75 },
  { id: 'ft_90', name: '鲐背之年', category: 'fortune', desc: '活到 90 岁', check: (s) => calendar(s.time).age >= 90 },
  { id: 'ft_events10', name: '经历丰富', category: 'fortune', desc: '遭遇 25 次随机事件', check: (s) => s.player.stats.milestones.filter((m) => m.text.startsWith('事件')).length >= 25 },
  { id: 'ft_events50', name: '风云人生', category: 'fortune', desc: '遭遇 60 次随机事件', check: (s) => s.player.stats.milestones.filter((m) => m.text.startsWith('事件')).length >= 60 },
  { id: 'ft_survive', name: '命悬一线', category: 'fortune', desc: '健康低于 10 后恢复到 60 以上', check: (s) => s.player.stats.milestones.some((m) => m.text.includes('重获新生')) },
  { id: 'ft_richOld', name: '寿富双全', category: 'fortune', desc: '70 岁后总资产超过 500 万', check: (s) => calendar(s.time).age >= 70 && money(s) >= 5000000 },
  { id: 'ft_weather', name: '风雨人生', category: 'fortune', desc: '经历 5 种不同天气', check: () => true },
]

export const ACHIEVEMENTS: AchievementDef[] = [...WEALTH, ...CAREER, ...SKILL, ...SOCIAL, ...FAMILY, ...EXPLORE, ...FORTUNE]

export const ACHIEVEMENT_INDEX = new Map(ACHIEVEMENTS.map((a) => [a.id, a]))
