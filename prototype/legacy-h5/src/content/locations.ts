export interface LocationDef {
  id: string
  name: string
  aliases: string[]
  district: string
  openHours: [number, number]
  actions: string[]
  shop?: string
  desc: string
}

export const LOCATIONS: LocationDef[] = [
  { id: 'home', name: '家', aliases: ['回家', '住宅'], district: 'residential', openHours: [0, 24], actions: ['sleep', 'cook', 'decorate', 'eat'], desc: '你的居所，温暖而安静。' },
  { id: 'company', name: '公司', aliases: ['单位', '写字楼'], district: 'downtown', openHours: [8, 22], actions: ['work', 'overtime', 'resign', 'jobHunt'], desc: '钢筋玻璃的写字楼，无数人为生计奔波。' },
  { id: 'businessStreet', name: '商业街', aliases: ['商业区', '街'], district: 'downtown', openHours: [8, 22], actions: ['openShop', 'stroll'], desc: '临街商铺林立，创业者在此圆梦。' },
  { id: 'school', name: '学校', aliases: ['大学', '学院'], district: 'education', openHours: [7, 21], actions: ['attendSchool', 'takeExam'], desc: '知识与青春的殿堂。' },
  { id: 'library', name: '图书馆', aliases: ['图书室'], district: 'education', openHours: [8, 21], actions: ['study', 'read'], desc: '安静的自习圣地，学习效率更高。' },
  { id: 'bookstore', name: '书店', aliases: ['书城'], district: 'education', openHours: [9, 21], actions: ['buy', 'read'], shop: 'bookstore', desc: '一排排书架散发着油墨香。' },
  { id: 'hospital', name: '医院', aliases: ['诊所'], district: 'medical', openHours: [0, 24], actions: ['treat', 'checkup'], desc: '白色的走廊里弥漫着消毒水味。' },
  { id: 'pharmacy', name: '药店', aliases: ['药房'], district: 'medical', openHours: [8, 22], actions: ['buy'], shop: 'pharmacy', desc: '小病小痛，这里就能解决。' },
  { id: 'bank', name: '银行', aliases: ['储蓄所'], district: 'financial', openHours: [9, 17], actions: ['deposit', 'withdraw', 'loan', 'repay'], desc: '金库大门紧闭，柜员面带微笑。' },
  { id: 'stockExchange', name: '股票交易所', aliases: ['交易所', '证券公司'], district: 'financial', openHours: [9, 15], actions: ['buyStock', 'sellStock'], desc: '大屏上红绿数字跳动，财富在流转。' },
  { id: 'supermarket', name: '超市', aliases: ['大卖场'], district: 'residential', openHours: [8, 22], actions: ['buy'], shop: 'supermarket', desc: '货架琳琅满目，生活必需品一应俱全。' },
  { id: 'convenience', name: '便利店', aliases: ['小卖部', '24小时店'], district: 'residential', openHours: [0, 24], actions: ['buy'], shop: 'convenience', desc: '深夜的一盏灯，随时为你敞开。' },
  { id: 'mall', name: '商场', aliases: ['购物中心', '百货'], district: 'downtown', openHours: [10, 22], actions: ['buy'], shop: 'mall', desc: '名牌橱窗闪闪发光。' },
  { id: 'restaurant', name: '餐厅', aliases: ['饭店', '酒楼'], district: 'downtown', openHours: [10, 21], actions: ['eat', 'treat'], shop: 'restaurant', desc: ' 服务生热情地招呼着客人。' },
  { id: 'fastFood', name: '快餐店', aliases: ['快餐'], district: 'downtown', openHours: [7, 22], actions: ['eat'], shop: 'fastFood', desc: '出餐快，价格实惠。' },
  { id: 'cafe', name: '咖啡馆', aliases: ['咖啡店', '咖啡厅'], district: 'downtown', openHours: [9, 22], actions: ['eat', 'chat'], shop: 'cafe', desc: '醇香咖啡配一段悠闲时光。' },
  { id: 'nightMarket', name: '夜市', aliases: ['夜市街', '大排档'], district: 'leisure', openHours: [17, 24], actions: ['eat', 'buy', 'stroll'], shop: 'nightMarket', desc: '烟火气升腾，烤串滋滋作响。' },
  { id: 'park', name: '公园', aliases: ['市民公园'], district: 'leisure', openHours: [5, 23], actions: ['stroll', 'exercise', 'chat'], desc: '湖水倒映着树影，晨练的老人打着太极。' },
  { id: 'gym', name: '健身房', aliases: ['健身馆', '体育馆'], district: 'leisure', openHours: [6, 23], actions: ['exercise'], desc: '铁与汗的交响。' },
  { id: 'netbar', name: '网吧', aliases: ['网咖', '电竞馆'], district: 'leisure', openHours: [0, 24], actions: ['surf'], desc: '键盘声噼啪作响，屏幕荧光闪烁。' },
  { id: 'cinema', name: '电影院', aliases: ['影院', '影城'], district: 'leisure', openHours: [10, 23], actions: ['watchMovie'], desc: '巨幕上正在上演悲欢离合。' },
  { id: 'ktv', name: 'KTV', aliases: ['歌厅', '练歌房'], district: 'leisure', openHours: [12, 24], actions: ['sing'], desc: '话筒递过来，唱出喜怒哀乐。' },
  { id: 'scenicArea', name: '郊外景区', aliases: ['景区', '风景区'], district: 'suburb', openHours: [6, 19], actions: ['stroll', 'travel'], desc: '山清水秀，鸟鸣山幽。' },
  { id: 'station', name: '车站', aliases: ['公交站', '汽车站'], district: 'downtown', openHours: [5, 23], actions: ['bus'], desc: '班车来往，人流如织。' },
  { id: 'gasStation', name: '加油站', aliases: ['油站'], district: 'suburb', openHours: [0, 24], actions: ['refuel'], desc: '为爱车补充能量。' },
  { id: 'carDealer', name: '车行', aliases: ['汽车城', '4S店'], district: 'suburb', openHours: [9, 20], actions: ['buy'], shop: 'carDealer', desc: '锃亮的轿车一字排开。' },
  { id: 'police', name: '警察局', aliases: ['警局', '派出所'], district: 'downtown', openHours: [0, 24], actions: ['surrender'], desc: '法网恢恢，疏而不漏。' },
  { id: 'lottery', name: '彩票站', aliases: ['福彩', '彩票店'], district: 'residential', openHours: [8, 21], actions: ['buyLottery'], desc: '每张彩票都藏着一个发财梦。' },
  { id: 'travelAgency', name: '旅行社', aliases: ['旅游公司'], district: 'downtown', openHours: [9, 19], actions: ['travel'], desc: '世界那么大，去看看。' },
  { id: 'marriageRegistry', name: '民政局', aliases: ['婚姻登记处'], district: 'downtown', openHours: [9, 17], actions: ['marry', 'divorce'], desc: '红本本与绿本本，人生大事在此定格。' },
  { id: 'jail', name: '监狱', aliases: ['看守所'], district: 'suburb', openHours: [0, 24], actions: ['sleep', 'reflect'], desc: '高墙铁窗，悔恨与反思之地。' },
]

export const LOCATION_INDEX = new Map(LOCATIONS.map((l) => [l.id, l]))
export const LOCATION_BY_NAME = new Map<string, LocationDef>()
for (const loc of LOCATIONS) {
  LOCATION_BY_NAME.set(loc.name, loc)
  for (const a of loc.aliases) LOCATION_BY_NAME.set(a, loc)
}

export const DISTRICT_NAMES: Record<string, string> = {
  residential: '住宅区',
  downtown: '市中心',
  education: '文教区',
  medical: '医疗区',
  financial: '金融区',
  leisure: '休闲区',
  suburb: '郊区',
  special: '特殊',
}

/** Approximate travel minutes between districts on foot. */
export const DISTRICT_DISTANCE: Record<string, number> = {
  residential: 0,
  downtown: 20,
  education: 25,
  medical: 25,
  financial: 30,
  leisure: 20,
  suburb: 45,
  special: 10,
}
