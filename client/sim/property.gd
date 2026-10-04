class_name PropertySystem
extends RefCounted
## 完整房产系统（R16、R49；design D9）。
##
## 职责：
##   - 房产属性：地段、面积、户型、学区、物业、产权年限；
##   - 流程：看房→贷款（首付/利率/年限）→过户（契税）→装修→自住或出租→出售→拆迁；
##   - 房价/租金联动利率、供需与政策（限购/限贷）；
##   - 持有结算：按月扣贷款本息、物业、维修，按月收租金，按年折旧；
##   - 边界：断供累计触发法拍、房东违约、拆迁补偿。
##
## 约定：所有金额为最小货币单位整数，经 EconomySystem 统一结算，货币守恒由其保证。

const EconomyFieldDebt: String = "debt"

const DOWN_PAYMENT_RATIO: float = 0.3
const MORTGAGE_RATE_ANNUAL: float = 0.045
const DEFAULT_TERM_YEARS: int = 30
const DEED_TAX_RATE: float = 0.015
const MAINTENANCE_RATE_ANNUAL: float = 0.005
const DEPRECIATION_RATE_ANNUAL: float = 0.02
const RENT_YIELD_ANNUAL: float = 0.02
const FORECLOSE_ARREARS_MONTHS: int = 3
const PRICE_FLOOR_RATIO: float = 0.5
const PRICE_CEIL_RATIO: float = 3.0

const PROP_REQUIRED: Array = ["id", "name", "city", "district", "area_sqm", "base_price"]

## 政策（限购/限贷），可由远程覆盖。
var policy: Dictionary = {
	"limit_buy": 0,              # 0 表示不限购
	"max_loans": 1,             # 最多贷款套数
	"min_down_ratio_first": DOWN_PAYMENT_RATIO,
	"min_down_ratio_second": 0.5,
}


func set_policy(p: Dictionary) -> void:
	for k in p.keys():
		policy[k] = p[k]


func make_property(spec: Dictionary) -> Dictionary:
	for key in PROP_REQUIRED:
		if not spec.has(key):
			return {}
	var prop: Dictionary = {
		"kind": "property",
		"id": str(spec["id"]),
		"name": str(spec["name"]),
		"city": str(spec["city"]),
		"district": str(spec["district"]),
		"area_sqm": float(spec["area_sqm"]),
		"layout": str(spec.get("layout", "2室1厅")),
		"school_district": bool(spec.get("school_district", false)),
		"years_remaining": int(spec.get("years_remaining", 70)),
		"base_price": maxi(0, int(spec["base_price"])),
		"property_fee_month": maxi(0, int(spec.get("property_fee_month", 0))),
		"monthly_rent": maxi(0, int(spec.get("monthly_rent", 0))),
		"renovation": int(spec.get("renovation", 0)),
		"age_years": float(spec.get("age_years", 0.0)),
		"owner": str(spec.get("owner", "")),
		"owned_day": int(spec.get("owned_day", -1)),
		"rented": false,
		"mortgage": {},
		"arrears_months": 0,
		"stalled": bool(spec.get("stalled", false)),  # 烂尾楼
	}
	return prop


func view(prop: Dictionary) -> Dictionary:
	return {
		"id": prop.get("id", ""),
		"name": prop.get("name", ""),
		"city": prop.get("city", ""),
		"district": prop.get("district", ""),
		"area_sqm": prop.get("area_sqm", 0.0),
		"layout": prop.get("layout", ""),
		"school_district": prop.get("school_district", false),
		"years_remaining": prop.get("years_remaining", 0),
		"monthly_rent": prop.get("monthly_rent", 0),
		"renovation": prop.get("renovation", 0),
		"stalled": prop.get("stalled", false),
	}


# --- 定价 ---

## 市场估值：基准价 × 供需 × 政策 × 利率因子 × 折旧，并 clamp 到有界区间。
## opts: supply(默认1)、policy_factor(默认1)、rate(年利率)、base_rate(默认0.03)、renovation_factor。
func market_value(prop: Dictionary, opts: Dictionary = {}) -> int:
	var base: float = float(prop.get("base_price", 0))
	var supply: float = float(opts.get("supply", 1.0))
	var pol: float = float(opts.get("policy_factor", 1.0))
	var rate: float = float(opts.get("rate", MORTGAGE_RATE_ANNUAL))
	var base_rate: float = float(opts.get("base_rate", 0.03))
	var rate_factor: float = clampf(1.0 - (rate - base_rate) * 3.0, 0.7, 1.3)
	var reno: float = 1.0 + float(prop.get("renovation", 0)) * 0.05
	var depreciation: float = maxf(0.3, 1.0 - DEPRECIATION_RATE_ANNUAL * float(prop.get("age_years", 0.0)))
	var value: float = base * supply * pol * rate_factor * reno * depreciation
	var floor_v: float = base * PRICE_FLOOR_RATIO
	var ceil_v: float = base * PRICE_CEIL_RATIO
	return maxi(0, int(round(clampf(value, floor_v, ceil_v))))


## 默认月租（按收益率估算）。
func estimated_monthly_rent(prop: Dictionary) -> int:
	if int(prop.get("monthly_rent", 0)) > 0:
		return int(prop["monthly_rent"])
	return maxi(0, int(round(float(prop.get("base_price", 0)) * RENT_YIELD_ANNUAL / 12.0)))


## 等额本息月供。
func mortgage_payment(principal: int, annual_rate: float = MORTGAGE_RATE_ANNUAL, years: int = DEFAULT_TERM_YEARS) -> int:
	if principal <= 0:
		return 0
	var n: int = maxi(1, years * 12)
	var r: float = annual_rate / 12.0
	if absf(r) < 1e-12:
		return int(round(float(principal) / float(n)))
	var m: float = float(principal) * r / (1.0 - pow(1.0 + r, -float(n)))
	return int(round(m))


func owned_properties(player: Dictionary) -> Array:
	var out: Array = []
	for a in player.get("assets", []):
		if a is Dictionary and str(a.get("kind", "")) == "property":
			out.append(a)
	return out


func mortgage_count(player: Dictionary) -> int:
	var n: int = 0
	for p in owned_properties(player):
		if not (p.get("mortgage", {}) as Dictionary).is_empty():
			n += 1
	return n


# --- 交易流程 ---

## 购买：首付 + 契税扣现，余款形成房贷（信用创造增加货币总量）。返回交易摘要。
func purchase(player: Dictionary, economy, account: String, prop: Dictionary, day: int = 0, opts: Dictionary = {}) -> Dictionary:
	if prop.is_empty() or bool(prop.get("stalled", false)):
		return {"ok": false, "reason": "unavailable"}
	var owned: Array = owned_properties(player)
	var limit: int = int(opts.get("limit_buy", policy.get("limit_buy", 0)))
	if limit > 0 and owned.size() >= limit:
		return {"ok": false, "reason": "purchase_restricted"}
	var price: int = market_value(prop, opts)
	var is_first: bool = owned.is_empty()
	var max_loans: int = int(opts.get("max_loans", policy.get("max_loans", 1)))
	var take_loan: bool = economy != null and mortgage_count(player) < max_loans
	var down_ratio: float = float(policy.get("min_down_ratio_first", DOWN_PAYMENT_RATIO)) if is_first \
		else float(policy.get("min_down_ratio_second", 0.5))
	down_ratio = clampf(float(opts.get("down_ratio", down_ratio)), 0.0, 1.0)
	var down: int = int(round(float(price) * down_ratio))
	var principal: int = price - down if take_loan else 0
	if not take_loan:
		down = price
	var deed_tax: int = int(round(float(price) * DEED_TAX_RATE))
	var cash_due: int = down + deed_tax
	if economy == null:
		return {"ok": false, "reason": "no_economy"}
	if economy.cash(account) < cash_due:
		return {"ok": false, "reason": "insufficient_funds", "cash_due": cash_due}
	economy.add_money(account, -down, "property:down")
	economy.add_money(account, -deed_tax, "property:deed_tax")
	if principal > 0:
		economy.add_money(account, principal, "property:mortgage_cash")
		economy.add_money(account, principal, "property:mortgage_debt", EconomyFieldDebt)
		prop["mortgage"] = {
			"principal": principal,
			"remaining": principal,
			"annual_rate": float(opts.get("rate", MORTGAGE_RATE_ANNUAL)),
			"term_years": int(opts.get("term_years", DEFAULT_TERM_YEARS)),
			"months_paid": 0,
			"monthly_payment": mortgage_payment(principal, float(opts.get("rate", MORTGAGE_RATE_ANNUAL)), int(opts.get("term_years", DEFAULT_TERM_YEARS))),
		}
	prop["owner"] = account
	prop["owned_day"] = day
	prop["arrears_months"] = 0
	player["assets"] = player.get("assets", [])
	player["assets"].append(prop)
	return {
		"ok": true, "price": price, "down": down, "deed_tax": deed_tax,
		"principal": principal,
		"monthly_payment": int((prop.get("mortgage", {}) as Dictionary).get("monthly_payment", 0)),
	}


## 装修：提升估值因子。
func renovate(player: Dictionary, economy, account: String, prop: Dictionary, level: int = 1, unit_cost: int = 100000) -> Dictionary:
	if not owned_properties(player).has(prop):
		return {"ok": false, "reason": "not_owned"}
	var cost: int = maxi(0, level) * unit_cost
	if economy != null and economy.cash(account) < cost:
		return {"ok": false, "reason": "insufficient_funds", "cost": cost}
	if economy != null:
		economy.add_money(account, -cost, "property:renovate")
	prop["renovation"] = int(prop.get("renovation", 0)) + maxi(0, level)
	return {"ok": true, "cost": cost, "renovation": prop["renovation"]}


## 出租/收租开关；设定月租。
func set_rent(prop: Dictionary, monthly_rent: int, rented: bool = true) -> void:
	prop["monthly_rent"] = maxi(0, monthly_rent)
	prop["rented"] = rented


## 出售：按估值成交，清偿剩余房贷后净收入入账；房产移出资产。
func sell(player: Dictionary, economy, account: String, prop: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var assets: Array = player.get("assets", [])
	var idx: int = assets.find(prop)
	if idx < 0:
		return {"ok": false, "reason": "not_owned"}
	var price: int = market_value(prop, opts)
	var mortgage: Dictionary = prop.get("mortgage", {})
	var payoff: int = int(mortgage.get("remaining", 0)) if not mortgage.is_empty() else 0
	var net: int = price - payoff
	assets.remove_at(idx)
	if economy != null:
		if net >= 0:
			economy.add_money(account, net, "property:sell")
		else:
			economy.add_money(account, net, "property:sell")
		if payoff > 0:
			economy.add_money(account, -payoff, "property:payoff", EconomyFieldDebt)
	prop["owner"] = ""
	prop["mortgage"] = {}
	return {"ok": true, "price": price, "payoff": payoff, "net": net}


## 拆迁：按补偿收回房产。
func demolish(player: Dictionary, economy, account: String, prop: Dictionary, compensation: int) -> Dictionary:
	var assets: Array = player.get("assets", [])
	var idx: int = assets.find(prop)
	if idx < 0:
		return {"ok": false, "reason": "not_owned"}
	assets.remove_at(idx)
	if economy != null and compensation > 0:
		economy.add_money(account, compensation, "property:demolition")
	prop["owner"] = ""
	return {"ok": true, "compensation": maxi(0, compensation)}


# --- 持有结算 ---

## 按月结算：贷款本息、物业、维修、租金、折旧与断供法拍。返回摘要。
func monthly_settle(player: Dictionary, economy, account: String) -> Dictionary:
	var assets: Array = player.get("assets", [])
	var payment_total: int = 0
	var fee_total: int = 0
	var rent_total: int = 0
	var foreclosed: Array = []
	var i: int = 0
	while i < assets.size():
		var prop: Dictionary = assets[i]
		if str(prop.get("kind", "")) != "property":
			i += 1
			continue
		prop["age_years"] = float(prop.get("age_years", 0.0)) + 1.0 / 12.0
		# 计算本期应还本息（不预先摊销，只有实际还款才摊销）
		var payment: int = 0
		var principal_part: int = 0
		var mortgage: Dictionary = prop.get("mortgage", {})
		if not mortgage.is_empty() and int(mortgage.get("remaining", 0)) > 0:
			var r: float = float(mortgage.get("annual_rate", MORTGAGE_RATE_ANNUAL)) / 12.0
			var remaining: int = int(mortgage["remaining"])
			var interest: int = int(round(float(remaining) * r))
			var due_payment: int = int(mortgage.get("monthly_payment", 0))
			principal_part = mini(maxi(0, due_payment - interest), remaining)
			payment = interest + principal_part
		var fee: int = int(prop.get("property_fee_month", 0)) + int(round(float(market_value(prop)) * MAINTENANCE_RATE_ANNUAL / 12.0))
		var rent: int = estimated_monthly_rent(prop) if bool(prop.get("rented", false)) else 0
		var net_due: int = payment + fee - rent
		if net_due > 0 and economy != null and economy.cash(account) < net_due:
			prop["arrears_months"] = int(prop.get("arrears_months", 0)) + 1
			if int(prop["arrears_months"]) >= FORECLOSE_ARREARS_MONTHS:
				var rec: Dictionary = _foreclose(assets, i, prop)
				if economy != null and int(rec.get("debt", 0)) > 0:
					economy.add_money(account, -int(rec["debt"]), "property:foreclose", EconomyFieldDebt)
				foreclosed.append(rec)
				continue
			i += 1
			continue
		# 正常还款
		if economy != null:
			economy.add_money(account, -net_due, "property:settle")
			if principal_part > 0:
				economy.add_money(account, -principal_part, "property:mortgage_principal", EconomyFieldDebt)
		if principal_part > 0:
			mortgage["remaining"] = int(mortgage["remaining"]) - principal_part
			mortgage["months_paid"] = int(mortgage.get("months_paid", 0)) + 1
			if int(mortgage["remaining"]) <= 0:
				mortgage["remaining"] = 0
				prop["mortgage"] = {}
		payment_total += payment
		fee_total += fee
		rent_total += rent
		prop["arrears_months"] = 0
		i += 1
	return {
		"payment": payment_total, "fee": fee_total, "rent": rent_total,
		"foreclosed": foreclosed,
	}


## 断供法拍：清偿剩余债务并从资产移除。
func _foreclose(assets: Array, idx: int, prop: Dictionary) -> Dictionary:
	var mortgage: Dictionary = prop.get("mortgage", {})
	var debt: int = int(mortgage.get("remaining", 0)) if not mortgage.is_empty() else 0
	if idx >= 0 and idx < assets.size():
		assets.remove_at(idx)
	prop["owner"] = ""
	prop["mortgage"] = {}
	return {"id": prop.get("id", ""), "debt": debt}
