import type { EventEffect } from '../engine/state'

export interface GameEventDef {
  id: string
  category: 'chance' | 'accident' | 'social' | 'choice'
  weight: number
  text: string
  options?: { label: string; outcomeText: string; effects: EventEffect[] }[]
  effects?: EventEffect[]
}

const ATTR_KEYS = ['health', 'stamina', 'mood', 'intellect', 'charm', 'satiety', 'hygiene']

const A = (kind: string, value: number, target?: string): EventEffect => {
  if (ATTR_KEYS.includes(kind)) {
    return { kind: 'attrs', value, target: kind }
  }
  return { kind: kind as EventEffect['kind'], value, target }
}

export const EVENTS: GameEventDef[] = [
  // ============ 机遇 chance ============
  { id: 'ev_wallet', category: 'chance', weight: 6, text: '你在路边捡到一个钱包，里面有不少现金。', options: [
    { label: '交给警察', outcomeText: '你把钱包交到警察局，失主送来一面锦旗，你的名声变好了。', effects: [A('reputation', 5), A('mood', 5)] },
    { label: '收进自己口袋', outcomeText: '你左右看了看，把现金收进了口袋，心里却有点发虚。', effects: [A('money', 500), A('reputation', -5)] },
  ]},
  { id: 'ev_perform', category: 'chance', weight: 5, text: '街头艺人邀请你即兴表演一段，围观人群渐渐聚拢。', effects: [A('money', 120), A('mood', 6)] },
  { id: 'ev_oldstuff', category: 'chance', weight: 5, text: '整理旧物时，你翻出一件老物件，竟被收藏者看中了。', effects: [A('money', 800)] },
  { id: 'ev_alumni', category: 'chance', weight: 6, text: '你在街上偶遇多年未见的老同学，相谈甚欢。', effects: [A('mood', 8)] },
  { id: 'ev_helpHand', category: 'chance', weight: 6, text: '一位迷路老人向你求助，你送他到了目的地。', effects: [A('reputation', 4), A('mood', 4)] },
  { id: 'ev_bonus', category: 'chance', weight: 5, text: '公司季度业绩超预期，管理层决定发放特别奖金。', effects: [A('money', 2000), A('mood', 5)] },
  { id: 'ev_sale', category: 'chance', weight: 6, text: '商场周年庆，全场限时打折，你趁便宜囤了些好物。', effects: [A('mood', 5), A('money', -200)] },
  { id: 'ev_luckyDraw', category: 'chance', weight: 5, text: '超市小票抽奖，你抽中了一箱牛奶。', effects: [A('mood', 3)] },
  { id: 'ev_viral', category: 'chance', weight: 3, text: '你随手发的动态意外走红，点赞破万。', effects: [A('mood', 10), A('money', 300)] },
  { id: 'ev_foundMoney', category: 'chance', weight: 4, text: 'ATM 机旁散落着几张钞票，你环顾四周无人。', effects: [A('money', 200)] },
  { id: 'ev_freeMeal', category: 'chance', weight: 5, text: '餐厅老板心情好，给你的菜多加了一份。', effects: [A('satiety', 15), A('mood', 4)] },
  { id: 'ev_jobTip', category: 'chance', weight: 4, text: '一位好心人告诉你某公司在招人，待遇不错。', effects: [A('mood', 3)] },
  { id: 'ev_taxiFree', category: 'chance', weight: 4, text: '出租车司机认错了老顾客，这趟车费免了。', effects: [A('money', 30)] },
  { id: 'ev_winSmall', category: 'chance', weight: 4, text: '你随手刮了张刮刮乐，中了小奖。', effects: [A('money', 100), A('mood', 3)] },
  { id: 'ev_techPrize', category: 'chance', weight: 2, text: '你参加线上答题活动，凭知识拿了奖金。', effects: [A('money', 500), A('mood', 4)] },
  { id: 'ev_recycle', category: 'chance', weight: 5, text: '你把攒下的废品拿去回收站，换了顿早饭钱。', effects: [A('money', 45), A('hygiene', -3)] },
  { id: 'ev_mentor', category: 'chance', weight: 3, text: '一位前辈看你有潜力，免费指点了你一番。', effects: [A('intellect', 2), A('mood', 4)] },
  { id: 'ev_donation', category: 'chance', weight: 3, text: '你参加了一场公益义卖，收获满满成就感。', effects: [A('reputation', 6), A('mood', 6), A('money', -100)] },
  { id: 'ev_stocksTip', category: 'chance', weight: 3, text: '股友私聊你一条小道消息，你半信半疑。', options: [
    { label: '跟一把', outcomeText: '你跟了小仓位，居然小赚一笔。', effects: [A('money', 600), A('mood', 4)] },
    { label: '不理会', outcomeText: '你明智地没搭理小道消息，安心吃饭。', effects: [] },
  ]},
  { id: 'ev_gymFree', category: 'chance', weight: 4, text: '健身房搞体验活动，你免费练了一次。', effects: [A('stamina', -5), A('health', 3), A('mood', 3)] },
  // ============ 意外 accident ============
  { id: 'ev_cold', category: 'accident', weight: 6, text: '天气多变，你不小心着凉感冒了。', effects: [A('health', -10), A('mood', -5)] },
  { id: 'ev_stomach', category: 'accident', weight: 5, text: '昨晚的外卖似乎不太新鲜，你跑了一晚上厕所。', effects: [A('health', -8), A('stamina', -8)] },
  { id: 'ev_sprain', category: 'accident', weight: 4, text: '下楼梯时你踩空一步，脚踝扭了一下。', effects: [A('health', -6), A('stamina', -5)] },
  { id: 'ev_phoneStolen', category: 'accident', weight: 3, text: '公交车上人多手杂，你的手机被摸走了。', effects: [A('money', -3500), A('mood', -12)] },
  { id: 'ev_soaked', category: 'accident', weight: 6, text: '突降暴雨，你被淋成了落汤鸡。', effects: [A('health', -5), A('hygiene', -10), A('mood', -4)] },
  { id: 'ev_noise', category: 'accident', weight: 5, text: '隔壁装修电钻声不断，你一夜没睡好。', effects: [A('stamina', -10), A('mood', -6)] },
  { id: 'ev_flatTire', category: 'accident', weight: 3, text: '你的车在半路爆了胎，修理费不菲。', effects: [A('money', -300), A('mood', -4)] },
  { id: 'ev_elevator', category: 'accident', weight: 4, text: '电梯故障，你在里面被困了半小时。', effects: [A('mood', -6), A('stamina', -5)] },
  { id: 'ev_scam', category: 'accident', weight: 3, text: '一个"中奖电话"骗走了你几百块话费充值。', effects: [A('money', -200), A('mood', -8)] },
  { id: 'ev_lostWallet', category: 'accident', weight: 4, text: '你摸遍全身，发现钱包不见了。', effects: [A('money', -300), A('mood', -8)] },
  { id: 'ev_burn', category: 'accident', weight: 4, text: '做饭时热油溅到了手背，烫出一小块红。', effects: [A('health', -4), A('mood', -3)] },
  { id: 'ev_allergy', category: 'accident', weight: 3, text: '不知吃了什么，你起了一身红疹。', effects: [A('health', -7), A('charm', -3), A('mood', -5)] },
  { id: 'ev_insomnia', category: 'accident', weight: 5, text: '你毫无缘由地失眠到凌晨三点。', effects: [A('stamina', -12), A('mood', -5)] },
  { id: 'ev_fallBike', category: 'accident', weight: 4, text: '骑车下坡时你摔了一跤，膝盖蹭破了皮。', effects: [A('health', -5), A('hygiene', -5)] },
  { id: 'ev_dataLost', category: 'accident', weight: 3, text: '电脑突然蓝屏，你没保存的文件全没了。', effects: [A('mood', -10), A('stamina', -5)] },
  { id: 'ev_feeUp', category: 'accident', weight: 4, text: '房东发来通知：水电网费涨价了。', effects: [A('money', -150), A('mood', -3)] },
  { id: 'ev_spill', category: 'accident', weight: 5, text: '你端着的咖啡洒在了衬衫上，只能回家换衣服。', effects: [A('mood', -4), A('hygiene', -5)] },
  { id: 'ev_toothache', category: 'accident', weight: 4, text: '半夜牙疼得厉害，看来要去看牙医了。', effects: [A('health', -6), A('mood', -6), A('money', -400)] },
  { id: 'ev_queue', category: 'accident', weight: 5, text: '银行排号排队两小时，业务五分钟办完。', effects: [A('stamina', -8), A('mood', -5)] },
  { id: 'ev_sprainedWrist', category: 'accident', weight: 3, text: '搬重物时你闪了手腕，肿了好几天。', effects: [A('health', -5), A('stamina', -6)] },
  // ============ 社会 social ============
  { id: 'ev_priceUp', category: 'social', weight: 6, text: '受市场波动影响，食品价格普遍上涨。', effects: [A('marketFactor', 0.05, 'food')] },
  { id: 'ev_priceDown', category: 'social', weight: 6, text: '应季果蔬大丰收，菜价回落。', effects: [A('marketFactor', -0.05, 'food')] },
  { id: 'ev_festival', category: 'social', weight: 5, text: '节日临近，街上张灯结彩，家家备礼。', effects: [A('mood', 6), A('marketFactor', 0.04, 'luxury')] },
  { id: 'ev_marathon', category: 'social', weight: 4, text: '城市马拉松开跑，你围观了热闹的赛事。', effects: [A('mood', 5)] },
  { id: 'ev_blackout', category: 'social', weight: 4, text: '片区电路检修，傍晚停了几小时电。', effects: [A('mood', -4)] },
  { id: 'ev_memeHot', category: 'social', weight: 5, text: '一个网络热梗刷屏全网，大家都在玩梗。', effects: [A('mood', 4)] },
  { id: 'ev_newMall', category: 'social', weight: 4, text: '新商场开业，人潮涌动，优惠多多。', effects: [A('mood', 5), A('marketFactor', -0.03, 'clothes')] },
  { id: 'ev_houseCool', category: 'social', weight: 4, text: '楼市降温，房价指数小幅回落。', effects: [A('marketFactor', -0.02, 'property')] },
  { id: 'ev_houseHot', category: 'social', weight: 4, text: '学区房 concept 再起，房价指数上扬。', effects: [A('marketFactor', 0.02, 'property')] },
  { id: 'ev_gasUp', category: 'social', weight: 4, text: '国际油价上涨，加油站价格牌换了数字。', effects: [A('marketFactor', 0.05, 'vehicle')] },
  { id: 'ev_fluSeason', category: 'social', weight: 4, text: '流感高发季，医院排起长队。', effects: [A('marketFactor', 0.06, 'medicine')] },
  { id: 'ev_community', category: 'social', weight: 5, text: '社区组织义务清扫，你也搭了把手。', effects: [A('reputation', 4), A('stamina', -5)] },
  { id: 'ev_bookFair', category: 'social', weight: 4, text: '书展来啦，书店全场八折。', effects: [A('marketFactor', -0.1, 'tool'), A('mood', 3)] },
  { id: 'ev_economy', category: 'social', weight: 3, text: '宏观经济数据向好，市场信心提振。', effects: [A('marketFactor', 0.02, 'food'), A('marketFactor', 0.02, 'luxury')] },
  { id: 'ev_rainWeek', category: 'social', weight: 4, text: '连日阴雨，外卖和骑手都忙疯了。', effects: [A('mood', -3)] },
  { id: 'ev_heatWavePub', category: 'social', weight: 3, text: '高温红色预警发布，户外工作尽量避免。', effects: [A('mood', -3)] },
  { id: 'ev_typhoon', category: 'social', weight: 3, text: '台风过境，全城戒备，你囤了些物资。', effects: [A('money', -100), A('marketFactor', 0.06, 'food')] },
  { id: 'ev_concert', category: 'social', weight: 4, text: '知名歌手来开演唱会，一票难求。', effects: [A('mood', 3)] },
  { id: 'ev_jobFair', category: 'social', weight: 4, text: '人才市场举办大型招聘会，人头攒动。', effects: [A('mood', 2)] },
  { id: 'ev_marketPanic', category: 'social', weight: 3, text: '国际市场震荡，股民人心惶惶。', effects: [A('marketFactor', 0.01, 'food')] },
  // ============ 选择 choice ============
  { id: 'ev_coworker', category: 'choice', weight: 6, text: '同事拜托你帮忙分担一部分工作，你自己的活还没干完。', options: [
    { label: '帮', outcomeText: '你帮同事扛下了任务，两人关系更近了，自己却熬到深夜。', effects: [A('relationship', 8, 'random'), A('stamina', -10)] },
    { label: '婉拒', outcomeText: '你婉拒了请求，同事虽然理解，但气氛微妙了一瞬。', effects: [A('relationship', -3, 'random')] },
  ]},
  { id: 'ev_beggar', category: 'choice', weight: 6, text: '街角一位衣衫褴褛的人向你伸手求助。', options: [
    { label: '给钱', outcomeText: '你递过一张钞票，对方连声道谢，你心里一暖。', effects: [A('money', -20), A('mood', 4), A('reputation', 2)] },
    { label: '走开', outcomeText: '你低头快步走开，心里有点不是滋味。', effects: [A('mood', -2)] },
  ]},
  { id: 'ev_overtimeAsk', category: 'choice', weight: 6, text: '主管问你是否愿意今晚留下来加班，有加班费。', options: [
    { label: '加班', outcomeText: '你留到深夜，拿到了加班费，也累得够呛。', effects: [A('money', 200), A('stamina', -15), A('mood', -4)] },
    { label: '回家', outcomeText: '你准点下班，享受了难得的夜晚。', effects: [A('mood', 3), A('reputation', -1)] },
  ]},
  { id: 'ev_cheapGoods', category: 'choice', weight: 5, text: '路边摊号称"祖传名表"只卖 200 元，围观者不少。', options: [
    { label: '买', outcomeText: '表用了三天就停了，果然是假货。', effects: [A('money', -200), A('mood', -6)] },
    { label: '不买', outcomeText: '你摇摇头走开，骗局与你无关。', effects: [] },
  ]},
  { id: 'ev_oldFriend', category: 'choice', weight: 5, text: '老同学约你周末聚会，但你想用周末充电学习。', options: [
    { label: '赴约', outcomeText: '聚会尽兴而归，友情升温，钱包却瘪了点。', effects: [A('relationship', 8, 'random'), A('money', -150), A('mood', 6)] },
    { label: '学习', outcomeText: '你婉拒聚会，安静地学了一天，收获扎实。', effects: [A('intellect', 1), A('relationship', -2, 'random')] },
  ]},
  { id: 'ev_strayCat', category: 'choice', weight: 5, text: '一只流浪猫在你家楼下蹭裤腿，喵喵直叫。', options: [
    { label: '收养', outcomeText: '你把小猫抱回了家，从此多了个毛茸茸的室友。', effects: [A('item', 1, 'lux_cat'), A('money', -100)] },
    { label: '投喂后离开', outcomeText: '你买了根火腿肠喂它，然后去赶地铁了。', effects: [A('money', -5), A('mood', 2)] },
  ]},
  { id: 'ev_insurance', category: 'choice', weight: 5, text: '保险推销员滔滔不绝，推荐一份年缴保单。', options: [
    { label: '投保', outcomeText: '你签了保单，图个心安。', effects: [A('money', -1000)] },
    { label: '拒绝', outcomeText: '你说"再考虑考虑"，脱身离开。', effects: [] },
  ]},
  { id: 'ev_classReunion', category: 'choice', weight: 4, text: '班级群里组织毕业十周年聚会，AA 制每人 500。', options: [
    { label: '参加', outcomeText: '推杯换盏间，往事如昨，人脉也宽了些。', effects: [A('money', -500), A('relationship', 10, 'random'), A('mood', 6)] },
    { label: '潜水', outcomeText: '你默默退出了群聊置顶，继续过自己的日子。', effects: [A('mood', -2)] },
  ]},
  { id: 'ev_lotteryDream', category: 'choice', weight: 5, text: '昨晚你梦见一组彩票号码，醒来还记得清清楚楚。', options: [
    { label: '买它', outcomeText: '你买了两注，结果只中了 5 块钱。', effects: [A('money', -15), A('mood', 1)] },
    { label: '算了', outcomeText: '梦终究是梦，你洗把脸去上班。', effects: [] },
  ]},
  { id: 'ev_concert2', category: 'choice', weight: 4, text: '黄牛手里有你心心念念的演唱会门票，但价格翻了三倍。', options: [
    { label: '咬咬牙买', outcomeText: '演唱会很燃，钱包在滴血。', effects: [A('money', -1200), A('mood', 12)] },
    { label: '算了', outcomeText: '你选择了等待下次巡演。', effects: [A('mood', -2)] },
  ]},
  { id: 'ev_gymCoach', category: 'choice', weight: 5, text: '健身房教练极力推荐私教课，十节只要 2000。', options: [
    { label: '买课', outcomeText: '私教带练效果拔群，肌肉酸痛但值。', effects: [A('money', -2000), A('health', 8), A('charm', 2)] },
    { label: '自己练', outcomeText: '你按自己节奏训练，省了钱。', effects: [A('health', 2)] },
  ]},
  { id: 'ev_borrowMoney', category: 'choice', weight: 5, text: '一位关系不错的朋友开口借 1000 块救急。', options: [
    { label: '借', outcomeText: '你转了账，朋友感激涕零。', effects: [A('money', -1000), A('relationship', 10, 'random')] },
    { label: '拒绝', outcomeText: '你为难地拒绝了，友谊出现了一道细缝。', effects: [A('relationship', -8, 'random'), A('mood', -3)] },
  ]},
  { id: 'ev_foundJob', category: 'choice', weight: 4, text: '猎头联系你：有家公司想挖你，薪资涨三成，但压力更大。', options: [
    { label: '跳槽', outcomeText: '你选择拥抱变化，新平台风高浪急。', effects: [A('money', 500), A('reputation', 3), A('mood', 5)] },
    { label: '留守', outcomeText: '你婉拒了邀约，稳字当头。', effects: [A('relationship', 4, 'random')] },
  ]},
  { id: 'ev_earlyBird', category: 'choice', weight: 5, text: '你醒了，比闹钟早了一个小时。', options: [
    { label: '起床学习', outcomeText: '清晨的大脑最好用，你学进去了不少。', effects: [A('intellect', 1), A('stamina', -3)] },
    { label: '回笼觉', outcomeText: '被窝真舒服啊……你又睡了过去。', effects: [A('mood', 3)] },
  ]},
  { id: 'ev_luckySeat', category: 'choice', weight: 4, text: '公交车上，一位老人站在你座位旁。', options: [
    { label: '让座', outcomeText: '老人连声道谢，全车人向你投来赞许目光。', effects: [A('reputation', 3), A('mood', 3), A('stamina', -3)] },
    { label: '装睡', outcomeText: '你闭眼装睡到站，心里有点过意不去。', effects: [A('mood', -2)] },
  ]},
  { id: 'ev_freeClass', category: 'choice', weight: 4, text: '美术馆举办免费大师讲座，名额有限。', options: [
    { label: '参加', outcomeText: '讲座精彩，你对艺术的理解更深了。', effects: [A('intellect', 1), A('mood', 4)] },
    { label: '错过', outcomeText: '你忙别的去了，与讲座擦肩而过。', effects: [] },
  ]},
  { id: 'ev_nightSnack', category: 'choice', weight: 6, text: '深夜，手机里的炸鸡图片勾起了你的食欲。', options: [
    { label: '点外卖', outcomeText: '深夜的炸鸡格外香，热量也格外真。', effects: [A('money', -30), A('satiety', 20), A('mood', 5), A('health', -2)] },
    { label: '忍住', outcomeText: '你喝了杯水，骄傲地睡了。', effects: [A('satiety', -3)] },
  ]},
  { id: 'ev_ipo', category: 'choice', weight: 3, text: '一家新股上市，首日预计大涨，朋友劝你打新。', options: [
    { label: '打新', outcomeText: '你中签了！首日上涨，小赚一笔。', effects: [A('money', 800), A('mood', 5)] },
    { label: '观望', outcomeText: '你看不懂新股，选择观望。', effects: [] },
  ]},
  { id: 'ev_raise', category: 'choice', weight: 4, text: '绩效面谈中，主管暗示你可以主动谈谈加薪。', options: [
    { label: '开口', outcomeText: '你据理力争，加薪谈判成功一半。', effects: [A('money', 800), A('reputation', 2), A('stamina', -5)] },
    { label: '沉默', outcomeText: '你把话咽了回去，一切照旧。', effects: [A('mood', -3)] },
  ]},
  { id: 'ev_volunteer', category: 'choice', weight: 4, text: '社区招募周末敬老院志愿者。', options: [
    { label: '报名', outcomeText: '你陪老人们聊了一天，收获了满满的感谢。', effects: [A('reputation', 8), A('mood', 6), A('stamina', -8)] },
    { label: '下次吧', outcomeText: '你想了想，决定下次再说。', effects: [] },
  ]},
  { id: 'ev_luckyCoin', category: 'choice', weight: 5, text: '喷泉池边，传说投硬币许愿很灵。', options: [
    { label: '投一枚', outcomeText: '硬币划出弧线落进池底，你许了个小愿。', effects: [A('money', -1), A('mood', 4)] },
    { label: '离开', outcomeText: '你笑了笑容话，转身离开。', effects: [] },
  ]},
  { id: 'ev_deliveryBonus', category: 'chance', weight: 4, text: '外卖平台发补贴，你这单少付了几块钱。', effects: [A('money', 8), A('mood', 2)] },
  { id: 'ev_clothesGift', category: 'chance', weight: 4, text: '亲戚寄来一箱旧衣服，里面竟有件全新大牌。', effects: [A('mood', 5), A('charm', 2)] },
  { id: 'ev_haircut', category: 'chance', weight: 4, text: '理发师今天状态神勇，发型帅出新高度。', effects: [A('charm', 3), A('mood', 4)] },
  { id: 'ev_wifiFree', category: 'chance', weight: 5, text: '邻居慷慨地共享了 WiFi，网速起飞。', effects: [A('mood', 3)] },
  { id: 'ev_parkingLuck', category: 'chance', weight: 4, text: '你在商圈转了三圈，居然撞见一个空车位。', effects: [A('mood', 3)] },
  { id: 'ev_birdPoop', category: 'accident', weight: 4, text: '一只鸟精准地"光顾"了你刚洗的外套。', effects: [A('mood', -5), A('hygiene', -8)] },
  { id: 'ev_keysLocked', category: 'accident', weight: 4, text: '你把自己锁在了门外，只好请开锁师傅。', effects: [A('money', -150), A('mood', -5)] },
  { id: 'ev_wetPhone', category: 'accident', weight: 3, text: '手机掉进了水盆，维修费肉疼。', effects: [A('money', -500), A('mood', -8)] },
  { id: 'ev_neighborParty', category: 'social', weight: 4, text: '邻居办乔迁宴，整层楼都收到了请柬。', effects: [A('mood', 5)] },
  { id: 'ev_discountFuel', category: 'social', weight: 4, text: '加油站会员日，油价直降。', effects: [A('marketFactor', -0.04, 'vehicle')] },
  { id: 'ev_sportEvent', category: 'social', weight: 4, text: '市体育馆举办篮球联赛决赛，气氛火爆。', effects: [A('mood', 4)] },
  { id: 'ev_gala', category: 'social', weight: 4, text: '跨年晚会将至，全城洋溢着节日的气氛。', effects: [A('mood', 6)] },
  { id: 'ev_examSeason', category: 'social', weight: 4, text: '考试季来临，图书馆一座难求。', effects: [A('mood', -2)] },
  { id: 'ev_oldFlim', category: 'social', weight: 4, text: '老电影重映，影迷们排队怀旧。', effects: [A('mood', 4)] },
]
