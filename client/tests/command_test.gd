extends "res://tests/test_base.gd"
## 中文指令解析器测试（任务 4.1 核心动词正反用例、任务 4.2 确定性与意图同源）。

const ParserScript = preload("res://command/command_parser.gd")
const RegistryScript = preload("res://command/verb_registry.gd")

func _suite_name() -> String:
	return "command"

func run_tests() -> void:
	_test_core_verbs()
	_test_particles_and_quantifiers()
	_test_negative_cases()
	_test_omission_and_pronoun()
	_test_ambiguity_and_index()
	_test_compound()
	_test_prefix_and_history()
	_test_help_and_suggest()
	_test_determinism()
	_test_source_equivalence()

# --- 测试上下文 ---

func _make_context() -> Dictionary:
	return {
		"catalogs": {
			"item": [
				{"id": "item_apple", "name": "苹果", "aliases": ["苹果手机"]},
				{"id": "item_water", "name": "水", "aliases": ["矿泉水"]},
				{"id": "item_phone", "name": "手机", "aliases": []},
			],
			"location": [
				{"id": "loc_beijing", "name": "北京", "aliases": ["北京市"]},
				{"id": "loc_home", "name": "家", "aliases": []},
			],
			"person": [
				{"id": "npc_zhangsan", "name": "张三", "aliases": ["小张"]},
			],
			"asset": [
				{"id": "asset_apple", "name": "苹果", "aliases": ["苹果股票"]},
			],
		},
		"slots": {
			"item": {"id": "item_water", "name": "水", "type": "item"},
			"location": {"id": "loc_home", "name": "家", "type": "location"},
			"person": {"id": "npc_zhangsan", "name": "张三", "type": "person"},
		},
		"recent": [{"id": "item_water", "name": "水", "type": "item"}],
	}

# --- 4.1 核心动词正反用例 ---

func _test_core_verbs() -> void:
	var p = ParserScript.new()
	var ctx := _make_context()

	check_eq(p.parse("帮助", ctx).verb, "帮助", "帮助 规范动词")
	check_eq(p.parse("help", ctx).verb, "帮助", "help 别名")
	check_eq(p.parse("?", ctx).verb, "帮助", "? 别名")
	check_eq(p.parse("看背包", ctx).verb, "看背包", "面板动词最长匹配")

	var go = p.parse("去北京", ctx)
	check(go.ok, "去北京 可执行")
	check_eq(go.verb, "去", "去 规范动词")
	check_eq(go.object_ids(), ["loc_beijing"], "去 地点解析")
	check_eq(p.parse("去北京市", ctx).object_ids(), ["loc_beijing"], "地点别名解析")

	var buy = p.parse("买两个苹果", ctx)
	check(buy.ok, "买两个苹果 可执行")
	check_eq(buy.verb, "买", "买 规范动词")
	check_eq(buy.object_ids(), ["item_apple"], "买 物品解析")
	check_eq(buy.params.get("quantity", 0), 2, "买 数量提取")
	check_eq(buy.params.get("unit", ""), "个", "买 量词归一")

	var eat = p.parse("吃苹果", ctx)
	check_eq(eat.verb, "吃", "吃 规范动词")
	check_eq(eat.object_ids(), ["item_apple"], "吃 物品解析")

	var save = p.parse("存钱1000元", ctx)
	check(save.ok, "存钱 可执行")
	check_eq(save.params.get("amount", 0), 1000, "金额提取")
	check_eq(save.params.get("amount_unit", ""), "元", "金额单位")

	var sleep = p.parse("睡8小时", ctx)
	check_eq(sleep.verb, "睡", "睡 规范动词")
	check_eq(sleep.params.get("duration", 0), 8, "时长提取")
	check_eq(sleep.params.get("duration_unit", ""), "小时", "时长单位")

	var chat = p.parse("聊天张三", ctx)
	check_eq(chat.verb, "聊天", "聊天 规范动词")
	check_eq(chat.object_ids(), ["npc_zhangsan"], "人物解析")

	var gift = p.parse("送张三苹果", ctx)
	check_eq(gift.verb, "赠送", "送 别名归一")
	check(gift.object_ids().has("npc_zhangsan") and gift.object_ids().has("item_apple"), "双对象解析")

func _test_particles_and_quantifiers() -> void:
	var p = ParserScript.new()
	var ctx := _make_context()

	var a = p.parse("把苹果吃了", ctx)
	check_eq(a.verb, "吃", "助词剥离后识别动词")
	check_eq(a.object_ids(), ["item_apple"], "助词不破坏对象")

	var b = p.parse("给张三送苹果", ctx)
	check_eq(b.verb, "赠送", "前置助词可跳过")
	check(b.object_ids().has("npc_zhangsan") and b.object_ids().has("item_apple"), "双对象解析")

	var c = p.parse("买三瓶矿泉水", ctx)
	check_eq(c.object_ids(), ["item_water"], "对象别名解析")
	check_eq(c.params.get("quantity", 0), 3, "中文数字归一")
	check_eq(c.params.get("unit", ""), "瓶", "量词归一")

# --- 负例 ---

func _test_negative_cases() -> void:
	var p = ParserScript.new()
	var ctx := _make_context()

	var unknown = p.parse("飞翔", ctx)
	check(not unknown.ok, "未知动词不可执行")
	check_eq(unknown.verb, "", "未知动词无规范名")
	check(unknown.error.find("无法识别") >= 0, "未知动词给出提示")

	var bad = p.parse("买圣杯", ctx)
	check(not bad.ok, "无效对象不可执行")
	check(bad.error.find("无法识别对象") >= 0, "无效对象给出具体原因")

	var missing = p.parse("去", {})
	check(not missing.ok, "无上下文时缺少地点失败")

# --- 省略补全与代词还原 ---

func _test_omission_and_pronoun() -> void:
	var p = ParserScript.new()
	var ctx := _make_context()

	var eat = p.parse("吃", ctx)
	check(eat.ok, "省略对象时按物品槽补全")
	check_eq(eat.object_ids(), ["item_water"], "物品槽默认对象")

	var go = p.parse("去", ctx)
	check(go.ok, "省略对象时按地点槽补全")
	check_eq(go.object_ids(), ["loc_home"], "地点槽默认对象")

	var use = p.parse("使用刚才的", ctx)
	check(use.ok, "代词「刚才的」还原")
	check_eq(use.object_ids(), ["item_water"], "代词还原到最近物品")

	var send = p.parse("送礼他苹果", ctx)
	check(send.ok, "人物代词还原且物品解析")
	check(send.object_ids().has("npc_zhangsan") and send.object_ids().has("item_apple"), "代词还原到人物槽")

# --- 多义候选与序号直选 ---

func _test_ambiguity_and_index() -> void:
	var p = ParserScript.new()
	var ctx := _make_context()

	var amb = p.parse("查看苹果", ctx)
	check(not amb.ok, "多义时不可直接执行")
	check_eq(amb.options.size(), 2, "多义候选数量")
	check(amb.error.find("序号") >= 0, "多义给出选择提示")
	check(amb.options[0].index == 1 and amb.options[1].index == 2, "候选序号从 1 起")

	var chosen = p.parse("2", ctx)
	check(chosen.ok, "序号直选成功")
	check_eq(chosen.object_ids(), ["item_apple"], "序号 2 选择物品苹果")

	# 同一段内附加序号。
	var p2 = ParserScript.new()
	var inline = p2.parse("查看苹果2", ctx)
	check(inline.ok, "同段序号直选成功")
	check_eq(inline.object_ids(), ["item_apple"], "同段序号选择物品苹果")

# --- 复合指令 ---

func _test_compound() -> void:
	var p = ParserScript.new()
	var ctx := _make_context()

	var ok = p.parse("去北京然后买苹果", ctx)
	check(ok.ok, "复合指令两段均成功")
	check_eq(ok.parts.size(), 2, "复合指令拆为两段")
	check_eq(ok.parts[0].verb, "去", "第一段动词")
	check_eq(ok.parts[1].verb, "买", "第二段动词")

	var fail = p.parse("飞翔然后买苹果", ctx)
	check(not fail.ok, "第一段失败即中断")
	check_eq(fail.parts.size(), 1, "失败后不再解析第二段")
	check(fail.error.find("第一段失败") >= 0, "复合失败说明段位")

# --- 前缀补全与历史 ---

func _test_prefix_and_history() -> void:
	var p = ParserScript.new()
	var ctx := _make_context()

	var reg = RegistryScript.new()
	check(reg.complete_prefix("存", {}).has("存钱"), "注册表前缀补全")
	var comp := p.complete("存", ctx)
	var found := false
	for item in comp:
		if item.get("value", "") == "存钱":
			found = true
	check(found, "解析器合并动词前缀补全")

	for i in range(25):
		p.record_history("cmd%d" % i)
	check_eq(p.history.size(), 20, "历史保留最近 20 条")
	check_eq(p.history[0], "cmd5", "历史淘汰最旧条目")
	check_eq(p.history[19], "cmd24", "历史保留最新条目")

# --- 帮助与提示 ---

func _test_help_and_suggest() -> void:
	var reg = RegistryScript.new()

	var normal := reg.help("")
	var has_hidden := false
	for e in normal:
		if e.get("verb", "") == "感知":
			has_hidden = true
	check(not has_hidden, "默认帮助过滤隐藏动词")

	var revealed := reg.help("", {"revealed_abnormal": true})
	var has_revealed := false
	for e in revealed:
		if e.get("verb", "") == "感知":
			has_revealed = true
	check(has_revealed, "接触异常后帮助包含隐藏动词")

	var trade := reg.help("物品与交易")
	check(not trade.is_empty(), "分类帮助非空")
	var wrong := false
	for e in trade:
		if e.get("category", "") != "物品与交易":
			wrong = true
	check(not wrong, "分类帮助仅含该分类")

	check(reg.suggest("存前", 3).has("存钱"), "未识别时给出相近动词")

# --- 4.2 确定性 ---

func _test_determinism() -> void:
	var ctx := _make_context()
	var a = ParserScript.new().parse("买两个苹果", ctx)
	var b = ParserScript.new().parse("买两个苹果", ctx)
	check_eq(a.to_dict(), b.to_dict(), "相同输入与上下文产出同一意图")

	var p = ParserScript.new()
	var first = p.parse("查看苹果", ctx)
	var second = p.parse("查看苹果", ctx)
	check_eq(first.to_dict(), second.to_dict(), "同一实例重复解析结果一致")

	# 多义排序确定性：候选顺序固定。
	check_eq(first.options[0].target.get("id", ""), "asset_apple", "多义候选排序稳定")

# --- 4.2 同源意图 ---

func _test_source_equivalence() -> void:
	var p = ParserScript.new()
	var ctx := _make_context()
	var apple := [{"id": "item_apple", "name": "苹果", "type": "item"}]
	var params := {"quantity": 2, "unit": "个"}

	var text = p.parse("买两个苹果", ctx, "text")
	var panel = p.from_action("买", apple, params, ctx, "panel")
	var hotkey = p.from_action("买", apple, params, ctx, "hotkey")

	check_eq(text.verb, panel.verb, "文字/面板 动词一致")
	check_eq(text.verb, hotkey.verb, "文字/快捷键 动词一致")
	check_eq(text.object_ids(), panel.object_ids(), "文字/面板 对象一致")
	check_eq(text.object_ids(), hotkey.object_ids(), "文字/快捷键 对象一致")
	check_eq(text.params.get("quantity", 0), panel.params.get("quantity", 0), "文字/面板 数量一致")
	check_eq(text.params.get("quantity", 0), hotkey.params.get("quantity", 0), "文字/快捷键 数量一致")
	check_eq(panel.source, "panel", "面板来源标记")
	check_eq(hotkey.source, "hotkey", "快捷键来源标记")
