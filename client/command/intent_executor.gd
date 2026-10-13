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
const VerbRegistryScript = preload("res://command/verb_registry.gd")

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
		"表白":
			return _confess(intent)
		"求婚":
			return _propose(intent)
		"离婚":
			return _divorce(intent)
		"怀孕":
			return _conceive(intent)
		"立遗嘱":
			return _write_will(intent)
		"看房":
			return _list_homes(intent)
		"买房":
			return _buy_home(intent)
		"卖房":
			return _sell_home(intent)
		"出租":
			return _rent_home(intent)
		"领养":
			return _adopt_pet(intent)
		"喂养":
			return _feed_pets(intent)
		"训练宠物":
			return _train_pets(intent)
		"收养":
			return _adopt_child(intent)
		"指定监护人":
			return _assign_guardian(intent)
		# 心理与精神健康
		"心理咨询":
			return _mental_treat(intent, "psychotherapy")
		"心理治疗":
			return _mental_treat(intent, "cbt")
		"精神科用药":
			return _mental_treat(intent, "medication")
		"重症干预":
			return _mental_treat(intent, "crisis_intervention")
		"放松":
			return _relax(intent)
		# 精神追求与信仰（D15）
		"修持":
			return _pursue_spirit(intent)
		"皈依":
			return _convert_faith(intent)
		"深化信仰":
			return _deepen_faith(intent)
		"化解危机":
			return _resolve_crisis(intent)
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
			# 面板查询：任意登记的面板动词「看 X」→ 打开对应面板。
			var pid := String(VerbRegistryScript.PANEL_VERBS.get(String(intent.verb), ""))
			if pid != "":
				return _panel(pid, "打开面板：%s。" % String(intent.verb))
			return _stub(String(intent.verb))

# --- 处理器 ---

func _help() -> Dictionary:
	var lines: Array = [
		"可用指令示例：",
		"· 面板：看自己 / 看技能 / 看背包 / 看关系 / 看地图 / 看资产 / 看医疗 / 看心理 / 看精神 / 看行情 / 看天气 …（全部 40 个面板）",
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
	var r: Dictionary = host.items.buy(host.player(), host.economy, host.account_id(), item_id, qty, null, "", "market", host.region_price_index())
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
	var r: Dictionary = host.items.sell(host.player(), host.economy, host.account_id(), item_id, qty, null, "", "market", 0.6, host.region_price_index())
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

func _confess(intent) -> Dictionary:
	var target := _object_id(intent, "person")
	if target.is_empty():
		return _fail("请指定人物。")
	if host.find_person(target).is_empty():
		return _fail("你与对方还不熟。")
	var p: Dictionary = host.player()
	var rel: Dictionary = host.relations.ensure_relation(p, target)
	var charm := _attr(p, "ability", "charm", 50.0)
	var mood := _attr(p, "psychological", "mood", 50.0)
	var r: Dictionary = host.family.confess(float(rel.get("favor", 0.0)), charm, mood, 50.0, host.rng)
	if bool(r.get("success", false)):
		host.relations.apply_interaction(p, target, "dine", {"minute": host.now_minutes(), "romance": true})
		return _ok(["你向 %s 表白，对方答应了。" % _person_name(target)], 0, "")
	return _ok(["你向 %s 表白，对方婉拒了。" % _person_name(target)], 0, "")

func _propose(intent) -> Dictionary:
	var target := _object_id(intent, "person")
	if target.is_empty():
		return _fail("请指定人物。")
	var rel: Dictionary = host.relations.get_relation(host.player(), target)
	if rel.is_empty():
		return _fail("你与 %s 还不熟。" % _person_name(target))
	var charm := _attr(host.player(), "ability", "charm", 50.0)
	var r: Dictionary = host.family.propose(float(rel.get("favor", 0.0)), float(rel.get("intimacy", 0.0)), charm, host.rng)
	if not bool(r.get("ok", false)):
		return _fail("还不到求婚的时候，需要更高的好感与亲密度。")
	if bool(r.get("success", false)):
		host.marry_with(target)
		return _ok(["你向 %s 求婚成功，你们结婚了。" % _person_name(target)], 0, "")
	return _ok(["你向 %s 求婚，对方暂时没有答应。" % _person_name(target)], 0, "")

func _divorce(_intent) -> Dictionary:
	var r: Dictionary = host.divorce()
	if not bool(r.get("ok", false)):
		return _fail("你目前没有配偶。")
	return _ok(["你结束了这段婚姻。"], 0, "")

func _person_name(person_id: String) -> String:
	var npc: Dictionary = host.find_person(person_id)
	return String(npc.get("name", person_id))

func _conceive(_intent) -> Dictionary:
	var r: Dictionary = host.try_conceive()
	if not bool(r.get("ok", false)):
		match String(r.get("reason", "")):
			"not_married":
				return _fail("你还没有结婚。")
			"already_pregnant":
				return _fail("你们已经有孩子在孕育中了。")
			_:
				return _fail("暂时不能受孕。")
	var due := int((r.get("pregnancy", {}) as Dictionary).get("due_minutes", 0))
	return _ok(["你们开始迎接新生命，预计在游戏第 %d 天前后分娩。" % (due / 1440 + 1)], 0, "")

func _write_will(_intent) -> Dictionary:
	var p: Dictionary = host.player()
	var fam: Dictionary = p.get("family", {})
	var bens: Array = []
	var sid := String(fam.get("spouse_id", ""))
	if sid != "":
		bens.append({"id": sid, "share": 1.0})
	else:
		var kids: Array = fam.get("children_ids", [])
		if kids.is_empty():
			return _fail("你还没有配偶或子女，暂时无人可继承。")
		var share := 1.0 / float(kids.size())
		for cid in kids:
			bens.append({"id": String(cid), "share": share})
	p["will"] = {"written_minutes": host.now_minutes(), "beneficiaries": bens}
	return _ok(["你立下遗嘱，指定了 %d 位继承人。" % bens.size()], 0, "")

func _list_homes(_intent) -> Dictionary:
	var rows: Array = []
	for p in host.property_listings():
		rows.append("%s（%s %.0f㎡）约 %.1f 万元，月供约 %.0f 元" % [
			String(p.get("name", "")), String(p.get("layout", "")), float(p.get("area_sqm", 0.0)),
			float(p.get("price", 0)) / 10000.0, float(p.get("monthly_payment", 0)) / 100.0])
	for p in host.property_owned():
		rows.append("【自有】%s（%s %.0f㎡）估值约 %.1f 万元%s" % [
			String(p.get("name", "")), String(p.get("layout", "")), float(p.get("area_sqm", 0.0)),
			float(p.get("price", 0)) / 10000.0, "，已出租" if bool(p.get("rented", false)) else ""])
	if rows.is_empty():
		return _ok(["当前没有可看的房源。"], 0, "")
	return _ok(["房源信息："] + rows, 0, "")

func _buy_home(intent) -> Dictionary:
	var prop_id := _object_id(intent, "property")
	if prop_id.is_empty():
		return _fail("请指定房源。")
	var r: Dictionary = host.property_purchase(prop_id)
	if not bool(r.get("ok", false)):
		return _fail("购买失败：%s。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["你买下了这套房，首付 %.1f 万元，月供 %.0f 元。" % [
		float(r.get("down", 0)) / 10000.0, float(r.get("monthly_payment", 0)) / 100.0]], 0, "")

func _sell_home(intent) -> Dictionary:
	var prop_id := _object_id(intent, "property")
	if prop_id.is_empty():
		return _fail("请指定房产。")
	var r: Dictionary = host.property_sell(prop_id)
	if not bool(r.get("ok", false)):
		return _fail("出售失败：%s。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["你卖掉了这套房，净得 %.1f 万元。" % (float(r.get("net", 0)) / 10000.0)], 0, "")

func _rent_home(intent) -> Dictionary:
	var prop_id := _object_id(intent, "property")
	if prop_id.is_empty():
		return _fail("请指定房产。")
	var r: Dictionary = host.property_rent(prop_id)
	if not bool(r.get("ok", false)):
		return _fail("出租失败：%s。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["已出租，月租 %.0f 元。" % (float(r.get("monthly_rent", 0)) / 100.0)], 0, "")

func _adopt_pet(intent) -> Dictionary:
	var species := _object_id(intent, "pet_species")
	if species.is_empty():
		return _fail("请指定要领养的宠物种类。")
	var r: Dictionary = host.adopt_pet(species)
	if not bool(r.get("ok", false)):
		match String(r.get("reason", "")):
			"insufficient_funds":
				return _fail("资金不足，无法领养。")
			"unknown_species":
				return _fail("没有这种宠物。")
			_:
				return _fail("暂时无法领养。")
	var pet_rec: Dictionary = r.get("pet", {})
	return _ok(["你领养了一只「%s」（%s）。" % [
		String(pet_rec.get("name", species)), String(pet_rec.get("species", species))]], 0, "")

func _feed_pets(_intent) -> Dictionary:
	var done: Array = host.feed_pets()
	if done.is_empty():
		return _fail("你没有需要喂养的宠物。")
	return _ok(["你喂饱了：%s。" % ", ".join(done)], 0, "")

func _train_pets(_intent) -> Dictionary:
	var done: Array = host.train_pets()
	if done.is_empty():
		return _fail("你没有可以训练的宠物。")
	return _ok(["你训练了：%s。" % ", ".join(done)], 0, "")

func _adopt_child(_intent) -> Dictionary:
	var r: Dictionary = host.adopt_child()
	if not bool(r.get("ok", false)):
		return _fail("暂时无法收养子女。")
	var child: Dictionary = r.get("child", {})
	return _ok(["你收养了 %s，从此担起养育之责。" % String(child.get("name", "一名子女"))], 0, "")

func _assign_guardian(intent) -> Dictionary:
	var target := _object_id(intent, "person")
	if target.is_empty():
		return _fail("请指定要托付的人。")
	var r: Dictionary = host.assign_guardian(target)
	if not bool(r.get("ok", false)):
		return _fail("未找到此人，无法指定为监护人。")
	return _ok(["你指定 %s 为子女的监护人。" % _person_name(target)], 0, "")

func _mental_treat(intent, method: String) -> Dictionary:
	var key := _object_id(intent, "mental_disorder")
	var r: Dictionary = host.mental_treat(method, key)
	if not bool(r.get("ok", false)):
		match String(r.get("reason", "")):
			"no_active_disorder":
				return _fail("你目前没有需要治疗的精神疾病。")
			"insufficient_funds":
				return _fail("资金不足，无法支付治疗费用。")
			"unknown_treatment":
				return _fail("暂不支持该治疗方式。")
			_:
				return _fail("治疗未能进行。")
	var outcome := String(r.get("outcome", "ineffective"))
	var outcome_cn: String = String({"cured": "根治", "remitted": "缓解", "ineffective": "无效"}.get(outcome, outcome))
	var lines: Array = ["接受了「%s」，对 %s 的结果：%s。" % [
		String(r.get("method_name", method)), String(r.get("key_name", "")), outcome_cn]]
	if bool(r.get("misdiagnosed", false)):
		lines.append("存在误诊，疗效打折。")
	if bool(r.get("side_effect", false)):
		lines.append("出现药物副作用。")
	return _ok(lines, 0, "")

func _relax(intent) -> Dictionary:
	var minutes := _duration_minutes(intent, HOUR)
	host.apply_emotion_event("praise")
	var adv: Dictionary = _advance_time(minutes, {}, "rest")
	var lines: Array = adv["narration"]
	var et: String = host.emotion_state()
	lines.append("你静心放松，情绪趋于%s。" % _emotion_cn(et))
	return _ok(lines, minutes, "")

func _emotion_cn(state: String) -> String:
	match state:
		"anxious":
			return "焦虑"
		"depressed":
			return "低落"
		"manic":
			return "亢奋"
		_:
			return "平静"

# --- 精神追求与信仰（D15） ---

func _pursue_spirit(intent) -> Dictionary:
	var kind := _object_id(intent, "pursuit")
	if kind.is_empty():
		return _fail("未指定修持法门；可修持冥想、修行、哲学阅读、写作、自省、志愿服务或艺术创作。")
	if not host.spirituality.PURSUITS.has(kind):
		return _fail("未知的修持法门。")
	var minutes := _duration_minutes(intent, HOUR)
	var adv: Dictionary = _advance_time(minutes, {}, "rest")
	var lines: Array = adv["narration"]
	var r: Dictionary = host.pursue_spirit(kind, minutes)
	if not bool(r.get("ok", false)):
		return _fail("此次修持未能进行。")
	lines.append("你投入「%s」%d 分钟，心境%s。" % [String(r.get("name", kind)), minutes, ("更进一层（%s）" % String(r.get("realm", ""))) if bool(r.get("realm_unlocked", false)) else "渐趋平和"])
	return _ok(lines, minutes, "")

func _convert_faith(intent) -> Dictionary:
	var faith := _object_id(intent, "faith")
	if faith.is_empty():
		return _fail("未指定信仰；可皈依佛教、道家、基督教、伊斯兰教或斯多葛、存在主义等流派。")
	var r: Dictionary = host.convert_faith(faith)
	if not bool(r.get("ok", false)):
		return _fail("无法皈依该信仰。")
	return _ok(["你皈依了「%s」（%s），从此有了精神寄托。" % [String(r.get("name", faith)), "宗教" if String(r.get("type", "")) == "religion" else "哲学"]], 0, "")

func _deepen_faith(intent) -> Dictionary:
	var minutes := _duration_minutes(intent, HOUR)
	var adv: Dictionary = _advance_time(minutes, {}, "rest")
	var lines: Array = adv["narration"]
	var r: Dictionary = host.deepen_faith(minutes)
	if not bool(r.get("ok", false)):
		return _fail("你尚未皈依任何信仰，无从深化。")
	lines.append("你潜心修持「%s」%d 分钟，境界%s。" % [String(r.get("faith_name", "")), minutes, String(r.get("realm", ""))])
	return _ok(lines, minutes, "")

func _resolve_crisis(intent) -> Dictionary:
	var exit_kind := _object_id(intent, "crisis_exit")
	if exit_kind.is_empty():
		return _fail("请指定化解出口：宗教熏修、哲学省思、心理疏导或志愿服务。")
	var r: Dictionary = host.resolve_spirit_crisis(exit_kind)
	if not bool(r.get("ok", false)):
		return _fail("当前没有需要化解的精神危机。" if String(r.get("reason", "")) == "no_crisis" else "该出口不适用于当前危机。")
	return _ok(["你以「%s」化解了精神危机，内心重归澄明。" % _exit_cn(String(r.get("via", exit_kind)))], 0, "")

func _exit_cn(kind: String) -> String:
	match kind:
		"religion":
			return "宗教熏修"
		"philosophy":
			return "哲学省思"
		"psychology":
			return "心理疏导"
		"volunteering":
			return "志愿服务"
		_:
			return kind

func _reason_cn(reason: String) -> String:
	match reason:
		"not_listed", "unavailable":
			return "此房源不可交易"
		"not_owned":
			return "你并不拥有这套房产"
		"purchase_restricted":
			return "受限购政策限制"
		"insufficient_funds":
			return "资金不足"
		"no_economy":
			return "经济系统未就绪"
		_:
			return reason if reason != "" else "未知原因"

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
