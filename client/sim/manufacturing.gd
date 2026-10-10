class_name ManufacturingSystem
extends RefCounted
## 制造业、工业与供应链（R70；design D26）。
##
## 覆盖：
##   - 岗位与技能对接：普工/技工/工程师/厂长/采购/品控/研发，分别贡献产能、良品率与供应能力；
##   - 生产链：接单 → 采购原料 → 排产 → 生产 → 质检 → 交付；
##     产能 = 设备 × 人力 × 效率，并受原料可得量约束；含良品率与工时；
##   - 质量守恒：一次生产消耗的原料总量 = 成品良品 + 次品 + 边角损耗（同口径单位，数量守恒）；
##   - 供应链：上游供应商、库存、物流；断料/涨价/单一供应商风险；
##   - 经营模式：开厂/代工 OEM/自建品牌 OBM/技术授权，含资质与资本门槛及代工→自建品牌升级路径；
##   - 中断风险：断电/断料/设备故障/罢工/缺勤，安全工伤，技术升级与自动化，环保限产；
##   - 边界：次品退货、产能扩张的资金链断裂。
##
## 设计取舍：
##   - 工厂为纯数据 Dictionary，便于存读档与 headless 测试；
##   - 配方 inputs 之和按 1.0 归一，故 1 单位成品恰好消耗 1.0 单位原料，质量守恒可精确核验；
##   - 良品率只由技能结构、品控/研发/工程师配置与自动化决定，clamp 到 [0.5, 0.995]，不引入随机漂移；
##   - 随机项（工伤、缺勤）只保留在 injury_check/absenteeism 中，并由外部 rng 注入，缺省确定化。

const BaselineScript = preload("res://sim/baseline.gd")

const ROLES: Dictionary = {
	"unskilled": {"name": "普工", "skill": "labor", "wage": 400000, "output": 1.0, "quality": 0.0, "supply": 0.0},
	"skilled": {"name": "技工", "skill": "craft", "wage": 700000, "output": 1.6, "quality": 0.01, "supply": 0.0},
	"engineer": {"name": "工程师", "skill": "engineering", "wage": 1200000, "output": 0.8, "quality": 0.008, "supply": 0.0},
	"director": {"name": "厂长", "skill": "management", "wage": 2000000, "output": 0.4, "quality": 0.004, "supply": 0.0},
	"procurement": {"name": "采购", "skill": "trade", "wage": 800000, "output": 0.0, "quality": 0.0, "supply": 0.06},
	"qc": {"name": "品控", "skill": "quality", "wage": 800000, "output": 0.0, "quality": 0.010, "supply": 0.0},
	"rd": {"name": "研发", "skill": "research", "wage": 1500000, "output": 0.0, "quality": 0.010, "supply": 0.0},
}

## 经营模式：资本门槛、所需资质、品牌加成（OBM 最高）。MODE_UPGRADE 给出升级路径。
const MODES: Dictionary = {
	"own_factory": {"name": "开厂", "min_capital": 5000000, "qualification": "factory_license", "brand_margin": 0.0},
	"oem": {"name": "代工", "min_capital": 2000000, "qualification": "business_license", "brand_margin": 0.05},
	"obm": {"name": "自建品牌", "min_capital": 10000000, "qualification": "brand_registration", "brand_margin": 0.30},
	"license": {"name": "技术授权", "min_capital": 3000000, "qualification": "patent", "brand_margin": 0.12},
}

const MODE_UPGRADE: Dictionary = {
	"own_factory": ["oem", "license"],
	"oem": ["obm"],
	"license": ["obm"],
	"obm": [],
}

## 配方：inputs 之和归一为 1.0，故 1 成品消耗 1.0 原料；base_yield 为基础良品率。
const RECIPES: Dictionary = {
	"steel_part": {"name": "钢制零件", "inputs": {"steel": 1.0}, "base_yield": 0.92, "work_hours": 1.0, "price": 5000},
	"plastic_part": {"name": "塑料件", "inputs": {"resin": 1.0}, "base_yield": 0.95, "work_hours": 0.6, "price": 3000},
	"circuit_board": {"name": "电路板", "inputs": {"copper": 0.4, "resin": 0.6}, "base_yield": 0.88, "work_hours": 1.5, "price": 12000},
}

const DISRUPTIONS: Array = ["power_outage", "material_shortage", "equipment_failure", "strike", "absenteeism"]

const REFERENCE_LABOR: float = BaselineScript.MFG_REFERENCE_LABOR
const DEFECT_SHARE: float = BaselineScript.MFG_DEFECT_SHARE


# --- 数据表 ---

func role_keys() -> Array:
	return ROLES.keys()


func role_def(role: String) -> Dictionary:
	if not ROLES.has(role):
		return {}
	return (ROLES[role] as Dictionary).duplicate(true)


func mode_keys() -> Array:
	return MODES.keys()


func mode_def(mode: String) -> Dictionary:
	if not MODES.has(mode):
		return {}
	return (MODES[mode] as Dictionary).duplicate(true)


func recipe_keys() -> Array:
	return RECIPES.keys()


func recipe_def(recipe_key: String) -> Dictionary:
	if not RECIPES.has(recipe_key):
		return {}
	return (RECIPES[recipe_key] as Dictionary).duplicate(true)


func input_materials(recipe_key: String) -> Array:
	if not RECIPES.has(recipe_key):
		return []
	return ((RECIPES[recipe_key] as Dictionary)["inputs"] as Dictionary).keys()


# --- 建厂与经营模式 ---

func new_factory(money: int = 5000000, opts: Dictionary = {}) -> Dictionary:
	var staff: Dictionary = {}
	for r in ROLES.keys():
		staff[r] = 0
	return {
		"money": money,
		"mode": str(opts.get("mode", "own_factory")),
		"qualifications": (opts.get("qualifications", []) as Array).duplicate(),
		"equipment": clampf(float(opts.get("equipment", 1.0)), 0.1, 3.0),
		"efficiency": clampf(float(opts.get("efficiency", 1.0)), 0.2, 2.0),
		"automation": clampf(float(opts.get("automation", 0.0)), 0.0, 1.0),
		"base_capacity": maxf(1.0, float(opts.get("base_capacity", 100.0))),
		"staff": staff,
		"materials": {},
		"products": {},
		"orders": [],
		"suppliers": [],
		"power_on": true,
		"environment_ratio": 1.0,
		"safety": clampf(float(opts.get("safety", 0.5)), 0.0, 1.0),
		"injury_count": 0,
		"disruptions": {},
	}


## 资质与资本校验：资金需覆盖门槛且持有资质，才可进入该模式。
func can_enter_mode(factory: Dictionary, mode: String) -> bool:
	if not MODES.has(mode):
		return false
	var def: Dictionary = MODES[mode]
	if int(factory.get("money", 0)) < int(def["min_capital"]):
		return false
	var quals: Array = factory.get("qualifications", [])
	return quals.has(str(def["qualification"]))


## 设置经营模式；校验失败返回原因。代工→自建品牌升级路径由 MODE_UPGRADE 给出。
func set_mode(factory: Dictionary, mode: String) -> Dictionary:
	if not MODES.has(mode):
		return {"ok": false, "reason": "unknown_mode"}
	if not can_enter_mode(factory, mode):
		return {"ok": false, "reason": "not_qualified"}
	factory["mode"] = mode
	return {"ok": true, "mode": mode, "brand_margin": float((MODES[mode] as Dictionary)["brand_margin"])}


## 升级到路径内的下一档模式（如 OEM → OBM）。
func upgrade_mode(factory: Dictionary, target: String) -> Dictionary:
	var current: String = str(factory.get("mode", ""))
	if not MODE_UPGRADE.has(current):
		return {"ok": false, "reason": "unknown_mode"}
	if not (MODE_UPGRADE[current] as Array).has(target):
		return {"ok": false, "reason": "no_upgrade_path"}
	return set_mode(factory, target)


func grant_qualification(factory: Dictionary, qualification: String) -> Dictionary:
	var quals: Array = factory.get("qualifications", [])
	if not quals.has(qualification):
		quals.append(qualification)
	factory["qualifications"] = quals
	return {"ok": true, "qualifications": quals.duplicate()}


# --- 岗位 ---

func staff_count(factory: Dictionary, role: String) -> int:
	return int((factory.get("staff", {}) as Dictionary).get(role, 0))


func headcount(factory: Dictionary) -> int:
	var total: int = 0
	for r in ROLES.keys():
		total += staff_count(factory, r)
	return total


func hire(factory: Dictionary, role: String, count: int) -> Dictionary:
	if not ROLES.has(role):
		return {"ok": false, "reason": "unknown_role"}
	var n: int = maxi(0, count)
	var staff: Dictionary = factory["staff"]
	staff[role] = int(staff.get(role, 0)) + n
	return {"ok": true, "role": role, "count": int(staff[role])}


func fire(factory: Dictionary, role: String, count: int) -> Dictionary:
	if not ROLES.has(role):
		return {"ok": false, "reason": "unknown_role"}
	var staff: Dictionary = factory["staff"]
	var before: int = int(staff.get(role, 0))
	var after: int = maxi(0, before - maxi(0, count))
	staff[role] = after
	return {"ok": true, "role": role, "count": after, "fired": before - after}


## 人力当量：各岗位 output 权重 × 人数，普工为主力。
func labor_output(factory: Dictionary) -> float:
	var total: float = 0.0
	for r in ROLES.keys():
		total += float(staff_count(factory, r)) * float((ROLES[r] as Dictionary)["output"])
	return total


func labor_factor(factory: Dictionary) -> float:
	return clampf(labor_output(factory) / REFERENCE_LABOR, 0.0, 3.0)


## 有效效率：基础效率 × 自动化加成 × 环保限产系数。
func effective_efficiency(factory: Dictionary) -> float:
	var auto: float = 1.0 + float(factory.get("automation", 0.0)) * 0.5
	var env: float = clampf(float(factory.get("environment_ratio", 1.0)), 0.0, 1.0)
	return clampf(float(factory.get("efficiency", 1.0)) * auto * env, 0.0, 5.0)


# --- 原料与供应商 ---

func material_qty(factory: Dictionary, material: String) -> float:
	var mats: Dictionary = factory.get("materials", {})
	if not mats.has(material):
		return 0.0
	return float((mats[material] as Dictionary).get("qty", 0.0))


func add_material(factory: Dictionary, material: String, qty: float, unit_cost: int = 0) -> Dictionary:
	var mats: Dictionary = factory["materials"]
	var entry: Dictionary = mats.get(material, {"qty": 0.0, "unit_cost": int(unit_cost)})
	var old_qty: float = float(entry.get("qty", 0.0))
	var old_cost: int = int(entry.get("unit_cost", unit_cost))
	var total: float = old_qty + maxf(0.0, qty)
	var weighted: int = int(unit_cost)
	if total > 0.0:
		weighted = int(round((old_qty * float(old_cost) + maxf(0.0, qty) * float(unit_cost)) / total))
	entry["qty"] = total
	entry["unit_cost"] = weighted
	mats[material] = entry
	return {"ok": true, "material": material, "qty": total, "unit_cost": weighted}


func add_supplier(factory: Dictionary, supplier: Dictionary) -> Dictionary:
	var suppliers: Array = factory["suppliers"]
	var id: String = str(supplier.get("id", "sup_%d" % suppliers.size()))
	var rec: Dictionary = {
		"id": id,
		"name": str(supplier.get("name", id)),
		"materials": (supplier.get("materials", []) as Array).duplicate(),
		"price_factor": clampf(float(supplier.get("price_factor", 1.0)), 0.1, 5.0),
		"reliability": clampf(float(supplier.get("reliability", 0.9)), 0.0, 1.0),
	}
	suppliers.append(rec)
	return {"ok": true, "supplier": rec}


## 采购：从覆盖该原料的供应商中下单；无供应商则断料。断料/涨价由此结算。
func purchase(factory: Dictionary, material: String, qty: float, opts: Dictionary = {}) -> Dictionary:
	var amount: float = maxf(0.0, qty)
	var candidates: Array = []
	for s in (factory["suppliers"] as Array):
		if (s as Dictionary)["materials"].has(material):
			candidates.append(s)
	if candidates.is_empty():
		return {"ok": false, "reason": "no_supplier", "material": material}
	if amount <= 0.0:
		return {"ok": false, "reason": "bad_quantity"}
	# 供货不足（断料）：按可靠性缩减可得量。
	var supplier: Dictionary = candidates[0]
	var reliable: float = clampf(float(supplier.get("reliability", 0.9)), 0.0, 1.0)
	var delivered: float = amount * reliable
	var unit_cost: int = int(round(float(opts.get("base_unit_cost", 1000)) * float(supplier.get("price_factor", 1.0))))
	var cost: int = int(round(delivered * float(unit_cost)))
	if int(factory.get("money", 0)) < cost:
		return {"ok": false, "reason": "insufficient_funds", "cost": cost}
	factory["money"] = int(factory["money"]) - cost
	add_material(factory, material, delivered, unit_cost)
	return {
		"ok": true, "material": material, "delivered": delivered, "unit_cost": unit_cost,
		"cost": cost, "shortfall": amount - delivered,
	}


## 单一供应商风险：返回仅有一家供应商的原料及其风险等级。
func supply_risk(factory: Dictionary) -> Dictionary:
	var counts: Dictionary = {}
	for s in (factory["suppliers"] as Array):
		for m in ((s as Dictionary)["materials"] as Array):
			counts[m] = int(counts.get(m, 0)) + 1
	var single: Array = []
	var risk: float = 0.0
	for m in counts.keys():
		if int(counts[m]) <= 1 and (RECIPES.values().any(func(r): return (r["inputs"] as Dictionary).has(m))):
			single.append(m)
			risk += 0.2
	return {"ok": true, "single_source": single, "risk": clampf(risk, 0.0, 1.0)}


# --- 产能与生产 ---

## 产能明细：设备、人力、效率三因子，报告最短板 bottleneck ∈ {equipment,labor,efficiency}。
func capacity(factory: Dictionary, recipe_key: String, opts: Dictionary = {}) -> Dictionary:
	if not RECIPES.has(recipe_key):
		return {"ok": false, "reason": "unknown_recipe"}
	var base: float = float(factory.get("base_capacity", 100.0))
	var equipment: float = clampf(float(factory.get("equipment", 1.0)), 0.0, 3.0)
	var labor: float = labor_factor(factory)
	var efficiency: float = effective_efficiency(factory)
	var equipment_cap: float = base * equipment
	var labor_cap: float = base * labor
	var efficiency_cap: float = base * efficiency
	var bottleneck: String = "labor"
	var min_cap: float = labor_cap
	if equipment_cap < min_cap:
		min_cap = equipment_cap
		bottleneck = "equipment"
	if efficiency_cap < min_cap:
		min_cap = efficiency_cap
		bottleneck = "efficiency"
	return {
		"ok": true, "equipment_factor": equipment, "labor_factor": labor, "efficiency": efficiency,
		"equipment_cap": equipment_cap, "labor_cap": labor_cap, "efficiency_cap": efficiency_cap,
		"effective_capacity": min_cap, "bottleneck": bottleneck,
	}


## 良品率：基础良品率 + 品控/工程师/研发加成 + 自动化加成 − 普工占比惩罚，clamp [0.5, 0.995]。
func quality_yield(factory: Dictionary, recipe_key: String) -> float:
	if not RECIPES.has(recipe_key):
		return 0.0
	var base: float = float((RECIPES[recipe_key] as Dictionary)["base_yield"])
	var qc_bonus: float = minf(0.08, float(staff_count(factory, "qc")) * float((ROLES["qc"] as Dictionary)["quality"]))
	var eng_bonus: float = minf(0.06, float(staff_count(factory, "engineer")) * float((ROLES["engineer"] as Dictionary)["quality"]))
	var rd_bonus: float = minf(0.05, float(staff_count(factory, "rd")) * float((ROLES["rd"] as Dictionary)["quality"]))
	var auto_bonus: float = float(factory.get("automation", 0.0)) * 0.03
	var total: int = maxi(1, headcount(factory))
	var unskilled_share: float = float(staff_count(factory, "unskilled")) / float(total)
	var value: float = base + qc_bonus + eng_bonus + rd_bonus + auto_bonus - unskilled_share * 0.10
	return clampf(value, 0.5, 0.995)


# --- 中断风险 ---

func set_disruption(factory: Dictionary, kind: String, active: bool) -> Dictionary:
	if not DISRUPTIONS.has(kind):
		return {"ok": false, "reason": "unknown_disruption"}
	var flags: Dictionary = factory["disruptions"]
	flags[kind] = active
	return {"ok": true, "kind": kind, "active": active}


func has_disruption(factory: Dictionary, kind: String) -> bool:
	return bool((factory.get("disruptions", {}) as Dictionary).get(kind, false))


func active_disruptions(factory: Dictionary) -> Array:
	var out: Array = []
	var flags: Dictionary = factory.get("disruptions", {})
	for k in flags.keys():
		if bool(flags[k]):
			out.append(k)
	return out


## 是否停线：断电、断料、设备故障、罢工任一发生即全停；缺勤仅降低人力。
func production_blocked(factory: Dictionary) -> bool:
	if not bool(factory.get("power_on", true)):
		return true
	for k in ["power_outage", "material_shortage", "equipment_failure", "strike"]:
		if has_disruption(factory, k):
			return true
	return false


func set_power(factory: Dictionary, on: bool) -> Dictionary:
	factory["power_on"] = on
	return {"ok": true, "power_on": on}


func injury_check(factory: Dictionary, opts: Dictionary = {}, rng = null) -> Dictionary:
	var risk: float = clampf(float(opts.get("base_risk", 0.05)) * (1.0 - float(factory.get("safety", 0.5))), 0.0, 1.0)
	var roll: float = _roll(float(opts.get("roll", -1.0)), rng)
	var injured: int = 0
	if roll < risk:
		injured = maxi(1, int(round(float(headcount(factory)) * risk)))
		factory["injury_count"] = int(factory.get("injury_count", 0)) + injured
	return {"ok": true, "injured": injured, "risk": risk, "safety": float(factory.get("safety", 0.5))}


func safety_invest(factory: Dictionary, amount: int) -> Dictionary:
	var gain: float = clampf(float(maxi(0, amount)) / 1000000.0, 0.0, 0.4)
	factory["safety"] = clampf(float(factory.get("safety", 0.5)) + gain, 0.0, 0.99)
	return {"ok": true, "safety": float(factory["safety"])}


func upgrade_automation(factory: Dictionary, level: float) -> Dictionary:
	factory["automation"] = clampf(float(factory.get("automation", 0.0)) + maxf(0.0, level), 0.0, 1.0)
	return {"ok": true, "automation": float(factory["automation"]), "efficiency": effective_efficiency(factory)}


func set_environment_limit(factory: Dictionary, ratio: float) -> Dictionary:
	factory["environment_ratio"] = clampf(ratio, 0.0, 1.0)
	return {"ok": true, "environment_ratio": float(factory["environment_ratio"])}


# --- 生产（质量守恒）---

## 排产并生产：产能受最短板约束，且消耗原料不超过可得量。
## 守恒口径：material_input == good_output + defect_output + scrap_output（同单位）。
func produce(factory: Dictionary, recipe_key: String, batches: float = 1.0, opts: Dictionary = {}) -> Dictionary:
	if not RECIPES.has(recipe_key):
		return {"ok": false, "reason": "unknown_recipe"}
	if production_blocked(factory):
		return {"ok": false, "reason": "disrupted"}
	var recipe: Dictionary = RECIPES[recipe_key]
	var inputs: Dictionary = recipe["inputs"]
	var requested: float = maxf(0.0, batches)
	if requested <= 0.0:
		return {"ok": false, "reason": "bad_batches"}
	var cap: Dictionary = capacity(factory, recipe_key, opts)
	# 断料/缺勤对产能的修正。
	if has_disruption(factory, "absenteeism"):
		requested *= 0.7
	# 原料约束：每种原料可得量 / 单耗 → 可生产成品单位数，取最小。
	var material_cap: float = INF
	for mat in inputs.keys():
		var need_per_unit: float = maxf(1e-9, float(inputs[mat]))
		material_cap = minf(material_cap, material_qty(factory, str(mat)) / need_per_unit)
	var output_units: float = minf(minf(requested, float(cap["effective_capacity"])), material_cap)
	output_units = maxf(0.0, output_units)
	# 按实际产量比例扣减原料（inputs 之和为 1.0，故 input 总量 = output_units）。
	var consumed: Dictionary = {}
	var material_input: float = 0.0
	for mat in inputs.keys():
		var use: float = float(inputs[mat]) * output_units
		consumed[str(mat)] = use
		material_input += use
		_deduct_material(factory, str(mat), use)
	var qy: float = quality_yield(factory, recipe_key)
	var good: float = material_input * qy
	var defect: float = material_input * (1.0 - qy) * DEFECT_SHARE
	var scrap: float = material_input - good - defect
	var products: Dictionary = factory["products"]
	products[recipe_key] = float(products.get(recipe_key, 0.0)) + good
	var bottleneck: String = str(cap["bottleneck"])
	if material_cap < minf(requested, float(cap["effective_capacity"])):
		bottleneck = "material"
	return {
		"ok": true, "recipe": recipe_key, "requested": requested, "output_units": output_units,
		"material_input": material_input, "good_output": good, "defect_output": defect, "scrap_output": scrap,
		"quality_yield": qy, "capacity": float(cap["effective_capacity"]), "material_cap": material_cap,
		"bottleneck": bottleneck, "work_hours": float(recipe["work_hours"]) * output_units,
		"consumed": consumed,
	}


func _deduct_material(factory: Dictionary, material: String, amount: float) -> void:
	var mats: Dictionary = factory["materials"]
	if not mats.has(material):
		return
	var entry: Dictionary = mats[material]
	entry["qty"] = maxf(0.0, float(entry.get("qty", 0.0)) - maxf(0.0, amount))
	mats[material] = entry


func product_qty(factory: Dictionary, recipe_key: String) -> float:
	return float((factory.get("products", {}) as Dictionary).get(recipe_key, 0.0))


# --- 订单与交付 ---

func accept_order(factory: Dictionary, recipe_key: String, quantity: float, price: int) -> Dictionary:
	if not RECIPES.has(recipe_key):
		return {"ok": false, "reason": "unknown_recipe"}
	var order: Dictionary = {
		"recipe": recipe_key, "quantity": maxf(0.0, quantity), "price": int(price),
		"delivered": 0.0, "fulfilled": false, "returned": 0.0,
	}
	(factory["orders"] as Array).append(order)
	return {"ok": true, "order": order}


## 交付：从成品扣减并结算收入；交货数量受库存与中断影响，可能延迟（partial）。
func deliver_order(factory: Dictionary, index: int, opts: Dictionary = {}) -> Dictionary:
	if index < 0 or index >= (factory["orders"] as Array).size():
		return {"ok": false, "reason": "no_order"}
	var order: Dictionary = factory["orders"][index]
	if bool(order.get("fulfilled", false)):
		return {"ok": false, "reason": "already_fulfilled"}
	var recipe: String = str(order["recipe"])
	var have: float = product_qty(factory, recipe)
	var want: float = maxf(0.0, float(order["quantity"]) - float(order.get("delivered", 0.0)))
	var qty: float = minf(want, have)
	var products: Dictionary = factory["products"]
	products[recipe] = have - qty
	order["delivered"] = float(order.get("delivered", 0.0)) + qty
	order["fulfilled"] = float(order["delivered"]) >= float(order["quantity"])
	var margin: float = 1.0 + float((MODES.get(str(factory.get("mode", "")), {}) as Dictionary).get("brand_margin", 0.0))
	var revenue: int = int(round(qty * float(order["price"]) * margin))
	factory["money"] = int(factory["money"]) + revenue
	return {
		"ok": true, "delivered": qty, "revenue": revenue, "fulfilled": bool(order["fulfilled"]),
		"late": production_blocked(factory), "remaining": maxf(0.0, float(order["quantity"]) - float(order["delivered"])),
	}


## 次品退货：按退货率回补良品库存并冲减收入。
func handle_return(factory: Dictionary, recipe_key: String, quantity: float, opts: Dictionary = {}) -> Dictionary:
	var qty: float = maxf(0.0, quantity)
	var restock_ratio: float = clampf(float(opts.get("restock_ratio", 0.3)), 0.0, 1.0)
	var refund_rate: float = float(opts.get("refund_rate", float((RECIPES.get(recipe_key, {}) as Dictionary).get("price", 0))))
	var products: Dictionary = factory["products"]
	products[recipe_key] = float(products.get(recipe_key, 0.0)) + qty * restock_ratio
	var refund: int = int(round(qty * refund_rate))
	factory["money"] = int(factory["money"]) - refund
	return {"ok": true, "returned": qty, "restocked": qty * restock_ratio, "refund": refund}


# --- 扩张与资金链 ---

## 产能扩张：资金不足则资金链断裂，拒绝且不改变状态。
func expand_capacity(factory: Dictionary, cost: int, opts: Dictionary = {}) -> Dictionary:
	var amount: int = maxi(0, cost)
	if int(factory.get("money", 0)) < amount:
		return {"ok": false, "reason": "funding_chain_broken", "cost": amount}
	factory["money"] = int(factory["money"]) - amount
	factory["base_capacity"] = float(factory.get("base_capacity", 100.0)) + float(opts.get("capacity_gain", float(amount) / 100000.0))
	return {"ok": true, "cost": amount, "base_capacity": float(factory["base_capacity"])}


func funding_risk(factory: Dictionary, cost: int) -> Dictionary:
	var shortfall: int = maxi(0, cost - int(factory.get("money", 0)))
	return {"ok": true, "shortfall": shortfall, "at_risk": shortfall > 0}


func payroll_cost(factory: Dictionary) -> int:
	var total: int = 0
	for r in ROLES.keys():
		total += staff_count(factory, r) * int((ROLES[r] as Dictionary)["wage"])
	return total


func _roll(forced: float, rng) -> float:
	if forced >= 0.0:
		return clampf(forced, 0.0, 1.0)
	if rng != null:
		return rng.next_float()
	return 0.0


func to_dict(factory: Dictionary) -> Dictionary:
	return factory.duplicate(true)


func from_dict(data: Dictionary) -> Dictionary:
	return data.duplicate(true)
