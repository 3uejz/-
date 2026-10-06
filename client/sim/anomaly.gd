class_name AnomalySystem
extends RefCounted
## 隐秘异常收容体系（R88；design D44）。本系统重点在「隔离」与「代价」。
##
## 覆盖：
##   - 隔离架构：独立隐藏状态树（self.state 内 anomaly 子树），默认 hidden=true，
##     不参与常规结算与界面，普通玩法可完全不受影响；
##   - 门闩途径（5）：稀有天赋、隐藏事件链、血脉传承、特殊地点、特殊物品；
##   - SCP 式分级：收容等级 Safe/Euclid/Keter/Thaumiel/Apollyon/Explained/
##     Neutralized/Pending；威胁等级 白/绿/黄/红/黑（与收容等级正交）；
##     危害类型 模因/认知/信息/现实扭曲/时空/生物/物品/超自然；
##     权限 Level 0–5 与 D 级人员，权限决定可查阅与接触的条目；
##   - 组织术语：基金会、O5 议会、站点、收容专家、D 级人员、记忆删除药剂；
##   - 能力线（4）：预知与气运、通灵与驱邪、修炼与异能、术法阵法；等级 0..20，
##     经验来自使用与事件，能力提升同步累积暴露值；修炼/术法耗灵力，
##     预知/通灵耗精神与理智；
##   - 阵营（4）：基金会、异常崇拜、黑实验室、猎魔/掠夺者，各有隐藏声望与任务线；
##   - 玩家身份（5）：基金会人员、异常持有者、研究对象(D级)、独立调查者、知情平民；
##   - 对抗战斗：独立结算，能力等级、法器、气运、认知抗性参与判定，
##     含收容失效与同行争夺；
##   - 认知危害应对：接触模因/认知/信息危害按暴露累积污染；记忆删除药剂可清除，
##     副作用剂量依赖（记忆缺口/部分不可逆/滥用累积），有使用上限；
##   - 暴露与反噬：暴露值达阈值触发 收容/猎杀/封禁/认知污染/精神崩溃；
##   - 异常条目：核心手写常量表 + 确定性生成 generate_entry(seed) + validate_entry；
##   - 图鉴可见性：仅接触后可见，is_known / known_entries；
##   - 传承：异常天赋、血脉与知识可跨代继承（inherit / can_enter）；
##   - 边界：异常与社会事件交叉（误判为犯罪），严重暴露触发不可逆结局。
##
## 设计取舍：
##   - 所有状态为纯 Dictionary，方法可接受「完整状态（含 anomaly 子树）」或
##     「anomaly 子树」本身，便于存读档与 headless 测试；
##   - 一切随机项由外部注入 roll/rng，缺省确定化；
##   - 常规系统永远看不到异常；regular_effects() 在隐藏时恒为空。

const RngScript = preload("res://sim/rng.gd")

# --- 分级与枚举 ---

const CONTAINMENT_KEYS: Array = ["safe", "euclid", "keter", "thaumiel", "apollyon", "explained", "neutralized", "pending"]
const CONTAINMENT_NAMES: Dictionary = {
	"safe": "Safe 安全", "euclid": "Euclid 欧几里得", "keter": "Keter 凯特",
	"thaumiel": "Thaumiel 泰米耶尔", "apollyon": "Apollyon 阿波里昂",
	"explained": "Explained 已解明", "neutralized": "Neutralized 已失效", "pending": "Pending 待定",
}

const THREAT_KEYS: Array = ["white", "green", "yellow", "red", "black"]
const THREAT_NAMES: Dictionary = {"white": "白", "green": "绿", "yellow": "黄", "red": "红", "black": "黑"}
## 威胁等级对暴露的贡献。
const THREAT_EXPOSURE: Dictionary = {"white": 1.0, "green": 3.0, "yellow": 6.0, "red": 12.0, "black": 20.0}

const HAZARD_KEYS: Array = ["meme", "cognition", "info", "reality", "spacetime", "bio", "item", "supernatural"]
const HAZARD_NAMES: Dictionary = {
	"meme": "模因危害", "cognition": "认知危害", "info": "信息危害", "reality": "现实扭曲",
	"spacetime": "时空异常", "bio": "生物", "item": "物品", "supernatural": "超自然",
}
## 危害类型 → 认知污染子类（仅模因/认知/信息累积污染）。
const HAZARD_CONTAM: Dictionary = {"meme": "meme", "cognition": "cognition", "info": "info"}

const GATE_KEYS: Array = ["rare_talent", "hidden_event_chain", "bloodline", "special_place", "special_item"]
## 稀有天赋出生概率（极低）。注入 roll 判定。
const RARE_TALENT_RATE: float = 0.001

const ABILITY_LINES: Array = ["precognition", "medium", "cultivation", "sorcery"]
const ABILITY_NAMES: Dictionary = {
	"precognition": "预知与气运", "medium": "通灵与驱邪",
	"cultivation": "修炼与异能", "sorcery": "术法阵法",
}
## 能力使用资源消耗：precognition/medium 耗精神与理智，cultivation/sorcery 耗灵力。
const ABILITY_COSTS: Dictionary = {
	"precognition": {"mana": 0.0, "spirit": 10.0, "sanity": 5.0},
	"medium": {"mana": 0.0, "spirit": 8.0, "sanity": 8.0},
	"cultivation": {"mana": 12.0, "spirit": 0.0, "sanity": 0.0},
	"sorcery": {"mana": 15.0, "spirit": 0.0, "sanity": 0.0},
}
const ABILITY_MAX_LEVEL: int = 20
const EXP_PER_LEVEL: float = 100.0

const FACTIONS: Dictionary = {
	"foundation": "基金会", "cult": "异常崇拜", "black_lab": "黑实验室", "hunter": "猎魔/掠夺者",
}
const IDENTITIES: Dictionary = {
	"foundation_staff": "基金会人员", "anomaly_holder": "异常持有者",
	"research_subject": "研究对象(D级)", "independent": "独立调查者", "informed_civilian": "知情平民",
}
## 术语本地化改写。
const TERMS: Dictionary = {
	"foundation": "基金会", "o5": "O5 议会", "site": "站点",
	"containment_expert": "收容专家", "d_class": "D 级人员", "amnestic": "记忆删除药剂",
}

# --- 暴露与反噬 ---

const BACKLASH_ORDER: Array = ["contamination", "hunt", "containment", "ban", "breakdown"]
const BACKLASH_THRESHOLDS: Dictionary = {
	"contamination": 40.0, "hunt": 60.0, "containment": 75.0, "ban": 90.0, "breakdown": 100.0,
}
const BACKLASH_NAMES: Dictionary = {
	"contamination": "认知污染", "hunt": "猎杀", "containment": "收容",
	"ban": "封禁", "breakdown": "精神崩溃",
}

## 记忆删除药剂。
const AMNESTIC_DEFAULT_MAX: int = 3
const AMNESTIC_CLEAR_PER_DOSE: float = 40.0

## 目标条目总量（R88.11：不少于 2000，核心手写其余生成）。
const TOTAL_CATALOG_SIZE: int = 2000

# --- 核心手写异常条目（8–15 条示例）---

const CORE_ENTRIES: Dictionary = {
	"异-002": {"id": "异-002", "name": "镜中人", "containment": "euclid", "threat": "green", "hazard": "cognition", "clearance_required": 2, "appearance": "于旧宅镜面显现，模仿照镜者动作延迟半秒", "pattern": "仅在独自照镜且情绪低落时出现", "containment_measures": "封存镜面，禁止单人长时间注视；每周复检", "unlocked": false},
	"异-017": {"id": "异-017", "name": "低语藤", "containment": "euclid", "threat": "yellow", "hazard": "bio", "clearance_required": 2, "appearance": "墙缝中生长的灰白色藤蔓，随风传出低语", "pattern": "夜间活性增强，靠近者产生被呼唤感", "containment_measures": "定期喷施抑制剂，隔离生长区域；佩戴隔音耳塞", "unlocked": false},
	"异-031": {"id": "异-031", "name": "倒走钟", "containment": "keter", "threat": "red", "hazard": "spacetime", "clearance_required": 3, "appearance": "逆时针行走的座钟，指针倒转", "pattern": "每逢整点使三米内时间倒流数秒", "containment_measures": "停摆封存于消磁间；禁止在整点接近", "unlocked": false},
	"异-044": {"id": "异-044", "name": "无面信使", "containment": "euclid", "threat": "yellow", "hazard": "info", "clearance_required": 2, "appearance": "无面孔的邮差，递送没有寄件人的信件", "pattern": "收到信件者会重复信中语句直至遗忘", "containment_measures": "拦截信件并焚毁；对收信者施用记忆删除", "unlocked": false},
	"异-058": {"id": "异-058", "name": "暖手石", "containment": "safe", "threat": "white", "hazard": "item", "clearance_required": 1, "appearance": "始终温热的拳大卵石", "pattern": "贴近者紧张缓解，无其他异常", "containment_measures": "常规物品柜保管，登记借用", "unlocked": false},
	"异-073": {"id": "异-073", "name": "食忆菌", "containment": "keter", "threat": "red", "hazard": "meme", "clearance_required": 4, "appearance": "半透明白色菌毯，蔓延于潮湿墙面", "pattern": "接触者相关记忆被逐层侵蚀，旁人亦受模因波及", "containment_measures": "负压隔离舱；燃烧处理；全员免疫接种", "unlocked": false},
	"异-090": {"id": "异-090", "name": "归乡门", "containment": "apollyon", "threat": "black", "hazard": "reality", "clearance_required": 5, "appearance": "荒野中孤立的旧门框，门后非任何已知地点", "pattern": "开启时改写周边现实，无法安全关闭", "containment_measures": "O5 授权封锁区；禁止开启；常驻站点监控", "unlocked": false},
	"异-104": {"id": "异-104", "name": "静默罩", "containment": "safe", "threat": "green", "hazard": "item", "clearance_required": 1, "appearance": "透明玻璃罩，罩内声音被完全吸收", "pattern": "用于存放高噪声或低风险传声异常", "containment_measures": "作为收容工具使用，定期声学检测", "unlocked": false},
	"异-119": {"id": "异-119", "name": "织梦蛛", "containment": "euclid", "threat": "yellow", "hazard": "cognition", "clearance_required": 3, "appearance": "指尖大小的银白蜘蛛，结出会映出梦境的网", "pattern": "靠近网者共见彼此梦境，易泄露心事", "containment_measures": "单独网箱饲养；禁止在睡眠者附近布网", "unlocked": false},
	"异-133": {"id": "异-133", "name": "影替身", "containment": "thaumiel", "threat": "red", "hazard": "supernatural", "clearance_required": 5, "appearance": "从持有者影子中独立出的替身", "pattern": "可代为承受伤害，但替身受损反噬本体", "containment_measures": "用于对抗高风险异常；签订契约并持续监控", "unlocked": false},
	"异-147": {"id": "异-147", "name": "潮汐客", "containment": "pending", "threat": "yellow", "hazard": "spacetime", "clearance_required": 3, "appearance": "满月夜自海边浅滩浮现的人形", "pattern": "随潮汐往返，行踪与月相相关", "containment_measures": "涨潮前清场并布设临时围栏；持续观察待定", "unlocked": false},
	"异-160": {"id": "异-160", "name": "灰烬书", "containment": "neutralized", "threat": "black", "hazard": "info", "clearance_required": 4, "appearance": "烧毁后仍自行拼合的炭黑书册", "pattern": "曾使读者记忆焚毁，现已被解明并失效", "containment_measures": "归档于已失效区，限研究与历史查阅", "unlocked": false},
	"异-171": {"id": "异-171", "name": "人偶师", "containment": "explained", "threat": "green", "hazard": "bio", "clearance_required": 2, "appearance": "以丝线操纵人偶的表演者", "pattern": "其能力经查为高超技艺与心理暗示，非异常", "containment_measures": "已解明并转为民间艺人管理", "unlocked": false},
}

## 生成条目名用词池（本地化改写）。
const GEN_PREFIX: Array = ["缄默", "灰烬", "倒映", "低语", "锈蚀", "织梦", "潮汐", "静默", "无面", "暖", "归乡", "影"]
const GEN_SUFFIX: Array = ["之物", "之面", "之钟", "之藤", "之信", "之罩", "之蛛", "之门", "之书", "之偶", "之客", "之石"]

var state: Dictionary = {}


func _init() -> void:
	state = new_state()


func _anom(s: Dictionary) -> Dictionary:
	# 支持传入完整状态（含 anomaly 子树）或 anomaly 子树本身。
	var a: Variant = s.get("anomaly", null)
	if a is Dictionary:
		return a
	return s


func new_state() -> Dictionary:
	return {"anomaly": _blank_anomaly()}


func _blank_anomaly() -> Dictionary:
	return {
		"hidden": true,
		"active": false,
		"exposure": 0.0,
		"gates": {
			"rare_talent": false, "hidden_event_chain": false, "bloodline": false,
			"special_place": false, "special_item": false,
		},
		"clearance": 0,
		"is_d_class": false,
		"identity": "",
		"faction": "",
		"faction_reputation": {"foundation": 0.0, "cult": 0.0, "black_lab": 0.0, "hunter": 0.0},
		"abilities": {
			"precognition": {"level": 0, "exp": 0.0},
			"medium": {"level": 0, "exp": 0.0},
			"cultivation": {"level": 0, "exp": 0.0},
			"sorcery": {"level": 0, "exp": 0.0},
		},
		"resources": {"mana": 100.0, "spirit": 100.0, "sanity": 100.0},
		"contamination": {"meme": 0.0, "cognition": 0.0, "info": 0.0},
		"known_entries": {},
		"artifacts": [],
		"fortune": 0.0,
		"cognitive_resistance": 0.0,
		"talents": [],
		"knowledge": {},
		"amnestics": {"uses": 0, "max": AMNESTIC_DEFAULT_MAX, "memory_gaps": 0, "irreversible": 0.0, "addiction": 0.0},
		"missions": {},
		"ending": "",
	}


func _roll(forced: float, rng) -> float:
	if forced >= 0.0:
		return clampf(forced, 0.0, 1.0)
	if rng != null:
		return rng.next_float()
	return 0.0


# --- 隔离与可见性 ---

func is_hidden(s: Dictionary) -> bool:
	return bool(_anom(s).get("hidden", true))


func set_hidden(s: Dictionary, hidden: bool) -> Dictionary:
	_anom(s)["hidden"] = hidden
	return {"ok": true, "hidden": hidden}


func is_active(s: Dictionary) -> bool:
	return bool(_anom(s).get("active", false))


## 常规结算注入点：隐藏或未激活时返回空，保证异常不参与常规结算。
func regular_effects(s: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var a: Dictionary = _anom(s)
	if bool(a.get("hidden", true)) or not bool(a.get("active", false)):
		return {}
	if not bool(opts.get("leak", false)):
		return {}
	return {"exposure": float(a.get("exposure", 0.0)), "ending": str(a.get("ending", ""))}


func terms() -> Dictionary:
	return TERMS.duplicate(true)


# --- 门闩途径 ---

func gate_keys() -> Array:
	return GATE_KEYS.duplicate()


func has_gate(s: Dictionary, path: String) -> bool:
	return bool((_anom(s).get("gates", {}) as Dictionary).get(path, false))


func open_gate(s: Dictionary, path: String, opts: Dictionary = {}) -> Dictionary:
	if not GATE_KEYS.has(path):
		return {"ok": false, "reason": "unknown_gate"}
	var a: Dictionary = _anom(s)
	(a["gates"] as Dictionary)[path] = true
	a["active"] = true
	return {"ok": true, "gate": path, "active": true, "gates": (a["gates"] as Dictionary).duplicate(true)}


## 稀有天赋判定：极低概率出生，注入 roll 判定。
func roll_rare_talent(roll: float) -> bool:
	return clampf(roll, 0.0, 1.0) < RARE_TALENT_RATE


func rare_talent_check(s: Dictionary, roll: float, opts: Dictionary = {}) -> Dictionary:
	var born: bool = roll_rare_talent(roll)
	if born:
		open_gate(s, "rare_talent")
	return {"ok": true, "born_with_talent": born, "roll": clampf(roll, 0.0, 1.0), "rate": RARE_TALENT_RATE}


## 是否可进入异常世界：激活或存在任一已开启门闩。
func can_enter(s: Dictionary) -> bool:
	var a: Dictionary = _anom(s)
	if bool(a.get("active", false)):
		return true
	for path in GATE_KEYS:
		if bool((a.get("gates", {}) as Dictionary).get(path, false)):
			return true
	return false


# --- 权限、身份与阵营 ---

func clearance_level(s: Dictionary) -> int:
	return clampi(int(_anom(s).get("clearance", 0)), 0, 5)


func set_clearance(s: Dictionary, level: int) -> Dictionary:
	_anom(s)["clearance"] = clampi(level, 0, 5)
	return {"ok": true, "clearance": clearance_level(s)}


func set_d_class(s: Dictionary, is_d: bool) -> Dictionary:
	_anom(s)["is_d_class"] = is_d
	return {"ok": true, "is_d_class": is_d}


func is_d_class(s: Dictionary) -> bool:
	return bool(_anom(s).get("is_d_class", false))


func identities() -> Array:
	return IDENTITIES.keys()


func identity_name(key: String) -> String:
	return str(IDENTITIES.get(key, key))


func set_identity(s: Dictionary, identity: String) -> Dictionary:
	if not IDENTITIES.has(identity):
		return {"ok": false, "reason": "unknown_identity"}
	_anom(s)["identity"] = identity
	return {"ok": true, "identity": identity, "name": identity_name(identity)}


func factions() -> Array:
	return FACTIONS.keys()


func faction_name(key: String) -> String:
	return str(FACTIONS.get(key, key))


func join_faction(s: Dictionary, faction: String, opts: Dictionary = {}) -> Dictionary:
	if not FACTIONS.has(faction):
		return {"ok": false, "reason": "unknown_faction"}
	var a: Dictionary = _anom(s)
	a["faction"] = faction
	(a["faction_reputation"] as Dictionary)[faction] = float(opts.get("reputation", 0.0))
	return {"ok": true, "faction": faction, "name": faction_name(faction)}


func faction_reputation(s: Dictionary, faction: String) -> float:
	return float((_anom(s).get("faction_reputation", {}) as Dictionary).get(faction, 0.0))


func _add_faction_rep(a: Dictionary, faction: String, delta: float) -> void:
	var rep: Dictionary = a["faction_reputation"]
	rep[faction] = float(rep.get(faction, 0.0)) + delta


func accept_mission(s: Dictionary, mission_id: String, faction: String, opts: Dictionary = {}) -> Dictionary:
	if not FACTIONS.has(faction):
		return {"ok": false, "reason": "unknown_faction"}
	(_anom(s).get("missions", {}) as Dictionary)[mission_id] = {"faction": faction, "status": "active", "reward": float(opts.get("reward", 10.0))}
	return {"ok": true, "mission_id": mission_id, "faction": faction, "status": "active"}


func complete_mission(s: Dictionary, mission_id: String, opts: Dictionary = {}) -> Dictionary:
	var a: Dictionary = _anom(s)
	var missions: Dictionary = a["missions"]
	if not missions.has(mission_id):
		return {"ok": false, "reason": "unknown_mission"}
	var m: Dictionary = missions[mission_id]
	var success: bool = bool(opts.get("success", true))
	m["status"] = "completed" if success else "failed"
	var reward: float = float(m.get("reward", 0.0)) if success else -float(m.get("reward", 0.0)) * 0.5
	_add_faction_rep(a, str(m.get("faction", "")), reward)
	return {"ok": true, "mission_id": mission_id, "status": str(m["status"]), "reputation": faction_reputation(s, str(m.get("faction", "")))}


# --- 能力线 ---

func ability_keys() -> Array:
	return ABILITY_LINES.duplicate()


func ability_name(line: String) -> String:
	return str(ABILITY_NAMES.get(line, line))


func ability_level(s: Dictionary, line: String) -> int:
	return int((_anom(s).get("abilities", {}).get(line, {}) as Dictionary).get("level", 0))


func ability_exp(s: Dictionary, line: String) -> float:
	return float((_anom(s).get("abilities", {}).get(line, {}) as Dictionary).get("exp", 0.0))


func _level_from_exp(exp: float) -> int:
	return clampi(int(exp / EXP_PER_LEVEL), 0, ABILITY_MAX_LEVEL)


## 获得经验并可能升级；能力提升同步累积暴露值。
func gain_exp(s: Dictionary, line: String, amount: float, opts: Dictionary = {}) -> Dictionary:
	if not ABILITY_LINES.has(line):
		return {"ok": false, "reason": "unknown_ability"}
	var a: Dictionary = _anom(s)
	var ab: Dictionary = a["abilities"][line]
	var before: int = int(ab.get("level", 0))
	ab["exp"] = float(ab.get("exp", 0.0)) + maxf(0.0, amount)
	ab["level"] = _level_from_exp(float(ab["exp"]))
	var gained: int = int(ab["level"]) - before
	var exposure_gain: float = maxf(0.0, amount) * float(opts.get("exposure_factor", 0.1))
	a["exposure"] = float(a.get("exposure", 0.0)) + exposure_gain
	return {
		"ok": true, "line": line, "level": int(ab["level"]), "exp": float(ab["exp"]),
		"level_gain": gained, "exposure_gain": exposure_gain, "exposure": float(a["exposure"]),
	}


## 使用能力：消耗资源、获得经验、累积暴露值。资源不足则拒绝。
func use_ability(s: Dictionary, line: String, opts: Dictionary = {}, rng = null) -> Dictionary:
	if not ABILITY_LINES.has(line):
		return {"ok": false, "reason": "unknown_ability"}
	var a: Dictionary = _anom(s)
	var cost: Dictionary = ABILITY_COSTS[line]
	var res: Dictionary = a["resources"]
	for key in ["mana", "spirit", "sanity"]:
		if float(res.get(key, 0.0)) < float(cost.get(key, 0.0)):
			return {"ok": false, "reason": "insufficient_" + key}
	for key in ["mana", "spirit", "sanity"]:
		res[key] = maxf(0.0, float(res.get(key, 0.0)) - float(cost.get(key, 0.0)))
	var exp_gain: float = float(opts.get("exp", 10.0))
	var gain: Dictionary = gain_exp(s, line, exp_gain, {"exposure_factor": opts.get("exposure_factor", 0.2)})
	var level: int = ability_level(s, line)
	var effect: float = clampf(float(level) / float(ABILITY_MAX_LEVEL) + float(opts.get("bonus", 0.0)), 0.0, 1.0)
	return {
		"ok": true, "line": line, "name": ability_name(line), "level": level,
		"effect_strength": effect, "exp": float(gain["exp"]),
		"resources": res.duplicate(), "exposure": float(a["exposure"]),
	}


# --- 暴露、污染与记忆删除药剂 ---

func exposure(s: Dictionary) -> float:
	return float(_anom(s).get("exposure", 0.0))


func add_exposure(s: Dictionary, amount: float) -> float:
	var a: Dictionary = _anom(s)
	a["exposure"] = maxf(0.0, float(a.get("exposure", 0.0)) + amount)
	return float(a["exposure"])


func exposure_tier(s: Dictionary) -> String:
	var e: float = exposure(s)
	var tier: String = ""
	for key in BACKLASH_ORDER:
		if e >= float(BACKLASH_THRESHOLDS[key]):
			tier = key
	return tier


## 暴露反噬：达阈值触发 认知污染/猎杀/收容/封禁/精神崩溃 中最严重者。
func check_backlash(s: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var e: float = exposure(s)
	var tier: String = exposure_tier(s)
	if tier == "":
		return {"ok": true, "triggered": false, "type": "", "name": "", "exposure": e}
	var a: Dictionary = _anom(s)
	var irreversible: bool = tier == "breakdown" or tier == "ban"
	if tier == "breakdown":
		a["ending"] = "breakdown"
	elif tier == "ban":
		a["ending"] = "ban"
	return {
		"ok": true, "triggered": true, "type": tier, "name": str(BACKLASH_NAMES[tier]),
		"exposure": e, "irreversible": irreversible, "ending": str(a.get("ending", "")),
	}


func ending(s: Dictionary) -> String:
	return str(_anom(s).get("ending", ""))


func hazard_types() -> Array:
	return HAZARD_KEYS.duplicate()


func hazard_name(key: String) -> String:
	return str(HAZARD_NAMES.get(key, key))


func contamination(s: Dictionary) -> Dictionary:
	return (_anom(s).get("contamination", {}) as Dictionary).duplicate(true)


func contamination_total(s: Dictionary) -> float:
	var total: float = 0.0
	for v in _anom(s).get("contamination", {}).values():
		total += float(v)
	return total


## 接触危害：模因/认知/信息累积认知污染，其余类型累积暴露值。
func contact_hazard(s: Dictionary, hazard_type: String, intensity: float = 1.0, opts: Dictionary = {}) -> Dictionary:
	if not HAZARD_KEYS.has(hazard_type):
		return {"ok": false, "reason": "unknown_hazard"}
	var a: Dictionary = _anom(s)
	var amt: float = maxf(0.0, intensity) * float(opts.get("mult", 1.0))
	var cognitive: bool = HAZARD_CONTAM.has(hazard_type)
	if cognitive:
		var key: String = str(HAZARD_CONTAM[hazard_type])
		var c: Dictionary = a["contamination"]
		c[key] = maxf(0.0, float(c.get(key, 0.0)) + amt)
	a["exposure"] = float(a.get("exposure", 0.0)) + amt * 0.5
	return {
		"ok": true, "hazard_type": hazard_type, "cognitive": cognitive,
		"added": amt, "contamination": (a["contamination"] as Dictionary).duplicate(true),
		"contamination_total": contamination_total(s), "exposure": float(a["exposure"]),
	}


func amnestic_status(s: Dictionary) -> Dictionary:
	return (_anom(s).get("amnestics", {}) as Dictionary).duplicate(true)


## 记忆删除药剂：清除认知污染，副作用剂量依赖，且受使用上限约束。
## dose 0..1；dose 越高清除越多，但记忆缺口、不可逆与成瘾副作用越重。
func amnestics(s: Dictionary, dose: float = 0.5, opts: Dictionary = {}, rng = null) -> Dictionary:
	var a: Dictionary = _anom(s)
	var am: Dictionary = a["amnestics"]
	var max_uses: int = int(am.get("max", AMNESTIC_DEFAULT_MAX))
	if int(am.get("uses", 0)) >= max_uses and not bool(opts.get("overdose", false)):
		return {
			"ok": false, "reason": "limit_reached",
			"uses": int(am.get("uses", 0)), "max": max_uses,
		}
	var d: float = clampf(dose, 0.0, 1.0)
	var clear: float = d * AMNESTIC_CLEAR_PER_DOSE
	var remaining: float = clear
	var c: Dictionary = a["contamination"]
	for key in ["meme", "cognition", "info"]:
		if remaining <= 0.0:
			break
		var take: float = minf(float(c.get(key, 0.0)), remaining)
		c[key] = float(c.get(key, 0.0)) - take
		remaining -= take
	var cleared: float = clear - remaining
	# 副作用剂量依赖。
	var gaps: int = int(round(d * 10.0))
	if d > 0.0 and gaps == 0:
		gaps = 1
	am["memory_gaps"] = int(am.get("memory_gaps", 0)) + gaps
	am["irreversible"] = clampf(float(am.get("irreversible", 0.0)) + (d if d > 0.7 else 0.0), 0.0, 1.0)
	am["addiction"] = clampf(float(am.get("addiction", 0.0)) + 0.2 + d * 0.3, 0.0, 1.0)
	am["uses"] = int(am.get("uses", 0)) + 1
	return {
		"ok": true, "dose": d, "cleared": cleared,
		"contamination_total": contamination_total(s),
		"memory_gaps": int(am["memory_gaps"]), "irreversible": float(am["irreversible"]),
		"addiction": float(am["addiction"]), "uses": int(am["uses"]), "max": max_uses,
	}


# --- 对抗战斗 ---

func _combat_power(s: Dictionary) -> float:
	var a: Dictionary = _anom(s)
	var power: float = 0.0
	for line in ABILITY_LINES:
		power += float((a["abilities"][line] as Dictionary).get("level", 0))
	power += float(a.get("fortune", 0.0)) * 2.0
	power += (a.get("artifacts", []) as Array).size() * 3.0
	power += float(a.get("cognitive_resistance", 0.0))
	return power


## 独立对抗结算：能力等级、法器、气运、认知抗性参与判定；含同行争夺与收容失效。
func resolve_combat(attacker: Dictionary, defender: Dictionary, opts: Dictionary = {}, rng = null) -> Dictionary:
	var atk: float = _combat_power(attacker) + float(opts.get("attacker_bonus", 0.0))
	var dfn: float = _combat_power(defender) + float(opts.get("defender_bonus", 0.0))
	var win_prob: float = clampf(0.5 + (atk - dfn) * 0.03, 0.05, 0.95)
	var roll: float = _roll(float(opts.get("roll", -1.0)), rng)
	var attacker_wins: bool = roll < win_prob
	var breach: bool = bool(opts.get("contest_containment", false))
	if breach:
		add_exposure(attacker, 5.0)
		add_exposure(defender, 5.0)
	return {
		"ok": true, "attacker_wins": attacker_wins, "defender_wins": not attacker_wins,
		"win_probability": win_prob, "roll": roll, "attacker_power": atk, "defender_power": dfn,
		"contest_type": str(opts.get("contest_type", "rival")),
		"containment_breach": breach,
	}


## 收容失效：异常挣脱，全员暴露上升。
func trigger_containment_breach(s: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var add: float = float(opts.get("exposure", 20.0))
	add_exposure(s, add)
	return {"ok": true, "breach": true, "exposure_gain": add, "exposure": exposure(s)}


# --- 异常条目与图鉴 ---

func core_catalog_size() -> int:
	return CORE_ENTRIES.size()


func catalog_size() -> int:
	return maxi(TOTAL_CATALOG_SIZE, CORE_ENTRIES.size())


func core_entries() -> Dictionary:
	return CORE_ENTRIES.duplicate(true)


func containment_levels() -> Array:
	return CONTAINMENT_KEYS.duplicate()


func containment_name(key: String) -> String:
	return str(CONTAINMENT_NAMES.get(key, key))


func threat_levels() -> Array:
	return THREAT_KEYS.duplicate()


func threat_name(key: String) -> String:
	return str(THREAT_NAMES.get(key, key))


func entry(entry_id: String) -> Dictionary:
	if CORE_ENTRIES.has(entry_id):
		return (CORE_ENTRIES[entry_id] as Dictionary).duplicate(true)
	return {}


## 确定性生成异常条目（受 seed 唯一决定）。
func generate_entry(seed: int) -> Dictionary:
	var rng = RngScript.new(seed)
	var ci: int = int(rng.next_float() * float(CONTAINMENT_KEYS.size()))
	ci = clampi(ci, 0, CONTAINMENT_KEYS.size() - 1)
	var ti: int = int(rng.next_float() * float(THREAT_KEYS.size()))
	ti = clampi(ti, 0, THREAT_KEYS.size() - 1)
	var hi: int = int(rng.next_float() * float(HAZARD_KEYS.size()))
	hi = clampi(hi, 0, HAZARD_KEYS.size() - 1)
	var pi: int = int(rng.next_float() * float(GEN_PREFIX.size()))
	pi = clampi(pi, 0, GEN_PREFIX.size() - 1)
	var si: int = int(rng.next_float() * float(GEN_SUFFIX.size()))
	si = clampi(si, 0, GEN_SUFFIX.size() - 1)
	var number: int = int(absf(float(seed))) % TOTAL_CATALOG_SIZE + 1
	var clearance: int = clampi(int(rng.next_float() * 6.0), 0, 5)
	return {
		"id": "异-%04d" % number,
		"name": str(GEN_PREFIX[pi]) + str(GEN_SUFFIX[si]),
		"containment": str(CONTAINMENT_KEYS[ci]),
		"threat": str(THREAT_KEYS[ti]),
		"hazard": str(HAZARD_KEYS[hi]),
		"clearance_required": clearance,
		"appearance": "由生成器产出的异常现象，编号 %04d" % number,
		"pattern": "出现规律与收容等级相关，需要人工复核",
		"containment_measures": "按 %s 级流程收容，定期校验" % str(CONTAINMENT_NAMES[CONTAINMENT_KEYS[ci]]),
		"unlocked": false,
		"generated": true,
	}


## 人工校验钩子：缺字段或非法枚举返回错误。
func validate_entry(e: Dictionary) -> Dictionary:
	var errors: Array = []
	var required: Array = ["id", "name", "containment", "threat", "hazard", "appearance", "pattern", "containment_measures"]
	for field in required:
		if not e.has(field):
			errors.append("missing:" + field)
		elif e[field] is String and str(e[field]) == "":
			errors.append("empty:" + field)
	if e.has("containment") and not CONTAINMENT_KEYS.has(str(e["containment"])):
		errors.append("invalid:containment")
	if e.has("threat") and not THREAT_KEYS.has(str(e["threat"])):
		errors.append("invalid:threat")
	if e.has("hazard") and not HAZARD_KEYS.has(str(e["hazard"])):
		errors.append("invalid:hazard")
	if e.has("clearance_required"):
		var clr: int = int(e["clearance_required"])
		if clr < 0 or clr > 5:
			errors.append("invalid:clearance_required")
	return {"ok": errors.is_empty(), "errors": errors}


func known_entries(s: Dictionary) -> Array:
	return (_anom(s).get("known_entries", {}) as Dictionary).keys()


func is_known(s: Dictionary, entry_id: String) -> bool:
	return (_anom(s).get("known_entries", {}) as Dictionary).has(entry_id)


## 权限判定：Level 0–5 或 D 级人员（D 级可接触但默认不查阅）。
func can_access(s: Dictionary, e: Dictionary, opts: Dictionary = {}) -> bool:
	var a: Dictionary = _anom(s)
	if bool(a.get("is_d_class", false)) and bool(opts.get("allow_d_class", true)):
		return true
	return clearance_level(s) >= int(e.get("clearance_required", 0))


func _resolve_entry(entry_or_id: Variant, opts: Dictionary) -> Dictionary:
	if entry_or_id is Dictionary:
		return (entry_or_id as Dictionary).duplicate(true)
	if entry_or_id is String:
		var core: Dictionary = entry(str(entry_or_id))
		if not core.is_empty():
			return core
		if opts.has("generated_seed"):
			return generate_entry(int(opts["generated_seed"]))
	return {}


## 接触异常条目：需权限；接触后才写入图鉴（unlocked/known）。
func encounter(s: Dictionary, entry_or_id: Variant, opts: Dictionary = {}) -> Dictionary:
	var e: Dictionary = _resolve_entry(entry_or_id, opts)
	if e.is_empty():
		return {"ok": false, "reason": "unknown_entry"}
	if not can_access(s, e, opts) and not bool(opts.get("ignore_clearance", false)):
		return {"ok": false, "reason": "insufficient_clearance", "entry": e, "known": is_known(s, str(e["id"]))}
	var a: Dictionary = _anom(s)
	var known: Dictionary = a["known_entries"]
	var newly_known: bool = not known.has(str(e["id"]))
	known[str(e["id"])] = true
	var threat: String = str(e.get("threat", "white"))
	var hazard: String = str(e.get("hazard", "item"))
	var exp_gain: float = float(THREAT_EXPOSURE.get(threat, 1.0))
	contact_hazard(s, hazard, float(opts.get("hazard_intensity", 1.0)))
	add_exposure(s, exp_gain)
	return {
		"ok": true, "entry": e, "newly_known": newly_known,
		"known": true, "exposure": exposure(s), "contamination_total": contamination_total(s),
	}


# --- 传承 ---

## 跨代继承：天赋、血脉与知识可继承；普通路线（无门闩/天赋/知识）不被触发。
func inherit(giver: Dictionary, heir: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var g: Dictionary = _anom(giver)
	var h: Dictionary = _anom(heir)
	var ratio: float = clampf(float(opts.get("ability_ratio", 0.5)), 0.0, 1.0)
	# 天赋继承。
	var talents: Array = (h.get("talents", []) as Array).duplicate()
	for t in g.get("talents", []):
		if not talents.has(t):
			talents.append(t)
	h["talents"] = talents
	# 血脉：稀有天赋或血脉门闩可继承，并据此激活。
	var blood: bool = bool((g.get("gates", {}) as Dictionary).get("rare_talent", false)) or bool((g.get("gates", {}) as Dictionary).get("bloodline", false))
	if blood:
		(h["gates"] as Dictionary)["bloodline"] = true
	# 知识继承。
	var know: Dictionary = (h.get("knowledge", {}) as Dictionary).duplicate()
	for k in g.get("knowledge", {}):
		know[k] = g["knowledge"][k]
	h["knowledge"] = know
	# 能力等级按比例继承（不高于继承者原有）。
	for line in ABILITY_LINES:
		var inherited_level: int = int(float((g["abilities"][line] as Dictionary).get("level", 0)) * ratio)
		if inherited_level > int((h["abilities"][line] as Dictionary).get("level", 0)):
			(h["abilities"][line] as Dictionary)["level"] = inherited_level
	# 继承不无条件激活；仅血脉/天赋传承者可达异常世界。
	if blood:
		h["active"] = true
	return {
		"ok": true, "bloodline": blood, "talents": talents,
		"inherited_knowledge": know.keys(), "active": bool(h.get("active", false)),
		"can_enter": can_enter(h), "heir": h,
	}


# --- 边界情况 ---

## 异常与社会事件交叉：异常导致事故可能被常规系统误判为犯罪。
## 返回标记供犯罪/司法系统消费，避免误判。
func misjudged_as_crime(s: Dictionary, event: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var anomaly_involved: bool = bool(event.get("anomaly_caused", false)) or (exposure(s) >= 40.0)
	return {
		"ok": true,
		"anomaly_involved": anomaly_involved,
		"misjudged_as_crime": anomaly_involved and bool(opts.get("regular_system_blind", true)),
		"flag": "anomaly_override" if anomaly_involved else "",
		"crime_system_hint": "suppress_charge" if anomaly_involved else "none",
	}


# --- 序列化 ---

func to_dict(s: Dictionary) -> Dictionary:
	return s.duplicate(true)


func from_dict(data: Dictionary) -> Dictionary:
	return data.duplicate(true)
