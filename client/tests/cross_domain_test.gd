extends "res://tests/test_base.gd"
## 跨域接口、权威边界与休眠补算契约测试（任务 52）。
## 覆盖：统一修饰符字典、逐域权威边界合并、领域休眠补算的守恒与幂等，以及与 RegionManager.wake 的衔接。

const ModifierScript = preload("res://sim/modifiers.gd")
const AuthorityScript = preload("res://sim/authority.gd")
const DomainWakeScript = preload("res://sim/domain_wake.gd")
const RegionManagerScript = preload("res://sim/region_manager.gd")

func _suite_name() -> String:
	return "cross_domain"

func run_tests() -> void:
	_test_modifier_apply_modes()
	_test_modifier_expiry_and_source()
	_test_modifier_serialization()
	_test_authority_declarations()
	_test_authority_resolve()
	_test_authority_merge()
	_test_domain_wake_project()
	_test_domain_wake_idempotent_and_conservation()
	_test_domain_wake_kinds()
	_test_domain_wake_serialization()
	_test_region_wake_integration()

func _test_modifier_apply_modes() -> void:
	var m = ModifierScript.new()
	m.push("weather.temperature", 3.0, ModifierScript.MODE_ADD)
	m.push("weather.temperature", 2.0, ModifierScript.MODE_ADD)
	check_near(m.apply(20.0, "weather.temperature"), 25.0, 0.0001, "add 叠加")
	m.push("energy.price", 2.0, ModifierScript.MODE_MUL)
	check_near(m.apply(1.0, "energy.price"), 2.0, 0.0001, "mul 结算")
	m.push("macro.demand", 99.0, ModifierScript.MODE_SET)
	check_near(m.apply(1.0, "macro.demand"), 99.0, 0.0001, "set 覆盖")
	check_near(m.apply(5.0, "unknown.key"), 5.0, 0.0001, "未知键返回基值")
	check(ModifierScript.is_known_key("weather.rain"), "已知键识别")
	check(not ModifierScript.is_known_key("nope"), "未知键拒绝")

func _test_modifier_expiry_and_source() -> void:
	var m = ModifierScript.new()
	m.push("health.epidemic", 0.5, ModifierScript.MODE_ADD, "event.a", 100)
	m.push("health.epidemic", 0.2, ModifierScript.MODE_ADD, "event.b", -1)
	check_near(m.apply(0.0, "health.epidemic", 50), 0.7, 0.0001, "未过期全部生效")
	check_near(m.apply(0.0, "health.epidemic", 200), 0.2, 0.0001, "过期条目被跳过")
	check_eq(m.purge_expired(200), 1, "清理过期一条")
	check_eq(m.remove_source("event.b"), 1, "按来源移除")
	check(not m.has_key("health.epidemic"), "移除后无有效键")

func _test_modifier_serialization() -> void:
	var m = ModifierScript.new()
	m.push("strike.labor", 0.4, ModifierScript.MODE_SET, "org.x", 500)
	var doc: Dictionary = m.to_dict()
	var back = ModifierScript.new()
	back.from_dict(doc)
	check(back.has_key("strike.labor"), "往返保留键")
	check_near(back.apply(1.0, "strike.labor", 100), 0.4, 0.0001, "往返保留值")
	check_eq(back.to_dict()["strike.labor"].size(), 1, "往返保留条目数")

func _test_authority_declarations() -> void:
	check_eq(AuthorityScript.authority_for("population"), AuthorityScript.SERVER, "人口后端权威")
	check_eq(AuthorityScript.authority_for("local_play"), AuthorityScript.CLIENT, "本地玩法客户端权威")
	check(not AuthorityScript.local_may_approximate("carbon_market"), "碳市场不允许离线近似")
	check(AuthorityScript.local_may_approximate("population"), "人口允许离线近似")
	check(AuthorityScript.is_known("disaster"), "灾害域已登记")
	check(not AuthorityScript.is_known("unknown_domain"), "未知域未登记")
	check_eq(AuthorityScript.anchor_for("population"), "absolute_minutes", "锚点字段")

func _test_authority_resolve() -> void:
	# server_wins：服务端存在则覆盖，缺失则回退本地。
	var r1: Dictionary = AuthorityScript.resolve("population", 100, 200)
	check_eq(r1["value"], 200, "server_wins 采用服务端")
	check_eq(r1["source"], AuthorityScript.SERVER, "来源为服务端")
	var r2: Dictionary = AuthorityScript.resolve("population", 100, null)
	check_eq(r2["value"], 100, "服务端缺失回退本地")
	# client_wins：忽略服务端。
	var r3: Dictionary = AuthorityScript.resolve("local_play", "local", "server")
	check_eq(r3["value"], "local", "client_wins 保持本地")
	check_eq(r3["source"], AuthorityScript.CLIENT, "client_wins 来源本地")
	# server_if_present 与 server_wins 在存在时一致，缺失回退本地。
	var r4: Dictionary = AuthorityScript.resolve("region_healthcare", 0.5, 0.9)
	check_eq(r4["value"], 0.9, "server_if_present 采用服务端")
	var r5: Dictionary = AuthorityScript.resolve("region_healthcare", 0.5, null)
	check_eq(r5["value"], 0.5, "server_if_present 缺失回退本地")

func _test_authority_merge() -> void:
	var local: Dictionary = {"local_play": "mine", "population": 100, "carbon_market": 1.0}
	var server: Dictionary = {
		"domains": {"population": 500, "macro_economy": 2.0},
		"absolute_minutes": 123456,
	}
	var out: Dictionary = AuthorityScript.merge(local, server)
	var merged: Dictionary = out["merged"]
	check_eq(merged["local_play"], "mine", "本地玩法保留")
	check_eq(merged["population"], 500, "人口被服务端覆盖")
	check_eq(merged["macro_economy"], 2.0, "新增服务端域并入")
	check_eq(merged["carbon_market"], 1.0, "服务端缺失沿用本地")
	check_eq(out["sources"]["population"], AuthorityScript.SERVER, "合并来源标注")
	check_eq(out["anchor_minute"], 123456, "锚点透传")

func _test_domain_wake_project() -> void:
	var dw = DomainWakeScript.new()
	dw.register_project("proj.a", {"rate": 1.0, "total": 100.0, "started_minute": 0})
	var s1: Dictionary = dw.advance_to(30)
	check_eq(s1["advanced_minutes"], 30, "推进 30 分钟")
	check(not dw.is_resolved("proj.a"), "未达总量未完成")
	check_near(dw.get_entry("proj.a")["progress"], 30.0, 0.001, "进度累计")
	var s2: Dictionary = dw.advance_to(120)
	check_eq(s2["resolved_count"], 1, "达到总量后完成")
	check(dw.is_resolved("proj.a"), "工程完成")
	check_near(dw.get_entry("proj.a")["progress"], 100.0, 0.001, "进度封顶")

func _test_domain_wake_idempotent_and_conservation() -> void:
	var dw = DomainWakeScript.new()
	dw.register_project("p", {"rate": 0.5, "total": 1000.0})
	dw.register_loan("l", {"principal": 10000.0, "annual_rate": 0.12})
	var first: Dictionary = dw.advance_to(1440)   # 1 天
	check_eq(first["advanced_minutes"], 1440, "首次推进守恒")
	check_eq(dw.advanced_total(), 1440, "累计推进守恒")
	var interest1: float = float(dw.get_entry("l")["result"]["interest"])
	var again: Dictionary = dw.advance_to(1440)
	check_eq(again["advanced_minutes"], 0, "重复推进无增量")
	check(again["idempotent"], "标记幂等")
	check_near(float(dw.get_entry("l")["result"]["interest"]), interest1, 0.000001, "幂等不改变利息")
	var second: Dictionary = dw.advance_to(2880)
	check_eq(second["advanced_minutes"], 1440, "再次推进增量守恒")
	check_eq(dw.advanced_total(), 2880, "累计推进等于总时长")

func _test_domain_wake_kinds() -> void:
	var dw = DomainWakeScript.new()
	dw.register_disaster("d", {"total": 60.0, "params": {"severity": 2.0}})
	dw.register_case("c", {"due_minute": 100})
	dw.register_anomaly("a", {"rate": 1.0, "params": {"threshold": 50.0}})
	dw.register_surgery("s", {"total": 30.0})
	dw.advance_to(100)
	check_eq(dw.get_entry("d")["status"], "resolved", "灾害到时消解")
	check_eq(dw.get_entry("c")["status"], "closed", "案件到期结案")
	check_eq(dw.get_entry("a")["status"], "breached", "异常暴露越阈")
	check_eq(dw.get_entry("s")["status"], "recovered", "手术康复")
	# 逾期催收：按本金 * 年利率 * 天数累计利息。
	var dw2 = DomainWakeScript.new()
	dw2.register_loan("loan", {"principal": 100000.0, "annual_rate": 0.10})
	dw2.advance_to(1440 * 365)
	var expected: float = 100000.0 * 0.10 * (1440.0 * 365.0) / (1440.0 * 365.25)
	check_near(float(dw2.get_entry("loan")["result"]["interest"]), expected, 1.0, "一年利息近似本金*年利率")
	check_near(float(dw2.get_entry("loan")["result"]["overdue_days"]), 365.0, 0.01, "逾期天数")

func _test_domain_wake_serialization() -> void:
	var dw = DomainWakeScript.new()
	dw.register_project("p", {"rate": 1.0, "total": 500.0})
	dw.register_loan("l", {"principal": 1000.0, "annual_rate": 0.2})
	dw.advance_to(100)
	var doc: Dictionary = dw.to_dict()
	var back = DomainWakeScript.new()
	back.from_dict(doc)
	check_eq(back.now_minute(), 100, "时钟往返")
	check_eq(back.advanced_total(), 100, "累计往返")
	check_near(float(back.get_entry("l")["result"]["interest"]), float(dw.get_entry("l")["result"]["interest"]), 0.000001, "利息往返")
	var s: Dictionary = back.advance_to(100)
	check_eq(s["advanced_minutes"], 0, "恢复后同点幂等")
	back.advance_to(200)
	check_near(float(back.get_entry("p")["progress"]), 200.0, 0.001, "恢复后继续推进")

func _test_region_wake_integration() -> void:
	var rm = RegionManagerScript.new(null, 11)
	rm.register_region("city.dw", {"population": 5000})
	var dw = DomainWakeScript.new()
	dw.register_project("roads", {"region_id": "city.dw", "rate": 2.0, "total": 100.0})
	rm.domain_wake = dw
	rm.advance_now(1440 * 10)   # 休眠 10 天
	var result: Dictionary = rm.wake("city.dw")
	check(result.has("domains"), "wake 返回领域补算摘要")
	check_eq(result["domains"]["advanced_minutes"], 1440 * 10, "领域补算时长与休眠一致")
	check(dw.is_resolved("roads"), "休眠期间工程推进完成")
	# 区域已激活，再次 wake 幂等且不重复补算领域。
	var result2: Dictionary = rm.wake("city.dw")
	check(result2["idempotent"], "区域再次 wake 幂等")
	check_eq(dw.advanced_total(), 1440 * 10, "领域累计时长不重复")
