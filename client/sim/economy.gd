class_name EconomySystem
extends RefCounted
## 经济与宏观（R15、R17、R48；design 经济系统、D8）。
##
## 职责：
##   - 统一资金入口 add_money：所有余额变动都落在账本上，支持金钱守恒核验；
##   - 账户模型 cash/bank/debt（金额为最小货币单位的整数，避免浮点漂移）；
##   - 宏观变量（GDP、通胀、基准利率、失业率、物价指数、PMI）按季度 tick 推进，
##     内生周期（繁荣/复苏/衰退/放缓）与货币、利率、就业的传导；
##   - 就业市场：失业率 → 求职难度与工资水平。
##
## 权威边界：全球宏观后端权威，客户端拉取快照并按本模型离线近似推进，不逐笔回放。
## 数值默认集中在 client/sim/baseline.gd，均可由远程配置覆盖。

const BaselineScript = preload("res://sim/baseline.gd")
const RngScript = preload("res://sim/rng.gd")

const FIELD_CASH: String = "cash"
const FIELD_BANK: String = "bank"
const FIELD_DEBT: String = "debt"
const FIELDS: Array = [FIELD_CASH, FIELD_BANK, FIELD_DEBT]


var _accounts: Dictionary = {}     # id -> {cash:int, bank:int, debt:int}
var _ledger: Array = []            # 账本：[{account, field, delta, reason, seq}]
var _initial_money: int = 0        # 初始货币总量（cash + bank）
var _seq: int = 0
var _rng = null

# 宏观状态
var macro: Dictionary = {}
var _money_supply: float = 1.0
var _quarter_printed: float = 0.0
var _wage_lag: Array = []          # 工资滞后队列（保留近 N 季通胀）


func _init(seed: int = 0) -> void:
	_rng = RngScript.new(seed)
	macro = _default_macro()


static func _default_macro() -> Dictionary:
	return {
		"gdp": 100.0,
		"gdp_growth": BaselineScript.MACRO_GDP_GROWTH_BASE,
		"inflation": BaselineScript.MACRO_BASE_INFLATION,
		"base_rate": BaselineScript.MACRO_BASE_RATE,
		"unemployment": BaselineScript.MACRO_UNEMPLOYMENT_BASE,
		"price_index": 1.0,
		"pmi": BaselineScript.MACRO_PMI_BASE,
		"money_supply": 1.0,
		"cycle_phase": "recovery",
		"cycle_quarters_left": 8,
	}


# --- 账户 ---

func open_account(id: String, cash_minor: int = 0, bank_minor: int = 0, debt_minor: int = 0) -> Dictionary:
	var acc: Dictionary = _accounts.get(id, {FIELD_CASH: 0, FIELD_BANK: 0, FIELD_DEBT: 0})
	acc[FIELD_CASH] = int(acc[FIELD_CASH]) + cash_minor
	acc[FIELD_BANK] = int(acc[FIELD_BANK]) + bank_minor
	acc[FIELD_DEBT] = int(acc[FIELD_DEBT]) + debt_minor
	_accounts[id] = acc
	_initial_money = total_money()
	return acc

func has_account(id: String) -> bool:
	return _accounts.has(id)

func get_account(id: String) -> Dictionary:
	return _accounts.get(id, {})

func cash(id: String) -> int:
	return int(get_account(id).get(FIELD_CASH, 0))

func bank(id: String) -> int:
	return int(get_account(id).get(FIELD_BANK, 0))

func debt(id: String) -> int:
	return int(get_account(id).get(FIELD_DEBT, 0))

## 流动余额（现金 + 存款）。
func liquid(id: String) -> int:
	return cash(id) + bank(id)

## 净资产 = 现金 + 存款 − 负债，可为负。
func net_worth(id: String) -> int:
	return cash(id) + bank(id) - debt(id)

## 系统货币总量（现金 + 存款），转账不改变它。
func total_money() -> int:
	var total: int = 0
	for id in _accounts.keys():
		total += cash(id) + bank(id)
	return total

func initial_money() -> int:
	return _initial_money


# --- 统一资金入口 ---

## 唯一资金变动入口。delta 为最小货币单位整数，可为负；返回实际生效的 delta。
## field ∈ {cash, bank, debt}；debt 余额下限为 0。
## 账本记录每条变动，money 类字段的账本累计等于货币总量相对初始值的变化。
func add_money(id: String, delta: int, reason: String, field: String = FIELD_CASH) -> int:
	if not FIELDS.has(field):
		field = FIELD_CASH
	if not _accounts.has(id):
		_accounts[id] = {FIELD_CASH: 0, FIELD_BANK: 0, FIELD_DEBT: 0}
	var acc: Dictionary = _accounts[id]
	var before: int = int(acc.get(field, 0))
	var after: int = before + delta
	if field == FIELD_DEBT:
		after = maxi(0, after)
	var applied: int = after - before
	acc[field] = after
	_seq += 1
	_ledger.append({
		"account": id, "field": field, "delta": applied,
		"reason": reason, "seq": _seq,
	})
	return applied

## 账户间转账：现金对现金，总额不变。余额不足时返回 false 不做任何改动。
func transfer(from_id: String, to_id: String, amount: int, reason: String = "transfer") -> bool:
	if amount <= 0 or cash(from_id) < amount:
		return false
	add_money(from_id, -amount, reason, FIELD_CASH)
	add_money(to_id, amount, reason, FIELD_CASH)
	return true

## 央行发行货币（增加总量），并计入本季货币投放用于通胀。
func issue_money(id: String, amount: int, reason: String = "issuance") -> int:
	if amount <= 0:
		return 0
	var applied: int = add_money(id, amount, reason, FIELD_CASH)
	_quarter_printed += float(applied)
	_money_supply += float(applied)
	return applied

## 央行回收货币（减少总量）。
func burn_money(id: String, amount: int, reason: String = "sink") -> int:
	var applied: int = -add_money(id, -amount, reason, FIELD_CASH)
	if applied > 0:
		_money_supply = maxf(0.0, _money_supply - float(applied))
	return applied

func ledger() -> Array:
	return _ledger.duplicate(true)

## 账本累计变化（delta 之和）。
func ledger_sum() -> int:
	var total: int = 0
	for e in _ledger:
		total += int(e.get("delta", 0))
	return total

## 守恒核验：货币总量变化等于 cash/bank 类账本累计。
func is_conserved() -> bool:
	var money_delta: int = 0
	for e in _ledger:
		var field: String = str(e.get("field", FIELD_CASH))
		if field == FIELD_CASH or field == FIELD_BANK:
			money_delta += int(e.get("delta", 0))
	return total_money() - _initial_money == money_delta


# --- 宏观指标 ---

func indicator(key: String) -> Variant:
	return macro.get(key)

func set_base_rate(rate: float) -> void:
	macro["base_rate"] = clampf(rate, BaselineScript.MACRO_RATE_MIN, BaselineScript.MACRO_RATE_MAX)

## 按季推进宏观：周期切换 → GDP → 通胀 → 利率 → 失业 → 物价指数。
## policy_rate >= 0 时作为外生政策利率直接设定；否则利率按通胀泰勒式内生调整。
func tick_macro(policy_rate: float = -1.0) -> Dictionary:
	_advance_cycle()
	var phase: String = str(macro.get("cycle_phase", "recovery"))
	var cycle_effect: float = float(BaselineScript.MACRO_CYCLE_GDP_EFFECT.get(phase, 0.0))

	# GDP：基准增长 + 周期效应（季度化）。
	var gdp_growth: float = BaselineScript.MACRO_GDP_GROWTH_BASE + cycle_effect
	macro["gdp_growth"] = gdp_growth
	var gdp: float = float(macro.get("gdp", 100.0)) * (1.0 + gdp_growth / float(BaselineScript.MACRO_QUARTERS_PER_YEAR))
	if is_finite(gdp):
		macro["gdp"] = maxf(0.0, gdp)

	# 通胀：基准 + 货币投放 − 利率抑制 + 周期压力，平滑逼近目标。
	var money_growth: float = _quarter_printed / maxf(1.0, _money_supply)
	var base_rate: float = float(macro.get("base_rate", BaselineScript.MACRO_BASE_RATE))
	var cycle_pressure: float = 0.01 if (phase == "boom" or phase == "recovery") else -0.01
	var target_inflation: float = (
		BaselineScript.MACRO_BASE_INFLATION
		+ 0.8 * money_growth
		- 0.3 * (base_rate - BaselineScript.MACRO_BASE_RATE)
		+ cycle_pressure
	)
	var inflation: float = float(macro.get("inflation", BaselineScript.MACRO_BASE_INFLATION))
	inflation = clampf(move_toward(inflation, target_inflation, 0.01),
		BaselineScript.MACRO_INFLATION_MIN, BaselineScript.MACRO_INFLATION_MAX)

	# 利率：外生政策或按通胀内生调整。
	if policy_rate >= 0.0:
		base_rate = clampf(policy_rate, BaselineScript.MACRO_RATE_MIN, BaselineScript.MACRO_RATE_MAX)
	else:
		var rate_target: float = BaselineScript.MACRO_BASE_RATE + 0.5 * (inflation - BaselineScript.MACRO_BASE_INFLATION)
		base_rate = clampf(base_rate + 0.5 * (rate_target - base_rate),
			BaselineScript.MACRO_RATE_MIN, BaselineScript.MACRO_RATE_MAX)
	macro["base_rate"] = base_rate

	# 失业：菲利普斯曲线 + 利率抑制。
	var unemployment_target: float = (
		BaselineScript.MACRO_UNEMPLOYMENT_BASE
		- BaselineScript.MACRO_INFLATION_UNEMPLOYMENT_TRADEOFF * (inflation - BaselineScript.MACRO_BASE_INFLATION)
		+ BaselineScript.MACRO_RATE_UNEMPLOYMENT_SENSITIVITY * (base_rate - BaselineScript.MACRO_BASE_RATE)
	)
	var unemployment: float = float(macro.get("unemployment", BaselineScript.MACRO_UNEMPLOYMENT_BASE))
	unemployment = clampf(move_toward(unemployment, unemployment_target, 0.01),
		BaselineScript.MACRO_UNEMPLOYMENT_MIN, BaselineScript.MACRO_UNEMPLOYMENT_MAX)

	macro["inflation"] = inflation
	macro["unemployment"] = unemployment

	# 物价指数累积（通胀 >= 下限，正通胀时单调上升）。
	var price_index: float = float(macro.get("price_index", 1.0))
	price_index *= (1.0 + inflation / float(BaselineScript.MACRO_QUARTERS_PER_YEAR))
	macro["price_index"] = maxf(0.0, price_index)

	# PMI：以通胀与失业相对基准构造，clamp 到 0..100。
	var pmi: float = (
		BaselineScript.MACRO_PMI_BASE
		+ 50.0 * (inflation - BaselineScript.MACRO_BASE_INFLATION)
		- 100.0 * (unemployment - BaselineScript.MACRO_UNEMPLOYMENT_BASE)
	)
	macro["pmi"] = clampf(pmi, BaselineScript.MACRO_PMI_MIN, BaselineScript.MACRO_PMI_MAX)
	macro["money_supply"] = _money_supply

	# 工资滞后：记录近 N 季通胀，供 wage_multiplier 使用。
	_wage_lag.append(inflation)
	while _wage_lag.size() > BaselineScript.MACRO_WAGE_LAG_QUARTERS + 1:
		_wage_lag.pop_front()

	_quarter_printed = 0.0
	return macro.duplicate(true)

## 周期切换：剩余季数归零时按确定性随机流进入下一阶段。
func _advance_cycle() -> void:
	var left: int = int(macro.get("cycle_quarters_left", 0)) - 1
	if left > 0:
		macro["cycle_quarters_left"] = left
		return
	var phases: Array = BaselineScript.MACRO_CYCLE_PHASES
	var idx: int = phases.find(str(macro.get("cycle_phase", "recovery")))
	if idx < 0:
		idx = 0
	idx = (idx + 1) % phases.size()
	var span: int = BaselineScript.MACRO_CYCLE_MAX_QUARTERS - BaselineScript.MACRO_CYCLE_MIN_QUARTERS
	macro["cycle_phase"] = phases[idx]
	macro["cycle_quarters_left"] = BaselineScript.MACRO_CYCLE_MIN_QUARTERS + int(_rng.next_float() * float(span + 1))

## 确定性复利推进物价指数（离线近似，不逐笔回放）。
func apply_inflation(price_index: float, annual_rate: float, years: float) -> float:
	var quarters: float = years * float(BaselineScript.MACRO_QUARTERS_PER_YEAR)
	var result: float = price_index * pow(1.0 + annual_rate / float(BaselineScript.MACRO_QUARTERS_PER_YEAR), quarters)
	if not is_finite(result):
		return price_index
	return maxf(0.0, result)


# --- 就业市场 ---

## 求职难度 0..1：失业率越高越难。
func hire_difficulty(unemployment: float = -1.0) -> float:
	var u: float = unemployment if unemployment >= 0.0 else float(macro.get("unemployment", BaselineScript.MACRO_UNEMPLOYMENT_BASE))
	return clampf(
		BaselineScript.EMPLOYMENT_BASE_HIRE_DIFFICULTY
		+ BaselineScript.EMPLOYMENT_UNEMPLOYMENT_SENSITIVITY * (u - BaselineScript.MACRO_UNEMPLOYMENT_BASE),
		0.0, 1.0)

## 名义工资乘数：失业率高则压低，且对通胀滞后一季调整。
func wage_multiplier(unemployment: float = -1.0) -> float:
	var u: float = unemployment if unemployment >= 0.0 else float(macro.get("unemployment", BaselineScript.MACRO_UNEMPLOYMENT_BASE))
	var mult: float = 1.0 - BaselineScript.EMPLOYMENT_WAGE_UNEMPLOYMENT_SENSITIVITY * (u - BaselineScript.MACRO_UNEMPLOYMENT_BASE)
	if not _wage_lag.is_empty():
		mult *= (1.0 + float(_wage_lag[0]))
	return clampf(mult, 0.3, 3.0)


# --- 序列化 ---

func to_dict() -> Dictionary:
	return {
		"accounts": _accounts.duplicate(true),
		"initial_money": _initial_money,
		"macro": macro.duplicate(true),
		"money_supply": _money_supply,
	}

func from_dict(data: Dictionary) -> void:
	var accounts: Variant = data.get("accounts", {})
	_accounts = (accounts as Dictionary).duplicate(true) if accounts is Dictionary else {}
	_initial_money = int(data.get("initial_money", total_money()))
	var m: Variant = data.get("macro", {})
	macro = (m as Dictionary).duplicate(true) if m is Dictionary and not (m as Dictionary).is_empty() else _default_macro()
	_money_supply = float(data.get("money_supply", macro.get("money_supply", 1.0)))
	_ledger.clear()
	_seq = 0
