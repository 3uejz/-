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

## 面板查询动词 → 面板 id（与 ui/panel_registry.gd 的 PANELS 对齐）。
## 供 IntentExecutor 解析「看 X」类动词并打开对应面板，满足「所有面板支持中文指令打开」。
const PANEL_VERBS: Dictionary = {
	"看自己": "character", "看技能": "skills", "看背包": "inventory",
	"看关系": "relations", "看地图": "map", "看资产": "finance",
	"看工作": "career", "看成就": "achievements", "看家族史": "family",
	"看经营": "business", "看组织": "organizations", "看案件": "legal",
	"看灾害": "rescue", "看环保": "environment", "看市政": "municipal",
	"看债务": "debt", "看维权": "consumer", "看福利": "welfare",
	"看殡葬": "funeral", "看玄学": "metaphysics", "看医疗": "medical",
	"看心理": "mental",
	"看精神": "spirit",
	"看语言": "language",
	"看养老": "disability",
	"看农业": "agriculture",
	"看文娱": "content_industry", "看工程": "engineering", "看服务": "services",
	"看交通": "transport_infra", "看家庭": "household", "看体育": "sports",
	"看活动": "events", "看奖项": "awards", "看数字": "digital",
	"看科技": "late_tech",
	"看知识产权": "ip_media",
	"看疫情": "epidemic", "看军旅": "war", "看行情": "market",
	"看天气": "weather", "看异常": "anomaly", "看系统": "goldfinger",
	"看设置": "settings",
}

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
		# 房产
		_seed("看房", ["查房源", "看房源"], [], [], "物品与交易", "看房", "查看在售房源"),
		_seed("买房", ["购房", "购入房产"], ["property"], [], "物品与交易", "买房 <房源>", "购买房产"),
		_seed("卖房", ["售房"], ["property"], [], "物品与交易", "卖房 <房产>", "出售房产"),
		_seed("出租", ["放租"], ["property"], [], "物品与交易", "出租 <房产>", "出租房产收取租金"),
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
		_seed("怀孕", ["备孕", "生育"], [], [], "社交与家庭", "怀孕", "与配偶备孕"),
		_seed("立遗嘱", ["写遗嘱"], [], [], "社交与家庭", "立遗嘱", "订立遗嘱分配遗产"),
		# 宠物
		_seed("领养", ["领养宠物"], ["pet_species"], [], "社交与家庭", "领养 <宠物>", "领养宠物"),
		_seed("喂养", ["喂食"], [], [], "社交与家庭", "喂养", "喂养宠物"),
		_seed("训练宠物", ["驯养"], [], [], "社交与家庭", "训练宠物", "训练宠物"),
		# 子女收养与监护
		_seed("收养", ["收为养子", "收养子女"], [], [], "社交与家庭", "收养", "收养子女"),
		_seed("指定监护人", ["立监护人"], ["person"], [], "社交与家庭", "指定监护人 <人物>", "指定未成年子女的监护人"),
		# 医疗与法律
		_seed("挂号", ["预约"], ["location"], [], "医疗与法律", "挂号 <医院/科室>", "医院挂号"),
		_seed("看病", ["就诊"], ["location", "person"], [], "医疗与法律", "看病 <医生> [症状]", "就医问诊"),
		_seed("住院", ["入院"], ["location"], ["duration"], "医疗与法律", "住院 <天数>", "办理住院"),
		_seed("手术", ["开刀"], ["location"], [], "医疗与法律", "手术 <项目>", "接受手术"),
		# 心理与精神健康
		_seed("心理咨询", ["看心理医生"], ["mental_disorder"], [], "医疗与法律", "心理咨询 [病种]", "接受心理咨询"),
		_seed("心理治疗", ["认知行为治疗", "CBT"], ["mental_disorder"], [], "医疗与法律", "心理治疗 [病种]", "接受认知行为治疗"),
		_seed("精神科用药", ["服药治疗", "精神科"], ["mental_disorder"], [], "医疗与法律", "精神科用药 [病种]", "接受药物治疗"),
		_seed("重症干预", ["危机干预"], [], [], "医疗与法律", "重症干预", "接受重症心理干预"),
		_seed("放松", ["正念", "冥想", "减压"], [], [], "生理与日常", "放松", "放松身心、缓解压力"),
		# 精神追求与信仰（D15）
		_seed("修持", ["修炼", "修行", "静修"], ["pursuit"], ["duration"], "心理与精神", "修持 <法门> [时长]", "投入精神追求"),
		_seed("皈依", ["入教", "信教"], ["faith"], [], "心理与精神", "皈依 <信仰>", "加入信仰或哲学流派"),
		_seed("深化信仰", ["参悟", "诵经", "精进"], [], ["duration"], "心理与精神", "深化信仰 [时长]", "深化信仰修持"),
		_seed("化解危机", ["寻求开解", "寻求指引"], ["crisis_exit"], [], "心理与精神", "化解危机 <出口>", "化解精神危机"),
		# 组织与社团（D19）
		_seed("加入组织", ["参加组织", "入会"], ["organization"], [], "组织与社团", "加入组织 <组织>", "加入组织或社团"),
		_seed("退出组织", ["退会", "脱离组织"], ["organization"], [], "组织与社团", "退出组织 [组织]", "退出组织或社团"),
		_seed("缴会费", ["交会费", "缴纳会费"], ["organization"], [], "组织与社团", "缴会费 [组织]", "缴纳组织会费"),
		_seed("组织任务", ["执行组织任务", "办事"], ["organization"], [], "组织与社团", "组织任务 [组织]", "完成组织交办事务"),
		_seed("罢工", ["发起罢工"], ["organization"], [], "组织与社团", "罢工 [组织]", "发起集体罢工"),
		_seed("请愿", ["集体请愿"], ["organization"], [], "组织与社团", "请愿 [组织]", "发起集体请愿"),
		_seed("募捐", ["筹款"], ["organization"], [], "组织与社团", "募捐 [组织]", "发起组织募捐"),
		_seed("游行", ["集会游行"], ["organization"], [], "组织与社团", "游行 [组织]", "发起集体游行"),
		_seed("抵制", ["联合抵制"], ["organization"], [], "组织与社团", "抵制 [组织]", "发起联合抵制"),
		# 语言与文化（D20）
		_seed("学语言", ["学习语言", "上语言课", "学外语"], ["language"], ["duration"], "语言与文化", "学语言 <语言> [时长]", "学习一门外语"),
		_seed("沉浸", ["语言沉浸", "留学"], ["language"], ["duration"], "语言与文化", "沉浸 <语言> [天数]", "在语言环境中快速提升"),
		_seed("语言考试", ["考语言证书", "参加语言考试"], ["language"], [], "语言与文化", "语言考试 <语言>", "参加语言等级考试"),
		_seed("适应文化", ["融入当地", "文化适应"], ["culture"], ["duration"], "语言与文化", "适应文化 <文化> [天数]", "适应当地文化、减轻文化冲击"),
		# 残障与养老（D21）
		_seed("装辅具", ["配备辅具", "装配辅具"], ["device"], [], "残障与养老", "装辅具 <辅具>", "装配轮椅/助听器等辅助器具"),
		_seed("康复训练", ["手术康复", "康复治疗"], [], [], "残障与养老", "康复训练", "手术或康复部分恢复能力"),
		_seed("无障碍改造", ["改造无障碍"], [], [], "残障与养老", "无障碍改造", "改造居所/场所减少移动惩罚"),
		_seed("选养老", ["选择养老", "养老安置"], ["care_mode"], [], "残障与养老", "选养老 <模式>", "选择居家/社区/机构养老"),
		_seed("临终关怀", ["安宁疗护"], [], [], "残障与养老", "临终关怀", "安排临终关怀以减轻痛苦"),
		_seed("指定监护", ["设立监护", "设定监护"], [], ["person"], "残障与养老", "指定监护 <监护人>", "为丧失决策能力者设立监护人"),
		# 农业与乡土（D22）
		_seed("承包土地", ["租地", "买地", "取得土地"], [], [], "农业与乡土", "承包土地 [面积]", "承包/购买/租赁农地"),
		_seed("播种", ["种植", "下种"], ["crop"], [], "农业与乡土", "播种 <作物>", "在农地播种作物"),
		_seed("收割", ["收成", "收获"], [], [], "农业与乡土", "收割", "收割成熟作物入仓"),
		_seed("养畜", ["养殖", "养牲畜"], ["livestock"], [], "农业与乡土", "养畜 <牲畜>", "增加牲畜存栏"),
		_seed("卖粮", ["出售农产", "卖农产品"], ["crop"], [], "农业与乡土", "卖粮 <作物>", "售卖农产品"),
		_seed("农业补贴", ["申领补贴"], [], [], "农业与乡土", "农业补贴", "申领农业补贴"),
		# 数字生活与黑客（D23）
		_seed("开账号", ["注册账号", "开通账号"], ["platform"], [], "数字与平台", "开账号 <平台>", "在内容平台开通账号"),
		_seed("实名认证", ["数字实名"], [], [], "数字与平台", "实名认证", "为数字身份办理实名认证"),
		_seed("网络兼职", ["网络安全", "从事网络安全"], ["security_job"], [], "数字与平台", "网络兼职 <类型>", "从事渗透测试/安全防护等网络安全工作"),
		_seed("发布内容", ["开播", "发作品"], ["platform"], [], "数字与平台", "发布内容 [平台]", "发布直播/短视频并结算收益"),
		_seed("黑客攻击", ["入侵"], ["hack_target"], [], "数字与平台", "黑客攻击 <目标>", "实施未授权入侵（游戏内抽象判定）"),
		# 后期科技（D24）
		_seed("解锁科技", ["科技突破", "推进科技"], [], [], "后期科技", "解锁科技", "解锁下一科技阶段"),
		_seed("应聘科技职业", ["科技就业", "入职科技"], ["late_tech_career"], [], "后期科技", "应聘科技职业 <职业>", "应聘信息/智能/星际时代的职业"),
		_seed("科技任务", ["前沿任务", "高风险任务"], ["late_tech_mission"], [], "后期科技", "科技任务 <任务>", "执行高风险前沿科技任务"),
		_seed("生物延寿", ["科技延寿"], [], [], "后期科技", "生物延寿 [投入]", "投资生物科技以延长寿命"),
		# 知识产权与媒体（D25）
		_seed("登记知识产权", ["申请专利", "注册商标", "登记版权"], ["ip_type"], [], "知识产权与媒体", "登记知识产权 <类型>", "登记版权/专利/商标/商业秘密"),
		_seed("知识产权授权", ["IP授权", "授权作品"], [], [], "知识产权与媒体", "知识产权授权 <IP> [规模]", "对外许可并收取许可费"),
		_seed("知识产权转让", ["转让IP", "出售版权"], [], [], "知识产权与媒体", "知识产权转让 <IP> [价格]", "转让所有权并收取成交价"),
		_seed("知识产权质押", ["质押IP", "IP融资"], [], [], "知识产权与媒体", "知识产权质押 <IP> [金额]", "以 IP 质押融资"),
		_seed("知识产权维权", ["侵权诉讼", "维权诉讼"], [], [], "知识产权与媒体", "知识产权维权 <IP>", "对侵权发起诉讼并索赔"),
		_seed("开办媒体", ["成立媒体", "新建媒体"], ["media_type"], [], "知识产权与媒体", "开办媒体 <类型>", "开办新闻社/出版社/影视公司/MCN/平台"),
		_seed("发行作品", ["上线作品", "发行出版"], [], [], "知识产权与媒体", "发行作品 <标题>", "在媒体机构发行作品并结算票房/销量"),
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
	# 面板查询：PANEL_VERBS 中尚未登记的面板动词统一登记，
	# 确保全部 45 个面板都能通过中文指令「看 X」打开（与 ui/panel_registry 对齐）。
	var seeded: Dictionary = {}
	for d in defs:
		seeded[String((d as Dictionary)["verb"])] = true
	for key in PANEL_VERBS.keys():
		var verb := String(key)
		if seeded.has(verb):
			continue
		var pid := String(PANEL_VERBS[key])
		var hidden := pid == "anomaly" or pid == "goldfinger"
		defs.append(_seed(verb, [], [], [], "面板查询", verb, "查看%s面板" % verb.trim_prefix("看"), hidden))
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
