class_name OrderSystem
extends RefCounted
## 网络消费与订单（R49.7–R49.9；design D9）。
##
## 职责：
##   - 渠道：电商、直播带货、外卖、二手平台、团购、跨境购、网约车、在线教育、流媒体订阅、数字内容；
##   - 订单状态机：created→paid→(shipping→)delivered→completed，含 refunding→refunded 与 cancelled；
##   - 履约：实物渠道按物流 tick 送达，即时渠道下单即履约；生成订单记录；
##   - 售后退换、投诉（联动 R84）、假货标记；
##   - 订阅按月经 EconomySystem 扣费，余额不足则停用；
##   - 消费心理：冲动消费/广告影响/攀比的强度因子。
##
## 约定：金额为最小货币单位整数；支付/退款走 EconomySystem，货币守恒由其保证。

const STATUS_CREATED: String = "created"
const STATUS_PAID: String = "paid"
const STATUS_SHIPPING: String = "shipping"
const STATUS_DELIVERED: String = "delivered"
const STATUS_COMPLETED: String = "completed"
const STATUS_REFUNDING: String = "refunding"
const STATUS_REFUNDED: String = "refunded"
const STATUS_CANCELLED: String = "cancelled"

const RETURN_WINDOW_DAYS: int = 7
const AUTO_COMPLETE_DAYS: int = 3
const MONTH_DAYS: int = 30

## 渠道配置：instant=即时履约；eta_days=物流天数；fee=配送费；discount=折扣；tariff=关税；psych=消费心理权重。
const CHANNEL_CONFIG: Dictionary = {
	"ecommerce": {"instant": false, "eta_days": 3, "fee": 0, "discount": 0.0, "tariff": 0.0, "psych": 0.2},
	"livestream": {"instant": false, "eta_days": 4, "fee": 0, "discount": 0.1, "tariff": 0.0, "psych": 0.8},
	"delivery": {"instant": false, "eta_days": 1, "fee": 300, "discount": 0.0, "tariff": 0.0, "psych": 0.5},
	"secondhand": {"instant": false, "eta_days": 3, "fee": 0, "discount": 0.5, "tariff": 0.0, "psych": 0.1},
	"group_buy": {"instant": false, "eta_days": 4, "fee": 0, "discount": 0.2, "tariff": 0.0, "psych": 0.3},
	"crossborder": {"instant": false, "eta_days": 10, "fee": 0, "discount": 0.0, "tariff": 0.1, "psych": 0.4},
	"rideshare": {"instant": true, "eta_days": 0, "fee": 0, "discount": 0.0, "tariff": 0.0, "psych": 0.0},
	"online_edu": {"instant": true, "eta_days": 0, "fee": 0, "discount": 0.0, "tariff": 0.0, "psych": 0.0},
	"streaming": {"instant": true, "eta_days": 0, "fee": 0, "discount": 0.0, "tariff": 0.0, "psych": 0.0},
	"digital": {"instant": true, "eta_days": 0, "fee": 0, "discount": 0.0, "tariff": 0.0, "psych": 0.1},
}

var _seq: int = 0


func channels() -> Array:
	var out: Array = CHANNEL_CONFIG.keys()
	out.sort()
	return out


func is_channel(channel: String) -> bool:
	return CHANNEL_CONFIG.has(channel)


func is_instant(channel: String) -> bool:
	return bool((CHANNEL_CONFIG.get(channel, {}) as Dictionary).get("instant", false))


# --- 下单与定价 ---

## 下单：计算金额（单价×数量×(1−折扣)+配送费+关税），状态为 created。
## unit_price 为最小货币单位；opts.ad_multiplier 放大冲动消费金额（仅影响定价展示，不改变单价逻辑）。
func place_order(channel: String, def_id: String, qty: int, day: int, unit_price: int, opts: Dictionary = {}) -> Dictionary:
	if not is_channel(channel) or qty <= 0:
		return {}
	var cfg: Dictionary = CHANNEL_CONFIG[channel]
	var subtotal: int = maxi(0, unit_price) * qty
	var discount: int = int(round(float(subtotal) * float(cfg.get("discount", 0.0))))
	var fee: int = int(cfg.get("fee", 0))
	var tariff: int = int(round(float(subtotal) * float(cfg.get("tariff", 0.0))))
	var amount: int = subtotal - discount + fee + tariff
	_seq += 1
	return {
		"id": "order.%d" % _seq,
		"channel": channel,
		"def_id": def_id,
		"quantity": qty,
		"unit_price": maxi(0, unit_price),
		"subtotal": subtotal,
		"discount": discount,
		"shipping_fee": fee,
		"tariff": tariff,
		"amount": amount,
		"status": STATUS_CREATED,
		"created_day": day,
		"eta_day": 0,
		"delivered_day": -1,
		"completed_day": -1,
		"seller": str(opts.get("seller", "platform")),
		"counterfeit": false,
		"complaints": 0,
	}


## 支付：转账给卖家；即时渠道直接 delivered，实物渠道进入 shipping。返回是否成功。
func pay(order: Dictionary, economy, account: String, day: int = -1) -> bool:
	if str(order.get("status", "")) != STATUS_CREATED:
		return false
	if economy == null:
		return false
	var amount: int = int(order.get("amount", 0))
	var seller: String = str(order.get("seller", "platform"))
	if amount > 0 and economy.cash(account) < amount:
		return false
	if amount > 0 and not economy.transfer(account, seller, amount, "order:" + str(order.get("id", ""))):
		return false
	var channel: String = str(order.get("channel", ""))
	var d: int = day if day >= 0 else int(order.get("created_day", 0))
	if is_instant(channel):
		order["status"] = STATUS_DELIVERED
		order["delivered_day"] = d
	else:
		order["status"] = STATUS_SHIPPING
		order["eta_day"] = d + int((CHANNEL_CONFIG[channel] as Dictionary).get("eta_days", 3))
	return true


# --- 履历推进 ---

## 推进单个订单状态；返回新状态。
func advance(order: Dictionary, day: int) -> String:
	var status: String = str(order.get("status", ""))
	if status == STATUS_SHIPPING and day >= int(order.get("eta_day", day)):
		order["status"] = STATUS_DELIVERED
		order["delivered_day"] = day
		status = STATUS_DELIVERED
	if status == STATUS_DELIVERED and int(order.get("delivered_day", -1)) >= 0:
		if day >= int(order["delivered_day"]) + AUTO_COMPLETE_DAYS:
			order["status"] = STATUS_COMPLETED
			order["completed_day"] = day
	return str(order.get("status", ""))


## 批量推进；返回本日完成的订单列表。
func tick(orders: Array, day: int) -> Array:
	var completed: Array = []
	for o in orders:
		if o is Dictionary and advance(o, day) == STATUS_COMPLETED:
			completed.append(o)
	return completed


# --- 售后 ---

## 申请退货：仅 delivered/completed 且未过退货窗口。
func request_return(order: Dictionary, day: int) -> Dictionary:
	var status: String = str(order.get("status", ""))
	if status != STATUS_DELIVERED and status != STATUS_COMPLETED:
		return {"ok": false, "reason": "not_returnable"}
	var delivered: int = int(order.get("delivered_day", -1))
	if delivered < 0 or day > delivered + RETURN_WINDOW_DAYS:
		return {"ok": false, "reason": "window_expired"}
	order["status"] = STATUS_REFUNDING
	return {"ok": true}


## 同意退款：从 seller 退回 account，订单转 refunded。
func approve_refund(order: Dictionary, economy, account: String) -> Dictionary:
	if str(order.get("status", "")) != STATUS_REFUNDING:
		return {"ok": false, "reason": "not_refunding"}
	var amount: int = int(order.get("amount", 0))
	var seller: String = str(order.get("seller", "platform"))
	if economy != null:
		economy.transfer(seller, account, amount, "refund:" + str(order.get("id", "")))
	order["status"] = STATUS_REFUNDED
	return {"ok": true, "refund": amount}


## 投诉/维权：累加投诉次数（联动 R84 消费维权）。
func complain(order: Dictionary) -> int:
	order["complaints"] = int(order.get("complaints", 0)) + 1
	return int(order["complaints"])


## 假货判定：roll ∈ [0,1) 小于概率则标记假货。
func mark_counterfeit(order: Dictionary, roll: float, chance: float = 0.05) -> bool:
	var fake: bool = roll < chance
	order["counterfeit"] = fake
	return fake


# --- 订阅 ---

## 订阅：记录渠道、方案、月费与起始日。
func subscribe(channel: String, plan_id: String, monthly_fee: int, day: int) -> Dictionary:
	if not is_channel(channel) or monthly_fee <= 0:
		return {}
	_seq += 1
	return {
		"id": "sub.%d" % _seq,
		"channel": channel,
		"plan_id": plan_id,
		"monthly_fee": monthly_fee,
		"started_day": day,
		"last_billed_month": -1,
		"active": true,
	}


## 按月扣费：到期则扣款；余额不足则停用。返回 {ok, charged, reason}。
func bill_subscription(sub: Dictionary, economy, account: String, day: int) -> Dictionary:
	if not bool(sub.get("active", false)):
		return {"ok": false, "charged": 0, "reason": "inactive"}
	var month_index: int = int(day / MONTH_DAYS)
	if month_index <= int(sub.get("last_billed_month", -1)):
		return {"ok": true, "charged": 0, "reason": "not_due"}
	var fee: int = int(sub.get("monthly_fee", 0))
	if economy == null or economy.cash(account) < fee:
		sub["active"] = false
		return {"ok": false, "charged": 0, "reason": "suspended"}
	economy.add_money(account, -fee, "subscription:" + str(sub.get("plan_id", "")))
	sub["last_billed_month"] = month_index
	return {"ok": true, "charged": fee, "reason": "billed"}


# --- 消费心理 ---

## 冲动消费强度因子：基础 1.0 + 渠道权重 × 广告暴露，clamp 到 [1.0, 3.0]。
func impulse_factor(channel: String, ad_exposure: float) -> float:
	var psych: float = float((CHANNEL_CONFIG.get(channel, {}) as Dictionary).get("psych", 0.0))
	return clampf(1.0 + psych * maxf(0.0, ad_exposure), 1.0, 3.0)


## 攀比强度：相对参照群体收入越低越强，clamp 到 [0,1]。
func conspicuous_factor(income: float, reference_income: float) -> float:
	if reference_income <= 0.0:
		return 0.0
	return clampf(1.0 - income / reference_income, 0.0, 1.0)
