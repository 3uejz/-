class_name EntertainmentSystem
extends RefCounted
## 娱乐与兴趣圈层（R54.1–R54.3、R54.7；design D14）。
##
## 123 种娱乐，覆盖居家、户外、文化、竞技、夜生活、收藏、极限七类；每种定义
## 费用、耗时、属性/技能要求、心情与健康效果、重复衰减与上瘾风险；兴趣形成同好
## 圈层并可发展为副业；过度娱乐导致负债或上瘾。

const BaselineScript = preload("res://sim/baseline.gd")

const CATEGORIES: Array = ["home", "outdoor", "culture", "sports", "nightlife", "collect", "extreme"]
const CATEGORY_NAMES: Dictionary = {
	"home": "居家", "outdoor": "户外", "culture": "文化", "sports": "竞技",
	"nightlife": "夜生活", "collect": "收藏", "extreme": "极限",
}

## 娱乐活动（fee 最小货币单位；minutes 耗时；mood/health 效果；skill 需求等级；addiction 上瘾系数）。
const ACTIVITIES: Dictionary = {
	# 居家
	"video_game": {"name": "电子游戏", "category": "home", "fee": 0, "minutes": 120, "mood": 6.0, "health": -1.0, "skill": "", "addiction": 0.06},
	"binge_watch": {"name": "追剧", "category": "home", "fee": 0, "minutes": 180, "mood": 5.0, "health": -0.5, "skill": "", "addiction": 0.05},
	"cooking": {"name": "烹饪", "category": "home", "fee": 3000, "minutes": 90, "mood": 4.0, "health": 1.0, "skill": "cooking", "addiction": 0.01},
	"gardening": {"name": "园艺", "category": "home", "fee": 2000, "minutes": 120, "mood": 4.0, "health": 1.0, "skill": "", "addiction": 0.01},
	"pet_play": {"name": "宠物互动", "category": "home", "fee": 0, "minutes": 60, "mood": 5.0, "health": 0.5, "skill": "", "addiction": 0.01},
	"tea_ceremony": {"name": "泡茶", "category": "home", "fee": 1000, "minutes": 45, "mood": 3.0, "health": 0.5, "skill": "", "addiction": 0.01},
	"calligraphy": {"name": "书法", "category": "home", "fee": 500, "minutes": 60, "mood": 3.0, "health": 0.5, "skill": "art", "addiction": 0.01},
	"jigsaw": {"name": "拼图", "category": "home", "fee": 500, "minutes": 120, "mood": 3.0, "health": 0.0, "skill": "", "addiction": 0.02},
	"board_game": {"name": "棋盘游戏", "category": "home", "fee": 1000, "minutes": 90, "mood": 4.0, "health": 0.0, "skill": "", "addiction": 0.02},
	"home_karaoke": {"name": "家庭K歌", "category": "home", "fee": 0, "minutes": 90, "mood": 5.0, "health": 0.0, "skill": "", "addiction": 0.02},
	"handcraft": {"name": "手工", "category": "home", "fee": 1500, "minutes": 120, "mood": 3.0, "health": 0.5, "skill": "", "addiction": 0.01},
	"read_novel": {"name": "阅读小说", "category": "home", "fee": 500, "minutes": 90, "mood": 4.0, "health": 0.5, "skill": "", "addiction": 0.02},
	"listen_music": {"name": "听音乐", "category": "home", "fee": 0, "minutes": 60, "mood": 4.0, "health": 0.0, "skill": "", "addiction": 0.02},
	"baking": {"name": "烘焙", "category": "home", "fee": 3000, "minutes": 120, "mood": 4.0, "health": 0.5, "skill": "cooking", "addiction": 0.02},
	"organizing": {"name": "收纳整理", "category": "home", "fee": 0, "minutes": 90, "mood": 3.0, "health": 1.0, "skill": "", "addiction": 0.0},
	"mahjong": {"name": "打麻将", "category": "home", "fee": 2000, "minutes": 180, "mood": 5.0, "health": -0.5, "skill": "", "addiction": 0.05},
	"chess": {"name": "下棋", "category": "home", "fee": 0, "minutes": 90, "mood": 3.0, "health": 0.0, "skill": "", "addiction": 0.02},
	"lego": {"name": "拼乐高", "category": "home", "fee": 5000, "minutes": 180, "mood": 4.0, "health": 0.0, "skill": "", "addiction": 0.01},
	"woodwork": {"name": "做木工", "category": "home", "fee": 4000, "minutes": 180, "mood": 4.0, "health": 1.0, "skill": "", "addiction": 0.01},
	"stargazing": {"name": "观星", "category": "home", "fee": 0, "minutes": 90, "mood": 5.0, "health": 0.5, "skill": "", "addiction": 0.01},
	# 户外
	"hiking": {"name": "徒步", "category": "outdoor", "fee": 2000, "minutes": 300, "mood": 7.0, "health": 5.0, "skill": "fitness", "addiction": 0.01},
	"camping": {"name": "露营", "category": "outdoor", "fee": 8000, "minutes": 720, "mood": 8.0, "health": 3.0, "skill": "", "addiction": 0.01},
	"fishing": {"name": "钓鱼", "category": "outdoor", "fee": 3000, "minutes": 240, "mood": 6.0, "health": 1.0, "skill": "", "addiction": 0.02},
	"skiing": {"name": "滑雪", "category": "outdoor", "fee": 30000, "minutes": 360, "mood": 8.0, "health": 3.0, "skill": "fitness", "addiction": 0.02},
	"diving": {"name": "潜水", "category": "outdoor", "fee": 50000, "minutes": 300, "mood": 8.0, "health": 2.0, "skill": "fitness", "addiction": 0.02},
	"mountaineering": {"name": "登山", "category": "outdoor", "fee": 20000, "minutes": 600, "mood": 9.0, "health": 5.0, "skill": "fitness", "addiction": 0.01},
	"cycling": {"name": "骑行", "category": "outdoor", "fee": 0, "minutes": 180, "mood": 6.0, "health": 5.0, "skill": "fitness", "addiction": 0.01},
	"running": {"name": "跑步", "category": "outdoor", "fee": 0, "minutes": 60, "mood": 5.0, "health": 5.0, "skill": "fitness", "addiction": 0.02},
	"picnic": {"name": "野餐", "category": "outdoor", "fee": 5000, "minutes": 240, "mood": 6.0, "health": 1.0, "skill": "", "addiction": 0.01},
	"birdwatching": {"name": "观鸟", "category": "outdoor", "fee": 1000, "minutes": 180, "mood": 5.0, "health": 1.0, "skill": "", "addiction": 0.01},
	"boating": {"name": "划船", "category": "outdoor", "fee": 10000, "minutes": 180, "mood": 6.0, "health": 3.0, "skill": "", "addiction": 0.01},
	"horse_riding": {"name": "骑马", "category": "outdoor", "fee": 40000, "minutes": 180, "mood": 7.0, "health": 3.0, "skill": "", "addiction": 0.02},
	"mushroom_picking": {"name": "采蘑菇", "category": "outdoor", "fee": 0, "minutes": 240, "mood": 5.0, "health": 2.0, "skill": "", "addiction": 0.01},
	"photography": {"name": "摄影", "category": "outdoor", "fee": 5000, "minutes": 180, "mood": 5.0, "health": 1.0, "skill": "art", "addiction": 0.02},
	"hot_spring": {"name": "温泉", "category": "outdoor", "fee": 20000, "minutes": 240, "mood": 7.0, "health": 3.0, "skill": "", "addiction": 0.01},
	"fruit_picking": {"name": "采摘", "category": "outdoor", "fee": 6000, "minutes": 180, "mood": 5.0, "health": 1.0, "skill": "", "addiction": 0.01},
	"skateboarding": {"name": "滑板", "category": "outdoor", "fee": 3000, "minutes": 120, "mood": 6.0, "health": 2.0, "skill": "fitness", "addiction": 0.02},
	"kite": {"name": "放风筝", "category": "outdoor", "fee": 1000, "minutes": 120, "mood": 5.0, "health": 1.0, "skill": "", "addiction": 0.01},
	"grass_skiing": {"name": "滑草", "category": "outdoor", "fee": 8000, "minutes": 180, "mood": 6.0, "health": 2.0, "skill": "", "addiction": 0.01},
	"trail_running": {"name": "越野跑", "category": "outdoor", "fee": 0, "minutes": 180, "mood": 6.0, "health": 6.0, "skill": "fitness", "addiction": 0.02},
	# 文化
	"exhibition": {"name": "看展览", "category": "culture", "fee": 8000, "minutes": 180, "mood": 6.0, "health": 0.5, "skill": "", "addiction": 0.01},
	"concert": {"name": "听音乐会", "category": "culture", "fee": 30000, "minutes": 180, "mood": 8.0, "health": 0.5, "skill": "", "addiction": 0.02},
	"theater": {"name": "看话剧", "category": "culture", "fee": 20000, "minutes": 180, "mood": 7.0, "health": 0.0, "skill": "", "addiction": 0.01},
	"cinema": {"name": "看电影", "category": "culture", "fee": 5000, "minutes": 150, "mood": 5.0, "health": 0.0, "skill": "", "addiction": 0.02},
	"reading": {"name": "读书", "category": "culture", "fee": 1000, "minutes": 120, "mood": 4.0, "health": 1.0, "skill": "", "addiction": 0.01},
	"museum": {"name": "逛博物馆", "category": "culture", "fee": 6000, "minutes": 180, "mood": 6.0, "health": 1.0, "skill": "", "addiction": 0.01},
	"opera": {"name": "看歌剧", "category": "culture", "fee": 50000, "minutes": 180, "mood": 7.0, "health": 0.0, "skill": "", "addiction": 0.01},
	"historic_site": {"name": "参观古迹", "category": "culture", "fee": 10000, "minutes": 240, "mood": 6.0, "health": 2.0, "skill": "", "addiction": 0.01},
	"lecture": {"name": "听讲座", "category": "culture", "fee": 3000, "minutes": 120, "mood": 4.0, "health": 0.5, "skill": "", "addiction": 0.01},
	"book_club": {"name": "参加读书会", "category": "culture", "fee": 2000, "minutes": 120, "mood": 5.0, "health": 0.5, "skill": "", "addiction": 0.01},
	"dance_show": {"name": "看舞蹈", "category": "culture", "fee": 20000, "minutes": 150, "mood": 6.0, "health": 0.0, "skill": "", "addiction": 0.01},
	"crosstalk": {"name": "看相声", "category": "culture", "fee": 15000, "minutes": 150, "mood": 7.0, "health": 0.0, "skill": "", "addiction": 0.01},
	"standup": {"name": "看脱口秀", "category": "culture", "fee": 15000, "minutes": 120, "mood": 7.0, "health": 0.0, "skill": "", "addiction": 0.02},
	"music_festival": {"name": "参加音乐节", "category": "culture", "fee": 60000, "minutes": 600, "mood": 9.0, "health": 0.0, "skill": "", "addiction": 0.02},
	"art_exhibition": {"name": "看美术展", "category": "culture", "fee": 10000, "minutes": 150, "mood": 6.0, "health": 0.5, "skill": "", "addiction": 0.01},
	"poetry_recital": {"name": "诗歌朗诵", "category": "culture", "fee": 2000, "minutes": 90, "mood": 5.0, "health": 0.5, "skill": "", "addiction": 0.01},
	# 竞技
	"basketball": {"name": "篮球", "category": "sports", "fee": 2000, "minutes": 120, "mood": 7.0, "health": 5.0, "skill": "fitness", "addiction": 0.02},
	"football": {"name": "足球", "category": "sports", "fee": 2000, "minutes": 120, "mood": 7.0, "health": 5.0, "skill": "fitness", "addiction": 0.02},
	"table_tennis": {"name": "乒乓球", "category": "sports", "fee": 1000, "minutes": 90, "mood": 6.0, "health": 3.0, "skill": "fitness", "addiction": 0.02},
	"badminton": {"name": "羽毛球", "category": "sports", "fee": 3000, "minutes": 90, "mood": 6.0, "health": 4.0, "skill": "fitness", "addiction": 0.02},
	"tennis": {"name": "网球", "category": "sports", "fee": 10000, "minutes": 120, "mood": 6.0, "health": 4.0, "skill": "fitness", "addiction": 0.01},
	"swimming": {"name": "游泳", "category": "sports", "fee": 5000, "minutes": 90, "mood": 6.0, "health": 6.0, "skill": "fitness", "addiction": 0.01},
	"billiards": {"name": "台球", "category": "sports", "fee": 3000, "minutes": 120, "mood": 5.0, "health": 0.5, "skill": "", "addiction": 0.02},
	"bowling": {"name": "保龄球", "category": "sports", "fee": 6000, "minutes": 90, "mood": 6.0, "health": 2.0, "skill": "", "addiction": 0.01},
	"golf": {"name": "高尔夫", "category": "sports", "fee": 80000, "minutes": 240, "mood": 7.0, "health": 3.0, "skill": "", "addiction": 0.01},
	"boxing": {"name": "拳击", "category": "sports", "fee": 8000, "minutes": 90, "mood": 6.0, "health": 4.0, "skill": "fitness", "addiction": 0.02},
	"martial_arts": {"name": "武术", "category": "sports", "fee": 5000, "minutes": 90, "mood": 6.0, "health": 5.0, "skill": "fitness", "addiction": 0.01},
	"esports": {"name": "电竞", "category": "sports", "fee": 1000, "minutes": 180, "mood": 7.0, "health": -1.0, "skill": "", "addiction": 0.06},
	"archery": {"name": "射箭", "category": "sports", "fee": 8000, "minutes": 90, "mood": 6.0, "health": 2.0, "skill": "", "addiction": 0.01},
	"fencing": {"name": "击剑", "category": "sports", "fee": 15000, "minutes": 90, "mood": 6.0, "health": 3.0, "skill": "fitness", "addiction": 0.01},
	"racing": {"name": "赛车", "category": "sports", "fee": 100000, "minutes": 180, "mood": 8.0, "health": 1.0, "skill": "", "addiction": 0.02},
	"volleyball": {"name": "排球", "category": "sports", "fee": 2000, "minutes": 90, "mood": 6.0, "health": 4.0, "skill": "fitness", "addiction": 0.02},
	"baseball": {"name": "棒球", "category": "sports", "fee": 8000, "minutes": 120, "mood": 6.0, "health": 4.0, "skill": "fitness", "addiction": 0.01},
	"rugby": {"name": "橄榄球", "category": "sports", "fee": 5000, "minutes": 120, "mood": 7.0, "health": 4.0, "skill": "fitness", "addiction": 0.02},
	"ice_climbing": {"name": "攀冰", "category": "sports", "fee": 30000, "minutes": 300, "mood": 8.0, "health": 4.0, "skill": "fitness", "addiction": 0.02},
	"gymnastics": {"name": "体操", "category": "sports", "fee": 6000, "minutes": 90, "mood": 6.0, "health": 5.0, "skill": "fitness", "addiction": 0.01},
	"ice_skating": {"name": "滑冰", "category": "sports", "fee": 5000, "minutes": 90, "mood": 6.0, "health": 3.0, "skill": "", "addiction": 0.01},
	# 夜生活
	"bar": {"name": "酒吧", "category": "nightlife", "fee": 20000, "minutes": 180, "mood": 7.0, "health": -1.0, "skill": "", "addiction": 0.06},
	"nightclub": {"name": "夜店", "category": "nightlife", "fee": 40000, "minutes": 300, "mood": 8.0, "health": -1.5, "skill": "", "addiction": 0.07},
	"ktv": {"name": "KTV", "category": "nightlife", "fee": 25000, "minutes": 240, "mood": 7.0, "health": -0.5, "skill": "", "addiction": 0.04},
	"live_show": {"name": "看演出", "category": "nightlife", "fee": 30000, "minutes": 180, "mood": 8.0, "health": 0.0, "skill": "", "addiction": 0.02},
	"clubbing": {"name": "蹦迪", "category": "nightlife", "fee": 35000, "minutes": 240, "mood": 8.0, "health": -1.0, "skill": "", "addiction": 0.06},
	"quiet_bar": {"name": "清吧", "category": "nightlife", "fee": 15000, "minutes": 150, "mood": 6.0, "health": -0.5, "skill": "", "addiction": 0.04},
	"food_stall": {"name": "大排档", "category": "nightlife", "fee": 6000, "minutes": 120, "mood": 6.0, "health": -0.5, "skill": "", "addiction": 0.02},
	"night_market": {"name": "夜市", "category": "nightlife", "fee": 8000, "minutes": 150, "mood": 6.0, "health": 0.0, "skill": "", "addiction": 0.02},
	"midnight_movie": {"name": "午夜电影", "category": "nightlife", "fee": 5000, "minutes": 150, "mood": 5.0, "health": -0.5, "skill": "", "addiction": 0.02},
	"board_game_bar": {"name": "桌游吧", "category": "nightlife", "fee": 12000, "minutes": 180, "mood": 6.0, "health": 0.0, "skill": "", "addiction": 0.03},
	"jazz_bar": {"name": "爵士酒吧", "category": "nightlife", "fee": 30000, "minutes": 180, "mood": 7.0, "health": -0.5, "skill": "", "addiction": 0.03},
	"crosstalk_teahouse": {"name": "相声茶馆", "category": "nightlife", "fee": 15000, "minutes": 150, "mood": 7.0, "health": 0.0, "skill": "", "addiction": 0.02},
	"late_night_food": {"name": "深夜食堂", "category": "nightlife", "fee": 8000, "minutes": 90, "mood": 5.0, "health": -0.5, "skill": "", "addiction": 0.03},
	"escape_room": {"name": "密室逃脱", "category": "nightlife", "fee": 18000, "minutes": 120, "mood": 7.0, "health": 1.0, "skill": "", "addiction": 0.02},
	"script_game": {"name": "剧本杀", "category": "nightlife", "fee": 20000, "minutes": 240, "mood": 7.0, "health": 0.0, "skill": "", "addiction": 0.03},
	# 收藏
	"stamp_collect": {"name": "集邮", "category": "collect", "fee": 10000, "minutes": 90, "mood": 5.0, "health": 0.0, "skill": "", "addiction": 0.02},
	"figure_collect": {"name": "手办", "category": "collect", "fee": 50000, "minutes": 60, "mood": 6.0, "health": 0.0, "skill": "", "addiction": 0.03},
	"antique": {"name": "古董", "category": "collect", "fee": 200000, "minutes": 120, "mood": 7.0, "health": 0.0, "skill": "", "addiction": 0.03},
	"coin_collect": {"name": "钱币", "category": "collect", "fee": 20000, "minutes": 60, "mood": 5.0, "health": 0.0, "skill": "", "addiction": 0.02},
	"card_collect": {"name": "卡牌", "category": "collect", "fee": 15000, "minutes": 90, "mood": 6.0, "health": 0.0, "skill": "", "addiction": 0.04},
	"sneaker_collect": {"name": "球鞋", "category": "collect", "fee": 80000, "minutes": 60, "mood": 6.0, "health": 0.0, "skill": "", "addiction": 0.03},
	"jade_collect": {"name": "玉石", "category": "collect", "fee": 150000, "minutes": 90, "mood": 6.0, "health": 0.0, "skill": "", "addiction": 0.02},
	"vinyl_collect": {"name": "唱片", "category": "collect", "fee": 40000, "minutes": 60, "mood": 6.0, "health": 0.0, "skill": "", "addiction": 0.02},
	"model_collect": {"name": "模型", "category": "collect", "fee": 30000, "minutes": 120, "mood": 6.0, "health": 0.0, "skill": "", "addiction": 0.02},
	"book_collect": {"name": "书籍收藏", "category": "collect", "fee": 25000, "minutes": 60, "mood": 5.0, "health": 0.5, "skill": "", "addiction": 0.01},
	"art_collect": {"name": "艺术画", "category": "collect", "fee": 500000, "minutes": 90, "mood": 7.0, "health": 0.0, "skill": "", "addiction": 0.02},
	"wine_collect": {"name": "酒收藏", "category": "collect", "fee": 100000, "minutes": 60, "mood": 6.0, "health": -0.5, "skill": "", "addiction": 0.03},
	"badge_collect": {"name": "徽章", "category": "collect", "fee": 10000, "minutes": 60, "mood": 5.0, "health": 0.0, "skill": "", "addiction": 0.02},
	"postcard_collect": {"name": "明信片", "category": "collect", "fee": 5000, "minutes": 60, "mood": 5.0, "health": 0.0, "skill": "", "addiction": 0.01},
	"camera_collect": {"name": "老相机", "category": "collect", "fee": 120000, "minutes": 60, "mood": 6.0, "health": 0.0, "skill": "", "addiction": 0.02},
	"teapot_collect": {"name": "紫砂壶", "category": "collect", "fee": 90000, "minutes": 60, "mood": 6.0, "health": 0.0, "skill": "", "addiction": 0.02},
	"fossil_collect": {"name": "化石", "category": "collect", "fee": 70000, "minutes": 90, "mood": 6.0, "health": 0.0, "skill": "", "addiction": 0.02},
	# 极限
	"skydiving": {"name": "跳伞", "category": "extreme", "fee": 150000, "minutes": 240, "mood": 10.0, "health": -1.0, "skill": "fitness", "addiction": 0.03},
	"bungee": {"name": "蹦极", "category": "extreme", "fee": 60000, "minutes": 180, "mood": 9.0, "health": -1.0, "skill": "fitness", "addiction": 0.03},
	"rock_climbing": {"name": "攀岩", "category": "extreme", "fee": 20000, "minutes": 240, "mood": 8.0, "health": 4.0, "skill": "fitness", "addiction": 0.03},
	"paragliding": {"name": "滑翔伞", "category": "extreme", "fee": 120000, "minutes": 300, "mood": 10.0, "health": -1.0, "skill": "fitness", "addiction": 0.03},
	"deep_diving": {"name": "深潜", "category": "extreme", "fee": 100000, "minutes": 360, "mood": 9.0, "health": 1.0, "skill": "fitness", "addiction": 0.02},
	"rafting": {"name": "漂流", "category": "extreme", "fee": 40000, "minutes": 300, "mood": 8.0, "health": 2.0, "skill": "fitness", "addiction": 0.02},
	"offroad": {"name": "越野", "category": "extreme", "fee": 80000, "minutes": 360, "mood": 8.0, "health": 1.0, "skill": "", "addiction": 0.02},
	"hot_air_balloon": {"name": "热气球", "category": "extreme", "fee": 90000, "minutes": 240, "mood": 9.0, "health": 0.0, "skill": "", "addiction": 0.02},
	"surfing": {"name": "冲浪", "category": "extreme", "fee": 50000, "minutes": 300, "mood": 9.0, "health": 3.0, "skill": "fitness", "addiction": 0.02},
	"wingsuit": {"name": "翼装飞行", "category": "extreme", "fee": 300000, "minutes": 300, "mood": 10.0, "health": -3.0, "skill": "fitness", "addiction": 0.03},
	"caving": {"name": "探洞", "category": "extreme", "fee": 40000, "minutes": 360, "mood": 8.0, "health": 1.0, "skill": "fitness", "addiction": 0.02},
	"alpine_skiing": {"name": "高山滑雪", "category": "extreme", "fee": 100000, "minutes": 420, "mood": 9.0, "health": 2.0, "skill": "fitness", "addiction": 0.02},
	"parkour": {"name": "极限跑酷", "category": "extreme", "fee": 0, "minutes": 180, "mood": 8.0, "health": 4.0, "skill": "fitness", "addiction": 0.03},
	"cliff_diving": {"name": "悬崖跳水", "category": "extreme", "fee": 20000, "minutes": 180, "mood": 9.0, "health": -2.0, "skill": "fitness", "addiction": 0.03},
}

const ADDICTION_THRESHOLD: float = BaselineScript.ENT_ADDICTION_THRESHOLD


func categories() -> Array:
	return CATEGORIES.duplicate()


func activities_count() -> int:
	return ACTIVITIES.size()


func activity(id: String) -> Dictionary:
	return (ACTIVITIES.get(id, {}) as Dictionary).duplicate()


func by_category(category: String) -> Array:
	var out: Array = []
	for id in ACTIVITIES:
		if str(ACTIVITIES[id]["category"]) == category:
			out.append(id)
	return out


## 执行娱乐（R54.2、R54.7）。previous_count 为同一活动近期次数，用于重复衰减。
func do_activity(activity_id: String, previous_count: int, money: int, rng = null) -> Dictionary:
	if not ACTIVITIES.has(activity_id):
		return {"ok": false, "reason": "unknown_activity"}
	var a: Dictionary = ACTIVITIES[activity_id]
	var fee: int = int(a["fee"])
	if money < fee:
		return {"ok": false, "reason": "insufficient_funds", "fee": fee}
	var decay: float = 1.0 / (1.0 + maxf(0.0, float(previous_count)) * 0.4)
	var mood: float = float(a["mood"]) * decay
	var health: float = float(a["health"]) * decay
	var addiction_gain: float = float(a["addiction"]) * (1.0 - decay * 0.5)
	return {"ok": true, "activity": activity_id, "fee": fee, "minutes": int(a["minutes"]), "mood": mood, "health": health, "tolerance": decay, "addiction_gain": addiction_gain}


## 上瘾结算（R54.7）：累积超过阈值即成瘾。
func update_addiction(current: float, gain: float) -> Dictionary:
	var value: float = clampf(current + gain * 100.0, 0.0, 100.0)
	return {"value": value, "addicted": value >= ADDICTION_THRESHOLD}


## 同好圈层（R54.3）。
func interest_circle(activity_id: String) -> Dictionary:
	if not ACTIVITIES.has(activity_id):
		return {"ok": false, "reason": "unknown_activity"}
	var cat: String = str(ACTIVITIES[activity_id]["category"])
	return {"ok": true, "circle": "%s同好会" % CATEGORY_NAMES.get(cat, cat), "social": true}


## 副业转化（R54.3）：专精后可将兴趣发展为副业。
func side_business(activity_id: String, proficiency: float) -> Dictionary:
	if not ACTIVITIES.has(activity_id):
		return {"ok": false, "reason": "unknown_activity"}
	if proficiency < 60.0:
		return {"ok": true, "available": false, "required": 60.0}
	return {"ok": true, "available": true, "monthly_income": int(proficiency * 200.0)}


## 过度娱乐风险（R54.7）。
func overspend_risk(debt: int, addiction: float) -> Dictionary:
	return {"debt_risk": debt > 0, "addiction_risk": addiction >= ADDICTION_THRESHOLD, "problem": debt > 0 or addiction >= ADDICTION_THRESHOLD}
