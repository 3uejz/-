class_name Illustration
extends RefCounted
## 内联水墨插画解析（R35、R57；任务 47 收尾）。
## 叙事消息可携带插画键；本模块把键解析为随内容包分发的插画资源路径。
## 资源缺失时回退占位（水墨留白），保证叙事流不因缺图而中断。纯逻辑，headless 可测。

const DIR: String = "res://art/illustrations"
const EXTENSIONS: Array[String] = [".tres", ".png", ".svg", ".webp"]

## 解析插画键为 {key, available, path, caption, placeholder}。
## caption 缺省时回退到键名（去前缀），仅作占位说明。
static func resolve(key: String, caption: String = "", resolver: Callable = Callable()) -> Dictionary:
	var clean: String = _normalize(key)
	if caption.is_empty() and resolver.is_valid():
		var nm: Variant = resolver.call(key)
		if nm != null:
			caption = String(nm)
	var found: String = _find_asset(clean)
	var available: bool = not found.is_empty()
	return {
		"key": clean,
		"available": available,
		"path": found if available else DIR.path_join("_placeholder.tres"),
		"caption": caption if not caption.is_empty() else clean,
		"placeholder": not available,
	}

## 插画资源是否随内容包存在。
static func has_asset(key: String) -> bool:
	return not _find_asset(_normalize(key)).is_empty()

static func _normalize(key: String) -> String:
	var k: String = key.strip_edges()
	for prefix in ["illus.", "illustration.", "art."]:
		if k.begins_with(prefix):
			k = k.substr(prefix.length())
	return k

static func _find_asset(name: String) -> String:
	if name.is_empty():
		return ""
	for ext in EXTENSIONS:
		var path: String = DIR.path_join(name + ext)
		if ResourceLoader.exists(path) or FileAccess.file_exists(path):
			return path
	return ""
