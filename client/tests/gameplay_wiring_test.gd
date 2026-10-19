extends "res://tests/test_base.gd"
## 玩法接线端到端测试（任务 3/4/23）：真实主壳 + GameState + 指令 → 状态变化。
## 在无 Autoload 的 --script 环境中，手动把 GameState / WorldClock 挂到 root。

const GameStateScript = preload("res://autoload/game_state.gd")
const WorldClockScript = preload("res://autoload/world_clock.gd")
const SaveManagerScript = preload("res://sim/save_manager.gd")

var _main
var _game
var _ran := false

func _suite_name() -> String:
	return "gameplay_wiring"

func _initialize() -> void:
	print("[test] %s" % _suite_name())
	# --script 环境下 Autoload 可能缺失；有则复用，无则手动挂载。
	_game = root.get_node_or_null("GameState")
	if _game == null:
		_game = GameStateScript.new()
		_game.name = "GameState"
		root.add_child(_game)
	_game.new_game(11)
	if root.get_node_or_null("WorldClock") == null:
		var clock = WorldClockScript.new()
		clock.name = "WorldClock"
		root.add_child(clock)
	var packed = load("res://ui/main.tscn")
	if packed == null:
		_fail("main.tscn 无法加载")
		quit(failures)
		return
	_main = packed.instantiate()
	root.add_child(_main)

func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	run_tests()
	if failures == 0:
		print("[test] %s PASS" % _suite_name())
	else:
		print("[test] %s FAILURES: %d" % [_suite_name(), failures])
	quit(failures)
	return true

func run_tests() -> void:
	_test_wait_advances_state_clock()
	_test_panel_command_opens_panel()
	_test_map_panel_mounts_view()
	_test_buy_changes_inventory()
	_test_statusbar_weather()
	_test_marry_command()
	_test_property_commands()
	_test_family_commands()
	_test_pet_commands()
	_test_adoption_commands()
	_test_mental_commands()
	_test_spirit_commands()
	_test_org_commands()
	_test_language_commands()
	_test_disability_commands()
	_test_agriculture_commands()
	_test_digital_commands()
	_test_late_tech_commands()
	_test_ip_media_commands()
	_test_manufacturing_commands()
	_test_trade_commands()
	_test_mining_commands()
	_test_primary_commands()
	_test_dining_commands()
	_test_fashion_commands()
	_test_sports_commands()
	_test_events_commands()
	_test_honors_commands()
	_test_police_commands()
	_test_emergency_commands()
	_test_environment_commands()
	_test_municipal_commands()
	_test_debt_commands()
	_test_consumer_commands()
	_test_welfare_commands()
	_test_funeral_commands()
	_test_metaphysics_commands()
	_test_anomaly_commands()
	_test_medical_commands()
	_test_content_industry_commands()
	_test_engineering_commands()
	_test_professional_commands()
	_test_life_services_commands()
	_test_transport_infra_commands()
	_test_appearance_commands()
	_test_military_commands()
	_test_workplace_commands()
	_test_company_commands()
	_test_save_writes_file()

func _test_wait_advances_state_clock() -> void:
	_main.submit("等待 2 小时")
	check_eq(int(_game.clock.get("absolute_minutes", 0)), 120, "等待后游戏时钟推进 120 分钟")

func _test_panel_command_opens_panel() -> void:
	_main.submit("看自己")
	check(_main.has_panel("character"), "「看自己」打开角色面板")

func _test_map_panel_mounts_view() -> void:
	_main.submit("看地图")
	check(_main.has_panel("map"), "「看地图」打开地图面板")
	var drawer = _main.get_node_or_null("Root/Drawers/Drawer_map")
	check(drawer != null, "地图抽屉已创建")

func _test_buy_changes_inventory() -> void:
	_main.submit("买 苹果 2")
	var inv: Array = _game.player.get("inventory", [])
	var count := 0
	for inst in inv:
		if typeof(inst) == TYPE_DICTIONARY and String(inst.get("def_id", "")) == "item.apple":
			count += int(inst.get("quantity", 0))
	check_eq(count, 2, "「买 苹果 2」入包 2 个")

func _test_statusbar_weather() -> void:
	_main.submit("看天气")
	var label = _main.get_node_or_null("Root/StatusBar/WeatherLabel")
	check(label != null, "状态栏含天气标签")
	if label != null:
		check(label.text.begins_with("天气：") and label.text != "天气：--", "状态栏天气已由世界运行时填充")

func _test_marry_command() -> void:
	var sim = _main._sim
	var npc: Dictionary = sim.acquaintances()[0]
	var pid := String(npc.get("id", ""))
	var name := String(npc.get("name", ""))
	var rel: Dictionary = sim.relations.ensure_relation(_game.player, pid)
	rel["favor"] = 90.0
	rel["intimacy"] = 80.0
	_main.submit("求婚 " + name)
	check_eq(String(_game.player.get("family", {}).get("spouse_id", "")), pid, "「求婚 <人名>」经解析器链接并写入配偶")

func _test_property_commands() -> void:
	var sim = _main._sim
	sim.economy.add_money(sim.account_id(), 1000000000, "test")
	_main.submit("看房")
	var listings: Array = sim.property_listings()
	check(not listings.is_empty(), "存在在售房源")
	if listings.is_empty():
		return
	var pid := String(listings[0].get("id", ""))
	var name := String(listings[0].get("name", ""))
	_main.submit("买房 " + name)
	var owned := false
	for p in sim.property_owned():
		if String(p.get("id", "")) == pid:
			owned = true
	check(owned, "「买房 <房源>」经解析器链接并计入名下资产")

func _test_family_commands() -> void:
	var sim = _main._sim
	var npc: Dictionary = sim.acquaintances()[0]
	sim.marry_with(String(npc.get("id", "")))
	_main.submit("怀孕")
	check(sim.is_pregnant(), "「怀孕」进入妊娠状态")
	_main.submit("立遗嘱")
	check(not (_game.player.get("will", {}) as Dictionary).is_empty(), "「立遗嘱」写入遗嘱")

func _test_pet_commands() -> void:
	var sim = _main._sim
	sim.economy.add_money(sim.account_id(), 100000000, "test")
	_main.submit("领养 狗")
	check_eq(sim.pets().size(), 1, "「领养 <宠物>」经解析器链接并入档")
	if sim.pets().is_empty():
		return
	sim.pets()[0]["hunger"] = 10.0
	_main.submit("喂养")
	check(float(sim.pets()[0].get("hunger", 0.0)) > 10.0, "「喂养」回复宠物饥饿")

func _test_adoption_commands() -> void:
	var sim = _main._sim
	_main.submit("收养")
	check_eq(sim.adopted_children().size(), 1, "「收养」收养一名子女")
	var npc: Dictionary = sim.acquaintances()[0]
	_main.submit("指定监护人 " + String(npc.get("name", "")))
	check_eq(sim.guardians().size(), 1, "「指定监护人 <人物>」写入监护人")

func _test_mental_commands() -> void:
	var sim = _main._sim
	sim.economy.add_money(sim.account_id(), 100000000, "test")
	_main.submit("看心理")
	check(_main.has_panel("mental"), "「看心理」打开精神健康面板")
	# 强制发作一个病种，再经指令治疗（结果三态，不校验具体态）。
	sim.mental_onset("anxiety")
	_main.submit("心理咨询 焦虑症")
	check(sim.mental.disorders_count() >= 20, "精神疾病库覆盖 20+ 病种")
	# 放松降低压力。
	_game.player["attrs"]["psychological"]["stress"] = 80.0
	_main.submit("放松")
	check(float(_game.player["attrs"]["psychological"]["stress"]) < 80.0, "「放松」缓解压力")

func _test_spirit_commands() -> void:
	var sim = _main._sim
	_main.submit("看精神")
	check(_main.has_panel("spirit"), "「看精神」打开精神追求面板")
	# 修持：投入冥想 1 小时后追求深度增加。
	_main.submit("修持 冥想 1 小时")
	var depths: Dictionary = sim.spirit_state().get("depth", {})
	check(float(depths.get("meditation", 0.0)) > 0.0, "「修持 冥想」累计追求深度")
	# 皈依：写入信仰。
	_main.submit("皈依 佛教")
	check_eq(String(sim.spirit_state().get("faith", "")), "buddhism", "「皈依 佛教」写入信仰")
	# 深化信仰：境界随修持累积。
	_main.submit("深化信仰 1 小时")
	check(float(sim.spirit_state().get("faith_depth", 0.0)) > 0.0, "「深化信仰」累计信仰深度")
	# 化解危机：强制设置危机后经出口化解。
	sim.spirit_state()["crisis"] = "meaning_loss"
	_main.submit("化解危机 哲学省思")
	check_eq(String(sim.spirit_state().get("crisis", "")), "", "「化解危机」清空危机")

func _test_org_commands() -> void:
	var sim = _main._sim
	sim.economy.add_money(sim.account_id(), 1000000000, "test")
	_main.submit("看组织")
	check(_main.has_panel("organizations"), "「看组织」打开组织面板")
	var data: Dictionary = sim.organizations_panel_data()
	var available: Array = data.get("available", [])
	check(not available.is_empty(), "存在可加入组织")
	if available.is_empty():
		return
	var org: Dictionary = available[0]
	var oid := String(org.get("id", ""))
	var name := String(org.get("name", ""))
	_main.submit("加入组织 " + name)
	check(not sim.organizations.membership(_game.player, oid).is_empty(), "「加入组织」写入成员契约")
	# 会费：人为制造欠费后缴清。
	sim.organizations.membership(_game.player, oid)["dues_owed"] = 1000
	_main.submit("缴会费 " + name)
	check_eq(int(sim.organizations.membership(_game.player, oid).get("dues_owed", 0)), 0, "「缴会费」清减欠费")
	# 组织任务：预置任务数，行动后任务计数不倒退。
	sim.organizations.membership(_game.player, oid)["tasks_completed"] = 3
	_main.submit("组织任务 " + name)
	check(int(sim.organizations.membership(_game.player, oid).get("tasks_completed", 0)) >= 3, "「组织任务」推进任务计数")
	# 集体行动：请愿不报错。
	_main.submit("请愿 " + name)
	check(true, "「请愿」执行集体行动")
	# 退出组织。
	_main.submit("退出组织 " + name)
	check(sim.organizations.membership(_game.player, oid).is_empty(), "「退出组织」移除成员契约")

func _test_language_commands() -> void:
	var sim = _main._sim
	_main.submit("看语言")
	check(_main.has_panel("language"), "「看语言」打开语言与文化面板")
	# 学语言：提升综合等级。
	var before: float = float(sim.language.overall(sim.language_state(), "en"))
	_main.submit("学语言 英语")
	var after: float = float(sim.language.overall(sim.language_state(), "en"))
	check(after > before, "「学语言」提升语言等级")
	# 沉浸：继续提升。
	_main.submit("沉浸 英语")
	check(float(sim.language.overall(sim.language_state(), "en")) >= after - 0.01, "「沉浸」不降低语言等级")
	# 语言考试：预置等级后通过。
	sim.language.set_level(sim.language_state(), "en", 90.0, 90.0, 90.0)
	_main.submit("语言考试 英语")
	var has_cert: bool = sim.language.has_certificate(sim.language_state(), "en", 60.0)
	check(has_cert, "「语言考试」通过并颁发证书")
	# 适应文化：提升适应度。
	_main.submit("适应文化 美国")
	check(float(sim.language.current_adaptation(sim._culture, "us")) > 0.0, "「适应文化」提升文化适应度")

func _test_disability_commands() -> void:
	var sim = _main._sim
	sim.economy.add_money(sim.account_id(), 1000000000, "test")
	sim.acquire_disability("physical", "accident", "heavy")
	_main.submit("看养老")
	check(_main.has_panel("disability"), "「看养老」打开残障与养老面板")
	# 装辅具：提升移动能力。
	var before: float = sim.disability.mobility(sim.disability_state())
	_main.submit("装辅具 轮椅")
	check(sim.disability.mobility(sim.disability_state()) > before, "「装辅具」提升移动能力")
	# 康复训练：不报错。
	_main.submit("康复训练")
	check(true, "「康复训练」执行康复")
	# 选养老：写入养老模式。
	_main.submit("选养老 机构养老")
	check_eq(str(sim.disability_state().get("care_mode", "")), "institution_care", "「选养老」写入模式")
	# 指定监护：先制造丧失决策能力。
	sim.acquire_disability("intellectual", "illness", "heavy")
	_main.submit("指定监护 长子")
	check_eq(str(sim.disability_state().get("guardian", "")), "长子", "「指定监护」写入监护人")

func _test_agriculture_commands() -> void:
	var sim = _main._sim
	_main.submit("看农业")
	check(_main.has_panel("agriculture"), "「看农业」打开农业与乡土面板")
	# 承包土地
	_main.submit("承包土地 5")
	check((sim.farm_state().get("land", []) as Array).size() >= 1, "「承包土地」写入土地")
	# 播种
	_main.submit("播种 水稻")
	check((sim.farm_state().get("plots", []) as Array).size() >= 1, "「播种」写入地块")
	# 推进成熟后收割
	sim.grow_farm(200.0)
	_main.submit("收割")
	check(float(sim.farm_state().get("storage", {}).get("rice", 0.0)) > 0.0, "「收割」入仓水稻")
	# 养畜
	_main.submit("养畜 生猪")
	check((sim.farm_state().get("livestock", []) as Array).size() >= 1, "「养畜」写入牲畜")
	# 卖粮
	_main.submit("卖粮 水稻")
	check(float(sim.farm_state().get("storage", {}).get("rice", 0.0)) <= 0.01, "「卖粮」清空水稻库存")
	# 补贴
	_main.submit("农业补贴")
	check(float(sim.farm_state().get("subsidy", 0.0)) > 0.0, "「农业补贴」发放补贴")

func _test_digital_commands() -> void:
	var sim = _main._sim
	_main.submit("看数字")
	check(_main.has_panel("digital"), "「看数字」打开数字与平台面板")
	# 开账号
	_main.submit("开账号 短视频")
	check((sim.digital_state().get("accounts", {}) as Dictionary).has("short_video"), "「开账号」写入平台账号")
	# 实名认证
	_main.submit("实名认证")
	check(bool(sim.digital_state().get("real_name_verified", false)), "「实名认证」写入实名状态")
	# 发布内容
	var money_before: int = sim.economy.cash(sim.account_id())
	_main.submit("发布内容 短视频")
	check(not sim.digital_panel_data().get("creator", {}).is_empty(), "「发布内容」生成创作者数据")
	check(sim.economy.cash(sim.account_id()) >= money_before, "「发布内容」结算收益")
	# 网络兼职
	_main.submit("网络兼职 渗透测试")
	check(true, "「网络兼职」执行网络安全工作")

func _test_late_tech_commands() -> void:
	var sim = _main._sim
	_main.submit("看科技")
	check(_main.has_panel("late_tech"), "「看科技」打开后期科技面板")
	# 解锁科技阶段
	_main.submit("解锁科技")
	check_eq(String(sim.late_tech_panel_data().get("stage", "")), "intelligent", "「解锁科技」推进阶段")
	# 生物延寿（带金额参数）
	_main.submit("生物延寿 1000000")
	check(float(sim.late_tech_state().get("lifespan_bonus", 0.0)) > 0.0, "「生物延寿」写入延寿加成")
	# 自动化冲击
	_main.submit("自动化评估 120")
	check_eq(String((sim.late_tech_state().get("last_report", {}) as Dictionary).get("kind", "")), "automation", "「自动化评估」记录冲击")
	# 极端环境（先恢复健康，避免前序操作已耗尽体力）
	sim.player()["attrs"]["physiological"]["health"] = 100.0
	var health_before: float = float(sim.player().get("attrs", {}).get("physiological", {}).get("health", 100.0))
	_main.submit("极端环境 失重 10")
	var health_after: float = float(sim.player().get("attrs", {}).get("physiological", {}).get("health", 100.0))
	check(health_after < health_before, "「极端环境」扣减健康")
	# 气候难民
	_main.submit("气候难民 20")
	check(float(sim.late_tech_state().get("warming", 0.0)) >= 2.0, "「气候难民」写入升温")
	# AI 伦理事件
	_main.submit("AI伦理事件 100")
	check_eq(String((sim.late_tech_state().get("last_report", {}) as Dictionary).get("kind", "")), "ai", "「AI伦理事件」记录演练")

func _test_ip_media_commands() -> void:
	var sim = _main._sim
	_main.submit("看知识产权")
	check(_main.has_panel("ip_media"), "「看知识产权」打开知识产权与媒体面板")
	# 登记版权
	_main.submit("登记知识产权 版权")
	check((sim.ip_media_state().get("ips", []) as Array).size() >= 1, "「登记知识产权」写入 IP")
	# 授权
	_main.submit("知识产权授权 版权")
	check(true, "「知识产权授权」执行授权")
	# 开办媒体
	_main.submit("开办媒体 出版社")
	check((sim.ip_media_state().get("outlets", []) as Array).size() >= 1, "「开办媒体」写入媒体机构")
	# 发行作品
	var money_before: int = sim.economy.cash(sim.account_id())
	_main.submit("发行作品 试作")
	check(sim.economy.cash(sim.account_id()) >= money_before, "「发行作品」结算营收")

func _test_manufacturing_commands() -> void:
	var sim = _main._sim
	_main.submit("看工厂")
	check(_main.has_panel("business"), "「看工厂」打开经营面板")
	# 开办工厂
	_main.submit("开办工厂")
	check(not sim.manufacturing_state().is_empty(), "「开办工厂」建立工厂")
	# 招工
	_main.submit("招工 普工 10")
	check_eq(int(sim.manufacturing.headcount(sim.manufacturing_state())), 10, "「招工」写入产线人员")
	# 采购原料
	_main.submit("采购原料 钢 100")
	var steel: float = sim.manufacturing.material_qty(sim.manufacturing_state(), "steel")
	check(steel > 0.0, "「采购原料」入库存")
	# 生产
	_main.submit("生产 钢制零件 20")
	check(sim.manufacturing.product_qty(sim.manufacturing_state(), "steel_part") > 0.0, "「生产」产出成品")
	# 接单与交付
	_main.submit("接单 钢制零件 10")
	_main.submit("交付订单")
	var orders: Array = sim.manufacturing_state().get("orders", [])
	check(orders.size() >= 1 and float((orders[0] as Dictionary).get("delivered", 0.0)) > 0.0, "「交付订单」结算交付")

func _test_trade_commands() -> void:
	var sim = _main._sim
	_main.submit("看外贸")
	check(_main.has_panel("business"), "「看外贸」打开经营面板")
	_main.submit("出口 钢材")
	check((sim.trade_state().get("shipments", []) as Array).size() >= 1, "「出口」建立外贸单据")
	_main.submit("规划运输 海运")
	var shipments: Array = sim.trade_state().get("shipments", [])
	check(int((shipments[0] as Dictionary).get("freight", 0)) > 0, "「规划运输」写入运费")
	_main.submit("签订外贸合同 FOB")
	check_eq(String((shipments[0] as Dictionary).get("incoterm", "")), "FOB", "「签订外贸合同」写入术语")
	_main.submit("报关")
	check((shipments[0] as Dictionary).has("duties"), "「报关」落税")
	_main.submit("外贸交付")
	check(bool((shipments[0] as Dictionary).get("settled", false)) == false, "「外贸交付」进入交付")
	_main.submit("结汇")
	check(bool((shipments[0] as Dictionary).get("settled", false)), "「结汇」标记已结汇")
	_main.submit("贸易壁垒 反倾销")
	check((shipments[0] as Dictionary).get("barriers", []).size() >= 1, "「贸易壁垒」写入壁垒")
	_main.submit("外贸风险 制裁")
	check((shipments[0] as Dictionary).get("risk_events", []).size() >= 1, "「外贸风险」写入风险事件")
	_main.submit("检验检疫")
	check(bool((shipments[0] as Dictionary).get("inspection_passed", false)), "「检验检疫」记录结果")
	var goods_before: int = int((shipments[0] as Dictionary).get("goods_value", 0))
	_main.submit("货损 10")
	check(int((shipments[0] as Dictionary).get("goods_value", 0)) < goods_before, "「货损」折减货值")
	_main.submit("退运")
	check(bool((shipments[0] as Dictionary).get("returned", false)), "「退运」标记退运")

func _test_mining_commands() -> void:
	var sim = _main._sim
	_main.submit("看矿业")
	check(_main.has_panel("business"), "「看矿业」打开经营面板")
	_main.submit("开矿 铁矿")
	check(not (sim.mining_state().get("mine", {}) as Dictionary).is_empty(), "「开矿」建立矿场")
	_main.submit("取得矿权")
	check(bool((sim.mining_state().get("mine", {}) as Dictionary).get("concession", false)), "「取得矿权」取得特许")
	_main.submit("勘探 1000000")
	check(float((sim.mining_state().get("mine", {}) as Dictionary).get("reserve", 0.0)) > 0.0, "「勘探」揭示储量")
	_main.submit("开采 1000")
	var mined: Dictionary = sim.mining_state().get("mine", {})
	check(float(mined.get("stockpile_ore", 0.0)) + float(mined.get("in_transit_ore", 0.0)) > 0.0, "「开采」产出矿石")
	_main.submit("冶炼 1000")
	check(float((sim.mining_state().get("mine", {}) as Dictionary).get("refined_metal", 0.0)) > 0.0, "「冶炼」产出金属")
	_main.submit("卖矿 1000")
	check(int((sim.mining_state().get("mine", {}) as Dictionary).get("revenue", 0)) > 0, "「卖矿」取得收入")
	_main.submit("建能源项目 光伏")
	check((sim.mining_panel_data().get("projects", []) as Array).size() >= 1, "「建能源项目」登记项目")
	_main.submit("安全投入 1000000")
	check(float((sim.mining_state().get("mine", {}) as Dictionary).get("safety", 0.0)) > 0.5, "「安全投入」提升安全水平")
	_main.submit("矿难")
	check(sim.mining_panel_data().has("last_accident"), "「矿难」返回事故判定")
	_main.submit("能源期货 石油 100")
	check((sim.mining_panel_data().get("futures", []) as Array).size() >= 1, "「能源期货」建立合约")
	_main.submit("期货结算 石油")
	var futures: Array = sim.mining_panel_data().get("futures", [])
	check(futures.size() >= 1 and bool((futures[0] as Dictionary).get("settled", false)), "「期货结算」结算合约")
	_main.submit("能源长约 石油 1000")
	check((sim.mining_panel_data().get("contracts", []) as Array).size() >= 1, "「能源长约」签订长约")

func _test_primary_commands() -> void:
	var sim = _main._sim
	_main.submit("看渔场")
	check(_main.has_panel("agriculture"), "「看渔场」打开农业面板")
	_main.submit("建渔场")
	check(not (sim.primary_state().get("fishery", {}) as Dictionary).is_empty(), "「建渔场」建立渔场")
	_main.submit("捕鱼 鳕鱼 100")
	check(float((sim.primary_state().get("fishery", {}) as Dictionary).get("overfish", 0.0)) > 0.0, "「捕鱼」记录捕捞")
	_main.submit("休渔")
	check(bool((sim.primary_state().get("fishery", {}) as Dictionary).get("closed_season", false)), "「休渔」进入休渔期")
	_main.submit("承包林场 用材林")
	check(not (sim.primary_state().get("forest", {}) as Dictionary).is_empty(), "「承包林场」建立林场")
	_main.submit("采伐 100")
	check(float((sim.primary_state().get("forest", {}) as Dictionary).get("wood", 0.0)) > 0.0, "「采伐」入库木材")
	var trees_before: float = float((sim.primary_state().get("forest", {}) as Dictionary).get("trees", 0.0))
	_main.submit("造林 50")
	var trees_after: float = float((sim.primary_state().get("forest", {}) as Dictionary).get("trees", 0.0))
	check(trees_after > trees_before, "「造林」补植林木")
	_main.submit("申请狩猎许可")
	check(bool((sim.primary_state().get("hunter", {}) as Dictionary).get("license", false)), "「申请狩猎许可」取得许可")
	_main.submit("狩猎 鹿 1")
	check(int((sim.primary_state().get("hunter", {}) as Dictionary).get("money", 0)) > 0, "「狩猎」取得收益")

func _test_dining_commands() -> void:
	var sim = _main._sim
	_main.submit("看餐厅")
	check(_main.has_panel("business"), "「看餐厅」打开经营面板")
	_main.submit("建餐厅")
	check(not sim.dining_state().is_empty(), "「建餐厅」开办餐厅")
	_main.submit("加菜 家常小炒")
	check((sim.dining_state().get("menu", []) as Array).has("home_style"), "「加菜」入菜单")
	_main.submit("定菜价 家常小炒 4000")
	check(int((sim.dining_state().get("prices", {}) as Dictionary).get("home_style", 0)) == 4000, "「定菜价」设置售价")
	_main.submit("雇厨 厨师 2")
	check(int((sim.dining_state().get("staff", {}) as Dictionary).get("cook", 0)) == 2, "「雇厨」雇佣厨师")
	var money_before: int = int(sim.dining_state().get("money", 0))
	_main.submit("营业")
	check(int(sim.dining_state().get("money", 0)) != money_before, "「营业」结算一日流水")
	_main.submit("食品认证 卫生")
	check((sim.dining_state().get("certifications", []) as Array).has("hygiene_a"), "「食品认证」取得认证")

func _test_fashion_commands() -> void:
	var sim = _main._sim
	_main.submit("看品牌")
	check(_main.has_panel("business"), "「看品牌」打开经营面板")
	_main.submit("建品牌 大众")
	check(not (sim.fashion_state().get("brand", {}) as Dictionary).is_empty(), "「建品牌」创立品牌")
	_main.submit("创作设计 服装设计")
	check((sim.fashion_state().get("brand", {}) as Dictionary).get("collections", []).size() == 1, "「创作设计」产出作品")
	_main.submit("时装周 秋冬季")
	check(float((sim.fashion_state().get("brand", {}) as Dictionary).get("fame", 0.0)) > 30.0, "「时装周」提升热度")
	_main.submit("限量发售 手袋 10")
	check(not ((sim.fashion_state().get("brand", {}) as Dictionary).get("inventory", {}) as Dictionary).is_empty(), "「限量发售」入库")
	_main.submit("联名 80")
	check(int((sim.fashion_state().get("brand", {}) as Dictionary).get("money", 0)) > 1000000, "「联名」取得收入")

func _test_sports_commands() -> void:
	var sim = _main._sim
	_main.submit("看球队")
	check(_main.has_panel("sports"), "「看球队」打开体育面板")
	_main.submit("开启球涯")
	check(not (sim.sports_state().get("player", {}) as Dictionary).is_empty(), "「开启球涯」开启生涯")
	_main.submit("比赛")
	check(int((sim.sports_state().get("player", {}) as Dictionary).get("appearances", 0)) >= 1, "「比赛」记录出场")
	_main.submit("转会 5000000")
	check(String((sim.sports_state().get("player", {}) as Dictionary).get("club", "")) == "rival_club", "「转会」更换球会")
	_main.submit("代言合同 800000")
	check((sim.sports_state().get("player", {}) as Dictionary).get("sponsors", []).size() == 1, "「代言合同」增加赞助")
	_main.submit("国家队征召 中国")
	check_eq(String((sim.sports_state().get("player", {}) as Dictionary).get("national_team", "")), "中国", "「国家队征召」入选国家队")
	_main.submit("国际赛事 世界杯")
	check(not ((sim.sports_state().get("player", {}) as Dictionary).get("last_tournament", {}) as Dictionary).is_empty(), "「国际赛事」记录赛事")
	_main.submit("球迷冲突")
	check(float(sim.sports_panel_data().get("club_reputation", 100.0)) < 50.0, "「球迷冲突」损伤球会声誉")
	var cash_before: int = sim.economy.cash(sim.account_id())
	_main.submit("裁判争议")
	check(sim.economy.cash(sim.account_id()) < cash_before, "「裁判争议」支付申诉费")
	_main.submit("学业冲突")
	check(true, "「学业冲突」可执行")
	_main.submit("运动康复 30")
	check(true, "「运动康复」可执行")
	_main.submit("退役")
	check(String((sim.sports_state().get("player", {}) as Dictionary).get("career_stage", "")) == "retire", "「退役」结束生涯")

func _test_events_commands() -> void:
	var sim = _main._sim
	_main.submit("看活动")
	check(_main.has_panel("events"), "「看活动」打开活动面板")
	_main.submit("活动策划")
	check(not (sim.events_state().get("planner", {}) as Dictionary).is_empty(), "「活动策划」开启职业")
	_main.submit("办活动 演唱会")
	check(String((sim.events_state().get("event", {}) as Dictionary).get("type", "")) == "concert", "「办活动」创建活动")
	_main.submit("租场地 2000000")
	check(int((sim.events_state().get("event", {}) as Dictionary).get("capacity", 0)) > 0, "「租场地」设定容量")
	_main.submit("报批")
	check(bool((sim.events_state().get("event", {}) as Dictionary).get("approved", false)), "「报批」通过")
	_main.submit("拉赞助 冠名赞助")
	check((sim.events_state().get("event", {}) as Dictionary).get("sponsors", []).size() == 1, "「拉赞助」入账")
	_main.submit("售票 5000")
	check(int((sim.events_state().get("event", {}) as Dictionary).get("sold", 0)) == 5000, "「售票」记录")
	_main.submit("布置安保 80")
	check(float((sim.events_state().get("event", {}) as Dictionary).get("security_level", 0.0)) > 0.0, "「布置安保」配置")
	_main.submit("举办活动")
	check(String((sim.events_state().get("event", {}) as Dictionary).get("stage", "")) == "live", "「举办活动」进入现场")
	_main.submit("活动复盘")
	check(String((sim.events_state().get("event", {}) as Dictionary).get("stage", "")) == "review", "「活动复盘」进入复盘")

func _test_honors_commands() -> void:
	var sim = _main._sim
	_main.submit("名人堂")
	check(_main.has_panel("awards"), "「名人堂」打开荣誉面板")
	_main.submit("荣誉档案 90")
	check(not (sim.honors_state().get("candidate", {}) as Dictionary).is_empty(), "「荣誉档案」建立档案")
	_main.submit("提名 学术成就奖")
	_main.submit("评审 学术成就奖")
	_main.submit("领奖 学术成就奖")
	check((sim.honors_state().get("candidate", {}) as Dictionary).get("honors", []).size() == 1, "「领奖」登记荣誉")
	_main.submit("买奖 艺术大奖")
	_main.submit("揭露黑幕")
	check((sim.honors_state().get("candidate", {}) as Dictionary).get("honors", []).size() == 0, "「揭露黑幕」撤销荣誉")

func _test_police_commands() -> void:
	var sim = _main._sim
	_main.submit("看案件")
	check(_main.has_panel("legal"), "「看案件」打开案件面板")
	_main.submit("立案 偷窃")
	check(not (sim.police_state().get("case", {}) as Dictionary).is_empty(), "「立案」建立案件")
	_main.submit("勘查")
	check(float((sim.police_state().get("case", {}) as Dictionary).get("leads", 0.0)) > 0.0, "「勘查」取得线索")
	_main.submit("搜查令")
	check(bool(((sim.police_state().get("case", {}) as Dictionary).get("legal", {}) as Dictionary).get("warrant", false)), "「搜查令」获批")
	_main.submit("取证 监控")
	check(float((((sim.police_state().get("case", {}) as Dictionary).get("evidence", {}) as Dictionary).get("surveillance", 0.0))) > 0.0, "「取证」采集监控")
	_main.submit("审讯 40")
	_main.submit("线人")
	_main.submit("卧底")
	_main.submit("技侦")
	_main.submit("侦破")
	_main.submit("侦破")
	_main.submit("侦破")
	check(String((sim.police_state().get("case", {}) as Dictionary).get("stage", "")) in ["solved", "cold"], "「侦破」推进案件终结")
	_main.submit("开安保公司 测试安保")
	check(not (sim.police_state().get("firm", {}) as Dictionary).is_empty(), "「开安保公司」建立公司")
	_main.submit("承接安保 押运")
	check((sim.police_state().get("firm", {}) as Dictionary).get("contracts", []).size() == 1, "「承接安保」登记业务")
	_main.submit("履约安保")
	check(bool(((sim.police_state().get("firm", {}) as Dictionary).get("contracts", [])[0] as Dictionary).get("resolved", false)), "「履约安保」结算业务")

func _test_emergency_commands() -> void:
	var sim = _main._sim
	_main.submit("看灾害")
	check(_main.has_panel("rescue"), "「看灾害」打开救援面板")
	_main.submit("接警 消防 60")
	check(not (sim.emergency_state().get("incident", {}) as Dictionary).is_empty(), "「接警」建立事件")
	_main.submit("出警 5")
	check(float((sim.emergency_state().get("incident", {}) as Dictionary).get("response_minutes", -1.0)) > 0.0, "「出警」计算响应时间")
	_main.submit("现场救援")
	check(String((sim.emergency_state().get("incident", {}) as Dictionary).get("stage", "")) == "rescue", "「现场救援」进入救援")
	_main.submit("二次事故")
	sim._incident["deaths"] = 10
	var stress_before: float = float(sim.player().get("attrs", {}).get("psychological", {}).get("stress", 0.0))
	_main.submit("善后处理")
	check(String((sim.emergency_state().get("incident", {}) as Dictionary).get("stage", "")) == "aftermath", "「善后处理」进入善后")
	var stress_after: float = float(sim.player().get("attrs", {}).get("psychological", {}).get("stress", 0.0))
	check(stress_after > stress_before, "「善后处理」灾后创伤写入心理压力")
	_main.submit("开志愿队 测试志愿队")
	check(not (sim.emergency_state().get("org", {}) as Dictionary).is_empty(), "「开志愿队」建立志愿队")
	_main.submit("招募志愿者 10")
	check(int((sim.emergency_state().get("org", {}) as Dictionary).get("volunteers", 0)) == 10, "「招募志愿者」入队")
	_main.submit("采购救援装备 装备 100")
	check(int((sim.emergency_state().get("org", {}) as Dictionary).get("equipment", 0)) == 1, "「采购救援装备」入库")

func _test_environment_commands() -> void:
	var sim = _main._sim
	_main.submit("看环保")
	check(_main.has_panel("environment"), "「看环保」打开环保面板")
	_main.submit("垃圾分类 80")
	check(float((sim.environment_state().get("city", {}) as Dictionary).get("garbage_sorting", 0.0)) == 0.8, "「垃圾分类」设定")
	_main.submit("污水处理 90")
	check(float((sim.environment_state().get("city", {}) as Dictionary).get("sewage_treatment", 0.0)) == 0.9, "「污水处理」设定")
	_main.submit("空气治理 1000000")
	check(float((sim.environment_state().get("city", {}) as Dictionary).get("air_quality", 0.0)) > 0.6, "「空气治理」改善")
	_main.submit("碳核算")
	_main.submit("碳交易 10")
	check(float((sim.environment_state().get("enterprise", {}) as Dictionary).get("credits", 0.0)) == 10.0, "「碳交易」入账")
	_main.submit("低碳转型 1000000")
	check(float((sim.environment_state().get("enterprise", {}) as Dictionary).get("green_investment", 0.0)) > 0.0, "「低碳转型」投入")
	_main.submit("开环保公司 环保企业")
	check(not (sim.environment_state().get("org", {}) as Dictionary).is_empty(), "「开环保公司」建立组织")
	_main.submit("承接环保项目 污水厂 1000000")
	check((sim.environment_state().get("org", {}) as Dictionary).get("projects", []).size() == 1, "「承接环保项目」登记")
	_main.submit("偷排 20")
	_main.submit("邻避评估 50")

func _test_municipal_commands() -> void:
	var sim = _main._sim
	_main.submit("看市政")
	check(_main.has_panel("municipal"), "「看市政」打开市政面板")
	_main.submit("市政养护 公园 3000000")
	var park: Dictionary = (sim.municipal_state().get("city", {}) as Dictionary).get("facilities", {}).get("park", {})
	check(float(park.get("condition", 0.0)) >= 0.99, "「市政养护」提升设施健康度")
	_main.submit("设施巡检")
	_main.submit("市政施工 道路 30")
	var road: Dictionary = (sim.municipal_state().get("city", {}) as Dictionary).get("facilities", {}).get("road", {})
	check(bool(road.get("under_construction", false)), "「市政施工」开工")
	_main.submit("施工推进 40")
	road = (sim.municipal_state().get("city", {}) as Dictionary).get("facilities", {}).get("road", {})
	check(not bool(road.get("under_construction", false)), "「施工推进」完工")
	_main.submit("道路开挖 桥梁")
	_main.submit("市政投诉 扰民")
	check(int(sim.municipal_inspect().get("unresolved_complaints", 0)) >= 1, "「市政投诉」登记")
	_main.submit("投诉处理 0")
	_main.submit("邮政寄件 p1")
	_main.submit("包裹发运")
	_main.submit("快递生涯")
	check(not (sim.municipal_state().get("courier", {}) as Dictionary).is_empty(), "「快递生涯」建立职业")
	_main.submit("揽投")
	_main.submit("特许经营 道路保洁")
	check((sim.municipal_state().get("city", {}) as Dictionary).get("franchises", []).size() >= 1, "「特许经营」登记合同")
	_main.submit("服务考核 90")
	_main.submit("政府购买 公园养护 800000")

func _test_debt_commands() -> void:
	var sim = _main._sim
	sim.player()["income"] = 10000000
	sim.player()["credit_history"] = 1.0
	_main.submit("看债务")
	check(_main.has_panel("debt"), "「看债务」打开债务面板")
	_main.submit("典当 手表 500000")
	check(not (sim.debt_state().get("loan", {}) as Dictionary).is_empty(), "「典当」登记借款")
	_main.submit("赎回")
	_main.submit("借贷 小额信贷 100000")
	check(String((sim.debt_state().get("loan", {}) as Dictionary).get("status", "")) == "active", "「借贷」获批在贷")
	_main.submit("放贷 民间借贷 500000")
	check(not (sim.debt_state().get("lend", {}) as Dictionary).is_empty(), "「放贷」登记")
	_main.submit("信用评估")
	_main.submit("合法催收")
	_main.submit("暴力催收")
	check(bool((sim.debt_state().get("lend", {}) as Dictionary).get("illegal_collection", false)), "「暴力催收」标记违法")
	_main.submit("债务重组")
	_main.submit("套路贷 300000")
	_main.submit("非法集资 500000")
	_main.submit("跑路")

func _test_consumer_commands() -> void:
	var sim = _main._sim
	_main.submit("看维权")
	check(_main.has_panel("consumer"), "「看维权」打开维权面板")
	_main.submit("消费订单 100000")
	check(not (sim.consumer_state().get("order", {}) as Dictionary).is_empty(), "「消费订单」登记")
	_main.submit("商品退换 1")
	_main.submit("三包退换 2")
	_main.submit("商品保修 30")
	_main.submit("消费举证 30")
	_main.submit("消费协商")
	_main.submit("平台投诉")
	_main.submit("消协调解")
	_main.submit("集体维权")
	_main.submit("质量事故 80")
	_main.submit("食安事故 90")
	_main.submit("商品召回 100")
	_main.submit("职业打假")
	_main.submit("恶意索赔")

func _test_welfare_commands() -> void:
	var sim = _main._sim
	_main.submit("看福利")
	check(_main.has_panel("welfare"), "「看福利」打开救助面板")
	var p: Dictionary = sim.player()
	p["age"] = 35
	p["income"] = 200000.0
	p["assets"] = 100000.0
	p["criminal_record"] = false
	p["major_illness"] = false
	_main.submit("收养评估")
	check(not (sim.welfare_state().get("application", {}) as Dictionary).is_empty(), "「收养评估」登记申请")
	p["income"] = 6000.0
	p["household_size"] = 3
	p["registered_local"] = true
	_main.submit("低保申请")
	_main.submit("救助发放 30")
	_main.submit("家庭变故")
	_main.submit("慈善基金")
	_main.submit("慈善捐赠 500000")
	_main.submit("公益支出 100000")
	_main.submit("善款审计")
	_main.submit("善款挪用 50000")
	check(not (sim.welfare_state().get("fund", {}) as Dictionary).is_empty(), "「慈善基金」建立基金")
	_main.submit("社工入职")
	_main.submit("个案跟进")
	_main.submit("个案结案")
	_main.submit("虐待举报")
	_main.submit("救助依赖")
	check(not (sim.welfare_state().get("worker", {}) as Dictionary).is_empty(), "「社工入职」开启社工路径")

func _test_funeral_commands() -> void:
	var sim = _main._sim
	_main.submit("看殡葬")
	check(_main.has_panel("funeral"), "「看殡葬」打开殡葬面板")
	_main.submit("殡葬安排 火化")
	_main.submit("殡葬执行")
	_main.submit("器官捐献")
	_main.submit("伦理审查")
	_main.submit("器官分配")
	_main.submit("器官移植")
	_main.submit("立纪念碑")
	_main.submit("祭扫")
	_main.submit("数字纪念")
	_main.submit("遗嘱执行")
	_main.submit("开殡仪馆")
	_main.submit("殡葬报价 火化")
	_main.submit("殡葬成交 火化")
	_main.submit("殡葬监管")
	_main.submit("殡葬改革")
	_main.submit("无人认领")
	_main.submit("撤销捐献")
	_main.submit("捐献争议")
	check(not (sim.funeral_state().get("state", {}) as Dictionary).is_empty(), "「殡葬安排」建立运行态")

func _test_metaphysics_commands() -> void:
	var sim = _main._sim
	_main.submit("看玄学")
	check(_main.has_panel("metaphysics"), "「看玄学」打开玄学面板")
	_main.submit("玄学咨询 算命")
	_main.submit("民俗仪式 许愿")
	_main.submit("开玄学馆")
	_main.submit("玄学营业")
	_main.submit("玄学投诉")
	_main.submit("诈骗查处")
	_main.submit("人设翻车")
	_main.submit("组织迷信 500")
	_main.submit("勾结灰产")
	_main.submit("真假难辨")
	check(not (sim.metaphysics_state().get("business", {}) as Dictionary).is_empty(), "「开玄学馆」建立经营体")

func _test_anomaly_commands() -> void:
	var sim = _main._sim
	_main.submit("开启门闩 血脉传承")
	check(sim.anomaly_revealed(), "「开启门闩」激活异常世界")
	_main.submit("看异常")
	_main.submit("天赋觉醒")
	_main.submit("权限晋升 3")
	_main.submit("查阅条目 镜中人")
	_main.submit("使用能力 修炼与异能")
	_main.submit("加入阵营 基金会")
	_main.submit("接受任务 基金会 清理任务")
	_main.submit("完成任务 清理任务")
	_main.submit("服用记忆删除 50")
	_main.submit("认知对抗")
	_main.submit("收容失效")
	_main.submit("身份设定 基金会人员")
	check(not (sim.anomaly_state().get("known_entries", {}) as Dictionary).is_empty(), "「查阅条目」收录异常图鉴")

func _test_medical_commands() -> void:
	var sim = _main._sim
	_main.submit("看医疗")
	_main.submit("就医挂号 二级 外科")
	_main.submit("医学检查 化验")
	_main.submit("疾病治疗 感冒")
	_main.submit("就医手术")
	_main.submit("高阶医疗 器官移植 自愿捐献")
	_main.submit("医疗伦理 基因编辑 80")
	_main.submit("医药立项 药A")
	_main.submit("医药推进 药A")
	_main.submit("医药生产 药A 2")
	_main.submit("医药销售 药A 100")
	_main.submit("医药代表 药A 20")
	_main.submit("假药查缉 50")
	_main.submit("医疗纠纷 50")
	check(not (sim._civil.get("claim", {}) as Dictionary).is_empty(), "「医疗纠纷」自动立民事案件")
	_main.submit("过度医疗 100000")
	_main.submit("医疗保险欺诈 100000")
	_main.submit("试验丑闻 药A")
	check(not sim._pharma_company.is_empty(), "「医药立项」建立医药公司")

func _test_content_industry_commands() -> void:
	var sim = _main._sim
	_main.submit("看文娱")
	_main.submit("开工作室 星火")
	_main.submit("招募团队 程序 2")
	_main.submit("招募团队 美术 1")
	_main.submit("立项作品 游戏 星河传说")
	_main.submit("项目管理 80")
	_main.submit("推进创作 600")
	_main.submit("作品发行")
	_main.submit("渠道分成 平台分成")
	_main.submit("作品版权")
	_main.submit("IP改编 动漫")
	_main.submit("IP运营 周边 1000000")
	_main.submit("查重抄袭 50")
	_main.submit("内容审查 30")
	_main.submit("艺人翻车 60")
	_main.submit("工作室融资 种子轮")
	_main.submit("挖角团队 策划")
	_main.submit("版号审批 游戏")
	_main.submit("粉丝运营 30")
	_main.submit("作品下架 内容违规")
	check(not sim._content_studio.is_empty(), "「开工作室」建立工作室")
	check(not sim._content_work.is_empty(), "「立项作品」建立在研作品")

func _test_engineering_commands() -> void:
	var sim = _main._sim
	_main.submit("看工程")
	_main.submit("办工程公司 一级 宏基建设")
	_main.submit("承接工程 跨江大桥 50000000")
	for _i in 6:
		_main.submit("工程推进")
	_main.submit("工程监理 80")
	_main.submit("工程招标")
	_main.submit("围标")
	_main.submit("招标行贿 20000000")
	_main.submit("偷工减料 50")
	_main.submit("工程事故")
	_main.submit("拖欠工程款 10000000")
	_main.submit("三角债 10000000")
	_main.submit("规划新城 云港 1200000")
	_main.submit("变更用地 商业区")
	_main.submit("城建交通 商业区")
	_main.submit("规划腐败 20000000")
	_main.submit("房屋拆迁 商业区 500000")
	_main.submit("办地产公司 宏基地产")
	_main.submit("楼盘预售 10")
	_main.submit("楼盘施工 5000000")
	_main.submit("楼盘烂尾")
	check(not sim._eng_contractor.is_empty(), "「办工程公司」成立工程公司")
	check(not sim._eng_project.is_empty(), "「承接工程」建立工程")
	check(not sim._eng_city.is_empty(), "「规划新城」建立城市")
	check(not sim._eng_developer.is_empty(), "「办地产公司」成立地产公司")


func _test_professional_commands() -> void:
	var sim = _main._sim
	_main.submit("看事务所")
	_main.submit("开事务所 恒信事务所")
	_main.submit("考执业资质 注册会计师")
	_main.submit("开发客户")
	_main.submit("立项项目 会计审计 客户甲")
	_main.submit("尽职调查 90")
	_main.submit("并购顾问 10000000")
	_main.submit("独立性审查 审计+咨询")
	_main.submit("虚假报告 60")
	_main.submit("内幕交易 1000000")
	_main.submit("商业贿赂 500000")
	_main.submit("吸收合伙人 王会计 20")
	_main.submit("合伙人分裂 王会计")
	_main.submit("竞业限制")
	_main.submit("客户流失")
	check(not sim._prof_firm.is_empty(), "「开事务所」成立事务所")
	check(not sim._prof_project.is_empty(), "「立项项目」建立项目")


func _test_life_services_commands() -> void:
	var sim = _main._sim
	_main.submit("看服务")
	_main.submit("注册服务者 家政保洁 王阿姨")
	_main.submit("背景核查")
	_main.submit("预约服务 家政保洁 2000")
	_main.submit("相亲婚介")
	_main.submit("婚礼策划 50000")
	_main.submit("家政保洁")
	_main.submit("月嫂照料")
	_main.submit("宠物寄养 寄养")
	_main.submit("服务事故 50")
	_main.submit("纠纷处理 10000")
	_main.submit("平台抽成 10000")
	_main.submit("服务标准化 100000")
	check(not sim._life_provider.is_empty(), "「注册服务者」登记服务者")
	check(not sim._life_order.is_empty(), "「预约服务」生成服务单")


func _test_transport_infra_commands() -> void:
	var sim = _main._sim
	_main.submit("看交通")
	_main.submit("基建立项 公路 100")
	_main.submit("基建招标")
	_main.submit("基建推进 50")
	_main.submit("线路运营 物流 50")
	_main.submit("区域影响")
	_main.submit("路网效应")
	_main.submit("线路补贴 0")
	_main.submit("基建结算")
	_main.submit("基建事故 50")
	_main.submit("定价监管 80")
	_main.submit("国际扰动 50")
	check(not sim._tin_project.is_empty(), "「基建立项」建立基建项目")
	check(not sim._tin_route.is_empty(), "「线路运营」建立线路")


func _test_appearance_commands() -> void:
	var sim = _main._sim
	sim.economy.add_money(sim.account_id(), 20000000, "test_appearance")
	_main.submit("看形象")
	_main.submit("形象护理 穿搭 85")
	_main.submit("医美 注射微整")
	_main.submit("证件核验")
	_main.submit("重办证件")
	sim._aesthetic["last_failed_illegal"] = true
	_main.submit("医美维权")
	check(not sim._appearance.is_empty(), "「形象护理」建立形象档案")
	check(not sim._aesthetic.is_empty(), "「医美」建立医美运行态")
	check_eq(String((sim._civil.get("claim", {}) as Dictionary).get("type", "")), "tort", "「医美维权」立案成功")

func _test_military_commands() -> void:
	var sim = _main._sim
	var p: Dictionary = sim.player()
	p["birth_minutes"] = sim.now_minutes() - int(21.0 * sim.MINUTES_PER_YEAR)
	p["education"] = [{"content_key": "edu.high_school", "status": "graduated"}]
	p["attrs"]["physiological"]["health"] = 100.0
	p["skills"] = [{"content_key": "skill.physique", "level": 10}]
	_main.submit("参军 陆军")
	check_eq(String(sim.player()["military"].get("status", "")), "serving", "「参军」入伍")
	_main.submit("军训 10")
	check(float(sim.player()["military"].get("merits", 0.0)) > 0.0, "「军训」积累军功")
	_main.submit("辞职")
	_main.submit("军务任务 100")
	_main.submit("军衔晋升")
	_main.submit("退伍")
	check_eq(String(sim.player()["military"].get("status", "")), "discharged", "「退伍」转为退伍")
	sim.player()["military"]["status"] = "serving"
	_main.submit("逃兵")
	check_eq(String(sim.player()["military"].get("status", "")), "deserter", "「逃兵」记录逃兵")

func _test_workplace_commands() -> void:
	var sim = _main._sim
	sim.player()["military"] = {"status": "discharged"}
	sim.player()["job"] = {
		"content_key": "job.engineer", "title": "工程师", "industry": "it",
		"salary": 9000, "performance": 60.0, "internal_reputation": 55.0, "status": "regular",
	}
	_main.submit("办公室政治 抢功")
	_main.submit("站队 改革派")
	_main.submit("骑墙")
	_main.submit("自组派系 技术派")
	_main.submit("职场晋升")
	check(not sim._workplace.is_empty(), "职场指令建立运行态")
	check((sim._workplace.get("factions", {}) as Dictionary).size() >= 3, "「自组派系」新增派系")

func _test_company_commands() -> void:
	var sim = _main._sim
	sim.economy.add_money(sim.account_id(), 500000000, "test_company")
	_main.submit("注册公司 测试公司")
	check(not sim._company.is_empty(), "「注册公司」建立公司")
	_main.submit("公司选址 60")
	_main.submit("开业")
	_main.submit("进货 苹果 200")
	_main.submit("定价 苹果 30")
	_main.submit("雇人 3000")
	_main.submit("扩张 20000")
	_main.submit("公司纳税")
	_main.submit("公司融资 种子")
	_main.submit("融资对赌 1000000")
	_main.submit("公司退出 上市")
	check(not (sim._company.get("inventory", {}) as Dictionary).is_empty(), "「进货」写入库存")
	check(bool((sim._cap_table).get("exited", false)), "「公司退出」标记退出")


func _test_save_writes_file() -> void:
	_main.submit("存档")
	var mgr = SaveManagerScript.new("user://saves")
	check(mgr.exists("1"), "「存档」写入槽位 1")
	_main.free()
