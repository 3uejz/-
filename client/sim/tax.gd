class_name TaxSystem
extends RefCounted
## 税制（R15、R48；design D8）。
##
## 覆盖个人所得税超额累进（7 级、3%–45%）、企业所得税、增值税、消费税、
## 房产税、遗产税、印花税与社保缴费；按年汇算清缴。
## 计税与扣缴一律经 EconomySystem 转账，payer 与 gov 账户间货币守恒。
## 税表与税率默认集中在 client/sim/baseline.gd，均可由远程配置覆盖。

const BaselineScript = preload("res://sim/baseline.gd")


# --- 累进与比例计税 ---

## 通用超额累进：amount 按 brackets 的 upper 分档，upper < 0 表示无上限。
static func progressive_tax(amount: float, brackets: Array) -> float:
	if amount <= 0.0:
		return 0.0
	var remaining: float = amount
	var lower: float = 0.0
	var tax: float = 0.0
	for entry in brackets:
		var bracket: Dictionary = entry
		var upper: float = float(bracket.get("upper", -1.0))
		var rate: float = float(bracket.get("rate", 0.0))
		var band: float = remaining if upper < 0.0 else minf(remaining, upper - lower)
		if band > 0.0:
			tax += band * rate
			remaining -= band
		lower = upper if upper >= 0.0 else lower
		if remaining <= 0.0:
			break
	return tax

## 个人所得税：先减除标准扣除额，再按累进税表计税。
func income_tax(gross: float, deduction: float = -1.0) -> float:
	var ded: float = deduction if deduction >= 0.0 else float(BaselineScript.effective_economy_param(
		"tax_standard_deduction", BaselineScript.TAX_STANDARD_DEDUCTION))
	var taxable: float = maxf(0.0, gross - ded)
	return progressive_tax(taxable, BaselineScript.effective_income_brackets())

func corporate_tax(profit: float) -> float:
	var rate: float = float(BaselineScript.effective_economy_param("tax_corporate_rate", BaselineScript.TAX_CORPORATE_RATE))
	return maxf(0.0, profit) * rate

func vat(consumption: float) -> float:
	var rate: float = float(BaselineScript.effective_economy_param("tax_vat_rate", BaselineScript.TAX_VAT_RATE))
	return maxf(0.0, consumption) * rate

func consumption_tax(consumption: float) -> float:
	var rate: float = float(BaselineScript.effective_economy_param("tax_consumption_rate", BaselineScript.TAX_CONSUMPTION_RATE))
	return maxf(0.0, consumption) * rate

func property_tax(property_value: float, years: float = 1.0) -> float:
	var rate: float = float(BaselineScript.effective_economy_param("tax_property_rate_annual", BaselineScript.TAX_PROPERTY_RATE_ANNUAL))
	return maxf(0.0, property_value) * rate * maxf(0.0, years)

func inheritance_tax(estate: float) -> float:
	return progressive_tax(maxf(0.0, estate), BaselineScript.effective_inheritance_brackets())

func stamp_tax(value: float) -> float:
	var rate: float = float(BaselineScript.effective_economy_param("tax_stamp_rate", BaselineScript.TAX_STAMP_RATE))
	return maxf(0.0, value) * rate

func social_security(salary: float) -> float:
	var rate: float = float(BaselineScript.effective_economy_param("tax_social_security_rate", BaselineScript.TAX_SOCIAL_SECURITY_RATE))
	return maxf(0.0, salary) * rate

## 按税目计算应纳税额（金额单位与基础价一致）。
func liability(tax_type: String, base_amount: float) -> float:
	match tax_type:
		"income":
			return income_tax(base_amount)
		"corporate":
			return corporate_tax(base_amount)
		"vat":
			return vat(base_amount)
		"consumption":
			return consumption_tax(base_amount)
		"property":
			return property_tax(base_amount)
		"inheritance":
			return inheritance_tax(base_amount)
		"stamp":
			return stamp_tax(base_amount)
		"social_security":
			return social_security(base_amount)
		_:
			return 0.0


# --- 征缴（货币守恒）---

## 从 payer 扣缴税款入 gov 账户。返回实际征收额（分）；余额不足则征到可用现金为止。
func collect(economy, payer: String, gov: String, amount_minor: int, tax_type: String) -> int:
	if amount_minor <= 0:
		return 0
	var payable: int = mini(amount_minor, economy.cash(payer))
	if payable <= 0:
		return 0
	var ok: bool = economy.transfer(payer, gov, payable, "tax.%s" % tax_type)
	return payable if ok else 0

## 年汇算清缴：对多种税目计税并扣缴，返回明细与合计。
## 入参均为对应计税基数（income 为税前年收入，其余为对应金额）。
func settle_annual(economy, payer: String, gov: String, bases: Dictionary) -> Dictionary:
	var breakdown: Dictionary = {}
	var total: int = 0
	for tax_type in BaselineScript.TAX_TYPES:
		if not bases.has(tax_type):
			continue
		var base_amount: float = float(bases[tax_type])
		var due: float = liability(tax_type, base_amount)
		var due_minor: int = int(round(due))
		var collected: int = collect(economy, payer, gov, due_minor, tax_type)
		breakdown[tax_type] = {"due": due_minor, "collected": collected}
		total += collected
	return {"breakdown": breakdown, "total_collected": total}


# --- 避税/逃税（双路径，逃税有稽查风险）---

## 尝试逃税：按基础概率被稽查。未稽查则省下 amount；稽查则补缴并罚金（一倍罚款）。
func attempt_evasion(economy, payer: String, gov: String, amount_minor: int, rng, audit_chance: float = -1.0) -> Dictionary:
	var chance: float = audit_chance if audit_chance >= 0.0 else BaselineScript.TAX_EVASION_AUDIT_CHANCE
	var audited: bool = rng.next_float() < chance
	if not audited:
		return {"audited": false, "evaded": amount_minor, "penalty": 0, "collected": 0}
	var penalty: int = amount_minor
	var collected: int = collect(economy, payer, gov, amount_minor + penalty, "evasion_penalty")
	return {"audited": true, "evaded": 0, "penalty": penalty, "collected": collected}
