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
		# 组织与社团（D19）
		"加入组织":
			return _join_org(intent)
		"退出组织":
			return _leave_org(intent)
		"缴会费":
			return _pay_org_dues(intent)
		"组织任务":
			return _org_task(intent)
		"罢工":
			return _org_action(intent, "strike")
		"请愿":
			return _org_action(intent, "petition")
		"募捐":
			return _org_action(intent, "fundraiser")
		"游行":
			return _org_action(intent, "march")
		"抵制":
			return _org_action(intent, "boycott")
		# 语言与文化（D20）
		"学语言":
			return _study_language(intent)
		"沉浸":
			return _immerse_language(intent)
		"语言考试":
			return _language_exam(intent)
		"适应文化":
			return _adapt_culture(intent)
		# 残障与养老（D21）
		"装辅具":
			return _fit_device(intent)
		"康复训练":
			return _rehab(intent)
		"无障碍改造":
			return _accessible_retrofit(intent)
		"选养老":
			return _choose_care_mode(intent)
		"临终关怀":
			return _hospice(intent)
		"指定监护":
			return _guardianship(intent)
		# 农业与乡土（D22）
		"承包土地":
			return _acquire_land(intent)
		"播种":
			return _sow(intent)
		"收割":
			return _harvest_crop(intent)
		"养畜":
			return _raise_livestock(intent)
		"卖粮":
			return _sell_produce(intent)
		"农业补贴":
			return _farm_subsidy(intent)
		# 数字生活与黑客（D23）
		"开账号":
			return _open_account(intent)
		"实名认证":
			return _verify_identity(intent)
		"网络兼职":
			return _security_work(intent)
		"发布内容":
			return _publish_content(intent)
		"黑客攻击":
			return _hack_target(intent)
		# 后期科技（D24）
		"解锁科技":
			return _unlock_tech(intent)
		"应聘科技职业":
			return _apply_tech_career(intent)
		"科技任务":
			return _tech_mission(intent)
		"生物延寿":
			return _biotech(intent)
		# 知识产权与媒体（D25）
		"登记知识产权":
			return _register_ip(intent)
		"知识产权授权":
			return _license_ip(intent)
		"知识产权转让":
			return _transfer_ip(intent)
		"知识产权质押":
			return _pledge_ip(intent)
		"知识产权维权":
			return _sue_ip(intent)
		"开办媒体":
			return _open_media(intent)
		"发行作品":
			return _release_work(intent)
		# 制造业与供应链（D26）
		"开办工厂":
			return _found_factory(intent)
		"招工":
			return _mfg_hire(intent)
		"采购原料":
			return _mfg_purchase(intent)
		"生产":
			return _mfg_produce(intent)
		"接单":
			return _mfg_order(intent)
		"交付订单":
			return _mfg_deliver(intent)
		"改进经营模式":
			return _mfg_mode(intent)
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
		"· 面板：看自己 / 看技能 / 看背包 / 看关系 / 看地图 / 看资产 / 看医疗 / 看心理 / 看精神 / 看语言 / 看养老 / 看行情 / 看天气 …（全部 45 个面板）",
		"· 时间：等待 1 小时 / 睡 8 小时 / 工作 4 小时 / 学习 <技能> 2 小时 / 锻炼 1 小时",
		"· 生活：吃 <食物> / 买 <物品> 2 / 卖 <物品> / 存钱 500 元 / 取钱 200 元",
		"· 社交：聊天 <人物> / 送礼 <人物> / 约会 <人物> / 求职 <岗位>",
		"· 组织：加入组织 <组织> / 缴会费 / 组织任务 / 罢工 / 请愿 / 募捐 / 退出组织",
		"· 语言：学语言 <语言> [时长] / 沉浸 <语言> [天数] / 语言考试 <语言> / 适应文化 <文化>",
		"· 残障与养老：装辅具 <辅具> / 康复训练 / 无障碍改造 / 选养老 <模式> / 临终关怀 / 指定监护 <监护人>",
		"· 农业与乡土：承包土地 [面积] / 播种 <作物> / 收割 / 养畜 <牲畜> / 卖粮 <作物> / 农业补贴",
		"· 数字与平台：开账号 <平台> / 实名认证 / 网络兼职 <类型> / 发布内容 [平台] / 黑客攻击 <目标>",
		"· 后期科技：解锁科技 / 应聘科技职业 <职业> / 科技任务 <任务> / 生物延寿 [投入]",
		"· 知识产权与媒体：登记知识产权 <类型> / 知识产权授权 <IP> [规模] / 知识产权转让 <IP> [价格] / 知识产权质押 <IP> [金额] / 知识产权维权 <IP> / 开办媒体 <类型> / 发行作品 <标题>",
		"· 制造业与供应链：开办工厂 [模式] / 招工 <岗位> [人数] / 采购原料 <原料> [数量] / 生产 <配方> [批次] / 接单 <配方> [数量] / 交付订单 [序号] / 改进经营模式 <模式>",
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

# --- 组织与社团（D19） ---

func _join_org(intent) -> Dictionary:
	var oid := _object_id(intent, "organization")
	if oid.is_empty():
		return _fail("未指定要加入的组织；可打开「组织」面板了解可加入的工会、协会、NGO、俱乐部或阵营。")
	var r: Dictionary = host.join_organization(oid)
	if not bool(r.get("ok", false)):
		return _fail(_org_reason(String(r.get("reason", ""))))
	return _ok(["你加入了「%s」，缴纳首次会费 %.0f 元。" % [String(r.get("name", oid)), float(r.get("dues", 0))]], 0, "")

func _leave_org(intent) -> Dictionary:
	var oid := _object_id(intent, "organization")
	if oid.is_empty():
		var memberships: Array = host.organizations_panel_data().get("memberships", [])
		if memberships.size() == 1:
			oid = String((memberships[0] as Dictionary).get("id", ""))
		else:
			return _fail("请指定要退出哪个组织。")
	var r: Dictionary = host.leave_organization(oid, false)
	if not bool(r.get("ok", false)):
		return _fail(_org_reason(String(r.get("reason", ""))))
	var lines: Array = ["你退出了「%s」。" % String(r.get("name", oid))]
	var cost := int(r.get("exit_cost", 0))
	if cost > 0:
		lines.append("退出成本 %.0f 元。" % float(cost))
	if float(r.get("legal_risk", 0.0)) > 0.0:
		lines.append("叛逃留下法律隐患（风险 %.0f%%）。" % (float(r.get("legal_risk", 0.0)) * 100.0))
	return _ok(lines, 0, "")

func _pay_org_dues(intent) -> Dictionary:
	var oid := _object_id(intent, "organization")
	if oid.is_empty():
		var memberships: Array = host.organizations_panel_data().get("memberships", [])
		if memberships.size() == 1:
			oid = String((memberships[0] as Dictionary).get("id", ""))
		else:
			return _fail("请指定要缴纳会费的组织。")
	var r: Dictionary = host.pay_org_dues(oid)
	if not bool(r.get("ok", false)):
		return _fail(_org_reason(String(r.get("reason", ""))))
	return _ok(["你缴纳了 %.0f 元会费，尚欠 %.0f 元。" % [float(r.get("paid", 0)), float(r.get("dues_owed", 0))]], 0, "")

func _org_task(intent) -> Dictionary:
	var oid := _object_id(intent, "organization")
	if oid.is_empty():
		var memberships: Array = host.organizations_panel_data().get("memberships", [])
		if memberships.size() == 1:
			oid = String((memberships[0] as Dictionary).get("id", ""))
		else:
			return _fail("请指定要承接任务的组织。")
	var r: Dictionary = host.do_org_task(oid)
	if not bool(r.get("ok", false)):
		return _fail(_org_reason(String(r.get("reason", ""))))
	var lines: Array = []
	if bool(r.get("success", false)):
		lines.append("你完成了组织交办的事务，累计 %d 件。" % int(r.get("tasks_completed", 0)))
		if bool(r.get("promoted", false)):
			lines.append("你获得晋升，现任「%s」，开始领取津贴。" % String(r.get("rank_name", "")))
	else:
		lines.append("此次事务未能办妥，声望略有损失。")
	return _ok(lines, 0, "")

func _org_action(intent, action: String) -> Dictionary:
	var oid := _object_id(intent, "organization")
	if oid.is_empty():
		var memberships: Array = host.organizations_panel_data().get("memberships", [])
		if memberships.size() == 1:
			oid = String((memberships[0] as Dictionary).get("id", ""))
		else:
			return _fail("请指定要发起行动的组织。")
	var r: Dictionary = host.org_collective_action(oid, action)
	if not bool(r.get("ok", false)):
		return _fail(_org_reason(String(r.get("reason", ""))))
	var lines: Array = ["你组织了「%s」（成功率 %.0f%%）。" % [_org_action_cn(action), float(r.get("probability", 0.0)) * 100.0]]
	if bool(r.get("success", false)):
		lines.append("行动奏效，组织影响力上升。")
	else:
		lines.append("行动受挫，组织影响力受损。")
	if bool(r.get("exposed", false)):
		lines.append("组织因此暴露并瓦解，你留下案底（通缉等级 %d）。" % int(r.get("wanted_level", 0)))
	return _ok(lines, 0, "")

func _org_action_cn(action: String) -> String:
	return String(host.organizations.ACTIONS.get(action, {}).get("name", action))

func _org_reason(reason: String) -> String:
	match reason:
		"not_found":
			return "未找到该组织"
		"already_member":
			return "你已是该组织成员"
		"not_member":
			return "你并未加入该组织"
		"disbanded":
			return "该组织已经解散"
		"insufficient_funds":
			return "资金不足"
		"nothing_due":
			return "当前没有欠缴会费"
		"unknown_action":
			return "不支持该集体行动"
		_:
			return reason if reason != "" else "操作未能完成"

# --- 语言与文化（D20） ---

func _study_language(intent) -> Dictionary:
	var lang := _object_id(intent, "language")
	if lang.is_empty():
		return _fail("未指定语言；可学汉语、英语、西班牙语、日语或法语。")
	var minutes := _duration_minutes(intent, HOUR)
	var adv: Dictionary = _advance_time(minutes, {}, "study")
	var lines: Array = adv["narration"]
	var r: Dictionary = host.study_language(lang, "course", float(minutes) / 60.0)
	if not bool(r.get("ok", false)):
		return _fail("无法学习该语言。")
	lines.append("你修习「%s」%.0f 小时，综合等级升至 %.1f。" % [_language_name(lang), float(minutes) / 60.0, float(r.get("overall", 0.0))])
	return _ok(lines, minutes, "")

func _immerse_language(intent) -> Dictionary:
	var lang := _object_id(intent, "language")
	if lang.is_empty():
		return _fail("未指定语言；可在海外环境中沉浸学习。")
	var minutes := _duration_minutes(intent, DAY)
	var adv: Dictionary = _advance_time(minutes, {}, "study")
	var lines: Array = adv["narration"]
	var days: float = float(minutes) / float(DAY)
	var r: Dictionary = host.immerse_language(lang, days)
	if not bool(r.get("ok", false)):
		return _fail("无法沉浸学习该语言。")
	lines.append("你沉浸在「%s」的语言环境中 %.1f 天，综合等级升至 %.1f。" % [_language_name(lang), days, float(r.get("overall", 0.0))])
	return _ok(lines, minutes, "")

func _language_exam(intent) -> Dictionary:
	var lang := _object_id(intent, "language")
	if lang.is_empty():
		return _fail("未指定语言；可参加汉语、英语、西班牙语、日语或法语考试。")
	var target := 60.0
	var r: Dictionary = host.take_language_exam(lang, target)
	if not bool(r.get("ok", false)):
		return _fail("无法参加该语言考试。")
	if bool(r.get("passed", false)):
		return _ok(["你通过了「%s」等级 %.0f 考试（成绩 %.1f），获得证书。" % [_language_name(lang), target, float(r.get("score", 0.0))]], 0, "")
	return _fail("你的「%s」水平（%.1f）未达到等级 %.0f 的要求，未能通过考试。" % [_language_name(lang), float(r.get("score", 0.0)), target])

func _adapt_culture(intent) -> Dictionary:
	var culture := _object_id(intent, "culture")
	if culture.is_empty():
		return _fail("未指定文化；可适应中华、美国、日本、法国或阿拉伯文化。")
	var minutes := _duration_minutes(intent, 30 * DAY)
	var adv: Dictionary = _advance_time(minutes, {}, "rest")
	var lines: Array = adv["narration"]
	var days: float = float(minutes) / float(DAY)
	var r: Dictionary = host.adapt_culture(culture, days)
	if not bool(r.get("ok", false)):
		return _fail("无法适应该文化。")
	lines.append("你用了 %.0f 天适应当地文化，适应度升至 %.0f%%，文化冲击降至 %.0f%%。" % [
		days, float(r.get("adaptation", 0.0)) * 100.0, float(r.get("shock", 0.0)) * 100.0])
	return _ok(lines, minutes, "")


# --- 残障与养老（D21） ---

func _fit_device(intent) -> Dictionary:
	var device := _object_id(intent, "device")
	if device.is_empty():
		return _fail("未指定辅具；可装备轮椅、助听器、义肢、导盲犬等。")
	var dev: Dictionary = host.disability.DEVICES.get(device, {})
	var r: Dictionary = host.fit_disability_device(device)
	if not bool(r.get("ok", false)):
		return _fail("无法装配该辅具（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["你装配了「%s」，移动能力升至 %.0f%%。" % [String(dev.get("name", device)), float(r.get("mobility", 1.0)) * 100.0]], 0, "")

func _rehab(intent) -> Dictionary:
	var minutes := _duration_minutes(intent, 30 * DAY)
	var adv: Dictionary = _advance_time(minutes, {}, "rest")
	var lines: Array = adv["narration"]
	var r: Dictionary = host.disability_surgery(0.3)
	if not bool(r.get("ok", false)):
		return _fail("无法进行康复训练（%s）。" % _reason_cn(String(r.get("reason", ""))))
	lines.append("你坚持康复训练 %.0f 天，移动能力恢复至 %.0f%%。" % [float(minutes) / float(DAY), float(r.get("mobility", 1.0)) * 100.0])
	return _ok(lines, minutes, "")

func _accessible_retrofit(intent) -> Dictionary:
	var r: Dictionary = host.set_accessible_place(true)
	if not bool(r.get("ok", false)):
		return _fail("无法进行无障碍改造（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["你完成了无障碍改造，移动能力升至 %.0f%%。" % (float(r.get("mobility", 1.0)) * 100.0)], 0, "")

func _choose_care_mode(intent) -> Dictionary:
	var mode := _object_id(intent, "care_mode")
	if mode.is_empty():
		return _fail("未指定养老模式；可选居家护理、社区养老或机构养老。")
	var r: Dictionary = host.choose_care_mode(mode)
	if not bool(r.get("ok", false)):
		return _fail("无法选择该养老模式。")
	var def: Dictionary = r.get("def", {})
	return _ok(["你选择了「%s」养老，月成本约 %d，照护质量 %.0f%%。" % [
		String(def.get("name", mode)), int(def.get("cost_per_month", 0)), float(def.get("quality", 0.0)) * 100.0]], 0, "")

func _hospice(intent) -> Dictionary:
	var r: Dictionary = host.hospice_care(0.8)
	if not bool(r.get("ok", false)):
		return _fail("无法安排临终关怀。")
	return _ok(["你安排了临终关怀，舒适度与尊严得到保障（%.0f%%）。" % (float(r.get("comfort", 0.0)) * 100.0)], 0, "")

func _guardianship(intent) -> Dictionary:
	var guardian := _object_id(intent, "person")
	if guardian.is_empty():
		guardian = String(intent.params.get("method", "")).strip_edges()
	if guardian.is_empty():
		return _fail("未指定监护人。")
	var r: Dictionary = host.establish_guardianship(guardian)
	if not bool(r.get("ok", false)):
		return _fail("无法设立监护：当事人仍具备决策能力。")
	return _ok(["已为当事人设立监护人「%s」。" % guardian], 0, "")

func _language_name(lang: String) -> String:
	return String(host.language.language_def(lang).get("name", lang))


# --- 农业与乡土（D22） ---

func _acquire_land(intent) -> Dictionary:
	var area := float(intent.params.get("number", 0))
	if area <= 0.0:
		area = 5.0
	var r: Dictionary = host.acquire_farm_land(area, "grain", "contract", 100000, {})
	if not bool(r.get("ok", false)):
		return _fail("无法取得土地（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["你承包了 %.1f 亩农地，累计土地估值 %d。" % [area, int(r.get("asset_value", 0))]], 0, "")

func _sow(intent) -> Dictionary:
	var crop := _object_id(intent, "crop")
	if crop.is_empty():
		return _fail("未指定作物；可选水稻、小麦、棉花、油菜、蔬菜或药材。")
	var r: Dictionary = host.plant_crop(0, crop, {})
	if not bool(r.get("ok", false)):
		return _fail("无法播种（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["你在农地播下「%s」。" % _crop_name(crop)], 0, "")

func _harvest_crop(intent) -> Dictionary:
	var farm: Dictionary = host.farm_state()
	var plots: Array = farm.get("plots", [])
	var idx := -1
	for i in range(plots.size()):
		if String((plots[i] as Dictionary).get("stage", "")) == "mature":
			idx = i
			break
	if idx < 0:
		return _fail("没有成熟的作物可以收割。")
	var r: Dictionary = host.harvest_crop(idx, {"skill": 0.5})
	if not bool(r.get("ok", false)):
		return _fail("收割失败（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["你收割了「%s」，入仓 %.1f。" % [_crop_name(String(r.get("crop", ""))), float(r.get("yield", 0.0))]], 0, "")

func _raise_livestock(intent) -> Dictionary:
	var animal := _object_id(intent, "livestock")
	if animal.is_empty():
		return _fail("未指定牲畜；可选生猪、肉牛、肉鸡、鸭或鱼。")
	var count := int(intent.params.get("number", 0))
	if count <= 0:
		count = 5
	var r: Dictionary = host.add_farm_livestock(animal, count)
	if not bool(r.get("ok", false)):
		return _fail("无法增加存栏（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["你购入了 %d 头/只「%s」。" % [count, _livestock_name(animal)]], 0, "")

func _sell_produce(intent) -> Dictionary:
	var item := _object_id(intent, "crop")
	if item.is_empty():
		return _fail("未指定农产品；可用卖粮 <作物>。")
	var storage: Dictionary = host.farm_state().get("storage", {})
	var amount := float(storage.get(item, 0.0))
	if amount <= 0.0:
		return _fail("仓中并无该农产品。")
	var r: Dictionary = host.sell_produce(item, amount, "market", {})
	if not bool(r.get("ok", false)):
		return _fail("售卖失败（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["你售出「%s」%.1f，收入 %d。" % [_crop_name(item), amount, int(r.get("revenue", 0))]], 0, "")

func _farm_subsidy(intent) -> Dictionary:
	var r: Dictionary = host.apply_farm_subsidy(50000)
	if not bool(r.get("ok", false)):
		return _fail("申领补贴失败。")
	return _ok(["你申领到农业补贴 %d。" % int(r.get("granted", 0))], 0, "")

func _open_account(intent) -> Dictionary:
	var platform := _object_id(intent, "platform")
	if platform.is_empty():
		platform = String(intent.params.get("method", "")).strip_edges()
	if platform.is_empty():
		return _fail("未指定平台；可选直播或短视频。")
	var r: Dictionary = host.open_digital_account(platform)
	if not bool(r.get("ok", false)):
		return _fail("开通账号失败（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["你开通了「%s」账号。" % _platform_name(platform)], 0, "")

func _verify_identity(intent) -> Dictionary:
	var r: Dictionary = host.verify_digital_identity()
	return _ok(["数字身份已实名认证，隐私级别降至 %.0f%%。" % (float(r.get("privacy", 0.0)) * 100.0)], 0, "")

func _security_work(intent) -> Dictionary:
	var kind := _object_id(intent, "security_job")
	if kind.is_empty():
		return _fail("未指定工作类型；可选渗透测试、安全防护、应急响应或数据泄露处置。")
	var r: Dictionary = host.digital_security_work(kind)
	if not bool(r.get("ok", false)):
		return _fail("无法从事该网络安全工作（%s）。" % _reason_cn(String(r.get("reason", ""))))
	if not bool(r.get("success", false)):
		return _ok(["本次%s任务未通过，暂无收入。" % _security_job_name(kind)], 0, "")
	return _ok(["你完成了%s任务，收入 %d。" % [_security_job_name(kind), int(r.get("income", 0))]], 0, "")

func _publish_content(intent) -> Dictionary:
	var platform := _object_id(intent, "platform")
	if platform.is_empty():
		platform = "short_video"
	var r: Dictionary = host.publish_digital_content(platform)
	if not bool(r.get("ok", false)):
		return _fail("发布失败（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["你在「%s」发布内容，播放 %d，涨粉 %d，收入 %d。" % [_platform_name(platform), int(r.get("views", 0)), int(r.get("fans_delta", 0)), int(r.get("income", 0))]], 0, "")

func _hack_target(intent) -> Dictionary:
	var target := _object_id(intent, "hack_target")
	if target.is_empty():
		return _fail("未指定目标；可选个人、企业、政府或黑产。")
	var r: Dictionary = host.digital_hack(target)
	if not bool(r.get("ok", false)):
		return _fail("无法实施入侵（%s）。" % _reason_cn(String(r.get("reason", ""))))
	if bool(r.get("exposed", false)):
		return _ok(["你侵入了%s，获取 %d，但行动暴露并留下案底。" % [_hack_target_name(target), int(r.get("gain", 0))]], 0, "")
	if not bool(r.get("success", false)):
		return _ok(["你尝试侵入%s，但未能得手。" % _hack_target_name(target)], 0, "")
	return _ok(["你侵入了%s，获取 %d，未被察觉。" % [_hack_target_name(target), int(r.get("gain", 0))]], 0, "")

func _platform_name(platform: String) -> String:
	return String(host.digital.CONTENT_PLATFORMS.get(platform, {}).get("name", platform))

func _security_job_name(kind: String) -> String:
	return String(host.digital.SECURITY_JOBS.get(kind, {}).get("name", kind))

func _hack_target_name(target: String) -> String:
	return String(host.digital.HACK_TARGETS.get(target, {}).get("name", target))

func _crop_name(crop: String) -> String:
	return String(host.agriculture.crop_def(crop).get("name", crop))
func _livestock_name(animal: String) -> String:
	return String(host.agriculture.livestock_def(animal).get("name", animal))

# --- 后期科技（D24） ---

func _unlock_tech(intent) -> Dictionary:
	var r: Dictionary = host.unlock_late_tech_stage()
	if not bool(r.get("ok", false)):
		if String(r.get("reason", "")) == "max_stage":
			return _ok(["科技已抵达最高阶段：%s。" % host.late_tech_panel_data().get("stage_name", "")], 0, "")
		return _fail("无法推进科技（%s）。" % _reason_cn(String(r.get("reason", ""))))
	var data: Dictionary = host.late_tech_panel_data()
	return _ok(["科技迈入新阶段：%s。" % String(data.get("stage_name", ""))], 0, "")

func _apply_tech_career(intent) -> Dictionary:
	var career := _object_id(intent, "late_tech_career")
	if career.is_empty():
		return _fail("未指定科技职业；可先「看科技」查看可选职业。")
	var r: Dictionary = host.apply_late_tech_career(career)
	if not bool(r.get("ok", false)):
		return _fail("无法应聘该科技职业（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["你入职了%s，薪资 %d。" % [_tech_career_name(career), int(r.get("salary", 0))]], 0, "")

func _tech_mission(intent) -> Dictionary:
	var mission := _object_id(intent, "late_tech_mission")
	if mission.is_empty():
		return _fail("未指定任务；可先「看科技」查看高风险任务。")
	var r: Dictionary = host.risk_late_tech_mission(mission)
	if not bool(r.get("ok", false)):
		return _fail("无法执行该任务（%s）。" % _reason_cn(String(r.get("reason", ""))))
	if bool(r.get("casualty", false)):
		return _ok(["在执行%s时发生重大事故，任务失败。" % _tech_mission_name(mission)], 0, "")
	if bool(r.get("accident", false)):
		return _ok(["执行%s时遭遇事故，仍获得报酬 %d。" % [_tech_mission_name(mission), int(r.get("reward", 0))]], 0, "")
	return _ok(["完成%s，获得报酬 %d。" % [_tech_mission_name(mission), int(r.get("reward", 0))]], 0, "")

func _biotech(intent) -> Dictionary:
	var amount: float = 1000.0
	var p: Variant = intent.params.get("number", null) if intent.params is Dictionary else null
	if p != null:
		amount = float(p)
	var r: Dictionary = host.invest_biotech_lifespan(amount)
	if not bool(r.get("ok", false)):
		return _fail("无法进行生物延寿投资（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["你投入 %d 于生物科技，延寿 %+.1f 年（累计 %+.1f 年）。" % [int(amount), float(r.get("lifespan_gain", 0.0)), float(r.get("total_bonus", 0.0))]], 0, "")

func _tech_career_name(career: String) -> String:
	return String(host.late_tech.CAREERS.get(career, {}).get("name", career))

func _tech_mission_name(mission: String) -> String:
	return String(host.late_tech.MISSIONS.get(mission, {}).get("name", mission))

# --- 知识产权与媒体（D25） ---

func _register_ip(intent) -> Dictionary:
	var ip_type := _object_id(intent, "ip_type")
	if ip_type.is_empty():
		return _fail("未指定知识产权类型；可选版权、专利、商标或商业秘密。")
	var r: Dictionary = host.register_ip_asset(ip_type)
	if not bool(r.get("ok", false)):
		return _fail("无法登记知识产权（%s）。" % _reason_cn(String(r.get("reason", ""))))
	var ip: Dictionary = r.get("ip", {})
	return _ok(["你登记了%s「%s」，登记费 %d。" % [_ip_type_name(ip_type), String(ip.get("title", "")), int(r.get("fee", 0))]], 0, "")

func _license_ip(intent) -> Dictionary:
	var ip_id := _resolve_by_name("ip_asset", String(intent.params.get("method", "")))
	if ip_id.is_empty():
		return _fail("未指定知识产权；可先「看知识产权」查看已登记资产。")
	var deal: float = 1000000.0
	if intent.params.has("amount"):
		deal = float(intent.params.get("amount", 0))
	var r: Dictionary = host.license_ip_asset(ip_id, deal, false)
	if not bool(r.get("ok", false)):
		return _fail("无法授权（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["你对外授权，收取许可费 %d。" % int(r.get("fee", 0))], 0, "")

func _transfer_ip(intent) -> Dictionary:
	var ip_id := _resolve_by_name("ip_asset", String(intent.params.get("method", "")))
	if ip_id.is_empty():
		return _fail("未指定知识产权；可先「看知识产权」查看已登记资产。")
	var price: int = 500000
	if intent.params.has("amount"):
		price = int(intent.params.get("amount", 0))
	var r: Dictionary = host.transfer_ip_asset(ip_id, price)
	if not bool(r.get("ok", false)):
		return _fail("无法转让（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["你以 %d 转让了该知识产权。" % int(r.get("price", 0))], 0, "")

func _pledge_ip(intent) -> Dictionary:
	var ip_id := _resolve_by_name("ip_asset", String(intent.params.get("method", "")))
	if ip_id.is_empty():
		return _fail("未指定知识产权；可先「看知识产权」查看已登记资产。")
	var amount: int = 300000
	if intent.params.has("amount"):
		amount = int(intent.params.get("amount", 0))
	var r: Dictionary = host.pledge_ip_asset(ip_id, amount)
	if not bool(r.get("ok", false)):
		return _fail("无法质押（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["你以该知识产权质押融资 %d。" % int(r.get("amount", 0))], 0, "")

func _sue_ip(intent) -> Dictionary:
	var ip_id := _resolve_by_name("ip_asset", String(intent.params.get("method", "")))
	if ip_id.is_empty():
		return _fail("未指定知识产权；可先「看知识产权」查看已登记资产。")
	var r: Dictionary = host.sue_ip_infringer(ip_id)
	if not bool(r.get("ok", false)):
		return _fail("无法发起维权诉讼（%s）。" % _reason_cn(String(r.get("reason", ""))))
	if not bool(r.get("win", false)):
		return _ok(["维权诉讼败诉，未能获得赔偿。"], 0, "")
	return _ok(["维权诉讼胜诉，获赔 %d。" % int(r.get("compensation", 0))], 0, "")

func _open_media(intent) -> Dictionary:
	var media_type := _object_id(intent, "media_type")
	if media_type.is_empty():
		return _fail("未指定媒体类型；可选新闻社、出版社、影视公司、MCN 或平台。")
	var r: Dictionary = host.register_media_outlet(media_type)
	if not bool(r.get("ok", false)):
		return _fail("无法开办媒体（%s）。" % _reason_cn(String(r.get("reason", ""))))
	var outlet: Dictionary = r.get("outlet", {})
	return _ok(["你开办了%s「%s」。" % [_media_type_name(media_type), String(outlet.get("name", ""))]], 0, "")

func _release_work(intent) -> Dictionary:
	var outlets: Array = host.ip_media_state().get("outlets", [])
	if outlets.is_empty():
		return _fail("尚未开办媒体机构；先「开办媒体」再发行作品。")
	var outlet_id: String = String((outlets[0] as Dictionary).get("id", ""))
	var title: String = String(intent.params.get("method", "")).strip_edges()
	if title.is_empty():
		title = "未命名作品"
	var r: Dictionary = host.release_media_work(outlet_id, title)
	if not bool(r.get("ok", false)):
		return _fail("无法发行作品（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["发行《%s》，票房/销量结算 %d。" % [title, int(r.get("revenue", 0))]], 0, "")

func _ip_type_name(ip_type: String) -> String:
	return String(host.ip_media.IP_TYPES.get(ip_type, {}).get("name", ip_type))

func _media_type_name(media_type: String) -> String:
	return String(host.ip_media.MEDIA_TYPES.get(media_type, {}).get("name", media_type))

# --- 制造业与供应链（D26） ---

func _found_factory(intent) -> Dictionary:
	var mode := _object_id(intent, "mfg_mode")
	if mode.is_empty():
		mode = "own_factory"
	var r: Dictionary = host.found_factory(mode)
	if not bool(r.get("ok", false)):
		return _fail("无法开办工厂（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["你开办了工厂，经营模式：%s。" % _mfg_mode_name(String(r.get("mode", mode)))], 0, "")

func _mfg_hire(intent) -> Dictionary:
	var role := _object_id(intent, "mfg_role")
	var count: int = _param_number(intent, "number", 1)
	var r: Dictionary = host.mfg_hire(role, count)
	if not bool(r.get("ok", false)):
		return _fail("无法招工（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["你招入 %d 名%s。" % [int(r.get("hired", count)), _mfg_role_name(role)]], 0, "")

func _mfg_purchase(intent) -> Dictionary:
	var material := _object_id(intent, "mfg_material")
	var qty: float = float(_param_number(intent, "number", 100))
	var r: Dictionary = host.mfg_purchase(material, qty)
	if not bool(r.get("ok", false)):
		return _fail("无法采购原料（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["采购%s %.1f 单位，花费 %d。" % [material, float(r.get("delivered", 0.0)), int(r.get("cost", 0))]], 0, "")

func _mfg_produce(intent) -> Dictionary:
	var recipe := _object_id(intent, "mfg_recipe")
	var batches: float = float(_param_number(intent, "number", 1))
	var r: Dictionary = host.mfg_produce(recipe, batches)
	if not bool(r.get("ok", false)):
		return _fail("无法生产（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["生产%s，良品 %.1f（良品率 %.0f%%）。" % [_mfg_recipe_name(recipe), float(r.get("good_output", 0.0)), float(r.get("quality_yield", 0.0)) * 100.0]], 0, "")

func _mfg_order(intent) -> Dictionary:
	var recipe := _object_id(intent, "mfg_recipe")
	var qty: float = float(_param_number(intent, "number", 100))
	var r: Dictionary = host.mfg_accept_order(recipe, qty)
	if not bool(r.get("ok", false)):
		return _fail("无法接单（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["承接%s订单 %d 件。" % [_mfg_recipe_name(recipe), int(qty)]], 0, "")

func _mfg_deliver(intent) -> Dictionary:
	var index: int = _param_number(intent, "number", 0)
	var r: Dictionary = host.mfg_deliver_order(index)
	if not bool(r.get("ok", false)):
		return _fail("无法交付订单（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["交付 %.1f 件，结算收入 %d。" % [float(r.get("delivered", 0.0)), int(r.get("revenue", 0))]], 0, "")

func _mfg_mode(intent) -> Dictionary:
	var mode := _object_id(intent, "mfg_mode")
	var r: Dictionary = host.mfg_set_mode(mode)
	if not bool(r.get("ok", false)):
		return _fail("无法切换经营模式（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["经营模式改为%s。" % _mfg_mode_name(mode)], 0, "")

func _mfg_role_name(role: String) -> String:
	return String(host.manufacturing.ROLES.get(role, {}).get("name", role))

func _mfg_mode_name(mode: String) -> String:
	return String(host.manufacturing.MODES.get(mode, {}).get("name", mode))

func _mfg_recipe_name(recipe: String) -> String:
	return String(host.manufacturing.recipe_def(recipe).get("name", recipe))

func _param_number(intent, key: String, default: int) -> int:
	if intent.params is Dictionary and (intent.params as Dictionary).has(key):
		return int((intent.params as Dictionary).get(key, default))
	return default

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
		"not_applicable":
			return "该辅具不适用于现有残障类型"
		"has_capacity":
			return "当事人仍具备决策能力，无需监护"
		"unknown_device":
			return "未知辅具"
		"unknown_mode":
			return "未知养老模式"
		"unknown_crop":
			return "未知作物"
		"unknown_animal":
			return "未知牲畜"
		"unknown_use":
			return "未知土地用途"
		"unknown_channel":
			return "未知销售渠道"
		"no_land":
			return "尚未取得土地"
		"no_plot":
			return "指定地块不存在"
		"no_stock":
			return "库存不足"
		"no_order":
			return "订单不存在"
		"unknown_platform":
			return "未知平台"
		"unknown_job":
			return "未知网络安全工作"
		"unknown_target":
			return "未知目标"
		"banned":
			return "账号已被封禁"
		"unknown_career":
			return "未知科技职业"
		"unknown_mission":
			return "未知科技任务"
		"unknown_stage":
			return "未知科技阶段"
		"stage_locked":
			return "该内容尚未解锁"
		"skill_too_low":
			return "技能等级不足"
		"already_unlocked":
			return "该阶段已解锁"
		"locked":
			return "需先解锁前置阶段"
		"max_stage":
			return "已达最高科技阶段"
		"era_before_late_tech":
			return "时代尚未进入后期科技"
		"unknown_ip_type":
			return "未知知识产权类型"
		"unknown_ip":
			return "未找到该知识产权"
		"unknown_media_type":
			return "未知媒体类型"
		"unknown_outlet":
			return "未找到该媒体机构"
		"public_domain":
			return "该知识产权已进入公有领域"
		"perpetual_or_expired":
			return "该知识产权为无限期或已到期"
		"article_not_found":
			return "未找到该稿件"
		"unknown_mode":
			return "未知经营模式"
		"no_factory":
			return "尚未开办工厂"
		"unknown_recipe":
			return "未知生产配方"
		"no_supplier":
			return "该原料暂无供应商"
		"bad_quantity":
			return "数量不合法"
		"bad_batches":
			return "批次不合法"
		"disrupted":
			return "产线中断，无法生产"
		"already_fulfilled":
			return "该订单已交付完毕"
		"funding_chain_broken":
			return "资金链断裂"
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
		"organization":
			return _find_org_by_name(text)
		"language":
			return _find_language_by_name(text)
		"culture":
			return _find_culture_by_name(text)
		"device":
			return _find_device_by_name(text)
		"care_mode":
			return _find_care_mode_by_name(text)
		"crop":
			return _find_crop_by_name(text)
		"livestock":
			return _find_livestock_by_name(text)
		"platform":
			return _find_platform_by_name(text)
		"hack_target":
			return _find_hack_target_by_name(text)
		"security_job":
			return _find_security_job_by_name(text)
		"late_tech_career":
			return _find_late_tech_career_by_name(text)
		"late_tech_mission":
			return _find_late_tech_mission_by_name(text)
		"ip_asset":
			return _find_ip_asset_by_name(text)
		"mfg_role":
			return _find_catalog_by_name(host.mfg_roles_catalog(), text)
		"mfg_mode":
			return _find_catalog_by_name(host.mfg_modes_catalog(), text)
		"mfg_recipe":
			return _find_catalog_by_name(host.mfg_recipes_catalog(), text)
		"mfg_material":
			return _find_catalog_by_name(host.mfg_materials_catalog(), text)
		_:
			return ""

## 通用目录名回退：按 id 或显示名匹配条目列表（[{id,name}]）。
func _find_catalog_by_name(items: Array, text: String) -> String:
	var needle := text.strip_edges()
	if needle.is_empty():
		return ""
	for it in items:
		if it is Dictionary and String((it as Dictionary).get("id", "")) == needle:
			return String((it as Dictionary).get("id", ""))
	for it in items:
		if it is Dictionary and String((it as Dictionary).get("name", "")).find(needle) >= 0:
			return String((it as Dictionary).get("id", ""))
	return ""

## 辅具名回退：按辅具 id 或显示名匹配。
func _find_device_by_name(text: String) -> String:
	var needle := text.strip_edges()
	if needle.is_empty():
		return ""
	for key in host.disability.DEVICES.keys():
		if String(key) == needle:
			return String(key)
	for key in host.disability.DEVICES.keys():
		if String((host.disability.DEVICES[key] as Dictionary).get("name", "")).find(needle) >= 0:
			return String(key)
	return ""

## 养老模式名回退：按 id 或显示名匹配。
func _find_care_mode_by_name(text: String) -> String:
	var needle := text.strip_edges()
	if needle.is_empty():
		return ""
	for key in host.disability.CARE_MODES.keys():
		if String(key) == needle:
			return String(key)
	for key in host.disability.CARE_MODES.keys():
		if String((host.disability.CARE_MODES[key] as Dictionary).get("name", "")).find(needle) >= 0:
			return String(key)
	return ""

## 语言名回退：按语言 id 或显示名匹配。
func _find_language_by_name(text: String) -> String:
	var needle := text.strip_edges()
	if needle.is_empty():
		return ""
	for key in host.language.LANGUAGES.keys():
		if String(key) == needle:
			return String(key)
	for key in host.language.LANGUAGES.keys():
		if String((host.language.LANGUAGES[key] as Dictionary).get("name", "")).find(needle) >= 0:
			return String(key)
	return ""

## 文化名回退：按文化 id 或显示名匹配。
func _find_culture_by_name(text: String) -> String:
	var needle := text.strip_edges()
	if needle.is_empty():
		return ""
	for key in host.language.CULTURES.keys():
		if String(key) == needle:
			return String(key)
	for key in host.language.CULTURES.keys():
		if String((host.language.CULTURES[key] as Dictionary).get("name", "")).find(needle) >= 0:
			return String(key)
	return ""

## 作物名回退：按作物 id 或显示名匹配。
func _find_crop_by_name(text: String) -> String:
	var needle := text.strip_edges()
	if needle.is_empty():
		return ""
	for key in host.agriculture.CROPS.keys():
		if String(key) == needle:
			return String(key)
	for key in host.agriculture.CROPS.keys():
		if String((host.agriculture.CROPS[key] as Dictionary).get("name", "")).find(needle) >= 0:
			return String(key)
	return ""

## 牲畜名回退：按牲畜 id 或显示名匹配。
func _find_livestock_by_name(text: String) -> String:
	var needle := text.strip_edges()
	if needle.is_empty():
		return ""
	for key in host.agriculture.LIVESTOCK.keys():
		if String(key) == needle:
			return String(key)
	for key in host.agriculture.LIVESTOCK.keys():
		if String((host.agriculture.LIVESTOCK[key] as Dictionary).get("name", "")).find(needle) >= 0:
			return String(key)
	return ""

## 平台名回退：按平台 id 或显示名匹配。
func _find_platform_by_name(text: String) -> String:
	var needle := text.strip_edges()
	if needle.is_empty():
		return ""
	for key in host.digital.CONTENT_PLATFORMS.keys():
		if String(key) == needle:
			return String(key)
	for key in host.digital.CONTENT_PLATFORMS.keys():
		if String((host.digital.CONTENT_PLATFORMS[key] as Dictionary).get("name", "")).find(needle) >= 0:
			return String(key)
	return ""

## 黑客目标名回退：按目标 id 或显示名匹配。
func _find_hack_target_by_name(text: String) -> String:
	var needle := text.strip_edges()
	if needle.is_empty():
		return ""
	for key in host.digital.HACK_TARGETS.keys():
		if String(key) == needle:
			return String(key)
	for key in host.digital.HACK_TARGETS.keys():
		if String((host.digital.HACK_TARGETS[key] as Dictionary).get("name", "")).find(needle) >= 0:
			return String(key)
	return ""

## 网络安全职业名回退：按 id 或显示名匹配。
func _find_security_job_by_name(text: String) -> String:
	var needle := text.strip_edges()
	if needle.is_empty():
		return ""
	for key in host.digital.SECURITY_JOBS.keys():
		if String(key) == needle:
			return String(key)
	for key in host.digital.SECURITY_JOBS.keys():
		if String((host.digital.SECURITY_JOBS[key] as Dictionary).get("name", "")).find(needle) >= 0:
			return String(key)
	return ""

## 科技职业名回退：按 id 或显示名匹配。
func _find_late_tech_career_by_name(text: String) -> String:
	var needle := text.strip_edges()
	if needle.is_empty():
		return ""
	for key in host.late_tech.CAREERS.keys():
		if String(key) == needle:
			return String(key)
	for key in host.late_tech.CAREERS.keys():
		if String((host.late_tech.CAREERS[key] as Dictionary).get("name", "")).find(needle) >= 0:
			return String(key)
	return ""

## 科技任务名回退：按 id 或显示名匹配。
func _find_late_tech_mission_by_name(text: String) -> String:
	var needle := text.strip_edges()
	if needle.is_empty():
		return ""
	for key in host.late_tech.MISSIONS.keys():
		if String(key) == needle:
			return String(key)
	for key in host.late_tech.MISSIONS.keys():
		if String((host.late_tech.MISSIONS[key] as Dictionary).get("name", "")).find(needle) >= 0:
			return String(key)
	return ""

## 知识产权名回退：在已登记 IP 中按 id 或标题匹配。
func _find_ip_asset_by_name(text: String) -> String:
	var needle := text.strip_edges()
	if needle.is_empty():
		return ""
	var ips: Array = host.ip_media_state().get("ips", [])
	for ip in ips:
		if ip is Dictionary and String((ip as Dictionary).get("id", "")) == needle:
			return String((ip as Dictionary).get("id", ""))
	for ip in ips:
		if ip is Dictionary and String((ip as Dictionary).get("title", "")).find(needle) >= 0:
			return String((ip as Dictionary).get("id", ""))
	return ""

## 组织名回退：在可加入组织与已加入组织中按名称匹配。
func _find_org_by_name(text: String) -> String:
	var needle := text.strip_edges()
	if needle.is_empty():
		return ""
	var data: Dictionary = host.organizations_panel_data()
	for group in ["available", "memberships"]:
		for item in data.get(group, []):
			if not (item is Dictionary):
				continue
			var d: Dictionary = item
			if String(d.get("name", "")) == needle:
				return String(d.get("id", ""))
	for group in ["available", "memberships"]:
		for item in data.get(group, []):
			if not (item is Dictionary):
				continue
			var d: Dictionary = item
			if String(d.get("name", "")).find(needle) >= 0:
				return String(d.get("id", ""))
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
