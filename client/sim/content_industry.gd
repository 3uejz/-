class_name ContentIndustrySystem
extends RefCounted
## 文娱内容产业（R90；design D46）。
##
## 覆盖：
##   - 创作：游戏研发、动漫制作、网络文学、影视、综艺、音乐制作，含创作团队与项目管理；
##   - 发行与变现：平台分成、票务、播放量/销量、付费订阅、广告；口碑影响后续作品；
##   - IP 运营：改编、周边、授权、版权交易与 IP 宇宙衍生（联动 D25，不重复版权诉讼）；
##   - 风险：抄袭、涉政/违规、翻车触发下架、处罚与舆情；
##   - 经营：开设工作室、组建团队、融资，爆款与扑街；
##   - 边界：团队挖角、版号/审查延误、粉丝文化与饭圈（联动 D23）。
##
## 设计取舍：
##   - 工作室、作品、IP 均为纯数据 Dictionary，便于存读档与 headless 测试；
##   - 作品质量由团队技能、预算、项目管理与注入 roll 共同决定，缺省确定化；
##   - 收入按渠道分别建模（平台抽成 / 票务 / 订阅 / 广告 / 销量），公式简单可解释；
##   - 与既有系统解耦：政治审查、饭圈舆情、公司经营以入参或结构化返回值交给上层编排。

## 内容类型：基准预算、基准开发天数、主要变现渠道与质量难度。
const CONTENT_TYPES: Dictionary = {
	"game": {"name": "游戏研发", "base_budget": 5000000, "base_days": 240.0, "difficulty": 0.7,
		"channels": ["platform_share", "advertising", "sales"]},
	"anime": {"name": "动漫制作", "base_budget": 3000000, "base_days": 180.0, "difficulty": 0.6,
		"channels": ["platform_share", "subscription", "advertising"]},
	"webnovel": {"name": "网络文学", "base_budget": 200000, "base_days": 90.0, "difficulty": 0.4,
		"channels": ["subscription", "advertising", "sales"]},
	"film": {"name": "影视", "base_budget": 8000000, "base_days": 150.0, "difficulty": 0.75,
		"channels": ["ticketing", "platform_share", "advertising"]},
	"variety": {"name": "综艺", "base_budget": 4000000, "base_days": 60.0, "difficulty": 0.5,
		"channels": ["advertising", "platform_share", "ticketing"]},
	"music": {"name": "音乐制作", "base_budget": 500000, "base_days": 45.0, "difficulty": 0.45,
		"channels": ["platform_share", "ticketing", "sales"]},
}

## 创作团队角色：雇工成本、月薪与基准技能。
const CREATION_ROLES: Dictionary = {
	"producer": {"name": "制作人", "hire_cost": 200000, "wage": 400000, "skill": 0.5},
	"design": {"name": "策划", "hire_cost": 120000, "wage": 250000, "skill": 0.5},
	"art": {"name": "美术", "hire_cost": 100000, "wage": 220000, "skill": 0.5},
	"engineering": {"name": "程序", "hire_cost": 150000, "wage": 320000, "skill": 0.5},
	"writing": {"name": "编剧文案", "hire_cost": 80000, "wage": 180000, "skill": 0.5},
	"audio": {"name": "音乐音效", "hire_cost": 80000, "wage": 180000, "skill": 0.5},
	"operations": {"name": "运营宣发", "hire_cost": 90000, "wage": 200000, "skill": 0.5},
}

## 各内容类型对各角色的技能权重（用于汇总团队技能）。
const TYPE_ROLE_WEIGHTS: Dictionary = {
	"game": {"producer": 0.15, "design": 0.25, "art": 0.20, "engineering": 0.30, "audio": 0.10},
	"anime": {"producer": 0.15, "art": 0.30, "writing": 0.20, "audio": 0.15, "engineering": 0.20},
	"webnovel": {"writing": 0.70, "producer": 0.15, "operations": 0.15},
	"film": {"producer": 0.15, "writing": 0.25, "art": 0.20, "audio": 0.15, "operations": 0.25},
	"variety": {"producer": 0.20, "writing": 0.20, "operations": 0.40, "art": 0.20},
	"music": {"audio": 0.50, "writing": 0.20, "producer": 0.15, "operations": 0.15},
}

## 变现渠道：可适用的内容类型。
const CHANNELS: Dictionary = {
	"platform_share": {"name": "平台分成", "types": ["game", "anime", "film", "variety", "music", "webnovel"]},
	"ticketing": {"name": "票务", "types": ["film", "variety", "music"]},
	"subscription": {"name": "付费订阅", "types": ["webnovel", "anime", "music"]},
	"advertising": {"name": "广告", "types": ["game", "film", "variety", "webnovel", "music", "anime"]},
	"sales": {"name": "销量", "types": ["game", "music", "webnovel"]},
}

## 发行平台：抽成比例。
const PLATFORMS: Dictionary = {
	"appstore": {"name": "应用商店", "cut_rate": 0.30},
	"video": {"name": "视频平台", "cut_rate": 0.40},
	"cinema": {"name": "院线", "cut_rate": 0.50},
	"reading": {"name": "阅读平台", "cut_rate": 0.30},
	"music": {"name": "音乐平台", "cut_rate": 0.30},
	"tv": {"name": "电视台", "cut_rate": 0.20},
}

## IP 运营方式：基准收益倍率与是否消耗一次授权。
const IP_OPERATIONS: Dictionary = {
	"adaptation": {"name": "改编", "mult": 0.60, "consumes": false},
	"merchandise": {"name": "周边", "mult": 0.35, "consumes": false},
	"licensing": {"name": "授权", "mult": 0.25, "consumes": true},
	"copyright_trade": {"name": "版权交易", "mult": 1.20, "consumes": true},
}

## 融资轮次。
const FUNDING_STAGES: Array = ["seed", "angel", "a", "b", "c"]

var _seq: int = 0


func _roll(forced: float, rng) -> float:
	if forced >= 0.0:
		return clampf(forced, 0.0, 1.0)
	if rng != null:
		return rng.next_float()
	return 0.0


# --- 数据表 ---

func content_type_keys() -> Array:
	return CONTENT_TYPES.keys()


func content_type_def(key: String) -> Dictionary:
	if not CONTENT_TYPES.has(key):
		return {}
	return (CONTENT_TYPES[key] as Dictionary).duplicate(true)


func content_type_name(key: String) -> String:
	return str((CONTENT_TYPES.get(key, {}) as Dictionary).get("name", key))


func role_keys() -> Array:
	return CREATION_ROLES.keys()


func role_def(key: String) -> Dictionary:
	if not CREATION_ROLES.has(key):
		return {}
	return (CREATION_ROLES[key] as Dictionary).duplicate(true)


func channel_keys() -> Array:
	return CHANNELS.keys()


func channel_def(key: String) -> Dictionary:
	if not CHANNELS.has(key):
		return {}
	return (CHANNELS[key] as Dictionary).duplicate(true)


func platform_def(key: String) -> Dictionary:
	if not PLATFORMS.has(key):
		return {}
	return (PLATFORMS[key] as Dictionary).duplicate(true)


func ip_operation_keys() -> Array:
	return IP_OPERATIONS.keys()


## 某内容类型推荐（或允许）的变现渠道。
func channels_for(content_type: String) -> Array:
	if not CONTENT_TYPES.has(content_type):
		return []
	return (CONTENT_TYPES[content_type] as Dictionary)["channels"].duplicate()


# --- 工作室与团队 ---

## 开设工作室。
func new_studio(opts: Dictionary = {}) -> Dictionary:
	_seq += 1
	return {
		"id": str(opts.get("id", "studio.%d" % _seq)),
		"name": str(opts.get("name", "文娱工作室")),
		"money": maxi(0, int(opts.get("money", 2000000))),
		"team": {},
		"catalog": [],
		"ip_library": {},
		"reputation": clampf(float(opts.get("reputation", 0.5)), 0.0, 1.0),
		"fandom": {"size": maxi(0, int(opts.get("fandom_size", 0))), "loyalty": 0.5, "toxicity": 0.0},
		"financing": {"stage": "", "raised": 0, "valuation": 0},
	}


## 雇佣团队成员：成本 = 雇工成本 × 人数；技能按加权平均合并。
func hire(studio: Dictionary, role: String, count: int, opts: Dictionary = {}) -> Dictionary:
	if not CREATION_ROLES.has(role):
		return {"ok": false, "reason": "unknown_role"}
	var n: int = maxi(0, count)
	if n <= 0:
		return {"ok": false, "reason": "bad_count"}
	var per: int = int((CREATION_ROLES[role] as Dictionary)["hire_cost"])
	var cost: int = per * n
	if int(studio.get("money", 0)) < cost:
		return {"ok": false, "reason": "insufficient_funds", "cost": cost}
	studio["money"] = int(studio["money"]) - cost
	var merged: Dictionary = _add_team_member(studio, role, n, float(opts.get("skill", (CREATION_ROLES[role] as Dictionary)["skill"])))
	return {"ok": true, "role": role, "count": int(merged["count"]), "cost": cost, "skill": float(merged["skill"])}


## 向工作室团队加入成员（不涉及成本），供雇佣与挖角复用。
func _add_team_member(studio: Dictionary, role: String, count: int, skill: float) -> Dictionary:
	var n: int = maxi(0, count)
	var team: Dictionary = studio["team"]
	var entry: Dictionary = team.get(role, {"count": 0, "skill": clampf(skill, 0.0, 1.0)})
	var old_count: int = int(entry.get("count", 0))
	var new_count: int = old_count + n
	var blended: float = (float(entry.get("skill", 0.5)) * float(old_count) + clampf(skill, 0.0, 1.0) * float(n)) / maxi(1, new_count)
	entry["count"] = new_count
	entry["skill"] = clampf(blended, 0.0, 1.0)
	team[role] = entry
	studio["team"] = team
	return entry


func fire(studio: Dictionary, role: String, count: int) -> Dictionary:
	if not CREATION_ROLES.has(role):
		return {"ok": false, "reason": "unknown_role"}
	var team: Dictionary = studio["team"]
	if not team.has(role):
		return {"ok": false, "reason": "none_employed"}
	var entry: Dictionary = team[role]
	entry["count"] = maxi(0, int(entry.get("count", 0)) - maxi(0, count))
	team[role] = entry
	studio["team"] = team
	return {"ok": true, "role": role, "count": int(entry["count"])}


## 团队对某内容类型的加权技能（0..1）。无团队时返回 0。
func team_skill(studio: Dictionary, content_type: String) -> float:
	if not TYPE_ROLE_WEIGHTS.has(content_type):
		return 0.0
	var weights: Dictionary = TYPE_ROLE_WEIGHTS[content_type]
	var team: Dictionary = studio.get("team", {})
	var total: float = 0.0
	var weight_sum: float = 0.0
	for role in weights.keys():
		var w: float = float(weights[role])
		weight_sum += w
		var entry: Dictionary = team.get(role, {})
		if int(entry.get("count", 0)) > 0:
			total += w * clampf(float(entry.get("skill", 0.0)), 0.0, 1.0)
	if weight_sum <= 0.0:
		return 0.0
	return clampf(total / weight_sum, 0.0, 1.0)


# --- 创作与项目管理 ---

## 立项新作品。
func new_work(work_id: String, content_type: String, opts: Dictionary = {}) -> Dictionary:
	if not CONTENT_TYPES.has(content_type):
		return {"ok": false, "reason": "unknown_content_type"}
	var def: Dictionary = CONTENT_TYPES[content_type]
	var needed: float = maxf(1.0, float(opts.get("required_days", def["base_days"])))
	return {
		"ok": true,
		"work": {
			"id": work_id,
			"type": content_type,
			"title": str(opts.get("title", work_id)),
			"budget": maxi(0, int(opts.get("budget", int(def["base_budget"])))),
			"spent": 0,
			"progress": 0.0,
			"required_progress": needed,
			"quality": 0.0,
			"hype": clampf(float(opts.get("hype", 0.3)), 0.0, 1.0),
			"management": clampf(float(opts.get("management", 0.5)), 0.0, 1.0),
			"controversy": 0.0,
			"status": "in_progress",
			"released": false,
			"revenue": 0,
			"ip_id": "",
			"plagiarized": false,
			"violations": [],
		},
	}


## 项目管理：调整进度速率与质量增益（管理效率 0..1）。
func project_management(work: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var m: float = clampf(float(opts.get("management", work.get("management", 0.5))), 0.0, 1.0)
	work["management"] = m
	var speed: float = 0.8 + m * 0.4
	return {"ok": true, "management": m, "speed_mult": speed, "quality_bonus": m * 0.1}


## 推进创作：进度 += 天数 × 速度；完成时结算质量。
## 质量 = 团队技能 + 预算充足度 + 项目管理 + 注入 roll − 类型难度。
func advance_project(work: Dictionary, studio: Dictionary, days: float, opts: Dictionary = {}, rng = null) -> Dictionary:
	if str(work.get("status", "")) == "released":
		return {"ok": false, "reason": "already_released"}
	var ctype: String = str(work.get("type", ""))
	var skill: float = team_skill(studio, ctype)
	var management: float = clampf(float(work.get("management", 0.5)), 0.0, 1.0)
	var speed: float = maxf(0.05, (0.6 + skill * 0.8) * (0.8 + management * 0.4))
	var d: float = maxf(0.0, days)
	work["progress"] = float(work.get("progress", 0.0)) + d * speed
	var needed: float = maxf(1.0, float(work.get("required_progress", 1.0)))
	var ready: bool = float(work["progress"]) >= needed
	var quality: float = float(work.get("quality", 0.0))
	if ready and not bool(work.get("quality_settled", false)):
		var base_budget: float = float((CONTENT_TYPES[ctype] as Dictionary)["base_budget"])
		var budget_factor: float = clampf(float(work.get("budget", 0)) / maxf(1.0, base_budget), 0.0, 2.0) / 2.0
		var difficulty: float = float((CONTENT_TYPES[ctype] as Dictionary)["difficulty"])
		var roll: float = _roll(float(opts.get("roll", -1.0)), rng)
		quality = clampf(0.15 + skill * 0.45 + budget_factor * 0.20 + management * 0.10 + roll * 0.20 - difficulty * 0.10, 0.0, 1.0)
		work["quality"] = quality
		work["status"] = "ready"
		work["quality_settled"] = true
	return {
		"ok": true, "progress": float(work["progress"]), "required": needed,
		"ready": ready, "status": str(work["status"]), "team_skill": skill, "quality": quality,
	}


## 发行作品：口碑与热度决定表现，表现反馈工作室声誉；爆款/扑街分类。
func release_work(studio: Dictionary, work: Dictionary, opts: Dictionary = {}, rng = null) -> Dictionary:
	if str(work.get("status", "")) != "ready" and not bool(work.get("quality_settled", false)):
		return {"ok": false, "reason": "not_ready"}
	var quality: float = clampf(float(work.get("quality", 0.5)), 0.0, 1.0)
	var hype: float = clampf(float(opts.get("hype", work.get("hype", 0.3))), 0.0, 1.0)
	var controversy: float = clampf(float(work.get("controversy", 0.0)), 0.0, 1.0)
	var roll: float = _roll(float(opts.get("roll", -1.0)), rng)
	var performance: float = clampf(quality * 0.6 + hype * 0.3 + roll * 0.1 - controversy * 0.3, 0.0, 1.0)
	var hit: bool = performance >= float(opts.get("hit_threshold", 0.7))
	var flop: bool = performance < float(opts.get("flop_threshold", 0.35))
	var rep_delta: float = (performance - 0.5) * 0.2
	studio["reputation"] = clampf(float(studio.get("reputation", 0.5)) + rep_delta, 0.0, 1.0)
	work["released"] = true
	work["status"] = "released"
	work["quality"] = quality
	(studio["catalog"] as Array).append({
		"id": str(work.get("id", "")), "type": str(work.get("type", "")),
		"title": str(work.get("title", "")), "quality": quality, "performance": performance,
	})
	return {
		"ok": true, "quality": quality, "performance": performance,
		"hit": hit, "flop": flop, "reputation_delta": rep_delta,
	}


# --- 发行与变现 ---

## 渠道收入：按渠道参数计算毛收入，再乘作品口碑系数（0.5..1.5）。
func monetize(work: Dictionary, channel: String, opts: Dictionary = {}) -> Dictionary:
	if not CHANNELS.has(channel):
		return {"ok": false, "reason": "unknown_channel"}
	var allowed: Array = (CHANNELS[channel] as Dictionary)["types"]
	if not allowed.has(str(work.get("type", ""))):
		return {"ok": false, "reason": "channel_inapplicable"}
	var quality: float = clampf(float(work.get("quality", 0.5)), 0.0, 1.0)
	var reception: float = clampf(0.5 + quality, 0.0, 1.5)
	var gross: float = 0.0
	match channel:
		"platform_share":
			gross = float(opts.get("reach", 1000000)) * float(opts.get("arpu", 10.0)) * reception
		"ticketing":
			gross = float(opts.get("audience", 100000)) * float(opts.get("ticket_price", 40.0)) * reception
		"subscription":
			gross = float(opts.get("subscribers", 100000)) * float(opts.get("price", 15.0)) * clampf(float(opts.get("retention", 0.6)), 0.0, 1.0) * reception
		"advertising":
			gross = float(opts.get("reach", 1000000)) * float(opts.get("cpm", 20.0)) / 1000.0 * reception
		"sales":
			gross = float(opts.get("units", 50000)) * float(opts.get("unit_price", 60.0)) * reception
	var cut: float = 0.0
	if PLATFORMS.has(str(opts.get("platform", ""))):
		cut = float((PLATFORMS[str(opts.get("platform"))] as Dictionary)["cut_rate"])
	var revenue: int = int(round(gross * (1.0 - cut)))
	work["revenue"] = int(work.get("revenue", 0)) + revenue
	return {
		"ok": true, "channel": channel, "gross": int(round(gross)),
		"platform_cut": cut, "revenue": revenue, "reception": reception,
	}


# --- IP 运营 ---

## 登记 IP：以作品质量作为初始 IP 势能，纳入工作室 IP 库。
func register_ip(studio: Dictionary, work: Dictionary, opts: Dictionary = {}) -> Dictionary:
	_seq += 1
	var ip_id: String = str(opts.get("id", "ip.%s.%d" % [str(work.get("id", "w")), _seq]))
	var power: float = clampf(float(work.get("quality", 0.5)) + float(opts.get("power_bonus", 0.0)), 0.0, 1.0)
	var ip: Dictionary = {
		"id": ip_id,
		"title": str(work.get("title", ip_id)),
		"source_work": str(work.get("id", "")),
		"type": str(work.get("type", "")),
		"power": power,
		"adaptations": [],
		"licenses": [],
		"universe": str(opts.get("universe", "")),
	}
	(studio["ip_library"] as Dictionary)[ip_id] = ip
	work["ip_id"] = ip_id
	return {"ok": true, "ip": ip}


## IP 改编：生成衍生作品并提升 IP 势能。
func adapt(ip: Dictionary, target_type: String, opts: Dictionary = {}) -> Dictionary:
	if not CONTENT_TYPES.has(target_type):
		return {"ok": false, "reason": "unknown_content_type"}
	var fit: float = clampf(float(opts.get("fit", 0.5)), 0.0, 1.0)
	var power: float = clampf(float(ip.get("power", 0.5)), 0.0, 1.0)
	var quality: float = clampf(power * 0.6 + fit * 0.4, 0.0, 1.0)
	(ip["adaptations"] as Array).append({"type": target_type, "quality": quality})
	ip["power"] = clampf(power + 0.05, 0.0, 1.0)
	return {"ok": true, "target_type": target_type, "quality": quality, "ip_power": float(ip["power"])}


## IP 运营变现：周边/授权/改编/版权交易。scale 为交易规模。
## 收益 = IP 势能 × 运营倍率 × 规模 × 运气系数。
func operate_ip(ip: Dictionary, operation: String, scale: float, opts: Dictionary = {}, rng = null) -> Dictionary:
	if not IP_OPERATIONS.has(operation):
		return {"ok": false, "reason": "unknown_operation"}
	var def: Dictionary = IP_OPERATIONS[operation]
	var power: float = clampf(float(ip.get("power", 0.5)), 0.0, 1.0)
	var roll: float = _roll(float(opts.get("roll", -1.0)), rng)
	var luck: float = 0.7 + roll * 0.6
	var revenue: int = int(round(maxf(0.0, scale) * float(def["mult"]) * (0.3 + power) * luck))
	if bool(def["consumes"]):
		(ip["licenses"] as Array).append({"operation": operation, "scale": maxf(0.0, scale), "revenue": revenue})
	return {"ok": true, "operation": operation, "revenue": revenue, "ip_power": power, "luck": luck}


## IP 宇宙衍生：多 IP 联动带来额外加成（IP 数 ≥ 2 生效）。
func build_ip_universe(ips: Array, opts: Dictionary = {}) -> Dictionary:
	var count: int = ips.size()
	if count < 2:
		return {"ok": true, "universe": false, "bonus": 0.0, "count": count}
	var avg_power: float = 0.0
	for ip in ips:
		avg_power += clampf(float((ip as Dictionary).get("power", 0.5)), 0.0, 1.0)
	avg_power /= float(count)
	var bonus: float = clampf((float(count) - 1.0) * 0.1 * (0.5 + avg_power * 0.5), 0.0, 1.0)
	var name: String = str(opts.get("universe", "共享宇宙"))
	for ip in ips:
		(ip as Dictionary)["universe"] = name
	return {"ok": true, "universe": true, "bonus": bonus, "count": count, "name": name}


# --- 风险：抄袭、违规、翻车 ---

## 抄袭检测：相似度与检测力度决定是否被揭发。
func plagiarism_check(work: Dictionary, opts: Dictionary = {}, rng = null) -> Dictionary:
	var similarity: float = clampf(float(opts.get("similarity", 0.5)), 0.0, 1.0)
	var detect: float = clampf(float(opts.get("detect_prob", 0.5)), 0.0, 1.0)
	var roll: float = _roll(float(opts.get("roll", -1.0)), rng)
	var exposed: bool = roll < similarity * detect
	if exposed:
		work["plagiarized"] = true
		work["controversy"] = clampf(float(work.get("controversy", 0.0)) + similarity * 0.5, 0.0, 1.0)
	return {"ok": true, "similarity": similarity, "exposed": exposed, "controversy": float(work.get("controversy", 0.0))}


## 内容合规：涉政/违规风险与政策严格度决定是否通过。
func content_compliance(work: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var risk: float = clampf(float(opts.get("risk", 0.3)), 0.0, 1.0)
	var strictness: float = clampf(float(opts.get("strictness", 0.5)), 0.0, 1.0)
	var approved: bool = risk < (1.0 - strictness)
	if not approved:
		(work["violations"] as Array).append(str(opts.get("reason", "content_violation")))
		work["controversy"] = clampf(float(work.get("controversy", 0.0)) + risk * 0.4, 0.0, 1.0)
	return {"ok": true, "approved": approved, "risk": risk, "strictness": strictness}


## 下架：作品被移除并罚款，工作室声誉与舆情受创。
func take_down(studio: Dictionary, work: Dictionary, reason: String, opts: Dictionary = {}) -> Dictionary:
	var severity: float = clampf(float(opts.get("severity", 0.6)), 0.0, 1.0)
	var penalty: int = int(round(severity * float(opts.get("max_fine", 3000000.0))))
	work["status"] = "taken_down"
	work["takedown_reason"] = reason
	(studio["catalog"] as Array).append({"id": str(work.get("id", "")), "status": "taken_down", "reason": reason})
	studio["reputation"] = clampf(float(studio.get("reputation", 0.5)) - severity * 0.4, 0.0, 1.0)
	var fandom: Dictionary = studio.get("fandom", {})
	fandom["toxicity"] = clampf(float(fandom.get("toxicity", 0.0)) + severity * 0.3, 0.0, 1.0)
	studio["fandom"] = fandom
	return {"ok": true, "reason": reason, "penalty": penalty, "public_opinion": -severity}


## 翻车事件（艺人/主创丑闻）：按严重度与曝光度打击声誉，粉丝反噬。
func scandal_event(studio: Dictionary, opts: Dictionary = {}, rng = null) -> Dictionary:
	var severity: float = clampf(float(opts.get("severity", 0.6)), 0.0, 1.0)
	var exposure: float = clampf(float(opts.get("exposure", 0.6)), 0.0, 1.0)
	var roll: float = _roll(float(opts.get("roll", -1.0)), rng)
	var occurred: bool = roll < severity
	if not occurred:
		return {"ok": true, "occurred": false, "reputation_delta": 0.0, "backlash": 0.0}
	var hit: float = severity * exposure
	studio["reputation"] = clampf(float(studio.get("reputation", 0.5)) - hit * 0.5, 0.0, 1.0)
	var fandom: Dictionary = studio.get("fandom", {})
	fandom["toxicity"] = clampf(float(fandom.get("toxicity", 0.0)) + hit * 0.4, 0.0, 1.0)
	fandom["loyalty"] = clampf(float(fandom.get("loyalty", 0.5)) - hit * 0.3, 0.0, 1.0)
	studio["fandom"] = fandom
	return {"ok": true, "occurred": true, "reputation_delta": -hit * 0.5, "backlash": hit}


# --- 经营：融资、爆款与扑街、挖角、审查、饭圈 ---

## 融资：按轮次提升估值与规模，资金注入工作室。
func raise_funding(studio: Dictionary, stage: String, opts: Dictionary = {}, rng = null) -> Dictionary:
	if not FUNDING_STAGES.has(stage):
		return {"ok": false, "reason": "unknown_stage"}
	var fin: Dictionary = studio.get("financing", {"stage": "", "raised": 0, "valuation": 0})
	var idx: int = FUNDING_STAGES.find(stage)
	var base_valuation: int = int(opts.get("valuation", maxi(1000000, (idx + 1) * 3000000)))
	var sentiment: float = clampf(float(opts.get("sentiment", 1.0)), 0.2, 3.0)
	var equity: float = clampf(float(opts.get("equity_pct", 0.15)), 0.01, 0.5)
	var valuation: int = int(round(float(base_valuation) * sentiment * (1.0 + float(studio.get("reputation", 0.5)))))
	var investment: int = int(round(float(valuation) * equity))
	studio["money"] = int(studio.get("money", 0)) + investment
	fin["stage"] = stage
	fin["raised"] = int(fin.get("raised", 0)) + investment
	fin["valuation"] = valuation
	studio["financing"] = fin
	return {"ok": true, "stage": stage, "valuation": valuation, "investment": investment, "equity_pct": equity}


## 爆款与扑街分类：基于发行表现。
func hit_or_flop(work: Dictionary, performance: float, opts: Dictionary = {}) -> Dictionary:
	var p: float = clampf(performance, 0.0, 1.0)
	var hit: bool = p >= float(opts.get("hit_threshold", 0.7))
	var flop: bool = p < float(opts.get("flop_threshold", 0.35))
	var label: String = "hit" if hit else ("flop" if flop else "ordinary")
	return {"ok": true, "performance": p, "hit": hit, "flop": flop, "label": label}


## 挖角：以更高待遇从对手工作室挖人；成功率由待遇差与对手忠诚决定。
func poach_team(studio: Dictionary, target_studio: Dictionary, role: String, opts: Dictionary = {}, rng = null) -> Dictionary:
	if not CREATION_ROLES.has(role):
		return {"ok": false, "reason": "unknown_role"}
	var target_team: Dictionary = target_studio.get("team", {})
	var entry: Dictionary = target_team.get(role, {})
	if int(entry.get("count", 0)) <= 0:
		return {"ok": false, "reason": "no_target"}
	var offer: float = clampf(float(opts.get("offer_mult", 1.5)), 0.0, 5.0)
	var loyalty: float = clampf(float(opts.get("target_loyalty", 0.6)), 0.0, 1.0)
	var success_prob: float = clampf((offer - 1.0) * 0.5 * (1.0 - loyalty) + 0.1, 0.0, 0.95)
	var roll: float = _roll(float(opts.get("roll", -1.0)), rng)
	var success: bool = roll < success_prob
	var cost: int = int(round(float((CREATION_ROLES[role] as Dictionary)["hire_cost"]) * offer))
	if success:
		if int(studio.get("money", 0)) < cost:
			return {"ok": false, "reason": "insufficient_funds", "cost": cost, "success_prob": success_prob}
		studio["money"] = int(studio["money"]) - cost
		entry["count"] = int(entry.get("count", 0)) - 1
		target_team[role] = entry
		target_studio["team"] = target_team
		_add_team_member(studio, role, 1, float(opts.get("skill", entry.get("skill", 0.5))))
	return {"ok": true, "success": success, "success_prob": success_prob, "role": role, "cost": cost if success else 0}


## 版号/审查延误：返回延误天数与是否获批。
func approval_delay(content_type: String, opts: Dictionary = {}, rng = null) -> Dictionary:
	if not CONTENT_TYPES.has(content_type):
		return {"ok": false, "reason": "unknown_content_type"}
	var base: float = maxf(0.0, float(opts.get("base_days", 30.0)))
	var strictness: float = clampf(float(opts.get("strictness", 0.5)), 0.0, 1.0)
	var roll: float = _roll(float(opts.get("roll", -1.0)), rng)
	var delay: float = base * (1.0 + strictness) * (0.5 + roll)
	var approved: bool = roll >= strictness * 0.5
	return {"ok": true, "content_type": content_type, "delay_days": delay, "approved": approved}


## 粉丝文化与饭圈：粉丝增长与反噬双向演化。
func fandom_dynamics(studio: Dictionary, opts: Dictionary = {}, rng = null) -> Dictionary:
	var fandom: Dictionary = studio.get("fandom", {"size": 0, "loyalty": 0.5, "toxicity": 0.0})
	var growth: float = clampf(float(opts.get("growth", 0.1)), -1.0, 3.0)
	var roll: float = _roll(float(opts.get("roll", -1.0)), rng)
	var size: int = maxi(0, int(fandom.get("size", 0)))
	var delta: int = int(round(float(size) * growth + roll * 1000.0))
	var new_size: int = maxi(0, size + delta)
	fandom["size"] = new_size
	if new_size > 100000:
		fandom["toxicity"] = clampf(float(fandom.get("toxicity", 0.0)) + 0.05, 0.0, 1.0)
	studio["fandom"] = fandom
	var backlash: bool = roll < clampf(float(fandom.get("toxicity", 0.0)) * 0.5, 0.0, 0.95) and new_size > 0
	return {"ok": true, "fandom_size": new_size, "delta": delta, "toxicity": float(fandom["toxicity"]), "backlash": backlash}


# --- 序列化 ---

func to_dict(state: Dictionary) -> Dictionary:
	return state.duplicate(true)


func from_dict(data: Dictionary) -> Dictionary:
	return data.duplicate(true)
