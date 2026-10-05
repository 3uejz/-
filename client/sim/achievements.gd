class_name AchievementSystem
extends RefCounted
## 成就与图鉴（R29；design D34）。
##
## 覆盖财富、事业、技能、社交、家庭、探索、奇遇、健康、法律九类成就；条件满足即
## 解锁、宣告并归档；图鉴记录已解锁成就、物品与人物；成就与图鉴跨周目累计。

const CATEGORIES: Array = ["wealth", "career", "skill", "social", "family", "exploration", "adventure", "health", "law"]
const CATEGORY_NAMES: Dictionary = {
	"wealth": "财富", "career": "事业", "skill": "技能", "social": "社交", "family": "家庭",
	"exploration": "探索", "adventure": "奇遇", "health": "健康", "law": "法律",
}

## 成就定义：metric 为统计键，threshold 为达成阈值。
const ACHIEVEMENTS: Dictionary = {
	"first_10k": {"name": "第一桶金", "category": "wealth", "metric": "money", "threshold": 1000000, "desc": "资产达到 1 万元", "hidden": false},
	"millionaire": {"name": "百万富翁", "category": "wealth", "metric": "money", "threshold": 100000000, "desc": "资产达到 100 万元", "hidden": false},
	"tycoon": {"name": "商业巨擘", "category": "wealth", "metric": "money", "threshold": 10000000000, "desc": "资产达到 1 亿元", "hidden": false},
	"first_job": {"name": "初入职场", "category": "career", "metric": "career_tier", "threshold": 1, "desc": "获得第一份工作", "hidden": false},
	"manager": {"name": "管理者", "category": "career", "metric": "career_tier", "threshold": 3, "desc": "晋升到管理岗", "hidden": false},
	"boss": {"name": "一方之主", "category": "career", "metric": "career_tier", "threshold": 5, "desc": "成为企业家或高层", "hidden": false},
	"polyglot": {"name": "学有所长", "category": "skill", "metric": "skill_max", "threshold": 10, "desc": "任一技能达到 10 级", "hidden": false},
	"master": {"name": "大师", "category": "skill", "metric": "skill_max", "threshold": 18, "desc": "任一技能达到 18 级", "hidden": false},
	"socialite": {"name": "善交游", "category": "social", "metric": "friends", "threshold": 10, "desc": "结识 10 位朋友", "hidden": false},
	"beloved": {"name": "万人迷", "category": "social", "metric": "friends", "threshold": 50, "desc": "结识 50 位朋友", "hidden": false},
	"married": {"name": "喜结连理", "category": "family", "metric": "married", "threshold": 1, "desc": "步入婚姻", "hidden": false},
	"parent": {"name": "为人父母", "category": "family", "metric": "children", "threshold": 1, "desc": "养育子女", "hidden": false},
	"big_family": {"name": "儿孙满堂", "category": "family", "metric": "children", "threshold": 3, "desc": "养育 3 个子女", "hidden": false},
	"traveler": {"name": "行万里路", "category": "exploration", "metric": "cities_visited", "threshold": 5, "desc": "到访 5 座城市", "hidden": false},
	"globetrotter": {"name": "环游世界", "category": "exploration", "metric": "countries_visited", "threshold": 5, "desc": "到访 5 个国家", "hidden": false},
	"collector": {"name": "收藏家", "category": "exploration", "metric": "items_collected", "threshold": 50, "desc": "收集 50 件物品", "hidden": false},
	"adventurer": {"name": "冒险者", "category": "adventure", "metric": "adventures", "threshold": 1, "desc": "完成一次探险", "hidden": false},
	"thrill_seeker": {"name": "极限挑战者", "category": "adventure", "metric": "extreme_activities", "threshold": 5, "desc": "完成 5 项极限活动", "hidden": true},
	"secret_luck": {"name": "天降横财", "category": "adventure", "metric": "lottery_wins", "threshold": 1, "desc": "彩票中奖", "hidden": true},
	"healthy": {"name": "身强体健", "category": "health", "metric": "health", "threshold": 95, "desc": "健康达到 95", "hidden": false},
	"longevity": {"name": "长命百岁", "category": "health", "metric": "age", "threshold": 100, "desc": "活到 100 岁", "hidden": false},
	"recovered": {"name": "战胜病魔", "category": "health", "metric": "diseases_recovered", "threshold": 1, "desc": "从重病中康复", "hidden": true},
	"first_crime": {"name": "初犯", "category": "law", "metric": "crimes_committed", "threshold": 1, "desc": "第一次犯罪", "hidden": true},
	"jailed": {"name": "铁窗生涯", "category": "law", "metric": "times_jailed", "threshold": 1, "desc": "入狱服刑", "hidden": true},
	"exonerated": {"name": "沉冤得雪", "category": "law", "metric": "exonerations", "threshold": 1, "desc": "再审平反", "hidden": true},
}


func categories() -> Array:
	return CATEGORIES.duplicate()


func achievement_count() -> int:
	return ACHIEVEMENTS.size()


func new_profile() -> Dictionary:
	return {"unlocked": {}, "announcements": [], "codex": {"achievements": {}, "items": {}, "characters": {}}, "runs": 0}


func is_unlocked(profile: Dictionary, id: String) -> bool:
	return (profile.get("unlocked", {}) as Dictionary).has(id)


## 结算成就（R29.2）：满足条件立即解锁、宣告并归档。
func check(profile: Dictionary, stats: Dictionary) -> Dictionary:
	var unlocked: Array = []
	for id in ACHIEVEMENTS:
		if is_unlocked(profile, id):
			continue
		var a: Dictionary = ACHIEVEMENTS[id]
		var value: float = float(stats.get(str(a["metric"]), 0.0))
		if value >= float(a["threshold"]):
			profile["unlocked"][id] = {"name": a["name"], "category": a["category"]}
			profile["codex"]["achievements"][id] = true
			profile["announcements"].append("解锁成就：%s（%s）" % [a["name"], a["desc"]])
			unlocked.append(id)
	return {"ok": true, "unlocked": unlocked, "announcements": profile["announcements"].slice(maxi(0, profile["announcements"].size() - unlocked.size()))}


## 图鉴登记（R29.3）。
func add_item(profile: Dictionary, item_id: String) -> Dictionary:
	profile["codex"]["items"][item_id] = true
	return {"ok": true, "items": (profile["codex"]["items"] as Dictionary).size()}


func add_character(profile: Dictionary, character_id: String) -> Dictionary:
	profile["codex"]["characters"][character_id] = true
	return {"ok": true, "characters": (profile["codex"]["characters"] as Dictionary).size()}


## 跨周目累计（R29.4）：合并上一周目图鉴并递增周目数。
func merge_run(profile: Dictionary, run_codex: Dictionary) -> Dictionary:
	for key in ["achievements", "items", "characters"]:
		var src: Dictionary = run_codex.get(key, {})
		for id in src:
			profile["codex"][key][id] = true
	profile["runs"] = int(profile["runs"]) + 1
	return {"ok": true, "runs": int(profile["runs"]), "total": int(profile["codex"]["achievements"].size())}
