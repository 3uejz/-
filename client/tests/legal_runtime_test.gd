extends "res://tests/test_base.gd"
## 犯罪与监狱运行时接线测试（R22/R23、D12）：
## 犯罪暴露 → 案底通缉 → 受审定罪入监 → 服刑生活 → 刑满释放与融入。

const GameStateScript = preload("res://autoload/game_state.gd")
const SimHostScript = preload("res://sim/sim_host.gd")
const ExecutorScript = preload("res://command/intent_executor.gd")
const ParserScript = preload("res://command/command_parser.gd")


func _suite_name() -> String:
	return "legal_runtime"


func _setup(seed: int = 11):
	var state = GameStateScript.new()
	state.new_game(seed)
	return {"state": state, "host": SimHostScript.new(state, seed)}


func run_tests() -> void:
	_test_attempt_to_trial()
	_test_prison_life_and_release()
	_test_persistence()
	_test_commands()
	_test_surrender_then_trial()


func _test_attempt_to_trial() -> void:
	var env: Dictionary = _setup()
	var host = env["host"]
	host.rng.set_state(0)
	var a: Dictionary = host.crime_attempt("theft")
	check(bool(a.get("ok", false)), "犯罪指令可执行")
	check(not bool(a.get("success", false)), "低技能偷窃失败")
	check(bool(a.get("detected", false)), "失败被察觉")
	var legal: Dictionary = host.player().get("legal", {})
	check_eq(int(legal.get("wanted_level", 0)), 2, "暴露后按难度生成通缉等级")
	check(bool(legal.get("criminal_record", false)), "暴露后留下案底")
	check_eq((legal.get("record_entries", []) as Array).size(), 1, "案底条目入法律状态")
	var panel: Dictionary = host.law_panel_data()
	var crime: Dictionary = panel.get("crime", {})
	check_eq((crime.get("records", []) as Array).size(), 1, "法律面板含案底")
	check_eq((crime.get("wanted", []) as Array).size(), 1, "法律面板含通缉")
	host.rng.set_state(3)
	var t: Dictionary = host.crime_trial()
	check(bool(t.get("ok", false)), "刑事受审可执行")
	check(bool(t.get("convicted", false)), "证据充分时定罪")
	check(int(t.get("days", 0)) > 0, "刑事定罪产生刑期")
	check(int(t.get("fine", 0)) > 0, "刑事定罪产生罚金")
	check(bool(host.player().get("legal", {}).get("in_prison", false)), "定罪后进入在押状态")
	check(host._prison_active(), "监狱运行时处于在押")
	check_eq(int(host.player().get("legal", {}).get("wanted_level", 0)), 0, "受审后通缉解除")


func _test_prison_life_and_release() -> void:
	var env: Dictionary = _setup()
	var host = env["host"]
	host._crime_state = host._crime_new_state()
	host.crime_sys.add_record(host._crime_state, "theft", host.current_region_id(), host.now_minutes(), 0.8)
	host.crime_sys.add_wanted(host._crime_state, "theft", host.current_region_id(), 2)
	host._sync_legal()
	host.rng.set_state(3)
	var t: Dictionary = host.crime_trial()
	check(bool(t.get("convicted", false)), "预置通缉可定罪")
	var cash_before: int = host.economy.cash(host.account_id())
	var lab: Dictionary = host.prison_labor(8.0)
	check(bool(lab.get("ok", false)), "监狱劳动可执行")
	check(int(lab.get("income", 0)) > 0, "劳动产生报酬")
	check(host.economy.cash(host.account_id()) > cash_before, "劳动报酬到账")
	check(float(lab.get("behavior", 0.0)) > 50.0, "劳动提升服刑表现")
	var visit: Dictionary = host.prison_visit("家人")
	check(bool(visit.get("ok", false)), "探视可执行")
	var gang: Dictionary = host.prison_join_gang("order")
	check(bool(gang.get("ok", false)), "加入狱帮可执行")
	check_eq(String(gang.get("name", "")), "秩序帮", "狱帮名称解析")
	host._prison["behavior"] = 80.0
	var red: Dictionary = host.prison_reduce_sentence(5)
	check(bool(red.get("ok", false)), "表现良好可减刑")
	check_eq(int(red.get("days_remaining", 0)), int(t.get("days", 0)) - 5, "减刑扣减剩余刑期")
	host._prison["days_remaining"] = 1
	host._prison["behavior"] = 80.0
	host._prison_last_day = host.now_minutes() / 1440
	host._prison_tick(host.now_minutes(), host.now_minutes() + 1440)
	check(not host._prison_active(), "刑满释放")
	check(not bool(host.player().get("legal", {}).get("in_prison", false)), "释放后解除在押")
	var rein: Dictionary = host.prison_reintegrate(60.0)
	check(bool(rein.get("ok", false)), "出狱融入可执行")
	check(float(rein.get("recidivism_risk", 0.0)) > 0.0, "出狱后仍有再犯风险")
	check(float(host.player().get("legal", {}).get("employment_penalty", 0.0)) > 0.0, "案底与融入影响就业")


func _test_persistence() -> void:
	var env: Dictionary = _setup()
	var state = env["state"]
	var host = env["host"]
	host._crime_state = host._crime_new_state()
	host.crime_sys.add_record(host._crime_state, "fraud", "r-test", host.now_minutes(), 0.7)
	host.crime_sys.add_wanted(host._crime_state, "fraud", "r-test", 3)
	host._prison = host.prison_sys.new_inmate("测试人", "fraud", 30)
	host._persist_crime()
	host._persist_prison()
	host._sync_legal()
	var reloaded = SimHostScript.new(state, 11)
	var panel: Dictionary = reloaded.law_panel_data()
	check_eq((panel.get("crime", {}).get("records", []) as Array).size(), 1, "读档恢复案底")
	check_eq((panel.get("crime", {}).get("wanted", []) as Array).size(), 1, "读档恢复通缉")
	check_eq(int(panel.get("prison", {}).get("days_remaining", 0)), 30, "读档恢复刑期")
	check(bool(reloaded.player().get("legal", {}).get("in_prison", false)), "读档恢复在押状态")


func _test_commands() -> void:
	var env: Dictionary = _setup()
	var host = env["host"]
	var executor = ExecutorScript.new(host)
	var parser = ParserScript.new()
	var intent = parser.parse("犯罪 偷窃")
	check_eq(String(intent.verb), "实施犯罪", "犯罪指令解析")
	var r: Dictionary = executor.execute(intent)
	check(bool(r.get("ok", false)), "犯罪指令经执行器可运行")
	check_eq(String(parser.parse("受审").verb), "刑事受审", "受审指令解析")
	check_eq(String(parser.parse("探视 家人").verb), "监狱探视", "探视别名解析")
	check_eq(String(parser.parse("减刑 10 天").verb), "减刑", "减刑指令解析")
	check_eq(String(parser.parse("出狱融入 60").verb), "出狱融入", "出狱融入指令解析")


func _test_surrender_then_trial() -> void:
	var env: Dictionary = _setup()
	var host = env["host"]
	host._crime_state = host._crime_new_state()
	host.crime_sys.add_record(host._crime_state, "fraud", host.current_region_id(), host.now_minutes(), 0.6)
	host.crime_sys.add_wanted(host._crime_state, "fraud", host.current_region_id(), 2)
	host._sync_legal()
	var sur: Dictionary = host.crime_self_surrender()
	check(bool(sur.get("ok", false)), "自首可执行")
	check_eq(int(host.player().get("legal", {}).get("wanted_level", 0)), 0, "自首解除通缉")
	host.rng.set_state(3)
	var t: Dictionary = host.crime_trial()
	check(bool(t.get("ok", false)), "自首后仍可受审")
	check(bool(t.get("convicted", false)), "自首后证据充分可定罪")
	check(bool(host.player().get("legal", {}).get("in_prison", false)), "自首受审后可入监")
