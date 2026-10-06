class_name AgricultureSystem
extends RefCounted
## 农业与乡土（R66；design D22）。
##
## 覆盖：
##   - 土地承包/购买/流转/租赁并计入资产与遗产，区分用途与地力；轮作与地力恢复；
##   - 种植（粮食/经济/蔬果/药材）播种→施肥→灌溉→除草→收成，产量受土壤/气候/灾害/技能/技术影响；
##   - 养殖（家畜/家禽/水产）饲料/繁殖/疫病/市场波动；
##   - 经营与市场（自给/集市/订单农业/合作社/期货、仓储保鲜与滞销）；
##   - 乡土关系（村民/集市/合作社/土地流转/人情）；
##   - 边界：干旱/洪水/虫害/滞销、征地补偿纠纷、农村空心化、规模化与补贴。
##
## 设计取舍：
##   - 农场为纯数据 Dictionary；土地/地块/牲畜/仓储分别为数组或字典，便于存读档与 headless 测试；
##   - 收成时一次性结算产量入仓，售卖按渠道价格倍率换算，年收入在 settle_year 汇总；
##   - 随机项（繁殖/疫病/价格波动）由外部 roll/rng 注入，缺省确定化。

const CROPS: Dictionary = {
	"rice": {"name": "水稻", "use": "grain", "base_yield": 600.0, "price": 3000, "growth_days": 120.0, "water_need": 1.2, "fertility_cost": 0.15, "spoil_rate": 0.002},
	"wheat": {"name": "小麦", "use": "grain", "base_yield": 500.0, "price": 3200, "growth_days": 150.0, "water_need": 0.8, "fertility_cost": 0.10, "spoil_rate": 0.002},
	"cotton": {"name": "棉花", "use": "cash", "base_yield": 300.0, "price": 8000, "growth_days": 180.0, "water_need": 0.9, "fertility_cost": 0.18, "spoil_rate": 0.001},
	"rapeseed": {"name": "油菜", "use": "cash", "base_yield": 250.0, "price": 6000, "growth_days": 160.0, "water_need": 0.7, "fertility_cost": 0.12, "spoil_rate": 0.001},
	"vegetable": {"name": "蔬菜", "use": "vegetable", "base_yield": 2000.0, "price": 2500, "growth_days": 60.0, "water_need": 1.3, "fertility_cost": 0.20, "spoil_rate": 0.020},
	"herb": {"name": "药材", "use": "herbal", "base_yield": 200.0, "price": 20000, "growth_days": 240.0, "water_need": 0.9, "fertility_cost": 0.10, "spoil_rate": 0.005},
}

const LIVESTOCK: Dictionary = {
	"pig": {"name": "生猪", "kind": "livestock", "feed_per_day": 2.5, "breed_rate": 0.06, "disease_risk": 0.08, "market_price": 4000},
	"cattle": {"name": "肉牛", "kind": "livestock", "feed_per_day": 6.0, "breed_rate": 0.03, "disease_risk": 0.05, "market_price": 15000},
	"chicken": {"name": "肉鸡", "kind": "poultry", "feed_per_day": 0.15, "breed_rate": 0.15, "disease_risk": 0.12, "market_price": 60},
	"duck": {"name": "鸭", "kind": "poultry", "feed_per_day": 0.2, "breed_rate": 0.12, "disease_risk": 0.12, "market_price": 80},
	"fish": {"name": "鱼", "kind": "aquaculture", "feed_per_day": 0.05, "breed_rate": 0.10, "disease_risk": 0.15, "market_price": 25},
}

## 销售渠道：价格倍率（自给不自售）。
const MARKET_CHANNELS: Dictionary = {
	"self_supply": {"name": "自给", "price_mult": 0.0},
	"market": {"name": "集市", "price_mult": 1.0},
	"order": {"name": "订单农业", "price_mult": 1.15},
	"cooperative": {"name": "合作社", "price_mult": 1.08},
	"futures": {"name": "期货", "price_mult": 1.25},
}

const DISASTERS: Array = ["drought", "flood", "pest"]
const DISASTER_NAMES: Dictionary = {"drought": "干旱", "flood": "洪水", "pest": "虫害"}

const LAND_MODES: Array = ["contract", "purchase", "transfer", "lease"]
const LAND_MODE_NAMES: Dictionary = {"contract": "承包", "purchase": "购买", "transfer": "流转", "lease": "租赁"}
const LAND_USES: Array = ["grain", "cash", "vegetable", "herbal"]


# --- 数据表 ---

func crop_types() -> Array:
	return CROPS.keys()


func crop_def(key: String) -> Dictionary:
	if not CROPS.has(key):
		return {}
	return (CROPS[key] as Dictionary).duplicate(true)


func crop_price(key: String) -> int:
	if not CROPS.has(key):
		return 0
	return int((CROPS[key] as Dictionary)["price"])


func livestock_types() -> Array:
	return LIVESTOCK.keys()


func livestock_def(key: String) -> Dictionary:
	if not LIVESTOCK.has(key):
		return {}
	return (LIVESTOCK[key] as Dictionary).duplicate(true)


func _price_for(item: String) -> int:
	if CROPS.has(item):
		return int((CROPS[item] as Dictionary)["price"])
	if LIVESTOCK.has(item):
		return int((LIVESTOCK[item] as Dictionary)["market_price"])
	return 0


func _spoil_rate(item: String) -> float:
	if CROPS.has(item):
		return float((CROPS[item] as Dictionary).get("spoil_rate", 0.002))
	return 0.001


# --- 农场与土地 ---

func new_farm(money: int = 1000000, opts: Dictionary = {}) -> Dictionary:
	return {
		"money": money,
		"land": [],
		"plots": [],
		"livestock": [],
		"storage": {},
		"orders": [],
		"futures": [],
		"coop": str(opts.get("coop", "")),
		"relations": {},
		"subsidy": 0.0,
		"year_income": 0,
	}


## 取得土地。mode：承包/购买/流转/租赁；租赁不计入资产，其余计入资产价值。
func acquire_land(farm: Dictionary, area: float, use: String, mode: String, price_per_area: int, opts: Dictionary = {}) -> Dictionary:
	if not LAND_MODES.has(mode):
		return {"ok": false, "reason": "unknown_mode"}
	if not LAND_USES.has(use):
		return {"ok": false, "reason": "unknown_use"}
	var a: float = maxf(0.0, area)
	var land: Dictionary = {
		"id": str(opts.get("id", "land_%d" % (farm["land"] as Array).size())),
		"area": a, "use": use, "mode": mode,
		"fertility": clampf(float(opts.get("fertility", 0.8)), 0.1, 1.0),
		"asset_value": 0, "rent": 0,
	}
	match mode:
		"purchase":
			var val: int = int(round(a * float(price_per_area)))
			farm["money"] = int(farm["money"]) - val
			land["asset_value"] = val
		"contract":
			var cval: int = int(round(a * float(price_per_area) * 0.6))
			farm["money"] = int(farm["money"]) - cval
			land["asset_value"] = cval
		"transfer":
			var fee: int = int(round(a * float(price_per_area) * 0.1))
			farm["money"] = int(farm["money"]) - fee
			land["asset_value"] = int(round(a * float(price_per_area) * 0.7))
			land["transferred_from"] = str(opts.get("from", ""))
		"lease":
			land["rent"] = int(round(a * float(price_per_area) * 0.08))
			land["asset_value"] = 0
	(farm["land"] as Array).append(land)
	return {"ok": true, "land": land, "asset_value": land_asset_value(farm), "mode": mode}


## 土地资产价值：可用于遗产与资产统计。
func land_asset_value(farm: Dictionary) -> int:
	var total: int = 0
	for land in (farm["land"] as Array):
		total += int((land as Dictionary).get("asset_value", 0))
	return total


func improve_fertility(farm: Dictionary, land_index: int, amount: float) -> Dictionary:
	if land_index < 0 or land_index >= (farm["land"] as Array).size():
		return {"ok": false, "reason": "no_land"}
	var land: Dictionary = farm["land"][land_index]
	land["fertility"] = clampf(float(land["fertility"]) + amount, 0.1, 1.0)
	return {"ok": true, "fertility": float(land["fertility"])}


## 轮作恢复地力。
func rotate(farm: Dictionary, land_index: int) -> Dictionary:
	if land_index < 0 or land_index >= (farm["land"] as Array).size():
		return {"ok": false, "reason": "no_land"}
	var land: Dictionary = farm["land"][land_index]
	land["fertility"] = clampf(float(land["fertility"]) + 0.2, 0.1, 1.0)
	return {"ok": true, "fertility": float(land["fertility"])}


# --- 种植 ---

func plant(farm: Dictionary, land_index: int, crop_key: String, opts: Dictionary = {}) -> Dictionary:
	if land_index < 0 or land_index >= (farm["land"] as Array).size():
		return {"ok": false, "reason": "no_land"}
	if not CROPS.has(crop_key):
		return {"ok": false, "reason": "unknown_crop"}
	var crop: Dictionary = CROPS[crop_key]
	var plot: Dictionary = {
		"land_index": land_index, "crop": crop_key, "stage": "sown",
		"fertilized": false, "irrigated": false, "weeded": false,
		"growth_days": float(crop["growth_days"]), "elapsed": 0.0, "health": 1.0,
	}
	(farm["plots"] as Array).append(plot)
	return {"ok": true, "plot": plot, "land_use": str(crop["use"])}


func _plot_at(farm: Dictionary, plot_index: int) -> Dictionary:
	if plot_index < 0 or plot_index >= (farm["plots"] as Array).size():
		return {}
	return farm["plots"][plot_index]


func fertilize(farm: Dictionary, plot_index: int) -> Dictionary:
	var plot: Dictionary = _plot_at(farm, plot_index)
	if plot.is_empty():
		return {"ok": false, "reason": "no_plot"}
	plot["fertilized"] = true
	return {"ok": true, "fertilized": true}


func irrigate(farm: Dictionary, plot_index: int) -> Dictionary:
	var plot: Dictionary = _plot_at(farm, plot_index)
	if plot.is_empty():
		return {"ok": false, "reason": "no_plot"}
	plot["irrigated"] = true
	return {"ok": true, "irrigated": true}


func weed(farm: Dictionary, plot_index: int) -> Dictionary:
	var plot: Dictionary = _plot_at(farm, plot_index)
	if plot.is_empty():
		return {"ok": false, "reason": "no_plot"}
	plot["weeded"] = true
	return {"ok": true, "weeded": true}


## 推进生长；到达生长天数后转为成熟。
func grow(farm: Dictionary, days: float) -> Dictionary:
	var d: float = maxf(0.0, days)
	var matured: Array = []
	for plot in (farm["plots"] as Array):
		var p: Dictionary = plot
		p["elapsed"] = float(p.get("elapsed", 0.0)) + d
		if float(p["elapsed"]) >= float(p["growth_days"]) and str(p["stage"]) != "mature":
			p["stage"] = "mature"
			matured.append(str(p["crop"]))
	return {"ok": true, "matured": matured}


## 收成：产量受土壤/气候/灾害/技能/技术/田间管理影响，入仓并消耗地力。
## opts: climate(0.2..1.5)、disaster(0..1 损失比例)、skill(0..1)、tech(0.5..1.5)。
func harvest(farm: Dictionary, plot_index: int, opts: Dictionary = {}) -> Dictionary:
	var plot: Dictionary = _plot_at(farm, plot_index)
	if plot.is_empty():
		return {"ok": false, "reason": "no_plot"}
	var land: Dictionary = farm["land"][int(plot["land_index"])]
	var crop: Dictionary = CROPS[str(plot["crop"])]
	var soil: float = float(land["fertility"])
	var climate: float = clampf(float(opts.get("climate", 1.0)), 0.2, 1.5)
	var skill: float = clampf(float(opts.get("skill", 0.5)), 0.0, 1.0)
	var tech: float = clampf(float(opts.get("tech", 1.0)), 0.5, 1.5)
	var disaster: float = clampf(float(opts.get("disaster", 0.0)), 0.0, 1.0)
	var health: float = clampf(float(plot.get("health", 1.0)), 0.0, 1.0)
	var maturity: float = clampf(float(plot["elapsed"]) / maxf(1.0, float(plot["growth_days"])), 0.0, 1.0)
	var care: float = 1.0
	if bool(plot.get("fertilized", false)):
		care += 0.10
	if bool(plot.get("irrigated", false)):
		care += 0.08
	if bool(plot.get("weeded", false)):
		care += 0.06
	var yield_amount: float = float(crop["base_yield"]) * float(land["area"]) * soil * climate \
		* (1.0 - disaster) * (0.5 + skill) * tech * care * maturity * health
	var item: String = str(plot["crop"])
	var storage: Dictionary = farm["storage"]
	storage[item] = float(storage.get(item, 0.0)) + yield_amount
	land["fertility"] = clampf(soil - float(crop["fertility_cost"]) - (0.05 if bool(plot.get("fertilized", false)) else 0.0), 0.1, 1.0)
	(farm["plots"] as Array).remove_at(plot_index)
	return {
		"ok": true, "crop": item, "yield": yield_amount,
		"storage": float(storage[item]), "land_fertility": float(land["fertility"]),
	}


# --- 养殖 ---

func add_livestock(farm: Dictionary, animal: String, count: int) -> Dictionary:
	if not LIVESTOCK.has(animal):
		return {"ok": false, "reason": "unknown_animal"}
	var n: int = maxi(0, count)
	(farm["livestock"] as Array).append({"animal": animal, "count": n, "feed_days": 0.0, "diseased": false})
	return {"ok": true, "animal": animal, "count": n}


## 喂养：饲料不足则生长受损。
func feed_livestock(farm: Dictionary, days: float, feed_available: float) -> Dictionary:
	var d: float = maxf(0.0, days)
	var need: float = 0.0
	for rec in (farm["livestock"] as Array):
		var r: Dictionary = rec
		var def: Dictionary = LIVESTOCK[str(r["animal"])]
		need += float(def["feed_per_day"]) * float(r["count"]) * d
	var shortage: bool = feed_available < need
	for rec in (farm["livestock"] as Array):
		if shortage:
			(rec as Dictionary)["diseased"] = true
	return {"ok": true, "feed_needed": need, "shortage": shortage}


## 繁殖：按繁殖率与 roll 增加数量。
func breed_livestock(farm: Dictionary, animal: String, opts: Dictionary = {}, rng = null) -> Dictionary:
	if not LIVESTOCK.has(animal):
		return {"ok": false, "reason": "unknown_animal"}
	var def: Dictionary = LIVESTOCK[animal]
	var roll: float = _roll(float(opts.get("roll", -1.0)), rng)
	var born: int = 0
	for rec in (farm["livestock"] as Array):
		var r: Dictionary = rec
		if str(r["animal"]) == animal and roll < float(def["breed_rate"]):
			born += maxi(1, int(round(float(r["count"]) * float(def["breed_rate"]))))
			r["count"] = int(r["count"]) + born
	return {"ok": true, "animal": animal, "born": born}


## 疫病：按疫病风险损失存栏。
func livestock_disease(farm: Dictionary, animal: String, opts: Dictionary = {}, rng = null) -> Dictionary:
	if not LIVESTOCK.has(animal):
		return {"ok": false, "reason": "unknown_animal"}
	var def: Dictionary = LIVESTOCK[animal]
	var roll: float = _roll(float(opts.get("roll", -1.0)), rng)
	var lost: int = 0
	for rec in (farm["livestock"] as Array):
		var r: Dictionary = rec
		if str(r["animal"]) == animal and roll < float(def["disease_risk"]):
			var l: int = int(round(float(r["count"]) * 0.3))
			lost += l
			r["count"] = maxi(0, int(r["count"]) - l)
	return {"ok": true, "animal": animal, "lost": lost}


## 市场波动：写入市场价倍率（用于售卖时修正）。
func update_market_prices(farm: Dictionary, opts: Dictionary = {}, rng = null) -> Dictionary:
	var roll: float = _roll(float(opts.get("roll", -1.0)), rng)
	var factor: float = clampf(0.8 + roll * 0.4, 0.8, 1.2)
	if not farm.has("market_factor") or typeof(farm["market_factor"]) != TYPE_DICTIONARY:
		farm["market_factor"] = {}
	(farm["market_factor"] as Dictionary)["all"] = factor
	return {"ok": true, "factor": factor}


# --- 经营与市场 ---

## 售卖农产品或牲畜：按渠道价格倍率与市场波动换算收益。自给渠道不产生收入。
func sell(farm: Dictionary, item: String, amount: float, channel: String = "market", opts: Dictionary = {}) -> Dictionary:
	if not MARKET_CHANNELS.has(channel):
		return {"ok": false, "reason": "unknown_channel"}
	var storage: Dictionary = farm["storage"]
	var have: float = float(storage.get(item, 0.0))
	var qty: float = minf(maxf(0.0, amount), have)
	if qty <= 0.0:
		return {"ok": false, "reason": "no_stock"}
	if channel == "self_supply":
		storage[item] = have - qty
		return {"ok": true, "channel": channel, "sold": qty, "revenue": 0, "consumed": qty}
	var price: float = float(opts.get("price", _price_for(item)))
	var price_mult: float = float((MARKET_CHANNELS[channel] as Dictionary)["price_mult"])
	var market_factor: float = 1.0
	var mf: Variant = farm.get("market_factor", {})
	if mf is Dictionary:
		market_factor = float((mf as Dictionary).get("all", 1.0))
	var revenue: int = int(round(qty * price * price_mult * market_factor))
	storage[item] = have - qty
	farm["money"] = int(farm["money"]) + revenue
	farm["year_income"] = int(farm["year_income"]) + revenue
	return {"ok": true, "channel": channel, "sold": qty, "revenue": revenue, "price": price}


## 仓储保鲜：按各物保鲜率减少库存，蔬果更快腐坏。
func storage_spoil(farm: Dictionary, days: float) -> Dictionary:
	var d: float = maxf(0.0, days)
	var storage: Dictionary = farm["storage"]
	var spoiled: Dictionary = {}
	for item in storage.keys():
		var before: float = float(storage[item])
		var lost: float = before * _spoil_rate(str(item)) * d
		storage[item] = maxf(0.0, before - lost)
		if lost > 0.0:
			spoiled[str(item)] = lost
	return {"ok": true, "spoiled": spoiled}


## 滞销判定：市场价过低或供给过剩时，最多可售出的份额受限。
func unsalable(farm: Dictionary, item: String, opts: Dictionary = {}) -> Dictionary:
	var storage: Dictionary = farm["storage"]
	var have: float = float(storage.get(item, 0.0))
	var glut: float = clampf(float(opts.get("glut", 0.0)), 0.0, 1.0)
	var sellable: float = have * (1.0 - glut)
	return {"ok": true, "item": item, "sellable": sellable, "unsalable": have - sellable, "glut": glut}


## 订单农业：锁定未来以约定价交付。
func place_order(farm: Dictionary, item: String, amount: float, price: int) -> Dictionary:
	var order: Dictionary = {"item": item, "amount": maxf(0.0, amount), "price": int(price), "fulfilled": false}
	(farm["orders"] as Array).append(order)
	return {"ok": true, "order": order}


## 交付订单：从库存扣除并获取约定收入；库存不足则部分交付。
func fulfill_order(farm: Dictionary, order_index: int, opts: Dictionary = {}) -> Dictionary:
	if order_index < 0 or order_index >= (farm["orders"] as Array).size():
		return {"ok": false, "reason": "no_order"}
	var order: Dictionary = farm["orders"][order_index]
	if bool(order.get("fulfilled", false)):
		return {"ok": false, "reason": "already_fulfilled"}
	var storage: Dictionary = farm["storage"]
	var item: String = str(order["item"])
	var have: float = float(storage.get(item, 0.0))
	var qty: float = minf(float(order["amount"]), have)
	var revenue: int = int(round(qty * float(order["price"])))
	storage[item] = have - qty
	farm["money"] = int(farm["money"]) + revenue
	farm["year_income"] = int(farm["year_income"]) + revenue
	order["fulfilled"] = qty >= float(order["amount"])
	return {"ok": true, "delivered": qty, "revenue": revenue, "fulfilled": bool(order["fulfilled"])}


func join_cooperative(farm: Dictionary, name: String, opts: Dictionary = {}) -> Dictionary:
	farm["coop"] = name
	return {"ok": true, "coop": name, "price_bonus": float((MARKET_CHANNELS["cooperative"] as Dictionary)["price_mult"]) - 1.0}


## 期货建仓：锁定价格，待平仓时按市价与锁价差额结算盈亏。
func futures_contract(farm: Dictionary, item: String, amount: float, lock_price: int) -> Dictionary:
	var contract: Dictionary = {"item": item, "amount": maxf(0.0, amount), "lock_price": int(lock_price), "settled": false}
	(farm["futures"] as Array).append(contract)
	return {"ok": true, "contract": contract}


func settle_futures(farm: Dictionary, index: int, market_price: int) -> Dictionary:
	if index < 0 or index >= (farm["futures"] as Array).size():
		return {"ok": false, "reason": "no_contract"}
	var contract: Dictionary = farm["futures"][index]
	if bool(contract.get("settled", false)):
		return {"ok": false, "reason": "settled"}
	var pnl: int = int(round(float(contract["amount"]) * float(int(market_price) - int(contract["lock_price"]))))
	farm["money"] = int(farm["money"]) + pnl
	farm["year_income"] = int(farm["year_income"]) + maxi(0, pnl)
	contract["settled"] = true
	return {"ok": true, "pnl": pnl}


## 年结算：返回本年收入与期末库存，重置年度收入计数（R66.5）。
func settle_year(farm: Dictionary) -> Dictionary:
	var storage: Dictionary = farm["storage"]
	return {
		"ok": true, "income": int(farm["year_income"]),
		"inventory": storage.duplicate(true),
		"money": int(farm["money"]),
	}


func reset_year(farm: Dictionary) -> void:
	farm["year_income"] = 0


# --- 灾害与乡土边界 ---

## 灾害：干旱/洪水/虫害降低地块健康与地力。
func strike_disaster(farm: Dictionary, disaster: String, severity: float) -> Dictionary:
	if not DISASTERS.has(disaster):
		return {"ok": false, "reason": "unknown_disaster"}
	var sev: float = clampf(severity, 0.0, 1.0)
	var affected: int = 0
	for plot in (farm["plots"] as Array):
		var p: Dictionary = plot
		p["health"] = clampf(float(p.get("health", 1.0)) - sev * 0.5, 0.0, 1.0)
		if disaster == "pest":
			p["health"] = clampf(float(p["health"]) - sev * 0.2, 0.0, 1.0)
		affected += 1
	var fertility_loss: float = 0.0
	if disaster == "flood":
		fertility_loss = sev * 0.15
	elif disaster == "drought":
		fertility_loss = sev * 0.10
	for land in (farm["land"] as Array):
		(land as Dictionary)["fertility"] = clampf(float((land as Dictionary)["fertility"]) - fertility_loss, 0.1, 1.0)
	return {"ok": true, "disaster": disaster, "severity": sev, "affected": affected, "fertility_loss": fertility_loss}


## 征地补偿：补偿低于公允价值则产生纠纷（联动 D12）。
func land_requisition(farm: Dictionary, land_index: int, compensation: int, fair_value: int) -> Dictionary:
	if land_index < 0 or land_index >= (farm["land"] as Array).size():
		return {"ok": false, "reason": "no_land"}
	var fair: int = maxi(0, fair_value)
	var dispute: bool = int(compensation) < fair
	var shortfall: int = maxi(0, fair - int(compensation))
	if dispute:
		set_villager_relation(farm, "government", -20.0)
	return {"ok": true, "dispute": dispute, "compensation": int(compensation), "fair_value": fair, "shortfall": shortfall}


## 农村空心化：劳动力外流降低可用劳力，越过阈值影响生产。
func rural_hollowing(farm: Dictionary, workforce: float, outflow: float) -> Dictionary:
	var out: float = clampf(outflow, 0.0, 1.0)
	var labor: float = maxf(0.0, workforce) * (1.0 - out)
	var severity: float = clampf(out - 0.3, 0.0, 0.7)
	return {"ok": true, "labor_available": labor, "hollowing_severity": severity, "productivity_penalty": severity}


## 补贴政策：规模化经营可获额外补贴。
func apply_subsidy(farm: Dictionary, amount: int) -> Dictionary:
	var granted: int = maxi(0, amount) + int(round(land_asset_value(farm) / 100000.0)) * 1000
	farm["subsidy"] = float(farm["subsidy"]) + float(granted)
	farm["money"] = int(farm["money"]) + granted
	return {"ok": true, "subsidy": float(farm["subsidy"]), "granted": granted}


# --- 乡土关系 ---

func set_villager_relation(farm: Dictionary, villager_id: String, favor: float) -> Dictionary:
	var relations: Dictionary = farm["relations"]
	relations[villager_id] = float(relations.get(villager_id, 0.0)) + favor
	return {"ok": true, "villager": villager_id, "favor": float(relations[villager_id])}


func villager_relation(farm: Dictionary, villager_id: String) -> float:
	var relations: Dictionary = farm.get("relations", {})
	return float(relations.get(villager_id, 0.0))


## 土地流转：在村民之间转移使用权并影响人情。
func land_transfer(farm: Dictionary, land_index: int, from_id: String, to_id: String) -> Dictionary:
	if land_index < 0 or land_index >= (farm["land"] as Array).size():
		return {"ok": false, "reason": "no_land"}
	var land: Dictionary = farm["land"][land_index]
	land["mode"] = "transfer"
	land["transferred_from"] = from_id
	set_villager_relation(farm, from_id, 5.0)
	set_villager_relation(farm, to_id, 5.0)
	return {"ok": true, "land": land, "from": from_id, "to": to_id}


func _roll(forced: float, rng) -> float:
	if forced >= 0.0:
		return clampf(forced, 0.0, 1.0)
	if rng != null:
		return rng.next_float()
	return 0.0


func to_dict(farm: Dictionary) -> Dictionary:
	return farm.duplicate(true)


func from_dict(data: Dictionary) -> Dictionary:
	return data.duplicate(true)
