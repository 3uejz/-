class_name MetaphysicsSystem
extends RefCounted
## 玄学、命理与民俗信仰（R87；design D43）。
##
## 覆盖：
##   - 服务：算命、风水、占星、看相、取名、开运、驱邪，支持线上与线下；
##   - 真实性：多数从业者为心理安慰、话术与诈骗，成功率接近随机（基准 0.5），
##     不改变现实因果；仅异常者（D44）可能有真实能力，通过入参 real_ability 表示；
##   - 心理作用：安慰剂与确认偏误影响心情与决策倾向，但属性与事件结果不被改变；
##   - 经营与风险：经营玄学业务，投诉、举报与诈骗追责（R22/R84），大师人设翻车；
##   - 民俗信仰：民间信仰、禁忌、节日仪式、护身符、许愿，影响心情与社交；
##   - 边界：组织化迷信、与灰产勾结、真实能力者与骗子的模糊界线（D44）。
##
## 设计取舍：
##   - 服务与从业者为纯 Dictionary，便于存读档与 headless 测试；
##   - 「无真实能力不改变因果」是硬约束：consult 永远返回
##     attributes_changed=false、event_outcome_changed=false，安慰剂只作用于心情；
##   - 有真实能力者（real_ability=true）才允许 reality_changed/事件结果被改变；
##   - 随机性由注入 roll/rng 决定，缺省确定化。

## 玄学服务。base_rate 为无真实能力时的成功率（统一 0.5，接近随机）。
const BaselineScript = preload("res://sim/baseline.gd")

const SERVICES: Dictionary = {
	"fortune": {"name": "算命", "fee": 20000, "risk": 0.20, "base_rate": 0.5},
	"fengshui": {"name": "风水", "fee": 50000, "risk": 0.25, "base_rate": 0.5},
	"astrology": {"name": "占星", "fee": 30000, "risk": 0.20, "base_rate": 0.5},
	"physiognomy": {"name": "看相", "fee": 20000, "risk": 0.20, "base_rate": 0.5},
	"naming": {"name": "取名", "fee": 30000, "risk": 0.15, "base_rate": 0.5},
	"luck_opening": {"name": "开运", "fee": 50000, "risk": 0.35, "base_rate": 0.5},
	"exorcism": {"name": "驱邪", "fee": 80000, "risk": 0.40, "base_rate": 0.5},
}

const MODES: Array = ["online", "offline"]
const MODE_NAMES: Dictionary = {"online": "线上", "offline": "线下"}

## 民俗信仰活动：只影响心情/社交/意义，不改变属性与事件结果。
const FOLK_PRACTICES: Dictionary = {
	"taboo": {"name": "禁忌", "mood": 1.0, "social": 0.5},
	"festival_ritual": {"name": "节日仪式", "mood": 4.0, "social": 3.0},
	"amulet": {"name": "护身符", "mood": 3.0, "social": 0.0},
	"wish": {"name": "许愿", "mood": 3.0, "social": 1.0},
}

## 安慰剂/确认偏误带来的心情与决策倾向上限。
const PLACEBO_MOOD: float = BaselineScript.META_PLACEBO_MOOD
const CONFIRMATION_BIAS: float = BaselineScript.META_CONFIRMATION_BIAS


func services() -> Array:
	return SERVICES.keys()


func service_def(key: String) -> Dictionary:
	if not SERVICES.has(key):
		return {}
	return (SERVICES[key] as Dictionary).duplicate(true)


func modes() -> Array:
	return MODES.duplicate()


func folk_practices() -> Array:
	return FOLK_PRACTICES.keys()


func new_practitioner(id: String, opts: Dictionary = {}) -> Dictionary:
	return {
		"id": id,
		"name": str(opts.get("name", id)),
		"real_ability": bool(opts.get("real_ability", false)),
		"scamming": bool(opts.get("scamming", false)),
		"skill": clampf(float(opts.get("skill", 0.5)), 0.0, 1.0),
		"reputation": clampf(float(opts.get("reputation", 0.5)), 0.0, 1.0),
		"income": maxi(0, int(opts.get("income", 0))),
		"complaints": 0,
	}


func new_client() -> Dictionary:
	return {"mood": 50.0, "stress": 40.0, "belief": 0.0, "social": 0.0, "last_consult": ""}


func _roll(forced: float, rng) -> float:
	if forced >= 0.0:
		return clampf(forced, 0.0, 1.0)
	if rng != null:
		return rng.next_float()
	return 0.0


# --- 咨询服务 ---

## 咨询：无真实能力者成功率接近随机（0.5），不改变属性与事件结果；
## 有真实能力者（real_ability=true）才可能改变现实因果。
## opts 可含 mode、roll、event_related。
func consult(practitioner: Dictionary, service: String, client: Dictionary = {}, opts: Dictionary = {}, rng = null) -> Dictionary:
	if not SERVICES.has(service):
		return {"ok": false, "reason": "unknown_service"}
	var s: Dictionary = SERVICES[service]
	var mode: String = str(opts.get("mode", "offline"))
	if not MODES.has(mode):
		return {"ok": false, "reason": "unknown_mode"}
	var real: bool = bool(practitioner.get("real_ability", false))
	var skill: float = clampf(float(practitioner.get("skill", 0.5)), 0.0, 1.0)
	# 无真实能力：成功率固定为基准 0.5（接近随机，与话术/精神无关）；有真实能力才提升。
	var prob: float = 0.5
	if real:
		prob = clampf(0.75 + skill * 0.2, 0.5, 0.98)
	var roll: float = _roll(float(opts.get("roll", -1.0)), rng)
	var success: bool = roll < prob
	var scam: bool = bool(practitioner.get("scamming", false)) and not real

	var fee: int = int(round(float(s["fee"]) * (1.0 + skill * 0.5)))
	var result: Dictionary = {
		"ok": true, "service": service, "service_name": str(s["name"]),
		"mode": mode, "real_ability": real, "fee": fee,
		"probability": prob, "roll": roll, "success": success,
		"reality_changed": real and success,
		"attributes_changed": false,
		"event_outcome_changed": real and success and bool(opts.get("event_related", false)),
		"scam": scam,
		"claimed": _claim(service, success),
	}
	# 心理安慰：无论真假都产生少量心情改善（安慰剂），但绝不改变属性。
	var mood_delta: float = 0.0
	if not client.is_empty():
		mood_delta = PLACEBO_MOOD if success else -1.0
		client["mood"] = clampf(float(client.get("mood", 50.0)) + mood_delta, 0.0, 100.0)
		client["belief"] = clampf(float(client.get("belief", 0.0)) + float(s["risk"]), 0.0, 1.0)
		client["last_consult"] = service
	result["mood_delta"] = mood_delta
	result["confirmation_bias"] = CONFIRMATION_BIAS if (not real and success) else 0.0
	if not client.is_empty():
		result["mood"] = float(client["mood"])
	return result


func _claim(service: String, success: bool) -> String:
	match service:
		"fortune":
			return "近期有贵人相助" if success else "近期宜静不宜动"
		"fengshui":
			return "宅内气场需调整" if success else "方位尚可"
		"astrology":
			return "星象显示转运在即" if success else "星象平淡"
		"physiognomy":
			return "面相福厚" if success else "面相平平"
		"naming":
			return "新名可补五行" if success else "旧名亦可"
		"luck_opening":
			return "开运后诸事顺遂" if success else "开运收效有限"
		"exorcism":
			return "邪祟已驱散" if success else "邪祟未净"
		_:
			return ""


## 安慰剂与确认偏误：只影响心情与决策倾向，明确声明属性与事件结果不变。
func apply_placebo(client: Dictionary, result: Dictionary, opts: Dictionary = {}) -> Dictionary:
	if not bool(result.get("ok", false)):
		return {"ok": false, "reason": "invalid_result"}
	var success: bool = bool(result.get("success", false))
	var mood_delta: float = PLACEBO_MOOD if success else -1.0
	client["mood"] = clampf(float(client.get("mood", 50.0)) + mood_delta, 0.0, 100.0)
	var bias: float = CONFIRMATION_BIAS if success else 0.0
	return {
		"ok": true, "mood_delta": mood_delta, "decision_bias": bias,
		"attributes_changed": false, "event_outcome_changed": false,
	}


# --- 经营与风险 ---

func new_business(name: String, opts: Dictionary = {}) -> Dictionary:
	return {
		"name": name,
		"income": maxi(0, int(opts.get("income", 0))),
		"customers": 0,
		"complaints": 0,
		"reports": 0,
		"reputation": clampf(float(opts.get("reputation", 0.5)), 0.0, 1.0),
		"under_investigation": false,
	}


## 营业：成功获客入账，存在被投诉概率（由注入 roll 判定）。
func operate_business(business: Dictionary, opts: Dictionary = {}, rng = null) -> Dictionary:
	var customers: int = maxi(1, int(opts.get("customers", 1)))
	var earned: int = customers * maxi(1, int(opts.get("fee", 20000)))
	business["income"] = int(business.get("income", 0)) + earned
	business["customers"] = int(business.get("customers", 0)) + customers
	var complaint_rate: float = clampf(float(opts.get("complaint_rate", 0.15)), 0.0, 1.0)
	var complained: bool = _roll(float(opts.get("roll", -1.0)), rng) < complaint_rate
	if complained:
		business["complaints"] = int(business.get("complaints", 0)) + 1
	return {"ok": true, "earned": earned, "customers": customers, "complained": complained, "income": int(business["income"])}


## 投诉/举报：累计越多越可能被立案调查与追责。
func file_complaint(business: Dictionary, opts: Dictionary = {}) -> Dictionary:
	business["complaints"] = int(business.get("complaints", 0)) + 1
	var filed: bool = bool(opts.get("report", false))
	if filed:
		business["reports"] = int(business.get("reports", 0)) + 1
	return {"ok": true, "complaints": int(business["complaints"]), "reports": int(business["reports"])}


## 诈骗追责：举报量达标且查处成功则罚款、降声誉、立案。
func investigate_fraud(business: Dictionary, opts: Dictionary = {}, rng = null) -> Dictionary:
	var reports: int = int(business.get("reports", 0))
	var threshold: int = int(opts.get("threshold", 3))
	if reports < threshold:
		return {"ok": false, "reason": "insufficient_reports", "reports": reports}
	var convicted: bool = _roll(float(opts.get("roll", -1.0)), rng) < float(opts.get("convict_rate", 0.7))
	var fine: int = 0
	if convicted:
		fine = maxi(0, int(opts.get("fine", 300000)))
		business["income"] = int(business.get("income", 0)) - fine
		business["reputation"] = clampf(float(business.get("reputation", 0.0)) - 0.6, 0.0, 1.0)
		business["under_investigation"] = true
	return {"ok": true, "convicted": convicted, "fine": fine, "reputation": float(business["reputation"])}


## 大师人设翻车：声誉崩塌，业务量骤降。
func master_fall(business: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var severity: float = clampf(float(opts.get("severity", 0.5)), 0.0, 1.0)
	business["reputation"] = clampf(float(business.get("reputation", 0.0)) - severity, 0.0, 1.0)
	var loss: int = int(round(float(business.get("income", 0)) * severity * 0.5))
	business["income"] = maxi(0, int(business.get("income", 0)) - loss)
	return {"ok": true, "reputation": float(business["reputation"]), "income_loss": loss}


# --- 民俗信仰 ---

func use_folk_practice(client: Dictionary, practice: String, opts: Dictionary = {}) -> Dictionary:
	if not FOLK_PRACTICES.has(practice):
		return {"ok": false, "reason": "unknown_practice"}
	var p: Dictionary = FOLK_PRACTICES[practice]
	var mood: float = float(p["mood"])
	var social: float = float(p["social"])
	client["mood"] = clampf(float(client.get("mood", 50.0)) + mood, 0.0, 100.0)
	client["social"] = float(client.get("social", 0.0)) + social
	return {
		"ok": true, "practice": practice, "name": str(p["name"]),
		"mood_delta": mood, "social_delta": social,
		"attributes_changed": false, "event_outcome_changed": false,
	}


# --- 边界情况 ---

## 组织化迷信：规模化的迷信组织，影响力与风险并存。
func organized_superstition(members: int, opts: Dictionary = {}) -> Dictionary:
	var influence: float = clampf(float(members) / 1000.0, 0.0, 1.0)
	return {
		"ok": true, "members": maxi(0, members), "influence": influence,
		"risk": clampf(influence * float(opts.get("risk_mult", 0.8)), 0.0, 1.0),
	}


## 与灰产勾结：玄学业务为灰产导流，可能被牵连追责。
func collude_gray_market(business: Dictionary, opts: Dictionary = {}, rng = null) -> Dictionary:
	var entangled: bool = true
	var exposed: bool = _roll(float(opts.get("roll", -1.0)), rng) < float(opts.get("exposure_risk", 0.3))
	if exposed:
		business["reputation"] = clampf(float(business.get("reputation", 0.0)) - 0.5, 0.0, 1.0)
		business["under_investigation"] = true
	return {"ok": true, "entangled": entangled, "exposed": exposed, "criminal": exposed}


## 真实能力者与骗子的模糊界线：外表与话术相同，仅凭表现无法区分。
func blur_real_and_fake(practitioner: Dictionary) -> Dictionary:
	var real: bool = bool(practitioner.get("real_ability", false))
	var scamming: bool = bool(practitioner.get("scamming", false))
	var label: String = "普通从业者"
	if real:
		label = "疑似真实能力者"
	elif scamming:
		label = "疑似诈骗者"
	return {
		"ok": true, "real_ability": real, "scamming": scamming,
		"label": label,
		# 外观不可区分：真实能力者与非能力者对外表现一致。
		"indistinguishable": true,
	}


# --- 序列化 ---

func to_dict(state: Dictionary) -> Dictionary:
	return state.duplicate(true)


func from_dict(data: Dictionary) -> Dictionary:
	return data.duplicate(true)
