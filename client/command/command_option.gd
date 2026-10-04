class_name CommandOption
extends RefCounted
## 指令多义候选：当对象/动词存在多种合法解释时，向玩家展示至多 9 项，
## 支持以序号（如「2」）直接选择。见 R27 验收 13、design.md「多义」。
## 字段：index、label、target、reason。

var index: int = 0            ## 展示序号，从 1 起
var label: String = ""        ## 展示文本
var target: Dictionary = {}   ## 候选指向（对象条目或动词条目）
var reason: String = ""       ## 产生/排序原因说明

func _init(p_index: int = 0, p_label: String = "", p_target: Dictionary = {}, p_reason: String = "") -> void:
	index = p_index
	label = p_label
	target = p_target
	reason = p_reason

func to_dict() -> Dictionary:
	return {
		"index": index,
		"label": label,
		"target": target.duplicate(true),
		"reason": reason,
	}
