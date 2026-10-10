class_name DomainWake
extends RefCounted
## 休眠唤醒的领域状态补算契约（R52；gaps 系统性问题 7）。
##
## RegionManager.wake 负责区域人口/经济/事件的统计快进；本类补上"领域实体"在休眠期的演化：
## 案件、灾害、在建工程、逾期催收、异常暴露、手术/试验等。所有规则确定性、幂等、时间守恒：
##   - 时间守恒：advance_to(t) 累计推进的分钟恰为从上次推进点到 t 的差值，不重复结算；
##   - 幂等：对同一 t 连续两次 advance_to，第二次返回 advanced_minutes=0 且不改变任何条目。
##
## 为便于 headless 测试与离线近似，本类不依赖 Autoload，也不持节点树，纯 Dictionary 状态。

const BaselineScript = preload("res://sim/baseline.gd")

const MINUTES_PER_DAY: int = BaselineScript.WAKE_MINUTES_PER_DAY
const MINUTES_PER_YEAR: float = 1440.0 * 365.25

const KIND_CASE: String = "case"
const KIND_DISASTER: String = "disaster"
const KIND_PROJECT: String = "project"
const KIND_LOAN: String = "loan"
const KIND_ANOMALY: String = "anomaly"
const KIND_SURGERY: String = "surgery"

const KIND_HANDLERS: Dictionary = {
	KIND_CASE: "advance_case",
	KIND_DISASTER: "advance_disaster",
	KIND_PROJECT: "advance_project",
	KIND_LOAN: "advance_loan",
	KIND_ANOMALY: "advance_anomaly",
	KIND_SURGERY: "advance_surgery",
}

const EPSILON: float = BaselineScript.WAKE_EPSILON

var _entries: Dictionary = {}      # id -> entry dict
var _now_minute: int = 0
var _advanced_total: int = 0

func now_minute() -> int:
	return _now_minute

func advanced_total() -> int:
	return _advanced_total

func entry_count() -> int:
	return _entries.size()

func get_entry(entry_id: String) -> Dictionary:
	return _entries.get(entry_id, {})

## 通用注册。entry 至少包含 id 与 kind；其余字段按 kind 取默认值。
## 领域参数可放在 opts["params"]，也可直接作为 opts 的额外键（自动归入 params）。
func register(entry_id: String, kind: String, opts: Dictionary = {}) -> Dictionary:
	if not KIND_HANDLERS.has(kind):
		return {}
	var params: Dictionary = Dictionary(opts.get("params", {})).duplicate(true)
	for k in opts.keys():
		if not (k in ["params", "region_id", "status", "started_minute", "progress", "total", "rate", "due_minute"]):
			params[k] = opts[k]
	var entry: Dictionary = {
		"id": entry_id,
		"kind": kind,
		"region_id": str(opts.get("region_id", "")),
		"status": str(opts.get("status", "pending")),
		"started_minute": int(opts.get("started_minute", _now_minute)),
		"last_minute": int(opts.get("started_minute", _now_minute)),
		"progress": float(opts.get("progress", 0.0)),
		"total": float(opts.get("total", 0.0)),
		"rate": float(opts.get("rate", 0.0)),
		"due_minute": int(opts.get("due_minute", -1)),
		"params": params,
		"result": {},
	}
	_entries[entry_id] = entry
	return entry

func register_project(entry_id: String, opts: Dictionary = {}) -> Dictionary:
	return register(entry_id, KIND_PROJECT, opts)

func register_case(entry_id: String, opts: Dictionary = {}) -> Dictionary:
	return register(entry_id, KIND_CASE, opts)

func register_disaster(entry_id: String, opts: Dictionary = {}) -> Dictionary:
	return register(entry_id, KIND_DISASTER, opts)

func register_loan(entry_id: String, opts: Dictionary = {}) -> Dictionary:
	return register(entry_id, KIND_LOAN, opts)

func register_anomaly(entry_id: String, opts: Dictionary = {}) -> Dictionary:
	return register(entry_id, KIND_ANOMALY, opts)

func register_surgery(entry_id: String, opts: Dictionary = {}) -> Dictionary:
	return register(entry_id, KIND_SURGERY, opts)

func is_resolved(entry_id: String) -> bool:
	var e: Dictionary = _entries.get(entry_id, {})
	return _is_resolved_status(str(e.get("status", "")))

## 按区域筛选未结算条目。
func active_entries_for_region(region_id: String) -> Array:
	var out: Array = []
	for id in _entries:
		var e: Dictionary = _entries[id]
		if str(e.get("region_id", "")) == region_id and not _is_resolved_status(str(e.get("status", ""))):
			out.append(e.duplicate(true))
	return out

## 推进到目标分钟。返回补算摘要；advanced_minutes 为本次结算的分钟数。
func advance_to(target_minute: int) -> Dictionary:
	var delta: int = target_minute - _now_minute
	if delta <= 0:
		return _summary(0, 0, {}, true)
	var by_kind: Dictionary = {}
	var resolved: Array = []
	for id in _entries.keys():
		var e: Dictionary = _entries[id]
		if _is_resolved_status(str(e.get("status", ""))):
			continue
		var entry_elapsed: int = target_minute - int(e.get("last_minute", _now_minute))
		if entry_elapsed <= 0:
			continue
		var before_status: String = str(e.get("status", ""))
		var handler: String = str(KIND_HANDLERS.get(str(e.get("kind", "")), ""))
		if handler != "" and has_method(handler):
			call(handler, e, entry_elapsed, target_minute)
		e["last_minute"] = target_minute
		by_kind[str(e.get("kind", ""))] = int(by_kind.get(str(e.get("kind", "")), 0)) + 1
		if before_status != str(e.get("status", "")) and _is_resolved_status(str(e.get("status", ""))):
			resolved.append(id)
	_now_minute = target_minute
	_advanced_total += delta
	return _summary(delta, _entries.size(), by_kind, false, resolved)

func _summary(delta: int, entries: int, by_kind: Dictionary, idempotent: bool, resolved: Array = []) -> Dictionary:
	return {
		"advanced_minutes": delta,
		"entries": entries,
		"by_kind": by_kind,
		"resolved": resolved,
		"resolved_count": resolved.size(),
		"idempotent": idempotent,
		"now_minute": _now_minute,
		"advanced_total": _advanced_total,
	}

static func _is_resolved_status(status: String) -> bool:
	return status in ["resolved", "closed", "completed", "contained", "recovered", "breached"]

# --- 各领域演化规则（确定性）---

func advance_project(e: Dictionary, elapsed: int, now: int) -> void:
	e["progress"] = float(e.get("progress", 0.0)) + float(e.get("rate", 0.0)) * float(elapsed)
	e["status"] = "in_progress"
	var total: float = float(e.get("total", 0.0))
	if total > 0.0 and float(e["progress"]) >= total - EPSILON:
		e["progress"] = total
		e["status"] = "completed"
		e["result"]["completed_minute"] = now

func advance_case(e: Dictionary, elapsed: int, now: int) -> void:
	e["status"] = "in_progress"
	var due: int = int(e.get("due_minute", -1))
	if due >= 0 and now >= due:
		e["status"] = "closed"
		e["result"]["closed_minute"] = now
	else:
		e["progress"] = float(e.get("progress", 0.0)) + float(elapsed)

func advance_disaster(e: Dictionary, elapsed: int, now: int) -> void:
	e["status"] = "in_progress"
	var duration: float = float(e.get("total", 0.0))
	if duration <= 0.0:
		duration = float(e["params"].get("duration_minutes", 0.0))
	if duration <= 0.0:
		return
	e["progress"] = float(e.get("progress", 0.0)) + float(elapsed)
	var severity0: float = float(e["params"].get("severity", 1.0))
	var remaining: float = maxf(0.0, 1.0 - float(e["progress"]) / duration)
	e["result"]["severity"] = severity0 * remaining
	e["result"]["damage"] = severity0 * clampf(float(e["progress"]) / duration, 0.0, 1.0)
	if float(e["progress"]) >= duration - EPSILON:
		e["progress"] = duration
		e["status"] = "resolved"
		e["result"]["severity"] = 0.0
		e["result"]["resolved_minute"] = now

func advance_loan(e: Dictionary, elapsed: int, now: int) -> void:
	e["status"] = "overdue"
	var principal: float = float(e["params"].get("principal", 0.0))
	var annual_rate: float = float(e["params"].get("annual_rate", 0.0))
	var interest: float = float(e.get("result", {}).get("interest", 0.0)) \
		+ principal * annual_rate * float(elapsed) / MINUTES_PER_YEAR
	e["result"]["interest"] = interest
	e["progress"] = float(e.get("progress", 0.0)) + float(elapsed)
	e["result"]["overdue_days"] = float(e["progress"]) / float(MINUTES_PER_DAY)

func advance_anomaly(e: Dictionary, elapsed: int, now: int) -> void:
	e["status"] = "exposed"
	var exposure: float = float(e["params"].get("exposure", 0.0)) \
		+ float(e.get("rate", 0.0)) * float(elapsed)
	e["progress"] = exposure
	e["result"]["exposure"] = exposure
	var threshold: float = float(e["params"].get("threshold", INF))
	if exposure >= threshold - EPSILON:
		e["status"] = "breached"
		e["result"]["breached_minute"] = now

func advance_surgery(e: Dictionary, elapsed: int, now: int) -> void:
	e["status"] = "in_progress"
	var required: float = float(e.get("total", 0.0))
	if required <= 0.0:
		required = float(e["params"].get("recovery_minutes", 0.0))
	e["progress"] = float(e.get("progress", 0.0)) + float(elapsed)
	if required > 0.0 and float(e["progress"]) >= required - EPSILON:
		e["progress"] = required
		e["status"] = "recovered"
		e["result"]["recovered_minute"] = now

# --- 序列化 ---

func to_dict() -> Dictionary:
	var entries: Dictionary = {}
	for id in _entries:
		entries[id] = _entries[id].duplicate(true)
	return {
		"now_minute": _now_minute,
		"advanced_total": _advanced_total,
		"entries": entries,
	}

func from_dict(doc: Dictionary) -> void:
	_now_minute = int(doc.get("now_minute", 0))
	_advanced_total = int(doc.get("advanced_total", 0))
	_entries.clear()
	var raw: Dictionary = Dictionary(doc.get("entries", {}))
	for id in raw:
		_entries[id] = Dictionary(raw[id]).duplicate(true)
