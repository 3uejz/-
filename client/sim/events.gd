class_name EventsSystem
extends RefCounted
## 随机事件与日程调度（R6、R98；design「事件与日程调度」）。
##
## 四种触发：加权随机池、条件驱动、事件链状态机、日程系统，统一进入调度器。
## 优先级可打断低优先级事件与当前动作；每事件独立冷却叠加全局限流，支持互斥组；
## 抉择事件暂停时间；离线按同一调度补算并以挂机日志汇总（不逐事件回放）。

const BaselineScript = preload("res://sim/baseline.gd")

const TYPES: Array = ["opportunity", "accident", "social", "environment", "story"]
const TYPE_NAMES: Dictionary = {"opportunity": "机遇", "accident": "意外", "social": "社会", "environment": "环境", "story": "剧情"}
const TRIGGERS: Array = ["random", "condition", "chain", "schedule"]

const DEFAULT_GLOBAL_DAILY_CAP: int = BaselineScript.EVENT_DEFAULT_GLOBAL_DAILY_CAP
const MINUTES_PER_DAY: int = BaselineScript.EVENT_MINUTES_PER_DAY

## 事件库（示例基线，可由内容包/远程配置覆盖）。
const EVENTS: Dictionary = {
	"found_wallet": {"name": "捡到钱包", "type": "opportunity", "trigger": "random", "priority": 30, "weight": 10, "cooldown": 4320, "duration": 30, "exclusive": "", "conditions": {}, "choices": [{"label": "归还失主", "effects": {"karma": 5, "fame": 2}}, {"label": "据为己有", "effects": {"money": 5000, "karma": -5, "crime": "theft"}}], "chain": ""},
	"promotion_offer": {"name": "升职机会", "type": "opportunity", "trigger": "condition", "priority": 60, "weight": 20, "cooldown": 10080, "duration": 60, "exclusive": "career", "conditions": {"min_skill": 12}, "choices": [{"label": "接受挑战", "effects": {"career": 1}}, {"label": "婉拒", "effects": {"stress": -3}}], "chain": "promotion_aftermath"},
	"promotion_aftermath": {"name": "升职之后", "type": "story", "trigger": "chain", "priority": 40, "weight": 0, "cooldown": 0, "duration": 0, "exclusive": "career", "conditions": {}, "choices": [], "chain": ""},
	"traffic_accident": {"name": "交通事故", "type": "accident", "trigger": "random", "priority": 80, "weight": 4, "cooldown": 20160, "duration": 120, "exclusive": "", "conditions": {}, "choices": [{"label": "报警处理", "effects": {"health": -10, "money": -10000, "stress": 8}}, {"label": "私了", "effects": {"money": -30000, "stress": 5}}], "chain": ""},
	"illness_flu": {"name": "偶感风寒", "type": "accident", "trigger": "random", "priority": 50, "weight": 8, "cooldown": 10080, "duration": 0, "exclusive": "", "conditions": {}, "choices": [{"label": "去医院", "effects": {"health": 5, "money": -3000}}, {"label": "硬扛", "effects": {"health": -8, "stress": 4}}], "chain": ""},
	"street_performance": {"name": "街头演出", "type": "social", "trigger": "random", "priority": 30, "weight": 7, "cooldown": 4320, "duration": 60, "exclusive": "", "conditions": {}, "choices": [{"label": "驻足欣赏", "effects": {"mood": 5}}, {"label": "打赏", "effects": {"mood": 4, "money": -2000, "fame": 1}}], "chain": ""},
	"old_friend": {"name": "老友重逢", "type": "social", "trigger": "random", "priority": 40, "weight": 6, "cooldown": 20160, "duration": 120, "exclusive": "", "conditions": {}, "choices": [{"label": "叙旧", "effects": {"mood": 6, "relation": 5}}, {"label": "敷衍", "effects": {"relation": -3}}], "chain": ""},
	"rainstorm": {"name": "突降暴雨", "type": "environment", "trigger": "random", "priority": 35, "weight": 9, "cooldown": 2880, "duration": 180, "exclusive": "", "conditions": {}, "choices": [], "chain": ""},
	"heatwave": {"name": "酷暑高温", "type": "environment", "trigger": "schedule", "priority": 45, "weight": 0, "cooldown": 43200, "duration": 1440, "exclusive": "", "conditions": {"season": "summer"}, "choices": [], "chain": "", "schedule": {"months": [6, 7, 8]}},
	"festival_gathering": {"name": "节庆集会", "type": "social", "trigger": "schedule", "priority": 55, "weight": 0, "cooldown": 43200, "duration": 1440, "exclusive": "", "conditions": {}, "choices": [{"label": "参加", "effects": {"mood": 8, "relation": 4}}, {"label": "宅家", "effects": {"mood": -2}}], "chain": "", "schedule": {"months": [1]}},
	"lottery_win": {"name": "彩票中奖", "type": "opportunity", "trigger": "random", "priority": 70, "weight": 2, "cooldown": 14400, "duration": 0, "exclusive": "", "conditions": {"min_money": 1000}, "choices": [], "chain": ""},
	"mugging": {"name": "遭遇抢劫", "type": "accident", "trigger": "random", "priority": 85, "weight": 3, "cooldown": 43200, "duration": 60, "exclusive": "", "conditions": {}, "choices": [{"label": "反抗", "effects": {"health": -15, "money": -2000}}, {"label": "破财免灾", "effects": {"money": -10000, "stress": 6}}], "chain": "police_followup"},
	"police_followup": {"name": "警方后续", "type": "story", "trigger": "chain", "priority": 65, "weight": 0, "cooldown": 0, "duration": 0, "exclusive": "", "conditions": {}, "choices": [], "chain": ""},
	"business_opportunity": {"name": "商业机遇", "type": "opportunity", "trigger": "condition", "priority": 55, "weight": 15, "cooldown": 20160, "duration": 0, "exclusive": "business", "conditions": {"min_money": 100000}, "choices": [{"label": "投资", "effects": {"money": -100000, "investment": 1}}, {"label": "观望", "effects": {}}], "chain": ""},
	"charity_request": {"name": "慈善募捐", "type": "social", "trigger": "random", "priority": 25, "weight": 8, "cooldown": 10080, "duration": 30, "exclusive": "", "conditions": {}, "choices": [{"label": "捐款", "effects": {"money": -5000, "fame": 2, "karma": 4}}, {"label": "拒绝", "effects": {"karma": -1}}], "chain": ""},
	"mentor_appears": {"name": "贵人相助", "type": "story", "trigger": "condition", "priority": 65, "weight": 5, "cooldown": 43200, "duration": 0, "exclusive": "", "conditions": {"min_fame": 40}, "choices": [{"label": "拜师", "effects": {"skill_bonus": 1, "relation": 10}}, {"label": "婉拒", "effects": {}}], "chain": ""},
	"family_emergency": {"name": "家人急病", "type": "accident", "trigger": "random", "priority": 90, "weight": 3, "cooldown": 43200, "duration": 0, "exclusive": "", "conditions": {}, "choices": [{"label": "倾力救治", "effects": {"money": -50000, "relation": 10, "stress": 10}}, {"label": "无力承担", "effects": {"relation": -10, "stress": 15}}], "chain": ""},
	"weather_typhoon": {"name": "台风过境", "type": "environment", "trigger": "schedule", "priority": 75, "weight": 0, "cooldown": 43200, "duration": 2880, "exclusive": "", "conditions": {"season": "summer"}, "choices": [], "chain": "", "schedule": {"months": [7, 8]}},
	"old_photo": {"name": "旧照回忆", "type": "story", "trigger": "random", "priority": 20, "weight": 5, "cooldown": 20160, "duration": 30, "exclusive": "", "conditions": {"min_age": 30}, "choices": [{"label": "回味", "effects": {"mood": 4}}, {"label": "收起", "effects": {}}], "chain": ""},
	"neighbor_dispute": {"name": "邻里纠纷", "type": "social", "trigger": "random", "priority": 45, "weight": 6, "cooldown": 10080, "duration": 60, "exclusive": "", "conditions": {}, "choices": [{"label": "协商", "effects": {"relation": 3}}, {"label": "争吵", "effects": {"relation": -5, "stress": 5}}], "chain": ""},
	"investment_crash": {"name": "投资暴跌", "type": "accident", "trigger": "random", "priority": 70, "weight": 5, "cooldown": 20160, "duration": 0, "exclusive": "business", "conditions": {"min_money": 50000}, "choices": [{"label": "止损", "effects": {"money": -30000}}, {"label": "持有", "effects": {"stress": 8}}], "chain": ""},
	"travel_invite": {"name": "旅行邀约", "type": "social", "trigger": "condition", "priority": 40, "weight": 6, "cooldown": 20160, "duration": 0, "exclusive": "travel", "conditions": {"min_money": 50000}, "choices": [{"label": "同行", "effects": {"money": -20000, "mood": 8, "relation": 6}}, {"label": "婉拒", "effects": {"relation": -2}}], "chain": ""},
	"health_check": {"name": "体检建议", "type": "random", "priority": 35, "weight": 7, "cooldown": 43200, "duration": 0, "exclusive": "", "conditions": {"min_age": 40}, "choices": [{"label": "去体检", "effects": {"health": 3, "money": -2000}}, {"label": "忽略", "effects": {}}], "chain": ""},
	"inheritance_notice": {"name": "遗产通知", "type": "story", "trigger": "random", "priority": 60, "weight": 2, "cooldown": 43200, "duration": 0, "exclusive": "", "conditions": {"min_age": 35}, "choices": [{"label": "接受", "effects": {"money": 80000}}, {"label": "放弃", "effects": {"karma": 2}}], "chain": ""},
	"public_speech": {"name": "公开演讲邀约", "type": "opportunity", "trigger": "condition", "priority": 50, "weight": 8, "cooldown": 10080, "duration": 120, "exclusive": "", "conditions": {"min_fame": 30}, "choices": [{"label": "上台", "effects": {"fame": 5, "stress": 6}}, {"label": "推辞", "effects": {}}], "chain": ""},
	"lost_pet": {"name": "宠物走失", "type": "accident", "trigger": "condition", "priority": 75, "weight": 5, "cooldown": 43200, "duration": 1440, "exclusive": "", "conditions": {"has_pet": true}, "choices": [{"label": "寻找", "effects": {"stress": 8, "relation": 5}}, {"label": "放弃", "effects": {"mood": -6}}], "chain": ""},
	"study_abroad": {"name": "留学机遇", "type": "opportunity", "trigger": "condition", "priority": 65, "weight": 5, "cooldown": 43200, "duration": 0, "exclusive": "travel", "conditions": {"min_age": 18, "min_skill": 14}, "choices": [{"label": "申请", "effects": {"money": -200000, "skill_bonus": 2}}, {"label": "放弃", "effects": {}}], "chain": ""},
}


var _events: Dictionary = {}            # id -> event
var _cooldowns: Dictionary = {}         # id -> available_at minute
var _active_groups: Dictionary = {}     # group -> expire minute
var _daily_count: Dictionary = {}       # day index -> count
var _global_cap: int = DEFAULT_GLOBAL_DAILY_CAP
var _rng = null
var _log: Array = []


func _init(seed: int = 0, global_daily_cap: int = DEFAULT_GLOBAL_DAILY_CAP) -> void:
	_global_cap = global_daily_cap
	for id in EVENTS:
		_events[id] = (EVENTS[id] as Dictionary).duplicate(true)


func set_rng(rng) -> void:
	_rng = rng


func event_count() -> int:
	return _events.size()


func event_info(id: String) -> Dictionary:
	return (_events.get(id, {}) as Dictionary).duplicate(true)


func type_names() -> Dictionary:
	return TYPE_NAMES.duplicate()


## 条件匹配（R98.1）。
func conditions_met(event: Dictionary, context: Dictionary) -> bool:
	var conds: Dictionary = event.get("conditions", {})
	if conds.has("min_age") and int(context.get("age", 0)) < int(conds["min_age"]):
		return false
	if conds.has("max_age") and int(context.get("age", 999)) > int(conds["max_age"]):
		return false
	if conds.has("min_money") and int(context.get("money", 0)) < int(conds["min_money"]):
		return false
	if conds.has("min_health") and float(context.get("health", 100.0)) < float(conds["min_health"]):
		return false
	if conds.has("max_health") and float(context.get("health", 100.0)) > float(conds["max_health"]):
		return false
	if conds.has("min_fame") and float(context.get("fame", 0.0)) < float(conds["min_fame"]):
		return false
	if conds.has("min_skill") and int(context.get("skill", 0)) < int(conds["min_skill"]):
		return false
	if conds.has("season") and str(context.get("season", "")) != str(conds["season"]):
		return false
	if conds.has("weather") and str(context.get("weather", "")) != str(conds["weather"]):
		return false
	if conds.has("has_pet") and bool(context.get("has_pet", false)) != bool(conds["has_pet"]):
		return false
	return true


func _day_index(minute: int) -> int:
	return int(minute / MINUTES_PER_DAY)


## 冷却与互斥与限流检查（R98.3）。
func is_eligible(id: String, minute: int) -> bool:
	if not _events.has(id):
		return false
	if int(_cooldowns.get(id, -1)) > minute:
		return false
	var group: String = str((_events[id] as Dictionary).get("exclusive", ""))
	if group != "" and int(_active_groups.get(group, -1)) > minute:
		return false
	return true


func _activate(event: Dictionary, minute: int) -> void:
	var id: String = str(event.get("id", ""))
	var group: String = str(event.get("exclusive", ""))
	var duration: int = int(event.get("duration", 0))
	if group != "":
		_active_groups[group] = minute + maxi(duration, 60)
	_cooldowns[id] = minute + int(event.get("cooldown", 0))


## 触发一次调度：优先判定日程/条件事件，再按权重随机（R6.2）。
func tick(context: Dictionary, rng = null) -> Dictionary:
	var minute: int = int(context.get("minute", 0))
	var day: int = _day_index(minute)
	var used: int = int(_daily_count.get(day, 0))
	if used >= _global_cap:
		return {"ok": true, "event": {}, "reason": "global_rate_limited", "used": used}

	# 1) 日程事件（当天匹配月份）。
	var scheduled: Array = []
	# 2) 条件事件。
	var conditioned: Array = []
	var random_pool: Array = []
	for id in _events:
		var e: Dictionary = _events[id]
		if not is_eligible(id, minute) or not conditions_met(e, context):
			continue
		var trigger: String = str(e.get("trigger", "random"))
		if trigger == "schedule":
			var months: Array = (e.get("schedule", {}) as Dictionary).get("months", [])
			if months.is_empty() or months.has(int(context.get("month", 0))):
				scheduled.append(id)
		elif trigger == "condition":
			conditioned.append(id)
		elif trigger == "random":
			random_pool.append(id)

	var candidates: Array = conditioned + random_pool
	var chosen_id: String = ""
	if not scheduled.is_empty():
		# 日程事件当due即触发，无需权重。
		chosen_id = str(scheduled[0])
	elif candidates.is_empty():
		return {"ok": true, "event": {}, "reason": "none_available"}
	else:
		chosen_id = _weighted_pick(candidates, rng)

	var chosen: Dictionary = _events[chosen_id].duplicate(true)
	chosen["id"] = chosen_id
	_activate(chosen, minute)
	_daily_count[day] = used + 1
	var requires_choice: bool = not (chosen.get("choices", []) as Array).is_empty()
	return {"ok": true, "event": chosen, "pause": requires_choice, "requires_choice": requires_choice, "used": used + 1}


func _weighted_pick(candidates: Array, rng) -> String:
	var total: float = 0.0
	for id in candidates:
		total += maxf(0.0, float((_events[id] as Dictionary).get("weight", 1.0)))
	if total <= 0.0:
		return str(candidates[0])
	var roll: float = 0.0
	if rng != null:
		roll = rng.next_float() * total
	else:
		roll = total * 0.5
	var acc: float = 0.0
	for id in candidates:
		acc += maxf(0.0, float((_events[id] as Dictionary).get("weight", 1.0)))
		if roll < acc:
			return str(id)
	return str(candidates[candidates.size() - 1])


## 事件链状态机（R98.1）。
func resolve_choice(event: Dictionary, choice_index: int, minute: int) -> Dictionary:
	var choices: Array = event.get("choices", [])
	if choice_index < 0 or choice_index >= choices.size():
		return {"ok": false, "reason": "invalid_choice"}
	var choice: Dictionary = choices[choice_index]
	var next: String = str(event.get("chain", ""))
	var result: Dictionary = {"ok": true, "effects": (choice.get("effects", {}) as Dictionary).duplicate(true), "next": next}
	if next != "" and _events.has(next):
		result["chain_event"] = _events[next]
		_cooldowns[next] = minute + 1
	return result


## 优先级打断（R98.2）：高优先级可打断低优先级。
func can_interrupt(incoming: Dictionary, current_priority: int) -> bool:
	return int(incoming.get("priority", 0)) > current_priority


## 离线补算（R98.5、R6.5）：按天汇总，不逐事件回放。
func simulate_offline(start_minute: int, end_minute: int, context: Dictionary, rng = null) -> Dictionary:
	var entries: Array = []
	var total: int = 0
	var cursor: int = start_minute
	while cursor < end_minute:
		var day_start: int = _day_index(cursor) * MINUTES_PER_DAY
		# 每天触发 1..cap 次（按上下文）。
		var per_day: int = 1 + (int(rng.next_float() * 100.0) % _global_cap) if rng != null else 2
		for i in per_day:
			var r: Dictionary = tick({"minute": day_start + i * 60, "month": int(context.get("month", 0)), "season": str(context.get("season", ""))}, rng)
			if not (r["event"] as Dictionary).is_empty():
				total += 1
				entries.append({"minute": day_start, "name": str(r["event"]["name"]), "type": str(r["event"]["type"])})
		cursor = day_start + MINUTES_PER_DAY
	_log = entries.duplicate(true)
	return {"ok": true, "count": total, "log": entries}


func offline_log() -> Array:
	return _log.duplicate(true)


func reset_daily() -> void:
	_daily_count.clear()
