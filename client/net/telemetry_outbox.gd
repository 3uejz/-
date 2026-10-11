class_name TelemetryOutbox
extends RefCounted
## 遥测离线队列：累积事件、按 event_id 去重、批量刷出。
##
## 后端按 event_id 去重（openapi `/telemetry/events`，单批 ≤500）。本队列保证
## 同一事件不重复入队，网络失败时保留待下次刷出，被后端拒绝的事件永久丢弃。

const MAX_EVENTS := 5000
const MAX_BATCH := 500
const ACCEPTED_MEMORY := 10000

var _queue: Array[Dictionary] = []
var _accepted: Dictionary = {}      # event_id -> true（近期已成功，防重复入队）
var last_rejected: Array[Dictionary] = []  # [{event_id, code}]

func enqueue(event: Dictionary, event_id: String = "") -> String:
	var e := event.duplicate(true)
	var id := event_id if event_id != "" else str(e.get("event_id", ""))
	if id == "":
		id = Uuid.v7()
	e["event_id"] = id
	if _accepted.has(id) or _contains_pending(id):
		return id
	_queue.append(e)
	while _queue.size() > MAX_EVENTS:
		_queue.pop_front()
	return id

func pending_count() -> int:
	return _queue.size()

func pending_events() -> Array[Dictionary]:
	return _queue.duplicate(true)

func take_batch(limit: int = MAX_BATCH) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var n: int = mini(limit, _queue.size())
	for i in range(n):
		out.append(_queue[i].duplicate(true))
	return out

## 批量刷出（同步）。client 需实现 post_telemetry(events) -> 结果 Dictionary。
func flush(client: ApiClient) -> Dictionary:
	if _queue.is_empty():
		return {"ok": true, "skipped": true, "accepted": 0, "rejected": 0, "remaining": 0}
	var batch := take_batch(MAX_BATCH)
	var result := client.post_telemetry(batch)
	return apply_result(batch, result)

## 应用一次上报结果（纯函数，供同步 flush 与异步网关复用）。
## batch 为本次发送的事件（take_batch 的返回，尚未从队列移除）。
func apply_result(batch: Array, result: Dictionary) -> Dictionary:
	if not result.get("ok", false):
		return {
			"ok": false,
			"skipped": false,
			"accepted": 0,
			"rejected": 0,
			"remaining": _queue.size(),
			"code": str(result.get("code", "")),
			"offline": bool(result.get("offline", false)),
		}
	var data: Variant = result.get("data", {})
	var accepted_ids: Array = []
	var rejected_items: Array = []
	if typeof(data) == TYPE_DICTIONARY:
		accepted_ids = (data as Dictionary).get("accepted", [])
		rejected_items = (data as Dictionary).get("rejected", [])
	var accepted_set: Dictionary = {}
	for id in accepted_ids:
		accepted_set[str(id)] = true
	var rejected_ids: Dictionary = {}
	last_rejected = []
	for item in rejected_items:
		if typeof(item) == TYPE_DICTIONARY:
			var rid := str((item as Dictionary).get("event_id", ""))
			rejected_ids[rid] = true
			last_rejected.append({"event_id": rid, "code": str((item as Dictionary).get("code", ""))})
	_remove_ids(accepted_set)
	_remove_ids(rejected_ids)
	for id in accepted_set.keys():
		_accepted[id] = true
	if _accepted.size() > ACCEPTED_MEMORY:
		_accepted = {}
	return {
		"ok": true,
		"skipped": false,
		"accepted": accepted_set.size(),
		"rejected": rejected_ids.size(),
		"remaining": _queue.size(),
	}

func clear() -> void:
	_queue.clear()
	last_rejected.clear()

func to_dict() -> Dictionary:
	return {
		"queue": _queue.duplicate(true),
		"accepted": _accepted.keys(),
	}

func from_dict(data: Dictionary) -> void:
	_queue.clear()
	_accepted.clear()
	for item in data.get("queue", []):
		if typeof(item) == TYPE_DICTIONARY and (item as Dictionary).has("event_id"):
			_queue.append(item)
	for id in data.get("accepted", []):
		_accepted[str(id)] = true

func _contains_pending(id: String) -> bool:
	for e in _queue:
		if str(e.get("event_id", "")) == id:
			return true
	return false

func _remove_ids(ids: Dictionary) -> void:
	if ids.is_empty():
		return
	var kept: Array[Dictionary] = []
	for e in _queue:
		if not ids.has(str(e.get("event_id", ""))):
			kept.append(e)
	_queue = kept
