extends "res://tests/test_base.gd"
## 随机事件与日程调度测试（任务 22；R6、R98）。

const EventsScript = preload("res://sim/events.gd")


class FixedRng:
	var seq: Array
	var i: int = 0
	func _init(s: Array) -> void:
		seq = s
	func next_float() -> float:
		var v: float = float(seq[i % seq.size()])
		i += 1
		return v


func _suite_name() -> String:
	return "events"


func run_tests() -> void:
	_test_catalog()
	_test_conditions()
	_test_tick_rate_limit()
	_test_schedule_priority()
	_test_choice_chain()
	_test_offline()


func _test_catalog() -> void:
	var sys = EventsScript.new()
	check(sys.event_count() >= 20, "事件库充足")
	check_eq(EventsScript.TYPES.size(), 5, "五类事件")
	check_eq(EventsScript.TRIGGERS.size(), 4, "四种触发")


func _test_conditions() -> void:
	var sys = EventsScript.new()
	var e: Dictionary = sys.event_info("promotion_offer")
	check(not sys.conditions_met(e, {"skill": 5}), "条件不足不满足")
	check(sys.conditions_met(e, {"skill": 15}), "条件满足")
	check(not sys.conditions_met(sys.event_info("heatwave"), {"season": "winter"}), "季节不符")


func _test_tick_rate_limit() -> void:
	var sys = EventsScript.new(0, 3)
	sys.set_rng(FixedRng.new([0.0]))
	var ctx: Dictionary = {"minute": 0, "month": 1, "season": "winter", "age": 30, "money": 200000, "skill": 15, "fame": 50}
	var r1: Dictionary = sys.tick(ctx, FixedRng.new([0.0]))
	check(bool(r1["ok"]), "调度成功")
	check(not (r1["event"] as Dictionary).is_empty(), "触发事件")
	sys.tick(ctx, FixedRng.new([0.0]))
	sys.tick(ctx, FixedRng.new([0.0]))
	var r4: Dictionary = sys.tick(ctx, FixedRng.new([0.0]))
	check_eq(str(r4["reason"]), "global_rate_limited", "全局限流")


func _test_schedule_priority() -> void:
	var sys = EventsScript.new()
	# 1 月日程事件应触发节庆集会。
	var r: Dictionary = sys.tick({"minute": 0, "month": 1, "season": "winter", "age": 30}, FixedRng.new([0.0]))
	check_eq(str((r["event"] as Dictionary)["id"]), "festival_gathering", "日程事件触发")
	# 优先级打断。
	check(sys.can_interrupt({"priority": 90}, 50), "高优先级可打断")
	check(not sys.can_interrupt({"priority": 20}, 50), "低优先级不可打断")


func _test_choice_chain() -> void:
	var sys = EventsScript.new()
	var wallet: Dictionary = sys.event_info("found_wallet")
	var res: Dictionary = sys.resolve_choice(wallet, 0, 100)
	check(bool(res["ok"]), "抉择结算")
	check(bool((res["effects"] as Dictionary).has("karma")), "效果生效")
	var promo: Dictionary = sys.event_info("promotion_offer")
	var chain: Dictionary = sys.resolve_choice(promo, 0, 100)
	check_eq(str(chain["next"]), "promotion_aftermath", "链式下一事件")
	check((chain as Dictionary).has("chain_event"), "返回链事件")


func _test_offline() -> void:
	var sys = EventsScript.new()
	var r: Dictionary = sys.simulate_offline(0, 1440 * 3, {"month": 6, "season": "summer"}, FixedRng.new([0.0, 0.5, 0.9]))
	check(int(r["count"]) > 0, "离线补算产生汇总")
	check((r["log"] as Array).size() == int(r["count"]), "挂机日志条目一致")
