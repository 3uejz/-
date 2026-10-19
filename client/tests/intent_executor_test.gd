extends "res://tests/test_base.gd"
## 意图执行器测试（任务 3/4/23 接线层）：指令 → 模拟系统 → 状态变化与叙事。

const GameStateScript = preload("res://autoload/game_state.gd")
const SimHostScript = preload("res://sim/sim_host.gd")
const ExecutorScript = preload("res://command/intent_executor.gd")
const ParserScript = preload("res://command/command_parser.gd")
const VerbRegistryScript = preload("res://command/verb_registry.gd")

var state
var host
var executor
var parser

func _suite_name() -> String:
	return "intent_executor"

func _setup(seed: int = 7) -> void:
	state = GameStateScript.new()
	state.new_game(seed)
	host = SimHostScript.new(state, seed)
	executor = ExecutorScript.new(host)
	parser = ParserScript.new()

func _run(raw: String) -> Dictionary:
	return executor.execute(parser.parse(raw))

func run_tests() -> void:
	_test_help()
	_test_panel_open()
	_test_all_panel_verbs()
	_test_unknown_verb()
	_test_wait_advances_clock()
	_test_eat_generic()
	_test_buy_and_sell()
	_test_deposit_withdraw()
	_test_securities_commands()
	_test_bank_loan_commands()
	_test_study()
	_test_exercise()
	_test_job_apply_unqualified()
	_test_meta_actions()
	_test_compound()

func _test_help() -> void:
	_setup()
	var r: Dictionary = _run("帮助")
	check(bool(r["ok"]), "帮助可执行")
	check(r["narration"].size() > 0, "帮助有输出")
	check_eq(int(r["minutes"]), 0, "帮助不耗时")

func _test_panel_open() -> void:
	_setup()
	var r: Dictionary = _run("看自己")
	check(bool(r["ok"]), "看自己成功")
	check_eq(String(r["panel"]), "character", "打开角色面板")
	check_eq(int(r["minutes"]), 0, "看面板不耗时")

func _test_all_panel_verbs() -> void:
	_setup()
	for key in VerbRegistryScript.PANEL_VERBS.keys():
		var verb := String(key)
		var r: Dictionary = _run(verb)
		check(bool(r["ok"]), "面板动词可执行：%s" % verb)
		check_eq(String(r["panel"]), String(VerbRegistryScript.PANEL_VERBS[key]), "面板动词打开正确面板：%s" % verb)

func _test_unknown_verb() -> void:
	_setup()
	var r: Dictionary = _run("跳舞")
	check(not bool(r["ok"]), "未知动词失败")
	check(String(r["error"]) != "", "未知动词有错误信息")

func _test_wait_advances_clock() -> void:
	_setup()
	var before: int = host.now_minutes()
	var r: Dictionary = _run("等待 2 小时")
	check(bool(r["ok"]), "等待成功")
	check_eq(int(r["minutes"]), 120, "等待 2 小时 = 120 分钟")
	check_eq(host.now_minutes(), before + 120, "时钟推进 120 分钟")

func _test_eat_generic() -> void:
	_setup()
	host.player()["attrs"]["physiological"]["hunger"] = 40.0
	var r: Dictionary = _run("吃")
	check(bool(r["ok"]), "吃一餐成功")
	check(float(host.player()["attrs"]["physiological"]["hunger"]) > 40.0, "饱食度提升")

func _test_buy_and_sell() -> void:
	_setup()
	var cash0: float = float(host.player()["finances"]["cash"])
	var r: Dictionary = _run("买 苹果 2")
	check(bool(r["ok"]), "买苹果成功: %s" % String(r["error"]))
	check(int(host.items.count(host.player(), "item.apple")) == 2, "背包 +2 苹果")
	check(float(host.player()["finances"]["cash"]) < cash0, "现金减少")
	var r2: Dictionary = _run("卖 苹果 1")
	check(bool(r2["ok"]), "卖苹果成功")
	check(int(host.items.count(host.player(), "item.apple")) == 1, "背包剩 1 苹果")

func _test_deposit_withdraw() -> void:
	_setup()
	var cash0: float = float(host.player()["finances"]["cash"])
	var r: Dictionary = _run("存钱 500 元")
	check(bool(r["ok"]), "存钱成功: %s" % String(r["error"]))
	check(float(host.player()["finances"]["cash"]) < cash0, "现金减少")
	check(float(host.player()["finances"]["bank"]) > 0.0, "存款增加")
	var r2: Dictionary = _run("取钱 200 元")
	check(bool(r2["ok"]), "取钱成功")
	check(float(host.player()["finances"]["cash"]) > 0.0, "现金回升")

func _test_securities_commands() -> void:
	_setup()
	host.economy.issue_money(host.account_id(), 2000000, "test_fund")
	host.sync_finances()
	var buy: Dictionary = _run("买股票 科技成长 3")
	check(bool(buy["ok"]), "买股票指令可执行")
	check_eq(host.bank.holding_qty("stock.tech"), 3, "指令买入写入持仓")
	var sell: Dictionary = _run("卖股票 科技成长 1")
	check(bool(sell["ok"]), "卖股票指令可执行")
	check_eq(host.bank.holding_qty("stock.tech"), 2, "指令卖出减少持仓")
	var over: Dictionary = _run("卖股票 科技成长 99")
	check(not bool(over["ok"]), "超卖指令被拒绝")
	var bad: Dictionary = _run("买股票 不存在 1")
	check(not bool(bad["ok"]), "未知证券指令被拒绝")

func _test_bank_loan_commands() -> void:
	_setup()
	var loan: Dictionary = _run("贷款 5000元 1年")
	check(bool(loan["ok"]), "贷款指令可执行")
	check_eq(host.economy.debt(host.account_id()), 500000, "贷款计入负债")
	var repay: Dictionary = _run("还款 2000元")
	check(bool(repay["ok"]), "还款指令可执行")
	check_eq(host.economy.debt(host.account_id()), 300000, "还款冲抵负债")

func _test_study() -> void:
	_setup()
	var r: Dictionary = _run("学习 数学 2 小时")
	check(bool(r["ok"]), "学习成功: %s" % String(r["error"]))
	var skills: Array = host.player()["skills"]
	check(skills.size() > 0, "技能记录被写入")
	if skills.size() > 0:
		check(float(skills[0]["xp"]) > 0.0, "获得经验")

func _test_exercise() -> void:
	_setup()
	var before: int = host.now_minutes()
	var r: Dictionary = _run("锻炼 1 小时")
	check(bool(r["ok"]), "锻炼成功")
	check_eq(host.now_minutes() - before, 60, "锻炼耗时 1 小时")

func _test_job_apply_unqualified() -> void:
	_setup()
	var r: Dictionary = _run("求职 教授")
	check(bool(r["ok"]), "求职可执行且不崩溃: %s" % String(r["error"]))
	check(not host.jobs.is_employed(host.player()), "新玩家未入职")

func _test_meta_actions() -> void:
	_setup()
	check_eq(String(_run("存档")["action"]), "save", "存档动作")
	check_eq(String(_run("读档")["action"]), "load", "读档动作")

func _test_compound() -> void:
	_setup()
	var r: Dictionary = _run("等待 1 小时 然后 看自己")
	check(bool(r["ok"]), "复合指令成功")
	check_eq(String(r["panel"]), "character", "复合指令打开面板")
	check_eq(int(r["minutes"]), 60, "复合指令时间汇总")
