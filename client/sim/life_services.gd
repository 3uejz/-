class_name LifeServicesSystem
extends RefCounted
## 家庭与生活服务业（R93；design D49）。
##
## 覆盖：
##   - 婚恋：相亲婚介、婚礼策划、婚庆、婚纱摄影（与 D11 恋爱结婚打通）；
##   - 家政：家政、月嫂、育儿嫂、保洁、钟点工、照料服务（与养育、养老打通）；
##   - 宠物：寄养、美容、医疗、训练、殡葬全链（联动 D11）；
##   - 其他：维修、开锁、搬家、洗护、代驾、收纳、跑腿；
##   - 风险与信任：背景核查、服务纠纷或事故触发投诉、赔偿与法律后果；
##   - 边界：服务标准化与平台抽成。
##
## 设计取舍：
##   - 服务者、订单、纠纷均为纯数据 Dictionary，便于存读档与 headless 测试；
##   - 事故 / 纠纷判定统一走 _roll(forced, rng)，缺省确定化；
##   - 与既有系统解耦：婚育 / 养老 / 宠物本体与法律后果以结构化返回值交给上层编排。

## 服务目录：名称、平台抽成比例与固有风险度。
const SERVICE_CATEGORIES: Dictionary = {
	"matchmaking": {"name": "相亲婚介", "platform_cut": 0.20, "risk": 0.15},
	"wedding": {"name": "婚礼策划", "platform_cut": 0.15, "risk": 0.30},
	"housekeeping": {"name": "家政保洁", "platform_cut": 0.25, "risk": 0.30},
	"maternity": {"name": "月嫂育儿", "platform_cut": 0.20, "risk": 0.35},
	"pet": {"name": "宠物服务", "platform_cut": 0.20, "risk": 0.20},
	"repair": {"name": "维修开锁", "platform_cut": 0.20, "risk": 0.15},
	"moving": {"name": "搬家收纳", "platform_cut": 0.18, "risk": 0.18},
	"delivery": {"name": "代驾跑腿", "platform_cut": 0.30, "risk": 0.20},
}

## 宠物服务全链：名称与顺序。
const PET_CHAIN: Dictionary = {
	"boarding": {"name": "寄养", "order": 1},
	"grooming": {"name": "美容", "order": 2},
	"medical": {"name": "医疗", "order": 3},
	"training": {"name": "训练", "order": 4},
	"funeral": {"name": "殡葬", "order": 5},
}

var _seq: int = 0


func _roll(forced: float, rng) -> float:
	if forced >= 0.0:
		return clampf(forced, 0.0, 1.0)
	if rng != null:
		return rng.next_float()
	return 0.0


# --- 数据表 ---

func category_keys() -> Array:
	return SERVICE_CATEGORIES.keys()


func category_def(key: String) -> Dictionary:
	if not SERVICE_CATEGORIES.has(key):
		return {}
	return (SERVICE_CATEGORIES[key] as Dictionary).duplicate(true)


func category_name(key: String) -> String:
	return str((SERVICE_CATEGORIES.get(key, {}) as Dictionary).get("name", key))


func pet_service_keys() -> Array:
	return PET_CHAIN.keys()


func pet_service_def(key: String) -> Dictionary:
	if not PET_CHAIN.has(key):
		return {}
	return (PET_CHAIN[key] as Dictionary).duplicate(true)


# --- 服务者与信任 ---

## 注册服务者：评分与信任为初始值，背景状态未知。
func new_provider(opts: Dictionary = {}) -> Dictionary:
	_seq += 1
	return {
		"id": str(opts.get("id", "provider.%d" % _seq)),
		"name": str(opts.get("name", "服务者")),
		"category": str(opts.get("category", "housekeeping")),
		"rating": clampf(float(opts.get("rating", 0.6)), 0.0, 1.0),
		"trust": clampf(float(opts.get("trust", 0.6)), 0.0, 1.0),
		"background": "unknown",
		"orders": [],
		"disputes": [],
	}


## 背景核查：记录概率决定是否标记，标记则显著降低信任。
func background_check(provider: Dictionary, opts: Dictionary = {}, rng = null) -> Dictionary:
	var record_rate: float = clampf(float(opts.get("record_rate", 0.15)), 0.0, 1.0)
	var roll: float = _roll(float(opts.get("roll", -1.0)), rng)
	var flagged: bool = roll < record_rate
	provider["background"] = "flagged" if flagged else "clean"
	if flagged:
		provider["trust"] = clampf(float(provider["trust"]) - 0.4, 0.0, 1.0)
	else:
		provider["trust"] = clampf(float(provider["trust"]) + 0.1, 0.0, 1.0)
	return {"ok": true, "status": str(provider["background"]), "flagged": flagged, "criminal_record": flagged}


# --- 订单 ---

## 下单：按服务类别生成订单，价格由上层给定。
func new_order(provider: Dictionary, opts: Dictionary = {}) -> Dictionary:
	_seq += 1
	var cat: String = str(provider.get("category", "housekeeping"))
	var order: Dictionary = {
		"id": str(opts.get("id", "order.%d" % _seq)),
		"category": cat,
		"service": str(opts.get("service", cat)),
		"price": maxi(0, int(opts.get("price", 1000))),
		"status": "open",
		"dispute": null,
	}
	(provider["orders"] as Array).append(order)
	return {"ok": true, "order": order}


# --- 婚恋 ---

## 相亲婚介：从候选池中择优，兼容度与掷骰共同决定是否配对成功。
func matchmaking(provider: Dictionary, candidates: Array, opts: Dictionary = {}, rng = null) -> Dictionary:
	if candidates == null or candidates.is_empty():
		return {"ok": false, "reason": "no_candidates"}
	var threshold: float = clampf(float(opts.get("threshold", 0.5)), 0.0, 1.0)
	var roll: float = _roll(float(opts.get("roll", -1.0)), rng)
	var best: Dictionary = {}
	var best_score: float = -1.0
	for cand in candidates:
		var c: Dictionary = cand
		var score: float = clampf(float(c.get("compatibility", 0.5)) + float(c.get("wealth", 0.0)) * 0.2, 0.0, 1.0)
		if score > best_score:
			best_score = score
			best = c
	var matched: bool = best_score >= threshold and roll < clampf(best_score + 0.2, 0.0, 0.95)
	if matched:
		provider["trust"] = clampf(float(provider["trust"]) + 0.05, 0.0, 1.0)
	return {"ok": true, "matched": matched, "match": best.duplicate(true), "score": best_score}


## 婚礼策划：品质越高成本越高，事故概率随品质与信任下降。
func wedding_plan(provider: Dictionary, order: Dictionary, opts: Dictionary = {}, rng = null) -> Dictionary:
	var budget: int = maxi(0, int(opts.get("budget", 50000)))
	var quality: float = clampf(float(opts.get("quality", provider.get("rating", 0.6))), 0.0, 1.0)
	var cost: int = int(round(float(budget) * (0.8 + quality * 0.4)))
	var accident_prob: float = clampf((1.0 - quality) * 0.4 + (1.0 - float(provider.get("trust", 0.6))) * 0.3, 0.0, 0.95)
	var roll: float = _roll(float(opts.get("roll", -1.0)), rng)
	var accident: bool = roll < accident_prob
	order["status"] = "done"
	order["accident"] = accident
	return {"ok": true, "accident": accident, "quality": quality, "cost": cost, "accident_prob": accident_prob}


# --- 家政与月嫂 ---

## 家政 / 月嫂服务：低信任抬升盗窃概率，低评分抬升失职概率。
func housekeeping_order(provider: Dictionary, order: Dictionary, opts: Dictionary = {}, rng = null) -> Dictionary:
	var trust: float = float(provider.get("trust", 0.6))
	var negligence_prob: float = clampf((1.0 - float(provider.get("rating", 0.6))) * 0.4, 0.0, 0.9)
	var theft_prob: float = clampf((1.0 - trust) * 0.3, 0.0, 0.9)
	var roll: float = _roll(float(opts.get("roll", -1.0)), rng)
	var incident: String = ""
	if roll < theft_prob:
		incident = "theft"
	elif roll < theft_prob + negligence_prob:
		incident = "negligence"
	order["status"] = "done"
	order["incident"] = incident
	return {"ok": true, "incident": incident, "trust": trust, "theft_prob": theft_prob, "negligence_prob": negligence_prob}


# --- 宠物服务 ---

## 宠物服务链单步：寄养 / 美容 / 医疗 / 训练 / 殡葬。
func pet_service_order(provider: Dictionary, order: Dictionary, opts: Dictionary = {}, rng = null) -> Dictionary:
	if not PET_CHAIN.has(str(order.get("service", ""))):
		return {"ok": false, "reason": "unknown_pet_service"}
	var roll: float = _roll(float(opts.get("roll", -1.0)), rng)
	var incident_prob: float = clampf((1.0 - float(provider.get("rating", 0.6))) * 0.25, 0.0, 0.8)
	var incident: bool = roll < incident_prob
	order["status"] = "done"
	order["incident"] = incident
	return {"ok": true, "service": str(order.get("service")), "completed": not incident, "incident": incident}


# --- 风险、纠纷与信任 ---

## 服务事故 / 纠纷：由类别固有风险与掷骰判定，命中则写入纠纷并打击评分与信任。
func service_incident(provider: Dictionary, order: Dictionary, opts: Dictionary = {}, rng = null) -> Dictionary:
	var severity: float = clampf(float(opts.get("severity", 0.5)), 0.0, 1.0)
	var base: float = clampf(float((SERVICE_CATEGORIES.get(str(provider.get("category", "")), {}) as Dictionary).get("risk", 0.2)), 0.0, 1.0)
	var roll: float = _roll(float(opts.get("roll", -1.0)), rng)
	var occurred: bool = roll < base
	var kind: String = str(opts.get("kind", "dispute"))
	if occurred:
		(provider["disputes"] as Array).append({"order": str(order.get("id", "")), "kind": kind, "severity": severity})
		provider["trust"] = clampf(float(provider["trust"]) - severity * 0.3, 0.0, 1.0)
		provider["rating"] = clampf(float(provider["rating"]) - severity * 0.2, 0.0, 1.0)
	return {"ok": true, "occurred": occurred, "kind": kind, "severity": severity}


## 纠纷处理：投诉、赔偿与是否上升为法律后果。
func resolve_dispute(provider: Dictionary, order: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var severity: float = clampf(float(opts.get("severity", 0.5)), 0.0, 1.0)
	var claim: int = maxi(0, int(opts.get("claim", 0)))
	var compensation: int = int(round(float(claim) * (0.5 + severity * 0.5)))
	var complaint: bool = bool(opts.get("complain", true))
	var legal: bool = severity >= float(opts.get("legal_threshold", 0.7))
	order["status"] = "disputed"
	return {"ok": true, "complaint": complaint, "compensation": compensation, "legal": legal, "severity": severity}


# --- 平台与标准化 ---

## 平台抽成：按类别抽成比例拆分订单价格。
func platform_commission(price: int, category: String, opts: Dictionary = {}) -> Dictionary:
	var default_cut: float = float((SERVICE_CATEGORIES.get(category, {}) as Dictionary).get("platform_cut", 0.2))
	var cut: float = clampf(float(opts.get("cut", default_cut)), 0.0, 0.9)
	var commission: int = int(round(float(price) * cut))
	return {"ok": true, "price": price, "commission": commission, "provider_received": price - commission, "cut": cut}


## 服务标准化：投入提升标准等级，降低类别固有风险。
func standardization(category: String, opts: Dictionary = {}) -> Dictionary:
	if not SERVICE_CATEGORIES.has(category):
		return {"ok": false, "reason": "unknown_category"}
	var invest: int = maxi(0, int(opts.get("invest", 100000)))
	var level: float = clampf(float(opts.get("level", 0.5)), 0.0, 1.0)
	return {"ok": true, "category": category, "level": level, "invest": invest, "risk_reduction": level * 0.3}


# --- 序列化 ---

func to_dict(state: Dictionary) -> Dictionary:
	return state.duplicate(true)


func from_dict(data: Dictionary) -> Dictionary:
	return data.duplicate(true)
