extends "res://tests/test_base.gd"
## 分区休眠与唤醒测试（任务 6.1）：激活/休眠、唤醒时间守恒与幂等属性、快照往返、确定性、活动 tick。

const RegionManagerScript = preload("res://sim/region_manager.gd")
const BaselineScript = preload("res://sim/baseline.gd")

func _suite_name() -> String:
	return "region"

func run_tests() -> void:
	_test_activate_dormant()
	_test_wake_time_conservation_property()
	_test_wake_linearity_and_monotonicity()
	_test_wake_idempotent()
	_test_active_tick()
	_test_snapshot_roundtrip()
	_test_deterministic()
	_test_remote_config_override()


## 基本激活/休眠用例：进入补算、离开写快照、再次进入按休眠时长唤醒。
func _test_activate_dormant() -> void:
	var rm = RegionManagerScript.new(null, 7)
	var region = rm.register_region("city.a", {"population": 1000})
	check(not region.is_active(), "初始为休眠")
	check(not rm.is_active("city.a"), "manager 初始休眠集合为空")
	check(region.snapshot.has("last_simulated_minute"), "登记后即有快照")

	var entered: Dictionary = rm.enter("city.a")
	check(rm.is_active("city.a"), "进入后为活动")
	check_eq(entered["state"], "active", "进入返回状态 active")
	check_eq(int(entered["advanced_minutes"]), 0, "休眠 0 分钟补算 0")

	rm.advance_now(120)
	var left: Dictionary = rm.leave("city.a")
	check(not rm.is_active("city.a"), "离开后为休眠")
	check_eq(left["state"], "dormant", "离开返回状态 dormant")
	check_eq(int(left["snapshot"]["last_simulated_minute"]), 120, "离开快照记录上次模拟时刻")

	rm.advance_now(480)  # 世界时间到 600
	var reentered: Dictionary = rm.enter("city.a")
	check(rm.is_active("city.a"), "再次进入为活动")
	check_eq(int(reentered["advanced_minutes"]), 480, "按休眠时长 480 分钟唤醒")
	check_eq(rm.get_region("city.a").last_simulated_minute, 600, "唤醒后已模拟时刻追平当前")

## 时间守恒属性测试：多轮随机休眠，累计补算分钟恰等于累计休眠时长。
func _test_wake_time_conservation_property() -> void:
	for trial in range(24):
		var rm = RegionManagerScript.new(null, 1000 + trial)
		var region_id: String = "city.t%d" % trial
		var population: int = 400 + trial * 53
		rm.register_region(region_id, {"population": population})

		var expected_total: int = 0
		var cursor: int = 0
		for cycle in range(6):
			# 确定性伪随机休眠时长，覆盖分钟到数年量级。
			var dormant: int = ((trial * 97 + cycle * 613) % 5000) + 1
			rm.advance_now(dormant)
			cursor += dormant

			var result: Dictionary = rm.wake(region_id)
			expected_total += dormant
			check_eq(int(result["advanced_minutes"]), dormant, "第 %d/%d 轮补算时长守恒" % [trial, cycle])
			check_eq(rm.get_region(region_id).last_simulated_minute, cursor, "已模拟时刻单调追平当前")
			check_eq(rm.now_minute(), cursor, "当前时钟等于累计休眠")

			# 回到休眠，进入下一轮。
			rm.leave(region_id)

		check_eq(rm.total_advanced_minutes(), expected_total, "累计补算分钟守恒")
		check_eq(rm.get_region(region_id).last_simulated_minute, expected_total, "最终已模拟时刻等于总时长")

## 线性与单调：补算时长随休眠时长线性增长，快照指标单调不倒退。
func _test_wake_linearity_and_monotonicity() -> void:
	var durations: Array = [1, 60, 1439, 1440, 43200, 525960, 525960 * 3]
	var previous_population: int = 0
	for d in durations:
		var rm = RegionManagerScript.new(null, 5)
		rm.register_region("city.lin", {"population": 10000})
		rm.advance_now(int(d))
		var result: Dictionary = rm.wake("city.lin")
		check_eq(int(result["advanced_minutes"]), int(d), "补算时长=%d 线性守恒" % int(d))
		check_eq(rm.get_region("city.lin").last_simulated_minute, int(d), "last 追平 %d" % int(d))
		check(float(result["advanced_years"]) > 0.0, "时长 %d 换算正数年" % int(d))
		check(int(result["events"]) >= 0, "事件数非负")
		# 默认出生率高于死亡率：休眠越久，统计快进后人口单调不减。
		check(int(result["population"]) >= previous_population, "人口随休眠时长单调不减")
		previous_population = int(result["population"])

## 幂等：对同一区域连续两次 wake，第二次不改变任何状态。
func _test_wake_idempotent() -> void:
	var rm = RegionManagerScript.new(null, 42)
	rm.register_region("city.idem", {"population": 2000})
	rm.advance_now(10000)

	var first: Dictionary = rm.wake("city.idem")
	check_eq(int(first["advanced_minutes"]), 10000, "首次补算完整时长")
	check(not bool(first["idempotent"]), "首次非幂等跳变")

	var snapshot_before: Dictionary = rm.snapshot("city.idem")
	var region_before = rm.get_region("city.idem").to_dict()
	var total_before: int = rm.total_advanced_minutes()

	for i in range(3):
		# 即使显式传入新的时长，活动区域也不再补算。
		var again: Dictionary = rm.wake("city.idem", 999999 if i == 0 else -1)
		check(bool(again["idempotent"]), "第 %d 次重复 wake 幂等" % (i + 1))
		check_eq(int(again["advanced_minutes"]), 0, "重复 wake 补算 0")
		check(_deep_equal(rm.snapshot("city.idem"), snapshot_before), "重复 wake 快照不变")
		check(_deep_equal(rm.get_region("city.idem").to_dict(), region_before), "重复 wake 区域状态不变")
		check_eq(rm.total_advanced_minutes(), total_before, "重复 wake 累计补算不变")

## 活动区域分钟级 tick：时间前移且不重复结算。
func _test_active_tick() -> void:
	var rm = RegionManagerScript.new(null, 11)
	rm.register_region("city.tick", {"population": 800})
	rm.enter("city.tick")

	rm.tick_minute(300)
	check_eq(rm.get_region("city.tick").last_simulated_minute, 300, "活动 tick 前移")
	var snap = rm.snapshot("city.tick")
	check_eq(int(snap["active_minutes_total"]), 300, "活动时长累计")

	rm.tick_minute(300)  # 同一时刻重复调用不重复结算
	check_eq(int(rm.snapshot("city.tick")["active_minutes_total"]), 300, "重复 tick 不重复结算")

	rm.tick_minute(301)
	check_eq(int(rm.snapshot("city.tick")["active_minutes_total"]), 301, "继续 tick 累加")
	check_eq(int(rm.total_advanced_minutes()), 0, "活动时段不计入休眠补算")

## 休眠快照往返：写入 world_delta 增量后再载入等价。
func _test_snapshot_roundtrip() -> void:
	var rm = RegionManagerScript.new(null, 3)
	rm.register_region("city.rt", {"population": 1234, "price_index": 1.1, "safety": 66.0})
	rm.advance_now(20000)
	rm.wake("city.rt")
	rm.leave("city.rt")

	var delta: Dictionary = rm.to_delta("city.rt")
	check_eq(delta["region_key"], "city.rt", "delta key")
	check(delta.has("population"), "delta 含人口")

	var rm2 = RegionManagerScript.new(null, 3)
	rm2.load_delta(delta)
	check(rm2.has_region("city.rt"), "载入区域")
	check(not rm2.is_active("city.rt"), "载入后视为休眠")

	var a = rm.get_region("city.rt")
	var b = rm2.get_region("city.rt")
	check_eq(b.population, a.population, "人口往返")
	check_eq(b.last_simulated_minute, a.last_simulated_minute, "已模拟时刻往返")
	check_near(b.price_index, a.price_index, 1e-9, "物价往返")
	check(_deep_equal(b.snapshot, a.snapshot), "快照往返等价")

## 确定性：同种子 + 同输入序列产生相同演化（可复现）。
func _test_deterministic() -> void:
	var a = RegionManagerScript.new(null, 2024)
	var b = RegionManagerScript.new(null, 2024)
	for rm in [a, b]:
		rm.register_region("city.det", {"population": 5000})
		rm.advance_now(525960 * 2)
	var ra: Dictionary = a.wake("city.det")
	var rb: Dictionary = b.wake("city.det")
	check_eq(int(ra["events"]), int(rb["events"]), "同种子事件数一致")
	check_eq(int(ra["population"]), int(rb["population"]), "同种子人口一致")
	check_near(a.get_region("city.det").economy, b.get_region("city.det").economy, 1e-9, "同种子经济一致")

## 远程配置可覆盖区域统计快进参数。
func _test_remote_config_override() -> void:
	BaselineScript.apply_remote_config({
		"region_birth_rate_annual": 0.0,
		"region_death_rate_annual": 0.0,
		"region_migration_rate_annual": 0.0,
		"region_event_rate_annual": 0.0,
	})
	var rm = RegionManagerScript.new(null, 9)
	rm.register_region("city.cfg", {"population": 1000})
	rm.advance_now(525960)
	var result: Dictionary = rm.wake("city.cfg")
	check_eq(int(result["births"]), 0, "出生率被覆盖为 0")
	check_eq(int(result["deaths"]), 0, "死亡率被覆盖为 0")
	check_eq(int(result["events"]), 0, "事件率被覆盖为 0")
	check_eq(int(result["population"]), 1000, "人口不变")
	BaselineScript.clear_overrides()

	# 恢复默认后出生/死亡回到非零。
	var rm2 = RegionManagerScript.new(null, 9)
	rm2.register_region("city.cfg2", {"population": 1000})
	rm2.advance_now(525960)
	var result2: Dictionary = rm2.wake("city.cfg2")
	check(int(result2["births"]) > 0, "默认出生率为正")
	check(int(result2["deaths"]) > 0, "默认死亡率为正")

## 深度相等（兼容 JSON 数字 float 与 int）。
func _deep_equal(a: Variant, b: Variant) -> bool:
	var ta: int = typeof(a)
	var tb: int = typeof(b)
	if ta != tb:
		if (ta == TYPE_INT or ta == TYPE_FLOAT) and (tb == TYPE_INT or tb == TYPE_FLOAT):
			return float(a) == float(b)
		return false
	if ta == TYPE_DICTIONARY:
		var da: Dictionary = a
		var db: Dictionary = b
		if da.size() != db.size():
			return false
		for key in da.keys():
			if not db.has(key) or not _deep_equal(da[key], db[key]):
				return false
		return true
	if ta == TYPE_ARRAY:
		var aa: Array = a
		var ab: Array = b
		if aa.size() != ab.size():
			return false
		for i in aa.size():
			if not _deep_equal(aa[i], ab[i]):
				return false
		return true
	return a == b
