class_name HistoryView
extends RefCounted
## 叙事流历史视图模型：超长会话的窗口化加载（R35；任务 47 收尾）。
## 纯逻辑：只保留历史行数据并按滚动位置计算可见窗口，视图仅实例化窗口内的行，
## 避免一次性构建成千上万个 RichTextLabel 造成卡顿。行高为估算值（调用方注入），
## 用于滚动定位；真实高度由视图自行测得的可另行校正。

var _rows: Array = []

func count() -> int:
	return _rows.size()

func is_empty() -> bool:
	return _rows.is_empty()

func append(row: Dictionary) -> void:
	_rows.append(row.duplicate(true))

func clear() -> void:
	_rows.clear()

func row_at(index: int) -> Dictionary:
	if index < 0 or index >= _rows.size():
		return {}
	return _rows[index]

## 总高度（估算）：行数 × 行高。
func total_height(row_height: float) -> float:
	return float(_rows.size()) * row_height

## 可见窗口 [start, end)（含 overscan 预取），并夹到有效范围。
func visible_window(scroll_top: float, viewport_height: float, row_height: float, overscan: int = 2) -> Dictionary:
	if _rows.is_empty() or row_height <= 0.0:
		return {"start": 0, "end": 0}
	var first: int = int(floor(max(0.0, scroll_top) / row_height)) - overscan
	var last: int = int(ceil((max(0.0, scroll_top) + max(0.0, viewport_height)) / row_height)) + overscan
	first = clampi(first, 0, _rows.size())
	last = clampi(last, first, _rows.size())
	return {"start": first, "end": last}

## 窗口内的行（供视图实例化）。
func window_rows(scroll_top: float, viewport_height: float, row_height: float, overscan: int = 2) -> Array:
	var w: Dictionary = visible_window(scroll_top, viewport_height, row_height, overscan)
	var out: Array = []
	for i in range(int(w["start"]), int(w["end"])):
		out.append({"index": i, "row": _rows[i]})
	return out

## 把滚动位置夹到合法区间。
func clamp_scroll(scroll_top: float, viewport_height: float, row_height: float) -> float:
	var max_top: float = max(0.0, total_height(row_height) - viewport_height)
	return clampf(scroll_top, 0.0, max_top)

func to_dict() -> Dictionary:
	return {"rows": _rows.duplicate(true)}

func from_dict(data: Dictionary) -> void:
	_rows.clear()
	for r in data.get("rows", []):
		if r is Dictionary:
			_rows.append((r as Dictionary).duplicate(true))
