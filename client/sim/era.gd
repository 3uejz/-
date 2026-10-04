class_name EraSystem
extends RefCounted
## 时代演化（R41；design D1、D24）。
##
## 九个时代阶段：石器、农业、古典、中世纪、工业、电气、信息、智能、星际。
## 推进方式：世界时间线按年份自动推进 + 重大科技成果/事件加速（accelerate）。
## 内容以 `era_min`/`era_max` 为时代门闩：可用区间取闭区间 [era_min, era_max]，
## 缺省一端表示无界（era_min 缺省为最早时代，era_max 缺省为最晚时代）。
## 门闩值可写时代索引（int）或时代键（String，如 "industrial"）。
## 数值默认集中在 client/sim/baseline.gd，均可由远程配置覆盖。

const BaselineScript = preload("res://sim/baseline.gd")


var _index: int = 0
var _world_year: int = 0
var _floor_index: int = 0        # 科技/事件加速解锁的最低时代（不可回退）
var _announcements: Array = []


func _init(start_year: int = 0) -> void:
	_world_year = start_year
	_index = era_index_for_year(start_year)


# --- 查询 ---

func era_count() -> int:
	return BaselineScript.effective_era_definitions().size()

func current_index() -> int:
	return _index

func current() -> Dictionary:
	return BaselineScript.effective_era(_index)

func current_key() -> String:
	return str(current().get("key", ""))

func current_name() -> String:
	return str(current().get("name", ""))

func world_year() -> int:
	return _world_year

func floor_index() -> int:
	return _floor_index

## 自上次清空以来累积的时代宣告（供消息流展示）。
func announcements() -> Array:
	return _announcements.duplicate()

func drain_announcements() -> Array:
	var out: Array = _announcements.duplicate()
	_announcements.clear()
	return out


# --- 推进 ---

## 世界时间线推进到指定公历年；时代不早于加速下限。
func advance_to_year(year: int) -> Dictionary:
	_world_year = year
	var timed: int = era_index_for_year(year)
	return _set_index(maxi(timed, _floor_index), "世界时间线推进")

func advance_years(years: int) -> Dictionary:
	return advance_to_year(_world_year + years)

## 重大科技成果/事件加速：以当前时代为基准前进一级（封顶最晚时代），并抬升加速下限。
func accelerate(reason: String = "重大科技成果") -> Dictionary:
	var last: int = maxi(0, era_count() - 1)
	_floor_index = clampi(maxi(_floor_index, _index) + 1, 0, last)
	var target: int = maxi(era_index_for_year(_world_year), _floor_index)
	return _set_index(target, reason)

## 直接设定加速下限（如科研解锁写回）。
func set_floor(index: int) -> void:
	_floor_index = clampi(index, 0, maxi(0, era_count() - 1))

## 强制设定时代（金手指/调试用），并同步加速下限。
func set_index(index: int, reason: String = "时代变更") -> Dictionary:
	var last: int = maxi(0, era_count() - 1)
	_floor_index = maxi(_floor_index, clampi(index, 0, last))
	return _set_index(clampi(index, 0, last), reason)

func _set_index(index: int, reason: String) -> Dictionary:
	var last: int = maxi(0, era_count() - 1)
	var target: int = clampi(index, 0, last)
	var from: int = _index
	_index = target
	var changed: bool = target != from
	if changed:
		_announcements.append({
			"type": "era_change",
			"from_index": from,
			"to_index": target,
			"from_key": era_key(from),
			"to_key": era_key(target),
			"to_name": era_name(target),
			"year": _world_year,
			"reason": reason,
			"message": "时代进入%s阶段（%s）。" % [era_name(target), reason],
		})
	return {
		"changed": changed,
		"from_index": from,
		"to_index": target,
		"from_key": era_key(from),
		"to_key": era_key(target),
		"to_name": era_name(target),
		"announcement": _announcements.back() if changed else {},
	}


# --- 内容时代门闩 ---

## 判定内容在其 `era`（默认当前时代）是否可用。
## 闭区间语义：era_min ≤ era ≤ era_max；缺省 min 为 0、缺省 max 为最后时代；min > max 恒不可用。
func is_content_available(item: Dictionary, era_index: int = -1) -> bool:
	var era: int = _index if era_index < 0 else era_index
	var lo: int = 0
	var hi: int = maxi(0, era_count() - 1)
	if item.has("era_min") and item["era_min"] != null:
		lo = _bound_to_index(item["era_min"])
		if lo < 0:
			lo = 0
	if item.has("era_max") and item["era_max"] != null:
		hi = _bound_to_index(item["era_max"])
		if hi < 0:
			hi = maxi(0, era_count() - 1)
	if lo > hi:
		return false
	return era >= lo and era <= hi

## 过滤内容列表，仅保留在当前（或指定）时代可用的条目。
func filter_items(items: Array, era_index: int = -1) -> Array:
	var out: Array = []
	for item in items:
		if item is Dictionary and is_content_available(item, era_index):
			out.append(item)
	return out

## 在当前（或指定）时代被淘汰/未解锁的内容列表。
func outdated_items(items: Array, era_index: int = -1) -> Array:
	var out: Array = []
	for item in items:
		if item is Dictionary and not is_content_available(item, era_index):
			out.append(item)
	return out

## 某时代可用的时代门闩标签（用于科技/职业/物品/交通/政策的解锁集合）。
func unlocked_tags(era_index: int = -1) -> Array:
	var era: int = _index if era_index < 0 else era_index
	var out: Array = []
	for i in range(clampi(era, 0, maxi(0, era_count() - 1)) + 1):
		var def: Dictionary = BaselineScript.effective_era(i)
		for tag in def.get("tags", []):
			if not out.has(tag):
				out.append(tag)
	return out


# --- 静态工具 ---

## 由公历年解析时代索引：取 start_year ≤ year 的最晚时代（闭下界）。
static func era_index_for_year(year: int) -> int:
	var defs: Array = BaselineScript.effective_era_definitions()
	for i in range(defs.size() - 1, -1, -1):
		if year >= int((defs[i] as Dictionary).get("start_year", 0)):
			return i
	return 0

static func era_key(index: int) -> String:
	return str(BaselineScript.effective_era(index).get("key", ""))

static func era_name(index: int) -> String:
	return str(BaselineScript.effective_era(index).get("name", ""))

## 把时代门闩值规整为索引：int/float 直接取整；String 按时代键查表；未知返回 -1。
static func _bound_to_index(value: Variant) -> int:
	match typeof(value):
		TYPE_INT:
			return int(value)
		TYPE_FLOAT:
			return int(value)
		TYPE_STRING, TYPE_STRING_NAME:
			var key := str(value)
			var defs: Array = BaselineScript.effective_era_definitions()
			for i in range(defs.size()):
				if str((defs[i] as Dictionary).get("key", "")) == key:
					return i
			return -1
		_:
			return -1
