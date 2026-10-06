class_name TransportInfraSystem
extends RefCounted
## 交通基建与航运（R94；design D50）。
##
## 覆盖：
##   - 建设：公路、铁路、高铁、港口、机场、隧道、桥梁的建设，并经招投标承接（联动 D47）；
##   - 运营：航运、航空与物流网络经营，维护票价、班期与准点率；
##   - 区域影响：基建投用改变区域可达性、地价、GDP 与人口流动（联动 D9、D47）；
##   - 网络效应：枢纽与线路形成网络，影响换乘（D2）与物流；
##   - 结算：建设周期、成本、安全、运营盈亏与公益性线路的政府补贴；
##   - 边界：工程超支延期、重大事故、航线受国际局势影响、垄断与定价监管。
##
## 设计取舍：
##   - 项目、区域、线路均为纯数据 Dictionary，便于存读档与 headless 测试；
##   - 事故 / 国际扰动判定统一走 _roll(forced, rng)，缺省确定化；
##   - 与既有系统解耦：招投标评分、区域大盘、国际局势以入参或结构化返回值交给上层编排。

## 基建类型：名称、基准成本、基准工期（天）、运力与公益性（可补贴）。
const INFRA_TYPES: Dictionary = {
	"highway": {"name": "公路", "base_cost": 50000000, "base_days": 180.0, "capacity": 1.0, "public_good": true},
	"railway": {"name": "铁路", "base_cost": 200000000, "base_days": 365.0, "capacity": 2.0, "public_good": true},
	"highspeed_rail": {"name": "高铁", "base_cost": 800000000, "base_days": 720.0, "capacity": 3.0, "public_good": true},
	"port": {"name": "港口", "base_cost": 500000000, "base_days": 540.0, "capacity": 3.0, "public_good": false},
	"airport": {"name": "机场", "base_cost": 1200000000, "base_days": 900.0, "capacity": 4.0, "public_good": false},
	"tunnel": {"name": "隧道", "base_cost": 300000000, "base_days": 400.0, "capacity": 1.5, "public_good": true},
	"bridge": {"name": "桥梁", "base_cost": 250000000, "base_days": 360.0, "capacity": 1.5, "public_good": true},
}

## 运营模式：名称与基准成本比。
const MODES: Dictionary = {
	"shipping": {"name": "航运", "cost_ratio": 0.85},
	"aviation": {"name": "航空", "cost_ratio": 0.92},
	"logistics": {"name": "物流", "cost_ratio": 0.80},
}

var _seq: int = 0


func _roll(forced: float, rng) -> float:
	if forced >= 0.0:
		return clampf(forced, 0.0, 1.0)
	if rng != null:
		return rng.next_float()
	return 0.0


# --- 数据表 ---

func infra_type_keys() -> Array:
	return INFRA_TYPES.keys()


func infra_type_def(key: String) -> Dictionary:
	if not INFRA_TYPES.has(key):
		return {}
	return (INFRA_TYPES[key] as Dictionary).duplicate(true)


func infra_type_name(key: String) -> String:
	return str((INFRA_TYPES.get(key, {}) as Dictionary).get("name", key))


func mode_keys() -> Array:
	return MODES.keys()


func mode_def(key: String) -> Dictionary:
	if not MODES.has(key):
		return {}
	return (MODES[key] as Dictionary).duplicate(true)


# --- 建设：立项、招投标、施工 ---

## 立项：规模缩放基准成本与工期。
func new_infra_project(opts: Dictionary = {}) -> Dictionary:
	_seq += 1
	var t: String = str(opts.get("type", "highway"))
	var def: Dictionary = INFRA_TYPES.get(t, INFRA_TYPES["highway"])
	var scale: float = clampf(float(opts.get("scale", 1.0)), 0.1, 10.0)
	var cost: int = int(round(float(def["base_cost"]) * scale))
	var days: float = float(def["base_days"]) * scale
	return {
		"id": str(opts.get("id", "infra.%d" % _seq)),
		"type": t,
		"region": str(opts.get("region", "r0")),
		"cost_estimate": cost,
		"spent": 0,
		"budget": maxi(cost, int(opts.get("budget", cost))),
		"days_total": days,
		"progress": 0.0,
		"delayed_days": 0.0,
		"status": "planned",
		"quality": clampf(float(opts.get("quality", 0.6)), 0.0, 1.0),
		"capacity": float(def["capacity"]) * scale,
		"subsidy": 0,
		"accident": false,
	}


## 招投标：价格、资质与关系加权评分，最高分者中标。
func tender_infra(project: Dictionary, bids: Array, opts: Dictionary = {}, rng = null) -> Dictionary:
	if bids == null or bids.is_empty():
		return {"ok": false, "reason": "no_bids"}
	var weight_price: float = float(opts.get("weight_price", 0.6))
	var weight_qual: float = float(opts.get("weight_qual", 0.3))
	var weight_rel: float = float(opts.get("weight_rel", 0.1))
	var min_price: float = -1.0
	for b in bids:
		var p: float = float((b as Dictionary).get("price", 0.0))
		if min_price < 0.0 or p < min_price:
			min_price = p
	if min_price <= 0.0:
		min_price = 1.0
	var best: Dictionary = {}
	var best_score: float = -1e30
	for b in bids:
		var bd: Dictionary = b
		var price: float = float(bd.get("price", 0.0))
		var price_score: float = min_price / maxf(1.0, price)
		var score: float = price_score * weight_price + float(bd.get("qualification_score", 0.5)) * weight_qual + float(bd.get("relationship", 0.0)) * weight_rel
		if score > best_score:
			best_score = score
			best = bd
	project["status"] = "awarded"
	project["operator"] = str(best.get("id", ""))
	return {"ok": true, "winner": str(best.get("id", "")), "score": best_score, "min_price": min_price}


## 施工推进：质量越低超支越多；工期随掷骰延长；进度满则建成。
func build(project: Dictionary, opts: Dictionary = {}, rng = null) -> Dictionary:
	var pace: float = clampf(float(opts.get("pace", 0.5)), 0.0, 1.0)
	var roll: float = _roll(float(opts.get("roll", -1.0)), rng)
	var overrun_rate: float = clampf(float(opts.get("overrun_rate", 0.15)) + (1.0 - float(project.get("quality", 0.6))) * 0.2, 0.0, 1.0)
	var overrun: int = int(round(float(project.get("cost_estimate", 0)) * overrun_rate * roll))
	var delay: float = float(opts.get("delay_days", 0.0)) + float(project.get("days_total", 0.0)) * 0.1 * roll
	project["spent"] = int(project.get("spent", 0)) + overrun
	project["delayed_days"] = float(project.get("delayed_days", 0.0)) + delay
	project["progress"] = clampf(float(project.get("progress", 0.0)) + pace, 0.0, 1.0)
	if float(project["progress"]) >= 1.0:
		project["status"] = "built"
	return {"ok": true, "progress": float(project["progress"]), "overrun": overrun, "delay_days": delay, "status": str(project["status"])}


# --- 运营 ---

## 运营一期：按票价、需求与运力算收入与盈亏，并给出准点率。
func operate(project: Dictionary, opts: Dictionary = {}, rng = null) -> Dictionary:
	var mode: String = str(opts.get("mode", "logistics"))
	var default_ratio: float = float((MODES.get(mode, {}) as Dictionary).get("cost_ratio", 0.9))
	var fare: float = maxf(0.0, float(opts.get("fare", 50.0)))
	var demand: float = maxf(0.0, float(opts.get("demand", 1.0)))
	var load: float = clampf(demand * float(project.get("capacity", 1.0)) / maxf(1.0, float(opts.get("supply", 1.0))), 0.0, 1.5)
	var revenue: int = int(round(fare * load * float(opts.get("riders", 100000.0))))
	var cost: int = int(round(float(revenue) * float(opts.get("cost_ratio", default_ratio))))
	var roll: float = _roll(float(opts.get("roll", -1.0)), rng)
	var on_time: float = clampf(float(opts.get("base_on_time", 0.9)) - (1.0 - float(project.get("quality", 0.6))) * 0.3 - roll * 0.1, 0.0, 1.0)
	var profit: int = revenue - cost + int(project.get("subsidy", 0))
	return {"ok": true, "revenue": revenue, "cost": cost, "profit": profit, "load": load, "on_time_rate": on_time, "mode": mode}


# --- 区域影响与网络效应 ---

## 区域影响：投用提升可达性、地价、GDP 与人口流动。
func regional_impact(project: Dictionary, region: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var capacity: float = float(project.get("capacity", 1.0))
	if not region.has("accessibility"):
		region["accessibility"] = 0.5
	region["accessibility"] = clampf(float(region["accessibility"]) + capacity * 0.1, 0.0, 1.0)
	var land_delta: float = capacity * 0.08
	var old_land: float = float(region.get("land_price", 10000.0))
	var old_gdp: float = float(region.get("gdp", 1000000.0))
	var old_pop: float = float(region.get("population", 100000.0))
	region["land_price"] = old_land * (1.0 + land_delta)
	region["gdp"] = old_gdp * (1.0 + land_delta * 1.5)
	var pop_delta: float = capacity * 0.02 * float(opts.get("migration", 1.0))
	region["population"] = old_pop * (1.0 + pop_delta)
	return {
		"ok": true,
		"accessibility": float(region["accessibility"]),
		"land_delta": land_delta,
		"gdp": float(region["gdp"]),
		"population": float(region["population"]),
		"population_delta": float(region["population"]) - old_pop,
	}


## 网络效应：线路密度与枢纽数决定换乘效率与物流增益。
func network_effect(nodes: Array, routes: Array, opts: Dictionary = {}) -> Dictionary:
	var n: int = nodes.size() if nodes != null else 0
	var r: int = routes.size() if routes != null else 0
	var hub_count: int = 0
	if nodes != null:
		for nd in nodes:
			if bool((nd as Dictionary).get("hub", false)):
				hub_count += 1
	var connectivity: float = 0.0
	if n > 1:
		connectivity = clampf(float(r) / float(n * (n - 1) / 2), 0.0, 1.0)
	var transfer: float = clampf(connectivity * 0.7 + float(hub_count) * 0.1, 0.0, 1.0)
	var logistics: float = clampf(connectivity * 0.6 + float(hub_count) * 0.15, 0.0, 2.0)
	return {"ok": true, "connectivity": connectivity, "transfer_efficiency": transfer, "logistics_gain": logistics, "hub_count": hub_count}


# --- 结算、补贴与风险 ---

## 政府补贴：公益性线路可获补贴并计入项目。
func subsidy(project: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var public_good: bool = bool(opts.get("public_good", bool((INFRA_TYPES.get(str(project.get("type", "")), {}) as Dictionary).get("public_good", false))))
	var amount: int = maxi(0, int(opts.get("amount", int(float(project.get("cost_estimate", 0)) * 0.2))))
	var granted: int = amount if public_good else 0
	project["subsidy"] = int(project.get("subsidy", 0)) + granted
	return {"ok": true, "granted": granted, "subsidy": int(project["subsidy"]), "public_good": public_good}


## 结算：汇总建设周期、成本、安全与运营盈亏。
func settle(project: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var accident: bool = bool(project.get("accident", false))
	var safety: float = clampf(float(project.get("quality", 0.6)) - (0.3 if accident else 0.0), 0.0, 1.0)
	return {
		"ok": true,
		"construction_days": float(project.get("days_total", 0.0)) + float(project.get("delayed_days", 0.0)),
		"cost": int(project.get("spent", 0)),
		"budget": int(project.get("budget", 0)),
		"safety": safety,
		"operating_profit": int(opts.get("operating_profit", 0)),
		"subsidy": int(project.get("subsidy", 0)),
	}


## 重大事故：偷工减料与低质量抬升概率，命中则损失且可能致死。
func infra_accident(project: Dictionary, opts: Dictionary = {}, rng = null) -> Dictionary:
	var cut: float = clampf(float(opts.get("cut_corners", 0.0)), 0.0, 1.0)
	var prob: float = clampf(float(opts.get("base_prob", 0.05)) + cut * 0.5 + (1.0 - float(project.get("quality", 0.6))) * 0.2, 0.0, 0.95)
	var roll: float = _roll(float(opts.get("roll", -1.0)), rng)
	var occurred: bool = roll < prob
	var severity: float = clampf(float(opts.get("severity", 0.6)), 0.0, 1.0)
	var loss: int = int(round(severity * float(project.get("cost_estimate", 0)) * 0.1)) if occurred else 0
	var deaths: int = int(round(severity * 5.0 * cut)) if occurred else 0
	if occurred:
		project["accident"] = true
		project["quality"] = clampf(float(project.get("quality", 0.6)) - severity * 0.3, 0.0, 1.0)
	return {"ok": true, "occurred": occurred, "severity": severity, "loss": loss, "deaths": deaths, "prob": prob}


## 垄断与定价监管：市占率超阈值触发限价与罚款。
func monopoly_regulation(opts: Dictionary = {}) -> Dictionary:
	var market_share: float = clampf(float(opts.get("market_share", 0.5)), 0.0, 1.0)
	var price: float = maxf(0.0, float(opts.get("price", 100.0)))
	var threshold: float = clampf(float(opts.get("threshold", 0.7)), 0.0, 1.0)
	var action: String = "none"
	var price_cap: float = 0.0
	var fine: int = 0
	if market_share >= threshold:
		action = "price_cap"
		price_cap = price * 0.8
		fine = int(round(float(opts.get("revenue", 0)) * 0.05))
	return {"ok": true, "action": action, "price_cap": price_cap, "fine": fine, "market_share": market_share}


## 国际局势扰动：敏感度决定航线是否中断并产生损失。
func international_disruption(route: Dictionary, opts: Dictionary = {}, rng = null) -> Dictionary:
	var sensitivity: float = clampf(float(opts.get("sensitivity", 0.5)), 0.0, 1.0)
	var roll: float = _roll(float(opts.get("roll", -1.0)), rng)
	var disrupted: bool = roll < sensitivity * 0.6
	var loss: int = 0
	if disrupted:
		loss = int(round(float(opts.get("daily_revenue", 100000.0)) * float(opts.get("days", 30.0)) * sensitivity))
		route["suspended"] = true
		if route.has("on_time_rate"):
			route["on_time_rate"] = clampf(float(route["on_time_rate"]) - 0.3, 0.0, 1.0)
	return {"ok": true, "disrupted": disrupted, "loss": loss, "sensitivity": sensitivity}


# --- 序列化 ---

func to_dict(state: Dictionary) -> Dictionary:
	return state.duplicate(true)


func from_dict(data: Dictionary) -> Dictionary:
	return data.duplicate(true)
