// Narrative text templates. {vars} are replaced at render time.
// Conditions: night / weather / season / moodLow / moodHigh
import type { TemplateGroup } from '../engine/narrate'

export const MOVE_TEMPLATES: TemplateGroup[] = [
  { texts: ['{name}迈开脚步，朝着{dest}走去。', '穿过几条街道，{name}抵达了{dest}。', '路上行人匆匆，{name}一路来到{dest}。'] },
  { conditions: { weather: 'rain' }, texts: ['雨丝斜织，{name}撑着伞走向{dest}。', '雨水打湿裤脚，{name}快步走向{dest}。'] },
  { conditions: { weather: 'snow' }, texts: ['雪地咯吱作响，{name}深一脚浅一脚地走向{dest}。'] },
  { conditions: { weather: 'heatwave' }, texts: ['烈日灼人，{name}擦着汗走向{dest}。'] },
  { conditions: { weather: 'coldwave' }, texts: ['寒风刺骨，{name}裹紧衣服走向{dest}。'] },
  { conditions: { night: true }, texts: ['夜色渐深，路灯拉长了{name}的影子，走向{dest}。'] },
]

export const SLEEP_TEMPLATES: TemplateGroup[] = [
  { texts: ['{name}洗漱完毕，倒在床上沉沉睡去。', '被窝的温暖包裹了{name}，睡意袭来。', '关灯躺下，{name}很快进入了梦乡。'] },
  { conditions: { moodLow: true }, texts: ['{name}带着一身的疲惫与心事躺下，这一觉并不安稳。'] },
  { conditions: { moodHigh: true }, texts: ['{name}哼着小曲钻进被窝，连梦都是甜的。'] },
]

export const WORK_TEMPLATES: TemplateGroup[] = [
  { texts: ['{name}投入工作，时间在键盘与报表间流逝。', '忙碌的一天，{name}把该做的事一一做完。', '工作台前，{name}全神贯注。'] },
  { conditions: { moodLow: true }, texts: ['{name}强打精神应付工作，效率低得可怜。'] },
  { conditions: { season: 'summer' }, texts: ['空调房里，{name}埋头苦干，窗外蝉鸣阵阵。'] },
]

export const STUDY_TEMPLATES: TemplateGroup[] = [
  { texts: ['{name}静下心来钻研{skill}，渐渐有所领悟。', '一页页翻过，{name}对{skill}的理解又深了一层。', '{name}埋首于{skill}的练习中，忘了时间。'] },
  { conditions: { night: true }, texts: ['夜深人静，{name}仍在灯下苦学{skill}。'] },
  { conditions: { moodLow: true }, texts: ['心浮气躁，{name}学{skill}总是走神，效果一般。'] },
]

export const EXERCISE_TEMPLATES: TemplateGroup[] = [
  { texts: ['{name}挥汗如雨，身体的疲惫换来精神的畅快。', '跑步、拉伸、再冲刺，{name}锻炼得大汗淋漓。'] },
  { conditions: { weather: 'sunny', season: 'spring' }, texts: ['春光正好，{name}在微风中舒展筋骨。'] },
]

export const EAT_TEMPLATES: TemplateGroup[] = [
  { texts: ['{name}坐下来，享用了{item}。', '{item}下肚，饱腹感来得刚刚好。', '{name}细嚼慢咽，把{item}吃得干干净净。'] },
  { conditions: { moodLow: true }, texts: ['{name}机械地吃着{item}，食之无味。'] },
]

export const CHAT_TEMPLATES: TemplateGroup[] = [
  { texts: ['{name}和{npc}聊起了近况，气氛轻松。', '两人有一搭没一搭地聊着，{npc}谈起了自己的见闻。', '{name}与{npc}相谈甚欢。'] },
  { conditions: { moodHigh: true }, texts: ['{name}妙语连珠，{npc}被逗得哈哈大笑。'] },
]

export const BUY_TEMPLATES: TemplateGroup[] = [
  { texts: ['{name}付了钱，把{item}收入囊中。', '扫码付款，{item}到手。', '老板麻利地打包好{item}递了过来。'] },
]

export const WEATHER_ANNOUNCE = {
  sunny: '今日晴朗，风和日丽。',
  rain: '下雨了，出门记得带伞。',
  snow: '落雪了，整座城市银装素裹。',
  heatwave: '高温预警！烈日炙烤着大地。',
  coldwave: '寒潮来袭，气温骤降。',
}

export const LIFE_EVENT_TEXTS = {
  born: '你在这个世界的中心，一座名为云州市的城市醒来。成年人的第一课，是学会独立生活。',
  deathNatural: '岁月的钟摆停在了此刻。你合上双眼，一生的故事就此落笔。',
  deathHealth: '身体终于撑不住了。眼前的世界渐渐模糊、变暗……',
  deathJail: null,
}

export const NEW_YEAR_TEXT = [
  '新的一年开始了，万象更新。',
  '日历翻过最后一页，新的一年悄然而至。',
  '窗外的鞭炮声隐约响起，新年来了。',
]
