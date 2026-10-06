class_name ConsumerProtectionSystem
extends RefCounted
## 消费者保护与产品质量（R84；design D40）。
##
## 覆盖：
##   - 机制：退换货、投诉、三包、召回，含质保期与保修；
##   - 维权路径：协商 → 投诉（12315/平台）→ 消协 → 诉讼/集体维权，含举证责任；
##   - 监管：食安与质量事故引发监管处罚、赔偿与产品下架；
##   - 影响：维权结果影响商家声誉与销量，含职业打假；
##   - 边界：恶意索赔、举证困难、平台推诿、下架与召回成本。
##
## 设计取舍：
##   - 订单、商品、商家均为纯数据 Dictionary，便于存读档与 headless 测试；
##   - 维权按 CHANNELS 逐级增强（渠道权重 + 证据强度 + 举证责任修正），结果确定可测；
##   - 与民事诉讼（D12）的边界：本系统只走到“消协/投诉/集体维权”的行政与平台阶段，
##     具体诉讼程序委托 CivilSystem，不重复其立案—判决流程；
##   - 职业打假与恶意索赔以“是否滥用/超出合理范围”区分，由 roll 判定，缺省确定化。

const CHANNEL_NEGOTIATE: String = "negotiate"
const CHANNEL_PLATFORM: String = "platform"
const CHANNEL_12315: String = "hotline_12315"
const CHANNEL_ASSOCIATION: String = "consumer_association"
const CHANNEL_LITIGATION: String = "litigation"
const CHANNEL_CLASS_ACTION: String = "class_action"

const CHANNELS: Array = ["negotiate", "platform", "hotline_12315", "consumer_association", "litigation", "class_action"]
const CHANNEL_NAMES: Dictionary = {
	"negotiate": "协商", "platform": "平台投诉", "hotline_12315": "12315 投诉",
	"consumer_association": "消协调解", "litigation": "诉讼", "class_action": "集体维权",
}

## 渠道权重：越靠后强制力越强。
const CHANNEL_WEIGHTS: Dictionary = {
	"negotiate": 0.25, "platform": 0.40, "hotline_12315": 0.60,
	"consumer_association": 0.70, "litigation": 0.85, "class_action": 0.90,
}

const RETURN_WINDOW_DAYS: int = 7       # 七日无理由退货
const THREE_GUARANTEE_DAYS: int = 15    # 三包退换
const WARRANTY_DEFECT_DAYS: int = 180   # 举证责任倒置期（耐用商品六个月瑕疵）

const INCIDENT_FOOD_SAFETY: String = "food_safety"
const INCIDENT_QUALITY: String = "quality"
const INCIDENT_KINDS: Array = ["food_safety", "quality"]

const OUTCOME_NONE: String = "none"
const OUTCOME_RESOLVED: String = "resolved"
const OUTCOME_REJECTED: String = "rejected"
const OUTCOME_ESCALATED: String = "escalated"


func _roll(forced: float, rng) -> float:
	if forced >= 0.0:
		return clampf(forced, 0.0, 1.0)
	if rng != null:
		return rng.next_float()
	return 0.0


# --- 数据表 ---

func channel_keys() -> Array:
	return CHANNELS.duplicate()


func channel_names() -> Dictionary:
	return CHANNEL_NAMES.duplicate(true)


func incident_kinds() -> Array:
	return INCIDENT_KINDS.duplicate()


# --- 订单与商品 ---

func new_order(order_id: String, merchant: String, amount: int, opts: Dictionary = {}) -> Dictionary:
	return {
		"order_id": order_id,
		"merchant": merchant,
		"amount": maxi(0, amount),
		"day": int(opts.get("day", 0)),
		"category": str(opts.get("category", "general")),
		"defective": bool(opts.get("defective", false)),
		"fake": bool(opts.get("fake", false)),
		"status": "paid",
		"refunded": 0,
		"complaints": [],
	}


func new_product(name: String, opts: Dictionary = {}) -> Dictionary:
	return {
		"name": name,
		"merchant": str(opts.get("merchant", "")),
		"category": str(opts.get("category", "general")),
		"warranty_days": maxi(0, int(opts.get("warranty_days", 365))),
		"purchase_day": int(opts.get("purchase_day", 0)),
		"defect_rate": clampf(float(opts.get("defect_rate", 0.05)), 0.0, 1.0),
		"recalled": false,
		"price": maxi(0, int(opts.get("price", 10000))),
	}


# --- 退换货、三包与保修 ---

## 退换货：七日无理由或质量原因；质量原因不受窗口限制。
func request_return(order: Dictionary, days_since: int, reason: String = "no_reason", opts: Dictionary = {}) -> Dictionary:
	var quality: bool = reason == "quality" or bool(order.get("defective", false)) or bool(order.get("fake", false))
	var within: bool = days_since <= int(opts.get("window_days", RETURN_WINDOW_DAYS))
	if not quality and not within:
		return {"ok": true, "accepted": false, "reason": "out_of_window", "refund": 0}
	var refund: int = int(order.get("amount", 0))
	order["refunded"] = int(order.get("refunded", 0)) + refund
	order["status"] = "returned"
	return {
		"ok": true, "accepted": true, "quality": quality,
		"refund": refund, "reason": "quality" if quality else "no_reason",
	}


## 三包：同一故障在质保期内多次维修仍不能使用可退换。
func three_guarantee(order: Dictionary, repair_count: int, opts: Dictionary = {}) -> Dictionary:
	if repair_count < int(opts.get("repairs_required", 2)):
		return {"ok": true, "eligible": false, "reason": "repairs_not_enough"}
	var refund: int = int(order.get("amount", 0))
	order["refunded"] = int(order.get("refunded", 0)) + refund
	order["status"] = "returned"
	return {"ok": true, "eligible": true, "refund": refund}


## 保修：质保期内免费维修，逾期按比例收费。
func warranty_claim(product: Dictionary, days_used: int, opts: Dictionary = {}) -> Dictionary:
	var warranty: int = int(product.get("warranty_days", 0))
	var covered: bool = days_used <= warranty
	var fee: int = 0
	if not covered:
		var over: int = days_used - warranty
		fee = int(round(float(product.get("price", 0)) * clampf(0.1 + float(over) / 3650.0, 0.0, 0.5)))
	return {"ok": true, "covered": covered, "fee": fee, "warranty_days": warranty}


# --- 举证责任与投诉 ---

## 举证责任分配：耐用商品短期内出现瑕疵，举证责任在商家（倒置）。
func burden_of_proof(order: Dictionary, days_since: int, opts: Dictionary = {}) -> Dictionary:
	var durable: bool = str(order.get("category", "general")) in ["appliance", "electronics", "furniture", "vehicle"]
	var reversed: bool = durable and days_since <= int(opts.get("reverse_window_days", WARRANTY_DEFECT_DAYS))
	return {"ok": true, "bearer": "merchant" if reversed else "consumer", "reversed": reversed}


## 提交投诉：登记渠道；平台可能推诿。
func file_complaint(order: Dictionary, channel: String, opts: Dictionary = {}) -> Dictionary:
	if not CHANNELS.has(channel):
		return {"ok": false, "reason": "unknown_channel"}
	var complaint: Dictionary = {
		"channel": channel, "day": int(opts.get("day", 0)),
		"claim": maxi(0, int(opts.get("claim", int(order.get("amount", 0))))),
		"evidence": clampf(float(opts.get("evidence", 0.3)), 0.0, 1.0),
		"platform_evade": false,
		"status": "filed",
	}
	if channel == CHANNEL_PLATFORM:
		var evade_risk: float = clampf(float(opts.get("platform_evade_risk", 0.3)), 0.0, 1.0)
		complaint["platform_evade"] = _roll(float(opts.get("platform_roll", 1.0)), null) < evade_risk
	complaint["channel_weight"] = float(CHANNEL_WEIGHTS.get(channel, 0.3))
	(order["complaints"] as Array).append(complaint)
	return {"ok": true, "complaint": complaint, "platform_evade": bool(complaint["platform_evade"])}


# --- 维权路径 ---

## 解决纠纷：按渠道权重 + 证据强度 + 举证责任判定结果。与 CivilSystem 的诉讼衔接，
## 本系统只结算行政/平台/集体维权阶段的赔付与声誉。
## opts：channel/evidence/resolution_roll/compensation_multiple。
func resolve_dispute(order: Dictionary, merchant: Dictionary = {}, opts: Dictionary = {}, rng = null) -> Dictionary:
	var channel: String = str(opts.get("channel", CHANNEL_NEGOTIATE))
	if not CHANNELS.has(channel):
		return {"ok": false, "reason": "unknown_channel"}
	var evidence: float = clampf(float(opts.get("evidence", 0.3)), 0.0, 1.0)
	var weight: float = float(CHANNEL_WEIGHTS.get(channel, 0.3))
	var burden: Dictionary = burden_of_proof(order, int(opts.get("days_since", 0)), opts)
	# 举证责任在商家时，消费者胜算上浮。
	var prob: float = clampf(weight * 0.6 + evidence * 0.5 + (0.1 if bool(burden["reversed"]) else 0.0), 0.02, 0.98)
	var roll: float = _roll(float(opts.get("resolution_roll", -1.0)), rng)
	var success: bool = roll < prob
	var multiple: float = float(opts.get("compensation_multiple", 1.0))
	# 假货/缺陷适用惩罚性赔偿。
	if bool(order.get("fake", false)) or bool(order.get("defective", false)):
		multiple = maxf(multiple, float(opts.get("punitive_multiple", 3.0)))
	var compensation: int = int(round(float(order.get("amount", 0)) * multiple)) if success else 0
	var outcome: String = OUTCOME_RESOLVED if success else OUTCOME_REJECTED
	order["status"] = "resolved" if success else order.get("status", "paid")
	if success and not merchant.is_empty():
		merchant["reputation"] = clampf(float(merchant.get("reputation", 0.5)) - 0.15, 0.0, 1.0)
		merchant["sales"] = maxf(0.0, float(merchant.get("sales", 1.0)) - 0.05)
		merchant["compensation_paid"] = int(merchant.get("compensation_paid", 0)) + compensation
	elif not success and not merchant.is_empty():
		# 消费者败诉，商家声誉略升、可能反诉恶意索赔。
		merchant["reputation"] = clampf(float(merchant.get("reputation", 0.5)) + 0.02, 0.0, 1.0)
	return {
		"ok": true, "channel": channel, "success": success, "outcome": outcome,
		"probability": prob, "compensation": compensation,
		"bearer": str(burden["bearer"]),
	}


## 集体维权：合并多笔订单，按参与人数与总金额增强胜算。
func class_action(orders: Array, merchant: Dictionary = {}, opts: Dictionary = {}, rng = null) -> Dictionary:
	if orders.is_empty():
		return {"ok": false, "reason": "no_orders"}
	var total: int = 0
	for o in orders:
		total += int((o as Dictionary).get("amount", 0))
	var participants: int = orders.size()
	var prob: float = clampf(float(CHANNEL_WEIGHTS[CHANNEL_CLASS_ACTION]) * 0.6 + clampf(float(participants) / 100.0, 0.0, 0.3), 0.02, 0.98)
	var roll: float = _roll(float(opts.get("resolution_roll", -1.0)), rng)
	var success: bool = roll < prob
	var compensation: int = int(round(float(total) * float(opts.get("compensation_multiple", 1.0)))) if success else 0
	if success and not merchant.is_empty():
		merchant["reputation"] = clampf(float(merchant.get("reputation", 0.5)) - 0.3, 0.0, 1.0)
		merchant["sales"] = maxf(0.0, float(merchant.get("sales", 1.0)) - 0.2)
	return {
		"ok": true, "participants": participants, "total_amount": total,
		"success": success, "compensation": compensation, "probability": prob,
	}


# --- 监管：事故处罚、赔偿与下架 ---

## 食安/质量事故：监管处罚、对消费者赔偿、产品下架。
func regulate_incident(merchant: Dictionary, incident: String, opts: Dictionary = {}) -> Dictionary:
	if not INCIDENT_KINDS.has(incident):
		return {"ok": false, "reason": "unknown_incident"}
	var victims: int = maxi(0, int(opts.get("victims", 1)))
	var severity: float = clampf(float(opts.get("severity", 0.5)), 0.0, 1.0)
	var base_fine: float = 500000.0 if incident == INCIDENT_FOOD_SAFETY else 200000.0
	var fine: int = int(round(base_fine * (1.0 + severity * 3.0)))
	var compensation: int = int(round(float(victims) * float(opts.get("per_victim", 50000)) * (1.0 + severity)))
	var delisted: bool = severity >= float(opts.get("delist_threshold", 0.6)) or incident == INCIDENT_FOOD_SAFETY and severity >= 0.5
	merchant["fines"] = int(merchant.get("fines", 0)) + fine
	merchant["compensation_paid"] = int(merchant.get("compensation_paid", 0)) + compensation
	merchant["reputation"] = clampf(float(merchant.get("reputation", 0.5)) - severity * 0.5, 0.0, 1.0)
	merchant["sales"] = maxf(0.0, float(merchant.get("sales", 1.0)) - severity * 0.4)
	if delisted:
		merchant["delisted"] = true
	return {
		"ok": true, "incident": incident, "fine": fine, "compensation": compensation,
		"delisted": delisted, "victims": victims,
	}


## 召回：按受影响数量结算成本，并下架产品。
func recall(product: Dictionary, affected: int, opts: Dictionary = {}) -> Dictionary:
	var cost: int = int(round(float(maxi(0, affected)) * float(opts.get("unit_cost", 5000))))
	product["recalled"] = true
	return {
		"ok": true, "affected": maxi(0, affected), "cost": cost,
		"recalled": true, "brand_damage": clampf(float(opts.get("brand_damage", 0.2)), 0.0, 1.0),
	}


# --- 职业打假与边界 ---

## 职业打假：以牟利为目的的批量索赔。合理范围内受支持，超出即视为恶意索赔。
func professional_fraud(order: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var claims: int = maxi(1, int(opts.get("claim_count", 1)))
	var abusive: bool = claims > int(opts.get("abusive_threshold", 20))
	var success: bool = bool(opts.get("defect_confirmed", bool(order.get("defective", false)) or bool(order.get("fake", false)))) and not abusive
	var compensation: int = 0
	if success:
		compensation = int(round(float(order.get("amount", 0)) * float(opts.get("compensation_multiple", 3.0))))
	return {
		"ok": true, "professional": true, "abusive": abusive,
		"success": success, "compensation": compensation,
		"reason": "abusive_claim" if abusive else ("supported" if success else "no_defect"),
	}


## 恶意索赔：无缺陷却索要赔偿。可被识别并驳回，严重者构成敲诈。
func malicious_claim(order: Dictionary, merchant: Dictionary = {}, opts: Dictionary = {}, rng = null) -> Dictionary:
	var has_defect: bool = bool(order.get("defective", false)) or bool(order.get("fake", false))
	if has_defect:
		return {"ok": true, "malicious": false, "reason": "legitimate"}
	var detected: bool = _roll(float(opts.get("detect_roll", -1.0)), rng) < clampf(float(opts.get("detect_risk", 0.5)), 0.0, 1.0)
	if detected and not merchant.is_empty():
		# 商家反诉敲诈，声誉小幅回升。
		merchant["reputation"] = clampf(float(merchant.get("reputation", 0.5)) + 0.03, 0.0, 1.0)
	return {
		"ok": true, "malicious": true, "detected": detected,
		"outcome": "rejected", "claim": maxi(0, int(order.get("amount", 0))),
	}


## 平台推诿：以概率判定平台是否推诿，推诿可要求升级到 12315。
func platform_buck_pass(opts: Dictionary = {}, rng = null) -> Dictionary:
	var risk: float = clampf(float(opts.get("evade_risk", 0.4)), 0.0, 1.0)
	var evaded: bool = _roll(float(opts.get("roll", -1.0)), rng) < risk
	return {"ok": true, "evaded": evaded, "escalate_to": CHANNEL_12315 if evaded else ""}


## 商家影响汇总：按维权结果计算声誉与销量变化。
func merchant_effects(merchant: Dictionary, outcome: String, opts: Dictionary = {}) -> Dictionary:
	var rep_delta: float = 0.0
	var sales_delta: float = 0.0
	match outcome:
		OUTCOME_RESOLVED, "lost":
			rep_delta = -0.15
			sales_delta = -0.1
		OUTCOME_REJECTED, "won":
			rep_delta = 0.05
			sales_delta = 0.0
		_:
			rep_delta = 0.0
	merchant["reputation"] = clampf(float(merchant.get("reputation", 0.5)) + rep_delta, 0.0, 1.0)
	merchant["sales"] = maxf(0.0, float(merchant.get("sales", 1.0)) + sales_delta)
	return {"ok": true, "reputation": float(merchant["reputation"]), "sales": float(merchant["sales"])}


# --- 序列化 ---

func to_dict(state: Dictionary) -> Dictionary:
	return state.duplicate(true)


func from_dict(data: Dictionary) -> Dictionary:
	return data.duplicate(true)
