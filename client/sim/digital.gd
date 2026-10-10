class_name DigitalSystem
extends RefCounted

const BaselineScript = preload("res://sim/baseline.gd")
## 数字生活与黑客（R67；design D23）。
##
## 覆盖：
##   - 数字身份与数据：账号、实名、隐私级别、数据泄露与买卖，数字资产（账号/虚拟物品/加密钱包）被盗与追回；
##   - 网络安全职业（合法方向）：渗透测试、安全防护、应急响应与数据泄露事件处置；
##   - 黑客（游戏内虚构抽象判定）：目标个人/企业/政府/黑产，按犯罪技能树 hacking 等级判定成败，
##     结算收益、暴露概率与法律后果，不出现任何现实工具或手法；
##   - 电子竞技：训练、战队、赛事、奖金、转会与生涯伤病（与 D32 通过入参衔接）；
##   - 内容平台：直播/短视频、粉丝、打赏、平台分成、带货与舆情风险，翻车掉粉与处罚；
##     算法推荐与信息茧房影响认知与舆情；
##   - 边界：数据泄露牵连他人（结构化返回被牵连者供上层记账）、平台封号、网络成瘾。
##
## 设计取舍：
##   - 身份/生涯/创作者状态均为纯数据 Dictionary，便于存读档与 headless 测试；
##   - 随机项统一由 opts 的 roll/exposure_roll/virality_roll 等或外部 rng 注入，缺省确定化，便于断言；
##   - 黑客判定只做“技能 − 难度”抽象概率，不建模任何现实攻击手法；
##   - 与既有系统解耦：技能等级、电竞天赋、声望效应均以入参或结构化返回值交给上层编排。

const HACK_PERSONAL: String = "personal"
const HACK_ENTERPRISE: String = "enterprise"
const HACK_GOVERNMENT: String = "government"
const HACK_BLACK_MARKET: String = "black_market"

## 黑客目标：难度（0..20）、基准收益、基础暴露率、法律后果（刑期/罚金/通缉等级）。
## 数值真源：shared/consistency/baseline/digital.json。
const HACK_TARGETS: Dictionary = BaselineScript.DIGITAL_HACK_TARGETS

## 网络安全职业（合法方向）：难度、收入、声望增益。数值真源：shared/consistency/baseline/digital.json。
const SECURITY_JOBS: Dictionary = BaselineScript.DIGITAL_SECURITY_JOBS

## 内容平台：基准播放、打赏率、平台分成比例、带货转化率。数值真源：shared/consistency/baseline/digital.json。
const CONTENT_PLATFORMS: Dictionary = BaselineScript.DIGITAL_CONTENT_PLATFORMS

const ADDICTION_THRESHOLD_HOURS: float = BaselineScript.DIGITAL_ADDICTION_THRESHOLD_HOURS


func _roll(forced: float, rng) -> float:
	if forced >= 0.0:
		return clampf(forced, 0.0, 1.0)
	if rng != null:
		return rng.next_float()
	return 0.0


# --- 数字身份与数据 ---

## 新建数字身份。contacts 供数据泄露牵连他人使用。
func new_identity(owner_id: String, opts: Dictionary = {}) -> Dictionary:
	return {
		"owner_id": owner_id,
		"accounts": {},
		"real_name_verified": bool(opts.get("real_name_verified", false)),
		"privacy": clampf(float(opts.get("privacy", 0.5)), 0.0, 1.0),
		"data": [],
		"assets": [],
		"contacts": [],
		"exposure_heat": 0.0,
		"banned_platforms": [],
		"addiction": 0.0,
		"_seq": 0,
	}


func create_account(identity: Dictionary, platform: String, opts: Dictionary = {}) -> Dictionary:
	var accounts: Dictionary = identity["accounts"]
	accounts[platform] = {
		"platform": platform,
		"real_name": bool(opts.get("real_name", bool(identity["real_name_verified"]))),
		"privacy": clampf(float(opts.get("privacy", float(identity["privacy"]))), 0.0, 1.0),
		"banned": false,
	}
	identity["accounts"] = accounts
	return {"ok": true, "account": accounts[platform]}


## 实名认证：提升可信度但降低隐私。
func verify_real_name(identity: Dictionary, verified: bool = true) -> Dictionary:
	identity["real_name_verified"] = verified
	if verified:
		identity["privacy"] = clampf(float(identity["privacy"]) - 0.1, 0.0, 1.0)
	return {"ok": true, "real_name_verified": verified, "privacy": float(identity["privacy"])}


func set_privacy(identity: Dictionary, level: float) -> Dictionary:
	identity["privacy"] = clampf(level, 0.0, 1.0)
	return {"ok": true, "privacy": float(identity["privacy"])}


## 记录一条数据（value 为数据价值，sensitivity 为敏感度）。
func add_data(identity: Dictionary, kind: String, value: float, opts: Dictionary = {}) -> Dictionary:
	var entry: Dictionary = {
		"kind": kind,
		"value": maxf(0.0, value),
		"sensitivity": clampf(float(opts.get("sensitivity", 0.5)), 0.0, 1.0),
		"leaked": false,
	}
	(identity["data"] as Array).append(entry)
	return {"ok": true, "data": entry}


func add_contact(identity: Dictionary, contact_id: String) -> Dictionary:
	(identity["contacts"] as Array).append(contact_id)
	return {"ok": true, "contacts": (identity["contacts"] as Array).size()}


## 数据泄露与买卖：未泄露数据全部外泄，按价值与出售比例计价，并牵连联系人。
func leak_data(identity: Dictionary, opts: Dictionary = {}, rng = null) -> Dictionary:
	var ratio: float = clampf(float(opts.get("sale_ratio", 0.3)), 0.0, 1.0)
	var leaked: Array = []
	var value: float = 0.0
	for d in (identity["data"] as Array):
		var entry: Dictionary = d
		if not bool(entry["leaked"]):
			entry["leaked"] = true
			leaked.append(entry)
			value += float(entry["value"]) * float(entry["sensitivity"])
	var implicated: Array = []
	for c in (identity["contacts"] as Array):
		# 被牵连者的隐私受损记录由上层据此写入其 legal/privacy 账本。
		implicated.append({"contact_id": str(c), "privacy_breach": true, "source": identity["owner_id"]})
	var sale_price: int = int(round(value * ratio))
	identity["exposure_heat"] = clampf(float(identity["exposure_heat"]) + 20.0, 0.0, 200.0)
	return {
		"ok": true, "leaked_count": leaked.size(), "leaked": leaked,
		"sale_price": sale_price, "implicated": implicated,
	}


# --- 数字资产：被盗与追回 ---

func add_asset(identity: Dictionary, asset_type: String, value: int, opts: Dictionary = {}) -> Dictionary:
	identity["_seq"] = int(identity.get("_seq", 0)) + 1
	var asset: Dictionary = {
		"id": "asset.%d" % int(identity["_seq"]),
		"type": asset_type,
		"value": maxi(0, value),
		"stolen": false,
	}
	(identity["assets"] as Array).append(asset)
	return {"ok": true, "asset": asset}


func find_asset(identity: Dictionary, asset_id: String) -> Dictionary:
	for a in (identity["assets"] as Array):
		if str((a as Dictionary).get("id", "")) == asset_id:
			return a
	return {}


## 数字资产被盗：防范由隐私/安全投入决定，越高越难被盗。
func steal_asset(identity: Dictionary, asset_id: String, opts: Dictionary = {}, rng = null) -> Dictionary:
	var asset: Dictionary = find_asset(identity, asset_id)
	if asset.is_empty():
		return {"ok": false, "reason": "unknown_asset"}
	if bool(asset["stolen"]):
		return {"ok": false, "reason": "already_stolen"}
	var defense: float = clampf(float(opts.get("defense", float(identity["privacy"]))), 0.0, 1.0)
	var prob: float = clampf(0.6 - defense * 0.5, 0.05, 0.95)
	var roll: float = _roll(float(opts.get("roll", -1.0)), rng)
	var success: bool = roll < prob
	if success:
		asset["stolen"] = true
	return {
		"ok": true, "success": success, "probability": prob,
		"loss": int(asset["value"]) if success else 0, "asset": asset,
	}


## 资产追回：警方协助（police）提高追回率。
func recover_asset(identity: Dictionary, asset_id: String, opts: Dictionary = {}, rng = null) -> Dictionary:
	var asset: Dictionary = find_asset(identity, asset_id)
	if asset.is_empty():
		return {"ok": false, "reason": "unknown_asset"}
	if not bool(asset["stolen"]):
		return {"ok": false, "reason": "not_stolen"}
	var police: float = clampf(float(opts.get("police", 0.0)), 0.0, 1.0)
	var prob: float = clampf(0.3 + police * 0.4, 0.05, 0.90)
	var roll: float = _roll(float(opts.get("roll", -1.0)), rng)
	var recovered: bool = roll < prob
	if recovered:
		asset["stolen"] = false
	return {"ok": true, "recovered": recovered, "probability": prob, "asset": asset}


# --- 网络安全职业（合法方向） ---

## 执行网络安全工作。返回成功率、收入与声望（无法律风险）。
func security_job(kind: String, skill: float, opts: Dictionary = {}, rng = null) -> Dictionary:
	if not SECURITY_JOBS.has(kind):
		return {"ok": false, "reason": "unknown_job"}
	var job: Dictionary = SECURITY_JOBS[kind]
	var s: float = clampf(skill, 0.0, 20.0)
	var prob: float = clampf(0.4 + (s - float(job["difficulty"])) / 20.0, 0.05, 0.95)
	var roll: float = _roll(float(opts.get("roll", -1.0)), rng)
	var success: bool = roll < prob
	var income: int = int(round(float(job["income"]) * (1.0 + s / 20.0))) if success else 0
	return {
		"ok": true, "kind": kind, "success": success, "probability": prob,
		"income": income, "reputation": float(job["reputation"]) if success else 0.0,
		"legal_risk": 0.0,
	}


## 数据泄露事件处置：控制损失、恢复数据并评估赔偿与信用影响。
func handle_breach(breach: Dictionary, skill: float, opts: Dictionary = {}, rng = null) -> Dictionary:
	var severity: float = clampf(float(breach.get("severity", 0.5)), 0.0, 1.0)
	var records: int = maxi(0, int(breach.get("records_lost", 0)))
	var s: float = clampf(skill, 0.0, 20.0)
	var contained_prob: float = clampf(0.3 + s / 20.0 * 0.5, 0.05, 0.95)
	var roll: float = _roll(float(opts.get("roll", -1.0)), rng)
	var contained: bool = roll < contained_prob
	var loss_factor: float = severity * (0.2 if contained else 1.0)
	var compensation: int = int(round(float(records) * 100.0 * loss_factor))
	return {
		"ok": true, "contained": contained, "contained_probability": contained_prob,
		"records_affected": int(round(float(records) * loss_factor)),
		"compensation": compensation, "credit_delta": (-10.0 if not contained else -2.0) * severity,
	}


# --- 黑客（游戏内虚构抽象判定） ---

## 目标暴露后的法律后果（供司法系统消费）。
func legal_consequence(target_type: String) -> Dictionary:
	var def: Dictionary = HACK_TARGETS.get(target_type, {})
	return {
		"criminal_record": true,
		"wanted_level": int(def.get("wanted", 1)),
		"sentence_days": int(def.get("sentence_days", 0)),
		"fine": int(def.get("fine", 0)),
	}


## 实施未授权入侵（抽象判定，不涉及现实手法）。
## 技能取犯罪技能树 hacking 等级 0..20；结算收益、暴露概率与法律后果。
func hack(target_type: String, skill: float, opts: Dictionary = {}, rng = null) -> Dictionary:
	if not HACK_TARGETS.has(target_type):
		return {"ok": false, "reason": "unknown_target"}
	var def: Dictionary = HACK_TARGETS[target_type]
	var s: float = clampf(skill, 0.0, 20.0)
	var prob: float = clampf(0.35 + (s - float(def["difficulty"])) / 20.0, 0.05, 0.95)
	var roll: float = _roll(float(opts.get("roll", -1.0)), rng)
	var success: bool = roll < prob
	var gain: int = int(round(float(def["base_gain"]) * (0.5 + s / 20.0))) if success else 0
	var exposure_prob: float = clampf(float(def["exposure"]) + (float(def["difficulty"]) - s) * 0.02, 0.02, 0.95)
	var exposure_roll: float = _roll(float(opts.get("exposure_roll", -1.0)), rng)
	var exposed: bool = exposure_roll < exposure_prob
	var legal: Dictionary = legal_consequence(target_type) if exposed else {}
	return {
		"ok": true, "target": target_type, "success": success, "probability": prob,
		"gain": gain, "exposed": exposed, "exposure_probability": exposure_prob,
		"legal_consequence": legal,
	}


# --- 电子竞技 ---

func new_esports_career(opts: Dictionary = {}) -> Dictionary:
	return {
		"team": str(opts.get("team", "自由人")),
		"skill": clampf(float(opts.get("skill", 10.0)), 0.0, 20.0),
		"fitness": clampf(float(opts.get("fitness", 1.0)), 0.0, 1.0),
		"fatigue": clampf(float(opts.get("fatigue", 0.0)), 0.0, 1.0),
		"prize_total": 0,
		"injuries": [],
		"retired": false,
		"matches": 0,
	}


## 训练：提升技能但累积疲劳、损耗体能。
func train(career: Dictionary, hours: float, opts: Dictionary = {}) -> Dictionary:
	var h: float = maxf(0.0, hours)
	var gain: float = h * 0.05 * (1.0 - float(career["fatigue"]))
	career["skill"] = clampf(float(career["skill"]) + gain, 0.0, 20.0)
	career["fatigue"] = clampf(float(career["fatigue"]) + h * 0.03, 0.0, 1.0)
	career["fitness"] = clampf(float(career["fitness"]) - h * 0.01, 0.0, 1.0)
	return {
		"ok": true, "skill": float(career["skill"]),
		"fatigue": float(career["fatigue"]), "fitness": float(career["fitness"]),
	}


func join_team(career: Dictionary, team: String, opts: Dictionary = {}) -> Dictionary:
	career["team"] = team
	return {"ok": true, "team": team}


## 转会：结算转会费与适应期，转会后短期内状态略降。
func transfer(career: Dictionary, new_team: String, fee: int = 0, opts: Dictionary = {}) -> Dictionary:
	var old_team: String = str(career["team"])
	career["team"] = new_team
	career["fatigue"] = clampf(float(career["fatigue"]) + 0.1, 0.0, 1.0)
	return {"ok": true, "from": old_team, "to": new_team, "fee": maxi(0, fee)}


## 参加赛事：胜率由技能与体能决定，胜出获得奖金。
func play_match(career: Dictionary, opts: Dictionary = {}, rng = null) -> Dictionary:
	var form: float = clampf(float(career["skill"]) / 20.0 * float(career["fitness"]), 0.0, 1.0)
	var prob: float = clampf(0.3 + form * 0.6, 0.05, 0.95)
	var roll: float = _roll(float(opts.get("roll", -1.0)), rng)
	var win: bool = roll < prob
	var prize: int = int(round(float(opts.get("prize", 100000)) * (1.0 + form))) if win else 0
	career["prize_total"] = int(career["prize_total"]) + prize
	career["matches"] = int(career["matches"]) + 1
	career["fatigue"] = clampf(float(career["fatigue"]) + 0.1, 0.0, 1.0)
	return {"ok": true, "win": win, "probability": prob, "prize": prize}


## 生涯伤病：概率随体能下降与疲劳上升，重伤可能迫使退役。
func career_injury(career: Dictionary, opts: Dictionary = {}, rng = null) -> Dictionary:
	var base: float = clampf((1.0 - float(career["fitness"])) * 0.6 + float(career["fatigue"]) * 0.4, 0.0, 1.0)
	var prob: float = clampf(base * float(opts.get("severity", 1.0)), 0.0, 0.95)
	var roll: float = _roll(float(opts.get("roll", -1.0)), rng)
	var injured: bool = roll < prob
	var severity: float = 0.0
	if injured:
		severity = clampf(prob, 0.1, 1.0)
		career["fitness"] = clampf(float(career["fitness"]) - 0.2 * severity, 0.0, 1.0)
		(career["injuries"] as Array).append({
			"type": str(opts.get("injury_type", "运动损伤")),
			"severity": severity,
			"minute": int(opts.get("minute", 0)),
		})
		if float(career["fitness"]) < 0.2:
			career["retired"] = true
	return {
		"ok": true, "injured": injured, "severity": severity,
		"probability": prob, "retired": bool(career["retired"]),
	}


# --- 内容平台 ---

func new_creator(creator_id: String, platform: String, opts: Dictionary = {}) -> Dictionary:
	return {
		"creator_id": creator_id,
		"platform": platform,
		"fans": maxi(0, int(opts.get("fans", 0))),
		"tips_total": 0,
		"ad_income": 0,
		"delivery_gmv": 0,
		"reputation": clampf(float(opts.get("reputation", 0.5)), 0.0, 1.0),
		"strikes": 0,
		"banned": false,
		"content_count": 0,
	}


## 发布内容：结算播放、涨粉、打赏、平台分成与可选带货 GMV。
func publish_content(creator: Dictionary, opts: Dictionary = {}, rng = null) -> Dictionary:
	if bool(creator["banned"]):
		return {"ok": false, "reason": "banned"}
	var platform_def: Dictionary = CONTENT_PLATFORMS.get(str(creator["platform"]), CONTENT_PLATFORMS["short_video"])
	var fans: int = int(creator["fans"])
	var viral_roll: float = _roll(float(opts.get("virality_roll", -1.0)), rng)
	var reach: float = clampf(0.5 + viral_roll * 1.5 + float(fans) / 200000.0, 0.1, 5.0)
	var views: int = int(round(float(platform_def["base_views"]) * reach))
	var tips: int = int(round(float(views) * float(platform_def["tip_rate"])))
	var platform_cut: int = int(round(float(tips) * float(platform_def["cut"])))
	var income: int = tips - platform_cut
	var gmv: int = 0
	if bool(opts.get("delivery", false)):
		gmv = int(round(float(views) * float(platform_def["conversion"]) * float(opts.get("unit_price", 50.0))))
		income += int(round(float(gmv) * 0.1))
	creator["fans"] = fans + int(round(float(views) * 0.001))
	creator["tips_total"] = int(creator["tips_total"]) + tips
	creator["delivery_gmv"] = int(creator["delivery_gmv"]) + gmv
	creator["content_count"] = int(creator["content_count"]) + 1
	return {
		"ok": true, "views": views, "fans_delta": int(round(float(views) * 0.001)),
		"tips": tips, "platform_cut": platform_cut, "income": income,
		"delivery_gmv": gmv, "reputation_delta": 0.005,
	}


## 翻车/舆情危机：掉粉、声誉下降、可能被处罚乃至封号。
func scandal(creator: Dictionary, severity: float, opts: Dictionary = {}, rng = null) -> Dictionary:
	var sev: float = clampf(severity, 0.0, 1.0)
	var roll: float = _roll(float(opts.get("roll", -1.0)), rng)
	var impact: float = sev * (0.5 + (1.0 - roll) * 0.5)
	var fans: int = int(creator["fans"])
	var fan_loss: int = int(round(float(fans) * clampf(0.1 + impact * 0.6, 0.0, 0.9)))
	creator["fans"] = maxi(0, fans - fan_loss)
	creator["strikes"] = int(creator["strikes"]) + 1
	var rep_delta: float = -impact * 0.5
	creator["reputation"] = clampf(float(creator["reputation"]) + rep_delta, 0.0, 1.0)
	var penalty: int = int(round(impact * float(opts.get("max_penalty", 500000))))
	var banned: bool = int(creator["strikes"]) >= int(opts.get("ban_threshold", 3))
	if banned:
		creator["banned"] = true
	return {
		"ok": true, "fan_loss": fan_loss, "reputation_delta": rep_delta,
		"penalty": penalty, "banned": banned, "strikes": int(creator["strikes"]),
	}


func platform_ban(creator: Dictionary, reason: String = "violation") -> Dictionary:
	creator["banned"] = true
	return {"ok": true, "banned": true, "reason": reason}


## 算法推荐与信息茧房：互动越高、内容越单一，认知收窄越明显。
func algorithm_feed(cognition: float, opts: Dictionary = {}) -> Dictionary:
	var engagement: float = clampf(float(opts.get("engagement", 0.5)), 0.0, 1.0)
	var diversity: float = clampf(float(opts.get("diversity", 0.5)), 0.0, 1.0)
	var bubble: float = clampf(engagement * (1.0 - diversity), 0.0, 1.0)
	var bias: float = clampf(float(opts.get("bias", 0.0)), -1.0, 1.0)
	return {
		"ok": true, "filter_bubble": bubble,
		"cognition_delta": -bubble * 0.3, "opinion_shift": bubble * bias * 0.5,
	}


## 网络成瘾：时长与依赖度越高越严重，并带来健康与社交惩罚。
func internet_addiction(hours: float, opts: Dictionary = {}) -> Dictionary:
	var h: float = maxf(0.0, hours)
	var level: float = clampf(h / ADDICTION_THRESHOLD_HOURS * float(opts.get("dependence", 0.5)), 0.0, 1.0)
	return {
		"ok": true, "addiction": level,
		"health_delta": -level * 0.2, "social_delta": -level * 0.3,
	}


func to_dict(identity: Dictionary) -> Dictionary:
	return identity.duplicate(true)


func from_dict(data: Dictionary) -> Dictionary:
	return data.duplicate(true)
