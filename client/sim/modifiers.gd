class_name ModifierRegistry
extends RefCounted
## 统一事件/修饰符字典（R52，gaps 系统性问题 6）。
##
## 跨域系统（天气、中断、罢工、数据泄露、能源价格、荣誉等）通过本注册表声明与叠加影响，
## 而不是各自私藏字段。所有修饰符是纯数据、可序列化，按 (scope, key) 取用。
##
## 约定：
##   - key 用点分命名空间，如 weather.rain、strike.logistics、energy.price；
##   - 每条修饰符为 {key, value, mode, source, expires_minute}，mode ∈ {add, mul, set}；
##   - apply(base) 按来源顺序结算：set 覆盖、add 相加、mul 相乘；
##   - 已过期（expires_minute >= 0 且当前分钟 > expires_minute）的条目不参与结算。

const MODE_ADD: String = "add"
const MODE_MUL: String = "mul"
const MODE_SET: String = "set"

## 规范键清单：跨域契约的权威命名（内容与事件必须引用这些键）。
const KNOWN_KEYS: Dictionary = {
	# 天气生态
	"weather.temperature": "气温偏置（摄氏度）",
	"weather.rain": "降水强度 0..1",
	"weather.visibility": "能见度 0..1",
	"weather.disaster_risk": "灾害风险 0..1",
	# 交通/物流中断
	"interruption.transport": "交通中断系数 0..1",
	"interruption.logistics": "物流中断系数 0..1",
	# 劳资
	"strike.labor": "罢工强度 0..1",
	"strike.logistics": "物流罢工强度 0..1",
	# 数字安全
	"dataleak.risk": "数据泄露风险 0..1",
	"dataleak.exposure": "已泄露程度 0..1",
	# 宏观
	"energy.price": "能源价格指数（1.0 为基准）",
	"macro.demand": "总需求偏置",
	# 社会
	"honor.reputation": "荣誉/声望偏置",
	"crime.rate": "犯罪率偏置",
	# 医疗/公共卫生
	"health.epidemic": "疫情传播系数 0..1",
	"health.capacity": "医疗承载力 0..1",
}

var _entries: Dictionary = {}   # key -> Array[Dictionary]

## 添加/更新一条修饰符。同 key 可叠加多个来源。
func push(key: String, value: float, mode: String = MODE_ADD, source: String = "", expires_minute: int = -1) -> Dictionary:
	var entry: Dictionary = {
		"key": key, "value": value, "mode": mode, "source": source, "expires_minute": expires_minute,
	}
	if not _entries.has(key):
		_entries[key] = []
	_entries[key].append(entry)
	return entry

## 移除指定来源的修饰符，返回移除数量。
func remove_source(source: String) -> int:
	var removed: int = 0
	for key in _entries.keys():
		var kept: Array = []
		for e in _entries[key]:
			if str(e.get("source", "")) == source:
				removed += 1
			else:
				kept.append(e)
		if kept.is_empty():
			_entries.erase(key)
		else:
			_entries[key] = kept
	return removed

## 清理已过期条目（now_minute 为当前世界分钟）。
func purge_expired(now_minute: int) -> int:
	var removed: int = 0
	for key in _entries.keys():
		var kept: Array = []
		for e in _entries[key]:
			var exp: int = int(e.get("expires_minute", -1))
			if exp >= 0 and now_minute > exp:
				removed += 1
			else:
				kept.append(e)
		if kept.is_empty():
			_entries.erase(key)
		else:
			_entries[key] = kept
	return removed

## 对基础值结算某键的全部有效修饰符。
func apply(base: float, key: String, now_minute: int = -1) -> float:
	if not _entries.has(key):
		return base
	var value: float = base
	for e in _entries[key]:
		var exp: int = int(e.get("expires_minute", -1))
		if now_minute >= 0 and exp >= 0 and now_minute > exp:
			continue
		match str(e.get("mode", MODE_ADD)):
			MODE_SET:
				value = float(e.get("value", value))
			MODE_MUL:
				value *= float(e.get("value", 1.0))
			_:
				value += float(e.get("value", 0.0))
	return value

## 某键当前有效值的聚合（无基础值时 base 取 0）。
func value_of(key: String, now_minute: int = -1, base: float = 0.0) -> float:
	return apply(base, key, now_minute)

func has_key(key: String) -> bool:
	return _entries.has(key) and not _entries[key].is_empty()

func keys() -> Array:
	return _entries.keys()

## 快照：{key: [entry, ...]} 的深拷贝。
func to_dict() -> Dictionary:
	var out: Dictionary = {}
	for key in _entries:
		var arr: Array = []
		for e in _entries[key]:
			arr.append(e.duplicate(true))
		out[key] = arr
	return out

func from_dict(doc: Dictionary) -> void:
	_entries.clear()
	for key in doc.keys():
		var arr: Array = []
		for e in doc[key]:
			arr.append(Dictionary(e).duplicate(true))
		_entries[key] = arr

static func is_known_key(key: String) -> bool:
	return KNOWN_KEYS.has(key)
