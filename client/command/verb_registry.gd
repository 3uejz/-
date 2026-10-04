class_name VerbRegistry
extends RefCounted
## 内容驱动的动词注册表：注册、别名归一、最长匹配、前缀补全、
## 按情境动态过滤帮助与未识别提示。见 R27 验收 2/3/6/10/11。
## 完整动词基线（verb-registry.md 共 217 词）由任务 23 内容管线导入；
## 此处内置覆盖核心动词的种子，供解析器与测试使用。

## 别名按「长度降序、同长字典序升序」排序，保证最长匹配与确定性。
var _verbs: Dictionary = {}          ## 规范动词 -> 定义
var _alias_index: Dictionary = {}    ## 别名（含规范名）-> 规范动词
var _sorted_aliases: Array = []      ## 排序后的别名表
var _category_order: Array = []      ## 分类出现顺序（确定性）

func _init() -> void:
	_seed_core()

# --- 注册 ---

## 注册一个动词定义。def 字段：verb、aliases、object_types、params、
## category、usage、description、hidden。
func register(def: Dictionary) -> void:
	if not def.has("verb") or String(def["verb"]).is_empty():
		push_error("VerbRegistry.register 缺少 verb 字段")
		return
	var verb := String(def["verb"])
	var d: Dictionary = {
		"verb": verb,
		"aliases": _to_string_array(def.get("aliases", [])),
		"object_types": _to_string_array(def.get("object_types", [])),
		"params": _to_string_array(def.get("params", [])),
		"category": String(def.get("category", "未分类")),
		"usage": String(def.get("usage", verb)),
		"description": String(def.get("description", "")),
		"hidden": bool(def.get("hidden", false)),
	}
	_verbs[verb] = d
	if not _category_order.has(d["category"]):
		_category_order.append(d["category"])
	_alias_index[verb] = verb
	for a in d["aliases"]:
		_alias_index[String(a)] = verb
	_rebuild_aliases()

func register_all(defs: Array) -> void:
	for d in defs:
		if typeof(d) == TYPE_DICTIONARY:
			register(d)

func has(verb: String) -> bool:
	return _verbs.has(verb)

func get_def(verb: String) -> Dictionary:
	return _verbs.get(verb, {})

## 别名归一：返回规范动词；未注册返回空串。
func canonical_of(word: String) -> String:
	return String(_alias_index.get(word, ""))

func categories() -> Array:
	return _category_order.duplicate()

# --- 最长匹配分词 ---

## 在 pos 处取最长别名匹配，返回 {canonical, alias, length}，无则空。
func match_at(text: String, pos: int) -> Dictionary:
	for alias in _sorted_aliases:
		var a := String(alias)
		if pos + a.length() > text.length():
			continue
		if text.substr(pos, a.length()) == a:
			return {"canonical": _alias_index[a], "alias": a, "length": a.length()}
	return {}

## 最长匹配：优先起始位置；否则在其余位置取最长匹配（兼容灵活语序）。
## 返回 {canonical, alias, length, pos}。
func match_longest(text: String) -> Dictionary:
	var head: Dictionary = match_at(text, 0)
	if not head.is_empty():
		head["pos"] = 0
		return head
	var best: Dictionary = {}
	for pos in range(1, text.length()):
		var m: Dictionary = match_at(text, pos)
		if m.is_empty():
			continue
		if best.is_empty() or int(m["length"]) > int(best["length"]):
			best = m
			best["pos"] = pos
	return best

# --- 前缀补全 ---

## 返回以 prefix 开头的规范动词（去重排序），按情境过滤隐藏动词。
func complete_prefix(prefix: String, filter: Dictionary = {}) -> Array:
	var revealed := bool(filter.get("revealed_abnormal", false))
	var out: Array = []
	for verb in _verbs.keys():
		var d: Dictionary = _verbs[verb]
		if bool(d["hidden"]) and not revealed:
			continue
		var hit := String(verb).begins_with(prefix)
		if not hit:
			for a in d["aliases"]:
				if String(a).begins_with(prefix):
					hit = true
					break
		if hit:
			out.append(verb)
	out.sort()
	return out

# --- 帮助与提示 ---

## 按分类与情境动态生成帮助条目。filter 支持：revealed_abnormal、
## allowed_verbs、object_types。
func help(category: String = "", filter: Dictionary = {}) -> Array:
	var revealed := bool(filter.get("revealed_abnormal", false))
	var allowed: Array = filter.get("allowed_verbs", [])
	var otypes: Array = filter.get("object_types", [])
	var out: Array = []
	for verb in _verbs.keys():
		var d: Dictionary = _verbs[verb]
		if bool(d["hidden"]) and not revealed:
			continue
		if not category.is_empty() and String(d["category"]) != category:
			continue
		if not allowed.is_empty() and not allowed.has(verb):
			continue
		var dts: Array = d["object_types"]
		if not otypes.is_empty() and not dts.is_empty():
			var hit := false
			for t in dts:
				if otypes.has(t):
					hit = true
					break
			if not hit:
				continue
		out.append({
			"verb": verb,
			"category": d["category"],
			"usage": d["usage"],
			"description": d["description"],
			"aliases": (d["aliases"] as Array).duplicate(),
		})
	out.sort_custom(_cmp_help)
	return out

## 未识别时给出相近合法动词（编辑距离最近）。
func suggest(text: String, limit: int = 5) -> Array:
	var scored: Array = []
	for verb in _verbs.keys():
		var d: Dictionary = _verbs[verb]
		var names: Array = [verb]
		for a in d["aliases"]:
			names.append(a)
		var best := 99
		for nm in names:
			var dist := _edit_distance(text, String(nm))
			if dist < best:
				best = dist
		scored.append({"verb": verb, "distance": best})
	scored.sort_custom(_cmp_suggest)
	var out: Array = []
	for i in range(min(limit, scored.size())):
		out.append(scored[i]["verb"])
	return out

# --- 内部 ---

func _rebuild_aliases() -> void:
	var keys: Array = _alias_index.keys()
	keys.sort_custom(_cmp_alias)
	_sorted_aliases = keys

func _cmp_alias(a: Variant, b: Variant) -> bool:
	var sa := String(a)
	var sb := String(b)
	if sa.length() != sb.length():
		return sa.length() > sb.length()
	return sa < sb

func _cmp_help(a: Variant, b: Variant) -> bool:
	var ca := String(a["category"])
	var cb := String(b["category"])
	if ca != cb:
		return ca < cb
	return String(a["verb"]) < String(b["verb"])

func _cmp_suggest(a: Variant, b: Variant) -> bool:
	if int(a["distance"]) != int(b["distance"]):
		return int(a["distance"]) < int(b["distance"])
	return String(a["verb"]) < String(b["verb"])

func _to_string_array(v: Variant) -> Array:
	var out: Array = []
	if typeof(v) == TYPE_ARRAY:
		for item in v:
			out.append(String(item))
	return out

## 经典 Levenshtein 编辑距离，用于相近动词提示。
func _edit_distance(a: String, b: String) -> int:
	var la := a.length()
	var lb := b.length()
	if la == 0:
		return lb
	if lb == 0:
		return la
	var prev: Array = []
	for j in range(lb + 1):
		prev.append(j)
	for i in range(1, la + 1):
		var curr: Array = [i]
		for j in range(1, lb + 1):
			var cost := 0 if a[i - 1] == b[j - 1] else 1
			curr.append(min(min(curr[j - 1] + 1, prev[j] + 1), prev[j - 1] + cost))
		prev = curr
	return int(prev[lb])

## 内置核心动词种子（内容导入见任务 23，完整基线 217 词不在此处）。
func _seed_core() -> void:
	var defs: Array = [
		# 通用与元指令
		_seed("帮助", ["help", "?"], [], [], "通用与元指令", "帮助 [分类/动词]", "查看可用指令与用法"),
		_seed("查看", ["看", "查询"], [], [], "通用与元指令", "查看 <状态/背包/地图/关系/资产>", "查询状态或面板"),
		_seed("设置", ["配置"], [], ["number"], "通用与元指令", "设置 <字号/对比/倍速/音量> <值>", "修改设置"),
		_seed("存档", ["保存"], [], [], "通用与元指令", "存档 [名称]", "保存当前存档"),
		_seed("读档", ["加载"], [], [], "通用与元指令", "读档 [槽位]", "载入存档"),
		_seed("等待", ["等", "挂机"], [], ["duration"], "通用与元指令", "等待 <时长>", "推进时间"),
		_seed("暂停", ["停"], [], [], "通用与元指令", "暂停", "暂停时间流逝"),
		_seed("加速", ["倍速"], [], ["number"], "通用与元指令", "加速 <1/2/4>", "设置倍速"),
		_seed("快进", ["跳到"], [], ["duration"], "通用与元指令", "快进 <时点/事件>", "快进到某时点"),
		_seed("重开", ["转生"], [], [], "通用与元指令", "重开", "开始新的一生"),
		# 移动与出行
		_seed("去", ["前往", "移动"], ["location"], ["method"], "移动与出行", "去 <地点> [方式]", "前往某地点"),
		_seed("回家", ["回"], [], [], "移动与出行", "回家", "回到住所"),
		_seed("上班", ["去上班"], ["location"], [], "移动与出行", "上班 [公司]", "前往工作地点"),
		_seed("乘车", ["坐车", "搭车"], ["location"], ["method"], "移动与出行", "乘车 <目的地> [方式]", "乘坐交通工具"),
		_seed("出国", ["出境"], ["location"], [], "移动与出行", "出国 <国家>", "前往他国"),
		_seed("旅行", ["旅游"], ["location"], ["duration"], "移动与出行", "旅行 <目的地> <天数>", "外出旅行"),
		_seed("入住", ["住宿"], ["location"], ["duration"], "移动与出行", "入住 <酒店> <天数>", "入住酒店或民宿"),
		# 生理与日常
		_seed("吃", ["进食", "用餐"], ["item"], ["quantity"], "生理与日常", "吃 <食物> [数量]", "进食"),
		_seed("喝", ["饮用"], ["item"], ["quantity"], "生理与日常", "喝 <饮品> [数量]", "饮水"),
		_seed("睡", ["睡觉", "休息"], [], ["duration"], "生理与日常", "睡 <时长>", "睡眠休息"),
		_seed("锻炼", ["运动", "健身"], [], ["duration"], "生理与日常", "锻炼 [项目] <时长>", "锻炼身体"),
		_seed("理发", ["剪发"], [], [], "生理与日常", "理发 [发型]", "修剪头发"),
		_seed("吃药", ["服药"], ["item"], [], "生理与日常", "吃药 <药品>", "服药治疗"),
		# 物品与交易
		_seed("买", ["购买", "购入"], ["item"], ["quantity", "amount"], "物品与交易", "买 <物品> [数量]", "购买物品"),
		_seed("卖", ["出售", "卖出"], ["item"], ["quantity"], "物品与交易", "卖 <物品> [数量]", "出售物品"),
		_seed("使用", ["用"], ["item"], [], "物品与交易", "使用 <物品>", "使用物品"),
		_seed("丢弃", ["扔"], ["item"], ["quantity"], "物品与交易", "丢弃 <物品> [数量]", "丢弃物品"),
		_seed("赠送", ["送"], ["person", "item"], [], "物品与交易", "赠送 <人物> <物品>", "赠送物品给他人"),
		_seed("整理", ["收纳"], [], [], "物品与交易", "整理 [背包]", "整理背包"),
		_seed("网购", ["下单"], ["item"], ["quantity"], "物品与交易", "网购 <商品> [数量]", "在线购物"),
		_seed("点外卖", ["订餐"], ["item"], [], "物品与交易", "点外卖 <餐品>", "点外卖"),
		_seed("退货", ["退款"], [], [], "物品与交易", "退货 <订单>", "退货退款"),
		_seed("投诉", ["举报"], ["person", "item"], [], "物品与交易", "投诉 <商家/产品>", "投诉举报"),
		# 金融
		_seed("存钱", ["存款"], ["location"], ["amount"], "金融", "存钱 <金额> [期限]", "存入银行"),
		_seed("取钱", ["取款"], ["location"], ["amount"], "金融", "取钱 <金额>", "支取现金"),
		_seed("贷款", ["借款"], [], ["amount", "duration"], "金融", "贷款 <金额> [期限]", "申请贷款"),
		_seed("还款", ["还贷"], [], ["amount"], "金融", "还款 <金额>", "偿还贷款"),
		_seed("买股票", ["炒股"], ["asset"], ["quantity"], "金融", "买股票 <代码> [数量]", "买入股票"),
		_seed("卖股票", ["平仓"], ["asset"], ["quantity"], "金融", "卖股票 <代码> [数量]", "卖出股票"),
		_seed("纳税", ["报税"], [], ["amount"], "金融", "纳税 <税种>", "申报纳税"),
		_seed("赌博", ["下注"], [], ["amount"], "金融", "赌博 <项目> <金额>", "参与赌博"),
		# 职业与教育
		_seed("求职", ["应聘", "找工作"], [], [], "职业与教育", "求职 <岗位/公司>", "寻找工作"),
		_seed("面试", ["面谈"], ["location", "person"], [], "职业与教育", "面试 <公司>", "参加面试"),
		_seed("工作", ["打工"], [], ["duration"], "职业与教育", "工作 <时长>", "进行工作"),
		_seed("请假", ["休假"], [], ["duration"], "职业与教育", "请假 <天数>", "请假"),
		_seed("辞职", ["离职"], [], [], "职业与教育", "辞职", "辞去工作"),
		_seed("学习", ["上课", "进修"], ["skill"], ["duration"], "职业与教育", "学习 <课程/技能> [时长]", "学习技能"),
		_seed("考试", ["应考"], ["skill"], [], "职业与教育", "考试 <科目/证书>", "参加考试"),
		_seed("毕业", ["结业"], [], [], "职业与教育", "毕业", "完成学业"),
		# 社交与家庭
		_seed("聊天", ["交谈"], ["person"], [], "社交与家庭", "聊天 <人物> [话题]", "与他人交谈"),
		_seed("请客", ["宴请"], ["person", "location"], [], "社交与家庭", "请客 <人物> [地点]", "请客吃饭"),
		_seed("送礼", ["赠礼"], ["person", "item"], [], "社交与家庭", "送礼 <人物> <礼物>", "赠送礼物"),
		_seed("表白", ["告白"], ["person"], [], "社交与家庭", "表白 <人物>", "表达爱意"),
		_seed("约会", ["交往"], ["person", "location"], [], "社交与家庭", "约会 <人物> [地点]", "与对象约会"),
		_seed("求婚", ["结婚"], ["person"], [], "社交与家庭", "求婚 <人物>", "向对象求婚"),
		_seed("离婚", ["分手"], ["person"], [], "社交与家庭", "离婚 <配偶>", "解除婚姻"),
		# 医疗与法律
		_seed("挂号", ["预约"], ["location"], [], "医疗与法律", "挂号 <医院/科室>", "医院挂号"),
		_seed("看病", ["就诊"], ["location", "person"], [], "医疗与法律", "看病 <医生> [症状]", "就医问诊"),
		_seed("住院", ["入院"], ["location"], ["duration"], "医疗与法律", "住院 <天数>", "办理住院"),
		_seed("手术", ["开刀"], ["location"], [], "医疗与法律", "手术 <项目>", "接受手术"),
		# 面板查询
		_seed("看自己", ["看角色", "属性"], [], [], "面板查询", "看自己", "查看角色与属性"),
		_seed("看技能", ["技能树"], [], [], "面板查询", "看技能", "查看技能树"),
		_seed("看背包", ["背包"], [], [], "面板查询", "看背包", "查看背包与装备"),
		_seed("看关系", ["人脉"], [], [], "面板查询", "看关系", "查看人际关系"),
		_seed("看地图", ["地图"], [], [], "面板查询", "看地图", "查看地图"),
		_seed("看资产", ["财务"], [], [], "面板查询", "看资产", "查看财务资产"),
		# 冲突与战斗
		_seed("攻击", ["打", "砍", "开枪"], ["person"], [], "冲突与战斗", "攻击 <目标> [招式]", "对目标发起攻击"),
		_seed("防御", ["格挡", "防守"], [], [], "冲突与战斗", "防御", "进入防御姿态"),
		_seed("闪避", ["躲"], [], [], "冲突与战斗", "闪避", "闪避攻击"),
		_seed("逃跑", ["撤", "溜"], [], ["method"], "冲突与战斗", "逃跑 [方向]", "脱离战斗"),
		_seed("观察", ["探查"], ["person"], [], "冲突与战斗", "观察 <目标>", "观察目标"),
		_seed("选择", ["选"], [], ["number"], "冲突与战斗", "选择 <编号>", "选择选项"),
		# 异常（隐藏，接触后可用）
		_seed("感知", ["感应"], [], [], "异常", "感知 <异常>", "感知异常", true),
		_seed("收容", ["封印"], [], [], "异常", "收容 <异常实体>", "收容异常实体", true),
	]
	register_all(defs)

func _seed(verb: String, aliases: Array, object_types: Array, params: Array, category: String, usage: String, description: String, hidden: bool = false) -> Dictionary:
	return {
		"verb": verb,
		"aliases": aliases,
		"object_types": object_types,
		"params": params,
		"category": category,
		"usage": usage,
		"description": description,
		"hidden": hidden,
	}
