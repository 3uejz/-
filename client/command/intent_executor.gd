class_name IntentExecutor
extends RefCounted
## 指令意图执行器：把 CommandIntent 落到 SimHost 与 GameState，产出叙事与面板指令。
## 纯逻辑、确定性、headless 可测；UI 只负责把返回的 narration/panel 呈现出来。
##
## 返回统一为 {ok, narration:[String], minutes:int, panel:String, action:String, error:String}。
## action 供 UI 层执行非模拟动作：save / load / pause / speed / restart（其余为空）。

const MINUTE: int = 1
const HOUR: int = 60
const DAY: int = 1440
const WEEK: int = 10080
const MONTH: int = 43200
const YEAR: int = 525600

const FlavorScript = preload("res://sim/flavor.gd")

var host                        # SimHost
var panels: Array = []          # 本次执行请求打开的面板 id（复合指令取最后一个）

func _init(sim_host) -> void:
	host = sim_host

# --- 对外入口 ---

func execute(intent) -> Dictionary:
	panels.clear()
	if intent == null:
		return _fail("无指令")
	if not intent.ok and String(intent.verb).is_empty():
		return _fail(intent.error if String(intent.error) != "" else "无法执行该指令")
	if String(intent.verb) == "然后":
		return _compound(intent)
	var result: Dictionary = _dispatch(intent)
	if not panels.is_empty():
		result["panel"] = panels.back()
	return result

# --- 复合指令 ---

func _compound(intent) -> Dictionary:
	var lines: Array = []
	var total := 0
	for part in intent.parts:
		var r: Dictionary = execute(part)
		if not bool(r["ok"]):
			return r
		lines.append_array(r["narration"])
		total += int(r["minutes"])
	var panel := ""
	if not panels.is_empty():
		panel = panels.back()
	return _ok(lines, total, panel)

# --- 动词分派 ---

func _dispatch(intent) -> Dictionary:
	match String(intent.verb):
		"帮助", "查看":
			return _help()
		# 面板查询
		"看自己":
			return _panel("character", "查看角色与属性。")
		"看技能":
			return _panel("skills", "查看技能树。")
		"看背包":
			return _panel("inventory", "查看背包与装备。")
		"看关系":
			return _panel("relations", "查看人际关系。")
		"看地图":
			return _panel("map", "查看地图。")
		"看资产":
			return _panel("finance", "查看财务与资产。")
		# 时间推进
		"等待", "快进":
			return _wait(intent)
		"睡":
			return _sleep(intent)
		"锻炼":
			return _exercise(intent)
		"工作":
			return _work(intent)
		"学习":
			return _study(intent)
		# 生理与物品
		"吃", "喝":
			return _eat(intent)
		"买":
			return _buy(intent)
		"卖":
			return _sell(intent)
		# 金融
		"存钱":
			return _deposit(intent)
		"取钱":
			return _withdraw(intent)
		# 职业
		"求职", "面试":
			return _job_apply(intent)
		"辞职":
			return _job_resign(intent)
		# 社交
		"聊天":
			return _interact(intent, "chat")
		"送礼":
			return _interact(intent, "gift")
		"约会":
			return _interact(intent, "dine")
		# 元指令（交 UI 处理）
		"存档":
			return _action("save", "已请求存档。")
		"读档":
			return _action("load", "已请求读档。")
		"暂停":
			return _action("pause", "已请求暂停。")
		"加速":
			return _action("speed", "已请求调整倍速。")
		"重开":
			return _action("restart", "已请求重开新的一生。")
		_:
			return _stub(String(intent.verb))

# --- 处理器 ---

func _help() -> Dictionary:
	var lines: Array = [
		"可用指令示例：",
		"· 状态：看自己 / 看技能 / 看背包 / 看关系 / 看地图 / 看资产",
		"· 时间：等待 1 小时 / 睡 8 小时 / 工作 4 小时 / 学习 <技能> 2 小时 / 锻炼 1 小时",
		"· 生活：吃 <食物> / 买 <物品> 2 / 卖 <物品> / 存钱 500 元 / 取钱 200 元",
		"· 社交：聊天 <人物> / 送礼 <人物> / 约会 <人物> / 求职 <岗位>",
	]
	return _ok(lines, 0, "")

func _wait(intent) -> Dictionary:
	var minutes := _duration_minutes(intent, HOUR)
	return _advance_time(minutes, {}, "wait")

func _sleep(intent) -> Dictionary:
	var minutes := _duration_minutes(intent, 8 * HOUR)
	return _advance_time(minutes, {"asleep": true}, "sleep")

func _exercise(intent) -> Dictionary:
	var minutes := _duration_minutes(intent, HOUR)
	var r: Dictionary = _advance_time(minutes, {"labor_intensity": 0.6}, "exercise")
	# 若指定了技能，一并计入练习；否则尝试体质类技能。
	var sid := _object_id(intent, "skill")
	if sid.is_empty():
		sid = _first_known_skill(["skill.physique", "skill.strength", "skill.sports", "skill.fitness"])
	var lines: Array = r["narration"]
	if not sid.is_empty() and host.skills.has_def(sid):
		var pr: Dictionary = _practice(sid, float(minutes) / 60.0)
		if bool(pr.get("ok", false)):
			lines.append("锻炼了 %s，等级 %d。" % [_skill_name(sid), int(pr.get("level", 0))])
	return _ok(lines, minutes, "")

func _work(intent) -> Dictionary:
	var minutes := _duration_minutes(intent, 8 * HOUR)
	if not host.jobs.is_employed(host.player()):
		return _fail("你目前没有工作，先「求职」。")
	var r: Dictionary = host.jobs.work(host.player(), float(minutes))
	if not bool(r.get("ok", false)):
		return _fail("无法工作：%s" % String(r.get("reason", "")))
	# work() 已扣体力与心情，这里只推进剩余代谢时间，避免重复扣减。
	var adv: Dictionary = _advance_time(minutes, {}, "work")
	var lines: Array = adv["narration"]
	lines.append("工作 %s，绩效 %.0f。" % [_duration_text(minutes), float(r.get("performance", 0.0))])
	return _ok(lines, minutes, "")

func _study(intent) -> Dictionary:
	var minutes := _duration_minutes(intent, 2 * HOUR)
	var sid := _object_id(intent, "skill")
	if sid.is_empty():
		return _fail("请指定要学习的技能。")
	if not host.skills.has_def(sid):
		return _fail("未知技能「%s」。" % sid)
	var r: Dictionary = _practice(sid, float(minutes) / 60.0)
	if not bool(r.get("ok", false)):
		return _fail("无法学习 %s：%s" % [_skill_name(sid), String(r.get("reason", ""))])
	var adv: Dictionary = _advance_time(minutes, {}, "study")
	var lines: Array = adv["narration"]
	lines.append("学习了 %s %s，当前等级 %d。" % [_skill_name(sid), _duration_text(minutes), int(r.get("level", 0))])
	if int(r.get("level_up", 0)) > 0:
		lines.append("技能提升！")
	return _ok(lines, minutes, "")

func _eat(intent) -> Dictionary:
	var item_id := _object_id(intent, "item")
	if not item_id.is_empty():
		if not host.items.has_def(item_id):
			return _fail("未知物品「%s」。" % item_id)
		var d: Dictionary = host.items.get_def(item_id)
		var cat := String(d.get("category", ""))
		if cat != "food" and cat != "medicine":
			return _fail("「%s」不能吃/喝。" % _item_name(item_id))
		var res: Dictionary = host.items.use(host.player(), item_id)
		if not bool(res.get("ok", false)):
			return _fail("无法食用：%s。" % String(res.get("reason", "")))
		host.sync_finances()
		return _ok(["你用了 %s。" % _item_name(item_id)], 0, "")
	# 无具体物品：一餐概况，直接补充饱食与营养。
	var food := {"protein": 10.0, "carbs": 24.0, "fat": 7.0, "vitamins": 6.0, "minerals": 4.0, "satiety": 38.0}
	var r: Dictionary = host.survival.eat(host.player(), food)
	if not bool(r.get("applied", false)):
		return _fail("无法进食。")
	host.sync_finances()
	return _ok([FlavorScript.time_line("eat", host.now_minutes()),
		"你吃了一餐，饱食度 +%.0f。" % float(r.get("satiety_added", 0.0))], 0, "")

func _buy(intent) -> Dictionary:
	var item_id := _object_id(intent, "item")
	if item_id.is_empty():
		return _fail("请指定要购买的物品。")
	if not host.items.has_def(item_id):
		return _fail("未知物品「%s」。" % item_id)
	var qty := _quantity(intent)
	var r: Dictionary = host.items.buy(host.player(), host.economy, host.account_id(), item_id, qty)
	if not bool(r.get("ok", false)):
		return _fail("购买失败：%s。" % String(r.get("reason", "")))
	host.sync_finances()
	var cost := float(r.get("cost_minor", 0)) / 100.0
	return _ok([FlavorScript.time_line("buy", host.now_minutes()),
		"你买了 %s×%d，花费 %.0f 元。" % [_item_name(item_id), qty, cost]], 0, "")

func _sell(intent) -> Dictionary:
	var item_id := _object_id(intent, "item")
	if item_id.is_empty():
		return _fail("请指定要出售的物品。")
	var qty := _quantity(intent)
	var r: Dictionary = host.items.sell(host.player(), host.economy, host.account_id(), item_id, qty)
	if not bool(r.get("ok", false)):
		return _fail("出售失败：%s。" % String(r.get("reason", "")))
	host.sync_finances()
	var proceeds := float(r.get("proceeds_minor", 0)) / 100.0
	return _ok([FlavorScript.time_line("sell", host.now_minutes()),
		"你卖出 %s×%d，得到 %.0f 元。" % [_item_name(item_id), qty, proceeds]], 0, "")

func _deposit(intent) -> Dictionary:
	var minor := _amount_minor(intent)
	var acct: String = host.account_id()
	if minor <= 0:
		minor = host.economy.cash(acct)
	if minor <= 0:
		return _fail("没有可存入的现金。")
	if not host.bank.deposit(host.economy, acct, minor):
		return _fail("存款失败。")
	host.sync_finances()
	return _ok([FlavorScript.time_line("bank", host.now_minutes()),
		"存入 %.0f 元。" % (float(minor) / 100.0)], 0, "")

func _withdraw(intent) -> Dictionary:
	var minor := _amount_minor(intent)
	var acct: String = host.account_id()
	if minor <= 0:
		minor = host.economy.bank(acct)
	if minor <= 0:
		return _fail("没有可支取的存款。")
	if not host.bank.withdraw(host.economy, acct, minor):
		return _fail("取款失败。")
	host.sync_finances()
	return _ok([FlavorScript.time_line("bank", host.now_minutes()),
		"取出 %.0f 元。" % (float(minor) / 100.0)], 0, "")

func _job_apply(intent) -> Dictionary:
	var job_id := _object_id(intent, "location")
	if job_id.is_empty():
		var openings: Array = host.jobs.openings(host.player())
		return _ok(["当前有 %d 个岗位可应聘；用「求职 <岗位>」申请。" % openings.size()], 0, "")
	if not host.jobs.has_def(job_id):
		return _fail("未知岗位「%s」。" % job_id)
	var r: Dictionary = host.jobs.apply(host.player(), job_id, host.rng, host.now_minutes())
	if r.is_empty():
		return _fail("求职失败。")
	if bool(r.get("hired", false)):
		return _ok(["你应聘 %s 成功，已入职。" % _job_name(job_id)], 0, "")
	if String(r.get("reason", "")) == "unqualified":
		return _ok(["你不符合 %s 的条件。" % _job_name(job_id)], 0, "")
	return _ok(["你应聘 %s 未通过，面试得分 %.0f。" % [_job_name(job_id), float(r.get("score", 0.0))]], 0, "")

func _job_resign(intent) -> Dictionary:
	if not host.jobs.is_employed(host.player()):
		return _fail("你目前没有工作。")
	var r: Dictionary = host.jobs.resign(host.player(), host.now_minutes())
	if not bool(r.get("ok", false)):
		return _fail("辞职失败。")
	return _ok(["你辞去了工作。"], 0, "")

func _interact(intent, type: String) -> Dictionary:
	var target := _object_id(intent, "person")
	if target.is_empty():
		return _fail("请指定人物。")
	var r: Dictionary = host.relations.apply_interaction(host.player(), target, type, {"minute": host.now_minutes()})
	if not bool(r.get("ok", false)):
		return _fail("互动失败：%s" % String(r.get("reason", "")))
	return _ok([FlavorScript.time_line("interact", host.now_minutes()),
		"你与 %s 互动（%s）。" % [target, String(r.get("level", ""))]], 0, "")

# --- 通用推进与叙事 ---

## 推进 time_minutes 并生成生理概况叙事。
func _advance_time(minutes: int, opts: Dictionary, flavor_key: String = "") -> Dictionary:
	var r: Dictionary = host.advance(minutes, opts)
	var p: Dictionary = host.player()["attrs"]["physiological"]
	var events: Array = r.get("events", [])
	var lines: Array = []
	if flavor_key != "":
		lines.append(FlavorScript.time_line(flavor_key, host.now_minutes()))
	lines.append("时间推进 %s。" % _duration_text(minutes))
	if _has_event(events, "death"):
		lines.append("你走到了生命的尽头。")
	elif _has_event(events, "dying"):
		lines.append("你已油尽灯枯，随时可能离世。")
	else:
		lines.append("饱食 %.0f / 口渴 %.0f / 体力 %.0f / 健康 %.0f。" % [
			float(p.get("hunger", 0.0)), float(p.get("thirst", 0.0)),
			float(p.get("stamina", 0.0)), float(p.get("health", 0.0)),
		])
	return _ok(lines, minutes, "")

func _practice(sid: String, hours: float) -> Dictionary:
	var p: Dictionary = host.player()
	var ctx := {
		"intelligence": _attr(p, "ability", "intelligence", 50.0),
		"willpower": _attr(p, "ability", "willpower", 50.0),
		"talents": p.get("talents", []),
		"now_minute": host.now_minutes(),
	}
	return host.skills.practice(p["skills"], sid, hours, ctx)

# --- 参数与命名辅助 ---

func _duration_minutes(intent, default_minutes: int) -> int:
	if not intent.params.has("duration"):
		return default_minutes
	var value := int(intent.params.get("duration", 0))
	var unit := String(intent.params.get("duration_unit", ""))
	return maxi(1, _unit_minutes(value, unit, default_minutes))

func _unit_minutes(value: int, unit: String, default_minutes: int) -> int:
	match unit:
		"秒":
			return maxi(1, value / 60)
		"分钟":
			return value * MINUTE
		"小时":
			return value * HOUR
		"天":
			return value * DAY
		"周":
			return value * WEEK
		"月":
			return value * MONTH
		"年":
			return value * YEAR
		_:
			return default_minutes if value <= 0 else value * MINUTE

## 金额参数（元/块/万元）换算为最小货币单位整数的绝对值。
func _amount_minor(intent) -> int:
	if intent.params.has("amount"):
		var v := int(intent.params.get("amount", 0))
		var unit := String(intent.params.get("amount_unit", "元"))
		var major := float(v) * (10000.0 if unit == "万元" else 1.0)
		return int(round(major * 100.0))
	if intent.params.has("number"):
		return int(intent.params.get("number", 0)) * 100
	return 0

## 数量参数：优先 quantity，其次解析器产出的 number，缺省 1。
func _quantity(intent) -> int:
	if intent.params.has("quantity"):
		return maxi(1, int(intent.params.get("quantity", 1)))
	if intent.params.has("number"):
		return maxi(1, int(intent.params.get("number", 1)))
	return 1

func _object_id(intent, type: String) -> String:
	var o: Dictionary = intent.object_of(type)
	var id := String(o.get("id", ""))
	if not id.is_empty():
		return id
	# 解析器未能链接目录时，用方法名/名词做一次名称回退匹配。
	return _resolve_by_name(type, String(intent.params.get("method", "")))

func _resolve_by_name(type: String, text: String) -> String:
	if text.is_empty():
		return ""
	match type:
		"skill":
			return _find_by_name(host.skills, text)
		"item":
			return _find_by_name(host.items, text)
		"location":
			# 岗位/机构名回退（求职等动词不声明对象类型，名称落在 method）。
			return _find_by_name(host.jobs, text)
		_:
			return ""

## 在目录系统中按 id 或名称（含前后缀包含）查找定义 id。
func _find_by_name(system, text: String) -> String:
	var needle := text.strip_edges()
	if needle.is_empty():
		return ""
	for id in system.ids():
		var d: Dictionary = system.get_def(String(id))
		var name := String(d.get("name", ""))
		if name == needle or name.contains(needle) or needle.contains(name):
			return String(id)
	return ""

func _has_event(events: Array, kind: String) -> bool:
	for e in events:
		if typeof(e) == TYPE_DICTIONARY and String((e as Dictionary).get("type", "")) == kind:
			return true
	return false

func _first_known_skill(candidates: Array) -> String:
	for sid in candidates:
		if host.skills.has_def(String(sid)):
			return String(sid)
	return ""

func _skill_name(sid: String) -> String:
	var d: Dictionary = host.skills.get_def(sid)
	return String(d.get("name", sid))

func _item_name(item_id: String) -> String:
	var d: Dictionary = host.items.get_def(item_id)
	return String(d.get("name", item_id))

func _job_name(job_id: String) -> String:
	var d: Dictionary = host.jobs.get_def(job_id)
	return String(d.get("name", job_id))

func _attr(player: Dictionary, group: String, key: String, fallback: float) -> float:
	var g: Variant = player.get("attrs", {})
	if g is Dictionary:
		var sub: Variant = (g as Dictionary).get(group, {})
		if sub is Dictionary:
			return float((sub as Dictionary).get(key, fallback))
	return fallback

func _duration_text(minutes: int) -> String:
	if minutes % DAY == 0 and minutes >= DAY:
		return "%d 天" % (minutes / DAY)
	if minutes % HOUR == 0:
		return "%d 小时" % (minutes / HOUR)
	return "%d 分钟" % minutes

# --- 结果构造 ---

func _ok(narration: Array, minutes: int, panel: String) -> Dictionary:
	return {"ok": true, "narration": narration, "minutes": minutes, "panel": panel, "action": "", "error": ""}

func _fail(message: String) -> Dictionary:
	return {"ok": false, "narration": [], "minutes": 0, "panel": "", "action": "", "error": message}

func _panel(id: String, hint: String) -> Dictionary:
	panels.append(id)
	return _ok([hint], 0, id)

func _action(kind: String, hint: String) -> Dictionary:
	return {"ok": true, "narration": [hint], "minutes": 0, "panel": "", "action": kind, "error": ""}

func _stub(verb: String) -> Dictionary:
	return _ok(["「%s」这个动作还没有接入模拟。" % verb], 0, "")
