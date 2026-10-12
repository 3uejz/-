class_name Flavor
extends RefCounted
## 文案变化层：为高频动作提供确定性、场景化的措辞变体，避免叙事重复单调。
## 纯静态、不消费模拟随机源（只用稳定哈希），故不改变任何玩法确定性；headless 可测。

const MINUTES_PER_DAY: int = 1440

## 时段 → 中文描述（覆盖一昼夜）。
const DAY_PARTS: Array = [
	[0, "凌晨"], [300, "清晨"], [480, "上午"], [690, "中午"],
	[810, "下午"], [1020, "傍晚"], [1140, "夜晚"], [1320, "深夜"],
]

## 各动作的措辞变体池（{part} 由 day_part 填充）。
const POOLS: Dictionary = {
	"wait": [
		"你在{part}静候时光流转。",
		"{part}，你放空思绪，任时间悄然走过。",
		"你驻足停留，看{part}的光影缓缓移动。",
	],
	"sleep": [
		"{part}万籁俱寂，你合眼沉沉睡去。",
		"{part}，你蜷进被褥，把一天交还给梦境。",
	],
	"eat": [
		"你寻了处安静角落，慢慢吃完这一餐。",
		"热气腾腾的一餐下肚，疲惫也散了几分。",
		"你细品食物的滋味，让饱足感缓缓漫上来。",
	],
	"exercise": [
		"你活动开筋骨，出了一身薄汗。",
		"你在{part}的场地上挥洒力气，气息渐渐沉稳。",
		"你把身体逼到极限，再缓缓收势。",
	],
	"work": [
		"你埋头于手头的活计，时间在忙碌中加速。",
		"你把手上的事一件件推进，无暇分神。",
		"你在{part}专注投入，杂念被工作填满。",
	],
	"study": [
		"你摊开书本，一字一句地啃读。",
		"你在{part}沉下心来，把陌生的东西一点点吃透。",
		"你反复推敲琢磨，纸页被翻得沙沙作响。",
	],
	"buy": [
		"你掂量再三，还是把它买下了。",
		"你把心仪之物收入囊中，心里踏实了些。",
	],
	"sell": [
		"你把它脱手，换回了些现钱。",
		"你与买家一番讨价，最终成交。",
	],
	"bank": [
		"你在柜台前办理妥当。",
		"你数清数目，与柜员核对无误。",
	],
	"interact": [
		"你们寒暄了几句，气氛还算融洽。",
		"你斟酌着措辞，把话说了出来。",
	],
}


## 依据游戏内分钟数返回时段描述。
static func day_part(minutes: int) -> String:
	var m: int = ((minutes % MINUTES_PER_DAY) + MINUTES_PER_DAY) % MINUTES_PER_DAY
	var label: String = String(DAY_PARTS[0][1])
	for entry in DAY_PARTS:
		if m >= int(entry[0]):
			label = String(entry[1])
	return label


## 从变体池中确定性地取一条并填充 {part}。
## key 建议用 "动作:时间戳" 形式，使同一时段同动作措辞稳定、跨时段有变化。
static func pick(pool_key: String, minutes: int, key: String = "") -> String:
	var pool: Array = POOLS.get(pool_key, [])
	if pool.is_empty():
		return ""
	var seed_key: String = "%s:%d:%s" % [pool_key, minutes, key]
	var idx: int = absi(seed_key.hash()) % pool.size()
	return String(pool[idx]).replace("{part}", day_part(minutes))


## 时间线首句：把时段与动作合成一句场景化描述。
static func time_line(pool_key: String, minutes: int, key: String = "") -> String:
	var text: String = pick(pool_key, minutes, key)
	if text.is_empty():
		return "你在%s做了片刻停留。" % day_part(minutes)
	return text
