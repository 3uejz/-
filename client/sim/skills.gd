class_name SkillSystem
extends RefCounted
## 领域技能树与成长（R10、R45.1-3；design D5）。
##
## 结构：7 棵领域树（生活/职业/学术/艺术/体育/社交/犯罪），每棵 21 个技能，等级 0..20，
##       含前置、等级上限、实践途径与职业解锁；部分技能受天赋或先天上限限制。
## 成长：升到 n 级所需经验 need(n) ≈ base·n^1.5；
##       实践收益 Δxp = practice·(1+智力)·(1+意志)·(1−疲劳)·(1+天赋)·(1+指导)；
##       高等级边际收益递减，长期不使用缓慢遗忘。
##
## 设计取舍：
##   - 技能数据直接读写 player["skills"] 数组（与 jobs.gd 的读取口径一致），本模块无 Autoload 依赖；
##   - 内容可随内容包扩展：register() 可无限追加技能定义；
##   - 随机性不由本模块引入，天赋/指导/疲劳均由调用方注入，便于复现与三端对齐。

const MAX_LEVEL: int = 20
const XP_BASE: float = 100.0
const XP_EXPONENT: float = 1.5
const PRACTICE_BASE: float = 10.0
const DIMINISH_START: int = 10
const DIMINISH_RATE: float = 0.9
const INNATE_CAP: int = 8
const IDLE_GRACE_DAYS: float = 30.0
const FORGET_PER_DAY: float = 0.02

const TREES: Array = ["life", "career", "academic", "art", "sports", "social", "crime"]
const TREE_NAMES: Dictionary = {
	"life": "生活", "career": "职业", "academic": "学术",
	"art": "艺术", "sports": "体育", "social": "社交", "crime": "犯罪",
}

## 每棵树 21 个技能：id -> 名称（按成长顺序排列，每 3 个一层）。
const TREE_SKILLS: Dictionary = {
	"life": [
		["cooking", "烹饪"], ["cleaning", "清洁"], ["driving", "驾驶"],
		["finance_life", "理财"], ["first_aid", "急救"], ["repair", "维修"],
		["gardening", "园艺"], ["sewing", "缝纫"], ["appliance_repair", "家电维修"],
		["woodwork", "木工"], ["fishing", "钓鱼"], ["camping", "露营"],
		["baking", "烘焙"], ["bartending", "调酒"], ["pet_care", "宠物照料"],
		["home_nursing", "家庭护理"], ["parenting", "育儿"], ["survival", "野外生存"],
		["organizing", "收纳"], ["diy", "DIY"], ["budgeting", "预算规划"],
	],
	"career": [
		["programming", "编程"], ["design", "设计"], ["technical", "技术操作"],
		["writing_pro", "文案写作"], ["accounting", "会计"], ["sales", "销售"],
		["negotiation", "谈判"], ["management", "管理"], ["public_speaking", "演讲"],
		["project_management", "项目管理"], ["marketing", "市场营销"], ["customer_service", "客户服务"],
		["logistics", "物流调度"], ["quality_control", "质量管理"], ["secretarial", "文秘"],
		["legal_affairs", "法务"], ["finance", "金融分析"], ["data_analysis", "数据分析"],
		["teaching", "教学"], ["engineering", "工程制图"], ["entrepreneurship", "创业实务"],
	],
	"academic": [
		["math", "数学"], ["physics", "物理"], ["chemistry", "化学"],
		["biology", "生物"], ["history", "历史"], ["philosophy", "哲学"],
		["foreign_language", "外语"], ["statistics", "统计"], ["academic", "学术研究"],
		["economics", "经济学"], ["psychology", "心理学"], ["sociology", "社会学"],
		["law", "法学"], ["medicine", "医学"], ["engineering_theory", "工程学"],
		["computer_science", "计算机科学"], ["literature", "文学"], ["geography", "地理"],
		["astronomy", "天文"], ["archaeology", "考古"], ["linguistics", "语言学"],
	],
	"art": [
		["painting", "绘画"], ["vocal", "声乐"], ["instrument", "乐器"],
		["dance", "舞蹈"], ["acting", "表演"], ["photography", "摄影"],
		["creative_writing", "文学创作"], ["sculpture", "雕塑"], ["calligraphy", "书法"],
		["film", "影视制作"], ["music_theory", "乐理"], ["composition", "作曲"],
		["directing", "导演"], ["fashion_design", "服装设计"], ["graphic_design", "平面设计"],
		["animation", "动画"], ["pottery", "陶艺"], ["opera", "戏曲"],
		["magic", "魔术"], ["hosting", "主持"], ["art_appreciation", "艺术鉴赏"],
	],
	"sports": [
		["physique", "体能"], ["running", "跑步"], ["swimming", "游泳"],
		["combat", "格斗"], ["ball_sports", "球类"], ["track", "田径"],
		["yoga", "瑜伽"], ["cycling", "骑行"], ["climbing", "攀岩"],
		["skiing", "滑雪"], ["martial_arts", "武术"], ["boxing", "拳击"],
		["weightlifting", "举重"], ["gymnastics", "体操"], ["shooting", "射击"],
		["archery", "射箭"], ["fencing", "击剑"], ["rowing", "赛艇"],
		["surfing", "冲浪"], ["parkour", "跑酷"], ["skating", "滑冰"],
	],
	"social": [
		["etiquette", "社交礼仪"], ["empathy", "共情"], ["persuasion", "说服"],
		["disguise", "伪装"], ["leadership", "领导"], ["willpower", "意志力"],
		["public_relations", "公关"], ["networking", "人脉经营"], ["lying", "说谎"],
		["mediation", "调解"], ["teamwork", "团队协作"], ["humor", "幽默"],
		["confiding", "倾诉"], ["conflict_resolution", "冲突化解"], ["emotional_control", "情绪管理"],
		["intimacy", "亲密关系"], ["mentoring", "指导他人"], ["bargaining", "砍价"],
		["impression", "印象管理"], ["hosting_social", "社交主持"], ["cross_cultural", "跨文化沟通"],
	],
	"crime": [
		["lockpicking", "开锁"], ["pickpocketing", "扒窃"], ["shoplifting", "顺手牵羊"],
		["fraud", "诈骗"], ["hacking", "黑客"], ["gambling", "赌术"],
		["counter_surveillance", "反侦察"], ["forgery", "伪造"], ["smuggling", "走私"],
		["money_laundering", "洗钱"], ["blackmail", "勒索"], ["drug_dealing", "贩毒"],
		["arms_trafficking", "军火交易"], ["cyber_theft", "网络盗窃"], ["scam_call", "电信诈骗"],
		["bribery", "行贿"], ["theft", "盗窃"], ["robbery", "抢劫"],
		["extortion", "敲诈"], ["insider_trading", "内幕交易"], ["crime_disguise", "犯罪伪装"],
	],
}

## 受天赋限制的技能：skill id -> 天赋标签。缺该天赋时等级上限为 INNATE_CAP。
const TALENT_GATED: Dictionary = {
	"vocal": "talent.music", "instrument": "talent.music", "composition": "talent.music",
	"painting": "talent.art", "physique": "talent.athletic",
	"running": "talent.athletic", "math": "talent.logical", "physics": "talent.logical",
}

var _defs: Dictionary = {}


# --- 目录 ---

## 注册技能定义；缺 id/name/tree 或非法领域拒绝。返回存入的定义或 {}。
func register(def: Dictionary) -> Dictionary:
	var id: String = str(def.get("id", ""))
	var name: String = str(def.get("name", ""))
	var tree: String = str(def.get("tree", ""))
	if id.is_empty() or name.is_empty() or not TREES.has(tree):
		return {}
	var max_level: int = int(def.get("max_level", MAX_LEVEL))
	if max_level < 1 or max_level > MAX_LEVEL:
		return {}
	var stored: Dictionary = {
		"id": id, "name": name, "tree": tree,
		"max_level": max_level,
		"prereq": (def.get("prereq", {}) as Dictionary).duplicate(),
		"talent": str(def.get("talent", TALENT_GATED.get(id, ""))),
		"practice": str(def.get("practice", tree)),
	}
	_defs[id] = stored
	return stored


## 注册起步目录：7 棵树 × 21 技能 = 147 个，返回技能总数。
func register_starter_catalog() -> int:
	for tree in TREES:
		var list: Array = TREE_SKILLS[tree]
		for i in list.size():
			var pair: Array = list[i]
			var skill_id: String = "skill." + str(pair[0])
			var prereq: Dictionary = {}
			var tier: int = i / 3
			if tier >= 1:
				var anchor: Array = list[(tier - 1) * 3 + (i % 3)]
				prereq["skill." + str(anchor[0])] = tier * 5
			register({
				"id": skill_id, "name": str(pair[1]), "tree": tree,
				"prereq": prereq,
				"talent": TALENT_GATED.get(str(pair[0]), ""),
			})
	return _defs.size()


func def_count() -> int:
	return _defs.size()


func has_def(id: String) -> bool:
	return _defs.has(id)


func get_def(id: String) -> Dictionary:
	return _defs.get(id, {})


func by_tree(tree: String) -> Array:
	var out: Array = []
	for id in _defs.keys():
		if str(_defs[id].get("tree", "")) == tree:
			out.append(_defs[id])
	return out


# --- 经验曲线 ---

## 从 level 升到 level+1 所需经验。
static func need_xp(level: int) -> float:
	if level < 0:
		return 0.0
	return XP_BASE * pow(float(level + 1), XP_EXPONENT)


# --- 玩家技能存取 ---

func entry_for(skills: Array, id: String) -> Dictionary:
	for s in skills:
		if str((s as Dictionary).get("content_key", "")) == id:
			return s
	return {}


func level_of(skills: Array, id: String) -> int:
	var e: Dictionary = entry_for(skills, id)
	return int(e.get("level", 0))


func xp_of(skills: Array, id: String) -> float:
	var e: Dictionary = entry_for(skills, id)
	return float(e.get("xp", 0.0))


func _ensure(skills: Array, id: String) -> Dictionary:
	var e: Dictionary = entry_for(skills, id)
	if e.is_empty():
		e = {"content_key": id, "level": 0, "xp": 0.0, "last_used_minute": 0}
		skills.append(e)
	return e


## 前置是否满足。返回 {ok, missing:[{skill, need, have}]}。
func prereq_ok(skills: Array, id: String) -> Dictionary:
	var def: Dictionary = get_def(id)
	var missing: Array = []
	for k in (def.get("prereq", {}) as Dictionary).keys():
		var need: int = int(def["prereq"][k])
		var have: int = level_of(skills, str(k))
		if have < need:
			missing.append({"skill": str(k), "need": need, "have": have})
	return {"ok": missing.is_empty(), "missing": missing}


func can_learn(skills: Array, id: String) -> bool:
	return has_def(id) and bool(prereq_ok(skills, id)["ok"])


## 等级上限：受定义 max_level 与天赋限制。
func level_cap(id: String, talents: Array = []) -> int:
	var def: Dictionary = get_def(id)
	if def.is_empty():
		return 0
	var cap: int = int(def.get("max_level", MAX_LEVEL))
	var talent: String = str(def.get("talent", ""))
	if not talent.is_empty() and not talents.has(talent):
		cap = mini(cap, INNATE_CAP)
	return cap


# --- 实践与成长 ---

## 实践一次。ctx：intelligence、willpower、fatigue(0..1)、talents(Array)、guidance(0..1)、now_minute。
## 返回 {ok, xp_gain, level, xp, level_up, capped, reason?}。
func practice(skills: Array, id: String, amount: float, ctx: Dictionary = {}) -> Dictionary:
	if not has_def(id):
		return {"ok": false, "reason": "unknown_skill"}
	if amount <= 0.0:
		return {"ok": false, "reason": "bad_amount"}
	if not bool(prereq_ok(skills, id)["ok"]):
		return {"ok": false, "reason": "locked"}
	var talents: Array = ctx.get("talents", [])
	var cap: int = level_cap(id, talents)
	var e: Dictionary = _ensure(skills, id)
	var level: int = int(e["level"])
	var intelligence: float = float(ctx.get("intelligence", 50.0))
	var willpower: float = float(ctx.get("willpower", 50.0))
	var fatigue: float = clampf(float(ctx.get("fatigue", 0.0)), 0.0, 1.0)
	var guidance: float = clampf(float(ctx.get("guidance", 0.0)), 0.0, 1.0)
	var talent_bonus: float = 0.0
	var talent: String = str(get_def(id).get("talent", ""))
	if not talent.is_empty() and talents.has(talent):
		talent_bonus = 0.5
	var gain: float = (
		amount * PRACTICE_BASE
		* (1.0 + intelligence / 100.0)
		* (1.0 + willpower / 100.0)
		* (1.0 - fatigue)
		* (1.0 + talent_bonus)
		* (1.0 + guidance)
	)
	if level >= DIMINISH_START:
		gain *= pow(DIMINISH_RATE, float(level - DIMINISH_START + 1))
	# 等级上限：满级不再累积经验。
	if level >= cap:
		e["last_used_minute"] = int(ctx.get("now_minute", e.get("last_used_minute", 0)))
		return {"ok": true, "xp_gain": 0.0, "level": level, "xp": float(e["xp"]), "level_up": 0, "capped": true}
	var xp: float = float(e["xp"]) + gain
	var level_up: int = 0
	while level < cap and xp >= need_xp(level):
		xp -= need_xp(level)
		level += 1
		level_up += 1
	if level >= cap:
		xp = minf(xp, need_xp(level) - 1.0)
	e["level"] = level
	e["xp"] = maxf(0.0, xp)
	e["last_used_minute"] = int(ctx.get("now_minute", e.get("last_used_minute", 0)))
	return {
		"ok": true, "xp_gain": gain, "level": level, "xp": float(e["xp"]),
		"level_up": level_up, "capped": level >= cap,
	}


## 长期不使用缓慢遗忘。now_minute 为当前分钟；返回受影响 [{content_key, level, xp}]。
func forget(skills: Array, now_minute: int, idle_days: float = -1.0) -> Array:
	var affected: Array = []
	for s in skills:
		var e: Dictionary = s
		var level: int = int(e.get("level", 0))
		if level <= 0:
			continue
		var last: int = int(e.get("last_used_minute", 0))
		var days: float = idle_days if idle_days >= 0.0 else (float(now_minute - last) / 1440.0)
		if days <= IDLE_GRACE_DAYS:
			continue
		var penalty: float = FORGET_PER_DAY * (days - IDLE_GRACE_DAYS) * (need_xp(level) / 30.0)
		var xp: float = float(e.get("xp", 0.0)) - penalty
		if xp < 0.0:
			level = maxi(0, level - 1)
			xp = maxf(0.0, need_xp(level) + xp) if level > 0 else 0.0
		e["level"] = level
		e["xp"] = xp
		affected.append(e)
	return affected
