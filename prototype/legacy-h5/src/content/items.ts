export type ItemCategory = 'food' | 'medicine' | 'clothes' | 'appliance' | 'tool' | 'vehicle' | 'luxury' | 'special'

export interface ItemDef {
  id: string
  name: string
  category: ItemCategory
  price: number
  /** Effect applied when consumed (food/medicine). */
  effect?: Partial<Record<'satiety' | 'health' | 'mood' | 'stamina' | 'hygiene' | 'charm', number>>
  expiryDays?: number
  /** Purchasing instantly grants this charm/mood bonus. */
  instant?: Partial<Record<'mood' | 'charm', number>>
  desc: string
}

const F = (id: string, name: string, price: number, satiety: number, mood = 0, expiryDays = 7, desc = ''): ItemDef => ({
  id, name, category: 'food', price, effect: { satiety, mood }, expiryDays,
  desc: desc || `${name}，可以填饱肚子。`,
})

const M = (id: string, name: string, price: number, health: number, desc: string): ItemDef => ({
  id, name, category: 'medicine', price, effect: { health }, desc,
})

export const ITEMS: ItemDef[] = [
  // -- food (39) --
  F('food_baozi', '包子', 3, 18, 1, 3),
  F('food_mantou', '馒头', 2, 15, 0, 5),
  F('food_youtiao', '油条', 3, 14, 1, 2),
  F('food_rice', '米饭套餐', 15, 35, 2, 2),
  F('food_noodle', '面条', 12, 32, 2, 3),
  F('food_dumpling', '饺子', 16, 36, 3, 3, '热腾腾的饺子。'),
  F('food_hamburg', '汉堡', 18, 32, 3, 3),
  F('food_hotdog', '热狗', 8, 20, 1, 3),
  F('food_pizza', '披萨', 48, 45, 6, 3),
  F('food_bbq', '烧烤', 35, 30, 6, 2),
  F('food_hotpot', '火锅', 88, 50, 10, 2, '热气腾腾的火锅，暖胃更暖心。'),
  F('food_friedChicken', '炸鸡', 25, 30, 4, 2),
  F('food_sushi', '寿司', 30, 30, 5, 2),
  F('food_salad', '沙拉', 20, 22, 2, 3),
  F('food_luwei', '卤味', 28, 28, 5, 3),
  F('food_cake', '蛋糕', 45, 25, 8, 3),
  F('food_mooncake', '月饼', 12, 18, 4, 30),
  F('food_instantNoodle', '泡面', 5, 22, 1, 60),
  F('food_chips', '薯片', 8, 10, 3, 30),
  F('food_milk', '牛奶', 6, 10, 1, 10),
  F('food_yogurt', '酸奶', 8, 8, 2, 10),
  F('food_bread', '面包', 9, 18, 1, 7),
  F('food_egg', '鸡蛋', 2, 10, 0, 15),
  F('food_apple', '苹果', 5, 12, 1, 15),
  F('food_banana', '香蕉', 4, 11, 1, 7),
  F('food_watermelon', '西瓜', 15, 14, 3, 5),
  F('food_nuts', '坚果', 20, 12, 3, 60),
  F('food_tea', '茶叶', 40, 0, 4, 180, '好茶提神静心。'),
  F('food_coffeeBeans', '咖啡豆', 50, 0, 5, 90),
  F('food_water', '矿泉水', 2, 5, 0, 60),
  F('food_juice', '果汁', 10, 8, 3, 10),
  F('food_cola', '可乐', 4, 6, 2, 60),
  F('food_milkTea', '奶茶', 15, 10, 5, 2),
  F('food_soyMilk', '豆浆', 4, 8, 1, 3),
  F('food_baijiu', '白酒', 60, 0, -5, 360, '烈酒伤身，少喝为宜。'),
  F('food_beer', '啤酒', 6, 3, 3, 60),
  F('food_icecream', '冰淇淋', 8, 6, 4, 2),
  F('food_riceBall', '饭团', 8, 20, 1, 2),
  F('food_fruitBox', '果切拼盘', 18, 14, 4, 2),
  // -- medicine (6) --
  M('med_cold', '感冒药', 15, 12, '缓解感冒症状。'),
  M('med_fever', '退烧药', 20, 16, '退烧必备。'),
  M('med_stomach', '肠胃药', 18, 12, '止住翻江倒海的肚子。'),
  M('med_bandage', '创可贴', 5, 6, '处理小伤口。'),
  M('med_vitamin', '维生素', 35, 6, '每日一粒，健康加分。'),
  M('med_tonic', '滋补品', 120, 20, '名贵滋补品，大补元气。'),
  // -- clothes (13) --
  { id: 'cl_tshirt', name: 'T恤', category: 'clothes', price: 60, instant: { charm: 1 }, desc: '简约百搭。' },
  { id: 'cl_shirt', name: '衬衫', category: 'clothes', price: 150, instant: { charm: 2 }, desc: '干净利落。' },
  { id: 'cl_suit', name: '西装', category: 'clothes', price: 800, instant: { charm: 5 }, desc: '职场标配，气场全开。' },
  { id: 'cl_dress', name: '连衣裙', category: 'clothes', price: 320, instant: { charm: 4 }, desc: '裙摆飞扬的浪漫。' },
  { id: 'cl_downJacket', name: '羽绒服', category: 'clothes', price: 600, instant: { charm: 2 }, desc: '寒冬里的温暖。' },
  { id: 'cl_jeans', name: '牛仔裤', category: 'clothes', price: 200, instant: { charm: 2 }, desc: '耐磨耐穿。' },
  { id: 'cl_sweater', name: '毛衣', category: 'clothes', price: 260, instant: { charm: 2 }, desc: '柔软温暖。' },
  { id: 'cl_sneakers', name: '运动鞋', category: 'clothes', price: 400, instant: { charm: 3 }, desc: '轻便舒适。' },
  { id: 'cl_leatherShoes', name: '皮鞋', category: 'clothes', price: 500, instant: { charm: 3 }, desc: '锃亮体面。' },
  { id: 'cl_tie', name: '领带', category: 'clothes', price: 120, instant: { charm: 1 }, desc: '细节见品味。' },
  { id: 'cl_skirt', name: '半身裙', category: 'clothes', price: 180, instant: { charm: 2 }, desc: '优雅知性。' },
  { id: 'cl_slippers', name: '拖鞋', category: 'clothes', price: 20, desc: '居家必备。' },
  { id: 'cl_hat', name: '帽子', category: 'clothes', price: 80, instant: { charm: 1 }, desc: '凹造型利器。' },
  // -- appliance (12) --
  { id: 'ap_tv', name: '电视机', category: 'appliance', price: 2500, instant: { mood: 5 }, desc: '客厅的主角。' },
  { id: 'ap_fridge', name: '冰箱', category: 'appliance', price: 2200, desc: '食物保质期延长一倍。' },
  { id: 'ap_washer', name: '洗衣机', category: 'appliance', price: 1800, desc: '解放双手，清洁度恢复更快。' },
  { id: 'ap_ac', name: '空调', category: 'appliance', price: 3000, desc: '冬暖夏凉，极端天气的护盾。' },
  { id: 'ap_pc', name: '电脑', category: 'appliance', price: 5500, instant: { mood: 4 }, desc: '学习编程效率大增。' },
  { id: 'ap_phone', name: '手机', category: 'appliance', price: 3500, instant: { mood: 4 }, desc: '现代人的生活枢纽。' },
  { id: 'ap_console', name: '游戏机', category: 'appliance', price: 3000, instant: { mood: 8 }, desc: '快乐源泉。' },
  { id: 'ap_speaker', name: '音箱', category: 'appliance', price: 1200, instant: { mood: 4 }, desc: '音乐环绕。' },
  { id: 'ap_vacuum', name: '吸尘器', category: 'appliance', price: 900, desc: '家务更轻松。' },
  { id: 'ap_microwave', name: '微波炉', category: 'appliance', price: 500, desc: '热饭神器。' },
  { id: 'ap_riceCooker', name: '电饭煲', category: 'appliance', price: 350, desc: '在家做饭更方便。' },
  { id: 'ap_lamp', name: '台灯', category: 'appliance', price: 150, desc: '深夜学习的陪伴。' },
  // -- tool / books (14) --
  { id: 'tool_umbrella', name: '雨伞', category: 'tool', price: 40, desc: '雨天出门不被淋湿。' },
  { id: 'tool_bike', name: '自行车', category: 'tool', price: 600, desc: '绿色出行，短途移动更快。' },
  { id: 'tool_bag', name: '书包', category: 'tool', price: 100, desc: '上学必备。' },
  { id: 'tool_notebook', name: '笔记本', category: 'tool', price: 25, desc: '好记性不如烂笔头。' },
  { id: 'tool_bookProg', name: '《编程入门》', category: 'tool', price: 68, desc: '阅读提升编程经验。' },
  { id: 'tool_bookCook', name: '《烹饪艺术》', category: 'tool', price: 55, desc: '阅读提升烹饪经验。' },
  { id: 'tool_bookFin', name: '《金融投资》', category: 'tool', price: 72, desc: '阅读提升金融经验。' },
  { id: 'tool_bookLit', name: '《文学名著》', category: 'tool', price: 45, desc: '阅读提升写作经验。' },
  { id: 'tool_bookLang', name: '《外语速成》', category: 'tool', price: 60, desc: '阅读提升语言经验。' },
  { id: 'tool_rod', name: '钓鱼竿', category: 'tool', price: 200, desc: '公园垂钓，修身养性。' },
  { id: 'tool_camera', name: '相机', category: 'tool', price: 2800, instant: { mood: 4 }, desc: '记录美好瞬间。' },
  { id: 'tool_guitar', name: '吉他', category: 'tool', price: 900, desc: '练习音乐更有效率。' },
  { id: 'tool_skateboard', name: '滑板', category: 'tool', price: 350, desc: '街头少年的浪漫。' },
  { id: 'tool_luggage', name: '行李箱', category: 'tool', price: 300, desc: '说走就走的旅行。' },
  // -- vehicle (4) --
  { id: 'veh_ebike', name: '电动车', category: 'vehicle', price: 3000, desc: '通勤利器，移动耗时减半。' },
  { id: 'veh_usedCar', name: '二手轿车', category: 'vehicle', price: 25000, desc: '遮风挡雨，代步够了。' },
  { id: 'veh_newCar', name: '新轿车', category: 'vehicle', price: 120000, instant: { charm: 3 }, desc: '体面的座驾。' },
  { id: 'veh_luxury', name: '豪华跑车', category: 'vehicle', price: 600000, instant: { charm: 8, mood: 10 }, desc: '财富与品位的象征。' },
  // -- luxury / misc (12) --
  { id: 'lux_watch', name: '名表', category: 'luxury', price: 12000, instant: { charm: 6 }, desc: '时间与身份的注脚。' },
  { id: 'lux_necklace', name: '项链', category: 'luxury', price: 8000, instant: { charm: 5 }, desc: '颈间的星光。' },
  { id: 'lux_perfume', name: '香水', category: 'luxury', price: 600, instant: { charm: 3 }, desc: '若隐若现的芬芳。' },
  { id: 'lux_flowers', name: '鲜花', category: 'luxury', price: 99, instant: { charm: 2, mood: 2 }, desc: '送人心意，自己愉悦。' },
  { id: 'lux_chocolate', name: '巧克力礼盒', category: 'luxury', price: 128, instant: { mood: 4 }, desc: '甜蜜的礼物。' },
  { id: 'lux_plant', name: '盆栽', category: 'luxury', price: 88, instant: { mood: 3 }, desc: '一抹绿意装点生活。' },
  { id: 'lux_cat', name: '宠物猫', category: 'luxury', price: 2000, instant: { mood: 10 }, desc: '毛茸茸的陪伴。' },
  { id: 'lux_dog', name: '宠物狗', category: 'luxury', price: 2500, instant: { mood: 10 }, desc: '忠诚的伙伴。' },
  { id: 'lux_toy', name: '手办', category: 'luxury', price: 300, instant: { mood: 5 }, desc: '收藏的快乐。' },
  { id: 'lux_gymCard', name: '健身年卡', category: 'luxury', price: 2000, desc: '健身房锻炼费用减半。' },
  { id: 'sp_lotteryTicket', name: '彩票', category: 'special', price: 10, desc: '下一期开奖见分晓。' },
  { id: 'sp_giftBox', name: '精美礼盒', category: 'special', price: 200, desc: '送礼体面又实惠。' },
]

export const ITEM_INDEX = new Map(ITEMS.map((i) => [i.id, i]))
export const ITEM_BY_NAME = new Map<string, ItemDef>()
for (const item of ITEMS) ITEM_BY_NAME.set(item.name, item)

export function itemById(id: string): ItemDef {
  const it = ITEM_INDEX.get(id)
  if (!it) throw new Error(`unknown item: ${id}`)
  return it
}

export function itemByName(name: string): ItemDef | undefined {
  return ITEM_BY_NAME.get(name)
}
