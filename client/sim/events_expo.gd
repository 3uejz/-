class_name EventsExpoSystem
extends RefCounted
## 会展、演出与大型活动（R77；design D33）。
##
## 覆盖：
##   - 类型：演唱会、音乐节、漫展、博览会、发布会、体育赛事、婚礼/庆典；
##   - 流程：场地租赁 → 报批审批 → 招商 → 票务 → 安保 → 现场 → 复盘；
##   - 风险：超售、踩踏、天气、舆情失控、安保失效、艺人违约，黄牛与票务欺诈；
##   - 收益与赞助：票务、赞助、周边、直播版权；主办方声誉影响上座率；
##   - 策划职业：策划、制作、场地、票务公司的从业路径；
##   - 边界：艺人违约、退票潮、安全事故追责。
##
## 设计取舍：
##   - 活动为纯数据 Dictionary，按 STAGES 顺序推进，便于存读档与 headless 测试；
##   - 收益与成本分别累计到 revenue/cost，复盘据此给出净利润，可核对；
##   - 超售、踩踏、安保失效、艺人违约等由确定性规则或外部注入的 roll 判定，缺省确定化。

const EVENT_TYPES: Dictionary = {
	"concert": {"name": "演唱会", "base_capacity": 20000, "base_price": 6800, "star_weight": 0.6, "base_risk": 0.25, "merch_per_capita": 300},
	"music_festival": {"name": "音乐节", "base_capacity": 30000, "base_price": 4800, "star_weight": 0.5, "base_risk": 0.30, "merch_per_capita": 400},
	"comic_con": {"name": "漫展", "base_capacity": 15000, "base_price": 3000, "star_weight": 0.3, "base_risk": 0.20, "merch_per_capita": 800},
	"expo": {"name": "博览会", "base_capacity": 50000, "base_price": 2000, "star_weight": 0.2, "base_risk": 0.18, "merch_per_capita": 600},
	"product_launch": {"name": "发布会", "base_capacity": 2000, "base_price": 0, "star_weight": 0.4, "base_risk": 0.15, "merch_per_capita": 100},
	"sports_event": {"name": "体育赛事", "base_capacity": 40000, "base_price": 3600, "star_weight": 0.35, "base_risk": 0.28, "merch_per_capita": 250},
	"wedding": {"name": "婚礼庆典", "base_capacity": 300, "base_price": 50000, "star_weight": 0.1, "base_risk": 0.10, "merch_per_capita": 0},
}

const STAGES: Array = ["venue", "approval", "sponsor", "ticketing", "security", "live", "review"]
const STAGE_NAMES: Dictionary = {
	"venue": "场地租赁", "approval": "报批审批", "sponsor": "招商", "ticketing": "票务",
	"security": "安保", "live": "现场", "review": "复盘",
}

## 风险事件。
const RISK_OVERSELL: String = "oversell"
const RISK_STAMPEDE: String = "stampede"
const RISK_WEATHER: String = "weather"
const RISK_PR_CRISIS: String = "pr_crisis"
const RISK_SECURITY_FAILURE: String = "security_failure"
const RISK_ARTIST_BREACH: String = "artist_breach"
const RISKS: Array = [RISK_OVERSELL, RISK_STAMPEDE, RISK_WEATHER, RISK_PR_CRISIS, RISK_SECURITY_FAILURE, RISK_ARTIST_BREACH]

## 赞助层级与基准金额。
const SPONSOR_TIERS: Dictionary = {
	"title": {"name": "冠名赞助", "amount": 5000000},
	"gold": {"name": "金牌赞助", "amount": 2000000},
	"silver": {"name": "银牌赞助", "amount": 800000},
	"supplier": {"name": "物资赞助", "amount": 200000},
}

## 策划职业路径。
const CAREER_ROLES: Dictionary = {
	"planner": {"name": "活动策划", "exp_per_level": 100},
	"producer": {"name": "制作人", "exp_per_level": 150},
	"venue": {"name": "场地运营", "exp_per_level": 120},
	"ticketing": {"name": "票务公司", "exp_per_level": 110},
}

const SECURITY_SAFE_LEVEL: float = 0.6
const BASE_LIABILITY: int = 500000
const EXP_PER_EVENT: int = 20


# --- 数据表 ---

func event_type_keys() -> Array:
	return EVENT_TYPES.keys()


func event_type_def(event_type: String) -> Dictionary:
	if not EVENT_TYPES.has(event_type):
		return {}
	return (EVENT_TYPES[event_type] as Dictionary).duplicate(true)


func stage_names() -> Dictionary:
	return STAGE_NAMES.duplicate(true)


func sponsor_tier_keys() -> Array:
	return SPONSOR_TIERS.keys()


func sponsor_tier_def(tier: String) -> Dictionary:
	if not SPONSOR_TIERS.has(tier):
		return {}
	return (SPONSOR_TIERS[tier] as Dictionary).duplicate(true)


func career_role_keys() -> Array:
	return CAREER_ROLES.keys()


# --- 活动 ---

func new_event(event_type: String, opts: Dictionary = {}) -> Dictionary:
	if not EVENT_TYPES.has(event_type):
		event_type = "concert"
	var def: Dictionary = EVENT_TYPES[event_type]
	return {
		"id": str(opts.get("id", "event")),
		"type": event_type,
		"name": str(opts.get("name", str(def["name"]))),
		"stage": STAGES[0],
		"venue": {},
		"capacity": 0,
		"ticket_price": maxi(0, int(opts.get("ticket_price", int(def["base_price"])))),
		"sold": 0,
		"approved": false,
		"approval_delay_days": 0.0,
		"sponsors": [],
		"budget": maxi(0, int(opts.get("budget", 10000000))),
		"reputation": clampf(float(opts.get("reputation", 50.0)), 0.0, 100.0),
		"star_power": clampf(float(opts.get("star_power", 50.0)), 0.0, 100.0),
		"hype": 1.0,
		"security_level": 0.0,
		"attendance": 0,
		"revenue": 0,
		"cost": 0,
		"streaming_deal": 0,
		"merchandise_income": 0,
		"refunded": 0,
		"incidents": [],
		"risks": [],
	}


func _def(event: Dictionary) -> Dictionary:
	return EVENT_TYPES.get(str(event.get("type", "concert")), {})


# --- 流程推进 ---

func advance_stage(event: Dictionary) -> Dictionary:
	var idx: int = STAGES.find(str(event.get("stage", STAGES[0])))
	if idx < 0 or idx >= STAGES.size() - 1:
		return {"ok": false, "reason": "at_end"}
	event["stage"] = STAGES[idx + 1]
	return {"ok": true, "stage": str(event["stage"]), "stage_name": str(STAGE_NAMES[event["stage"]])}


## 场地租赁：支付场租并设定容量。
func rent_venue(event: Dictionary, venue: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var cost: int = maxi(0, int(opts.get("cost", venue.get("cost", 0))))
	if int(event.get("budget", 0)) < cost:
		return {"ok": false, "reason": "insufficient_funds", "cost": cost}
	event["budget"] = int(event["budget"]) - cost
	event["cost"] = int(event.get("cost", 0)) + cost
	event["venue"] = venue.duplicate(true)
	event["capacity"] = maxi(0, int(venue.get("capacity", 0)))
	event["stage"] = "venue"
	return {"ok": true, "cost": cost, "capacity": int(event["capacity"])}


## 报批审批：驳回则推迟天数，通过则进入招商。
func apply_approval(event: Dictionary, approved: bool, opts: Dictionary = {}) -> Dictionary:
	event["approved"] = approved
	if approved:
		event["stage"] = "sponsor"
		event["approval_delay_days"] = 0.0
	else:
		event["approval_delay_days"] = maxf(0.0, float(opts.get("delay_days", 30.0)))
		event["stage"] = "approval"
	return {"ok": true, "approved": approved, "delay_days": float(event["approval_delay_days"])}


## 招商：按赞助层级入账并记入举办方收入。
func add_sponsor(event: Dictionary, tier: String, amount: int = -1, opts: Dictionary = {}) -> Dictionary:
	if not SPONSOR_TIERS.has(tier):
		return {"ok": false, "reason": "unknown_tier"}
	var def: Dictionary = SPONSOR_TIERS[tier]
	var value: int = maxi(0, amount if amount >= 0 else int(def["amount"]))
	(event["sponsors"] as Array).append({"tier": tier, "name": str(def["name"]), "amount": value})
	event["budget"] = int(event["budget"]) + value
	event["revenue"] = int(event.get("revenue", 0)) + value
	return {"ok": true, "tier": tier, "amount": value, "sponsors": (event["sponsors"] as Array).size()}


## 安保配置：等级越高越能压降事故概率，成本越高。
func set_security(event: Dictionary, level: float, opts: Dictionary = {}) -> Dictionary:
	var lv: float = clampf(level, 0.0, 1.0)
	var cost: int = maxi(0, int(opts.get("cost", int(lv * 1000000.0))))
	if int(event.get("budget", 0)) < cost:
		return {"ok": false, "reason": "insufficient_funds", "cost": cost}
	event["budget"] = int(event["budget"]) - cost
	event["cost"] = int(event.get("cost", 0)) + cost
	event["security_level"] = lv
	return {"ok": true, "security_level": lv, "cost": cost}


## 票务销售：可超售（超过容量记入超售风险），收入按票面价。
func sell_tickets(event: Dictionary, qty: int, opts: Dictionary = {}) -> Dictionary:
	var amount: int = maxi(0, qty)
	event["sold"] = int(event.get("sold", 0)) + amount
	if bool(opts.get("oversell", false)) or int(event["sold"]) > int(event["capacity"]):
		if not (event["risks"] as Array).has(RISK_OVERSELL):
			(event["risks"] as Array).append(RISK_OVERSELL)
	var revenue: int = amount * int(event.get("ticket_price", 0))
	event["budget"] = int(event["budget"]) + revenue
	event["revenue"] = int(event.get("revenue", 0)) + revenue
	return {"ok": true, "sold": int(event["sold"]), "revenue": revenue, "oversold": int(event["sold"]) > int(event["capacity"])}


## 明星效应与主办方声誉决定预期上座率。
func expected_fill_rate(event: Dictionary) -> float:
	var star: float = clampf(float(event.get("star_power", 50.0)), 0.0, 100.0)
	var rep: float = clampf(float(event.get("reputation", 50.0)), 0.0, 100.0)
	var hype: float = maxf(0.1, float(event.get("hype", 1.0)))
	return clampf(0.3 + star / 250.0 + rep / 250.0 + (hype - 1.0) * 0.2, 0.05, 1.2)


func add_hype(event: Dictionary, amount: float) -> Dictionary:
	event["hype"] = maxf(0.1, float(event.get("hype", 1.0)) + amount)
	return {"ok": true, "hype": float(event["hype"])}


## 黄牛：被囤票从正式渠道流失，造成潜在收入损失。
func scalping(event: Dictionary, qty: int, opts: Dictionary = {}) -> Dictionary:
	var amount: int = maxi(0, qty)
	var premium: float = float(opts.get("premium", 1.5))
	var face: int = amount * int(event.get("ticket_price", 0))
	var lost: int = int(round(float(face) * (premium - 1.0)))
	event["sold"] = maxi(0, int(event.get("sold", 0)) - amount)
	if not (event["risks"] as Array).has(RISK_OVERSELL) and amount > 0:
		pass
	return {"ok": true, "hoarded": amount, "lost_revenue": lost, "premium": premium}


# --- 现场与风险 ---

## 举办活动：结算门票/周边/直播，按规则触发超售、天气、安保失效与踩踏。
func hold_event(event: Dictionary, roll: float, opts: Dictionary = {}) -> Dictionary:
	var def: Dictionary = _def(event)
	var capacity: int = int(event.get("capacity", 0))
	var sold: int = int(event.get("sold", 0))
	var attendance: int = mini(sold, capacity)
	event["attendance"] = attendance
	var gate: int = attendance * int(event.get("ticket_price", 0))
	var merch: int = attendance * int(def.get("merch_per_capita", 0))
	var streaming: int = maxi(0, int(event.get("streaming_deal", 0)))
	event["merchandise_income"] = merch
	event["revenue"] = int(event.get("revenue", 0)) + merch + streaming
	var incidents: Array = []
	var risks: Array = event["risks"]
	var prisk: float = float(def.get("base_risk", 0.2))
	# 超售判定。
	if sold > capacity or risks.has(RISK_OVERSELL):
		if not incidents.has(RISK_OVERSELL):
			incidents.append(RISK_OVERSELL)
	# 天气。
	var bad_weather: bool = bool(opts.get("bad_weather", false)) or roll < prisk * 0.3
	if bad_weather:
		incidents.append(RISK_WEATHER)
	# 安保失效。
	var security: float = clampf(float(event.get("security_level", 0.0)), 0.0, 1.0)
	var security_failed: bool = bool(opts.get("security_failure", false)) or (security < SECURITY_SAFE_LEVEL and roll < prisk * 0.5)
	if security_failed:
		incidents.append(RISK_SECURITY_FAILURE)
	# 舆情失控。
	if bool(opts.get("pr_crisis", false)) or (roll > 0.9 and float(event.get("reputation", 50.0)) < 45.0):
		incidents.append(RISK_PR_CRISIS)
	# 踩踏：超售 + 安保不足（或强制）。
	var stampede: bool = bool(opts.get("stampede", false)) or (sold > capacity and security < SECURITY_SAFE_LEVEL)
	if stampede and security_failed:
		incidents.append(RISK_STAMPEDE)
	elif stampede and bool(opts.get("stampede", false)):
		incidents.append(RISK_STAMPEDE)
	# 声誉影响：上座率高、无事故则提升，事故则下滑。
	var fill: float = float(attendance) / maxf(1.0, float(capacity))
	var rep_delta: float = (fill - 0.6) * 10.0
	for inc in incidents:
		rep_delta -= 6.0
	event["reputation"] = clampf(float(event.get("reputation", 50.0)) + rep_delta, 0.0, 100.0)
	event["incidents"] = incidents
	event["stage"] = "live"
	return {
		"ok": true, "attendance": attendance, "gate": gate, "merchandise": merch,
		"streaming": streaming, "incidents": incidents, "reputation": float(event["reputation"]),
	}


## 艺人违约：取消或迟到，触发退票与声誉下滑。
func artist_breach(event: Dictionary, roll: float, opts: Dictionary = {}) -> Dictionary:
	var risk: float = clampf(float(opts.get("risk", 0.15)), 0.0, 1.0)
	if roll >= risk and not bool(opts.get("force", false)):
		return {"ok": true, "breach": false}
	var cancelled: bool = bool(opts.get("cancelled", true)) or roll < risk * 0.5
	if not (event["risks"] as Array).has(RISK_ARTIST_BREACH):
		(event["risks"] as Array).append(RISK_ARTIST_BREACH)
	var refund: int = 0
	if cancelled:
		refund = int(event.get("sold", 0)) * int(event.get("ticket_price", 0))
		event["refunded"] = int(event.get("refunded", 0)) + refund
		event["budget"] = int(event["budget"]) - refund
		event["sold"] = 0
	event["reputation"] = clampf(float(event.get("reputation", 50.0)) - 10.0, 0.0, 100.0)
	return {"ok": true, "breach": true, "cancelled": cancelled, "refund": refund, "reputation": float(event["reputation"])}


## 退票潮：按比例退票并返还票款。
func refund_wave(event: Dictionary, ratio: float, opts: Dictionary = {}) -> Dictionary:
	var r: float = clampf(ratio, 0.0, 1.0)
	var refunded_qty: int = int(round(float(event.get("sold", 0)) * r))
	var refund: int = refunded_qty * int(event.get("ticket_price", 0))
	event["sold"] = maxi(0, int(event.get("sold", 0)) - refunded_qty)
	event["refunded"] = int(event.get("refunded", 0)) + refund
	event["budget"] = int(event["budget"]) - refund
	event["revenue"] = int(event.get("revenue", 0)) - refund
	event["reputation"] = clampf(float(event.get("reputation", 50.0)) - 5.0 * r, 0.0, 100.0)
	return {"ok": true, "refunded_qty": refunded_qty, "refund": refund, "sold": int(event["sold"])}


## 票务欺诈：假票流入，按 roll 命中造成损失与声誉伤害。
func ticket_fraud(event: Dictionary, roll: float, opts: Dictionary = {}) -> Dictionary:
	var risk: float = clampf(float(opts.get("risk", 0.2)), 0.0, 1.0)
	if roll >= risk and not bool(opts.get("force", false)):
		return {"ok": true, "fraud": false}
	var fake: int = maxi(0, int(opts.get("fake_count", 100)))
	var loss: int = fake * int(event.get("ticket_price", 0))
	event["budget"] = int(event["budget"]) - loss
	event["reputation"] = clampf(float(event.get("reputation", 50.0)) - 6.0, 0.0, 100.0)
	return {"ok": true, "fraud": true, "fake_count": fake, "loss": loss}


## 安全事故追责：赔偿与法律责任。
func accident_liability(event: Dictionary, severity: float, opts: Dictionary = {}) -> Dictionary:
	var sev: float = clampf(severity, 0.0, 1.0)
	var compensation: int = int(round(float(opts.get("base_liability", BASE_LIABILITY)) * sev))
	var legal_days: float = float(opts.get("legal_days", 0.0)) if sev >= 0.5 else 0.0
	event["budget"] = int(event["budget"]) - compensation
	event["cost"] = int(event.get("cost", 0)) + compensation
	event["reputation"] = clampf(float(event.get("reputation", 50.0)) - 15.0 * sev, 0.0, 100.0)
	var liability: Dictionary = {"severity": sev, "compensation": compensation, "legal_days": legal_days}
	(event["incidents"] as Array).append("liability")
	return {"ok": true, "liability": liability, "budget": int(event["budget"]), "reputation": float(event["reputation"])}


## 复盘：净利润、上座率、口碑与评级。
func after_action_review(event: Dictionary) -> Dictionary:
	event["stage"] = "review"
	var capacity: int = maxi(1, int(event.get("capacity", 1)))
	var fill: float = float(event.get("attendance", 0)) / float(capacity)
	var profit: int = int(event.get("revenue", 0)) - int(event.get("cost", 0))
	var incident_count: int = (event.get("incidents", []) as Array).size()
	var rating: float = clampf(fill * 70.0 + float(event.get("reputation", 50.0)) * 0.3 - float(incident_count) * 5.0, 0.0, 100.0)
	return {
		"ok": true, "profit": profit, "revenue": int(event.get("revenue", 0)),
		"cost": int(event.get("cost", 0)), "fill_rate": fill, "incidents": incident_count,
		"rating": rating, "reputation": float(event.get("reputation", 50.0)),
	}


# --- 策划职业 ---

func new_planner(role: String = "planner", opts: Dictionary = {}) -> Dictionary:
	if not CAREER_ROLES.has(role):
		role = "planner"
	return {
		"role": role,
		"level": maxi(1, int(opts.get("level", 1))),
		"exp": maxi(0, int(opts.get("exp", 0))),
		"reputation": clampf(float(opts.get("reputation", 50.0)), 0.0, 100.0),
		"events_done": 0,
	}


## 从业积累：完成活动获得经验与声誉，达阈值升级。
func career_progress(planner: Dictionary, review: Dictionary) -> Dictionary:
	var exp_gain: int = EXP_PER_EVENT + maxi(0, int(review.get("rating", 0)) / 10)
	planner["exp"] = int(planner.get("exp", 0)) + exp_gain
	planner["events_done"] = int(planner.get("events_done", 0)) + 1
	planner["reputation"] = clampf(float(planner.get("reputation", 50.0)) + 1.0, 0.0, 100.0)
	var per_level: int = int((CAREER_ROLES.get(str(planner.get("role", "planner")), {}) as Dictionary).get("exp_per_level", 100))
	var leveled: bool = false
	while int(planner["exp"]) >= per_level * int(planner["level"]) and per_level > 0:
		planner["level"] = int(planner["level"]) + 1
		leveled = true
	return {"ok": true, "level": int(planner["level"]), "exp": int(planner["exp"]), "leveled": leveled}


func _roll(forced: float, rng) -> float:
	if forced >= 0.0:
		return clampf(forced, 0.0, 1.0)
	if rng != null:
		return rng.next_float()
	return 0.0


func to_dict(event: Dictionary) -> Dictionary:
	return event.duplicate(true)


func from_dict(data: Dictionary) -> Dictionary:
	return data.duplicate(true)
