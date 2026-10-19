class_name BankSystem
extends RefCounted
## 银行、金融工具与杠杆（R15、R48；design D8）。
##
## 职责：
##   - 活期/定期存款、贷款按日计息、逾期降级信用；
##   - 金融品种 GBM 报价（复用 MarketSystem.gbm_step，同种子可复现）；
##   - 杠杆保证金与强平；
##   - 保险保费/理赔与彩票购买/开奖。
##
## 账户资金一律经 EconomySystem.add_money 变动，保证账本可核验。
## 数值默认集中在 client/sim/baseline.gd，均可由远程配置覆盖。

const BaselineScript = preload("res://sim/baseline.gd")
const MarketScript = preload("res://sim/market.gd")
const RngScript = preload("res://sim/rng.gd")


var _credit: Dictionary = {}       # id -> 信用评级 0..1000
var _fixed_deposits: Dictionary = {}  # id -> [{principal, rate, start_day, term_days, matured}]
var _positions: Dictionary = {}    # pos_id -> 持仓
var _rng = null
var _lottery_tickets: int = 0
var _lottery_pool: int = 0
var _pos_seq: int = 0
var _securities: Dictionary = {}   # key -> {name, kind, price, mu, sigma, crypto}
var _holdings: Dictionary = {}     # key -> {qty, cost}


func _init(seed: int = 0) -> void:
	_rng = RngScript.new(seed)
	seed_securities()


# =====================================================================
# 存款与贷款
# =====================================================================

func fixed_deposits(id: String) -> Array:
	return (_fixed_deposits.get(id, []) as Array).duplicate(true)

func credit_rating(id: String) -> int:
	return int(_credit.get(id, BaselineScript.BANK_CREDIT_START))

func set_credit_rating(id: String, value: int) -> void:
	_credit[id] = clampi(value, BaselineScript.BANK_CREDIT_MIN, BaselineScript.BANK_CREDIT_MAX)

func demand_rate() -> float:
	return float(BaselineScript.effective_economy_param("bank_demand_rate_annual", BaselineScript.BANK_DEMAND_RATE_ANNUAL))

func fixed_rate() -> float:
	return float(BaselineScript.effective_economy_param("bank_fixed_rate_annual", BaselineScript.BANK_FIXED_RATE_ANNUAL))

func loan_rate() -> float:
	return float(BaselineScript.effective_economy_param("bank_loan_rate_annual", BaselineScript.BANK_LOAN_RATE_ANNUAL))

## 存款：现金转入存款账户，货币总量不变。
func deposit(economy, id: String, amount: int) -> bool:
	if amount <= 0 or economy.cash(id) < amount:
		return false
	economy.add_money(id, -amount, "bank_deposit", "cash")
	economy.add_money(id, amount, "bank_deposit", "bank")
	return true

## 取款：存款转回现金。
func withdraw(economy, id: String, amount: int) -> bool:
	if amount <= 0 or economy.bank(id) < amount:
		return false
	economy.add_money(id, -amount, "bank_withdraw", "bank")
	economy.add_money(id, amount, "bank_withdraw", "cash")
	return true

## 开定期存款：本金从现金划入存款，记录到期结算信息。
func open_fixed_deposit(economy, id: String, amount: int, start_day: int, term_days: int, rate: float = -1.0) -> bool:
	if amount <= 0 or term_days <= 0 or economy.cash(id) < amount:
		return false
	economy.add_money(id, -amount, "fixed_deposit", "cash")
	economy.add_money(id, amount, "fixed_deposit", "bank")
	var effective_rate: float = rate if rate >= 0.0 else fixed_rate()
	var list: Array = _fixed_deposits.get(id, [])
	list.append({
		"principal": amount, "rate": effective_rate,
		"start_day": start_day, "term_days": term_days, "matured": false,
	})
	_fixed_deposits[id] = list
	return true

## 到期结算：按约定利率计息并计入存款；返回结算利息（最小货币单位）。
func mature_fixed_deposits(economy, id: String, current_day: int) -> int:
	var list: Array = _fixed_deposits.get(id, [])
	var interest_total: int = 0
	for entry in list:
		var item: Dictionary = entry
		if bool(item.get("matured", false)):
			continue
		var due_day: int = int(item.get("start_day", 0)) + int(item.get("term_days", 0))
		if current_day < due_day:
			continue
		var principal: int = int(item.get("principal", 0))
		var years: float = float(item.get("term_days", 0)) / 365.0
		var interest: int = int(round(float(principal) * float(item.get("rate", 0.0)) * years))
		economy.add_money(id, interest, "fixed_deposit_interest", "bank")
		item["matured"] = true
		interest_total += interest
	_fixed_deposits[id] = list
	return interest_total

## 贷款发放：现金入账、负债增加（信用创造）。
func take_loan(economy, id: String, principal: int, term_days: int = 365) -> int:
	if principal <= 0 or term_days <= 0:
		return 0
	economy.add_money(id, principal, "loan_disbursement", "cash")
	economy.add_money(id, principal, "loan_principal", "debt")
	return principal

## 按日计息：负债按日复利累加，返回本次利息。
func accrue_loan_interest(economy, id: String, days: int, rate: float = -1.0) -> int:
	if days <= 0 or economy.debt(id) <= 0:
		return 0
	var annual: float = rate if rate >= 0.0 else loan_rate()
	var daily: float = annual / 365.0
	var principal: int = economy.debt(id)
	var interest: int = int(round(float(principal) * (pow(1.0 + daily, float(days)) - 1.0)))
	interest = maxi(0, interest)
	if interest > 0:
		economy.add_money(id, interest, "loan_interest", "debt")
	return interest

## 还款：现金冲抵负债。
func repay_loan(economy, id: String, amount: int) -> int:
	if amount <= 0 or economy.debt(id) <= 0:
		return 0
	var pay: int = mini(amount, economy.cash(id))
	pay = mini(pay, economy.debt(id))
	if pay <= 0:
		return 0
	economy.add_money(id, -pay, "loan_repayment", "cash")
	economy.add_money(id, -pay, "loan_repayment", "debt")
	return pay

## 逾期处理：超过阈值降级信用评级。
func record_overdue(id: String, overdue_days: int) -> bool:
	if overdue_days <= BaselineScript.BANK_OVERDUE_DAYS_DOWNGRADE:
		return false
	set_credit_rating(id, credit_rating(id) - BaselineScript.BANK_CREDIT_OVERDUE_PENALTY)
	return true


# =====================================================================
# GBM 报价
# =====================================================================

## 用 GBM 生成下一期报价（同种子可复现），供基金/理财等金融品种使用。
func quote_next(price: float, mu: float, sigma: float, dt_years: float) -> float:
	return MarketScript.gbm_step(price, mu, sigma, dt_years, _rng)


# =====================================================================
# 杠杆与强平
# =====================================================================

## 开仓：direction = 1 多 / -1 空。initial_ratio 为保证金率，越高杠杆越低。
func open_position(entry_price: float, notional: int, direction: int, initial_ratio: float = -1.0) -> Dictionary:
	var ratio: float = initial_ratio if initial_ratio > 0.0 else BaselineScript.MARGIN_INITIAL_RATIO
	ratio = clampf(ratio, BaselineScript.MARGIN_MAINTENANCE_RATIO, 1.0)
	_pos_seq += 1
	var pos: Dictionary = {
		"id": "pos_%d" % _pos_seq,
		"entry": maxf(1e-9, entry_price),
		"notional": notional,
		"direction": 1 if direction >= 0 else -1,
		"initial_ratio": ratio,
		"margin": int(round(float(notional) * ratio)),
		"liquidated": false,
	}
	_positions[pos["id"]] = pos
	return pos

## 强平价：多仓下跌、空仓上涨至维持保证金线。
func liquidation_price(pos: Dictionary) -> float:
	var entry: float = float(pos.get("entry", 1.0))
	var initial: float = float(pos.get("initial_ratio", BaselineScript.MARGIN_INITIAL_RATIO))
	var direction: int = int(pos.get("direction", 1))
	if direction >= 0:
		return entry * (1.0 + BaselineScript.MARGIN_MAINTENANCE_RATIO - initial)
	return entry * (1.0 - BaselineScript.MARGIN_MAINTENANCE_RATIO + initial)

func should_liquidate(pos: Dictionary, price: float) -> bool:
	var liq: float = liquidation_price(pos)
	if int(pos.get("direction", 1)) >= 0:
		return price <= liq
	return price >= liq

## 强平结算：返回账户可取回的保证金（已扣强平费），可为负。
func liquidate(pos: Dictionary, price: float) -> int:
	var entry: float = float(pos.get("entry", 1.0))
	var notional: int = int(pos.get("notional", 0))
	var direction: int = int(pos.get("direction", 1))
	var margin: int = int(pos.get("margin", 0))
	var pnl: int = int(round((price - entry) / entry * float(notional))) * direction
	var fee: int = int(round(float(notional) * BaselineScript.MARGIN_LIQUIDATION_FEE))
	var payout: int = margin + pnl - fee
	pos["liquidated"] = true
	_positions[pos["id"]] = pos
	return payout


# =====================================================================
# 保险与彩票
# =====================================================================

func insurance_premium(sum_insured: int) -> int:
	return int(round(float(sum_insured) * BaselineScript.INSURANCE_PREMIUM_RATE))

## 保险理赔：符合条件时按比例赔付。
func insurance_claim(sum_insured: int, incident: bool, covered: bool = true) -> int:
	if not incident or not covered:
		return 0
	return int(round(float(sum_insured) * BaselineScript.INSURANCE_PAYOUT_RATE))

## 购买彩票：扣款并计入奖池。
func buy_lottery(economy, id: String) -> bool:
	if economy.cash(id) < BaselineScript.LOTTERY_TICKET_PRICE_MINOR:
		return false
	economy.add_money(id, -BaselineScript.LOTTERY_TICKET_PRICE_MINOR, "lottery_ticket", "cash")
	_lottery_tickets += 1
	_lottery_pool += BaselineScript.LOTTERY_TICKET_PRICE_MINOR
	return true

## 开奖：以确定性随机流判定，中奖返还奖金。
func draw_lottery(economy, id: String) -> int:
	var win: bool = _rng.next_float() < BaselineScript.LOTTERY_WIN_CHANCE
	var payout: int = 0
	if win:
		payout = BaselineScript.LOTTERY_PAYOUT_MINOR
		economy.add_money(id, payout, "lottery_payout", "cash")
	return payout

func lottery_tickets() -> int:
	return _lottery_tickets


# --- 证券投资 ---

## 内置证券池：股票/基金/债券/黄金/加密资产，价格与漂移按风险分层。
const SECURITIES: Dictionary = {
	"stock.tech": {"name": "科技成长", "kind": "stock", "price": 58.0, "mu": 0.12, "sigma": 0.32},
	"stock.bank": {"name": "银行蓝筹", "kind": "stock", "price": 22.0, "mu": 0.07, "sigma": 0.22},
	"stock.energy": {"name": "能源周期", "kind": "stock", "price": 35.0, "mu": 0.09, "sigma": 0.28},
	"fund.index": {"name": "宽基指数", "kind": "fund", "price": 4.2, "mu": 0.06, "sigma": 0.14},
	"fund.bond": {"name": "债券基金", "kind": "fund", "price": 1.8, "mu": 0.03, "sigma": 0.05},
	"bond.gov": {"name": "国债", "kind": "bond", "price": 100.0, "mu": 0.025, "sigma": 0.03},
	"gold": {"name": "黄金", "kind": "commodity", "price": 520.0, "mu": 0.05, "sigma": 0.12},
	"crypto.btc": {"name": "比特币", "kind": "crypto", "price": 42000.0, "mu": 0.18, "sigma": 0.65, "crypto": true},
}

## 填充证券池（幂等）；已存在报价不覆盖，避免读档后重置。
func seed_securities() -> void:
	for key in SECURITIES.keys():
		if _securities.has(key):
			continue
		var def: Dictionary = SECURITIES[key]
		_securities[key] = {
			"name": String(def.get("name", key)), "kind": String(def.get("kind", "stock")),
			"price": maxf(0.01, float(def.get("price", 1.0))),
			"mu": float(def.get("mu", BaselineScript.GBM_DRIFT_DEFAULT)),
			"sigma": float(def.get("sigma", BaselineScript.GBM_VOLATILITY_DEFAULT)),
			"crypto": bool(def.get("crypto", false)),
		}

func security_keys() -> Array:
	return _securities.keys()

func security_quote(key: String) -> Dictionary:
	var sec: Dictionary = _securities.get(key, {})
	if sec.is_empty():
		return {}
	return {
		"key": key, "name": String(sec.get("name", key)), "kind": String(sec.get("kind", "stock")),
		"price": float(sec.get("price", 0.0)), "crypto": bool(sec.get("crypto", false)),
	}

## 推进全部证券报价；dt_years 为经过年数。价格恒为正且可复现。
func advance_securities(dt_years: float) -> void:
	if dt_years <= 0.0:
		return
	seed_securities()
	for key in _securities.keys():
		var sec: Dictionary = _securities[key]
		var stepped: float = quote_next(float(sec.get("price", 1.0)), float(sec.get("mu", 0.0)), float(sec.get("sigma", 0.0)), dt_years)
		sec["price"] = maxf(BaselineScript.GBM_PRICE_FLOOR, stepped)
		_securities[key] = sec

func holding_qty(key: String) -> int:
	return int((_holdings.get(key, {}) as Dictionary).get("qty", 0))

func holding_cost(key: String) -> float:
	return float((_holdings.get(key, {}) as Dictionary).get("cost", 0.0))

## 买入：按当前报价从现金扣款，均价成本按加权平均更新。返回成交明细。
func buy_security(economy, id: String, key: String, qty: int) -> Dictionary:
	seed_securities()
	if qty <= 0 or not _securities.has(key):
		return {"ok": false, "reason": "bad_order"}
	var price: float = float((_securities[key] as Dictionary).get("price", 0.0))
	var cost: int = int(round(price * float(BaselineScript.MONEY_MINOR_SCALE) * float(qty)))
	if cost <= 0 or economy.cash(id) < cost:
		return {"ok": false, "reason": "insufficient_cash", "cost": cost}
	economy.add_money(id, -cost, "security_buy", "cash")
	var held: Dictionary = _holdings.get(key, {"qty": 0, "cost": 0.0})
	var old_qty: int = int(held.get("qty", 0))
	var old_cost: float = float(held.get("cost", 0.0))
	var new_qty: int = old_qty + qty
	held["qty"] = new_qty
	held["cost"] = (old_cost * float(old_qty) + price * float(qty)) / float(new_qty)
	_holdings[key] = held
	return {"ok": true, "key": key, "qty": qty, "price": price, "cost": cost, "avg_cost": float(held["cost"])}

## 卖出：按当前报价回款，卖出部分不改变剩余持仓均价。
func sell_security(economy, id: String, key: String, qty: int) -> Dictionary:
	seed_securities()
	if qty <= 0 or not _securities.has(key):
		return {"ok": false, "reason": "bad_order"}
	var held: Dictionary = _holdings.get(key, {})
	if int(held.get("qty", 0)) < qty:
		return {"ok": false, "reason": "insufficient_holding"}
	var price: float = float((_securities[key] as Dictionary).get("price", 0.0))
	var proceeds: int = int(round(price * float(BaselineScript.MONEY_MINOR_SCALE) * float(qty)))
	economy.add_money(id, proceeds, "security_sell", "cash")
	held["qty"] = int(held.get("qty", 0)) - qty
	if int(held["qty"]) <= 0:
		_holdings.erase(key)
	else:
		_holdings[key] = held
	return {"ok": true, "key": key, "qty": qty, "price": price, "proceeds": proceeds}

## 组合市值与浮动盈亏（按当前报价；金额为主币单位）。
func portfolio() -> Dictionary:
	seed_securities()
	var items: Array = []
	var total_value: float = 0.0
	var total_cost: float = 0.0
	for key in _holdings.keys():
		var qty: int = int((_holdings[key] as Dictionary).get("qty", 0))
		if qty <= 0 or not _securities.has(key):
			continue
		var price: float = float((_securities[key] as Dictionary).get("price", 0.0))
		var avg: float = float((_holdings[key] as Dictionary).get("cost", 0.0))
		var value: float = price * float(qty)
		var cost: float = avg * float(qty)
		total_value += value
		total_cost += cost
		items.append({
			"key": key, "name": String((_securities[key] as Dictionary).get("name", key)),
			"kind": String((_securities[key] as Dictionary).get("kind", "stock")),
			"qty": qty, "price": price, "avg_cost": avg,
			"value": value, "profit": value - cost,
		})
	return {"items": items, "value": total_value, "cost": total_cost, "profit": total_value - total_cost}


# --- 序列化 ---

func to_dict() -> Dictionary:
	return {
		"credit": _credit.duplicate(true),
		"fixed_deposits": _fixed_deposits.duplicate(true),
		"positions": _positions.duplicate(true),
		"lottery_tickets": _lottery_tickets,
		"lottery_pool": _lottery_pool,
		"securities": _securities.duplicate(true),
		"holdings": _holdings.duplicate(true),
	}

func from_dict(data: Dictionary) -> void:
	var credit: Variant = data.get("credit", {})
	_credit = (credit as Dictionary).duplicate(true) if credit is Dictionary else {}
	var fixed: Variant = data.get("fixed_deposits", {})
	_fixed_deposits = (fixed as Dictionary).duplicate(true) if fixed is Dictionary else {}
	var positions: Variant = data.get("positions", {})
	_positions = (positions as Dictionary).duplicate(true) if positions is Dictionary else {}
	_lottery_tickets = int(data.get("lottery_tickets", 0))
	_lottery_pool = int(data.get("lottery_pool", 0))
	var sec: Variant = data.get("securities", {})
	_securities = (sec as Dictionary).duplicate(true) if sec is Dictionary and not (sec as Dictionary).is_empty() else {}
	var hold: Variant = data.get("holdings", {})
	_holdings = (hold as Dictionary).duplicate(true) if hold is Dictionary else {}
	seed_securities()
