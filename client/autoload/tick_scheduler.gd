extends Node
## 分层 tick 派发（Autoload）。
## 各系统按频率注册；时钟推进后调用 tick(total_minutes)，按分钟/小时/日/季节/年逐边界派发，
## 单帧结算分钟数受 single_frame_cap 限制，剩余由后续帧继续，避免单帧卡死。

enum Tier { MINUTE, HOUR, DAY, SEASON, YEAR }

const DEFAULT_FRAME_CAP: int = 1024

var _systems: Dictionary = {}  # Tier -> Array[Callable]
var _last_minute: int = 0
var _last_season: int = 0
var _last_year: int = 0
var _seeded: bool = false

func register(system: Object, method: StringName, tier: Tier) -> void:
	var callable := Callable(system, method)
	if not _systems.has(tier):
		_systems[tier] = []
	if not (_systems[tier] as Array).has(callable):
		(_systems[tier] as Array).append(callable)

func unregister(system: Object, method: StringName, tier: Tier) -> void:
	if _systems.has(tier):
		(_systems[tier] as Array).erase(Callable(system, method))

## 推进到 total_minutes 并派发跨越的边界；返回本次实际推进的分钟数。
func tick(total_minutes: int, single_frame_cap: int = DEFAULT_FRAME_CAP) -> int:
	if total_minutes < _last_minute:
		push_error("TickScheduler 时间回退: %d -> %d" % [_last_minute, total_minutes])
		return 0
	if not _seeded:
		_seed(total_minutes)
		return 0
	var target: int = total_minutes
	if single_frame_cap > 0 and target - _last_minute > single_frame_cap:
		target = _last_minute + single_frame_cap
	var advanced: int = target - _last_minute
	while _last_minute < target:
		_step(target)
	return advanced

func _step(target: int) -> void:
	var next: int = target
	if _has(Tier.MINUTE):
		next = _last_minute + 1
	else:
		next = mini(next, _next_hour(_last_minute))
		next = mini(next, _next_day(_last_minute))
	_last_minute = next

	if _has(Tier.MINUTE):
		_emit(Tier.MINUTE, _last_minute)
	if _last_minute % 60 == 0:
		_emit(Tier.HOUR, _last_minute)
	if _last_minute % Gregorian.MINUTES_PER_DAY == 0:
		_emit(Tier.DAY, _last_minute)
		var cal: Dictionary = Gregorian.from_absolute_minutes(_last_minute)
		var season: int = _season_index(cal["month"])
		if season != _last_season:
			_last_season = season
			_emit(Tier.SEASON, _last_minute)
		if cal["year"] != _last_year:
			_last_year = cal["year"]
			_emit(Tier.YEAR, _last_minute)

func _seed(total_minutes: int) -> void:
	_last_minute = total_minutes
	var cal: Dictionary = Gregorian.from_absolute_minutes(total_minutes)
	_last_season = _season_index(cal["month"])
	_last_year = cal["year"]
	_seeded = true

func _has(tier: Tier) -> bool:
	return _systems.has(tier) and not (_systems[tier] as Array).is_empty()

func _emit(tier: Tier, total_minutes: int) -> void:
	if not _systems.has(tier):
		return
	for callable in _systems[tier]:
		callable.call(total_minutes)

static func _next_hour(minute: int) -> int:
	return (minute / 60 + 1) * 60

static func _next_day(minute: int) -> int:
	return (minute / Gregorian.MINUTES_PER_DAY + 1) * Gregorian.MINUTES_PER_DAY

static func _season_index(month: int) -> int:
	return ((month - 1) / 3) % 4
