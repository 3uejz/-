extends "res://tests/test_base.gd"
## 战争/疫情/市政三系统的 SimHost 接线测试：
## 持久化、面板数据、动作资金闭环与按日/按月 tick。

const GameStateScript = preload("res://autoload/game_state.gd")
const SimHostScript = preload("res://sim/sim_host.gd")
const ExecutorScript = preload("res://command/intent_executor.gd")
const ParserScript = preload("res://command/command_parser.gd")


func _suite_name() -> String:
	return "civic_systems_runtime"


func _setup(seed: int = 11):
	var state = GameStateScript.new()
	state.new_game(seed)
	var host = SimHostScript.new(state, seed)
	host.economy.add_money(host.account_id(), 20_000_000, "test")
	return {"state": state, "host": host}


func run_tests() -> void:
	_test_war_flow_and_persistence()
	_test_epidemic_flow()
	_test_epidemic_daily_tick()
	_test_personal_protection()
	_test_infrastructure_flow()
	_test_infrastructure_monthly_tick()
	_test_commands()
	_test_panel_content()


func _test_war_flow_and_persistence() -> void:
	var env: Dictionary = _setup()
	var host = env["host"]
	var state = env["state"]
	var r: Dictionary = host.war_adjust_tension("CN", "US", 85.0)
	check(bool(r.get("ok", false)), "可调节两国紧张度")
	check(float(r.get("tension", 0.0)) >= 85.0, "紧张度累加")
	var d: Dictionary = host.war_declare("CN", "US")
	check(bool(d.get("ok", false)), "可宣战")
	check(host.war_state()["wars"].size() >= 1, "战争状态新增")
	var m: Dictionary = host.war_mobilize(0.6)
	check(bool(m.get("ok", false)), "可设置动员度")
	check(bool((state.sim_runtime as Dictionary).has("war")), "战争状态写入运行时")
	var panel: Dictionary = host.war_panel_data()
	check((panel.get("relations", []) as Array).size() >= 1, "战争面板含双边关系")
	check(bool(panel.get("effects", {}).has("active_wars")), "战争面板含经济影响")
	var before: int = int(host.war_state().get("economy", {}).get("debt", 0))
	host._war_tick(0, 525960)
	check(int(host.war_state()["economy"]["debt"]) > before, "战时经济按年累积国债")


func _test_epidemic_flow() -> void:
	var env: Dictionary = _setup()
	var host = env["host"]
	var s: Dictionary = host.epidemic_seed_infections(120)
	check(bool(s.get("ok", false)), "可播撒感染")
	var p: Dictionary = host.epidemic_set_policy("mask", true)
	check(bool(p.get("ok", false)), "可开启口罩政策")
	check(host.epidemic_state()["policies"].has("mask"), "政策写入区域状态")
	var r: Dictionary = host.epidemic_step(30.0)
	check(bool(r.get("ok", false)), "疫情按日推进")
	check(float(host.epidemic_state().get("susceptible", 0.0)) < float(host.epidemic_state().get("population", 0)), "易感人群被消耗")
	var panel: Dictionary = host.epidemic_panel_data()
	check((panel.get("policies", []) as Array).size() >= 5, "疫情面板含政策目录")
	check(int(panel.get("population", 0)) > 0, "疫情面板含人口")
	check(bool((env["state"].sim_runtime as Dictionary).has("epidemic")), "疫情状态写入运行时")


func _test_epidemic_daily_tick() -> void:
	var env: Dictionary = _setup()
	var host = env["host"]
	host.epidemic_seed_infections(50)
	host._epidemic_last_day = -1
	host.state.clock["absolute_minutes"] = 0
	host._epidemic_tick(0, 3 * 1440)
	check_eq(int(host._epidemic_last_day), 3, "跨日 tick 更新最后结算日")
	var again: Array = host._epidemic_tick(3 * 1440, 3 * 1440 + 60)
	check(again.is_empty(), "同日重复 tick 不重复结算")


func _test_personal_protection() -> void:
	var env: Dictionary = _setup()
	var host = env["host"]
	var before: int = host.economy.cash(host.account_id())
	var r: Dictionary = host.epidemic_personal_action("口罩")
	check(bool(r.get("ok", false)), "可购买个人防护")
	check(int(host.economy.cash(host.account_id())) < before, "个人防护真实扣款")
	check(float(r.get("protection", 0.0)) > 0.0, "防护系数提升")
	var bad: Dictionary = host.epidemic_personal_action("不存在")
	check(not bool(bad.get("ok", true)), "未知防护动作被拒绝")


func _test_infrastructure_flow() -> void:
	var env: Dictionary = _setup()
	var host = env["host"]
	var bill: Dictionary = host.infra_bill("power", 50000)
	check(bool(bill.get("ok", false)), "可出公用账单")
	check_eq(int(bill.get("due", 0)), 50000, "账单累加欠费")
	var cash_before: int = host.economy.cash(host.account_id())
	var pay: Dictionary = host.infra_pay("power", 50000)
	check(bool(pay.get("ok", false)), "可缴纳公用账单")
	check_eq(int(host.infrastructure_state()["city"]["accounts"]["power"]["due"]), 0, "缴费后欠费清零")
	check(int(host.economy.cash(host.account_id())) < cash_before, "缴费真实扣款")
	var inv: Dictionary = host.infra_invest("water", 100000)
	check(bool(inv.get("ok", false)), "可投资公用设施")
	check(float(inv.get("reliability", 0.0)) > 0.0, "投资提升可靠性")
	var inc: Dictionary = host.infra_report_incident("power", "disaster", 0.5)
	check(bool(inc.get("ok", false)), "可登记设施故障")
	var panel: Dictionary = host.infrastructure_panel_data()
	check((panel.get("facilities", []) as Array).size() >= 6, "市政面板含设施清单")
	check((panel.get("incidents", []) as Array).size() >= 1, "市政面板含待修故障")
	check(bool((env["state"].sim_runtime as Dictionary).has("infrastructure")), "市政状态写入运行时")


func _test_infrastructure_monthly_tick() -> void:
	var env: Dictionary = _setup()
	var host = env["host"]
	host._infra_last_month = -1
	host.state.clock["absolute_minutes"] = 0
	host._infra_tick(0, 30 * 1440)
	check(host._infra_last_month >= 1, "跨月 tick 更新最后结算月")
	var due: int = int(host.infrastructure_state()["city"]["accounts"]["power"]["due"])
	check(due > 0, "按月自动出账")
	host.state.clock["absolute_minutes"] = 45 * 1440
	host._infra_tick(30 * 1440, 45 * 1440)
	check(host._infra_last_month >= 1, "同月不重复出账")


func _test_commands() -> void:
	var env: Dictionary = _setup()
	var host = env["host"]
	var executor = ExecutorScript.new(host)
	var parser = ParserScript.new()
	for verb in ["宣战", "停战", "动员", "征兵体检", "应征入伍", "拒服兵役", "前线作战",
			"疫情爆发", "疫情推进", "防疫政策", "解除防控", "疫苗接种", "个人防护",
			"公用账单", "公用缴费", "设施抢修", "公用投资", "设施故障", "调节紧张"]:
		var intent = parser.from_action(verb, [], {"method": "CN,US", "number": 10})
		check(bool(intent.ok), "动词已注册：%s" % verb)
	check_eq(String(parser.parse("宣战 CN,US").verb), "宣战", "宣战文本指令解析")
	check_eq(String(parser.parse("疫情推进 3").verb), "疫情推进", "疫情推进文本指令解析")
	check_eq(String(parser.parse("公用缴费 电力 10000").verb), "公用缴费", "公用缴费文本指令解析")
	host.war_adjust_tension("CN", "US", 90.0)
	var r: Dictionary = executor.execute(parser.from_action("宣战", [], {"method": "CN,US"}))
	check(bool(r.get("ok", false)), "宣战指令可执行")
	var t: Dictionary = executor.execute(parser.from_action("调节紧张", [], {"method": "CN,US", "number": 5}))
	check(bool(t.get("ok", false)), "调节紧张指令可执行")
	var e: Dictionary = executor.execute(parser.from_action("疫情爆发", [], {"number": 20}))
	check(bool(e.get("ok", false)), "疫情爆发指令可执行")
	var p: Dictionary = executor.execute(parser.from_action("防疫政策", [], {"method": "口罩"}))
	check(bool(p.get("ok", false)), "防疫政策指令可执行")
	var b: Dictionary = executor.execute(parser.from_action("公用账单", [{"type": "infra_facility", "id": "power"}], {"number": 20000}))
	check(bool(b.get("ok", false)), "公用账单指令可执行")
	var pay: Dictionary = executor.execute(parser.from_action("公用缴费", [{"type": "infra_facility", "id": "power"}], {"number": 20000}))
	check(bool(pay.get("ok", false)), "公用缴费指令可执行")
	var inc: Dictionary = executor.execute(parser.from_action("设施故障", [{"type": "infra_facility", "id": "water"}], {"method": "灾害", "number": 60}))
	check(bool(inc.get("ok", false)), "设施故障指令可执行")
	var rep: Dictionary = executor.execute(parser.from_action("设施抢修", [], {"number": 20}))
	check(bool(rep.get("ok", false)), "设施抢修指令可执行")


func _test_panel_content() -> void:
	var env: Dictionary = _setup()
	var host = env["host"]
	host.epidemic_seed_infections(10)
	var ep: Dictionary = PanelContent.epidemic(host.player(), {"epidemic_panel": host.epidemic_panel_data()})
	check(not bool(ep.get("empty", true)), "疫情面板有内容")
	check((ep.get("sections", []) as Array).size() >= 3, "疫情面板含态势/政策/资源段")
	host.war_adjust_tension("CN", "US", 90.0)
	host.war_declare("CN", "US")
	var wp: Dictionary = PanelContent.war(host.player(), Callable(), {"war": host.war_panel_data()})
	check(not bool(wp.get("empty", true)), "战争面板有内容")
	check((wp.get("sections", []) as Array).size() >= 3, "战争面板含战事/关系/经济段")
	var mp: Dictionary = PanelContent.municipal(host.player(), {"infrastructure": host.infrastructure_panel_data()})
	check(not bool(mp.get("empty", true)), "市政面板含公用设施段")
