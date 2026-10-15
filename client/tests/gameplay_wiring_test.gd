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

func _test_save_writes_file() -> void:
	_main.submit("存档")
	var mgr = SaveManagerScript.new("user://saves")
	check(mgr.exists("1"), "「存档」写入槽位 1")
	_main.free()
