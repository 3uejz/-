class_name ItemSystem
extends RefCounted
## 物品目录、背包与物权（R16、R49；design D9）。
##
## 职责：
##   - 统一物品 schema：类别、品质、耐久、保质期、价格、保值率、获取途径、重量、占用；
##   - 目录无种类上限：register 任一条目；背包按类别归档并受格数与重量上限约束；
##   - 物权形态：拥有/租用/借贷/典当/抵押，支持赠送、遗失、损坏、继承；
##   - 使用食品/药品应用效果并移除；日结算移除过期物品并提示；
##   - 购买时经统一资金入口 EconomySystem 结算，货币守恒由 EconomySystem 保证。
##
## 设计取舍：
##   - 物品定义（ItemDef）为只读字典，运行期由内容包注册；实例（instance）为背包条目；
##   - 价格为最小货币单位整数（BaselineGenerated.MONEY_MINOR_SCALE），基准价可接 MarketSystem；
##   - 所有金额变动走 EconomySystem.add_money/transfer，本模块不直接改账户。

const BaselineScript = preload("res://sim/baseline.gd")

## 品质由低到高。
const RARITY_ORDER: Array = ["common", "fine", "rare", "legendary"]

## 物品类别（可随内容包扩展，不设上限）。
const CATEGORIES: Array = [
	"food", "daily", "clothing", "electronics", "appliance", "furniture",
	"tool", "book", "medicine", "luxury", "vehicle", "collectible",
]

## 物权形态。
const OWNERSHIP_FORMS: Array = ["own", "rent", "loan", "pawn", "mortgage"]

## 定义必填字段。
const DEF_REQUIRED: Array = ["id", "name", "category", "base_price"]

## 定义默认值。
const DEF_DEFAULTS: Dictionary = {
	"rarity": "common",
	"max_durability": 0,
	"shelf_life_days": 0,
	"value_retention": 0.9,
	"weight": 0.1,
	"size": 1,
	"stackable": true,
	"effects": {},
	"acquisition": ["buy"],
	"tags": [],
}

var _defs: Dictionary = {}          # id -> def dict
var _slots: int = 30                # 背包格数上限
var _weight_capacity: float = 50.0  # 背负重量上限（kg）


func _init(slots: int = 30, weight_capacity: float = 50.0) -> void:
	_slots = maxi(1, slots)
	_weight_capacity = maxf(0.0, weight_capacity)


# --- 目录 ---

## 注册物品定义；缺必填字段或类别非法返回 {}。
func register(def: Dictionary) -> Dictionary:
	for key in DEF_REQUIRED:
		if not def.has(key):
			return {}
	if not CATEGORIES.has(str(def["category"])):
		return {}
	var full: Dictionary = DEF_DEFAULTS.duplicate(true)
	for k in def.keys():
		full[k] = def[k]
	full["id"] = str(full["id"])
	full["category"] = str(full["category"])
	full["rarity"] = str(full["rarity"]) if RARITY_ORDER.has(str(full["rarity"])) else "common"
	full["base_price"] = float(full["base_price"])
	full["max_durability"] = int(full["max_durability"])
	full["shelf_life_days"] = int(full["shelf_life_days"])
	full["value_retention"] = clampf(float(full["value_retention"]), 0.0, 1.0)
	full["weight"] = maxf(0.0, float(full["weight"]))
	full["size"] = maxi(0, int(full["size"]))
	full["stackable"] = bool(full["stackable"])
	_defs[full["id"]] = full
	return full


func register_many(defs: Array) -> int:
	var n: int = 0
	for d in defs:
		if d is Dictionary and not register(d).is_empty():
			n += 1
	return n


func has_def(id: String) -> bool:
	return _defs.has(id)


func get_def(id: String) -> Dictionary:
	return _defs.get(id, {})


func def_count() -> int:
	return _defs.size()


func ids() -> Array:
	var out: Array = _defs.keys()
	out.sort()
	return out


func rarity_rank(id: String) -> int:
	var d: Dictionary = get_def(id)
	return RARITY_ORDER.find(str(d.get("rarity", "common")))


## 内置起步目录（内容包补齐属任务 50；此处保证可玩与测试）。
func register_starter_catalog() -> int:
	return register_many([
		{"id": "item.apple", "name": "苹果", "category": "food", "base_price": 5.0,
			"shelf_life_days": 7, "weight": 0.2, "effects": {"hunger": 20.0}},
		{"id": "item.bread", "name": "面包", "category": "food", "base_price": 8.0,
			"shelf_life_days": 3, "weight": 0.3, "effects": {"hunger": 30.0, "carbs": 5.0}},
		{"id": "item.water", "name": "瓶装水", "category": "food", "base_price": 2.0,
			"shelf_life_days": 365, "weight": 0.5, "effects": {"thirst": 30.0}},
		{"id": "item.painkiller", "name": "止痛药", "category": "medicine", "base_price": 15.0,
			"rarity": "fine", "shelf_life_days": 730, "weight": 0.05,
			"effects": {"health": 5.0, "mood": 2.0}},
		{"id": "item.tissue", "name": "抽纸", "category": "daily", "base_price": 6.0,
			"weight": 0.2},
		{"id": "item.tshirt", "name": "T恤", "category": "clothing", "base_price": 39.0,
			"max_durability": 100, "weight": 0.2, "stackable": false},
		{"id": "item.phone", "name": "手机", "category": "electronics", "base_price": 2999.0,
			"rarity": "fine", "max_durability": 100, "value_retention": 0.6,
			"weight": 0.2, "stackable": false},
		{"id": "item.fridge", "name": "冰箱", "category": "appliance", "base_price": 1999.0,
			"max_durability": 100, "value_retention": 0.5, "weight": 60.0, "size": 4,
			"stackable": false},
		{"id": "item.chair", "name": "椅子", "category": "furniture", "base_price": 199.0,
			"max_durability": 100, "value_retention": 0.4, "weight": 6.0, "size": 2,
			"stackable": false},
		{"id": "item.hammer", "name": "锤子", "category": "tool", "base_price": 45.0,
			"max_durability": 100, "weight": 0.8, "stackable": false},
		{"id": "item.novel", "name": "小说", "category": "book", "base_price": 45.0,
			"weight": 0.4, "effects": {"meaning": 3.0, "mood": 2.0}},
		{"id": "item.watch", "name": "名表", "category": "luxury", "base_price": 50000.0,
			"rarity": "rare", "value_retention": 0.8, "weight": 0.1, "stackable": false},
		{"id": "item.stamp", "name": "老邮票", "category": "collectible", "base_price": 800.0,
			"rarity": "rare", "value_retention": 0.95, "weight": 0.01, "stackable": false},
		{"id": "item.bicycle", "name": "自行车", "category": "vehicle", "base_price": 500.0,
			"max_durability": 100, "value_retention": 0.4, "weight": 15.0, "size": 6,
			"stackable": false},
		{"id": "item.car", "name": "汽车", "category": "vehicle", "base_price": 120000.0,
			"rarity": "fine", "max_durability": 100, "value_retention": 0.5,
			"weight": 1500.0, "size": 20, "stackable": false},
	])


# --- 定价 ---

## 单位价格（最小货币单位）。condition ∈ 0..1，用于二手折价；market 为空则用基准价。
func price_minor(id: String, market = null, season: String = "", condition: float = 1.0) -> int:
	var d: Dictionary = get_def(id)
	if d.is_empty():
		return 0
	var base: float = float(d["base_price"])
	if market != null and market.has_method("has_good") and market.has_good(id):
		base = market.price(id, season)
	return maxi(0, int(round(base * float(BaselineScript.MONEY_MINOR_SCALE) * clampf(condition, 0.0, 1.0))))


## 实例现值（最小货币单位，含按年保值与耐久折价），不含数量。
func instance_value_minor(inst: Dictionary, day: int, market = null, season: String = "") -> int:
	var id: String = str(inst.get("def_id", ""))
	var d: Dictionary = get_def(id)
	if d.is_empty():
		return 0
	var years: float = maxf(0.0, float(day - int(inst.get("acquired_day", day))) / 365.0)
	var retention: float = pow(float(d["value_retention"]), years)
	var dur: float = durability_ratio(inst)
	return maxi(0, int(round(price_minor(id, market, season, 1.0) * retention * dur)))


func durability_ratio(inst: Dictionary) -> float:
	var d: Dictionary = get_def(str(inst.get("def_id", "")))
	var mx: int = int(d.get("max_durability", 0))
	if mx <= 0:
		return 1.0
	return clampf(float(inst.get("durability", mx)) / float(mx), 0.0, 1.0)


## 购买：经 EconomySystem 从 account 转账给 seller 后入包。economy 为空则离线入包。
func buy(player: Dictionary, economy, account: String, def_id: String,
		qty: int = 1, market = null, season: String = "", seller: String = "market") -> Dictionary:
	if get_def(def_id).is_empty():
		return {"ok": false, "reason": "unknown_def", "cost_minor": 0}
	qty = maxi(1, qty)
	if not can_add(player, def_id, qty):
		return {"ok": false, "reason": "over_capacity", "cost_minor": 0}
	var cost: int = price_minor(def_id, market, season, 1.0) * qty
	if economy == null:
		add(player, def_id, qty)
		return {"ok": true, "cost_minor": cost, "offline": true, "id": def_id, "quantity": qty}
	if economy.cash(account) < cost:
		return {"ok": false, "reason": "insufficient_funds", "cost_minor": cost}
	if not economy.transfer(account, seller, cost, "buy:" + def_id):
		return {"ok": false, "reason": "payment_failed", "cost_minor": cost}
	add(player, def_id, qty)
	return {"ok": true, "cost_minor": cost, "id": def_id, "quantity": qty}


## 出售：按二手折价入账（money 从 buyer 转来），先扣物再收款。
func sell(player: Dictionary, economy, account: String, def_id: String, qty: int = 1,
		market = null, season: String = "", buyer: String = "market", condition: float = 0.6) -> Dictionary:
	qty = maxi(1, qty)
	if count(player, def_id) < qty:
		return {"ok": false, "reason": "not_owned", "proceeds_minor": 0}
	var unit: int = price_minor(def_id, market, season, clampf(condition, 0.0, 1.0))
	var proceeds: int = unit * qty
	remove(player, def_id, qty)
	if economy != null:
		economy.transfer(buyer, account, proceeds, "sell:" + def_id)
	return {"ok": true, "proceeds_minor": proceeds}


# --- 实例 ---

## 创建物品实例。opts: day, quantity, ownership, durability。
func make_instance(def_id: String, opts: Dictionary = {}) -> Dictionary:
	var d: Dictionary = get_def(def_id)
	if d.is_empty():
		return {}
	var day: int = int(opts.get("day", 0))
	var qty: int = maxi(1, int(opts.get("quantity", 1)))
	var shelf: int = int(d["shelf_life_days"])
	var max_dur: int = int(d["max_durability"])
	return {
		"def_id": def_id,
		"quantity": qty,
		"durability": int(opts.get("durability", max_dur)),
		"acquired_day": day,
		"expire_day": (day + shelf) if shelf > 0 else 0,
		"ownership": str(opts.get("ownership", "own")),
		"flags": [],
	}


func _inv(player: Dictionary) -> Array:
	if not player.has("inventory") or typeof(player["inventory"]) != TYPE_ARRAY:
		player["inventory"] = []
	return player["inventory"]


func used_slots(player: Dictionary) -> int:
	var total: int = 0
	for inst in _inv(player):
		var d: Dictionary = get_def(str(inst.get("def_id", "")))
		total += int(d.get("size", 0)) * int(inst.get("quantity", 0))
	return total


func used_weight(player: Dictionary) -> float:
	var total: float = 0.0
	for inst in _inv(player):
		var d: Dictionary = get_def(str(inst.get("def_id", "")))
		total += float(d.get("weight", 0.0)) * float(inst.get("quantity", 0))
	return total


func capacity_slots() -> int:
	return _slots


func capacity_weight() -> float:
	return _weight_capacity


func count(player: Dictionary, def_id: String) -> int:
	var total: int = 0
	for inst in _inv(player):
		if str(inst.get("def_id", "")) == def_id:
			total += int(inst.get("quantity", 0))
	return total


func can_add(player: Dictionary, def_id: String, qty: int = 1) -> bool:
	var d: Dictionary = get_def(def_id)
	if d.is_empty() or qty <= 0:
		return false
	var add_slots: int = int(d.get("size", 0)) * qty
	var add_weight: float = float(d.get("weight", 0.0)) * float(qty)
	if used_slots(player) + add_slots > _slots:
		return false
	if used_weight(player) + add_weight > _weight_capacity:
		return false
	return true


## 入包。返回 {ok, id, added, reason}。可堆叠则并入同类实例（取较早过期日）。
func add(player: Dictionary, def_id: String, qty: int = 1, opts: Dictionary = {}) -> Dictionary:
	var d: Dictionary = get_def(def_id)
	if d.is_empty():
		return {"ok": false, "reason": "unknown_def", "added": 0}
	qty = maxi(0, qty)
	if qty == 0:
		return {"ok": true, "id": def_id, "added": 0}
	if not can_add(player, def_id, qty):
		return {"ok": false, "reason": "over_capacity", "added": 0}
	var inv: Array = _inv(player)
	var ownership: String = str(opts.get("ownership", "own"))
	if bool(d["stackable"]):
		for inst in inv:
			if (str(inst.get("def_id", "")) == def_id
					and str(inst.get("ownership", "own")) == ownership):
				inst["quantity"] = int(inst.get("quantity", 0)) + qty
				var exp: int = int(opts.get("expire_day", 0))
				if exp > 0:
					var cur: int = int(inst.get("expire_day", 0))
					inst["expire_day"] = exp if cur == 0 else mini(cur, exp)
				return {"ok": true, "id": def_id, "added": qty, "merged": true}
		var stacked: Dictionary = make_instance(def_id, opts)
		stacked["quantity"] = qty
		stacked["ownership"] = ownership
		inv.append(stacked)
		return {"ok": true, "id": def_id, "added": qty, "merged": false}
	for _i in qty:
		var one_opts: Dictionary = opts.duplicate(true)
		one_opts["quantity"] = 1
		one_opts["ownership"] = ownership
		inv.append(make_instance(def_id, one_opts))
	return {"ok": true, "id": def_id, "added": qty, "merged": false}


## 出包：按实例顺序扣减，返回实际移除数量。
func remove(player: Dictionary, def_id: String, qty: int = 1) -> int:
	qty = maxi(0, qty)
	var inv: Array = _inv(player)
	var remaining: int = qty
	var i: int = 0
	while i < inv.size() and remaining > 0:
		var inst: Dictionary = inv[i]
		if str(inst.get("def_id", "")) == def_id:
			var have: int = int(inst.get("quantity", 0))
			var take: int = mini(have, remaining)
			remaining -= take
			if take >= have:
				inv.remove_at(i)
				continue
			inst["quantity"] = have - take
		i += 1
	return qty - remaining


## 使用食品/药品：应用效果并消耗 1 个。返回 {ok, effects, applied}。
func use(player: Dictionary, def_id: String) -> Dictionary:
	var d: Dictionary = get_def(def_id)
	if d.is_empty():
		return {"ok": false, "reason": "unknown_def"}
	if count(player, def_id) <= 0:
		return {"ok": false, "reason": "not_owned"}
	var effects: Dictionary = d.get("effects", {})
	remove(player, def_id, 1)
	var applied: Dictionary = apply_effects(player, effects)
	return {"ok": true, "id": def_id, "effects": effects, "applied": applied}


## 应用效果字典到 player.attrs；未知键忽略。返回实际应用的键值。
func apply_effects(player: Dictionary, effects: Dictionary) -> Dictionary:
	var attrs: Dictionary = player.get("attrs", {})
	var applied: Dictionary = {}
	for key in effects.keys():
		var delta: float = float(effects[key])
		var groups: Array = ["physiological", "nutrition", "psychological", "ability"]
		var hit: bool = false
		for g in groups:
			if attrs.has(g) and attrs[g] is Dictionary and attrs[g].has(key):
				var before: float = float(attrs[g][key])
				attrs[g][key] = clampf(before + delta, 0.0, 100.0)
				applied[key] = float(attrs[g][key]) - before
				hit = true
				break
		if not hit and key.contains("."):
			applied[key] = delta  # 显式路径暂存，交由上层解析
	return applied


# --- 耐久、损耗、遗失与继承 ---

## 减少耐久（如磨损/损坏）；归零移除 1 个。返回剩余耐久。
func damage(player: Dictionary, def_id: String, amount: int = 1) -> int:
	var inv: Array = _inv(player)
	for inst in inv:
		if str(inst.get("def_id", "")) == def_id:
			var mx: int = int(get_def(def_id).get("max_durability", 0))
			if mx <= 0:
				return 0
			var left: int = maxi(0, int(inst.get("durability", mx)) - maxi(0, amount))
			if left <= 0:
				remove(player, def_id, 1)
				return 0
			inst["durability"] = left
			return left
	return 0


## 维修恢复耐久（不超过上限）。
func repair(player: Dictionary, def_id: String, amount: int = 1000) -> int:
	for inst in _inv(player):
		if str(inst.get("def_id", "")) == def_id:
			var mx: int = int(get_def(def_id).get("max_durability", 0))
			if mx <= 0:
				return 0
			inst["durability"] = mini(mx, int(inst.get("durability", 0)) + maxi(0, amount))
			return int(inst["durability"])
	return 0


## 遗失/失窃/损坏：标记并移除，返回记录。
func lose(player: Dictionary, def_id: String, qty: int = 1, reason: String = "lost") -> Dictionary:
	var removed: int = remove(player, def_id, qty)
	return {"id": def_id, "removed": removed, "reason": reason}


## 赠送/交付：从 from 转移到 to，返回转移数量。
func give(from_player: Dictionary, to_player: Dictionary, def_id: String, qty: int = 1) -> int:
	var moved: int = remove(from_player, def_id, qty)
	if moved <= 0:
		return 0
	var r: Dictionary = add(to_player, def_id, moved)
	if int(r.get("added", 0)) < moved:
		# 目标超容，回退未入包部分
		add(from_player, def_id, moved - int(r.get("added", 0)))
		return int(r.get("added", 0))
	return moved


## 继承：把 deceased 的全部物品转给 heir（超容部分留原地并返回未转移清单）。
func inherit_all(deceased: Dictionary, heir: Dictionary) -> Array:
	var leftover: Array = []
	for inst in _inv(deceased).duplicate(true):
		var id: String = str(inst.get("def_id", ""))
		var qty: int = int(inst.get("quantity", 0))
		var r: Dictionary = add(heir, id, qty)
		var moved: int = int(r.get("added", 0))
		if moved < qty:
			leftover.append({"id": id, "amount": qty - moved})
		if moved > 0:
			remove(deceased, id, moved)
	return leftover


# --- 物权 ---

## 设置某物品的物权形态（own/rent/loan/pawn/mortgage）。
func set_ownership(player: Dictionary, def_id: String, form: String) -> bool:
	if not OWNERSHIP_FORMS.has(form):
		return false
	for inst in _inv(player):
		if str(inst.get("def_id", "")) == def_id:
			inst["ownership"] = form
			return true
	return false


func ownership_of(player: Dictionary, def_id: String) -> String:
	for inst in _inv(player):
		if str(inst.get("def_id", "")) == def_id:
			return str(inst.get("ownership", "own"))
	return ""


## 典当：物品转为 pawn，取得当金（由 EconomySystem 入账）。
func pawn(player: Dictionary, economy, account: String, def_id: String, amount: int, day: int = 0) -> bool:
	if economy == null or count(player, def_id) <= 0:
		return false
	if not set_ownership(player, def_id, "pawn"):
		return false
	economy.add_money(account, maxi(0, amount), "pawn:" + def_id)
	return true


## 赎回：偿还当金，恢复所有权。
func redeem(player: Dictionary, economy, account: String, def_id: String, amount: int) -> bool:
	if economy == null or ownership_of(player, def_id) != "pawn":
		return false
	if economy.cash(account) < amount:
		return false
	economy.add_money(account, -amount, "redeem:" + def_id)
	return set_ownership(player, def_id, "own")


# --- 日结算 ---

## 每日过期结算：移除已过期物品并返回提示 [{id, name, quantity}]。
func tick_day(player: Dictionary, day: int) -> Array:
	var expired: Array = []
	var inv: Array = _inv(player)
	var i: int = 0
	while i < inv.size():
		var inst: Dictionary = inv[i]
		var exp: int = int(inst.get("expire_day", 0))
		if exp > 0 and day >= exp:
			var id: String = str(inst.get("def_id", ""))
			expired.append({
				"id": id,
				"name": str(get_def(id).get("name", id)),
				"quantity": int(inst.get("quantity", 0)),
			})
			inv.remove_at(i)
			continue
		i += 1
	return expired


func to_dict() -> Dictionary:
	return {"slots": _slots, "weight_capacity": _weight_capacity}
