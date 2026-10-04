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


func _init(seed: int = 0) -> void:
	_rng = RngScript.new(seed)


# =====================================================================
# 存款与贷款
# =====================================================================

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


# --- 序列化 ---

func to_dict() -> Dictionary:
	return {
		"credit": _credit.duplicate(true),
		"fixed_deposits": _fixed_deposits.duplicate(true),
		"positions": _positions.duplicate(true),
		"lottery_tickets": _lottery_tickets,
		"lottery_pool": _lottery_pool,
	}
