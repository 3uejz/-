class_name MarketSystem
extends RefCounted
## 市场与价格（R17、R48；design 经济系统、D8）。
##
## 职责：
##   - 商品价格分层：价格 = 基础价 × 供需弹性 × 季节/事件修正 × 通胀累积；确定性可复现；
##   - 个体交易对价格影响微弱，组织/大额交易才显著推动；价格波动因子 clamp 到上下限；
##   - 股票/基金/外汇/大宗在基础趋势上叠加几何布朗运动（GBM）；
##   - 多国货币浮动汇率、换汇价差与手续费，换算价值守恒。
##
## 数值默认集中在 client/sim/baseline.gd，均可由远程配置覆盖。

const BaselineScript = preload("res://sim/baseline.gd")
const RngScript = preload("res://sim/rng.gd")

const MIN_SUPPLY: float = BaselineScript.MARKET_MIN_SUPPLY
const FX_EPSILON: float = BaselineScript.MARKET_FX_EPSILON


# --- 通用 GBM ---

## 标准正态采样（Box-Muller），使用传入的确定性随机流。
static func normal_sample(rng) -> float:
	var u1: float = maxf(1e-12, rng.next_float())
	var u2: float = rng.next_float()
	return sqrt(-2.0 * log(u1)) * cos(TAU * u2)

## GBM 单步：S *= exp((mu − 0.5σ²)dt + σ√dt·Z)，保证价格为正。
static func gbm_step(price: float, mu: float, sigma: float, dt_years: float, rng) -> float:
	var z: float = normal_sample(rng)
	var drift: float = (mu - 0.5 * sigma * sigma) * dt_years
	var diffusion: float = sigma * sqrt(maxf(0.0, dt_years)) * z
	var stepped: float = price * exp(drift + diffusion)
	if not is_finite(stepped):
		return price
	return maxf(BaselineScript.GBM_PRICE_FLOOR, stepped)


var _goods: Dictionary = {}        # key -> {base_price, category, seasonal}
var _supply: Dictionary = {}       # key -> float
var _demand: Dictionary = {}       # key -> float
var _events: Dictionary = {}       # key -> float 事件修正
var _inflation_index: float = 1.0

var _stocks: Dictionary = {}       # key -> {price, mu, sigma, crypto}
var _fx_rate: Dictionary = {}      # code -> 当前汇率


func _init() -> void:
	reset_fx()


# =====================================================================
# 商品价格
# =====================================================================

func register_good(key: String, base_price: float, category: String = "daily", seasonal: bool = false) -> void:
	_goods[key] = {"base_price": maxf(0.01, base_price), "category": category, "seasonal": seasonal}
	if not _supply.has(key):
		_supply[key] = 1.0
	if not _demand.has(key):
		_demand[key] = 1.0

func has_good(key: String) -> bool:
	return _goods.has(key)

func base_price(key: String) -> float:
	return float((_goods.get(key, {}) as Dictionary).get("base_price", 0.0))

## 设置事件修正（如灾荒、战争、节日）。
func set_event_modifier(key: String, factor: float) -> void:
	_events[key] = maxf(0.01, factor)

func clear_event_modifiers() -> void:
	_events.clear()

func set_inflation_index(index: float) -> void:
	_inflation_index = maxf(0.0, index)

func inflation_index() -> float:
	return _inflation_index

## 按年通胀率推进物价指数（确定性复利）。
func advance_inflation(annual_rate: float, years: float) -> float:
	var quarters: float = years * float(BaselineScript.MACRO_QUARTERS_PER_YEAR)
	_inflation_index *= pow(1.0 + annual_rate / float(BaselineScript.MACRO_QUARTERS_PER_YEAR), quarters)
	if not is_finite(_inflation_index):
		_inflation_index = 1.0
	return _inflation_index

## 季节修正：仅对季节敏感（seasonal=true）的品类生效。
func season_factor(season: String) -> float:
	var f: float = float(BaselineScript.PRICE_SEASONAL_FACTORS.get(season, 1.0))
	return f if f > 0.0 else 1.0

func _fluctuation(key: String, season: String = "") -> float:
	var good: Dictionary = _goods.get(key, {})
	var category: String = str(good.get("category", "daily"))
	var demand: float = maxf(MIN_SUPPLY, float(_demand.get(key, 1.0)))
	var supply: float = maxf(MIN_SUPPLY, float(_supply.get(key, 1.0)))
	var ratio: float = demand / supply
	var elastic: float = BaselineScript.effective_elasticity(category)
	var sd_factor: float = pow(ratio, elastic * BaselineScript.PRICE_DEMAND_TO_PRICE)
	var season_mult: float = 1.0
	if bool(good.get("seasonal", false)) and season != "":
		season_mult = season_factor(season)
	var event_mult: float = float(_events.get(key, 1.0))
	var fluct: float = sd_factor * season_mult * event_mult
	return clampf(fluct, BaselineScript.PRICE_FLOOR_RATIO, BaselineScript.PRICE_CEIL_RATIO)

## 当前价格：基础价 × 波动因子 × 通胀累积。
func price(key: String, season: String = "") -> float:
	if not _goods.has(key):
		return 0.0
	return base_price(key) * _fluctuation(key, season) * _inflation_index

## 相对基础价的波动因子（有界，便于测试与展示）。
func price_factor(key: String, season: String = "") -> float:
	return _fluctuation(key, season)

## 交易冲击供需。influence 缺省为个体级别（影响微弱）；组织传 ORG_TRADE_INFLUENCE。
func apply_trade(key: String, quantity: float, is_buy: bool, influence: float = -1.0) -> void:
	if not _goods.has(key):
		return
	var scale: float = BaselineScript.INDIVIDUAL_TRADE_INFLUENCE if influence < 0.0 else influence
	var shift: float = absf(quantity) * scale
	if is_buy:
		_demand[key] = maxf(MIN_SUPPLY, float(_demand.get(key, 1.0)) + shift)
	else:
		_supply[key] = maxf(MIN_SUPPLY, float(_supply.get(key, 1.0)) + shift)

func supply(key: String) -> float:
	return float(_supply.get(key, 1.0))

func demand(key: String) -> float:
	return float(_demand.get(key, 1.0))


# =====================================================================
# 金融品种（GBM）
# =====================================================================

## 注册金融品种：初始价、年化漂移 mu、年化波动率 sigma；crypto 波动更高。
func register_stock(key: String, price: float, mu: float = -1.0, sigma: float = -1.0, crypto: bool = false) -> void:
	var drift: float = mu if mu >= 0.0 else BaselineScript.GBM_DRIFT_DEFAULT
	var vol: float = sigma if sigma >= 0.0 else BaselineScript.GBM_VOLATILITY_DEFAULT
	if crypto:
		vol = maxf(vol, BaselineScript.GBM_CRYPTO_VOLATILITY)
	drift = clampf(drift, BaselineScript.GBM_DRIFT_MIN, BaselineScript.GBM_DRIFT_MAX)
	vol = clampf(vol, BaselineScript.GBM_VOLATILITY_MIN, BaselineScript.GBM_VOLATILITY_MAX) if not crypto else vol
	_stocks[key] = {"price": maxf(BaselineScript.GBM_PRICE_FLOOR, price), "mu": drift, "sigma": vol}

func stock_price(key: String) -> float:
	return float((_stocks.get(key, {}) as Dictionary).get("price", 0.0))

func has_stock(key: String) -> bool:
	return _stocks.has(key)

## 按世界时间推进报价。dt_years 为经过年数；随机量来自传入 rng（同种子可复现）。
func advance_stock(key: String, dt_years: float, rng) -> float:
	var stock: Dictionary = _stocks.get(key, {})
	if stock.is_empty():
		return 0.0
	var stepped: float = gbm_step(
		float(stock.get("price", 1.0)),
		float(stock.get("mu", BaselineScript.GBM_DRIFT_DEFAULT)),
		float(stock.get("sigma", BaselineScript.GBM_VOLATILITY_DEFAULT)),
		dt_years, rng)
	stock["price"] = stepped
	_stocks[key] = stock
	return stepped


# =====================================================================
# 多国货币与浮动汇率
# =====================================================================

func reset_fx() -> void:
	_fx_rate.clear()
	for code in BaselineScript.CURRENCIES.keys():
		_fx_rate[code] = float((BaselineScript.CURRENCIES[code] as Dictionary).get("rate", 1.0))

func fx_rate(code: String) -> float:
	return maxf(FX_EPSILON, float(_fx_rate.get(code, 1.0)))

func has_currency(code: String) -> bool:
	return BaselineScript.CURRENCIES.has(code) or _fx_rate.has(code)

## 浮动汇率推进：向基准均值回归 + GBM 随机项。dt_years 为经过年数。
func advance_fx(rng, dt_years: float) -> void:
	var vol: float = BaselineScript.effective_economy_param("fx_annual_volatility", BaselineScript.FX_ANNUAL_VOLATILITY)
	var mean_rev: float = BaselineScript.effective_economy_param("fx_mean_reversion", BaselineScript.FX_MEAN_REVERSION)
	for code in _fx_rate.keys():
		if code == BaselineScript.CURRENCY_BASE:
			continue
		var base_rate: float = float((BaselineScript.CURRENCIES.get(code, {}) as Dictionary).get("rate", 1.0))
		var current: float = maxf(FX_EPSILON, float(_fx_rate[code]))
		var log_gap: float = log(current / base_rate)
		var drift: float = -mean_rev * log_gap * dt_years
		var diffusion: float = vol * sqrt(maxf(0.0, dt_years)) * normal_sample(rng)
		var stepped: float = current * exp(drift + diffusion)
		if not is_finite(stepped):
			stepped = current
		_fx_rate[code] = maxf(FX_EPSILON, stepped)

## 以世界记账单位计的价值（主币单位）。
func value_in_base(amount_minor: int, code: String) -> float:
	return (float(amount_minor) / float(BaselineScript.MONEY_MINOR_SCALE)) / fx_rate(code)

## 换汇：扣除价差与手续费后按汇率折算。返回分项，价值守恒：
##   value_in_base(amount_in) ≈ value_out_base + fee_value_base
func exchange(amount_minor: int, from_code: String, to_code: String, spread_bps: float = -1.0, fee_rate: float = -1.0) -> Dictionary:
	var spread: float = (BaselineScript.FX_SPREAD_BPS if spread_bps < 0.0 else spread_bps) / 10000.0
	var fee: float = BaselineScript.FX_FEE_RATE if fee_rate < 0.0 else fee_rate
	var scale: float = float(BaselineScript.MONEY_MINOR_SCALE)
	var amount_major: float = float(amount_minor) / scale
	var rate_from: float = fx_rate(from_code)
	var rate_to: float = fx_rate(to_code)
	var value_in: float = amount_major / rate_from
	var fee_ratio: float = maxf(0.0, spread + fee)
	var fee_major: float = amount_major * fee_ratio
	var net_major: float = maxf(0.0, amount_major - fee_major)
	var out_major: float = net_major / rate_from * rate_to
	var out_minor: int = int(round(out_major * scale))
	var fee_minor: int = int(round(fee_major * scale))
	return {
		"amount_out": out_minor,
		"fee": fee_minor,
		"rate": rate_to / rate_from,
		"value_in_base": value_in,
		"value_out_base": (float(out_minor) / scale) / rate_to,
		"fee_value_base": (float(fee_minor) / scale) / rate_from,
	}


# --- 序列化 ---

func to_dict() -> Dictionary:
	return {
		"goods": _goods.duplicate(true),
		"supply": _supply.duplicate(true),
		"demand": _demand.duplicate(true),
		"events": _events.duplicate(true),
		"inflation_index": _inflation_index,
		"stocks": _stocks.duplicate(true),
		"fx_rate": _fx_rate.duplicate(true),
	}

func from_dict(data: Dictionary) -> void:
	_goods = (data.get("goods", {}) as Dictionary).duplicate(true)
	_supply = (data.get("supply", {}) as Dictionary).duplicate(true)
	_demand = (data.get("demand", {}) as Dictionary).duplicate(true)
	_events = (data.get("events", {}) as Dictionary).duplicate(true)
	_inflation_index = float(data.get("inflation_index", 1.0))
	_stocks = (data.get("stocks", {}) as Dictionary).duplicate(true)
	_fx_rate = (data.get("fx_rate", {}) as Dictionary).duplicate(true)
	if _fx_rate.is_empty():
		reset_fx()
