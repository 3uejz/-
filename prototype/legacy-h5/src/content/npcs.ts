import type { NPCScheduleSlot } from '../engine/state'

export interface NPCDef {
  id: string
  name: string
  gender: 'm' | 'f'
  age: number
  jobId: string | null
  personality: string[]
  homeId: string
  workLocationId: string | null
  leisureLocationId: string
  /** base relationship when game starts */
  startRelationship: number
  desc: string
}

export const NPC_DEFS: NPCDef[] = [
  { id: 'npc_mother', name: '王秀兰', gender: 'f', age: 48, jobId: null, personality: ['慈爱', '唠叨'], homeId: 'home', workLocationId: null, leisureLocationId: 'park', startRelationship: 75, desc: '你的母亲，永远惦记你吃饱穿暖。' },
  { id: 'npc_father', name: '李建国', gender: 'm', age: 51, jobId: 'factoryWorker', personality: ['沉默', '坚韧'], homeId: 'home', workLocationId: 'company', leisureLocationId: 'park', startRelationship: 70, desc: '你的父亲，话少但肩膀很宽。' },
  { id: 'npc_boss', name: '陈国富', gender: 'm', age: 45, jobId: 'techLead', personality: ['精明', '严格'], homeId: 'prop_flathome', workLocationId: 'company', leisureLocationId: 'cafe', startRelationship: 0, desc: '公司的顶头上司，眼神锐利。' },
  { id: 'npc_colleague', name: '刘晓峰', gender: 'm', age: 27, jobId: 'programmer', personality: ['热心', '话痨'], homeId: 'prop_flatown', workLocationId: 'company', leisureLocationId: 'netbar', startRelationship: 20, desc: '隔壁工位的老熟人。' },
  { id: 'npc_teacher', name: '赵文静', gender: 'f', age: 35, jobId: 'teacher', personality: ['温柔', '博学'], homeId: 'prop_flatown', workLocationId: 'school', leisureLocationId: 'library', startRelationship: 10, desc: '戴上眼镜是严师，摘下眼镜是知己。' },
  { id: 'npc_doctor', name: '周明远', gender: 'm', age: 40, jobId: 'doctor', personality: ['冷静', '专业'], homeId: 'prop_flathigh', workLocationId: 'hospital', leisureLocationId: 'gym', startRelationship: 0, desc: '主治医师，见惯生死却仍怀仁心。' },
  { id: 'npc_banker', name: '孙丽华', gender: 'f', age: 38, jobId: 'financeManager', personality: ['干练', '谨慎'], homeId: 'prop_flathigh', workLocationId: 'bank', leisureLocationId: 'mall', startRelationship: 0, desc: '银行客户经理，笑容标准。' },
  { id: 'npc_vendor', name: '张大壮', gender: 'm', age: 42, jobId: 'salesman', personality: ['豪爽', '大嗓门'], homeId: 'prop_flatsmall', workLocationId: 'nightMarket', leisureLocationId: 'nightMarket', startRelationship: 15, desc: '夜市摊主，烤串摊的活招牌。' },
  { id: 'npc_classmate', name: '林雨薇', gender: 'f', age: 24, jobId: 'barista', personality: ['文艺', '细腻'], homeId: 'prop_flatsmall', workLocationId: 'cafe', leisureLocationId: 'cinema', startRelationship: 25, desc: '旧日同窗，笑起来眼睛弯弯。' },
  { id: 'npc_classmate2', name: '张浩然', gender: 'm', age: 25, jobId: 'courier', personality: ['仗义', '冲动'], homeId: 'prop_flatsmall', workLocationId: 'station', leisureLocationId: 'netbar', startRelationship: 30, desc: '穿一条裤子长大的兄弟。' },
  { id: 'npc_landlord', name: '钱多多', gender: 'm', age: 55, jobId: null, personality: ['精明', '抠门'], homeId: 'prop_villaSub', workLocationId: null, leisureLocationId: 'park', startRelationship: 10, desc: '你的房东，收租日笑容格外灿烂。' },
  { id: 'npc_neighbor', name: '吴阿婆', gender: 'f', age: 68, jobId: null, personality: ['热心', '八卦'], homeId: 'prop_flatown', workLocationId: null, leisureLocationId: 'park', startRelationship: 20, desc: '楼下邻居，全小区的消息中枢。' },
  { id: 'npc_coach', name: '石铁柱', gender: 'm', age: 33, jobId: null, personality: ['豪迈', '严格'], homeId: 'prop_flatsmall', workLocationId: 'gym', leisureLocationId: 'gym', startRelationship: 10, desc: '健身房教练，嗓门能震碎杠铃片。' },
  { id: 'npc_nurse', name: '苏小暖', gender: 'f', age: 26, jobId: 'nurse', personality: ['细心', '乐观'], homeId: 'prop_flatsmall', workLocationId: 'hospital', leisureLocationId: 'park', startRelationship: 5, desc: '护士站的微笑担当。' },
  { id: 'npc_broker', name: '郑天成', gender: 'm', age: 31, jobId: 'stockbroker', personality: ['机敏', '激进'], homeId: 'prop_flathome', workLocationId: 'stockExchange', leisureLocationId: 'ktv', startRelationship: 0, desc: '证券公司红人，永远在追涨杀跌。' },
  { id: 'npc_artist', name: '顾清秋', gender: 'f', age: 29, jobId: 'writer', personality: ['沉静', '敏感'], homeId: 'prop_flathigh', workLocationId: 'library', leisureLocationId: 'scenicArea', startRelationship: 5, desc: '常在湖边写作的女子。' },
  { id: 'npc_musician', name: '韩乐天', gender: 'm', age: 28, jobId: 'musician', personality: ['洒脱', '浪漫'], homeId: 'prop_flatsmall', workLocationId: 'nightMarket', leisureLocationId: 'ktv', startRelationship: 10, desc: '抱着吉他的流浪歌手。' },
  { id: 'npc_cop', name: '雷正', gender: 'm', age: 36, jobId: 'police_officer', personality: ['正直', '铁面'], homeId: 'prop_flatown', workLocationId: 'police', leisureLocationId: 'gym', startRelationship: 0, desc: '片区民警，眼里揉不得沙子。' },
  { id: 'npc_chef', name: '蔡香厨', gender: 'm', age: 50, jobId: 'headChef', personality: ['暴脾气', '授业'], homeId: 'prop_flatown', workLocationId: 'restaurant', leisureLocationId: 'nightMarket', startRelationship: 0, desc: '后厨之魂，骂人声与菜香齐飞。' },
  { id: 'npc_florist', name: '唐小婉', gender: 'f', age: 23, jobId: 'salesman', personality: ['甜美', '健谈'], homeId: 'prop_flatsmall', workLocationId: 'mall', leisureLocationId: 'cinema', startRelationship: 10, desc: '花店打工的姑娘，笑靥如花。' },
  { id: 'npc_driver', name: '曹师傅', gender: 'm', age: 47, jobId: 'driver', personality: ['健谈', '世故'], homeId: 'prop_flatsmall', workLocationId: 'station', leisureLocationId: 'nightMarket', startRelationship: 10, desc: '出租车司机，城市故事的活地图。' },
  { id: 'npc_intern', name: '叶知秋', gender: 'f', age: 22, jobId: 'cashier', personality: ['青涩', '勤奋'], homeId: 'prop_flatsmall', workLocationId: 'supermarket', leisureLocationId: 'library', startRelationship: 5, desc: '刚入社会的实习生。' },
]

export function buildSchedule(def: NPCDef): NPCScheduleSlot[] {
  const home = def.homeId
  if (def.workLocationId) {
    return [
      { from: 0, to: 7, locationId: home },
      { from: 7, to: 9, locationId: 'station' },
      { from: 9, to: 12, locationId: def.workLocationId },
      { from: 12, to: 13, locationId: def.leisureLocationId },
      { from: 13, to: 18, locationId: def.workLocationId },
      { from: 18, to: 21, locationId: def.leisureLocationId },
      { from: 21, to: 24, locationId: home },
    ]
  }
  return [
    { from: 0, to: 8, locationId: home },
    { from: 8, to: 11, locationId: 'park' },
    { from: 11, to: 14, locationId: home },
    { from: 14, to: 18, locationId: def.leisureLocationId },
    { from: 18, to: 21, locationId: def.leisureLocationId },
    { from: 21, to: 24, locationId: home },
  ]
}
