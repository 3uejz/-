class_name MiningEnergySystem
extends RefCounted
## 矿业、能源与资源（R72；design D28）。
##
## 覆盖：
##   - 矿业链：勘探 → 开采 → 运输 → 冶炼 → 销售；矿权需特许资质与巨额资本，含品位与储量；
##   - 安全与职业病：按安全等级掷骰矿难/瓦斯爆炸/塌方/尘肺病，安全投入可降低事故率；
##   - 能源价格：油气煤电与新能源呈周期性波动，提供期货与长约定价；
##   - 新能源：电网调度、风光核运营、储能、碳交易与补贴政策；
##   - 资源与地缘：资源枯竭、资源城市衰退、战略资源管制与囤积；
##   - 边界：价格崩盘导致裁员与停产、环保事故追责。
##
## 设计取舍：
##   - 矿山与能源状态为纯数据 Dictionary，便于存读档与 headless 测试；
##   - 能源价格周期用确定性正弦函数 + 显式时钟推进，同输入可复现；
##   - 事故只由 安全水平 与 外部注入的 roll 决定，缺省确定化（roll=0）；
##   - 储量/品位为标量，冶炼按品位折算金属量，链条数值线性可核算。

const BaselineScript = preload("res://sim/baseline.gd")

const MINERALS: Dictionary = {
	"iron": {"name": "铁矿", "base_grade": 0.35, "base_reserve": 1000000.0, "smelt_yield": 0.90, "price": 800},
	"copper": {"name": "铜矿", "base_grade": 0.25, "base_reserve": 500000.0, "smelt_yield": 0.85, "price": 5000},
	"coal": {"name": "煤矿", "base_grade": 0.60, "base_reserve": 2000000.0, "smelt_yield": 0.95, "price": 400},
	"gold": {"name": "金矿", "base_grade": 0.02, "base_reserve": 50000.0, "smelt_yield": 0.80, "price": 40000},
}

const ACCIDENT_TYPES: Array = ["collapse", "gas_explosion", "landslide", "pneumoconiosis"]
const ACCIDENT_NAMES: Dictionary = {
	"collapse": "塌方", "gas_explosion": "瓦斯爆炸", "landslide": "冒顶", "pneumoconiosis": "尘肺病",
}

## 能源品种：基础价（最小货币单位/单位量）、波动率、周期（年）。
const ENERGY_TYPES: Dictionary = {
	"oil": {"name": "石油", "base_price": 500000, "volatility": 0.35, "cycle_years": 7.0, "kind": "fossil"},
	"gas": {"name": "天然气", "base_price": 300000, "volatility": 0.40, "cycle_years": 6.0, "kind": "fossil"},
	"coal": {"name": "煤炭", "base_price": 100000, "volatility": 0.25, "cycle_years": 8.0, "kind": "fossil"},
	"power": {"name": "电力", "base_price": 80000, "volatility": 0.15, "cycle_years": 5.0, "kind": "grid"},
	"new_energy": {"name": "新能源", "base_price": 120000, "volatility": 0.30, "cycle_years": 4.0, "kind": "renewable"},
}

const NEW_ENERGY_KINDS: Array = ["wind", "solar", "nuclear", "storage"]
const NEW_ENERGY_NAMES: Dictionary = {"wind": "风电", "solar": "光伏", "nuclear": "核电", "storage": "储能"}

const CONCESSION_QUALIFICATION: String = "mining_license"
const CONCESSION_MIN_CAPITAL: int = BaselineScript.MINING_CONCESSION_MIN_CAPITAL


# --- 数据表 ---

func mineral_keys() -> Array:
	return MINERALS.keys()


func mineral_def(key: String) -> Dictionary:
	if not MINERALS.has(key):
		return {}
	return (MINERALS[key] as Dictionary).duplicate(true)


func energy_keys() -> Array:
	return ENERGY_TYPES.keys()


func energy_def(key: String) -> Dictionary:
	if not ENERGY_TYPES.has(key):
		return {}
	return (ENERGY_TYPES[key] as Dictionary).duplicate(true)


# --- 矿权与勘探 ---

func new_mine(mineral: String, money: int = 0, opts: Dictionary = {}) -> Dictionary:
	if not MINERALS.has(mineral):
		return {}
	var def: Dictionary = MINERALS[mineral]
	return {
		"mineral": mineral,
		"money": money,
		"concession": false,
		"qualifications": (opts.get("qualifications", []) as Array).duplicate(),
		"reserve": float(opts.get("reserve", 0.0)),
		"grade": float(opts.get("grade", float(def["base_grade"]))),
		"explored": false,
		"operating": false,
		"stockpile_ore": 0.0,
		"refined_metal": 0.0,
		"workers": maxi(0, int(opts.get("workers", 0))),
		"safety": clampf(float(opts.get("safety", 0.5)), 0.0, 1.0),
		"accident_count": 0,
		"environment_liability": 0.0,
		"revenue": 0,
	}


## 取得矿权特许：需资质与最低资本。
func acquire_concession(mine: Dictionary, cost: int = CONCESSION_MIN_CAPITAL, opts: Dictionary = {}) -> Dictionary:
	var quals: Array = mine.get("qualifications", [])
	if not quals.has(CONCESSION_QUALIFICATION):
		return {"ok": false, "reason": "no_qualification"}
	var amount: int = maxi(0, cost)
	if int(mine.get("money", 0)) < amount:
		return {"ok": false, "reason": "insufficient_capital", "required": amount}
	mine["money"] = int(mine["money"]) - amount
	mine["concession"] = true
	return {"ok": true, "concession": true, "cost": amount}


## 勘探：投入资本揭示储量与品位；未勘探不可开采。
func explore(mine: Dictionary, budget: int, opts: Dictionary = {}) -> Dictionary:
	var mineral: String = str(mine.get("mineral", ""))
	if not MINERALS.has(mineral):
		return {"ok": false, "reason": "unknown_mineral"}
	var def: Dictionary = MINERALS[mineral]
	var spend: int = maxi(0, budget)
	if int(mine.get("money", 0)) < spend:
		return {"ok": false, "reason": "insufficient_funds"}
	mine["money"] = int(mine["money"]) - spend
	var quality: float = clampf(float(spend) / 10000000.0, 0.0, 1.0)
	mine["reserve"] = float(def["base_reserve"]) * (0.5 + quality)
	var grade_bonus: float = float(opts.get("grade_bonus", quality * 0.5))
	mine["grade"] = clampf(float(def["base_grade"]) * (1.0 + grade_bonus), 0.0, 0.9)
	mine["explored"] = true
	return {"ok": true, "reserve": float(mine["reserve"]), "grade": float(mine["grade"]), "cost": spend}


# --- 开采与链条 ---

## 开采：按安全与人力产出矿石，消耗储量。返回本步产量。
func extract(mine: Dictionary, amount: float, opts: Dictionary = {}) -> Dictionary:
	if not bool(mine.get("concession", false)):
		return {"ok": false, "reason": "no_concession"}
	if not bool(mine.get("explored", false)):
		return {"ok": false, "reason": "not_explored"}
	var reserve: float = float(mine.get("reserve", 0.0))
	if reserve <= 0.0:
		return {"ok": false, "reason": "depleted"}
	var requested: float = maxf(0.0, amount)
	var factor: float = clampf(float(opts.get("extract_factor", 1.0)) * (0.5 + float(mine.get("safety", 0.5)) * 0.5), 0.0, 1.5)
	var produced: float = minf(reserve, requested * factor)
	mine["reserve"] = reserve - produced
	mine["stockpile_ore"] = float(mine.get("stockpile_ore", 0.0)) + produced
	if float(mine["reserve"]) <= 0.0:
		mine["operating"] = false
	return {
		"ok": true, "ore": produced, "reserve": float(mine["reserve"]),
		"depleted": float(mine["reserve"]) <= 0.0, "stockpile_ore": float(mine["stockpile_ore"]),
	}


func transport_ore(mine: Dictionary, amount: float) -> Dictionary:
	var qty: float = minf(maxf(0.0, amount), float(mine.get("stockpile_ore", 0.0)))
	mine["stockpile_ore"] = float(mine["stockpile_ore"]) - qty
	mine["in_transit_ore"] = float(mine.get("in_transit_ore", 0.0)) + qty
	return {"ok": true, "transported": qty, "in_transit_ore": float(mine["in_transit_ore"])}


## 冶炼：把矿石按品位与冶炼收得率折算为金属量。
func smelt(mine: Dictionary, amount: float, opts: Dictionary = {}) -> Dictionary:
	var available: float = float(mine.get("in_transit_ore", 0.0))
	var qty: float = minf(maxf(0.0, amount), available)
	var mineral: String = str(mine.get("mineral", ""))
	var def: Dictionary = MINERALS.get(mineral, {})
	var grade: float = clampf(float(mine.get("grade", 0.0)), 0.0, 1.0)
	var smelt_yield: float = float(def.get("smelt_yield", 0.9))
	var metal: float = qty * grade * smelt_yield
	mine["in_transit_ore"] = available - qty
	mine["refined_metal"] = float(mine.get("refined_metal", 0.0)) + metal
	return {"ok": true, "smelted_ore": qty, "metal": metal, "grade": grade, "refined_metal": float(mine["refined_metal"])}


## 销售：按市价卖出精炼金属。
func sell(mine: Dictionary, amount: float, price: int = -1) -> Dictionary:
	var available: float = float(mine.get("refined_metal", 0.0))
	var qty: float = minf(maxf(0.0, amount), available)
	if qty <= 0.0:
		return {"ok": false, "reason": "no_stock"}
	var unit_price: int = int(price)
	if unit_price < 0:
		var def: Dictionary = MINERALS.get(str(mine.get("mineral", "")), {})
		unit_price = int(def.get("price", 0))
	var revenue: int = int(round(qty * float(unit_price)))
	mine["refined_metal"] = available - qty
	mine["money"] = int(mine.get("money", 0)) + revenue
	mine["revenue"] = int(mine.get("revenue", 0)) + revenue
	return {"ok": true, "sold": qty, "unit_price": unit_price, "revenue": revenue}


# --- 安全与职业病 ---

func safety_invest(mine: Dictionary, amount: int) -> Dictionary:
	var gain: float = clampf(float(maxi(0, amount)) / 20000000.0, 0.0, 0.45)
	mine["safety"] = clampf(float(mine.get("safety", 0.5)) + gain, 0.0, 0.99)
	return {"ok": true, "safety": float(mine["safety"])}


## 事故率：基础率随安全投入下降。
func accident_rate(mine: Dictionary, opts: Dictionary = {}) -> float:
	var base: float = float(opts.get("base_rate", 0.12))
	return clampf(base * (1.0 - float(mine.get("safety", 0.5))), 0.0, 1.0)


## 掷骰事故（矿难/瓦斯/塌方/尘肺）。安全投入降低事故率；高事故额外记环保负债。
func accident_check(mine: Dictionary, opts: Dictionary = {}, rng = null) -> Dictionary:
	var rate: float = accident_rate(mine, opts)
	var roll: float = _roll(float(opts.get("roll", -1.0)), rng)
	var occurred: bool = roll < rate
	var kind: String = ""
	var injured: int = 0
	if occurred:
		var idx: int = int(floor(roll / maxf(1e-9, rate) * float(ACCIDENT_TYPES.size())))
		kind = str(ACCIDENT_TYPES[clampi(idx, 0, ACCIDENT_TYPES.size() - 1)])
		injured = maxi(1, int(round(float(mine.get("workers", 0)) * rate)))
		mine["accident_count"] = int(mine.get("accident_count", 0)) + 1
		mine["environment_liability"] = clampf(float(mine.get("environment_liability", 0.0)) + rate * 0.5, 0.0, 1.0)
	return {
		"ok": true, "occurred": occurred, "kind": kind, "kind_name": str(ACCIDENT_NAMES.get(kind, "")),
		"injured": injured, "rate": rate, "safety": float(mine.get("safety", 0.5)),
	}


## 环保事故追责：罚款并提升负债。
func environmental_liability(mine: Dictionary, amount: int) -> Dictionary:
	var fine: int = maxi(0, amount)
	mine["money"] = int(mine.get("money", 0)) - fine
	mine["environment_liability"] = clampf(float(mine.get("environment_liability", 0.0)) + 0.2, 0.0, 1.0)
	return {"ok": true, "fine": fine, "environment_liability": float(mine["environment_liability"])}


# --- 能源价格周期 ---

func new_energy_state(opts: Dictionary = {}) -> Dictionary:
	var prices: Dictionary = {}
	var futures: Dictionary = {}
	for k in ENERGY_TYPES.keys():
		prices[k] = int((ENERGY_TYPES[k] as Dictionary)["base_price"])
		futures[k] = []
	return {
		"clock": maxf(0.0, float(opts.get("clock", 0.0))),
		"prices": prices,
		"futures": futures,
		"strategic_control": {},
		"stockpile": {},
		"credits": 0.0,
	}


## 推进能源价格：确定性正弦周期 + 缓慢趋势，可复现。
func tick_energy(state: Dictionary, years: float) -> Dictionary:
	state["clock"] = float(state.get("clock", 0.0)) + maxf(0.0, years)
	var t: float = float(state["clock"])
	var prices: Dictionary = state.get("prices", {})
	for k in ENERGY_TYPES.keys():
		var def: Dictionary = ENERGY_TYPES[k]
		var base: float = float(def["base_price"])
		var vol: float = float(def["volatility"])
		var cycle: float = maxf(1.0, float(def["cycle_years"]))
		var factor: float = 1.0 + vol * sin(TAU * t / cycle)
		prices[k] = maxi(0, int(round(base * factor)))
	state["prices"] = prices
	return {"ok": true, "clock": t, "prices": prices.duplicate()}


func energy_price(state: Dictionary, energy_type: String) -> int:
	return int((state.get("prices", {}) as Dictionary).get(energy_type, 0))


## 期货建仓：锁定未来价格，到期按市价与锁价差额结算。
func futures_contract(state: Dictionary, energy_type: String, amount: float, lock_price: int) -> Dictionary:
	if not ENERGY_TYPES.has(energy_type):
		return {"ok": false, "reason": "unknown_energy"}
	var futures: Dictionary = state["futures"]
	var contract: Dictionary = {"energy": energy_type, "amount": maxf(0.0, amount), "lock_price": int(lock_price), "settled": false}
	(futures[energy_type] as Array).append(contract)
	return {"ok": true, "contract": contract}


func settle_futures(state: Dictionary, energy_type: String, index: int, market_price: int) -> Dictionary:
	var futures: Dictionary = state.get("futures", {})
	if not futures.has(energy_type):
		return {"ok": false, "reason": "no_contracts"}
	var contracts: Array = futures[energy_type]
	if index < 0 or index >= contracts.size():
		return {"ok": false, "reason": "no_contract"}
	var contract: Dictionary = contracts[index]
	if bool(contract.get("settled", false)):
		return {"ok": false, "reason": "settled"}
	var pnl: int = int(round(float(contract["amount"]) * float(int(market_price) - int(contract["lock_price"]))))
	contract["settled"] = true
	return {"ok": true, "pnl": pnl}


## 长约：锁定固定价，期间不受市价影响。
func long_term_contract(state: Dictionary, energy_type: String, amount: float, fixed_price: int, years: float) -> Dictionary:
	if not ENERGY_TYPES.has(energy_type):
		return {"ok": false, "reason": "unknown_energy"}
	var contract: Dictionary = {
		"energy": energy_type, "amount": maxf(0.0, amount), "fixed_price": int(fixed_price),
		"years": maxf(0.0, years), "delivered": 0.0,
	}
	if not state.has("long_term_contracts"):
		state["long_term_contracts"] = []
	(state["long_term_contracts"] as Array).append(contract)
	return {"ok": true, "contract": contract}


# --- 新能源 ---

func new_energy_project(kind: String, capacity: float, opts: Dictionary = {}) -> Dictionary:
	if not NEW_ENERGY_KINDS.has(kind):
		return {}
	return {
		"kind": kind,
		"name": str(NEW_ENERGY_NAMES.get(kind, kind)),
		"capacity": maxf(0.0, capacity),
		"output": 0.0,
		"stored": 0.0,
		"subsidy": 0.0,
		"carbon_credits": 0.0,
		"curtailed": 0.0,
	}


## 电网调度：按需求调度出力，储能吸收弃风弃光，不足时留缺口。
func grid_dispatch(project: Dictionary, demand: float, opts: Dictionary = {}) -> Dictionary:
	var d: float = maxf(0.0, demand)
	var availability: float = float(project.get("capacity", 0.0)) * clampf(float(opts.get("availability", 0.85)), 0.0, 1.0)
	var supply: float = minf(availability, d)
	var surplus: float = maxf(0.0, availability - d)
	var stored: float = 0.0
	if str(project.get("kind", "")) == "storage":
		stored = minf(surplus, float(opts.get("storage_capacity", 0.0)))
	project["output"] = supply
	project["curtailed"] = maxf(0.0, surplus - stored)
	project["stored"] = minf(float(project.get("capacity", 0.0)), stored)
	return {
		"ok": true, "demand": d, "supply": supply, "gap": maxf(0.0, d - supply),
		"stored": float(project["stored"]), "curtailed": float(project["curtailed"]),
	}


## 碳交易：按核证减排量出售碳配额。
func carbon_trade(project: Dictionary, credits: float, price: int) -> Dictionary:
	var amount: float = maxf(0.0, credits)
	var revenue: int = int(round(amount * float(maxi(0, price))))
	project["carbon_credits"] = float(project.get("carbon_credits", 0.0)) + amount
	return {"ok": true, "credits": amount, "price": int(price), "revenue": revenue}


func apply_subsidy(project: Dictionary, amount: int) -> Dictionary:
	var granted: int = maxi(0, amount)
	project["subsidy"] = float(project.get("subsidy", 0.0)) + float(granted)
	return {"ok": true, "subsidy": float(project["subsidy"]), "granted": granted}


# --- 资源与地缘 ---

func reserve_ratio(mine: Dictionary) -> float:
	var mineral: String = str(mine.get("mineral", ""))
	var base: float = float((MINERALS.get(mineral, {}) as Dictionary).get("base_reserve", 1.0))
	return clampf(float(mine.get("reserve", 0.0)) / maxf(1.0, base), 0.0, 2.0)


## 资源城市衰退：储量比例越低，衰退越重。
func resource_city_decline(city: Dictionary, mine: Dictionary) -> Dictionary:
	var ratio: float = reserve_ratio(mine)
	var decline: float = clampf(1.0 - ratio, 0.0, 1.0)
	var population_loss: int = int(round(float(city.get("population", 0)) * decline * 0.3))
	city["population"] = maxi(0, int(city.get("population", 0)) - population_loss)
	city["decline"] = clampf(float(city.get("decline", 0.0)) + decline * 0.2, 0.0, 1.0)
	return {"ok": true, "decline": decline, "population_loss": population_loss, "reserve_ratio": ratio}


## 战略资源管制与囤积：管制等级越高，可交易比例越低，囤积越多。
func set_strategic_control(state: Dictionary, resource: String, level: float) -> Dictionary:
	state["strategic_control"][resource] = clampf(level, 0.0, 1.0)
	return {"ok": true, "resource": resource, "level": float(state["strategic_control"][resource])}


func stockpile(state: Dictionary, resource: String, amount: float) -> Dictionary:
	var stock: Dictionary = state["stockpile"]
	stock[resource] = maxf(0.0, float(stock.get(resource, 0.0)) + amount)
	return {"ok": true, "resource": resource, "stockpile": float(stock[resource])}


func tradable_ratio(state: Dictionary, resource: String) -> float:
	var level: float = float((state.get("strategic_control", {}) as Dictionary).get(resource, 0.0))
	return clampf(1.0 - level, 0.0, 1.0)


# --- 边界 ---

## 价格崩盘：停产并裁员，返回裁员人数与损失。
func price_crash(mine: Dictionary, crash_ratio: float) -> Dictionary:
	var ratio: float = clampf(crash_ratio, 0.0, 1.0)
	mine["operating"] = false
	var layoff: int = int(round(float(mine.get("workers", 0)) * ratio))
	mine["workers"] = maxi(0, int(mine.get("workers", 0)) - layoff)
	var unit_price: int = int((MINERALS.get(str(mine.get("mineral", "")), {}) as Dictionary).get("price", 0))
	var loss: int = int(round(float(mine.get("refined_metal", 0.0)) * float(unit_price) * ratio))
	return {"ok": true, "operating": false, "layoff": layoff, "loss": loss, "crash_ratio": ratio}


func _roll(forced: float, rng) -> float:
	if forced >= 0.0:
		return clampf(forced, 0.0, 1.0)
	if rng != null:
		return rng.next_float()
	return 0.0


func to_dict(state: Dictionary) -> Dictionary:
	return state.duplicate(true)


func from_dict(data: Dictionary) -> Dictionary:
	return data.duplicate(true)
