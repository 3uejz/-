class_name CompanySystem
extends RefCounted
## 创业经营：注册、选址、进货定价、营业客流、雇佣发薪、纳税、扩张与破产（R14；design D7）。
##
## 要点：
##   - 注册个体户/公司需校验资金与资质（R14.1）；
##   - 指令：选址、进货、定价、营业、打烊、雇佣、解雇、发薪、纳税、扩张（R14.2）；
##   - 营业时按世界时钟模拟客流，依定价与声誉生成收入（R14.3）；
##   - 库存不足停止销售并提示补货（R14.4）；
##   - 工资未按时发放降低员工忠诚并可能离职（R14.5）；
##   - 资不抵债触发破产清算（R14.6）。
##
## 设计取舍：
##   - 公司资金挂在 EconomySystem 账户 "company.<id>"，本金由业主账户转入（守恒）；
##   - 营业收入来自外部消费者，用 issue_money 注入；房租/工资等对外支出用 burn_money 回收；
##   - 库存以 {good: {qty, unit_cost}} 记录，定价存于 prices；客流为确定性公式 + 注入 rng 处理离职。

const BaselineScript = preload("res://sim/baseline.gd")
const TaxScript = preload("res://sim/tax.gd")

const KINDS: Array = ["sole_proprietor", "company"]
const MIN_CAPITAL: Dictionary = {"sole_proprietor": 100000, "company": 1000000}

const STATUS_REGISTERED: String = "registered"
const STATUS_OPEN: String = "open"
const STATUS_CLOSED: String = "closed"
const STATUS_BANKRUPT: String = "bankrupt"

const MONTH_DAYS: int = 30
const CUSTOMERS_PER_SQM: float = 0.3
const BASE_CONVERSION: float = 0.5
const REFERENCE_MARKUP: float = 1.5
const LIQUIDATION_RATIO: float = 0.5
const REPUTATION_GAIN_PER_DAY: float = 0.2
const REPUTATION_LOSS_SHORTAGE: float = 1.0
const LOYALTY_UNPAID_PENALTY: float = 8.0
const RESIGN_LOYALTY_THRESHOLD: float = 20.0
const RESIGN_CHANCE: float = 0.3


# --- 注册 ---

## 注册个体户/公司；校验类型、资金与资质。返回 {ok, reason?, company?}。
func register_company(economy, owner_account: String, spec: Dictionary) -> Dictionary:
	var kind: String = str(spec.get("kind", ""))
	if not KINDS.has(kind):
		return {"ok": false, "reason": "bad_kind"}
	var name: String = str(spec.get("name", ""))
	if name.is_empty():
		return {"ok": false, "reason": "empty_name"}
	var capital: int = int(spec.get("capital", 0))
	if capital < int(MIN_CAPITAL[kind]):
		return {"ok": false, "reason": "insufficient_capital"}
	if not economy.has_account(owner_account):
		return {"ok": false, "reason": "no_owner_account"}
	if economy.liquid(owner_account) < capital:
		return {"ok": false, "reason": "insufficient_funds"}
	var id: String = str(spec.get("id", "co.%d" % (economy.total_money() % 100000)))
	var account: String = "company." + id
	if not economy.transfer(owner_account, account, capital, "capital"):
		return {"ok": false, "reason": "transfer_failed"}
	var company: Dictionary = {
		"id": id,
		"name": name,
		"kind": kind,
		"account": account,
		"status": STATUS_REGISTERED,
		"site": {},
		"inventory": {},
		"prices": {},
		"reputation": 50.0,
		"employees": [],
		"revenue_history": [],
		"branches": 1,
		"founded_day": int(spec.get("day", 0)),
	}
	return {"ok": true, "company": company}


func choose_site(company: Dictionary, region_id: String, area_sqm: float, monthly_rent: int, opts: Dictionary = {}) -> Dictionary:
	if bool(opts.get("need_open", false)) and str(company.get("status", "")) != STATUS_OPEN:
		return {"ok": false, "reason": "not_open"}
	company["site"] = {
		"region_id": region_id,
		"area_sqm": maxf(1.0, area_sqm),
		"monthly_rent": maxi(0, monthly_rent),
	}
	return {"ok": true, "site": company["site"]}


func open_shop(company: Dictionary) -> Dictionary:
	if (company.get("site", {}) as Dictionary).is_empty():
		return {"ok": false, "reason": "no_site"}
	company["status"] = STATUS_OPEN
	return {"ok": true}


func close_shop(company: Dictionary) -> Dictionary:
	if str(company.get("status", "")) != STATUS_OPEN:
		return {"ok": false, "reason": "not_open"}
	company["status"] = STATUS_CLOSED
	return {"ok": true}


# --- 进货与定价 ---

## 进货：向供货方付款并入库。未提供供货账户时按对外采购回收货币。
func stock(company: Dictionary, economy, good_key: String, qty: int, unit_cost: int, supplier_account: String = "") -> Dictionary:
	if qty <= 0 or unit_cost < 0:
		return {"ok": false, "reason": "bad_args"}
	var cost: int = qty * unit_cost
	var account: String = str(company["account"])
	if economy.liquid(account) < cost:
		return {"ok": false, "reason": "insufficient_funds", "cost": cost}
	if not supplier_account.is_empty() and economy.has_account(supplier_account):
		economy.transfer(account, supplier_account, cost, "restock")
	else:
		economy.burn_money(account, cost, "restock")
	var inventory: Dictionary = company.get("inventory", {})
	var entry: Dictionary = inventory.get(good_key, {"qty": 0, "unit_cost": unit_cost})
	var old_qty: int = int(entry.get("qty", 0))
	var old_cost: int = int(entry.get("unit_cost", unit_cost))
	var total_qty: int = old_qty + qty
	var weighted: int = unit_cost
	if total_qty > 0:
		weighted = int((old_qty * old_cost + qty * unit_cost) / total_qty)
	entry["qty"] = total_qty
	entry["unit_cost"] = weighted
	inventory[good_key] = entry
	company["inventory"] = inventory
	return {"ok": true, "cost": cost, "qty": total_qty}


func set_price(company: Dictionary, good_key: String, price: int) -> Dictionary:
	if price < 0:
		return {"ok": false, "reason": "bad_price"}
	var prices: Dictionary = company.get("prices", {})
	prices[good_key] = price
	company["prices"] = prices
	return {"ok": true, "price": price}


func inventory_qty(company: Dictionary, good_key: String) -> int:
	var inventory: Dictionary = company.get("inventory", {})
	if not inventory.has(good_key):
		return 0
	return int((inventory[good_key] as Dictionary).get("qty", 0))


# --- 雇佣 ---

func hire(company: Dictionary, employee_id: String, monthly_wage: int, opts: Dictionary = {}) -> Dictionary:
	var employees: Array = company.get("employees", [])
	for e in employees:
		if str((e as Dictionary).get("id", "")) == employee_id:
			return {"ok": false, "reason": "already_hired"}
	employees.append({
		"id": employee_id,
		"name": str(opts.get("name", employee_id)),
		"wage": maxi(0, monthly_wage),
		"loyalty": float(opts.get("loyalty", 70.0)),
	})
	company["employees"] = employees
	return {"ok": true, "employees": employees.size()}


func fire(company: Dictionary, employee_id: String) -> Dictionary:
	var employees: Array = company.get("employees", [])
	var kept: Array = []
	var found: bool = false
	for e in employees:
		if str((e as Dictionary).get("id", "")) == employee_id:
			found = true
		else:
			kept.append(e)
	company["employees"] = kept
	return {"ok": found, "employees": kept.size()}


func payroll_cost(company: Dictionary, days: int = 1) -> int:
	var employees: Array = company.get("employees", [])
	var total: int = 0
	for e in employees:
		total += int(float((e as Dictionary).get("wage", 0)) / MONTH_DAYS * days)
	return total


# --- 营业 tick ---

## 按日模拟营业：客流 → 收入 → 房租/工资支出 → 声誉变化 → 破产检查。
func tick_day(company: Dictionary, economy, day: int, rng = null, opts: Dictionary = {}) -> Dictionary:
	if str(company.get("status", "")) != STATUS_OPEN:
		return {"ok": false, "reason": "not_open"}
	var site: Dictionary = company.get("site", {})
	var area: float = maxf(1.0, float(site.get("area_sqm", 1.0)))
	var rep: float = clampf(float(company.get("reputation", 50.0)), 0.0, 100.0)
	var account: String = str(company["account"])
	var inventory: Dictionary = company.get("inventory", {})
	var prices: Dictionary = company.get("prices", {})
	var revenue: int = 0
	var shortages: Array = []
	for good in inventory.keys():
		var entry: Dictionary = inventory[good]
		var qty: int = int(entry.get("qty", 0))
		var cost: int = int(entry.get("unit_cost", 0))
		var price: int = int(prices.get(good, int(cost * REFERENCE_MARKUP)))
		if price <= 0:
			continue
		if qty <= 0:
			shortages.append(good)
			continue
		var ref: float = maxf(1.0, float(cost) * REFERENCE_MARKUP)
		var price_factor: float = clampf(2.0 - float(price) / ref, 0.0, 1.5)
		var demand: float = area * CUSTOMERS_PER_SQM * BASE_CONVERSION * (rep / 100.0) * price_factor
		var sold: int = int(minf(demand, float(qty)))
		if sold > 0:
			revenue += sold * price
			entry["qty"] = qty - sold
			inventory[good] = entry
		if float(qty) <= demand:
			shortages.append(good)
	company["inventory"] = inventory
	# 声誉随缺货与经营波动。
	if not shortages.is_empty():
		company["reputation"] = clampf(rep - REPUTATION_LOSS_SHORTAGE, 0.0, 100.0)
	else:
		company["reputation"] = clampf(rep + REPUTATION_GAIN_PER_DAY, 0.0, 100.0)
	# 收入来自外部消费者。
	if revenue > 0:
		economy.issue_money(account, revenue, "sales")
	# 房租。
	var rent: int = int(float(site.get("monthly_rent", 0)) / MONTH_DAYS)
	var rent_paid: int = 0
	if rent > 0 and economy.liquid(account) >= rent:
		economy.burn_money(account, rent, "rent")
		rent_paid = rent
	# 工资。
	var employees: Array = company.get("employees", [])
	var wages_paid: int = 0
	var unpaid: int = 0
	for i in employees.size():
		var e: Dictionary = employees[i]
		var w: int = int(float(e.get("wage", 0)) / MONTH_DAYS)
		if w <= 0:
			continue
		if economy.liquid(account) >= w:
			economy.burn_money(account, w, "wage")
			wages_paid += w
		else:
			unpaid += w
			e["loyalty"] = clampf(float(e.get("loyalty", 70.0)) - LOYALTY_UNPAID_PENALTY, 0.0, 100.0)
		employees[i] = e
	company["employees"] = employees
	# 忠诚过低可能离职。
	var resigned: Array = []
	var kept: Array = []
	for e in employees:
		if float(e.get("loyalty", 70.0)) < RESIGN_LOYALTY_THRESHOLD:
			var roll: float = rng.next_float() if rng != null else 0.0
			if roll < RESIGN_CHANCE:
				resigned.append(str(e.get("id", "")))
				continue
		kept.append(e)
	company["employees"] = kept
	var costs: int = rent_paid + wages_paid
	var result: Dictionary = {
		"ok": true, "day": day, "revenue": revenue, "costs": costs,
		"profit": revenue - costs, "shortages": shortages,
		"wages_unpaid": unpaid, "resigned": resigned,
	}
	var history: Array = company.get("revenue_history", [])
	history.append({"day": day, "revenue": revenue, "costs": costs, "profit": revenue - costs})
	company["revenue_history"] = history
	# 资不抵债。
	if economy.liquid(account) < 0:
		result["bankrupt"] = true
	return result


# --- 纳税 ---

## 按正利润缴纳企业所得税；无利润不缴。返回税额。
func settle_tax(company: Dictionary, economy, gov_account: String, annual_profit: int = -1) -> Dictionary:
	if annual_profit < 0:
		annual_profit = 0
		for h in company.get("revenue_history", []):
			annual_profit += int((h as Dictionary).get("profit", 0))
	if annual_profit <= 0:
		return {"ok": true, "tax": 0}
	var tax: int = int(TaxScript.new().corporate_tax(float(annual_profit)) * BaselineScript.MONEY_MINOR_SCALE)
	var account: String = str(company["account"])
	var paid: int = mini(tax, maxi(0, economy.liquid(account)))
	if paid > 0:
		if not gov_account.is_empty() and economy.has_account(gov_account):
			economy.transfer(account, gov_account, paid, "corporate_tax")
		else:
			economy.burn_money(account, paid, "corporate_tax")
	return {"ok": paid >= tax, "tax": paid, "expected": tax}


# --- 扩张与破产 ---

func expand(company: Dictionary, economy, cost: int, opts: Dictionary = {}) -> Dictionary:
	var account: String = str(company["account"])
	if economy.liquid(account) < cost:
		return {"ok": false, "reason": "insufficient_funds"}
	economy.burn_money(account, cost, "expand")
	company["branches"] = int(company.get("branches", 1)) + 1
	if opts.has("region_id"):
		var site: Dictionary = company.get("site", {})
		site["region_id"] = str(opts["region_id"])
		company["site"] = site
	return {"ok": true, "branches": int(company["branches"])}


func inventory_value(company: Dictionary) -> int:
	var total: int = 0
	for good in (company.get("inventory", {}) as Dictionary).keys():
		var entry: Dictionary = company["inventory"][good]
		total += int(entry.get("qty", 0)) * int(entry.get("unit_cost", 0))
	return total


func net_worth(company: Dictionary, economy) -> int:
	return economy.liquid(str(company["account"])) + inventory_value(company)


## 破产清算：变卖库存回收部分资金，标记破产。
func bankrupt(company: Dictionary, economy) -> Dictionary:
	var proceeds: int = int(float(inventory_value(company)) * LIQUIDATION_RATIO)
	var account: String = str(company["account"])
	if proceeds > 0:
		economy.issue_money(account, proceeds, "liquidation")
	company["status"] = STATUS_BANKRUPT
	company["inventory"] = {}
	company["prices"] = {}
	company["employees"] = []
	return {"ok": true, "proceeds": proceeds, "status": STATUS_BANKRUPT, "liquid": economy.liquid(account)}


func is_insolvent(company: Dictionary, economy) -> bool:
	return economy.liquid(str(company["account"])) < 0


func to_dict(company: Dictionary) -> Dictionary:
	return company.duplicate(true)
