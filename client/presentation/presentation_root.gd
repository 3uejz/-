class_name PresentationRoot
extends Node
## 3D 表现层根节点：持有事件总线与场所场景管理器，并完成场所绑定。
## 文字 UI / 玩法模块通过 publish 与 show_place 单向驱动表现，不反向读取表现状态。

var bus: PresentationBus
var scenes: PlaceSceneManager

var _initialized := false


func _ready() -> void:
	ensure_initialized()


## 幂等初始化：headless 下 _ready 可能未触发，调用方亦可主动确保。
func ensure_initialized() -> void:
	if _initialized:
		return
	_initialized = true
	bus = PresentationBus.new()
	scenes = PlaceSceneManager.new()
	scenes.name = "PlaceScenes"
	add_child(scenes)
	PlaceBindings.register_all(scenes)


func show_place(place_key: String, lod_level: String = "") -> bool:
	ensure_initialized()
	return scenes.switch_place(place_key, lod_level)


func publish(event: String, payload: Variant = null) -> int:
	ensure_initialized()
	return bus.publish(event, payload)


func binding_count() -> int:
	ensure_initialized()
	return scenes.binding_count()
