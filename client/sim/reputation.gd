class_name ReputationSystem
extends RefCounted
## 声誉与分层传闻（R21；design D10）。世界级系统：持有传闻登记表。
##
## 三条声誉线（0..100）：名望 fame、社会地位 status、恶名 infamy。
## 传闻按圈层 → 区域 → 公众三层扩散，具有时延与失真；分层升级时结算声誉影响。
## 高名望解锁机会；高恶名导致场所拒服务与 NPC 敌意。

const BaselineScript = preload("res://sim/baseline.gd")

const GregorianScript = preload("res://sim/gregorian.gd")

const MAX_REPUTATION: float = BaselineScript.REPUTATION_MAX_REPUTATION
const MINUTES_PER_DAY: float = BaselineScript.REPUTATION_MINUTES_PER_DAY

## 行为 → 三条声誉线基础增减。
const ACTS: Dictionary = {
	"charity": {"fame": 3.0, "status": 1.0, "infamy": 0.0},
	"donation": {"fame": 2.0, "status": 1.0, "infamy": 0.0},
	"heroic": {"fame": 8.0, "status": 3.0, "infamy": 0.0},
	"public_speech": {"fame": 2.0, "status": 1.0, "infamy": 0.0},
	"career_advance": {"fame": 1.0, "status": 4.0, "infamy": 0.0},
	"wealth_gain": {"fame": 0.0, "status": 1.0, "infamy": 0.0},
	"crime": {"fame": 0.0, "status": -2.0, "infamy": 5.0},
	"scandal": {"fame": -3.0, "status": -1.0, "infamy": 6.0},
}

## 传闻层级（reach 阈值 → 层名）。
const TIER_CIRCLE: String = "circle"
const TIER_REGION: String = "region"
const TIER_PUBLIC: String = "public"
const TIER_INDEX: Dictionary = {"circle": 1, "region": 2, "public": 3}

const REACH_CIRCLE: float = BaselineScript.REPUTATION_REACH_CIRCLE
const REACH_REGION: float = BaselineScript.REPUTATION_REACH_REGION

## 机会解锁阈值（名望）。
const FAME_UNLOCKS: Dictionary = {
	"invite_elite": 60.0, "public_office": 80.0, "media_interview": 50.0,
}
const STATUS_UNLOCKS: Dictionary = {"board_seat": 70.0, "guild_master": 60.0}

## 恶名阈值。
const HOSTILE_THRESHOLD: float = BaselineScript.REPUTATION_HOSTILE_THRESHOLD
const REFUSE_SERVICE_THRESHOLD: float = BaselineScript.REPUTATION_REFUSE_SERVICE_THRESHOLD

var _rumors: Dictionary = {}   # id -> rumor
var _seq: int = 0


func _init(_seed: int = 0) -> void:
	pass


# --- 声誉线 ---

func ensure(owner: Dictionary) -> Dictionary:
	var r: Variant = owner.get("reputation", null)
	if not (r is Dictionary):
		r = {"fame": 0.0, "status": 0.0, "infamy": 0.0}
		owner["reputation"] = r
	return r


func get_reputation(owner: Dictionary) -> Dictionary:
	return ensure(owner).duplicate()


func apply_delta(owner: Dictionary, fame_d: float, status_d: float, infamy_d: float) -> Dictionary:
	var r: Dictionary = ensure(owner)
	r["fame"] = clampf(float(r["fame"]) + fame_d, 0.0, MAX_REPUTATION)
	r["status"] = clampf(float(r["status"]) + status_d, 0.0, MAX_REPUTATION)
	r["infamy"] = clampf(float(r["infamy"]) + infamy_d, 0.0, MAX_REPUTATION)
	return r.duplicate()


## 记录一次行为对三条声誉线的影响。magnitude 为强度倍数。
func record_act(owner: Dictionary, act: String, magnitude: float = 1.0) -> Dictionary:
	if not ACTS.has(act):
		return {"ok": false, "reason": "unknown_act"}
	var spec: Dictionary = ACTS[act]
	var r: Dictionary = ensure(owner)
	var before: Dictionary = r.duplicate()
	r["fame"] = clampf(float(r["fame"]) + float(spec["fame"]) * magnitude, 0.0, MAX_REPUTATION)
	r["status"] = clampf(float(r["status"]) + float(spec["status"]) * magnitude, 0.0, MAX_REPUTATION)
	r["infamy"] = clampf(float(r["infamy"]) + float(spec["infamy"]) * magnitude, 0.0, MAX_REPUTATION)
	return {
		"ok": true, "act": act,
		"deltas": {
			"fame": float(r["fame"]) - float(before["fame"]),
			"status": float(r["status"]) - float(before["status"]),
			"infamy": float(r["infamy"]) - float(before["infamy"]),
		},
	}


## 高名望/地位解锁的特殊机会。
func unlock_opportunities(owner: Dictionary) -> Array:
	var r: Dictionary = ensure(owner)
	var out: Array = []
	for key in FAME_UNLOCKS.keys():
		if float(r["fame"]) >= float(FAME_UNLOCKS[key]):
			out.append(key)
	for key in STATUS_UNLOCKS.keys():
		if float(r["status"]) >= float(STATUS_UNLOCKS[key]):
			out.append(key)
	return out


## 恶名过高：部分场所拒绝服务。
func refuses_service(owner: Dictionary) -> bool:
	return float(ensure(owner)["infamy"]) >= REFUSE_SERVICE_THRESHOLD


## 恶名过高：部分 NPC 产生敌意。
func hostile(owner: Dictionary) -> bool:
	return float(ensure(owner)["infamy"]) >= HOSTILE_THRESHOLD


# --- 传闻 ---

## 创建一条传闻。opts: valence(-1..1)、credibility、content、circle、source_id。
func create_rumor(subject_id: String, content: String, opts: Dictionary = {}) -> Dictionary:
	_seq += 1
	var info: Dictionary = {
		"id": "%s.rumor.%d" % [subject_id, _seq],
		"subject_id": subject_id,
		"content": content,
		"valence": clampf(float(opts.get("valence", 0.0)), -1.0, 1.0),
		"credibility": clampf(float(opts.get("credibility", 0.6)), 0.0, 1.0),
		"distortion": clampf(float(opts.get("distortion", 0.0)), 0.0, 1.0),
		"reach": 0.0,
		"circle": str(opts.get("circle", TIER_CIRCLE)),
		"source_id": str(opts.get("source_id", "")),
		"created_minute": int(opts.get("minute", 0)),
		"last_propagate_minute": int(opts.get("minute", 0)),
		"tier": TIER_CIRCLE,
		"reputation_tier_applied": 0,
		"witnesses": [],
	}
	_rumors[info["id"]] = info
	return info


## 按时间推进单条传闻的扩散。cfg 可覆盖：delay_days、reach_per_day、
## distortion_per_day、credibility_decay_per_day。
func propagate(rumor: Dictionary, now_minute: int, cfg: Dictionary = {}) -> Dictionary:
	var elapsed_days: float = float(now_minute - int(rumor.get("last_propagate_minute", 0))) / MINUTES_PER_DAY
	if elapsed_days <= 0.0:
		return rumor
	var age_days: float = float(now_minute - int(rumor.get("created_minute", 0))) / MINUTES_PER_DAY
	rumor["last_propagate_minute"] = now_minute
	var delay_days: float = float(cfg.get("delay_days", 0.5))
	if age_days < delay_days:
		# 传播时延：尚未开始扩散。
		return rumor
	var reach: float = float(rumor["reach"])
	var cred: float = float(rumor["credibility"])
	var reach_rate: float = float(cfg.get("reach_per_day", 0.5))
	var distortion_rate: float = float(cfg.get("distortion_per_day", 0.15))
	var cred_decay: float = float(cfg.get("credibility_decay_per_day", 0.05))
	var growth: float = reach_rate * elapsed_days * cred * (1.0 - reach)
	rumor["reach"] = clampf(reach + growth, 0.0, 1.0)
	# 失真随扩散累积：越广越易夸大。
	rumor["distortion"] = clampf(float(rumor["distortion"]) + distortion_rate * elapsed_days * (1.0 - reach), 0.0, 1.0)
	rumor["credibility"] = clampf(cred - cred_decay * elapsed_days, 0.0, 1.0)
	rumor["tier"] = tier_of(float(rumor["reach"]))
	return rumor


func tier_of(reach: float) -> String:
	if reach >= REACH_REGION:
		return TIER_PUBLIC
	if reach >= REACH_CIRCLE:
		return TIER_REGION
	return TIER_CIRCLE


## 按层级升级把传闻影响结算到主体声誉（每级只结算一次）。返回本次增量。
func apply_rumor_effect(owner: Dictionary, rumor: Dictionary) -> Dictionary:
	var idx: int = int(TIER_INDEX.get(str(rumor.get("tier", TIER_CIRCLE)), 1))
	var applied: int = int(rumor.get("reputation_tier_applied", 0))
	if idx <= applied:
		return {}
	var steps: int = idx - applied
	rumor["reputation_tier_applied"] = idx
	var magnitude: float = 2.0 * float(steps)
	var valence: float = float(rumor.get("valence", 0.0))
	if valence >= 0.0:
		return apply_delta(owner, magnitude, magnitude * 0.5, 0.0)
	return apply_delta(owner, 0.0, 0.0, magnitude)


## 推进所有传闻到 now。
func propagate_all(now_minute: int, cfg: Dictionary = {}) -> int:
	var n: int = 0
	for r in _rumors.values():
		propagate(r, now_minute, cfg)
		n += 1
	return n


func rumors_about(subject_id: String) -> Array:
	var out: Array = []
	for r in _rumors.values():
		if str(r.get("subject_id", "")) == subject_id:
			out.append(r)
	return out


## 失真后的传闻文本（叙事引用用）。
func distorted_content(rumor: Dictionary) -> String:
	var d: float = float(rumor.get("distortion", 0.0))
	var text: String = str(rumor.get("content", ""))
	if d < 0.25:
		return text
	if d < 0.6:
		return text + "（细节已被传得不太一样）"
	return text + "（早已面目全非）"


func rumor_count() -> int:
	return _rumors.size()


func get_rumor(rumor_id: String) -> Dictionary:
	return _rumors.get(rumor_id, {})
