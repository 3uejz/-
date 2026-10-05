class_name PresentationBus
extends RefCounted
## 文字 UI 与 3D 表现层之间的单向事件总线。
## 逻辑层与文字 UI 只负责 publish；3D 表现层只订阅并渲染，绝不回写玩法状态。

var _handlers: Dictionary = {}   # event -> Array[Callable]
var _next_token: int = 0
var _tokens: Dictionary = {}     # token -> {event, callable}


## 订阅事件，返回可用于取消订阅的 token。
func subscribe(event: String, handler: Callable) -> int:
	_next_token += 1
	var token := _next_token
	if not _handlers.has(event):
		_handlers[event] = []
	_handlers[event].append(handler)
	_tokens[token] = {"event": event, "callable": handler}
	return token


## 取消订阅。
func unsubscribe(token: int) -> bool:
	if not _tokens.has(token):
		return false
	var entry: Dictionary = _tokens[token]
	var handlers: Array = _handlers.get(entry["event"], [])
	handlers.erase(entry["callable"])
	_tokens.erase(token)
	return true


## 发布事件给所有订阅者；单个订阅者抛错不影响其他订阅者。
func publish(event: String, payload: Variant = null) -> int:
	if not _handlers.has(event):
		return 0
	var delivered := 0
	for handler in _handlers[event].duplicate():
		if handler is Callable and handler.is_valid():
			handler.call(payload)
			delivered += 1
	return delivered


func subscriber_count(event: String) -> int:
	return _handlers.get(event, []).size()
