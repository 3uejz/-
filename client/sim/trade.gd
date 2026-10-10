class_name TradeSystem
extends RefCounted
## 国际贸易、海关与物流（R71；design D27）。
##
## 覆盖：
##   - 流程：询盘 → 签约 → 报关 → 检验检疫 → 运输 → 清关 → 交付；
##   - 关税与税费：完税价格 = 货值 + 运费 + 保险 + 其他；关税 = 完税价 × 税率；
##     增值税 = (完税价 + 关税) × 税率；金额均为最小货币单位非负整数，落地成本可核对；
##   - 结算与汇率：Incoterms、信用证/汇付/保理；汇率换算为确定性纯函数，可复现；
##   - 运输方式：海运/空运/铁路/快递/管道，含时效、费用、损耗、容量；
##   - 风险与壁垒：贸易战/制裁/战争导致加税、改航线与滞留；关税壁垒/配额/反倾销/原产地；
##   - 跨境服务：货代、报关行、海外仓、跨境电商；
##   - 边界：滞港、损毁、退运、汇率大幅波动亏损。
##
## 设计取舍：
##   - 单据为纯数据 Dictionary，便于存读档与 headless 测试；
##   - 关税与增值税全部走整数最小货币单位，round 到分，避免浮点误差；
##   - 汇率换算只依赖静态汇率表与显式覆盖，同输入必得同输出（可复现）；
##   - 风险事件只调整单据字段与费用，不引入随机，保证结算确定性。

const BaselineScript = preload("res://sim/baseline.gd")

const STAGES: Array = ["inquiry", "contract", "declaration", "inspection", "transport", "clearance", "delivery"]
const STAGE_NAMES: Dictionary = {
	"inquiry": "询盘", "contract": "签约", "declaration": "报关", "inspection": "检验检疫",
	"transport": "运输", "clearance": "清关", "delivery": "交付",
}

## 运输方式：时效/费用/损耗/容量。
const TRANSPORT_MODES: Dictionary = {
	"sea": {"name": "海运", "days": 30.0, "cost_per_ton": 2000, "loss_rate": 0.005, "capacity": 5000.0, "min_charge": 50000},
	"air": {"name": "空运", "days": 3.0, "cost_per_ton": 30000, "loss_rate": 0.001, "capacity": 500.0, "min_charge": 100000},
	"rail": {"name": "铁路", "days": 12.0, "cost_per_ton": 8000, "loss_rate": 0.004, "capacity": 2000.0, "min_charge": 80000},
	"express": {"name": "快递", "days": 5.0, "cost_per_ton": 50000, "loss_rate": 0.002, "capacity": 50.0, "min_charge": 20000},
	"pipeline": {"name": "管道", "days": 20.0, "cost_per_ton": 3000, "loss_rate": 0.001, "capacity": 10000.0, "min_charge": 200000},
}

const INCOTERMS: Array = ["EXW", "FOB", "CFR", "CIF", "DAP", "DDP"]
## Incoterms 责任划分：卖方是否承担 运费/保险/关税。
const INCOTERM_DUTIES: Dictionary = {
	"EXW": {"freight": false, "insurance": false, "duty": false},
	"FOB": {"freight": false, "insurance": false, "duty": false},
	"CFR": {"freight": true, "insurance": false, "duty": false},
	"CIF": {"freight": true, "insurance": true, "duty": false},
	"DAP": {"freight": true, "insurance": true, "duty": false},
	"DDP": {"freight": true, "insurance": true, "duty": true},
}

## 结算方式：风险与费率。
const SETTLEMENTS: Dictionary = {
	"letter_of_credit": {"name": "信用证", "risk": 0.1, "fee_rate": 0.01},
	"remittance": {"name": "汇付", "risk": 0.5, "fee_rate": 0.003},
	"factoring": {"name": "保理", "risk": 0.2, "fee_rate": 0.02},
	"open_account": {"name": "赊销", "risk": 0.7, "fee_rate": 0.0},
}

const BARRIERS: Array = ["tariff", "quota", "anti_dumping", "origin"]
const RISK_EVENTS: Array = ["trade_war", "sanction", "war"]
const SERVICES: Array = ["freight_forwarder", "customs_broker", "overseas_warehouse", "cross_border_ecommerce"]

const DEFAULT_TARIFF_RATE: float = BaselineScript.TRADE_DEFAULT_TARIFF_RATE
const DEFAULT_VAT_RATE: float = BaselineScript.TRADE_DEFAULT_VAT_RATE


# --- 数据表 ---

func stage_names() -> Dictionary:
	return STAGE_NAMES.duplicate(true)


func transport_modes() -> Array:
	return TRANSPORT_MODES.keys()


func transport_def(mode: String) -> Dictionary:
	if not TRANSPORT_MODES.has(mode):
		return {}
	return (TRANSPORT_MODES[mode] as Dictionary).duplicate(true)


func incoterm_duties(incoterm: String) -> Dictionary:
	if not INCOTERM_DUTIES.has(incoterm):
		return {}
	return (INCOTERM_DUTIES[incoterm] as Dictionary).duplicate(true)


func settlement_def(method: String) -> Dictionary:
	if not SETTLEMENTS.has(method):
		return {}
	return (SETTLEMENTS[method] as Dictionary).duplicate(true)


# --- 单据 ---

func new_shipment(opts: Dictionary = {}) -> Dictionary:
	return {
		"id": str(opts.get("id", "shipment")),
		"currency": str(opts.get("currency", BaselineScript.CURRENCY_BASE)),
		"goods_value": maxi(0, int(opts.get("goods_value", 0))),
		"freight": maxi(0, int(opts.get("freight", 0))),
		"insurance": maxi(0, int(opts.get("insurance", 0))),
		"other_fees": maxi(0, int(opts.get("other_fees", 0))),
		"tariff_rate": clampf(float(opts.get("tariff_rate", DEFAULT_TARIFF_RATE)), 0.0, 1.0),
		"vat_rate": clampf(float(opts.get("vat_rate", DEFAULT_VAT_RATE)), 0.0, 1.0),
		"quantity_ton": maxf(0.0, float(opts.get("quantity_ton", 1.0))),
		"origin": str(opts.get("origin", "")),
		"destination": str(opts.get("destination", "")),
		"stage": STAGES[0],
		"incoterm": "",
		"settlement": "",
		"transport": "",
		"barriers": [],
		"risk_events": [],
		"services": [],
		"hedged": false,
		"hedge_rate": 0.0,
		"quota": -1.0,
		"origin_certificate": false,
		"history": [],
	}


# --- 运输估算 ---

## 运输报价：费用取 最低收费 与 吨×单位运费 的较大者；损耗按吨位与损耗率计。
func estimate_freight(mode: String, ton: float, opts: Dictionary = {}) -> Dictionary:
	if not TRANSPORT_MODES.has(mode):
		return {"ok": false, "reason": "unknown_mode"}
	var def: Dictionary = TRANSPORT_MODES[mode]
	var quantity: float = maxf(0.0, ton)
	var freight: int = int(round(maxf(float(def["min_charge"]), quantity * float(def["cost_per_ton"]))))
	var loss_ton: float = quantity * float(def["loss_rate"])
	var over_capacity: bool = quantity > float(def["capacity"])
	var days: float = float(def["days"]) * float(opts.get("route_factor", 1.0))
	return {
		"ok": not over_capacity, "mode": mode, "mode_name": str(def["name"]),
		"days": days, "freight": freight, "loss_ton": loss_ton, "loss_rate": float(def["loss_rate"]),
		"capacity": float(def["capacity"]), "over_capacity": over_capacity,
	}


# --- 关税与税费结算（关键）---

## 计算完税价格、关税、增值税与落地成本。全部为最小货币单位非负整数。
##   完税价格 = 货值 + 运费 + 保险 + 其他费用
##   关税     = round(完税价格 × 关税率)
##   增值税   = round((完税价格 + 关税) × 增值税率)
##   落地成本 = 完税价格 + 关税 + 增值税
func calculate_duties(shipment: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var goods: int = maxi(0, int(opts.get("goods_value", shipment.get("goods_value", 0))))
	var freight: int = maxi(0, int(opts.get("freight", shipment.get("freight", 0))))
	var insurance: int = maxi(0, int(opts.get("insurance", shipment.get("insurance", 0))))
	var other: int = maxi(0, int(opts.get("other_fees", shipment.get("other_fees", 0))))
	var tariff_rate: float = clampf(float(opts.get("tariff_rate", shipment.get("tariff_rate", DEFAULT_TARIFF_RATE))), 0.0, 1.0)
	var vat_rate: float = clampf(float(opts.get("vat_rate", shipment.get("vat_rate", DEFAULT_VAT_RATE))), 0.0, 1.0)
	var dutiable: int = goods + freight + insurance + other
	var tariff: int = int(round(float(dutiable) * tariff_rate))
	var vat: int = int(round(float(dutiable + tariff) * vat_rate))
	var total_tax: int = tariff + vat
	var landed: int = dutiable + total_tax
	return {
		"ok": true, "currency": str(shipment.get("currency", BaselineScript.CURRENCY_BASE)),
		"goods_value": goods, "freight": freight, "insurance": insurance, "other_fees": other,
		"dutiable_value": dutiable,
		"tariff_rate": tariff_rate, "tariff": tariff,
		"vat_rate": vat_rate, "vat": vat,
		"total_tax": total_tax, "landed_cost": landed,
		"non_negative": tariff >= 0 and vat >= 0 and landed >= 0,
	}


## 报关并落税：把关税/增值税写回单据，进入报关阶段。
func declare_customs(shipment: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var duties: Dictionary = calculate_duties(shipment, opts)
	shipment["duties"] = duties
	shipment["stage"] = "declaration"
	return duties


# --- 汇率与结算 ---

func fx_rate(code: String) -> float:
	var def: Dictionary = BaselineScript.CURRENCIES.get(code, {})
	if def.is_empty():
		return 0.0
	return maxf(1e-9, float(def.get("rate", 1.0)))


func has_currency(code: String) -> bool:
	return BaselineScript.CURRENCIES.has(code)


## 汇率换算：value_base = amount / rate_from；amount_out = round(value_base × rate_to)。
## 纯确定性函数，同输入必得同输出。
func convert(amount_minor: int, from_code: String, to_code: String) -> Dictionary:
	var rate_from: float = fx_rate(from_code)
	var rate_to: float = fx_rate(to_code)
	if rate_from <= 0.0 or rate_to <= 0.0:
		return {"ok": false, "reason": "unknown_currency"}
	var value_base: float = float(amount_minor) / rate_from
	var out_minor: int = int(round(value_base * rate_to))
	return {
		"ok": true, "amount_in": int(amount_minor), "amount_out": out_minor,
		"from": from_code, "to": to_code, "rate": rate_to / rate_from,
	}


## 按结算方式计手续费。
func settlement_fee(amount_minor: int, method: String) -> Dictionary:
	if not SETTLEMENTS.has(method):
		return {"ok": false, "reason": "unknown_settlement"}
	var fee: int = int(round(float(maxi(0, amount_minor)) * float((SETTLEMENTS[method] as Dictionary)["fee_rate"])))
	return {"ok": true, "method": method, "fee": fee, "net": maxi(0, amount_minor) - fee}


## 汇率对冲：锁定一个汇率；已对冲则按锁定价结算损益。
func hedge_fx(shipment: Dictionary, rate: float) -> Dictionary:
	shipment["hedged"] = true
	shipment["hedge_rate"] = maxf(1e-9, rate)
	return {"ok": true, "hedged": true, "hedge_rate": float(shipment["hedge_rate"])}


## 汇率波动损益：已对冲则无损失；未对冲按新汇率对货值的差额。
func fx_loss(shipment: Dictionary, new_rate: float) -> Dictionary:
	var goods: int = maxi(0, int(shipment.get("goods_value", 0)))
	if bool(shipment.get("hedged", false)):
		return {"ok": true, "hedged": true, "pnl": 0}
	var reference: float = fx_rate(str(shipment.get("currency", BaselineScript.CURRENCY_BASE)))
	var pnl: int = int(round(float(goods) * (reference / maxf(1e-9, new_rate) - 1.0)))
	return {"ok": true, "hedged": false, "pnl": pnl}


# --- 贸易壁垒与风险 ---

## 施加壁垒：加税/配额/反倾销/原产地规则，影响关税与可成交量。
func apply_barrier(shipment: Dictionary, barrier: String, opts: Dictionary = {}) -> Dictionary:
	if not BARRIERS.has(barrier):
		return {"ok": false, "reason": "unknown_barrier"}
	var barriers: Array = shipment["barriers"]
	barriers.append(barrier)
	var detail: Dictionary = {"ok": true, "barrier": barrier}
	match barrier:
		"tariff":
			var add: float = clampf(float(opts.get("add_rate", 0.05)), 0.0, 1.0)
			shipment["tariff_rate"] = clampf(float(shipment.get("tariff_rate", DEFAULT_TARIFF_RATE)) + add, 0.0, 1.0)
			detail["tariff_rate"] = float(shipment["tariff_rate"])
		"quota":
			var limit: float = maxf(0.0, float(opts.get("limit", 0.0)))
			shipment["quota"] = limit
			detail["quota"] = limit
			detail["exceeds_quota"] = float(shipment.get("quantity_ton", 0.0)) > limit
		"anti_dumping":
			var duty: float = clampf(float(opts.get("add_rate", 0.20)), 0.0, 2.0)
			shipment["anti_dumping_rate"] = duty
			detail["anti_dumping_rate"] = duty
		"origin":
			shipment["origin_certificate"] = bool(opts.get("certificate", false))
			detail["certificate_ok"] = bool(shipment["origin_certificate"])
	return detail


## 风险事件：加税、改航线、滞留。返回对时效/关税/费用的修正。
func risk_event(shipment: Dictionary, event: String, opts: Dictionary = {}) -> Dictionary:
	if not RISK_EVENTS.has(event):
		return {"ok": false, "reason": "unknown_event"}
	var events: Array = shipment["risk_events"]
	events.append(event)
	var result: Dictionary = {"ok": true, "event": event, "delay_days": 0.0, "extra_cost": 0, "detained": false}
	match event:
		"trade_war":
			shipment["tariff_rate"] = clampf(float(shipment.get("tariff_rate", DEFAULT_TARIFF_RATE)) + 0.25, 0.0, 2.0)
			result["delay_days"] = 5.0
			result["extra_cost"] = 50000
		"sanction":
			result["delay_days"] = 15.0
			result["extra_cost"] = 200000
			result["detained"] = true
		"war":
			result["delay_days"] = 30.0
			result["extra_cost"] = 500000
			result["rerouted"] = true
			result["detained"] = bool(opts.get("detained", false))
	return result


# --- 跨境服务 ---

func add_service(shipment: Dictionary, service: String, opts: Dictionary = {}) -> Dictionary:
	if not SERVICES.has(service):
		return {"ok": false, "reason": "unknown_service"}
	var services: Array = shipment["services"]
	services.append(service)
	var cost: int = 0
	match service:
		"freight_forwarder":
			cost = 20000
		"customs_broker":
			cost = 30000
		"overseas_warehouse":
			cost = 100000
		"cross_border_ecommerce":
			cost = 50000
	shipment["other_fees"] = maxi(0, int(shipment.get("other_fees", 0))) + cost
	return {"ok": true, "service": service, "cost": cost, "other_fees": int(shipment["other_fees"])}


# --- 流程推进 ---

func advance_stage(shipment: Dictionary) -> Dictionary:
	var idx: int = STAGES.find(str(shipment.get("stage", STAGES[0])))
	if idx < 0 or idx >= STAGES.size() - 1:
		return {"ok": false, "reason": "at_end"}
	shipment["stage"] = STAGES[idx + 1]
	(shipment["history"] as Array).append(shipment["stage"])
	return {"ok": true, "stage": str(shipment["stage"]), "stage_name": str(STAGE_NAMES[shipment["stage"]])}


## 检验检疫：不合格则退回或整改。
func quarantine_inspect(shipment: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var passed: bool = bool(opts.get("passed", true))
	shipment["stage"] = "inspection"
	shipment["inspection_passed"] = passed
	return {"ok": true, "passed": passed, "action": "pass" if passed else "return_or_rectify"}


func clear_customs(shipment: Dictionary) -> Dictionary:
	shipment["stage"] = "clearance"
	return {"ok": true, "stage": "clearance", "duration_days": float(shipment.get("clearance_days", 2.0))}


func deliver(shipment: Dictionary) -> Dictionary:
	shipment["stage"] = "delivery"
	return {"ok": true, "stage": "delivery", "delivered": true}


# --- 边界情况 ---

## 滞港费：按日累计。
func settle_demurrage(days: float, daily_rate: int) -> int:
	return int(round(maxf(0.0, days) * float(maxi(0, daily_rate))))


## 货物损毁：按损耗率折损货值。
func damage_loss(shipment: Dictionary, loss_rate: float) -> Dictionary:
	var rate: float = clampf(loss_rate, 0.0, 1.0)
	var lost: int = int(round(float(maxi(0, int(shipment.get("goods_value", 0)))) * rate))
	shipment["goods_value"] = maxi(0, int(shipment.get("goods_value", 0)) - lost)
	return {"ok": true, "loss": lost, "remaining_value": int(shipment["goods_value"])}


## 退运：标记退运并给出退运费用。
func return_shipment(shipment: Dictionary, reason: String = "rejected") -> Dictionary:
	shipment["returned"] = true
	shipment["return_reason"] = reason
	return {"ok": true, "returned": true, "reason": reason, "return_cost": int(shipment.get("freight", 0))}


func to_dict(shipment: Dictionary) -> Dictionary:
	return shipment.duplicate(true)


func from_dict(data: Dictionary) -> Dictionary:
	return data.duplicate(true)
