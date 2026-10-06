class_name DiningSystem
extends RefCounted
## 餐饮与食品工业（R74；design D30）。
##
## 覆盖：
##   - 经营：菜谱研发、成本毛利、定价、菜单管理、选址、翻台率、食材供应链；
##   - 扩张：中央厨房、连锁加盟、门店扩张、品牌管理与标准化品控；
##   - 食品工业：加工、包装、保质、渠道分销、食品安全标准与认证；
##   - 风险：食品安全事故（处罚/召回/口碑）、供应链污染；
##   - 评价与营销：评星、榜单、口碑、网红营销，网红店爆单与差评危机；
##   - 边界：外卖平台抽成、厨师流失被挖角、原料涨价。
##
## 设计取舍：
##   - 门店为纯数据 Dictionary，便于存读档与 headless 测试；
##   - 菜谱 ingredients 之和按 1.0 归一，配合 MATERIALS 基础单价推导单份成本，原料涨价可精确核对；
##   - 翻台率、客单价、客流均为确定性公式；随机项（爆单/差评、被挖角、品控事故）只由外部
##     rng 或 opts 强制值驱动，缺省时确定化，保证同输入同输出。

const MATERIALS: Dictionary = {
	"vegetable": {"name": "蔬菜", "base_unit_cost": 800},
	"meat": {"name": "肉类", "base_unit_cost": 3000},
	"rice": {"name": "米面", "base_unit_cost": 1000},
	"seafood": {"name": "海鲜", "base_unit_cost": 5000},
	"spice": {"name": "调味", "base_unit_cost": 1500},
	"dairy": {"name": "乳制品", "base_unit_cost": 2500},
}

## 菜谱：ingredients 之和为 1.0，单份成本 = Σ(用量 × 原料现价)。
const RECIPES: Dictionary = {
	"home_style": {"name": "家常小炒", "ingredients": {"vegetable": 0.5, "meat": 0.3, "spice": 0.2}, "base_price": 3600, "prep_minutes": 8.0, "taste": 70.0},
	"braised_pork": {"name": "红烧肉", "ingredients": {"meat": 0.7, "spice": 0.3}, "base_price": 5800, "prep_minutes": 15.0, "taste": 78.0},
	"garlic_seafood": {"name": "蒜蓉海鲜", "ingredients": {"seafood": 0.7, "vegetable": 0.2, "spice": 0.1}, "base_price": 9800, "prep_minutes": 12.0, "taste": 82.0},
	"beef_noodle": {"name": "牛肉面", "ingredients": {"rice": 0.5, "meat": 0.3, "vegetable": 0.2}, "base_price": 3200, "prep_minutes": 6.0, "taste": 68.0},
}

## 岗位：产出影响翻台率，品控/研发影响标准化与新菜质量。
const STAFF_ROLES: Dictionary = {
	"chef": {"name": "主厨", "wage": 2000000, "output": 0.5, "quality": 0.012, "menu_dev": 0.6},
	"cook": {"name": "厨师", "wage": 900000, "output": 0.8, "quality": 0.004, "menu_dev": 0.2},
	"waiter": {"name": "服务员", "wage": 500000, "output": 0.6, "quality": 0.0, "menu_dev": 0.0},
	"manager": {"name": "店长", "wage": 1500000, "output": 0.3, "quality": 0.006, "menu_dev": 0.1},
}

## 经营/扩张模式：资本门槛与标准化要求（连锁加盟、食品工业需要标准化达标）。
const EXPANSION: Dictionary = {
	"single_shop": {"name": "单店", "min_capital": 0, "stores": 1, "requires_standardization": 0.0},
	"chain": {"name": "连锁门店", "min_capital": 2000000, "stores": 3, "requires_standardization": 0.30},
	"central_kitchen": {"name": "中央厨房", "min_capital": 5000000, "stores": 3, "requires_standardization": 0.50},
	"franchise": {"name": "连锁加盟", "min_capital": 8000000, "stores": 5, "requires_standardization": 0.60},
	"food_factory": {"name": "食品工业", "min_capital": 20000000, "stores": 5, "requires_standardization": 0.70},
}

## 渠道：价格系数与平台抽成。
const CHANNELS: Dictionary = {
	"dine_in": {"name": "堂食", "price_factor": 1.0, "commission": 0.0},
	"takeout": {"name": "外卖", "price_factor": 0.9, "commission": 0.20},
	"retail": {"name": "零售", "price_factor": 0.8, "commission": 0.05},
	"ecommerce": {"name": "电商", "price_factor": 0.75, "commission": 0.10},
}

## 食品安全标准与认证。
const CERTIFICATIONS: Dictionary = {
	"hygiene_a": {"name": "卫生 A 级", "cost": 200000, "min_hygiene": 70.0, "standard_bonus": 0.10},
	"haccp": {"name": "HACCP", "cost": 800000, "min_hygiene": 80.0, "standard_bonus": 0.15},
	"iso22000": {"name": "ISO 22000", "cost": 1500000, "min_hygiene": 85.0, "standard_bonus": 0.20},
	"organic": {"name": "有机认证", "cost": 1000000, "min_hygiene": 78.0, "standard_bonus": 0.12},
}

## 营销方式：营销系数提升与反噬概率。
const MARKETING: Dictionary = {
	"ads": {"name": "广告投放", "boost": 0.10, "backlash": 0.0},
	"influencer": {"name": "网红营销", "boost": 0.25, "backlash": 0.30},
	"discount": {"name": "促销折扣", "boost": 0.15, "backlash": 0.0},
	"word_of_mouth": {"name": "口碑营销", "boost": 0.08, "backlash": 0.0},
}

## 食品安全事故事由。
const INCIDENT_CAUSES: Array = ["contamination", "expired", "poisoning", "foreign_object"]

## 预包装食品：保质期与渠道加成。
const PACKAGED: Dictionary = {
	"home_style": {"name": "速食家常菜", "shelf_life_days": 180.0, "channel_price_factor": 1.2},
	"braised_pork": {"name": "真空红烧肉", "shelf_life_days": 270.0, "channel_price_factor": 1.4},
	"beef_noodle": {"name": "方便牛肉面", "shelf_life_days": 365.0, "channel_price_factor": 1.1},
}

const STAR_NAMES: Dictionary = {1: "一星", 2: "二星", 3: "三星", 4: "四星", 5: "五星"}

const REFERENCE_STAFF: float = 5.0
const DEFAULT_TASTE: float = 65.0
const BASE_INCIDENT_PENALTY: int = 200000
const RECALL_UNIT_COST: int = 2000
const DAILY_RENT_DAYS: float = 30.0
const PACKAGING_COST: int = 300
const POACH_THRESHOLD: float = 40.0


# --- 数据表 ---

func recipe_keys() -> Array:
	return RECIPES.keys()


func recipe_def(recipe_key: String) -> Dictionary:
	if not RECIPES.has(recipe_key):
		return {}
	return (RECIPES[recipe_key] as Dictionary).duplicate(true)


func material_keys() -> Array:
	return MATERIALS.keys()


func material_def(material: String) -> Dictionary:
	if not MATERIALS.has(material):
		return {}
	return (MATERIALS[material] as Dictionary).duplicate(true)


func staff_role_keys() -> Array:
	return STAFF_ROLES.keys()


func expansion_modes() -> Array:
	return EXPANSION.keys()


func expansion_def(mode: String) -> Dictionary:
	if not EXPANSION.has(mode):
		return {}
	return (EXPANSION[mode] as Dictionary).duplicate(true)


func channel_keys() -> Array:
	return CHANNELS.keys()


func channel_def(channel: String) -> Dictionary:
	if not CHANNELS.has(channel):
		return {}
	return (CHANNELS[channel] as Dictionary).duplicate(true)


func certification_keys() -> Array:
	return CERTIFICATIONS.keys()


func certification_def(cert_id: String) -> Dictionary:
	if not CERTIFICATIONS.has(cert_id):
		return {}
	return (CERTIFICATIONS[cert_id] as Dictionary).duplicate(true)


# --- 开店 ---

func new_restaurant(money: int = 1000000, opts: Dictionary = {}) -> Dictionary:
	var staff: Dictionary = {}
	for r in STAFF_ROLES.keys():
		staff[r] = 0
	return {
		"money": money,
		"name": str(opts.get("name", "小馆")),
		"location": {
			"region_id": str(opts.get("region_id", "")),
			"area_sqm": maxf(1.0, float(opts.get("area_sqm", 60.0))),
			"monthly_rent": maxi(0, int(opts.get("monthly_rent", 0))),
			"foot_traffic": maxf(0.0, float(opts.get("foot_traffic", 1.0))),
		},
		"tables": maxi(1, int(opts.get("tables", 10))),
		"seats_per_table": maxi(1, int(opts.get("seats_per_table", 4))),
		"base_turnover": clampf(float(opts.get("base_turnover", 2.0)), 0.5, 6.0),
		"menu": [],
		"prices": {},
		"material_costs": {},
		"materials": {},
		"suppliers": [],
		"reputation": clampf(float(opts.get("reputation", 50.0)), 0.0, 100.0),
		"hygiene": clampf(float(opts.get("hygiene", 70.0)), 0.0, 100.0),
		"brand": clampf(float(opts.get("brand", 40.0)), 0.0, 100.0),
		"marketing": 1.0,
		"staff": staff,
		"mode": "single_shop",
		"central_kitchen": false,
		"stores": 1,
		"franchise_count": 0,
		"certifications": [],
		"channel": {"dine_in": true, "takeout": false},
		"products": {},
		"incidents": [],
		"chef_loyalty": clampf(float(opts.get("chef_loyalty", 70.0)), 0.0, 100.0),
		"viral": "",
	}


# --- 选址 ---

func choose_location(restaurant: Dictionary, region_id: String, area_sqm: float, monthly_rent: int, foot_traffic: float) -> Dictionary:
	restaurant["location"] = {
		"region_id": region_id,
		"area_sqm": maxf(1.0, area_sqm),
		"monthly_rent": maxi(0, monthly_rent),
		"foot_traffic": maxf(0.0, foot_traffic),
	}
	return {"ok": true, "location": (restaurant["location"] as Dictionary).duplicate(true)}


## 选址质量：客流 + 租金性价比（面积越大租金越高越不划算）。
func location_quality(restaurant: Dictionary) -> Dictionary:
	var loc: Dictionary = restaurant.get("location", {})
	var foot: float = maxf(0.0, float(loc.get("foot_traffic", 1.0)))
	var area: float = maxf(1.0, float(loc.get("area_sqm", 60.0)))
	var rent: float = float(loc.get("monthly_rent", 0))
	var rent_ratio: float = clampf(rent / (area * 2000.0), 0.0, 2.0)
	var score: float = clampf(foot * 0.7 + (1.0 - rent_ratio) * 0.3, 0.0, 2.0)
	return {"ok": true, "foot_traffic": foot, "rent_ratio": rent_ratio, "score": score}


# --- 菜单与成本毛利 ---

func menu_keys(restaurant: Dictionary) -> Array:
	return (restaurant.get("menu", []) as Array).duplicate()


func add_to_menu(restaurant: Dictionary, recipe_key: String) -> Dictionary:
	if not RECIPES.has(recipe_key):
		return {"ok": false, "reason": "unknown_recipe"}
	var menu: Array = restaurant["menu"]
	if not menu.has(recipe_key):
		menu.append(recipe_key)
	return {"ok": true, "menu": menu.duplicate()}


func remove_from_menu(restaurant: Dictionary, recipe_key: String) -> Dictionary:
	var menu: Array = restaurant["menu"]
	menu.erase(recipe_key)
	return {"ok": true, "menu": menu.duplicate()}


func set_price(restaurant: Dictionary, recipe_key: String, price: int) -> Dictionary:
	if not RECIPES.has(recipe_key):
		return {"ok": false, "reason": "unknown_recipe"}
	if price < 0:
		return {"ok": false, "reason": "bad_price"}
	(restaurant["prices"] as Dictionary)[recipe_key] = price
	return {"ok": true, "price": price}


func day_price(restaurant: Dictionary, recipe_key: String) -> int:
	if (restaurant.get("prices", {}) as Dictionary).has(recipe_key):
		return int((restaurant["prices"] as Dictionary)[recipe_key])
	return int((RECIPES.get(recipe_key, {}) as Dictionary).get("base_price", 0))


func material_unit_cost(restaurant: Dictionary, material: String) -> int:
	if (restaurant.get("material_costs", {}) as Dictionary).has(material):
		return int((restaurant["material_costs"] as Dictionary)[material])
	return int((MATERIALS.get(material, {}) as Dictionary).get("base_unit_cost", 0))


## 单份成本 = Σ(原料用量 × 原料现价)。
func recipe_cost(restaurant: Dictionary, recipe_key: String) -> int:
	if not RECIPES.has(recipe_key):
		return 0
	var inputs: Dictionary = (RECIPES[recipe_key] as Dictionary)["ingredients"]
	var total: float = 0.0
	for mat in inputs.keys():
		total += float(inputs[mat]) * float(material_unit_cost(restaurant, str(mat)))
	return int(round(total))


## 成本毛利：返回成本、定价、毛利额与毛利率。
func recipe_margin(restaurant: Dictionary, recipe_key: String) -> Dictionary:
	if not RECIPES.has(recipe_key):
		return {"ok": false, "reason": "unknown_recipe"}
	var cost: int = recipe_cost(restaurant, recipe_key)
	var price: int = day_price(restaurant, recipe_key)
	var gross: int = price - cost
	var margin: float = 0.0
	if price > 0:
		margin = clampf(float(gross) / float(price), -1.0, 1.0)
	return {"ok": true, "cost": cost, "price": price, "gross_profit": gross, "gross_margin": margin}


func avg_menu_price(restaurant: Dictionary) -> float:
	var menu: Array = restaurant["menu"]
	if menu.is_empty():
		return 0.0
	var total: int = 0
	for key in menu:
		total += day_price(restaurant, str(key))
	return float(total) / float(menu.size())


func avg_menu_cost(restaurant: Dictionary) -> float:
	var menu: Array = restaurant["menu"]
	if menu.is_empty():
		return 0.0
	var total: int = 0
	for key in menu:
		total += recipe_cost(restaurant, str(key))
	return float(total) / float(menu.size())


func avg_menu_taste(restaurant: Dictionary) -> float:
	var menu: Array = restaurant["menu"]
	if menu.is_empty():
		return DEFAULT_TASTE
	var total: float = 0.0
	for key in menu:
		total += float((RECIPES.get(str(key), {}) as Dictionary).get("taste", DEFAULT_TASTE))
	return total / float(menu.size())


## 菜谱研发：受主厨研发能力与投入资金影响，返回新菜质量评分。新菜写入 products 之外的菜单候选。
func research_recipe(restaurant: Dictionary, base_recipe: String, budget: int, rng = null, opts: Dictionary = {}) -> Dictionary:
	if not RECIPES.has(base_recipe):
		return {"ok": false, "reason": "unknown_recipe"}
	var spend: int = maxi(0, budget)
	if int(restaurant.get("money", 0)) < spend:
		return {"ok": false, "reason": "insufficient_funds", "cost": spend}
	restaurant["money"] = int(restaurant["money"]) - spend
	var luck: float = _roll(float(opts.get("luck", -1.0)), rng) * 100.0
	var dev: float = 0.0
	for role in STAFF_ROLES.keys():
		dev += float(staff_count(restaurant, role)) * float((STAFF_ROLES[role] as Dictionary)["menu_dev"])
	var base_taste: float = float((RECIPES[base_recipe] as Dictionary)["taste"])
	var quality: float = clampf(base_taste * 0.6 + minf(25.0, dev * 4.0) + luck * 0.15 + float(spend) / 200000.0, 0.0, 100.0)
	return {"ok": true, "base": base_recipe, "quality": quality, "taste": quality, "cost": spend}


# --- 人力 ---

func staff_count(restaurant: Dictionary, role: String) -> int:
	return int((restaurant.get("staff", {}) as Dictionary).get(role, 0))


func headcount(restaurant: Dictionary) -> int:
	var total: int = 0
	for r in STAFF_ROLES.keys():
		total += staff_count(restaurant, r)
	return total


func hire(restaurant: Dictionary, role: String, count: int) -> Dictionary:
	if not STAFF_ROLES.has(role):
		return {"ok": false, "reason": "unknown_role"}
	var staff: Dictionary = restaurant["staff"]
	staff[role] = int(staff.get(role, 0)) + maxi(0, count)
	return {"ok": true, "role": role, "count": int(staff[role])}


func labor_output(restaurant: Dictionary) -> float:
	var total: float = 0.0
	for r in STAFF_ROLES.keys():
		total += float(staff_count(restaurant, r)) * float((STAFF_ROLES[r] as Dictionary)["output"])
	return total


func staff_factor(restaurant: Dictionary) -> float:
	return clampf(0.5 + labor_output(restaurant) / REFERENCE_STAFF, 0.5, 2.0)


func daily_payroll(restaurant: Dictionary) -> int:
	var total: int = 0
	for r in STAFF_ROLES.keys():
		total += staff_count(restaurant, r) * int((STAFF_ROLES[r] as Dictionary)["wage"])
	return int(float(total) / DAILY_RENT_DAYS)


# --- 翻台率与客流 ---

func seat_capacity(restaurant: Dictionary) -> int:
	return maxi(0, int(restaurant.get("tables", 1)) * int(restaurant.get("seats_per_table", 4)))


## 翻台率：基础翻台 × 口碑 × 人力，clamp 到 [0.5, 6]。
func expected_turnover(restaurant: Dictionary) -> float:
	var base: float = float(restaurant.get("base_turnover", 2.0))
	var rep_factor: float = 0.5 + clampf(float(restaurant.get("reputation", 50.0)), 0.0, 100.0) / 100.0
	return clampf(base * rep_factor * staff_factor(restaurant), 0.5, 6.0)


func daily_capacity(restaurant: Dictionary) -> float:
	return float(seat_capacity(restaurant)) * expected_turnover(restaurant)


## 客流需求：受选址、口碑、评星与营销影响。
func demand(restaurant: Dictionary, opts: Dictionary = {}) -> float:
	var loc: Dictionary = restaurant.get("location", {})
	var area: float = maxf(1.0, float(loc.get("area_sqm", 60.0)))
	var foot: float = maxf(0.0, float(loc.get("foot_traffic", 1.0)))
	var rep: float = clampf(float(restaurant.get("reputation", 50.0)), 0.0, 100.0)
	var stars: int = review_stars(restaurant)
	var base: float = area * foot * 0.8
	var rep_factor: float = 0.4 + rep / 100.0
	var star_factor: float = 0.5 + float(stars) / 5.0
	var multiplier: float = maxf(0.0, float(restaurant.get("marketing", 1.0)))
	return base * rep_factor * star_factor * multiplier * float(opts.get("demand_factor", 1.0))


## 单日经营：堂食/外卖按渠道计算收入、抽成、食材成本、房租与工资。
func sell_day(restaurant: Dictionary, opts: Dictionary = {}, rng = null) -> Dictionary:
	var channel: String = str(opts.get("channel", "dine_in"))
	if not CHANNELS.has(channel):
		return {"ok": false, "reason": "unknown_channel"}
	if not bool((restaurant.get("channel", {}) as Dictionary).get(channel, channel == "dine_in")):
		return {"ok": false, "reason": "channel_disabled"}
	var ch: Dictionary = CHANNELS[channel]
	var want: float = demand(restaurant, opts)
	var cap: float = daily_capacity(restaurant)
	var overload: bool = want > cap * 1.1
	var covers: float = minf(want, cap)
	var avg_price: float = avg_menu_price(restaurant) * float(ch["price_factor"])
	var avg_cost: float = avg_menu_cost(restaurant)
	var revenue: int = int(round(covers * avg_price))
	var commission: int = int(round(float(revenue) * float(ch["commission"])))
	var cogs: int = int(round(covers * avg_cost))
	var rent: int = int(float((restaurant.get("location", {}) as Dictionary).get("monthly_rent", 0)) / DAILY_RENT_DAYS)
	var payroll: int = daily_payroll(restaurant)
	var profit: int = revenue - commission - cogs - rent - payroll
	restaurant["money"] = int(restaurant["money"]) + profit
	return {
		"ok": true, "channel": channel, "channel_name": str(ch["name"]),
		"covers": covers, "demand": want, "capacity": cap, "overload": overload,
		"revenue": revenue, "commission": commission, "cogs": cogs,
		"rent": rent, "payroll": payroll, "profit": profit,
	}


## 外卖平台抽成（独立核算，供利润结构展示）。
func takeout_commission(amount: int, rate: float = -1.0) -> Dictionary:
	var r: float = clampf(float(CHANNELS["takeout"]["commission"]) if rate < 0.0 else rate, 0.0, 1.0)
	var cut: int = int(round(float(maxi(0, amount)) * r))
	return {"ok": true, "commission": cut, "rate": r, "net": maxi(0, amount) - cut}


# --- 食材供应链 ---

func material_qty(restaurant: Dictionary, material: String) -> float:
	var mats: Dictionary = restaurant.get("materials", {})
	if not mats.has(material):
		return 0.0
	return float((mats[material] as Dictionary).get("qty", 0.0))


func add_material(restaurant: Dictionary, material: String, qty: float, unit_cost: int = 0) -> Dictionary:
	var mats: Dictionary = restaurant["materials"]
	var entry: Dictionary = mats.get(material, {"qty": 0.0, "unit_cost": int(unit_cost)})
	var old_qty: float = float(entry.get("qty", 0.0))
	var total: float = old_qty + maxf(0.0, qty)
	var weighted: int = int(unit_cost)
	if total > 0.0:
		weighted = int(round((old_qty * float(entry.get("unit_cost", unit_cost)) + maxf(0.0, qty) * float(unit_cost)) / total))
	entry["qty"] = total
	entry["unit_cost"] = weighted
	mats[material] = entry
	return {"ok": true, "material": material, "qty": total}


func add_supplier(restaurant: Dictionary, supplier: Dictionary) -> Dictionary:
	var suppliers: Array = restaurant["suppliers"]
	var id: String = str(supplier.get("id", "sup_%d" % suppliers.size()))
	var rec: Dictionary = {
		"id": id,
		"name": str(supplier.get("name", id)),
		"materials": (supplier.get("materials", []) as Array).duplicate(),
		"price_factor": clampf(float(supplier.get("price_factor", 1.0)), 0.1, 5.0),
		"reliability": clampf(float(supplier.get("reliability", 0.9)), 0.0, 1.0),
		"contaminated": bool(supplier.get("contaminated", false)),
	}
	suppliers.append(rec)
	return {"ok": true, "supplier": rec}


## 采购：可靠性决定实收量（断料），价格系数体现涨价，污染供应商标记污染批次。
func purchase(restaurant: Dictionary, material: String, qty: float, opts: Dictionary = {}) -> Dictionary:
	var amount: float = maxf(0.0, qty)
	var candidates: Array = []
	for s in (restaurant["suppliers"] as Array):
		if (s as Dictionary)["materials"].has(material):
			candidates.append(s)
	if candidates.is_empty():
		return {"ok": false, "reason": "no_supplier", "material": material}
	if amount <= 0.0:
		return {"ok": false, "reason": "bad_quantity"}
	var supplier: Dictionary = candidates[0]
	var reliable: float = clampf(float(supplier.get("reliability", 0.9)), 0.0, 1.0)
	var delivered: float = amount * reliable
	var unit_cost: int = int(round(float(opts.get("base_unit_cost", material_unit_cost(restaurant, material))) * float(supplier.get("price_factor", 1.0))))
	var cost: int = int(round(delivered * float(unit_cost)))
	if int(restaurant.get("money", 0)) < cost:
		return {"ok": false, "reason": "insufficient_funds", "cost": cost}
	restaurant["money"] = int(restaurant["money"]) - cost
	add_material(restaurant, material, delivered, unit_cost)
	return {
		"ok": true, "material": material, "delivered": delivered, "unit_cost": unit_cost,
		"cost": cost, "shortfall": amount - delivered, "contaminated": bool(supplier.get("contaminated", false)),
	}


## 供应链污染：标记供应商受污染。
func contaminate_supply(restaurant: Dictionary, supplier_id: String) -> Dictionary:
	var suppliers: Array = restaurant["suppliers"]
	for s in suppliers:
		if str((s as Dictionary).get("id", "")) == supplier_id:
			(s as Dictionary)["contaminated"] = true
			return {"ok": true, "supplier": supplier_id, "contaminated": true}
	return {"ok": false, "reason": "unknown_supplier"}


## 单一供应商风险。
func supply_risk(restaurant: Dictionary) -> Dictionary:
	var counts: Dictionary = {}
	for s in (restaurant["suppliers"] as Array):
		for m in ((s as Dictionary)["materials"] as Array):
			counts[m] = int(counts.get(m, 0)) + 1
	var single: Array = []
	for m in counts.keys():
		if int(counts[m]) <= 1:
			single.append(m)
	return {"ok": true, "single_source": single, "risk": clampf(float(single.size()) * 0.2, 0.0, 1.0)}


## 原料涨价：按倍数调整某原料现价。
func ingredient_price_shock(restaurant: Dictionary, material: String, factor: float) -> Dictionary:
	if not MATERIALS.has(material):
		return {"ok": false, "reason": "unknown_material"}
	var base: float = float((MATERIALS[material] as Dictionary)["base_unit_cost"])
	var new_cost: int = int(round(base * maxf(0.0, factor)))
	(restaurant["material_costs"] as Dictionary)[material] = new_cost
	return {"ok": true, "material": material, "unit_cost": new_cost}


# --- 标准化、扩张与认证 ---

## 标准化评分 0..1：中央厨房、认证、品牌与品控岗位共同决定。
func standardization_score(restaurant: Dictionary) -> float:
	var score: float = 0.0
	if bool(restaurant.get("central_kitchen", false)):
		score += 0.30
	score += clampf(float(restaurant.get("brand", 0.0)) / 100.0, 0.0, 1.0) * 0.20
	for cert in (restaurant.get("certifications", []) as Array):
		score += float((CERTIFICATIONS.get(str(cert), {}) as Dictionary).get("standard_bonus", 0.0))
	for role in STAFF_ROLES.keys():
		score += float(staff_count(restaurant, role)) * float((STAFF_ROLES[role] as Dictionary)["quality"])
	return clampf(score, 0.0, 1.0)


func can_enter_mode(restaurant: Dictionary, mode: String) -> bool:
	if not EXPANSION.has(mode):
		return false
	var def: Dictionary = EXPANSION[mode]
	if int(restaurant.get("money", 0)) < int(def["min_capital"]):
		return false
	return standardization_score(restaurant) >= float(def["requires_standardization"]) - 1e-9


## 扩张到目标模式：校验资本与标准化门槛，失败返回原因。
func expand_to(restaurant: Dictionary, mode: String, opts: Dictionary = {}) -> Dictionary:
	if not EXPANSION.has(mode):
		return {"ok": false, "reason": "unknown_mode"}
	if not can_enter_mode(restaurant, mode):
		return {"ok": false, "reason": "not_qualified", "standardization": standardization_score(restaurant)}
	if mode == "central_kitchen":
		restaurant["central_kitchen"] = true
	restaurant["mode"] = mode
	restaurant["stores"] = maxi(int(restaurant.get("stores", 1)), int((EXPANSION[mode] as Dictionary)["stores"]))
	return {"ok": true, "mode": mode, "stores": int(restaurant["stores"]), "standardization": standardization_score(restaurant)}


## 开新门店：资金不足拒绝。
func open_store(restaurant: Dictionary, cost: int) -> Dictionary:
	var amount: int = maxi(0, cost)
	if int(restaurant.get("money", 0)) < amount:
		return {"ok": false, "reason": "insufficient_funds", "cost": amount}
	restaurant["money"] = int(restaurant["money"]) - amount
	restaurant["stores"] = int(restaurant.get("stores", 1)) + 1
	return {"ok": true, "stores": int(restaurant["stores"])}


## 连锁加盟：需要标准化达标与品牌基础，收取加盟费并入账，品牌提升。
func franchise(restaurant: Dictionary, fee: int) -> Dictionary:
	if standardization_score(restaurant) < float((EXPANSION["franchise"] as Dictionary)["requires_standardization"]) - 1e-9:
		return {"ok": false, "reason": "not_qualified"}
	restaurant["franchise_count"] = int(restaurant.get("franchise_count", 0)) + 1
	restaurant["money"] = int(restaurant["money"]) + maxi(0, fee)
	restaurant["brand"] = clampf(float(restaurant.get("brand", 0.0)) + 1.0, 0.0, 100.0)
	return {"ok": true, "franchise_count": int(restaurant["franchise_count"]), "fee": maxi(0, fee)}


## 申请食安认证：校验资金与卫生门槛。
func certify(restaurant: Dictionary, cert_id: String) -> Dictionary:
	if not CERTIFICATIONS.has(cert_id):
		return {"ok": false, "reason": "unknown_certification"}
	var def: Dictionary = CERTIFICATIONS[cert_id]
	if float(restaurant.get("hygiene", 0.0)) < float(def["min_hygiene"]):
		return {"ok": false, "reason": "hygiene_too_low", "required": float(def["min_hygiene"])}
	if int(restaurant.get("money", 0)) < int(def["cost"]):
		return {"ok": false, "reason": "insufficient_funds", "cost": int(def["cost"])}
	restaurant["money"] = int(restaurant["money"]) - int(def["cost"])
	var certs: Array = restaurant["certifications"]
	if not certs.has(cert_id):
		certs.append(cert_id)
	restaurant["hygiene"] = clampf(float(restaurant.get("hygiene", 0.0)) + 2.0, 0.0, 100.0)
	return {"ok": true, "certification": cert_id, "standardization": standardization_score(restaurant)}


func has_certification(restaurant: Dictionary, cert_id: String) -> bool:
	return (restaurant.get("certifications", []) as Array).has(cert_id)


# --- 食品工业：加工、包装、保质、分销 ---

## 加工预包装食品：需中央厨房或食品工业模式；按件收包装费。
func process_food(restaurant: Dictionary, recipe_key: String, qty: float, opts: Dictionary = {}) -> Dictionary:
	if not PACKAGED.has(recipe_key):
		return {"ok": false, "reason": "not_packageable"}
	if not (bool(restaurant.get("central_kitchen", false)) or str(restaurant.get("mode", "")) == "food_factory"):
		return {"ok": false, "reason": "no_food_facility"}
	var amount: float = maxf(0.0, qty)
	if amount <= 0.0:
		return {"ok": false, "reason": "bad_quantity"}
	var unit_packaging: int = int(opts.get("packaging_cost", PACKAGING_COST))
	var cost: int = int(round(amount * float(unit_packaging)))
	if int(restaurant.get("money", 0)) < cost:
		return {"ok": false, "reason": "insufficient_funds", "cost": cost}
	restaurant["money"] = int(restaurant["money"]) - cost
	var products: Dictionary = restaurant["products"]
	var entry: Dictionary = products.get(recipe_key, {"qty": 0.0})
	entry["qty"] = float(entry.get("qty", 0.0)) + amount
	products[recipe_key] = entry
	return {"ok": true, "product": recipe_key, "qty": float(entry["qty"]), "packaging_cost": cost, "shelf_life_days": float((PACKAGED[recipe_key] as Dictionary)["shelf_life_days"])}


func product_qty(restaurant: Dictionary, recipe_key: String) -> float:
	return float((restaurant.get("products", {}) as Dictionary).get(recipe_key, {}).get("qty", 0.0))


## 渠道分销预包装食品：按渠道价格系数结算并扣抽成。
func distribute(restaurant: Dictionary, product_key: String, qty: float, channel: String = "retail") -> Dictionary:
	if not CHANNELS.has(channel):
		return {"ok": false, "reason": "unknown_channel"}
	var amount: float = maxf(0.0, qty)
	var have: float = product_qty(restaurant, product_key)
	var sold: float = minf(amount, have)
	if sold <= 0.0:
		return {"ok": false, "reason": "no_stock"}
	var base_price: float = float((RECIPES.get(product_key, {}) as Dictionary).get("base_price", 0.0))
	var pack_factor: float = float((PACKAGED.get(product_key, {}) as Dictionary).get("channel_price_factor", 1.0))
	var ch: Dictionary = CHANNELS[channel]
	var gross: int = int(round(sold * base_price * pack_factor * float(ch["price_factor"])))
	var commission: int = int(round(float(gross) * float(ch["commission"])))
	restaurant["money"] = int(restaurant["money"]) + gross - commission
	(restaurant["products"] as Dictionary)[product_key] = {"qty": have - sold}
	return {"ok": true, "sold": sold, "gross": gross, "commission": commission, "net": gross - commission}


## 保质：按天数对预包装食品做损耗（超期即报废）。days 相对保质期比例。
func spoilage(restaurant: Dictionary, days: float, opts: Dictionary = {}) -> Dictionary:
	var d: float = maxf(0.0, days)
	var rate: float = clampf(float(opts.get("rate", -1.0)), 0.0, 1.0)
	var lost: float = 0.0
	var products: Dictionary = restaurant["products"]
	for key in products.keys():
		var entry: Dictionary = products[key]
		var have: float = float(entry.get("qty", 0.0))
		if have <= 0.0:
			continue
		var shelf: float = maxf(1.0, float((PACKAGED.get(str(key), {}) as Dictionary).get("shelf_life_days", 180.0)))
		var spoil_rate: float = rate if rate >= 0.0 else clampf(d / shelf, 0.0, 1.0)
		var gone: float = have * spoil_rate
		entry["qty"] = maxf(0.0, have - gone)
		products[key] = entry
		lost += gone
	return {"ok": true, "lost": lost}


# --- 风险：食安事故与召回 ---

## 食品安全事故：处罚 + 召回成本 + 口碑/卫生下滑，严重时停业整顿。
func food_safety_incident(restaurant: Dictionary, cause: String, severity: float, opts: Dictionary = {}) -> Dictionary:
	if not INCIDENT_CAUSES.has(cause):
		return {"ok": false, "reason": "unknown_cause"}
	var sev: float = clampf(severity, 0.1, 1.0)
	var penalty: int = int(round(float(BASE_INCIDENT_PENALTY) * sev))
	var recall_qty: float = maxf(0.0, float(opts.get("recall_qty", 100.0)))
	var recall_cost: int = int(round(recall_qty * float(RECALL_UNIT_COST) * sev))
	var rep_loss: float = 20.0 * sev
	var hygiene_loss: float = 15.0 * sev
	restaurant["money"] = int(restaurant["money"]) - penalty - recall_cost
	restaurant["reputation"] = clampf(float(restaurant.get("reputation", 50.0)) - rep_loss, 0.0, 100.0)
	restaurant["hygiene"] = clampf(float(restaurant.get("hygiene", 70.0)) - hygiene_loss, 0.0, 100.0)
	var suspended: bool = bool(opts.get("suspend", sev >= 0.9))
	var incident: Dictionary = {
		"cause": cause, "severity": sev, "penalty": penalty,
		"recall_cost": recall_cost, "reputation_loss": rep_loss, "suspended": suspended,
	}
	(restaurant["incidents"] as Array).append(incident)
	return {"ok": true, "incident": incident, "money": int(restaurant["money"]), "reputation": float(restaurant["reputation"])}


## 召回：按数量结算召回费用并小幅损耗口碑。
func recall_product(restaurant: Dictionary, product_key: String, qty: float, opts: Dictionary = {}) -> Dictionary:
	var amount: float = maxf(0.0, qty)
	var unit: int = int(opts.get("unit_cost", RECALL_UNIT_COST))
	var cost: int = int(round(amount * float(unit)))
	if int(restaurant.get("money", 0)) < cost:
		cost = maxi(0, int(restaurant.get("money", 0)))
	restaurant["money"] = int(restaurant["money"]) - cost
	restaurant["reputation"] = clampf(float(restaurant.get("reputation", 50.0)) - clampf(amount / 500.0, 0.0, 5.0), 0.0, 100.0)
	var products: Dictionary = restaurant["products"]
	if products.has(product_key):
		var entry: Dictionary = products[product_key]
		entry["qty"] = maxf(0.0, float(entry.get("qty", 0.0)) - amount)
		products[product_key] = entry
	return {"ok": true, "recalled": amount, "cost": cost, "reputation": float(restaurant["reputation"])}


## 品控抽查：标准化越低、卫生越差，事故风险越高；可用 opts.roll 强制。
func quality_control(restaurant: Dictionary, opts: Dictionary = {}, rng = null) -> Dictionary:
	var std: float = standardization_score(restaurant)
	var hygiene: float = clampf(float(restaurant.get("hygiene", 70.0)), 0.0, 100.0)
	var risk: float = clampf(0.25 - std * 0.2 + (100.0 - hygiene) / 400.0, 0.0, 0.9)
	var roll: float = _roll(float(opts.get("roll", -1.0)), rng)
	var passed: bool = roll >= risk
	return {"ok": true, "passed": passed, "risk": risk, "standardization": std}


# --- 评价与营销 ---

## 评星 1..5：口碑、卫生与菜品口味加权。
func review_stars(restaurant: Dictionary) -> int:
	var score: float = (
		clampf(float(restaurant.get("reputation", 50.0)), 0.0, 100.0) * 0.5
		+ clampf(float(restaurant.get("hygiene", 70.0)), 0.0, 100.0) * 0.3
		+ clampf(avg_menu_taste(restaurant), 0.0, 100.0) * 0.2
	)
	return clampi(int(round(score / 20.0)), 1, 5)


func star_name(restaurant: Dictionary) -> String:
	return str(STAR_NAMES.get(review_stars(restaurant), "三星"))


## 美食榜单：按综合分在 total 家餐厅中的排名（越小越好）。
func rank_listing(restaurant: Dictionary, total: int = 100) -> Dictionary:
	var n: int = maxi(1, total)
	var score: float = (
		clampf(float(restaurant.get("reputation", 50.0)), 0.0, 100.0) * 0.6
		+ float(review_stars(restaurant)) / 5.0 * 40.0
	)
	var rank: int = clampi(int(round(float(n) * (1.0 - score / 100.0))) + 1, 1, n)
	return {"ok": true, "rank": rank, "total": n, "score": score}


## 营销：投入资金提升营销系数；网红营销有反噬概率。
func marketing_campaign(restaurant: Dictionary, kind: String, cost: int, rng = null, opts: Dictionary = {}) -> Dictionary:
	if not MARKETING.has(kind):
		return {"ok": false, "reason": "unknown_marketing"}
	var def: Dictionary = MARKETING[kind]
	var spend: int = maxi(0, cost)
	if int(restaurant.get("money", 0)) < spend:
		return {"ok": false, "reason": "insufficient_funds", "cost": spend}
	restaurant["money"] = int(restaurant["money"]) - spend
	var boost: float = float(def["boost"]) * clampf(float(spend) / 200000.0, 0.0, 3.0)
	restaurant["marketing"] = maxf(0.1, float(restaurant.get("marketing", 1.0)) + boost)
	var backlash: bool = false
	var risk: float = float(def["backlash"])
	if risk > 0.0:
		backlash = _roll(float(opts.get("roll", -1.0)), rng) < risk
	if backlash:
		restaurant["reputation"] = clampf(float(restaurant.get("reputation", 50.0)) - 8.0, 0.0, 100.0)
	return {"ok": true, "kind": kind, "boost": boost, "backlash": backlash, "marketing": float(restaurant["marketing"])}


## 网红事件：低 roll 为爆单（营销暴涨），高 roll 为差评危机（口碑下滑）。
func viral_event(restaurant: Dictionary, roll: float) -> Dictionary:
	var r: float = clampf(roll, 0.0, 1.0)
	if r < 0.5:
		restaurant["marketing"] = maxf(0.1, float(restaurant.get("marketing", 1.0)) + 0.5)
		restaurant["reputation"] = clampf(float(restaurant.get("reputation", 50.0)) + 3.0, 0.0, 100.0)
		restaurant["viral"] = "boom"
		return {"ok": true, "kind": "boom", "marketing": float(restaurant["marketing"]), "reputation": float(restaurant["reputation"])}
	restaurant["reputation"] = clampf(float(restaurant.get("reputation", 50.0)) - 10.0, 0.0, 100.0)
	restaurant["marketing"] = maxf(0.1, float(restaurant.get("marketing", 1.0)) - 0.2)
	restaurant["viral"] = "crisis"
	return {"ok": true, "kind": "crisis", "marketing": float(restaurant["marketing"]), "reputation": float(restaurant["reputation"])}


# --- 边界：厨师流失与保留 ---

## 提高主厨留任意愿。
func pay_retention(restaurant: Dictionary, amount: int) -> Dictionary:
	var gain: float = clampf(float(maxi(0, amount)) / 200000.0, 0.0, 40.0)
	restaurant["chef_loyalty"] = clampf(float(restaurant.get("chef_loyalty", 70.0)) + gain, 0.0, 100.0)
	return {"ok": true, "chef_loyalty": float(restaurant["chef_loyalty"])}


## 厨师被挖角：忠诚过低时按 roll 流失一名主厨，口碑受损。
func poach_chef(restaurant: Dictionary, roll: float, opts: Dictionary = {}) -> Dictionary:
	var chefs: int = staff_count(restaurant, "chef")
	if chefs <= 0:
		return {"ok": false, "reason": "no_chef"}
	var loyalty: float = float(restaurant.get("chef_loyalty", 70.0))
	var risk: float = clampf(float(opts.get("risk", (POACH_THRESHOLD - loyalty) / 100.0 + 0.2)), 0.0, 0.95)
	var r: float = clampf(roll, 0.0, 1.0)
	if r >= risk and not bool(opts.get("force", false)):
		return {"ok": true, "poached": false, "risk": risk}
	var staff: Dictionary = restaurant["staff"]
	staff["chef"] = maxi(0, chefs - 1)
	restaurant["chef_loyalty"] = clampf(loyalty - 20.0, 0.0, 100.0)
	restaurant["reputation"] = clampf(float(restaurant.get("reputation", 50.0)) - 5.0, 0.0, 100.0)
	return {"ok": true, "poached": true, "chefs": int(staff["chef"]), "chef_loyalty": float(restaurant["chef_loyalty"])}


func _roll(forced: float, rng) -> float:
	if forced >= 0.0:
		return clampf(forced, 0.0, 1.0)
	if rng != null:
		return rng.next_float()
	return 0.0


func to_dict(restaurant: Dictionary) -> Dictionary:
	return restaurant.duplicate(true)


func from_dict(data: Dictionary) -> Dictionary:
	return data.duplicate(true)
