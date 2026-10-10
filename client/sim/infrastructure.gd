class_name InfrastructureSystem
extends RefCounted
## 基础设施（R62；design D18）。
##
## 覆盖：
##   - 7 类设施：电力/供水/燃气/通信网络/公共交通/排污垃圾/供暖（寒带），各含覆盖、容量、可靠性、价格；
##   - 账单与停用：按住所结算，逾期停用；复通需缴费 + 手续费 + 信用影响；
##   - 中断与抢修：主因灾害/战争/老化/罢工，含抢修工期与优先级（医院/工厂优先）；
##   - 依赖行为：停水影响烹饪清洁、停电影响照明/生产/冷藏、断网影响网络消费、公交中断影响通勤、停暖影响健康；
##   - 基建投资与升级：影响区域经济与人口吸引力，基建老化产生慢性问题与维护压力。
##
## 设计取舍：
##   - 城市状态为纯数据 Dictionary（facilities/accounts/incidents），便于存读档与测试；
##   - 抢修用“工日”推进：按 设施优先级 × 严重度 排序，医院/工厂依赖的电力与供水优先；
##   - 设施“停机”由 active=false 与未完成 incident 共同表达，依赖效果据此推导。

const BaselineScript = preload("res://sim/baseline.gd")

const FACILITY_POWER: String = "power"
const FACILITY_WATER: String = "water"
const FACILITY_GAS: String = "gas"
const FACILITY_TELECOM: String = "telecom"
const FACILITY_TRANSIT: String = "transit"
const FACILITY_SANITATION: String = "sanitation"
const FACILITY_HEATING: String = "heating"

const FACILITY_TYPES: Array = ["power", "water", "gas", "telecom", "transit", "sanitation", "heating"]

const FACILITY_NAMES: Dictionary = {
	"power": "电力", "water": "供水", "gas": "燃气", "telecom": "通信网络",
	"transit": "公共交通", "sanitation": "排污垃圾", "heating": "供暖",
}

## 抢修优先级权重（越大越先抢修；电力/供水关系医院与工厂运转）。
const FACILITY_PRIORITY: Dictionary = {
	"power": 5, "water": 5, "heating": 3, "gas": 2, "telecom": 2, "transit": 2, "sanitation": 1,
}

## 中断原因。
const CAUSE_DISASTER: String = "disaster"
const CAUSE_WAR: String = "war"
const CAUSE_AGING: String = "aging"
const CAUSE_STRIKE: String = "strike"
const CAUSES: Array = [CAUSE_DISASTER, CAUSE_WAR, CAUSE_AGING, CAUSE_STRIKE]

const BILL_GRACE_DAYS: float = BaselineScript.INFRA_BILL_GRACE_DAYS
const RECONNECT_FEE: int = BaselineScript.INFRA_RECONNECT_FEE
const CREDIT_PENALTY: float = BaselineScript.INFRA_CREDIT_PENALTY


func new_city(population: int, opts: Dictionary = {}) -> Dictionary:
	var cold_zone: bool = bool(opts.get("cold_zone", false))
	var facilities: Dictionary = {}
	var accounts: Dictionary = {}
	for t in FACILITY_TYPES:
		if t == FACILITY_HEATING and not cold_zone:
			continue
		facilities[t] = {
			"coverage": 0.95, "capacity": 1.0, "reliability": 0.98,
			"price": _base_price(t), "active": true, "maintenance": 0.0,
		}
		accounts[t] = {"balance": 0, "due": 0, "overdue_days": 0.0, "active": true, "reason": ""}
	return {
		"population": population, "cold_zone": cold_zone,
		"facilities": facilities, "accounts": accounts, "incidents": [],
		"population_attraction": 1.0, "maintenance_pressure": 0.0, "credit": 700.0,
	}


func _base_price(facility: String) -> int:
	match facility:
		FACILITY_POWER:
			return 6000
		FACILITY_WATER:
			return 3000
		FACILITY_GAS:
			return 2500
		FACILITY_TELECOM:
			return 8000
		FACILITY_TRANSIT:
			return 2000
		FACILITY_SANITATION:
			return 1500
		FACILITY_HEATING:
			return 5000
	return 1000


# --- 账单与停用 ---

func bill(city: Dictionary, facility: String, amount: int) -> Dictionary:
	var accounts: Dictionary = city["accounts"]
	if not accounts.has(facility):
		return {"ok": false, "reason": "unknown_facility"}
	var acct: Dictionary = accounts[facility]
	acct["due"] = int(acct["due"]) + maxi(0, amount)
	return {"ok": true, "due": int(acct["due"])}


## 推进账单逾期；超宽限期未缴则停用对应服务。
func tick_bills(city: Dictionary, days: float) -> Dictionary:
	var suspended: Array = []
	var accounts: Dictionary = city["accounts"]
	for t in accounts.keys():
		var acct: Dictionary = accounts[t]
		if int(acct["due"]) <= 0:
			acct["overdue_days"] = 0.0
			continue
		acct["overdue_days"] = float(acct["overdue_days"]) + maxf(0.0, days)
		if float(acct["overdue_days"]) > BILL_GRACE_DAYS and bool(acct["active"]):
			acct["active"] = false
			acct["reason"] = "unpaid"
			_set_facility_active(city, t, false)
			suspended.append(t)
	return {"ok": true, "suspended": suspended}


## 缴费复通：清欠并支付复通手续费，信用下降；欠费未清不可复通。
func pay(city: Dictionary, facility: String, amount: int) -> Dictionary:
	var accounts: Dictionary = city["accounts"]
	if not accounts.has(facility):
		return {"ok": false, "reason": "unknown_facility"}
	var acct: Dictionary = accounts[facility]
	acct["due"] = maxi(0, int(acct["due"]) - maxi(0, amount))
	var restored: bool = false
	var fee: int = 0
	if int(acct["due"]) <= 0 and not bool(acct["active"]):
		restored = true
		fee = RECONNECT_FEE
		acct["active"] = true
		acct["reason"] = ""
		acct["overdue_days"] = 0.0
		city["credit"] = maxf(0.0, float(city["credit"]) - CREDIT_PENALTY)
		_set_facility_active(city, facility, true)
	return {"ok": true, "due": int(acct["due"]), "restored": restored, "fee": fee, "credit": float(city["credit"])}


func suspend(city: Dictionary, facility: String, reason: String = "manual") -> Dictionary:
	var accounts: Dictionary = city["accounts"]
	if not accounts.has(facility):
		return {"ok": false, "reason": "unknown_facility"}
	accounts[facility]["active"] = false
	accounts[facility]["reason"] = reason
	_set_facility_active(city, facility, false)
	return {"ok": true, "facility": facility, "reason": reason}


func _set_facility_active(city: Dictionary, facility: String, active: bool) -> void:
	var facilities: Dictionary = city["facilities"]
	if facilities.has(facility):
		facilities[facility]["active"] = active


# --- 中断与抢修 ---

## 报告中断：按原因与严重度生成抢修事件，工期由严重度与设施可靠性决定。
func report_incident(city: Dictionary, facility: String, cause: String, severity: float, opts: Dictionary = {}) -> Dictionary:
	if not (city["facilities"] as Dictionary).has(facility):
		return {"ok": false, "reason": "unknown_facility"}
	if not CAUSES.has(cause):
		return {"ok": false, "reason": "unknown_cause"}
	var sev: float = clampf(severity, 0.1, 1.0)
	var reli: float = clampf(float((city["facilities"] as Dictionary)[facility]["reliability"]), 0.1, 1.0)
	var work_required: float = float(opts.get("base_work", 10.0)) * sev / reli
	var incident: Dictionary = {
		"facility": facility, "cause": cause, "severity": sev,
		"work_required": work_required, "work_done": 0.0, "completed": false,
		"started_minutes": int(opts.get("started_minutes", 0)),
	}
	(city["incidents"] as Array).append(incident)
	_set_facility_active(city, facility, false)
	return {"ok": true, "incident": incident}


## 抢修：按 设施优先级 × 严重度 排序消耗工日；医院/工厂依赖的电力、供水优先。
func repair(city: Dictionary, worker_days: float, opts: Dictionary = {}) -> Dictionary:
	var budget: float = maxf(0.0, worker_days)
	var incidents: Array = city["incidents"]
	var pending: Array = []
	for inc in incidents:
		if not bool((inc as Dictionary)["completed"]):
			pending.append(inc)
	pending.sort_custom(func(a, b): return _incident_score(a) > _incident_score(b))
	var completed: Array = []
	for inc in pending:
		if budget <= 0.0:
			break
		var d: Dictionary = inc
		var need: float = float(d["work_required"]) - float(d["work_done"])
		var use: float = minf(budget, need)
		d["work_done"] = float(d["work_done"]) + use
		budget -= use
		if float(d["work_done"]) >= float(d["work_required"]):
			d["completed"] = true
			completed.append(str(d["facility"]))
	if not completed.is_empty():
		_reactivate_completed(city)
	return {"ok": true, "completed": completed, "remaining_worker_days": budget, "pending": _pending_count(city)}


func _incident_score(inc: Dictionary) -> float:
	var prio: float = float(FACILITY_PRIORITY.get(str(inc["facility"]), 1))
	return prio * float(inc["severity"])


func _pending_count(city: Dictionary) -> int:
	var n: int = 0
	for inc in (city["incidents"] as Array):
		if not bool((inc as Dictionary)["completed"]):
			n += 1
	return n


func _reactivate_completed(city: Dictionary) -> void:
	var facilities: Dictionary = city["facilities"]
	for t in facilities.keys():
		var blocked: bool = false
		for inc in (city["incidents"] as Array):
			var d: Dictionary = inc
			if str(d["facility"]) == t and not bool(d["completed"]):
				blocked = true
				break
		# 未欠费停用时才恢复；欠费停用由 pay() 复通。
		var acct: Dictionary = (city["accounts"] as Dictionary)[t]
		if not blocked and bool(acct["active"]):
			facilities[t]["active"] = true


# --- 依赖行为 ---

## 汇总当前停机设施对日常行为的影响。
func dependency_effects(city: Dictionary) -> Dictionary:
	var off: Dictionary = {}
	var facilities: Dictionary = city["facilities"]
	for t in facilities.keys():
		if not bool(facilities[t]["active"]):
			off[t] = true
	var eff: Dictionary = {
		"cooking": true, "cleaning": true, "lighting": true, "network": true,
		"commute": true, "cold_storage": true, "production": 1.0, "hygiene": 1.0, "heating_health": 1.0,
	}
	if off.has(FACILITY_POWER):
		eff["lighting"] = false
		eff["cold_storage"] = false
		eff["production"] = 0.3
	if off.has(FACILITY_WATER):
		eff["cooking"] = false
		eff["cleaning"] = false
		eff["hygiene"] = 0.4
	if off.has(FACILITY_GAS):
		eff["cooking"] = false
	if off.has(FACILITY_TELECOM):
		eff["network"] = false
	if off.has(FACILITY_TRANSIT):
		eff["commute"] = false
	if off.has(FACILITY_SANITATION):
		eff["hygiene"] = minf(float(eff["hygiene"]), 0.5)
	if off.has(FACILITY_HEATING):
		eff["heating_health"] = 0.4
	eff["off"] = off.keys()
	return eff


# --- 投资与老化 ---

## 投资升级：提升覆盖/容量/可靠性，并增强区域人口吸引力。
func invest(city: Dictionary, facility: String, amount: int) -> Dictionary:
	var facilities: Dictionary = city["facilities"]
	if not facilities.has(facility):
		return {"ok": false, "reason": "unknown_facility"}
	var f: Dictionary = facilities[facility]
	var gain: float = clampf(float(maxi(0, amount)) / 1000000.0, 0.0, 0.5)
	f["coverage"] = clampf(float(f["coverage"]) + gain, 0.0, 1.0)
	f["capacity"] = clampf(float(f["capacity"]) + gain * 0.5, 0.1, 5.0)
	f["reliability"] = clampf(float(f["reliability"]) + gain * 0.1, 0.0, 1.0)
	city["population_attraction"] = clampf(float(city["population_attraction"]) + gain * 0.3, 0.1, 3.0)
	city["maintenance_pressure"] = maxf(0.0, float(city["maintenance_pressure"]) - gain * 0.1)
	return {"ok": true, "coverage": float(f["coverage"]), "reliability": float(f["reliability"]), "population_attraction": float(city["population_attraction"])}


## 老化：可靠性随年代下降，维护压力累积。
func age_maintenance(city: Dictionary, years: float) -> Dictionary:
	var y: float = maxf(0.0, years)
	var decay: float = y * 0.002
	var facilities: Dictionary = city["facilities"]
	for t in facilities.keys():
		var f: Dictionary = facilities[t]
		f["reliability"] = clampf(float(f["reliability"]) - decay, 0.1, 1.0)
		f["maintenance"] = float(f["maintenance"]) + decay
	city["maintenance_pressure"] = clampf(float(city["maintenance_pressure"]) + decay * float(facilities.size()), 0.0, 1.0)
	return {"ok": true, "maintenance_pressure": float(city["maintenance_pressure"])}


func to_dict(city: Dictionary) -> Dictionary:
	return city.duplicate(true)


func from_dict(data: Dictionary) -> Dictionary:
	return data.duplicate(true)
