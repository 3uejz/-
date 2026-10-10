class_name LanguageSystem
extends RefCounted
## 语言与文化（R64；design D20）。
##
## 覆盖：
##   - 语言等级 0..100，分项口语/听力/读写，专业术语设门槛；
##   - 学习（课程/环境沉浸/自学）、考试与证书；长期不用缓慢遗忘；
##   - 方言本地降低交流门槛；
##   - 完整节日日历（宗教/国家/民俗），影响商铺营业/交通/社交/心情与节庆消费；
##   - 文化差异（礼节/禁忌/社交距离/时间观念）影响社交判定与适应曲线；
##   - 跨文化（翻译/外交/跨国婚姻/文化冲突、语言不通导致误会降关系）。
##
## 设计取舍：
##   - 玩家语言档案为纯数据 Dictionary；分项能力独立成长，总分按权重合成；
##   - 学习增益随当前水平递减，避免无脑刷满；遗忘由调用方给出闲置天数；
##   - 节日与文化表为常量数据表，效果按当日汇总，便于与其他系统（商铺/交通/心情）对接。

const BaselineScript = preload("res://sim/baseline.gd")

const COMPONENTS: Array = ["speaking", "listening", "literacy"]
const COMPONENT_NAMES: Dictionary = {"speaking": "口语", "listening": "听力", "literacy": "读写"}
const COMPONENT_WEIGHTS: Dictionary = {"speaking": 0.4, "listening": 0.3, "literacy": 0.3}
const MAX_LEVEL: float = BaselineScript.LANG_MAX_LEVEL
const BASE_STUDY_GAIN: float = BaselineScript.LANG_BASE_STUDY_GAIN

## 官方语言与区域方言。
const LANGUAGES: Dictionary = {
	"zh": {"name": "汉语", "official_regions": ["cn"], "dialects": ["sichuan", "cantonese", "wu"]},
	"en": {"name": "英语", "official_regions": ["us", "uk"], "dialects": ["cockney", "southern"]},
	"es": {"name": "西班牙语", "official_regions": ["es", "mx"], "dialects": ["andaluz"]},
	"ja": {"name": "日语", "official_regions": ["jp"], "dialects": ["kansai"]},
	"fr": {"name": "法语", "official_regions": ["fr"], "dialects": ["quebecois"]},
}

## 学习方法：效率倍率与分项偏好（口语/听力/读写）。
const STUDY_METHODS: Dictionary = {
	"course": {"name": "课程", "mult": 1.0, "bias": {"speaking": 0.8, "listening": 0.9, "literacy": 1.4}},
	"immersion": {"name": "环境沉浸", "mult": 1.4, "bias": {"speaking": 1.4, "listening": 1.3, "literacy": 0.7}},
	"self_study": {"name": "自学", "mult": 0.7, "bias": {"speaking": 0.6, "listening": 0.6, "literacy": 1.2}},
}

## 专业术语门槛（总分达到方可从事该领域）。
const PROFESSIONAL_TERMS: Dictionary = {"medical": 70.0, "legal": 80.0, "technical": 75.0, "diplomacy": 85.0}

## 语言等级解锁的职业（移民/外交/翻译）。
const CAREER_UNLOCKS: Dictionary = {"immigration": 60.0, "diplomat": 80.0, "translation": 85.0}

## 节日日历：type ∈ religious/national/folk。
const FESTIVALS: Array = [
	{"key": "spring_festival", "name": "春节", "type": "national", "month": 1, "day": 1, "shops_open": false, "traffic": 0.3, "social": 1.8, "mood": 8.0, "spending": 2.2},
	{"key": "lantern", "name": "元宵节", "type": "folk", "month": 1, "day": 15, "shops_open": true, "traffic": 0.6, "social": 1.4, "mood": 5.0, "spending": 1.5},
	{"key": "eid", "name": "开斋节", "type": "religious", "month": 4, "day": 10, "shops_open": false, "traffic": 0.5, "social": 1.6, "mood": 6.0, "spending": 1.6},
	{"key": "mid_autumn", "name": "中秋节", "type": "folk", "month": 9, "day": 15, "shops_open": true, "traffic": 0.7, "social": 1.5, "mood": 6.0, "spending": 1.7},
	{"key": "national_day", "name": "国庆", "type": "national", "month": 10, "day": 1, "shops_open": true, "traffic": 0.5, "social": 1.3, "mood": 6.0, "spending": 1.6},
	{"key": "christmas", "name": "圣诞节", "type": "religious", "month": 12, "day": 25, "shops_open": false, "traffic": 0.4, "social": 1.5, "mood": 7.0, "spending": 1.8},
]

## 文化差异表：社交距离与时间观念取值 0..1，越大越疏远/越守时。
const CULTURES: Dictionary = {
	"cn": {"name": "中华", "etiquette": "握手或点头", "taboos": ["数字4", "丧事白色"], "social_distance": 0.5, "time_orientation": 0.6},
	"us": {"name": "美国", "etiquette": "握手或拥抱", "taboos": ["过度贴近"], "social_distance": 0.7, "time_orientation": 0.9},
	"jp": {"name": "日本", "etiquette": "鞠躬", "taboos": ["迟到", "数字4"], "social_distance": 0.8, "time_orientation": 1.0},
	"fr": {"name": "法国", "etiquette": "贴面礼", "taboos": ["公开谈钱"], "social_distance": 0.5, "time_orientation": 0.5},
	"ae": {"name": "阿拉伯", "etiquette": "右手致意", "taboos": ["左手递物", "饮酒"], "social_distance": 0.4, "time_orientation": 0.4},
}


# --- 语言档案 ---

## 新建语言档案（无 Autoload 依赖，纯数据）。
func new_profile() -> Dictionary:
	var langs: Dictionary = {}
	for k in LANGUAGES.keys():
		langs[k] = {"speaking": 0.0, "listening": 0.0, "literacy": 0.0, "last_used_day": 0.0}
	return {"languages": langs, "certificates": [], "adaptation": {}}


func languages() -> Array:
	return LANGUAGES.keys()


func has_language(lang: String) -> bool:
	return LANGUAGES.has(lang)


func language_def(lang: String) -> Dictionary:
	if not LANGUAGES.has(lang):
		return {}
	return (LANGUAGES[lang] as Dictionary).duplicate(true)


func _lang(profile: Dictionary, lang: String) -> Dictionary:
	if not profile.has("languages") or typeof(profile["languages"]) != TYPE_DICTIONARY:
		profile["languages"] = {}
	var langs: Dictionary = profile["languages"]
	if not langs.has(lang):
		return {}
	return langs[lang]


func ensure_language(profile: Dictionary, lang: String) -> Dictionary:
	if not profile.has("languages") or typeof(profile["languages"]) != TYPE_DICTIONARY:
		profile["languages"] = {}
	var langs: Dictionary = profile["languages"]
	if not langs.has(lang):
		langs[lang] = {"speaking": 0.0, "listening": 0.0, "literacy": 0.0, "last_used_day": 0.0}
	return langs[lang]


## 直接设定分项等级（用于初始化/剧情）。
func set_level(profile: Dictionary, lang: String, speaking: float, listening: float, literacy: float) -> Dictionary:
	if not LANGUAGES.has(lang):
		return {"ok": false, "reason": "unknown_language"}
	var entry: Dictionary = ensure_language(profile, lang)
	entry["speaking"] = clampf(speaking, 0.0, MAX_LEVEL)
	entry["listening"] = clampf(listening, 0.0, MAX_LEVEL)
	entry["literacy"] = clampf(literacy, 0.0, MAX_LEVEL)
	return {"ok": true, "overall": overall(profile, lang)}


func component(profile: Dictionary, lang: String, comp: String) -> float:
	var entry: Dictionary = _lang(profile, lang)
	if entry.is_empty():
		return 0.0
	return float(entry.get(comp, 0.0))


## 综合等级：口语 0.4 + 听力 0.3 + 读写 0.3。
func overall(profile: Dictionary, lang: String) -> float:
	var entry: Dictionary = _lang(profile, lang)
	if entry.is_empty():
		return 0.0
	var total: float = 0.0
	for c in COMPONENTS:
		total += float(entry.get(c, 0.0)) * float(COMPONENT_WEIGHTS[c])
	return total


# --- 学习、考试与遗忘 ---

## 学习语言；水平越高增益越小。opts: aptitude 天赋(0.3..2.0)、day 记录使用日。
func study(profile: Dictionary, lang: String, method: String, hours: float, opts: Dictionary = {}) -> Dictionary:
	if not LANGUAGES.has(lang):
		return {"ok": false, "reason": "unknown_language"}
	if not STUDY_METHODS.has(method):
		return {"ok": false, "reason": "unknown_method"}
	var entry: Dictionary = ensure_language(profile, lang)
	var m: Dictionary = STUDY_METHODS[method]
	var current: float = overall(profile, lang)
	var room: float = clampf(1.0 - current / MAX_LEVEL, 0.0, 1.0)
	var aptitude: float = clampf(float(opts.get("aptitude", 1.0)), 0.3, 2.0)
	var gain: float = BASE_STUDY_GAIN * float(m["mult"]) * aptitude * room * maxf(0.0, hours)
	var bias: Dictionary = m["bias"]
	var gains: Dictionary = {}
	for c in COMPONENTS:
		var g: float = gain * float(bias[c])
		entry[c] = clampf(float(entry.get(c, 0.0)) + g, 0.0, MAX_LEVEL)
		gains[c] = g
	entry["last_used_day"] = float(opts.get("day", entry.get("last_used_day", 0.0)))
	return {"ok": true, "method": method, "gains": gains, "overall": overall(profile, lang)}


## 环境沉浸：以沉浸法按天学习。
func immerse(profile: Dictionary, lang: String, days: float, opts: Dictionary = {}) -> Dictionary:
	return study(profile, lang, "immersion", maxf(0.0, days) * float(opts.get("intensity", 1.0)), opts)


## 长期不用遗忘：扣除宽限期后按天衰减各分项，最低到 0。
func decay(profile: Dictionary, lang: String, idle_days: float, opts: Dictionary = {}) -> Dictionary:
	var entry: Dictionary = _lang(profile, lang)
	if entry.is_empty():
		return {"ok": false, "reason": "unknown_language"}
	var grace: float = float(opts.get("grace_days", 30.0))
	var idle: float = maxf(0.0, idle_days) - grace
	if idle <= 0.0:
		return {"ok": true, "decayed": false, "loss": {}, "overall": overall(profile, lang)}
	var lost: float = idle * float(opts.get("decay_rate", 0.02))
	var loss: Dictionary = {}
	for c in COMPONENTS:
		var before: float = float(entry.get(c, 0.0))
		entry[c] = clampf(before - lost, 0.0, MAX_LEVEL)
		loss[c] = before - float(entry[c])
	return {"ok": true, "decayed": true, "loss": loss, "overall": overall(profile, lang)}


## 参加语言考试：总分加随机扰动达到目标即通过并颁发证书。
func take_exam(profile: Dictionary, lang: String, target_level: float, opts: Dictionary = {}, rng = null) -> Dictionary:
	if not LANGUAGES.has(lang):
		return {"ok": false, "reason": "unknown_language"}
	var score: float = overall(profile, lang)
	var roll: float = _roll(float(opts.get("roll", -1.0)), rng)
	var jitter: float = (roll - 0.5) * 10.0
	var passed: bool = score + jitter >= float(target_level)
	if passed and not has_certificate(profile, lang, target_level):
		certificates(profile).append({"lang": lang, "level": target_level})
	return {"ok": true, "passed": passed, "score": score, "target": float(target_level)}


func certificates(profile: Dictionary) -> Array:
	if not profile.has("certificates") or typeof(profile["certificates"]) != TYPE_ARRAY:
		profile["certificates"] = []
	return profile["certificates"]


func has_certificate(profile: Dictionary, lang: String, target_level: float) -> bool:
	for c in certificates(profile):
		if c is Dictionary and str((c as Dictionary).get("lang", "")) == lang:
			if absf(float((c as Dictionary).get("level", 0.0)) - float(target_level)) < 0.01:
				return true
	return false


func meets_professional(profile: Dictionary, lang: String, field: String) -> bool:
	if not PROFESSIONAL_TERMS.has(field):
		return false
	return overall(profile, lang) >= float(PROFESSIONAL_TERMS[field])


## 达到门槛后可解锁的职业（移民/外交/翻译）。
func unlocked_careers(profile: Dictionary, lang: String) -> Array:
	var out: Array = []
	var lvl: float = overall(profile, lang)
	for career in CAREER_UNLOCKS.keys():
		if lvl >= float(CAREER_UNLOCKS[career]):
			out.append(career)
	return out


## 交流成功率：等级对难度，本地懂方言降低门槛。
func communication(profile: Dictionary, lang: String, opts: Dictionary = {}) -> Dictionary:
	var lvl: float = overall(profile, lang)
	var dialect_bonus: float = 0.0
	if bool(opts.get("local", false)) and bool(opts.get("knows_dialect", false)):
		dialect_bonus = float(opts.get("dialect_bonus", 15.0))
	var difficulty: float = float(opts.get("difficulty", 50.0))
	var effective: float = lvl + dialect_bonus
	var success: float = clampf(0.5 + (effective - difficulty) / 100.0, 0.0, 1.0)
	return {"ok": true, "effective_level": effective, "success": success, "dialect_bonus": dialect_bonus}


## 语言不通导致误会与关系下降。
func misunderstanding(profile: Dictionary, lang: String, threshold: float) -> Dictionary:
	var lvl: float = overall(profile, lang)
	if lvl >= float(threshold):
		return {"ok": true, "misunderstood": false, "relation_delta": 0.0}
	var severity: float = clampf((float(threshold) - lvl) / maxf(1.0, float(threshold)), 0.0, 1.0)
	return {"ok": true, "misunderstood": true, "relation_delta": -roundf(severity * 20.0)}


# --- 节日民俗 ---

func festivals_on(month: int, day: int) -> Array:
	var out: Array = []
	for f in FESTIVALS:
		var fest: Dictionary = f
		if int(fest["month"]) == month and int(fest["day"]) == day:
			out.append(fest.duplicate(true))
	return out


## 汇总当日节日效果：任一节日歇业则商铺歇业；交通取最低；社交/消费取最高；心情累加。
func festival_effects(month: int, day: int) -> Dictionary:
	var todays: Array = festivals_on(month, day)
	var eff: Dictionary = {
		"festivals": todays, "shops_open": true, "traffic": 1.0,
		"social": 1.0, "mood": 0.0, "spending": 1.0, "is_festival": not todays.is_empty(),
	}
	for f in todays:
		var fest: Dictionary = f
		if not bool(fest.get("shops_open", true)):
			eff["shops_open"] = false
		eff["traffic"] = minf(float(eff["traffic"]), float(fest.get("traffic", 1.0)))
		eff["social"] = maxf(float(eff["social"]), float(fest.get("social", 1.0)))
		eff["mood"] = float(eff["mood"]) + float(fest.get("mood", 0.0))
		eff["spending"] = maxf(float(eff["spending"]), float(fest.get("spending", 1.0)))
	return eff


# --- 文化差异与跨文化 ---

## 两文化社交修正：社交距离与时间观念差距越大，修正越低。
func social_modifier(culture_a: String, culture_b: String) -> float:
	if not CULTURES.has(culture_a) or not CULTURES.has(culture_b):
		return 1.0
	var da: float = float((CULTURES[culture_a] as Dictionary)["social_distance"])
	var db: float = float((CULTURES[culture_b] as Dictionary)["social_distance"])
	var ta: float = float((CULTURES[culture_a] as Dictionary)["time_orientation"])
	var tb: float = float((CULTURES[culture_b] as Dictionary)["time_orientation"])
	var mod: float = 1.0 - absf(da - db) * 0.3 - absf(ta - tb) * 0.3
	if culture_a != culture_b:
		mod -= 0.1
	return clampf(mod, 0.4, 1.0)


func culture_def(culture: String) -> Dictionary:
	if not CULTURES.has(culture):
		return {}
	return (CULTURES[culture] as Dictionary).duplicate(true)


## 新建文化适应状态。
func new_cultural_state() -> Dictionary:
	return {"adaptation": {}, "shock": 0.0}


func current_adaptation(state: Dictionary, culture: String) -> float:
	var a: Variant = state.get("adaptation", {})
	if a is Dictionary:
		return float((a as Dictionary).get(culture, 0.0))
	return 0.0


## 文化冲击与适应曲线：适应度趋近 1，冲击随之下降。
func adapt(state: Dictionary, culture: String, days: float) -> Dictionary:
	if not state.has("adaptation") or typeof(state["adaptation"]) != TYPE_DICTIONARY:
		state["adaptation"] = {}
	var a: Dictionary = state["adaptation"]
	var cur: float = float(a.get(culture, 0.0))
	var gain: float = clampf(1.0 - cur, 0.0, 1.0) * (maxf(0.0, days) / 365.0) * 0.8
	cur = clampf(cur + gain, 0.0, 1.0)
	a[culture] = cur
	state["shock"] = clampf(1.0 - cur, 0.0, 1.0)
	return {"ok": true, "adaptation": cur, "shock": float(state["shock"])}


## 翻译：等级达到难度方可胜任，质量由超出比例决定。
func translate(profile: Dictionary, lang: String, difficulty: float) -> Dictionary:
	var lvl: float = overall(profile, lang)
	var success: bool = lvl >= float(difficulty)
	var quality: float = clampf(lvl / maxf(1.0, float(difficulty)), 0.0, 1.5)
	return {"ok": true, "success": success, "quality": quality, "level": lvl}


## 跨国婚姻和谐度：文化修正 + 双方适应度。
func intercultural_marriage(culture_a: String, culture_b: String, adapt_a: float, adapt_b: float) -> Dictionary:
	var base: float = social_modifier(culture_a, culture_b)
	var harmony: float = clampf(base * 0.5 + (clampf(adapt_a, 0.0, 1.0) + clampf(adapt_b, 0.0, 1.0)) * 0.25, 0.0, 1.0)
	return {"ok": true, "harmony": harmony, "needs_adaptation": harmony < 0.6}


## 文化冲突事件：适应不足时更易发生。
func cultural_conflict(culture_a: String, culture_b: String, adapt_a: float, adapt_b: float, opts: Dictionary = {}, rng = null) -> Dictionary:
	var base: float = social_modifier(culture_a, culture_b)
	var harmony: float = clampf(base * 0.5 + (clampf(adapt_a, 0.0, 1.0) + clampf(adapt_b, 0.0, 1.0)) * 0.25, 0.0, 1.0)
	var conflict_chance: float = clampf((1.0 - harmony) * 0.5, 0.0, 0.5)
	var roll: float = _roll(float(opts.get("roll", -1.0)), rng)
	var conflict: bool = roll < conflict_chance
	return {"ok": true, "conflict": conflict, "chance": conflict_chance, "relation_delta": -15.0 if conflict else 0.0}


func _roll(forced: float, rng) -> float:
	if forced >= 0.0:
		return clampf(forced, 0.0, 1.0)
	if rng != null:
		return rng.next_float()
	return 0.0


func to_dict(profile: Dictionary) -> Dictionary:
	return profile.duplicate(true)


func from_dict(data: Dictionary) -> Dictionary:
	return data.duplicate(true)
