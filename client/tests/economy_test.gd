extends "res://tests/test_base.gd"
## 经济、金融、税制与宏观测试（任务 10；10.1 金钱守恒与税务守恒，10.2 价格有界/货币换算守恒/通胀单调）。
## 覆盖：统一 add_money 与账本守恒、转账守恒、银行存款守恒、税制累进与征缴守恒、
##       价格分层有界与确定性、个体/组织交易影响差异、GBM 可复现、
##       多国货币换算守恒、通胀单调、宏观有界与传导、杠杆强平、保险彩票、远程覆盖。

const EconomyScript = preload("res://sim/economy.gd")
const MarketScript = preload("res://sim/market.gd")
const BankScript = preload("res://sim/bank.gd")
const TaxScript = preload("res://sim/tax.gd")
const BaselineScript = preload("res://sim/baseline.gd")
const RngScript = preload("res://sim/rng.gd")

func _suite_name() -> String:
	return "economy"

func run_tests() -> void:
	BaselineScript.clear_overrides()
	_test_money_conservation()
	_test_transfer_and_insufficient()
	_test_bank_deposit_conservation()
	_test_income_tax_progressive()
	_test_tax_conservation()
	_test_settle_annual_conservation()
	_test_price_bounded()
	_test_price_deterministic()
	_test_trade_influence()
	_test_gbm_reproducible()
	_test_exchange_conservation()
	_test_inflation_monotonic()
	_test_macro_bounded_and_transmission()
	_test_bank_loan_and_credit()
	_test_margin_liquidation()
	_test_insurance_and_lottery()
	_test_remote_override()
	BaselineScript.clear_overrides()


# --- 10.1 金钱守恒 ---

func _test_money_conservation() -> void:
	var e = EconomyScript.new(1)
	e.open_account("a", 100000)
	e.open_account("b", 0)
	var total0: int = e.total_money()
	check_eq(total0, 100000, "初始货币总量")

	for i in range(50):
		e.transfer("a", "b", 100, "loop")
	check_eq(e.total_money(), total0, "连续转账后货币总量不变")
	check(e.is_conserved(), "账本守恒核验通过")

	# 发行与回收：总量按实际投放增减。
	e.issue_money("a", 5000, "issue")
	check_eq(e.total_money(), total0 + 5000, "发行增加货币总量")
	e.burn_money("a", 2000, "burn")
	check_eq(e.total_money(), total0 + 3000, "回收减少货币总量")

	# 账本累计等于货币总量相对初始值的变化。
	check_eq(e.ledger_sum(), e.total_money() - e.initial_money(), "账本累计等于货币总量变化")
	check(e.is_conserved(), "发行回收后仍守恒")


func _test_transfer_and_insufficient() -> void:
	var e = EconomyScript.new(2)
	e.open_account("x", 1000)
	e.open_account("y", 0)
	check(not e.transfer("y", "x", 500), "余额不足转账被拒绝")
	check_eq(e.total_money(), 1000, "拒绝后总量不变")
	check(e.transfer("x", "y", 400), "余额充足转账成功")
	check_eq(e.cash("x"), 600, "转出方扣减")
	check_eq(e.cash("y"), 400, "转入方增加")
	check_eq(e.cash("x") + e.cash("y"), 1000, "双方之和守恒")


func _test_bank_deposit_conservation() -> void:
	var e = EconomyScript.new(3)
	e.open_account("p", 10000)
	var bank = BankScript.new(3)
	var before: int = e.total_money()
	check(bank.deposit(e, "p", 4000), "存款成功")
	check_eq(e.cash("p"), 6000, "存款后现金减少")
	check_eq(e.bank("p"), 4000, "存款账户增加")
	check_eq(e.total_money(), before, "存款不改变货币总量")
	check(bank.withdraw(e, "p", 1500), "取款成功")
	check_eq(e.cash("p"), 7500, "取款后现金增加")
	check_eq(e.bank("p"), 2500, "取款后存款减少")
	check_eq(e.total_money(), before, "取款不改变货币总量")


# --- 10.1 税务守恒 ---

func _test_income_tax_progressive() -> void:
	var tax = TaxScript.new()
	check_eq(BaselineScript.effective_income_brackets().size(), 7, "个税 7 级超额累进")
	var rates: Array = []
	for b in BaselineScript.effective_income_brackets():
		rates.append(float((b as Dictionary)["rate"]))
	check_near(rates[0], 0.03, 1e-9, "最低税率 3%")
	check_near(rates[6], 0.45, 1e-9, "最高税率 45%")

	# gross=200000，减除 6000 后应税 194000：1080 + 10800 + 10000 = 21880。
	check_near(tax.income_tax(200000.0), 21880.0, 1e-6, "个税累进计算正确")
	check(tax.income_tax(200000.0) >= tax.income_tax(100000.0), "个税随收入单调不减")
	check_near(tax.income_tax(6000.0), 0.0, 1e-6, "未超起征点不纳税")
	check_near(tax.income_tax(36000.0, 0.0), 1080.0, 1e-6, "自定义扣除额计税")

	# 遗产税：1000000 中 500000 适用 10% = 50000。
	check_near(tax.inheritance_tax(1000000.0), 50000.0, 1e-6, "遗产税累进正确")


func _test_tax_conservation() -> void:
	var e = EconomyScript.new(4)
	e.open_account("alice", 100000000)
	e.open_account("gov", 0)
	var before: int = e.total_money()
	var tax = TaxScript.new()

	var due_minor: int = int(round(tax.income_tax(200000.0)))
	var collected: int = tax.collect(e, "alice", "gov", due_minor, "income")
	check_eq(collected, due_minor, "扣缴额等于应纳税额")
	check_eq(e.cash("gov"), due_minor, "税款入国库")
	check_eq(e.total_money(), before, "征税不改变货币总量")
	check(e.is_conserved(), "征税后账本守恒")

	# 应纳大于可用现金时，只征到可用额度。
	var e2 = EconomyScript.new(5)
	e2.open_account("poor", 100)
	e2.open_account("gov2", 0)
	var got: int = tax.collect(e2, "poor", "gov2", 100000, "income")
	check_eq(got, 100, "余额不足时按可用现金征收")
	check_eq(e2.cash("poor"), 0, "纳税人现金清零")
	check_eq(e2.total_money(), 100, "部分征收仍守恒")


func _test_settle_annual_conservation() -> void:
	var e = EconomyScript.new(6)
	e.open_account("biz", 100000000)
	e.open_account("treasury", 0)
	var before: int = e.total_money()
	var tax = TaxScript.new()
	var result: Dictionary = tax.settle_annual(e, "biz", "treasury", {
		"income": 200000.0,
		"corporate": 50000.0,
		"vat": 100000.0,
		"consumption": 100000.0,
		"property": 300000.0,
		"inheritance": 1000000.0,
		"stamp": 100000.0,
		"social_security": 200000.0,
	})
	var breakdown: Dictionary = result["breakdown"]
	check_eq(breakdown.size(), 8, "覆盖 8 个税目")
	var sum_collected: int = 0
	for key in breakdown.keys():
		sum_collected += int((breakdown[key] as Dictionary)["collected"])
	check_eq(sum_collected, int(result["total_collected"]), "明细合计等于总额")
	check_eq(e.total_money(), before, "汇算清缴后货币总量不变")
	check(e.is_conserved(), "汇算清缴后账本守恒")
	check_eq(e.cash("treasury"), int(result["total_collected"]), "国库收到全部税款")


# --- 10.2 价格有界与确定性 ---

func _test_price_bounded() -> void:
	var m = MarketScript.new()
	m.register_good("lux", 100.0, "luxury")
	# 需求暴涨：波动因子被上限截断。
	m.apply_trade("lux", 1.0e12, true, 1.0)
	check_near(m.price_factor("lux"), BaselineScript.PRICE_CEIL_RATIO, 1e-9, "价格上限截断")
	check(m.price("lux") <= 100.0 * BaselineScript.PRICE_CEIL_RATIO + 1e-6, "价格不超过上限")
	# 供给暴增：波动因子被下限截断。
	m.apply_trade("lux", 1.0e15, false, 1.0)
	check_near(m.price_factor("lux"), BaselineScript.PRICE_FLOOR_RATIO, 1e-9, "价格下限截断")
	check(m.price("lux") >= 100.0 * BaselineScript.PRICE_FLOOR_RATIO - 1e-6, "价格不低于下限")

	# 季节与事件修正仍落在上下限内。
	m.set_event_modifier("lux", 3.0)
	m.set_inflation_index(1.2)
	var p: float = m.price("lux", "winter")
	check(p >= 100.0 * 1.2 * BaselineScript.PRICE_FLOOR_RATIO - 1e-6, "叠加季节事件后仍有下界")
	check(p <= 100.0 * 1.2 * BaselineScript.PRICE_CEIL_RATIO + 1e-6, "叠加季节事件后仍有上界")


func _test_price_deterministic() -> void:
	var a = MarketScript.new()
	var b = MarketScript.new()
	for m in [a, b]:
		m.register_good("rice", 8.0, "necessity", true)
		m.apply_trade("rice", 5000.0, true, 1e-4)
		m.set_inflation_index(1.1)
	check_near(a.price("rice", "autumn"), b.price("rice", "autumn"), 1e-12, "同状态价格可复现")
	check_near(a.price_factor("rice"), b.price_factor("rice"), 1e-12, "同状态波动因子可复现")


func _test_trade_influence() -> void:
	var individual = MarketScript.new()
	individual.register_good("gold", 100.0, "luxury")
	var p0: float = individual.price("gold")
	individual.apply_trade("gold", 1000.0, true)
	var p1: float = individual.price("gold")

	var org = MarketScript.new()
	org.register_good("gold", 100.0, "luxury")
	var q0: float = org.price("gold")
	org.apply_trade("gold", 1000.0, true, BaselineScript.ORG_TRADE_INFLUENCE)
	var q1: float = org.price("gold")

	check(absf((p1 - p0) / p0) < 1e-3, "个体交易对价格影响微弱")
	check((q1 - q0) > (p1 - p0) * 100.0, "组织交易显著推动价格")


# --- GBM 与货币换算 ---

func _test_gbm_reproducible() -> void:
	var m1 = MarketScript.new()
	var m2 = MarketScript.new()
	m1.register_stock("stock", 100.0)
	m2.register_stock("stock", 100.0)
	var r1 = RngScript.new(4242)
	var r2 = RngScript.new(4242)
	for i in range(30):
		m1.advance_stock("stock", 1.0 / 365.0, r1)
		m2.advance_stock("stock", 1.0 / 365.0, r2)
	check_near(m1.stock_price("stock"), m2.stock_price("stock"), 1e-9, "同种子 GBM 报价一致")
	check(m1.stock_price("stock") > 0.0, "GBM 报价恒为正")

	var r3 = RngScript.new(9999)
	m1.advance_stock("stock", 1.0, r3)
	check(m1.stock_price("stock") > 0.0, "GBM 长期推进仍为正")


func _test_exchange_conservation() -> void:
	var m = MarketScript.new()
	var r: Dictionary = m.exchange(100000, "USD", "CNY")
	check(float(r["value_in_base"]) > 0.0, "换入价值为正")
	check_near(float(r["value_in_base"]), float(r["value_out_base"]) + float(r["fee_value_base"]), 1e-6, "换汇价值守恒")
	check(float(r["fee"]) > 0.0, "默认换汇收取手续费")
	check(m.fx_rate("CNY") > 0.0, "汇率为正")

	# 零价差零手续费：往返不损失。
	var zero: Dictionary = m.exchange(100000, "USD", "CNY", 0.0, 0.0)
	check_eq(int(zero["fee"]), 0, "零费率不收费")
	var back: Dictionary = m.exchange(int(zero["amount_out"]), "CNY", "USD", 0.0, 0.0)
	check_near(float(back["amount_out"]), 100000.0, 1.0, "零费率往返守恒（含最小单位取整）")

	# 有费率往返：只损失手续费，不会凭空增加。
	var round: Dictionary = m.exchange(int(r["amount_out"]), "CNY", "USD")
	check(int(round["amount_out"]) < 100000, "带费率往返后不增加")


# --- 通胀与宏观 ---

func _test_inflation_monotonic() -> void:
	var e = EconomyScript.new(7)
	e.macro["inflation"] = BaselineScript.MACRO_BASE_INFLATION
	var prev: float = float(e.indicator("price_index"))
	var strictly_increasing: bool = true
	for i in range(24):
		e.tick_macro()
		var cur: float = float(e.indicator("price_index"))
		if cur <= prev:
			strictly_increasing = false
		prev = cur
	check(prev > 1.0, "正通胀下物价指数上升")
	check(strictly_increasing, "通胀单调：物价指数逐季严格上升")

	# 闭式近似推进也单调。
	var idx: float = e.apply_inflation(1.0, 0.02, 10.0)
	check(idx > 1.0, "闭式通胀推进上升")
	check(e.apply_inflation(idx, 0.02, 5.0) > idx, "继续推进继续上升")


func _test_macro_bounded_and_transmission() -> void:
	var e = EconomyScript.new(8)
	for i in range(40):
		e.tick_macro()
		check(float(e.indicator("inflation")) >= BaselineScript.MACRO_INFLATION_MIN, "通胀有下界")
		check(float(e.indicator("inflation")) <= BaselineScript.MACRO_INFLATION_MAX, "通胀有上界")
		check(float(e.indicator("unemployment")) >= BaselineScript.MACRO_UNEMPLOYMENT_MIN, "失业率有下界")
		check(float(e.indicator("unemployment")) <= BaselineScript.MACRO_UNEMPLOYMENT_MAX, "失业率有上界")
		check(float(e.indicator("base_rate")) >= BaselineScript.MACRO_RATE_MIN, "利率有下界")
		check(float(e.indicator("base_rate")) <= BaselineScript.MACRO_RATE_MAX, "利率有上界")
		check(float(e.indicator("pmi")) >= BaselineScript.MACRO_PMI_MIN, "PMI 有下界")
		check(float(e.indicator("pmi")) <= BaselineScript.MACRO_PMI_MAX, "PMI 有上界")

	# 失业率传导：越高求职越难、工资越低。
	check(e.hire_difficulty(0.15) > e.hire_difficulty(0.03), "高失业率提高求职难度")
	check(e.wage_multiplier(0.15) < e.wage_multiplier(0.03), "高失业率压低工资")

	# 政策利率外生设定被 clamp。
	e.set_base_rate(99.0)
	check_near(float(e.indicator("base_rate")), BaselineScript.MACRO_RATE_MAX, 1e-9, "政策利率 clamp 到上限")


# --- 银行、杠杆、保险彩票 ---

func _test_bank_loan_and_credit() -> void:
	var e = EconomyScript.new(9)
	e.open_account("borrower", 0)
	var bank = BankScript.new(9)
	var before: int = e.total_money()
	bank.take_loan(e, "borrower", 100000)
	check_eq(e.cash("borrower"), 100000, "贷款到账")
	check_eq(e.debt("borrower"), 100000, "负债增加")
	check_eq(e.total_money(), before + 100000, "信用创造增加货币总量")

	var interest: int = bank.accrue_loan_interest(e, "borrower", 365)
	check(interest > 0, "贷款按日计息为正")
	check_eq(e.debt("borrower"), 100000 + interest, "利息计入负债")

	var repaid: int = bank.repay_loan(e, "borrower", e.cash("borrower"))
	check(repaid > 0, "还款成功")
	check(e.debt("borrower") < 100000 + interest, "还款减少负债")

	var rating0: int = bank.credit_rating("borrower")
	bank.record_overdue("borrower", BaselineScript.BANK_OVERDUE_DAYS_DOWNGRADE + 1)
	check(bank.credit_rating("borrower") < rating0, "逾期 30 天以上降级信用")


func _test_margin_liquidation() -> void:
	var bank = BankScript.new(10)
	var long_pos: Dictionary = bank.open_position(100.0, 100000, 1)
	check_near(bank.liquidation_price(long_pos), 75.0, 1e-6, "多仓强平价 = 入场×(1+维持−初始)")
	check(not bank.should_liquidate(long_pos, 80.0), "多仓未跌破不强平")
	check(bank.should_liquidate(long_pos, 74.0), "多仓跌破强平价强平")
	check(bank.liquidate(long_pos, 70.0) > 0, "强平可取回部分保证金")

	var short_pos: Dictionary = bank.open_position(100.0, 100000, -1)
	check_near(bank.liquidation_price(short_pos), 125.0, 1e-6, "空仓强平价 = 入场×(1−维持+初始)")
	check(not bank.should_liquidate(short_pos, 120.0), "空仓未涨破不强平")
	check(bank.should_liquidate(short_pos, 126.0), "空仓涨破强平价强平")


func _test_insurance_and_lottery() -> void:
	var bank = BankScript.new(11)
	check_eq(bank.insurance_premium(10000), 200, "保费按 2% 计")
	check_eq(bank.insurance_claim(10000, true), 10000, "出险按保额赔付")
	check_eq(bank.insurance_claim(10000, false), 0, "未出险不赔")
	check_eq(bank.insurance_claim(10000, true, false), 0, "不在保障范围不赔")

	# 彩票同种子同结果。
	var b1 = BankScript.new(2026)
	var b2 = BankScript.new(2026)
	var e1 = EconomyScript.new(1)
	var e2 = EconomyScript.new(1)
	e1.open_account("p", 1000000)
	e2.open_account("p", 1000000)
	for i in range(5):
		b1.buy_lottery(e1, "p")
		b2.buy_lottery(e2, "p")
	var draw1: Array = []
	var draw2: Array = []
	for i in range(5):
		draw1.append(b1.draw_lottery(e1, "p"))
		draw2.append(b2.draw_lottery(e2, "p"))
	check_eq(draw1, draw2, "同种子彩票开奖一致")
	check_eq(b1.lottery_tickets(), 5, "彩票注数正确")


# --- 远程配置覆盖 ---

func _test_remote_override() -> void:
	BaselineScript.apply_remote_config({
		"bank_loan_rate_annual": 0.10,
		"elasticity.luxury": 0.0,
		"tax_standard_deduction": 0.0,
	})
	var bank = BankScript.new(12)
	check_near(bank.loan_rate(), 0.10, 1e-9, "贷款利率可远程覆盖")
	check_near(BaselineScript.effective_elasticity("luxury"), 0.0, 1e-9, "价格弹性可远程覆盖")

	# 弹性为 0 时交易不改变价格。
	var m = MarketScript.new()
	m.register_good("lux", 100.0, "luxury")
	m.apply_trade("lux", 1.0e10, true, 1.0)
	check_near(m.price_factor("lux"), 1.0, 1e-9, "零弹性下交易不改变价格")

	# 扣除额为 0 时按全额累进。
	check_near(TaxScript.new().income_tax(36000.0), 1080.0, 1e-6, "扣除额可远程覆盖")
	BaselineScript.clear_overrides()
	check_near(BaselineScript.effective_elasticity("luxury"), BaselineScript.PRICE_ELASTICITY["luxury"], 1e-9, "清除覆盖恢复默认")
