class_name MunicipalSystem
extends RefCounted
## 市政公用与邮政（R82；design D38）。
##
## 覆盖：
##   - 市政设施：道路/桥梁/公园/环卫/污水/照明/公厕，含养护、施工与状态衰减；
##   - 邮政快递：收寄/分拣/时效/丢件/破损/理赔，含快递员职业路径与爆仓；
##   - 特许经营：公用事业特许与政府购买服务，服务质量考核与投诉；
##   - 施工影响：市政施工或设施停用影响通行与生活，产生扰民与投诉；
##   - 边界：道路反复开挖、公园维护缺位、快递爆仓。
##
## 设计取舍：
##   - 城市、包裹、快递员均为纯数据 Dictionary，便于存读档与 headless 测试；
##   - 设施损耗与施工工期用“天数”确定性推进；丢件/破损由注入 roll 判定，缺省确定化；
##   - 特许经营只结算本地服务质量考核与投诉，公用事业的真值由后端宏观承接（不重复）；
##   - 施工对通行的影响以系数表达，具体路径规划仍归 Transport（D2），不重复实现路网。

const BaselineScript = preload("res://sim/baseline.gd")

const FACILITY_ROAD: String = "road"
const FACILITY_BRIDGE: String = "bridge"
const FACILITY_PARK: String = "park"
const FACILITY_SANITATION: String = "sanitation"
const FACILITY_SEWAGE: String = "sewage"
const FACILITY_LIGHTING: String = "lighting"
const FACILITY_PUBLIC_TOILET: String = "public_toilet"

const FACILITY_TYPES: Array = ["road", "bridge", "park", "sanitation", "sewage", "lighting", "public_toilet"]

const FACILITY_NAMES: Dictionary = {
	"road": "道路", "bridge": "桥梁", "park": "公园", "sanitation": "环卫",
	"sewage": "污水", "lighting": "照明", "public_toilet": "公厕",
}

## 各类设施的初始健康度与养护难度（难度越大，同等投入提升越少）。
const FACILITY_BASE: Dictionary = {
	"road": {"condition": 0.85, "maintain_cost": 800000, "decay": 0.03},
	"bridge": {"condition": 0.90, "maintain_cost": 1200000, "decay": 0.02},
	"park": {"condition": 0.80, "maintain_cost": 300000, "decay": 0.05},
	"sanitation": {"condition": 0.85, "maintain_cost": 400000, "decay": 0.03},
	"sewage": {"condition": 0.80, "maintain_cost": 600000, "decay": 0.03},
	"lighting": {"condition": 0.90, "maintain_cost": 250000, "decay": 0.02},
	"public_toilet": {"condition": 0.75, "maintain_cost": 200000, "decay": 0.05},
}

const FACILITY_GRADE_THRESHOLD: float = BaselineScript.MUNICIPAL_FACILITY_GRADE_THRESHOLD
const ROAD_REOPEN_WINDOW_DAYS: int = BaselineScript.MUNICIPAL_ROAD_REOPEN_WINDOW_DAYS
const NEGLECT_CONDITION: float = BaselineScript.MUNICIPAL_NEGLECT_CONDITION
const NEGLECT_MAINTENANCE_DAYS: int = BaselineScript.MUNICIPAL_NEGLECT_MAINTENANCE_DAYS

## 邮政包裹状态。
const PARCEL_ACCEPTED: String = "accepted"
const PARCEL_SORTED: String = "sorted"
const PARCEL_DELIVERED: String = "delivered"
const PARCEL_LOST: String = "lost"
const PARCEL_DAMAGED: String = "damaged"

## 快递员职业路径。
const COURIER_RANKS: Array = [
	{"key": "trainee", "name": "实习快递员", "deliveries_required": 0, "income": 3000},
	{"key": "courier", "name": "快递员", "deliveries_required": 100, "income": 5000},
	{"key": "senior", "name": "资深快递员", "deliveries_required": 500, "income": 7000},
	{"key": "station_chief", "name": "网点主管", "deliveries_required": 1500, "income": 12000},
	{"key": "regional_manager", "name": "区域经理", "deliveries_required": 4000, "income": 25000},
]

## 特许经营与政府购买服务。quality_pass_line 为服务质量合格线（0..1）。
const FRANCHISE_SERVICES: Dictionary = {
	"water_supply": {"name": "供水特许", "facility": "sewage", "license_required": true, "base_fee": 5000000, "quality_pass_line": 0.6},
	"waste_collection": {"name": "垃圾清运", "facility": "sanitation", "license_required": true, "base_fee": 2000000, "quality_pass_line": 0.5},
	"street_cleaning": {"name": "道路保洁", "facility": "sanitation", "license_required": false, "base_fee": 1200000, "quality_pass_line": 0.5},
	"bus_operation": {"name": "公交运营", "facility": "road", "license_required": true, "base_fee": 3000000, "quality_pass_line": 0.6},
	"park_maintenance": {"name": "公园养护", "facility": "park", "license_required": false, "base_fee": 800000, "quality_pass_line": 0.5},
}


func _roll(forced: float, rng) -> float:
	if forced >= 0.0:
		return clampf(forced, 0.0, 1.0)
	if rng != null:
		return rng.next_float()
	return 0.0


# --- 数据表 ---

func facility_types() -> Array:
	return FACILITY_TYPES.duplicate()


func facility_name(key: String) -> String:
	return str(FACILITY_NAMES.get(key, key))


func courier_ranks() -> Array:
	return COURIER_RANKS.duplicate(true)


func franchise_service_keys() -> Array:
	return FRANCHISE_SERVICES.keys()


func franchise_service_def(key: String) -> Dictionary:
	if not FRANCHISE_SERVICES.has(key):
		return {}
	return (FRANCHISE_SERVICES[key] as Dictionary).duplicate(true)


# --- 城市 ---

func new_city(population: int, opts: Dictionary = {}) -> Dictionary:
	var facilities: Dictionary = {}
	for t in FACILITY_TYPES:
		var base: Dictionary = FACILITY_BASE[t]
		facilities[t] = {
			"type": t,
			"condition": clampf(float(opts.get(t, base["condition"])), 0.0, 1.0),
			"maintain_budget": 0,
			"last_maintained_day": 0,
			"under_construction": false,
			"construction_days_left": 0.0,
			"construction_total_days": 0.0,
			"last_excavation_day": -ROAD_REOPEN_WINDOW_DAYS - 1,
		}
	return {
		"population": maxi(0, population),
		"day": int(opts.get("day", 0)),
		"facilities": facilities,
		"franchises": [],
		"complaints": [],
		"nuisance": 0.0,
	}


func _facility(city: Dictionary, facility_type: String) -> Dictionary:
	return city["facilities"].get(facility_type, {})


func facility_condition(city: Dictionary, facility_type: String) -> float:
	var f: Dictionary = _facility(city, facility_type)
	return clampf(float(f.get("condition", 0.0)), 0.0, 1.0)


func facility_grade(city: Dictionary, facility_type: String) -> String:
	var c: float = facility_condition(city, facility_type)
	if c >= 0.85:
		return "优"
	if c >= 0.7:
		return "良"
	if c >= FACILITY_GRADE_THRESHOLD:
		return "合格"
	return "失修"


# --- 养护与老化 ---

## 养护投入：提升健康度，成本与设施难度相关。
func maintain_facility(city: Dictionary, facility_type: String, amount: int) -> Dictionary:
	if not FACILITY_TYPES.has(facility_type):
		return {"ok": false, "reason": "unknown_facility"}
	var f: Dictionary = city["facilities"][facility_type]
	var base: Dictionary = FACILITY_BASE[facility_type]
	var gain: float = clampf(float(maxi(0, amount)) / float(base["maintain_cost"]), 0.0, 0.5)
	f["condition"] = clampf(float(f["condition"]) + gain, 0.0, 1.0)
	f["maintain_budget"] = int(f["maintain_budget"]) + maxi(0, amount)
	f["last_maintained_day"] = int(city.get("day", 0))
	city["nuisance"] = maxf(0.0, float(city["nuisance"]) - gain * 0.2)
	return {"ok": true, "facility": facility_type, "condition": float(f["condition"]), "cost": maxi(0, amount)}


## 老化：维护缺位时健康度逐年下降；公园维护缺位衰减更快。
func age_facilities(city: Dictionary, years: float) -> Dictionary:
	var y: float = maxf(0.0, years)
	var facilities: Dictionary = city["facilities"]
	for t in facilities.keys():
		var f: Dictionary = facilities[t]
		var base: Dictionary = FACILITY_BASE[str(t)]
		var decay: float = float(base["decay"]) * y
		if str(t) == FACILITY_PARK and float(f["condition"]) < NEGLECT_CONDITION:
			decay *= 1.5
		f["condition"] = clampf(float(f["condition"]) - decay, 0.0, 1.0)
	city["day"] = int(city.get("day", 0)) + int(round(y * 365.0))
	return {"ok": true, "neglected_parks": inspect_parks(city)}


## 巡检公园：长期未养护且健康度低于阈值的公园判定为维护缺位。
func inspect_parks(city: Dictionary) -> Array:
	var out: Array = []
	var day: int = int(city.get("day", 0))
	var f: Dictionary = _facility(city, FACILITY_PARK)
	if f.is_empty():
		return out
	var idle_days: int = day - int(f.get("last_maintained_day", 0))
	if float(f["condition"]) < NEGLECT_CONDITION or idle_days > NEGLECT_MAINTENANCE_DAYS:
		out.append({
			"facility": FACILITY_PARK, "condition": float(f["condition"]),
			"idle_days": idle_days, "neglected": true,
		})
	return out


# --- 施工 ---

func start_construction(city: Dictionary, facility_type: String, opts: Dictionary = {}) -> Dictionary:
	if not FACILITY_TYPES.has(facility_type):
		return {"ok": false, "reason": "unknown_facility"}
	var f: Dictionary = city["facilities"][facility_type]
	if bool(f["under_construction"]):
		return {"ok": false, "reason": "already_under_construction", "days_left": float(f["construction_days_left"])}
	var days: float = maxf(1.0, float(opts.get("days", 30.0)))
	f["under_construction"] = true
	f["construction_days_left"] = days
	f["construction_total_days"] = days
	city["nuisance"] = clampf(float(city["nuisance"]) + 0.1, 0.0, 1.0)
	return {
		"ok": true, "facility": facility_type, "days_left": days,
		"commute_factor": commute_impact(city),
	}


func advance_construction(city: Dictionary, days: float) -> Dictionary:
	var d: float = maxf(0.0, days)
	var completed: Array = []
	var facilities: Dictionary = city["facilities"]
	for t in facilities.keys():
		var f: Dictionary = facilities[t]
		if not bool(f["under_construction"]):
			continue
		f["construction_days_left"] = maxf(0.0, float(f["construction_days_left"]) - d)
		if float(f["construction_days_left"]) <= 0.0:
			f["under_construction"] = false
			f["condition"] = clampf(float(f["condition"]) + 0.1, 0.0, 1.0)
			completed.append(str(t))
			city["nuisance"] = maxf(0.0, float(city["nuisance"]) - 0.1)
	city["day"] = int(city.get("day", 0)) + int(round(d))
	return {"ok": true, "completed": completed, "commute_factor": commute_impact(city)}


## 开挖登记：同一道路在窗口期内被反复开挖，构成“拉链路”，额外成本与扰民。
func start_excavation(city: Dictionary, facility_type: String, opts: Dictionary = {}) -> Dictionary:
	if not FACILITY_TYPES.has(facility_type):
		return {"ok": false, "reason": "unknown_facility"}
	var f: Dictionary = city["facilities"][facility_type]
	var day: int = int(opts.get("day", city.get("day", 0)))
	var last: int = int(f.get("last_excavation_day", -ROAD_REOPEN_WINDOW_DAYS - 1))
	var repeated: bool = (day - last) <= ROAD_REOPEN_WINDOW_DAYS
	f["last_excavation_day"] = day
	f["condition"] = clampf(float(f["condition"]) - 0.05, 0.0, 1.0)
	var complaint: Dictionary = {}
	if repeated and str(facility_type) == FACILITY_ROAD:
		city["nuisance"] = clampf(float(city["nuisance"]) + 0.2, 0.0, 1.0)
		complaint = report_nuisance(city, {"source": "repeated_excavation", "severity": 0.6, "day": day})
	return {
		"ok": true, "facility": facility_type, "repeated": repeated,
		"extra_cost": int(round(float(FACILITY_BASE[facility_type]["maintain_cost"]) * (0.3 if repeated else 0.0))),
		"complaint": complaint,
	}


## 施工/设施停用对通行的影响系数（1.0 为正常，越大越堵）。
func commute_impact(city: Dictionary) -> float:
	var factor: float = 1.0
	var facilities: Dictionary = city["facilities"]
	for t in [FACILITY_ROAD, FACILITY_BRIDGE]:
		if not facilities.has(t):
			continue
		var f: Dictionary = facilities[t]
		factor += (1.0 - clampf(float(f["condition"]), 0.0, 1.0)) * 0.4
		if bool(f["under_construction"]):
			factor += 0.4
	return clampf(factor, 1.0, 3.0)


# --- 扰民与投诉 ---

func report_nuisance(city: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var complaint: Dictionary = {
		"source": str(opts.get("source", "")),
		"severity": clampf(float(opts.get("severity", 0.3)), 0.0, 1.0),
		"day": int(opts.get("day", city.get("day", 0))),
		"resolved": false,
	}
	(city["complaints"] as Array).append(complaint)
	city["nuisance"] = clampf(float(city["nuisance"]) + float(complaint["severity"]) * 0.1, 0.0, 1.0)
	return complaint


func resolve_complaint(city: Dictionary, index: int, opts: Dictionary = {}) -> Dictionary:
	var complaints: Array = city["complaints"]
	if index < 0 or index >= complaints.size():
		return {"ok": false, "reason": "no_such_complaint"}
	var c: Dictionary = complaints[index]
	c["resolved"] = true
	c["resolution"] = str(opts.get("resolution", "handled"))
	city["nuisance"] = maxf(0.0, float(city["nuisance"]) - float(c["severity"]) * 0.1)
	return {"ok": true, "complaint": c, "nuisance": float(city["nuisance"])}


func unresolved_complaints(city: Dictionary) -> int:
	var n: int = 0
	for c in (city["complaints"] as Array):
		if not bool((c as Dictionary).get("resolved", false)):
			n += 1
	return n


# --- 邮政快递 ---

func new_postal_hub(opts: Dictionary = {}) -> Dictionary:
	return {
		"capacity_per_day": maxi(1, int(opts.get("capacity_per_day", 1000))),
		"pending": [],
		"processed": 0,
		"lost": 0,
		"damaged": 0,
		"claims_paid": 0,
		"couriers": [],
		"day": int(opts.get("day", 0)),
	}


func new_parcel(id: String, opts: Dictionary = {}) -> Dictionary:
	return {
		"id": id,
		"status": PARCEL_ACCEPTED,
		"weight_kg": maxf(0.0, float(opts.get("weight_kg", 1.0))),
		"distance_km": maxf(0.0, float(opts.get("distance_km", 100.0))),
		"insured": bool(opts.get("insured", false)),
		"value": maxi(0, int(opts.get("value", 10000))),
		"priority": str(opts.get("priority", "normal")),
		"lost": false,
		"damaged": false,
		"delivered_day": -1,
		"delay_days": 0,
	}


func accept_parcel(hub: Dictionary, parcel: Dictionary) -> Dictionary:
	parcel["status"] = PARCEL_ACCEPTED
	(hub["pending"] as Array).append(parcel)
	return {"ok": true, "pending": (hub["pending"] as Array).size()}


## 预计时效（天）：距离越远越久，爆仓时顺延。
func estimate_delivery(hub: Dictionary, parcel: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var distance: float = float(parcel.get("distance_km", 0.0))
	var expected: int = int(ceili(distance / float(opts.get("speed_km_per_day", 500.0)))) + 1
	var backlog: int = (hub["pending"] as Array).size()
	var overload: bool = backlog > int(hub["capacity_per_day"])
	var delay: int = (2 if overload else 0) + int(backlog / int(hub["capacity_per_day"]))
	return {"ok": true, "expected_days": expected, "delay_days": delay, "overloaded": overload}


## 发运一件包裹：分拣 → 投递，含丢件/破损/时效判定。
## opts：loss_risk/damage_risk/sla_days/loss_roll/damage_roll。
func ship(hub: Dictionary, parcel: Dictionary, opts: Dictionary = {}, rng = null) -> Dictionary:
	parcel["status"] = PARCEL_SORTED
	var est: Dictionary = estimate_delivery(hub, parcel, opts)
	var overloaded: bool = bool(est["overloaded"])
	var distance: float = float(parcel.get("distance_km", 0.0))
	var loss_risk: float = clampf(
		float(opts.get("loss_risk", 0.01)) + (0.05 if overloaded else 0.0) + distance / 100000.0,
		0.0, 0.9)
	var damage_risk: float = clampf(
		float(opts.get("damage_risk", 0.02)) + (0.05 if overloaded else 0.0) + float(parcel.get("weight_kg", 1.0)) / 100.0,
		0.0, 0.9)
	var lost: bool = _roll(float(opts.get("loss_roll", -1.0)), rng) < loss_risk
	var damaged: bool = false
	if not lost:
		damaged = _roll(float(opts.get("damage_roll", -1.0)), rng) < damage_risk
	var delay: int = int(est["delay_days"])
	var sla: int = int(opts.get("sla_days", int(est["expected_days"]) + 1))
	var on_time: bool = false
	if lost:
		parcel["status"] = PARCEL_LOST
		parcel["lost"] = true
		hub["lost"] = int(hub["lost"]) + 1
	elif damaged:
		parcel["status"] = PARCEL_DAMAGED
		parcel["damaged"] = true
		hub["damaged"] = int(hub["damaged"]) + 1
		on_time = (int(est["expected_days"]) + delay) <= sla
	else:
		parcel["status"] = PARCEL_DELIVERED
		parcel["delivered_day"] = int(hub.get("day", 0)) + int(est["expected_days"]) + delay
		on_time = (int(est["expected_days"]) + delay) <= sla
	parcel["delay_days"] = delay
	hub["processed"] = int(hub["processed"]) + 1
	hub["day"] = int(hub.get("day", 0)) + 1
	# 发运即出队，避免重复处理。
	var pending: Array = hub["pending"]
	pending.erase(parcel)
	return {
		"ok": true, "parcel": str(parcel.get("id", "")), "status": str(parcel["status"]),
		"lost": lost, "damaged": damaged, "on_time": on_time, "overloaded": overloaded,
		"expected_days": int(est["expected_days"]), "delay_days": delay,
		"lost_risk": loss_risk, "damage_risk": damage_risk,
	}


## 爆仓程度：待处理量 / 日处理容量（>1 即爆仓）。
func postal_overload(hub: Dictionary) -> float:
	return float((hub["pending"] as Array).size()) / maxf(1.0, float(hub["capacity_per_day"]))


## 理赔：仅丢失或破损可赔；保价按货值，未保价按上限。
func file_claim(hub: Dictionary, parcel: Dictionary, opts: Dictionary = {}) -> Dictionary:
	# 已理赔过的包裹不重复理赔。
	if bool(parcel.get("claimed", false)):
		return {"ok": false, "reason": "already_claimed", "paid": 0}
	if not bool(parcel.get("lost", false)) and not bool(parcel.get("damaged", false)):
		return {"ok": true, "paid": 0, "reason": "no_claim"}
	var value: int = int(parcel.get("value", 0))
	var paid: int = 0
	if bool(parcel.get("insured", false)):
		paid = value
	else:
		paid = mini(value, maxi(0, int(opts.get("max_uninsured", 10000))))
	parcel["claimed"] = true
	hub["claims_paid"] = int(hub["claims_paid"]) + paid
	return {"ok": true, "paid": paid, "insured": bool(parcel.get("insured", false))}


# --- 快递员职业路径 ---

func new_courier(id: String, opts: Dictionary = {}) -> Dictionary:
	return {
		"id": id,
		"name": str(opts.get("name", id)),
		"deliveries": maxi(0, int(opts.get("deliveries", 0))),
		"rank_index": 0,
		"income": int((COURIER_RANKS[0] as Dictionary)["income"]),
		"reputation": clampf(float(opts.get("reputation", 0.5)), 0.0, 1.0),
		"station": str(opts.get("station", "")),
	}


## 揽投一件：累加业绩并尝试晋升；破损/丢件会扣声誉。
func courier_deliver(courier: Dictionary, parcel: Dictionary, opts: Dictionary = {}) -> Dictionary:
	courier["deliveries"] = int(courier["deliveries"]) + 1
	var penalty: float = 0.0
	if bool(parcel.get("damaged", false)) or bool(parcel.get("lost", false)):
		penalty = 0.03
	courier["reputation"] = clampf(float(courier["reputation"]) - penalty, 0.0, 1.0)
	var promoted: Dictionary = promote_courier(courier)
	return {
		"ok": true, "deliveries": int(courier["deliveries"]),
		"reputation": float(courier["reputation"]), "promoted": bool(promoted["promoted"]),
		"rank_index": int(courier["rank_index"]),
	}


## 按累计揽投量晋升。
func promote_courier(courier: Dictionary) -> Dictionary:
	var deliveries: int = int(courier.get("deliveries", 0))
	var target: int = 0
	for i in range(COURIER_RANKS.size()):
		if deliveries >= int((COURIER_RANKS[i] as Dictionary)["deliveries_required"]):
			target = i
	courier["rank_index"] = target
	courier["income"] = int((COURIER_RANKS[target] as Dictionary)["income"])
	return {"ok": true, "promoted": target > 0, "rank_index": target, "income": int(courier["income"])}


# --- 特许经营与政府购买服务 ---

## 授予特许经营：需具备对应资质，登记合同并进入质量考核。
func grant_franchise(city: Dictionary, service: String, operator: Dictionary, opts: Dictionary = {}) -> Dictionary:
	if not FRANCHISE_SERVICES.has(service):
		return {"ok": false, "reason": "unknown_service"}
	var def: Dictionary = FRANCHISE_SERVICES[service]
	if bool(def["license_required"]) and not bool(operator.get("license", false)):
		return {"ok": false, "reason": "no_license"}
	var contract: Dictionary = {
		"service": service, "name": str(def["name"]),
		"operator": str(operator.get("id", "")),
		"fee": int(opts.get("fee", def["base_fee"])),
		"quality_score": 0.0, "quality_grade": "",
		"complaints": 0, "active": true,
	}
	(city["franchises"] as Array).append(contract)
	return {"ok": true, "contract": contract}


## 服务质量考核：按得分评级，低于合格线扣减服务费并累计整改。
func assess_service_quality(city: Dictionary, contract: Dictionary, score: float, opts: Dictionary = {}) -> Dictionary:
	var s: float = clampf(score, 0.0, 1.0)
	contract["quality_score"] = s
	var pass_line: float = 0.5
	var key: String = str(contract.get("service", ""))
	if FRANCHISE_SERVICES.has(key):
		pass_line = float((FRANCHISE_SERVICES[key] as Dictionary)["quality_pass_line"])
	var grade: String = "D"
	if s >= 0.85:
		grade = "A"
	elif s >= 0.7:
		grade = "B"
	elif s >= pass_line:
		grade = "C"
	contract["quality_grade"] = grade
	var penalty: int = 0
	if s < pass_line:
		penalty = int(round(float(contract.get("fee", 0)) * (pass_line - s)))
		contract["active"] = false
	return {"ok": true, "grade": grade, "passed": s >= pass_line, "penalty": penalty, "pass_line": pass_line}


## 特许经营投诉：计入合同并在反复投诉后触发复核。
func franchise_complaint(city: Dictionary, contract: Dictionary, opts: Dictionary = {}) -> Dictionary:
	contract["complaints"] = int(contract.get("complaints", 0)) + 1
	var c: Dictionary = report_nuisance(city, {
		"source": "franchise:" + str(contract.get("service", "")),
		"severity": clampf(float(opts.get("severity", 0.3)), 0.0, 1.0),
	})
	var review: bool = int(contract["complaints"]) >= 3
	return {"ok": true, "complaints": int(contract["complaints"]), "review": review, "complaint": c}


## 政府购买服务：一次性结算预算并登记合同。
func government_purchase(city: Dictionary, service: String, budget: int, opts: Dictionary = {}) -> Dictionary:
	if not FRANCHISE_SERVICES.has(service):
		return {"ok": false, "reason": "unknown_service"}
	var def: Dictionary = FRANCHISE_SERVICES[service]
	var contract: Dictionary = {
		"service": service, "name": str(def["name"]),
		"operator": str(opts.get("operator", "government")),
		"fee": maxi(0, budget), "quality_score": 0.0, "quality_grade": "",
		"complaints": 0, "active": true, "purchase": true,
	}
	(city["franchises"] as Array).append(contract)
	return {"ok": true, "contract": contract, "budget": maxi(0, budget)}


# --- 序列化 ---

func to_dict(state: Dictionary) -> Dictionary:
	return state.duplicate(true)


func from_dict(data: Dictionary) -> Dictionary:
	return data.duplicate(true)
