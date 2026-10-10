class_name PrimaryIndustrySystem
extends RefCounted
## 农林牧渔深化（R73；design D29）。
##
## 覆盖：
##   - 渔业：渔船、捕捞、养殖、休渔期；含海难与过度捕捞导致资源恢复变慢；渔获价格波动；
##   - 林业：林权、采伐、造林、护林、森林火灾；木材市场与林业碳汇；
##   - 狩猎与采集：需许可并符合枪支政策，无证狩猎入违法处理；含野生动物与保护区；
##   - 生态与可持续：过度开发导致资源衰退、水土流失、生态修复成本；外来物种入侵；
##   - 边界：极端天气减产、偷猎与走私、休渔期违规捕捞被罚。
##
## 设计取舍：
##   - 渔业/林业/狩猎为纯数据 Dictionary，生态为通用状态 Dictionary，便于存读档与 headless 测试；
##   - 资源恢复随“过度捕捞程度”变慢：恢复率 = 基础恢复 × 当前资源比例，简单且单调；
##   - 随机项（海难、火灾、狩猎命中）由外部 roll/rng 注入，缺省确定化（roll=0）；
##   - 违法捕捞/偷猎/无证狩猎统一走 legal_consequence，返回罚款与违法标记。

const BaselineScript = preload("res://sim/baseline.gd")

const FISH_SPECIES: Dictionary = {
	"cod": {"name": "鳕鱼", "price": 3000, "recovery": 0.01},
	"tuna": {"name": "金枪鱼", "price": 12000, "recovery": 0.005},
	"shrimp": {"name": "虾", "price": 6000, "recovery": 0.02},
}

const FOREST_TYPES: Dictionary = {
	"timber": {"name": "用材林", "yield_per_area": 8.0, "growth": 0.02, "carbon": 1.0},
	"protection": {"name": "防护林", "yield_per_area": 0.0, "growth": 0.05, "carbon": 2.0},
	"economic": {"name": "经济林", "yield_per_area": 4.0, "growth": 0.03, "carbon": 1.5},
}

const GAME_SPECIES: Dictionary = {
	"deer": {"name": "鹿", "price": 8000, "population": 500.0},
	"wild_boar": {"name": "野猪", "price": 5000, "population": 800.0},
	"rabbit": {"name": "野兔", "price": 800, "population": 2000.0},
}

const FISHING_CLOSED_DAYS: float = BaselineScript.PRIMARY_FISHING_CLOSED_DAYS
const FIRE_BASE_RISK: float = BaselineScript.PRIMARY_FIRE_BASE_RISK


# --- 渔业 ---

func new_fishery(money: int = 1000000, opts: Dictionary = {}) -> Dictionary:
	var stock: Dictionary = {}
	for s in FISH_SPECIES.keys():
		stock[s] = float((FISH_SPECIES[s] as Dictionary).get("population", 1000.0))
	return {
		"money": money,
		"boats": maxi(0, int(opts.get("boats", 1))),
		"aquaculture": maxf(0.0, float(opts.get("aquaculture", 0.0))),
		"stock": stock if not stock.is_empty() else {},
		"resource_ratio": 1.0,
		"closed_season": false,
		"closed_days_left": 0.0,
		"sea_safety": clampf(float(opts.get("sea_safety", 0.5)), 0.0, 1.0),
		"overfish": 0.0,
		"catch_history": [],
	}


func add_boat(fishery: Dictionary, count: int) -> Dictionary:
	fishery["boats"] = maxi(0, int(fishery.get("boats", 0)) + count)
	return {"ok": true, "boats": int(fishery["boats"])}


func start_closed_season(fishery: Dictionary, days: float = FISHING_CLOSED_DAYS) -> Dictionary:
	fishery["closed_season"] = true
	fishery["closed_days_left"] = maxf(0.0, days)
	return {"ok": true, "closed_days_left": float(fishery["closed_days_left"])}


func is_closed_season(fishery: Dictionary) -> bool:
	return bool(fishery.get("closed_season", false))


## 捕捞：休渔期违规将被罚；捕捞量受资源比例限制；过度捕捞使资源比例下降并使恢复变慢。
func catch_fish(fishery: Dictionary, species: String, amount: float, opts: Dictionary = {}, rng = null) -> Dictionary:
	if not FISH_SPECIES.has(species):
		return {"ok": false, "reason": "unknown_species"}
	if is_closed_season(fishery):
		var violation: Dictionary = closed_season_violation(fishery, amount)
		return {"ok": false, "reason": "closed_season", "violation": violation}
	var stock: Dictionary = fishery["stock"]
	var available: float = float(stock.get(species, 0.0))
	var boats: int = int(fishery.get("boats", 0))
	var capacity: float = float(boats) * 100.0
	var requested: float = minf(maxf(0.0, amount), capacity)
	var caught: float = minf(requested, available)
	stock[species] = available - caught
	fishery["stock"] = stock
	fishery["overfish"] = clampf(float(fishery.get("overfish", 0.0)) + caught / maxf(1.0, available) * 0.1, 0.0, 1.0)
	fishery["resource_ratio"] = clampf(1.0 - float(fishery["overfish"]), 0.0, 1.0)
	(fishery["catch_history"] as Array).append(caught)
	# 海难风险随安全投入下降。
	var storm: Dictionary = storm_check(fishery, opts, rng)
	return {
		"ok": true, "species": species, "caught": caught, "stock": float(stock[species]),
		"resource_ratio": float(fishery["resource_ratio"]), "storm": storm,
		"price": int((FISH_SPECIES[species] as Dictionary)["price"]),
	}


## 资源恢复：资源比例越低恢复越慢（过度捕捞后恢复变慢）。
func recover_resource(fishery: Dictionary, days: float) -> Dictionary:
	var d: float = maxf(0.0, days)
	var ratio: float = clampf(float(fishery.get("resource_ratio", 1.0)), 0.0, 1.0)
	var stock: Dictionary = fishery["stock"]
	for s in stock.keys():
		var def: Dictionary = FISH_SPECIES.get(s, {})
		var recovery: float = float(def.get("recovery", 0.01)) * ratio
		var cap: float = float(def.get("population", 1000.0))
		stock[s] = minf(cap, float(stock[s]) + cap * recovery * d / 365.0)
	fishery["stock"] = stock
	fishery["resource_ratio"] = clampf(ratio + 0.01 * ratio, 0.0, 1.0)
	return {"ok": true, "resource_ratio": float(fishery["resource_ratio"])}


## 养殖收获：不受休渔期限制，产量由养殖规模决定。
func harvest_aquaculture(fishery: Dictionary, species: String, opts: Dictionary = {}) -> Dictionary:
	if not FISH_SPECIES.has(species):
		return {"ok": false, "reason": "unknown_species"}
	var scale: float = maxf(0.0, float(fishery.get("aquaculture", 0.0)))
	var yield_amount: float = scale * clampf(float(opts.get("yield_per_scale", 20.0)), 0.0, 100.0)
	var revenue: int = int(round(yield_amount * float((FISH_SPECIES[species] as Dictionary)["price"])))
	fishery["money"] = int(fishery.get("money", 0)) + revenue
	return {"ok": true, "species": species, "yield": yield_amount, "revenue": revenue}


## 海难：按海况与安全等级判定，损失渔船。
func storm_check(fishery: Dictionary, opts: Dictionary = {}, rng = null) -> Dictionary:
	var severity: float = clampf(float(opts.get("storm_severity", 0.0)), 0.0, 1.0)
	if severity <= 0.0:
		return {"ok": true, "occurred": false, "boats_lost": 0}
	var safety: float = clampf(float(fishery.get("sea_safety", 0.5)), 0.0, 1.0)
	var risk: float = severity * (1.0 - safety) * 0.5
	var roll: float = _roll(float(opts.get("roll", -1.0)), rng)
	var occurred: bool = roll < risk
	var lost: int = 0
	if occurred:
		lost = maxi(1, int(round(float(fishery.get("boats", 0)) * severity * 0.5)))
		fishery["boats"] = maxi(0, int(fishery.get("boats", 0)) - lost)
	return {"ok": true, "occurred": occurred, "boats_lost": lost, "risk": risk}


## 休渔期违规捕捞：罚款并记录违法。
func closed_season_violation(fishery: Dictionary, amount: float) -> Dictionary:
	var fine: int = int(round(maxf(0.0, amount) * 500.0))
	fishery["money"] = int(fishery.get("money", 0)) - fine
	return {"ok": true, "fine": fine, "illegal": true, "reason": "closed_season"}


# --- 林业 ---

func new_forest(money: int = 1000000, opts: Dictionary = {}) -> Dictionary:
	return {
		"money": money,
		"forest_type": str(opts.get("forest_type", "timber")),
		"rights": false,
		"area": maxf(0.0, float(opts.get("area", 100.0))),
		"trees": maxf(0.0, float(opts.get("trees", 10000.0))),
		"wood": 0.0,
		"carbon_credits": 0.0,
		"fire_risk": FIRE_BASE_RISK,
		"history": [],
	}


func grant_forest_rights(forest: Dictionary, opts: Dictionary = {}) -> Dictionary:
	forest["rights"] = true
	forest["rights_years"] = maxf(0.0, float(opts.get("years", 30.0)))
	return {"ok": true, "rights": true, "years": float(forest["rights_years"])}


## 采伐：需林权；采伐量受林木存量限制；过度采伐提升火灾风险。
func log_trees(forest: Dictionary, amount: float, opts: Dictionary = {}) -> Dictionary:
	if not bool(forest.get("rights", false)):
		return {"ok": false, "reason": "no_rights"}
	var trees: float = float(forest.get("trees", 0.0))
	var qty: float = minf(maxf(0.0, amount), trees)
	var yield_per_tree: float = float((FOREST_TYPES.get(str(forest.get("forest_type", "timber")), {}) as Dictionary).get("yield_per_area", 8.0))
	var timber: float = qty * yield_per_tree / maxf(1.0, float(forest.get("area", 1.0)))
	forest["trees"] = trees - qty
	forest["wood"] = float(forest.get("wood", 0.0)) + timber
	var intensity: float = qty / maxf(1.0, trees)
	forest["fire_risk"] = clampf(float(forest.get("fire_risk", FIRE_BASE_RISK)) + intensity * 0.05, 0.0, 1.0)
	return {"ok": true, "logged": qty, "timber": timber, "trees": float(forest["trees"]), "fire_risk": float(forest["fire_risk"])}


func reforest(forest: Dictionary, amount: float, opts: Dictionary = {}) -> Dictionary:
	var gain: float = maxf(0.0, amount)
	forest["trees"] = float(forest.get("trees", 0.0)) + gain
	forest["fire_risk"] = clampf(float(forest.get("fire_risk", FIRE_BASE_RISK)) - 0.01, 0.0, 1.0)
	return {"ok": true, "trees": float(forest["trees"])}


## 护林：降低火灾风险。
func patrol_fire(forest: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var gain: float = clampf(float(opts.get("patrol_ratio", 0.01)), 0.0, 0.5)
	forest["fire_risk"] = clampf(float(forest.get("fire_risk", FIRE_BASE_RISK)) - gain, 0.0, 1.0)
	return {"ok": true, "fire_risk": float(forest["fire_risk"])}


## 森林火灾：按火灾风险掷骰，损失林木并计提生态修复成本。
func fire_check(forest: Dictionary, opts: Dictionary = {}, rng = null) -> Dictionary:
	var risk: float = clampf(float(forest.get("fire_risk", FIRE_BASE_RISK)) * (1.0 + float(opts.get("dryness", 0.0))), 0.0, 1.0)
	var roll: float = _roll(float(opts.get("roll", -1.0)), rng)
	var occurred: bool = roll < risk
	var lost: float = 0.0
	var restoration: int = 0
	if occurred:
		var severity: float = clampf(float(opts.get("severity", 0.5)), 0.0, 1.0)
		lost = float(forest.get("trees", 0.0)) * severity
		forest["trees"] = maxf(0.0, float(forest["trees"]) - lost)
		restoration = int(round(lost * 50.0))
		forest["fire_risk"] = maxf(0.0, risk - 0.5)
	return {"ok": true, "occurred": occurred, "lost_trees": lost, "restoration_cost": restoration, "risk": risk}


## 木材市场：卖出木材获得收入。
func timber_market(forest: Dictionary, amount: float, price: int = 500) -> Dictionary:
	var wood: float = float(forest.get("wood", 0.0))
	var qty: float = minf(maxf(0.0, amount), wood)
	var revenue: int = int(round(qty * float(maxi(0, price))))
	forest["wood"] = wood - qty
	forest["money"] = int(forest.get("money", 0)) + revenue
	return {"ok": true, "sold": qty, "revenue": revenue, "price": int(price)}


## 林业碳汇：按林分类型与面积核证碳汇并结算。
func carbon_sink(forest: Dictionary, price: int, opts: Dictionary = {}) -> Dictionary:
	var def: Dictionary = FOREST_TYPES.get(str(forest.get("forest_type", "timber")), {})
	var rate: float = float(def.get("carbon", 1.0))
	var credits: float = rate * float(forest.get("area", 0.0)) * clampf(float(opts.get("years", 1.0)), 0.0, 100.0) * 0.1
	var revenue: int = int(round(credits * float(maxi(0, price))))
	forest["carbon_credits"] = float(forest.get("carbon_credits", 0.0)) + credits
	forest["money"] = int(forest.get("money", 0)) + revenue
	return {"ok": true, "credits": credits, "revenue": revenue}


# --- 狩猎与采集 ---

func new_hunter(money: int = 100000, opts: Dictionary = {}) -> Dictionary:
	return {
		"money": money,
		"license": false,
		"gun_permit": bool(opts.get("gun_permit", false)),
		"gun_policy_allows": bool(opts.get("gun_policy_allows", true)),
		"wanted_level": 0,
		"catch": {},
	}


## 申请狩猎许可：需符合枪支政策。
func hunting_license(hunter: Dictionary, opts: Dictionary = {}) -> Dictionary:
	if not bool(hunter.get("gun_policy_allows", true)):
		return {"ok": false, "reason": "gun_policy_forbids"}
	var fee: int = maxi(0, int(opts.get("fee", 10000)))
	if int(hunter.get("money", 0)) < fee:
		return {"ok": false, "reason": "insufficient_funds"}
	hunter["money"] = int(hunter["money"]) - fee
	hunter["license"] = true
	return {"ok": true, "license": true, "fee": fee}


## 合法狩猎：需许可；在保护区狩猎或超采会伤害野生动物种群。
func hunt(hunter: Dictionary, species: String, amount: float, opts: Dictionary = {}, rng = null) -> Dictionary:
	if not GAME_SPECIES.has(species):
		return {"ok": false, "reason": "unknown_species"}
	if not bool(hunter.get("license", false)):
		return illegal_hunt(hunter, species, amount, opts, rng)
	if bool(opts.get("in_protected_area", false)):
		var violation: Dictionary = legal_consequence(hunter, "protected_area", int(round(maxf(0.0, amount) * 1000.0)))
		return {"ok": false, "reason": "protected_area", "violation": violation}
	var roll: float = _roll(float(opts.get("roll", -1.0)), rng)
	var hit_rate: float = clampf(float(opts.get("hit_rate", 0.7)), 0.0, 1.0)
	var harvested: float = amount * hit_rate if roll < hit_rate else 0.0
	var catch: Dictionary = hunter["catch"]
	catch[species] = float(catch.get(species, 0.0)) + harvested
	var revenue: int = int(round(harvested * float((GAME_SPECIES[species] as Dictionary)["price"])))
	hunter["money"] = int(hunter.get("money", 0)) + revenue
	return {"ok": true, "species": species, "harvested": harvested, "revenue": revenue, "legal": true}


## 无证狩猎：入违法处理，没收所得并提高通缉等级。
func illegal_hunt(hunter: Dictionary, species: String, amount: float, opts: Dictionary = {}, rng = null) -> Dictionary:
	var def: Dictionary = GAME_SPECIES.get(species, {})
	var unit: int = int(def.get("price", 1000))
	var base: int = int(round(maxf(0.0, amount) * float(unit)))
	var violation: Dictionary = legal_consequence(hunter, "illegal_hunting", base)
	return {"ok": true, "legal": false, "species": species, "violation": violation}


## 违法后果：罚款、通缉等级与可能的没收。
func legal_consequence(hunter: Dictionary, kind: String, base: int) -> Dictionary:
	var fine: int = maxi(0, base)
	hunter["money"] = int(hunter.get("money", 0)) - fine
	hunter["wanted_level"] = int(hunter.get("wanted_level", 0)) + 1
	return {"ok": true, "kind": kind, "fine": fine, "wanted_level": int(hunter["wanted_level"]), "illegal": true}


# --- 生态可持续 ---

func new_ecology(opts: Dictionary = {}) -> Dictionary:
	return {
		"resource_ratio": clampf(float(opts.get("resource_ratio", 1.0)), 0.0, 1.0),
		"soil_quality": clampf(float(opts.get("soil_quality", 1.0)), 0.0, 1.0),
		"erosion": 0.0,
		"restoration_needed": 0.0,
		"invasive": {},
	}


## 过度开发：资源衰退并加剧水土流失。
func over_develop(state: Dictionary, intensity: float) -> Dictionary:
	var amount: float = clampf(intensity, 0.0, 1.0)
	state["resource_ratio"] = clampf(float(state.get("resource_ratio", 1.0)) - amount * 0.1, 0.0, 1.0)
	state["erosion"] = clampf(float(state.get("erosion", 0.0)) + amount * 0.08, 0.0, 1.0)
	state["soil_quality"] = clampf(float(state.get("soil_quality", 1.0)) - amount * 0.05, 0.0, 1.0)
	state["restoration_needed"] = clampf(float(state.get("restoration_needed", 0.0)) + amount * 0.1, 0.0, 1.0)
	return {
		"ok": true, "resource_ratio": float(state["resource_ratio"]),
		"erosion": float(state["erosion"]), "soil_quality": float(state["soil_quality"]),
	}


func soil_erosion(state: Dictionary, amount: float) -> Dictionary:
	var severity: float = clampf(amount, 0.0, 1.0)
	state["erosion"] = clampf(float(state.get("erosion", 0.0)) + severity, 0.0, 1.0)
	state["soil_quality"] = clampf(float(state.get("soil_quality", 1.0)) - severity * 0.5, 0.0, 1.0)
	return {"ok": true, "erosion": float(state["erosion"]), "soil_quality": float(state["soil_quality"])}


## 生态修复：按修复需求计成本，修满后资源与土壤回升。
func restore_ecology(state: Dictionary, budget: int) -> Dictionary:
	var need: float = clampf(float(state.get("restoration_needed", 0.0)), 0.0, 1.0)
	var cost: int = int(round(need * 1000000.0))
	var paid: int = maxi(0, budget)
	var done: float = clampf(float(paid) / maxf(1.0, float(cost)), 0.0, 1.0) if cost > 0 else 1.0
	state["resource_ratio"] = clampf(float(state.get("resource_ratio", 1.0)) + need * done * 0.5, 0.0, 1.0)
	state["soil_quality"] = clampf(float(state.get("soil_quality", 1.0)) + need * done * 0.5, 0.0, 1.0)
	state["erosion"] = clampf(float(state.get("erosion", 0.0)) - need * done, 0.0, 1.0)
	state["restoration_needed"] = maxf(0.0, need - need * done)
	return {"ok": true, "cost": cost, "paid": paid, "restoration_done": done, "restoration_needed": float(state["restoration_needed"])}


## 外来物种入侵：降低本地资源比例并造成持续损失。
func invasive_species(state: Dictionary, species: String, severity: float) -> Dictionary:
	var amount: float = clampf(severity, 0.0, 1.0)
	var invasive: Dictionary = state["invasive"]
	invasive[species] = clampf(float(invasive.get(species, 0.0)) + amount, 0.0, 1.0)
	state["resource_ratio"] = clampf(float(state.get("resource_ratio", 1.0)) - amount * 0.05, 0.0, 1.0)
	return {"ok": true, "species": species, "level": float(invasive[species]), "resource_ratio": float(state["resource_ratio"])}


# --- 边界情况 ---

## 极端天气：按强度减产。
func extreme_weather(state: Dictionary, severity: float) -> Dictionary:
	var amount: float = clampf(severity, 0.0, 1.0)
	var loss: float = amount * 0.5
	state["weather_loss"] = loss
	return {"ok": true, "yield_loss_ratio": loss, "severity": amount}


## 偷猎与走私：获取非法收益，但提升违法风险并伤害野生动物种群。
func poaching_smuggling(state: Dictionary, species: String, amount: float, opts: Dictionary = {}) -> Dictionary:
	var qty: float = maxf(0.0, amount)
	var price: int = int((GAME_SPECIES.get(species, {}) as Dictionary).get("price", 1000))
	var revenue: int = int(round(qty * float(price) * clampf(float(opts.get("black_market_mult", 2.0)), 1.0, 5.0)))
	var detection: float = clampf(float(opts.get("detection_chance", 0.3)), 0.0, 1.0)
	var roll: float = _roll(float(opts.get("roll", -1.0)), null)
	state["illegal_profit"] = int(state.get("illegal_profit", 0)) + revenue
	state["wanted_level"] = int(state.get("wanted_level", 0)) + (1 if roll < detection else 0)
	return {
		"ok": true, "species": species, "revenue": revenue, "detected": roll < detection,
		"wanted_level": int(state.get("wanted_level", 0)),
	}


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
