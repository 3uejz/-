class_name SimHost
extends RefCounted
## 玩法接线层：把 GameState 与各领域系统连接起来，供指令执行与时间推进使用。
## 纯逻辑、不依赖节点树或 Autoload，headless 测试可直接实例化。
##
## 职责边界：
## - 游戏内时钟（state.clock.absolute_minutes）随 advance() 推进，是存档里的时间字段；
##   UI 日历由 main 镜像到 WorldClock 展示，避免双份时间源。
## - 货币权威是 EconomySystem；player.finances 作为展示镜像，由 sync_finances() 回写。
## - 系统按需惰性实例化，起步目录（技能/职业/物品）在构造时注册，保证离线可玩。

const SurvivalScript = preload("res://sim/survival.gd")
const SkillsScript = preload("res://sim/skills.gd")
const JobsScript = preload("res://sim/jobs.gd")
const ItemsScript = preload("res://sim/items.gd")
const EconomyScript = preload("res://sim/economy.gd")
const RelationsScript = preload("res://sim/relations.gd")
const HappinessScript = preload("res://sim/happiness.gd")
const WeatherScript = preload("res://sim/weather.gd")
const BankScript = preload("res://sim/bank.gd")
const RngScript = preload("res://sim/rng.gd")
const BaselineScript = preload("res://sim/baseline.gd")
const GeoScript = preload("res://sim/geo.gd")
const RegionManagerScript = preload("res://sim/region_manager.gd")
const DomainWakeScript = preload("res://sim/domain_wake.gd")
const GregorianScript = preload("res://sim/gregorian.gd")
const NpcScript = preload("res://sim/npc.gd")
const FamilyScript = preload("res://sim/family.gd")
const PropertyScript = preload("res://sim/property.gd")
const InheritanceScript = preload("res://sim/inheritance.gd")
const PetScript = preload("res://sim/pet.gd")
const ParentingScript = preload("res://sim/parenting.gd")
const MentalHealthScript = preload("res://sim/mental_health.gd")
const PersonalityScript = preload("res://sim/personality.gd")
const SpiritualityScript = preload("res://sim/spirituality.gd")
const OrganizationScript = preload("res://sim/organizations.gd")
const LanguageScript = preload("res://sim/language.gd")
const DisabilityElderlyScript = preload("res://sim/disability_elderly.gd")
const AgricultureScript = preload("res://sim/agriculture.gd")
const DigitalScript = preload("res://sim/digital.gd")
const LateTechScript = preload("res://sim/late_tech.gd")
const IpMediaScript = preload("res://sim/ip_media.gd")
const ManufacturingScript = preload("res://sim/manufacturing.gd")
const TradeScript = preload("res://sim/trade.gd")
const MiningScript = preload("res://sim/mining_energy.gd")
const PrimaryScript = preload("res://sim/primary_industry.gd")
const DiningScript = preload("res://sim/dining.gd")
const FashionScript = preload("res://sim/fashion.gd")
const SportsIndustryScript = preload("res://sim/sports_industry.gd")
const EventsExpoScript = preload("res://sim/events_expo.gd")

const MINUTES_PER_DAY: int = 1440
## 所在城市熟人名册容量（首发单城社交/婚恋链接）。
const ACQUAINTANCE_COUNT: int = 8
## 所在城市在售房源数量（确定性生成，供看房/买房）。
const PROPERTY_LISTING_COUNT: int = 5
## 所在城市可加入组织类型（确定性生成，供加入组织）。
const ORG_TYPES_SEED: Array = ["union", "club", "ngo", "trade_association", "religious"]
## 妊娠天数（自受孕至分娩）。
const GESTATION_DAYS: int = 280
## 持有房产按月结算的间隔（天）。
const SETTLE_INTERVAL_DAYS: int = 30

## 每游戏年分钟数（用于子女成长/早夭按年结算）。
const MINUTES_PER_YEAR: float = 365.25 * 1440.0

## 子女成年年龄（R51.4）。
const ADULT_AGE: int = 18

## 收养子女 NPC 的独立序号段基址，避免与熟人（1..N）及亲生子女（100000 段）id 冲突。
const ADOPT_SEQ_BASE: int = 200000
## 首发默认国家（无有效 nation 时降级，见 design「首发单城」）。
const DEFAULT_COUNTRY: String = "CN"
## 地理气候带（GeoData）→ 天气气候带（baseline CLIMATE_ZONES）的确定性映射。
const CLIMATE_TO_ZONE: Dictionary = {
	"tropical": "tropical_monsoon",
	"subtropical": "subtropical_monsoon",
	"temperate": "temperate_continental",
	"cold": "subarctic_conifer",
	"polar": "polar_highland",
}

var state                       ## 需暴露 player / clock / world_delta / legacy / meta
var rng                         ## 确定性随机源（供面试、暴击等消费）
var survival
var skills
var jobs
var items
var economy
var relations
var happiness
var weather
var bank
var geo                         ## 六级地理（种子确定性生成，不入档）
var regions                     ## 分区休眠/唤醒与全人口（RegionManager）
var domain_wake                 ## 领域状态休眠补算（DomainWake）
var npcs                        ## NPC 个体生成（NpcSystem）
var family                      ## 恋爱/婚姻/繁衍（FamilySystem）
var property                    ## 房产（PropertySystem）
var inheritance                ## 继承（InheritanceSystem）
var pet                         ## 宠物（PetSystem）
var parenting                   ## 育儿与成长（ParentingSystem）
var mental                      ## 精神疾病与情绪（MentalHealthSystem）
var personality                 ## 大五人格与标签（PersonalitySystem）
var spirituality                ## 价值观三轴/精神追求/信仰（SpiritualitySystem）
var _spirit: Dictionary = {}    ## 精神追求运行时（深度/信仰/危机），入档 sim_runtime.spirituality
var organizations               ## 组织与社团（OrganizationSystem）
var _orgs: Array = []           ## 所在城市可加入组织（确定性生成，运行时叠加存档增量）
var language                    ## 语言与文化（LanguageSystem）
var _lang_profile: Dictionary = {}   ## 语言档案（分项/证书/适应），入档 sim_runtime.language
var _culture: Dictionary = {}        ## 文化适应状态（适应度/冲击），入档 sim_runtime.culture
var disability                  ## 残障与养老（DisabilityElderlySystem）
var _disability: Dictionary = {}     ## 残障/养老运行时（残障/辅具/养老/监护），入档 sim_runtime.disability
var _care_incident: Dictionary = {}  ## 最近一次护工事件（供追责）
var agriculture                 ## 农业与乡土（AgricultureSystem）
var _farm: Dictionary = {}           ## 农场运行时（土地/地块/牲畜/仓储/订单），入档 sim_runtime.farm
var digital                     ## 数字生活与黑客（DigitalSystem）
var _identity: Dictionary = {}       ## 数字身份运行时（账号/隐私/数据/数字资产），入档 sim_runtime.digital
var _creator: Dictionary = {}        ## 内容创作者运行时（粉丝/打赏/带货），入档 sim_runtime.digital
var _esports: Dictionary = {}        ## 电竞生涯运行时（战队/技能/伤病），入档 sim_runtime.digital
var late_tech                   ## 后期科技（LateTechSystem）
var _late_tech: Dictionary = {}      ## 后期科技运行时（阶段/解锁/失业/延寿），入档 sim_runtime.late_tech
var ip_media                    ## 知识产权与媒体（IpMediaSystem）
var _ips: Array = []                 ## 已登记知识产权，入档 sim_runtime.ip_media.ips
var _outlets: Array = []             ## 媒体机构，入档 sim_runtime.ip_media.outlets
var manufacturing                ## 制造业与供应链（ManufacturingSystem）
var _factory: Dictionary = {}        ## 玩家工厂运行时（工厂为纯数据字典），入档 sim_runtime.manufacturing
var trade                        ## 国际贸易、海关与物流（TradeSystem）
var _shipments: Array = []           ## 外贸单据列表，入档 sim_runtime.trade.shipments
var mining_energy                ## 矿业、能源与资源（MiningEnergySystem）
var _mine: Dictionary = {}           ## 玩家矿场运行时，入档 sim_runtime.mining.mine
var _energy: Dictionary = {}         ## 能源市场运行时（价格/期货/项目），入档 sim_runtime.mining.energy
var primary_industry             ## 农林牧渔深化（PrimaryIndustrySystem）
var _fishery: Dictionary = {}        ## 渔场运行时，入档 sim_runtime.primary.fishery
var _forest: Dictionary = {}         ## 林场运行时，入档 sim_runtime.primary.forest
var _hunter: Dictionary = {}         ## 狩猎运行时，入档 sim_runtime.primary.hunter
var _ecology: Dictionary = {}        ## 生态可持续运行时，入档 sim_runtime.primary.ecology
var dining                      ## 餐饮与食品工业（DiningSystem）
var _restaurant: Dictionary = {}     ## 玩家餐厅运行时（门店为纯数据字典），入档 sim_runtime.dining
var fashion                     ## 时尚、设计与奢侈品（FashionSystem）
var _brand: Dictionary = {}          ## 时尚品牌运行时，入档 sim_runtime.fashion.brand
var _trend: Dictionary = {}          ## 时尚潮流周期，入档 sim_runtime.fashion.trend
var sports_industry             ## 体育产业与赛事（SportsIndustrySystem）
var _pro_player: Dictionary = {}     ## 玩家职业运动员生涯，入档 sim_runtime.sports.player
var _sports_club: Dictionary = {}    ## 玩家所属球会，入档 sim_runtime.sports.club
var _sports_rival: Dictionary = {}   ## 联赛对手球会，入档 sim_runtime.sports.rival
var _sports_league: Dictionary = {}  ## 地区联赛，入档 sim_runtime.sports.league
var events_expo                 ## 会展、演出与大型活动（EventsExpoSystem）
var _event: Dictionary = {}          ## 当前筹办中的活动，入档 sim_runtime.events.event
var _planner: Dictionary = {}        ## 活动策划职业，入档 sim_runtime.events.planner

var _seeded: bool = false
var _seed: int = 0
var _home_region_id: String = ""
var _acquaintances: Array = []  ## 所在城市熟人（确定性生成，供社交/婚恋链接）
var _listings: Array = []       ## 所在城市在售房源（确定性生成，不入档）
var _inheritance_settled: bool = false
var _child_seq: int = 0
var _adopt_seq: int = 0

func _init(state_obj = null, seed: int = 0) -> void:
	_seed = seed
	rng = RngScript.new(seed)
	survival = SurvivalScript.new(seed)
	skills = SkillsScript.new()
	jobs = JobsScript.new()
	items = ItemsScript.new()
	economy = EconomyScript.new()
	relations = RelationsScript.new()
	happiness = HappinessScript.new()
	weather = WeatherScript.new(seed)
	bank = BankScript.new(seed)
	geo = GeoScript.new()
	regions = RegionManagerScript.new(null, seed)
	domain_wake = DomainWakeScript.new()
	regions.domain_wake = domain_wake
	npcs = NpcScript.new()
	family = FamilyScript.new(seed)
	property = PropertyScript.new()
	inheritance = InheritanceScript.new()
	pet = PetScript.new()
	parenting = ParentingScript.new()
	mental = MentalHealthScript.new()
	personality = PersonalityScript.new()
	spirituality = SpiritualityScript.new()
	_spirit = spirituality.new_state()
	organizations = OrganizationScript.new()
	language = LanguageScript.new()
	_lang_profile = language.new_profile()
	_culture = language.new_cultural_state()
	disability = DisabilityElderlyScript.new()
	_disability = disability.new_state()
	agriculture = AgricultureScript.new()
	_farm = agriculture.new_farm()
	digital = DigitalScript.new()
	_identity = digital.new_identity("player")
	late_tech = LateTechScript.new()
	_late_tech = late_tech.new_state()
	ip_media = IpMediaScript.new()
	manufacturing = ManufacturingScript.new()
	trade = TradeScript.new()
	mining_energy = MiningScript.new()
	_energy = mining_energy.new_energy_state()
	primary_industry = PrimaryScript.new()
	_ecology = primary_industry.new_ecology()
	dining = DiningScript.new()
	fashion = FashionScript.new()
	_trend = fashion.new_trend()
	sports_industry = SportsIndustryScript.new()
	events_expo = EventsExpoScript.new()
	skills.register_starter_catalog()
	jobs.register_starter_catalog()
	items.register_starter_catalog()
	if state_obj != null:
		bind(state_obj)

func bind(state_obj) -> void:
	state = state_obj
	_seeded = false
	_ensure_world()

func player() -> Dictionary:
	return state.player

func account_id() -> String:
	return String(player().get("id", "player"))

func now_minutes() -> int:
	return int(state.clock.get("absolute_minutes", 0))

func day_index() -> int:
	return now_minutes() / MINUTES_PER_DAY

## 惰性建立经济运行所需的账户，并用存档现金为玩家账户初始注资。
func _ensure_world() -> void:
	if _seeded or state == null:
		return
	var id := account_id()
	if not economy.has_account(id):
		var cash := float(player().get("finances", {}).get("cash", 0.0))
		economy.open_account(id, int(round(cash * float(BaselineScript.MONEY_MINOR_SCALE))))
	for external_id in ["employer", "bank", "market", "government"]:
		if not economy.has_account(external_id):
			economy.open_account(external_id, 100000000)
	_seeded = true
	_ensure_world_geo()

## 建立世界运行时：种子确定性生成六级地理，载入存档中的区域增量，登记玩家所在城市为
## 活动区域并绑定气候带，使区域人口/经济与天气随游戏内时钟演化（R5/R50、D1/D2）。
## 地理不入档（同种子可复现）；区域增量写入 world_delta.regions（design：存档只记变化量）。
func _ensure_world_geo() -> void:
	if state == null:
		return
	# 恢复生存运行时（成瘾复发/营养过量天数/死亡标志/遗嘱）。
	if state.sim_runtime is Dictionary:
		var sr: Variant = (state.sim_runtime as Dictionary).get("survival", {})
		if sr is Dictionary and not (sr as Dictionary).is_empty():
			survival.from_dict(sr)
		# 恢复精神疾病病程运行时（三维病程/复发/治疗标志）。
		var mr: Variant = (state.sim_runtime as Dictionary).get("mental", {})
		if mr is Dictionary and not (mr as Dictionary).is_empty():
			mental.from_dict(mr)
		# 恢复精神追求运行时（追求深度/信仰/危机）。
		var spr: Variant = (state.sim_runtime as Dictionary).get("spirituality", {})
		if spr is Dictionary and not (spr as Dictionary).is_empty():
			_spirit = spirituality.from_dict(spr)
		# 恢复语言档案（分项/证书）与文化适应状态。
		var lr: Variant = (state.sim_runtime as Dictionary).get("language", {})
		if lr is Dictionary and not (lr as Dictionary).is_empty():
			_lang_profile = language.from_dict(lr)
		var cr: Variant = (state.sim_runtime as Dictionary).get("culture", {})
		if cr is Dictionary and not (cr as Dictionary).is_empty():
			_culture = language.from_dict(cr)
		# 恢复残障/养老运行时（残障/辅具/养老模式/监护）。
		var dr: Variant = (state.sim_runtime as Dictionary).get("disability", {})
		if dr is Dictionary and not (dr as Dictionary).is_empty():
			_disability = disability.from_dict(dr)
		# 恢复农场运行时（土地/地块/牲畜/仓储/订单）。
		var fr: Variant = (state.sim_runtime as Dictionary).get("farm", {})
		if fr is Dictionary and not (fr as Dictionary).is_empty():
			_farm = agriculture.from_dict(fr)
		# 恢复数字身份/创作者/电竞运行时。
		var dig: Variant = (state.sim_runtime as Dictionary).get("digital", {})
		if dig is Dictionary and not (dig as Dictionary).is_empty():
			var dd: Dictionary = dig
			if dd.get("identity", null) is Dictionary:
				_identity = digital.from_dict(dd["identity"])
			if dd.get("creator", null) is Dictionary:
				_creator = (dd["creator"] as Dictionary).duplicate(true)
			if dd.get("esports", null) is Dictionary:
				_esports = (dd["esports"] as Dictionary).duplicate(true)
		# 恢复后期科技运行时（阶段/解锁/延寿）。
		var lt: Variant = (state.sim_runtime as Dictionary).get("late_tech", {})
		if lt is Dictionary and not (lt as Dictionary).is_empty():
			_late_tech = late_tech.from_dict(lt)
		# 恢复知识产权与媒体运行时（IP/媒体机构）。
		var im: Variant = (state.sim_runtime as Dictionary).get("ip_media", {})
		if im is Dictionary and not (im as Dictionary).is_empty():
			_ips = (im.get("ips", []) as Array).duplicate(true)
			_outlets = (im.get("outlets", []) as Array).duplicate(true)
		# 恢复制造业运行时（玩家工厂）。
		var mf: Variant = (state.sim_runtime as Dictionary).get("manufacturing", {})
		if mf is Dictionary and not (mf as Dictionary).is_empty():
			_factory = manufacturing.from_dict(mf)
		# 恢复国际贸易运行时（外贸单据）。
		var tr: Variant = (state.sim_runtime as Dictionary).get("trade", {})
		if tr is Dictionary and not (tr as Dictionary).is_empty():
			_shipments = ((tr as Dictionary).get("shipments", []) as Array).duplicate(true)
		# 恢复矿业/能源运行时（矿场/能源市场）。
		var mn: Variant = (state.sim_runtime as Dictionary).get("mining", {})
		if mn is Dictionary and not (mn as Dictionary).is_empty():
			var mnd: Dictionary = mn
			if mnd.get("mine", null) is Dictionary and not (mnd["mine"] as Dictionary).is_empty():
				_mine = (mnd["mine"] as Dictionary).duplicate(true)
			if mnd.get("energy", null) is Dictionary and not (mnd["energy"] as Dictionary).is_empty():
				_energy = (mnd["energy"] as Dictionary).duplicate(true)
		# 恢复农林牧渔深化运行时（渔场/林场/狩猎/生态）。
		var pr: Variant = (state.sim_runtime as Dictionary).get("primary", {})
		if pr is Dictionary and not (pr as Dictionary).is_empty():
			var prd: Dictionary = pr
			if prd.get("fishery", null) is Dictionary and not (prd["fishery"] as Dictionary).is_empty():
				_fishery = (prd["fishery"] as Dictionary).duplicate(true)
			if prd.get("forest", null) is Dictionary and not (prd["forest"] as Dictionary).is_empty():
				_forest = (prd["forest"] as Dictionary).duplicate(true)
			if prd.get("hunter", null) is Dictionary and not (prd["hunter"] as Dictionary).is_empty():
				_hunter = (prd["hunter"] as Dictionary).duplicate(true)
			if prd.get("ecology", null) is Dictionary and not (prd["ecology"] as Dictionary).is_empty():
				_ecology = (prd["ecology"] as Dictionary).duplicate(true)
		# 恢复餐饮运行时（玩家餐厅）。
		var dn: Variant = (state.sim_runtime as Dictionary).get("dining", {})
		if dn is Dictionary and not (dn as Dictionary).is_empty():
			var dnd: Dictionary = dn
			if dnd.get("restaurant", null) is Dictionary and not (dnd["restaurant"] as Dictionary).is_empty():
				_restaurant = dining.from_dict(dnd["restaurant"])
		# 恢复时尚运行时（品牌/潮流）。
		var fa: Variant = (state.sim_runtime as Dictionary).get("fashion", {})
		if fa is Dictionary and not (fa as Dictionary).is_empty():
			var fad: Dictionary = fa
			if fad.get("brand", null) is Dictionary and not (fad["brand"] as Dictionary).is_empty():
				_brand = fashion.from_dict(fad["brand"])
			if fad.get("trend", null) is Dictionary and not (fad["trend"] as Dictionary).is_empty():
				_trend = (fad["trend"] as Dictionary).duplicate(true)
		# 恢复体育运行时（生涯/球会/联赛）。
		var sp: Variant = (state.sim_runtime as Dictionary).get("sports", {})
		if sp is Dictionary and not (sp as Dictionary).is_empty():
			var spd: Dictionary = sp
			if spd.get("player", null) is Dictionary and not (spd["player"] as Dictionary).is_empty():
				_pro_player = (spd["player"] as Dictionary).duplicate(true)
			if spd.get("club", null) is Dictionary and not (spd["club"] as Dictionary).is_empty():
				_sports_club = (spd["club"] as Dictionary).duplicate(true)
			if spd.get("rival", null) is Dictionary and not (spd["rival"] as Dictionary).is_empty():
				_sports_rival = (spd["rival"] as Dictionary).duplicate(true)
			if spd.get("league", null) is Dictionary and not (spd["league"] as Dictionary).is_empty():
				_sports_league = (spd["league"] as Dictionary).duplicate(true)
		# 恢复会展运行时（活动/策划）。
		var ev: Variant = (state.sim_runtime as Dictionary).get("events", {})
		if ev is Dictionary and not (ev as Dictionary).is_empty():
			var evd: Dictionary = ev
			if evd.get("event", null) is Dictionary and not (evd["event"] as Dictionary).is_empty():
				_event = events_expo.from_dict(evd["event"])
			if evd.get("planner", null) is Dictionary and not (evd["planner"] as Dictionary).is_empty():
				_planner = (evd["planner"] as Dictionary).duplicate(true)
	if geo.count() == 0:
		geo.generate(_seed)
	regions.configure_population(_seed)
	# 载入存档中的区域增量（地理由种子重建，存档只存变化量）。
	var saved: Array = _saved_regions()
	if not saved.is_empty() and regions.region_ids().is_empty():
		regions.load_deltas(saved)
	_home_region_id = _resolve_home_region_id()
	if _home_region_id != "" and not regions.has_region(_home_region_id):
		regions.register_region(_home_region_id, _geo_region_opts(_home_region_id))
	if _home_region_id != "":
		regions.enter(_home_region_id, now_minutes())
		_write_player_region(_home_region_id)
	# 补齐气候（存档不持久化气候，按地理重建）并为每个区域绑定天气气候带。
	for rid in regions.region_ids():
		var region = regions.get_region(rid)
		if region != null and String(region.climate) == "":
			region.climate = _climate_for_region(String(rid))
		if not weather.has_region(String(rid)):
			weather.register_region(String(rid), _zone_for_region(String(rid)))
	_ensure_acquaintances()
	_ensure_property_market()
	_ensure_organizations()

## 生成所在城市的熟人名册（确定性），建立初始关系并恢复婚姻状态。
## 名册由（种子, 区域, 序号）确定，不入档；关系随 player.relations 持久化。
func _ensure_acquaintances() -> void:
	if not _acquaintances.is_empty() or _home_region_id == "":
		return
	for i in ACQUAINTANCE_COUNT:
		var npc: Dictionary = npcs.generate(i, {
			"world_seed": _seed, "region_id": _home_region_id,
			"now_minute": now_minutes(), "individualized": true, "lod_tier": 0,
		})
		_acquaintances.append(npc)
		relations.ensure_relation(player(), String(npc.get("id", "")))
	var sid := String(player().get("family", {}).get("spouse_id", ""))
	if sid != "":
		var spouse := find_person(sid)
		if not spouse.is_empty():
			family.marry(spouse)

## 所在城市熟人名册（供解析目录与社交/婚恋链接）。
func acquaintances() -> Array:
	return _acquaintances

func find_person(person_id: String) -> Dictionary:
	for a in _acquaintances:
		if String((a as Dictionary).get("id", "")) == person_id:
			return a
	if state != null and state.world_delta is Dictionary:
		for n in (state.world_delta as Dictionary).get("npcs", []):
			if typeof(n) == TYPE_DICTIONARY and String(n.get("id", "")) == person_id:
				return n
	return {}

## 名下子女（存档于 world_delta.npcs，按 player.family.children_ids 引用）。
func children() -> Array:
	var out: Array = []
	var fam: Dictionary = player().get("family", {})
	for cid in fam.get("children_ids", []):
		var c := find_person(String(cid))
		if not c.is_empty():
			out.append(c)
	return out

## 是否处于妊娠中。
func is_pregnant() -> bool:
	return not (player().get("family", {}).get("pregnancy", {}) as Dictionary).is_empty()

## 尝试受孕：需已婚且无进行中的妊娠，写入 family.pregnancy（schema 字段）。
func try_conceive() -> Dictionary:
	var fam: Dictionary = player().get("family", {})
	var sid := String(fam.get("spouse_id", ""))
	if sid == "":
		return {"ok": false, "reason": "not_married"}
	if is_pregnant():
		return {"ok": false, "reason": "already_pregnant"}
	var preg: Dictionary = {
		"partner_id": sid,
		"conceived_minutes": now_minutes(),
		"due_minutes": now_minutes() + GESTATION_DAYS * MINUTES_PER_DAY,
	}
	fam["pregnancy"] = preg
	player()["family"] = fam
	return {"ok": true, "pregnancy": preg}

func _write_player_region(region_id: String) -> void:
	if state == null or not (state.player is Dictionary):
		return
	(state.player as Dictionary)["region_id"] = region_id

func _saved_regions() -> Array:
	if state == null or not (state.world_delta is Dictionary):
		return []
	var raw: Variant = (state.world_delta as Dictionary).get("regions", [])
	return raw if raw is Array else []

func _climate_for_region(region_id: String) -> String:
	var node = geo.get_node(region_id)
	return String(node.attributes.get("climate", "")) if node != null else ""

## 区域增量（world_delta.regions，符合 region_delta schema）：仅持久化契约允许的字段，
## 经济/气候等附加量收进 snapshot（additionalProperties=true）。
func regions_delta() -> Array:
	var out: Array = []
	if regions == null:
		return out
	for id in regions.region_ids():
		var r = regions.get_region(id)
		if r == null:
			continue
		var snap: Dictionary = r.snapshot.duplicate(true)
		snap["economy"] = r.economy
		snap["climate"] = r.climate
		out.append({
			"region_key": String(id),
			"population": int(r.population),
			"price_index": float(r.price_index),
			"safety": float(r.safety),
			"last_simulated_minute": int(r.last_simulated_minute),
			"snapshot": snap,
		})
	return out

## 把当前区域增量写回 world_delta.regions（供存档与面板读取）。
func _persist_regions() -> void:
	if state == null or not (state.world_delta is Dictionary):
		return
	(state.world_delta as Dictionary)["regions"] = regions_delta()

## 由地理节点派生区域初始状态（人口/经济/物价/治安/气候），并锚定到当前时刻。
func _geo_region_opts(region_id: String) -> Dictionary:
	var opts: Dictionary = {"last_simulated_minute": now_minutes()}
	var node = geo.get_node(region_id)
	if node != null:
		opts["population"] = int(node.attributes.get("population", 0))
		opts["economy"] = float(node.attributes.get("economy", 0.5))
		opts["price_index"] = float(node.attributes.get("price_index", 1.0))
		opts["safety"] = float(node.attributes.get("safety", 50.0))
		opts["climate"] = String(node.attributes.get("climate", ""))
	return opts

## 玩家所在区域：优先取存档中的 player.region_id（旅行/搬迁写入），其次由 player.nation 解析
## 国家取其首个核心城市；均无效时降级默认国家。
func _resolve_home_region_id() -> String:
	var saved: String = String(player().get("region_id", ""))
	if saved != "" and geo.has_node(saved):
		return saved
	var code: String = _nation_country_code()
	var profile = geo.country_profile(code)
	if profile == null or profile.city_ids.is_empty():
		return ""
	return String(profile.city_ids[0])

func _nation_country_code() -> String:
	var nation: String = String(player().get("nation", "")).to_lower()
	if nation.begins_with("nation."):
		nation = nation.substr("nation.".length())
	if nation.length() == 2:
		for code in geo.countries():
			if String(code).to_lower() == nation:
				return String(code)
	return DEFAULT_COUNTRY

func _zone_for_region(region_id: String) -> String:
	var node = geo.get_node(region_id)
	if node != null:
		var climate: String = String(node.attributes.get("climate", ""))
		if CLIMATE_TO_ZONE.has(climate):
			return String(CLIMATE_TO_ZONE[climate])
	return "temperate_continental"

## 当前区域标识（首发固定在所在城市；旅行/搬迁经 set_home_region 覆盖）。
func current_region_id() -> String:
	return _home_region_id

## 当前所在区域的物价指数（相对全国基准，1.0 为基准）；无区域时返回 1.0。
func region_price_index() -> float:
	var rid: String = current_region_id()
	if rid == "" or regions == null or not regions.has_region(rid):
		return 1.0
	var idx: float = float(regions.get_region(rid).price_index)
	return idx if idx > 0.0 else 1.0

## 注册领域实体（案件/工程/灾害/催收/异常/手术）以供离线补算；见 DomainWake。
func domain_register(entry_id: String, kind: String, opts: Dictionary = {}) -> Dictionary:
	return domain_wake.register(entry_id, kind, opts)

## 与指定熟人结婚：纳入家庭并持久化到 player.family.spouse_id。
func marry_with(person_id: String) -> Dictionary:
	var npc := find_person(person_id)
	if npc.is_empty():
		return {"ok": false, "reason": "unknown_person"}
	family.marry(npc)
	var p: Dictionary = player()
	var fam: Dictionary = p.get("family", {})
	fam["spouse_id"] = String(npc.get("id", ""))
	p["family"] = fam
	var rel: Dictionary = relations.ensure_relation(p, person_id)
	rel["romance"] = true
	relations.set_circle(rel, "family")
	return {"ok": true, "spouse": npc}

## 离婚：结算家庭状态并清除存档婚姻字段。
func divorce() -> Dictionary:
	var r: Dictionary = family.divorce(rng)
	if not bool(r.get("ok", false)):
		return r
	var p: Dictionary = player()
	var fam: Dictionary = p.get("family", {})
	fam.erase("spouse_id")
	p["family"] = fam
	return r

## 当前配偶档案（无则空）。
func spouse() -> Dictionary:
	var sid := String(player().get("family", {}).get("spouse_id", ""))
	return find_person(sid) if sid != "" else {}

## 生成所在城市在售房源（确定性，不入档）；已购入的房源不再挂牌。
func _ensure_property_market() -> void:
	if not _listings.is_empty() or _home_region_id == "":
		return
	var rid := _home_region_id
	var city := rid
	var node = geo.get_node(rid)
	if node != null:
		city = String(node.name)
	var r = RngScript.new(_seed * 1000003 + rid.hash())
	var mult := region_price_index()
	var districts := ["城区", "城郊", "老城", "新区", "湖畔"]
	var layouts := ["1室1厅", "2室1厅", "3室2厅", "4室2厅"]
	for i in PROPERTY_LISTING_COUNT:
		var area := 40 + _rand_int(r, 13) * 10
		var layout: String = layouts[_rand_int(r, layouts.size())]
		var base := int(round(float(area) * (80000.0 + float(_rand_int(r, 60)) * 1000.0) * mult))
		var p: Dictionary = property.make_property({
			"id": "prop:%s:%d" % [rid, i],
			"name": "%s%s房" % [city, districts[i % districts.size()]],
			"city": city,
			"district": districts[i % districts.size()],
			"area_sqm": area,
			"layout": layout,
			"base_price": base,
			"property_fee_month": int(round(float(area) * 2.0)),
			"monthly_rent": int(round(float(base) * 0.0025)),
		})
		if p.is_empty() or not find_owned(String(p.get("id", ""))).is_empty():
			continue
		_listings.append(p)

## 生成所在城市的可加入组织（确定性），载入存档运行时增量。
## 组织由（种子, 区域, 类型序号）确定，不入确定性世界；成员资格随 player.org_memberships
## 持久化，组织运行态（成员数/影响力/热度/派系）随 sim_runtime.organizations 持久化。
func _ensure_organizations() -> void:
	if not _orgs.is_empty() or _home_region_id == "":
		return
	var rid := _home_region_id
	var city := rid
	var node = geo.get_node(rid)
	if node != null:
		city = String(node.name)
	var r = RngScript.new(_seed * 2000003 + rid.hash())
	for i in ORG_TYPES_SEED.size():
		var t: String = ORG_TYPES_SEED[i]
		var def: Dictionary = organizations.type_def(t)
		if def.is_empty():
			continue
		var members := int(def.get("min_members", 5)) + _rand_int(r, 200)
		var created: Dictionary = organizations.create_org(t, members, {
			"id": "org:%s:%d" % [rid, i],
			"name": "%s%s" % [city, String(def.get("name", t))],
		})
		if not bool(created.get("ok", false)):
			continue
		_orgs.append(created["org"])
	if state != null and state.sim_runtime is Dictionary:
		var saved: Variant = (state.sim_runtime as Dictionary).get("organizations", [])
		if saved is Array:
			for so in saved:
				if not (so is Dictionary):
					continue
				var target := find_org(String((so as Dictionary).get("id", "")))
				if target.is_empty():
					continue
				for k in (so as Dictionary).keys():
					target[k] = (so as Dictionary)[k]

func _rand_int(r, bound: int) -> int:
	if bound <= 0:
		return 0
	return mini(bound - 1, int(r.next_float() * float(bound)))

## 在售房源视图（含市场估值报价）。
func property_listings() -> Array:
	var out: Array = []
	for p in _listings:
		var v: Dictionary = property.view(p)
		v["price"] = property.market_value(p, {"rate": PropertyScript.MORTGAGE_RATE_ANNUAL})
		v["monthly_payment"] = property.mortgage_payment(
			int(round(float(v["price"]) * (1.0 - PropertyScript.DOWN_PAYMENT_RATIO))))
		out.append(v)
	return out

## 名下房产视图。
func property_owned() -> Array:
	var out: Array = []
	for p in property.owned_properties(player()):
		var v: Dictionary = property.view(p)
		v["price"] = property.market_value(p)
		v["rented"] = bool(p.get("rented", false))
		v["has_mortgage"] = not (p.get("mortgage", {}) as Dictionary).is_empty()
		out.append(v)
	return out

## 解析目录用房源清单（在售 + 名下），供「买房/卖房/出租 <房源>」链接。
func property_catalog() -> Array:
	var out: Array = []
	for p in _listings:
		out.append({"id": String(p.get("id", "")), "name": String(p.get("name", "")), "owned": false})
	for p in property.owned_properties(player()):
		out.append({"id": String(p.get("id", "")), "name": String(p.get("name", "")), "owned": true})
	return out

func find_listing(prop_id: String) -> Dictionary:
	for p in _listings:
		if String((p as Dictionary).get("id", "")) == prop_id:
			return p
	return {}

func find_owned(prop_id: String) -> Dictionary:
	for p in property.owned_properties(player()):
		if String((p as Dictionary).get("id", "")) == prop_id:
			return p
	return {}

## 购买房源：扣首付/契税、形成房贷并计入名下资产，从挂牌移除。
func property_purchase(prop_id: String, opts: Dictionary = {}) -> Dictionary:
	var prop := find_listing(prop_id)
	if prop.is_empty():
		return {"ok": false, "reason": "not_listed"}
	var r: Dictionary = property.purchase(player(), economy, account_id(), prop, day_index(), opts)
	if bool(r.get("ok", false)):
		_listings.erase(prop)
		sync_finances()
	return r

## 出售名下房产。
func property_sell(prop_id: String, opts: Dictionary = {}) -> Dictionary:
	var prop := find_owned(prop_id)
	if prop.is_empty():
		return {"ok": false, "reason": "not_owned"}
	var r: Dictionary = property.sell(player(), economy, account_id(), prop, opts)
	if bool(r.get("ok", false)):
		sync_finances()
	return r

## 出租名下房产（设定月租并按月收租）。
func property_rent(prop_id: String, monthly_rent: int = -1) -> Dictionary:
	var prop := find_owned(prop_id)
	if prop.is_empty():
		return {"ok": false, "reason": "not_owned"}
	var rent: int = monthly_rent if monthly_rent >= 0 else int(property.estimated_monthly_rent(prop))
	property.set_rent(prop, rent, true)
	return {"ok": true, "monthly_rent": rent}

# --- 组织与社团（D19） ---

## 可加入组织目录（供解析器链接「加入组织 <组织>」）。
func organizations_catalog() -> Array:
	var out: Array = []
	for org in _orgs:
		out.append({"id": String((org as Dictionary).get("id", "")), "name": String((org as Dictionary).get("name", ""))})
	return out

func find_org(org_id: String) -> Dictionary:
	for org in _orgs:
		if (org is Dictionary) and String((org as Dictionary).get("id", "")) == org_id:
			return org
	return {}

## 加入组织：写入成员契约并扣除首次会费（不足则回滚）。
func join_organization(org_id: String) -> Dictionary:
	var org := find_org(org_id)
	if org.is_empty():
		return {"ok": false, "reason": "not_found"}
	var r: Dictionary = organizations.join(player(), org, {"minute": now_minutes()})
	if not bool(r.get("ok", false)):
		return r
	var fee := int(r.get("dues", 0))
	if fee > 0:
		if economy.cash(account_id()) < fee:
			organizations.leave(player(), org, {"approved": true})
			return {"ok": false, "reason": "insufficient_funds", "dues": fee}
		economy.add_money(account_id(), -fee, "org_dues:%s" % org_id)
		sync_finances()
		var entry: Dictionary = organizations.membership(player(), org_id)
		if not entry.is_empty():
			organizations.pay_dues(entry, fee)
	_persist_organizations()
	r["name"] = String(org.get("name", ""))
	return r

## 退出组织：结算退出成本与叛逃/法律风险。
func leave_organization(org_id: String, approved: bool = false) -> Dictionary:
	var org := find_org(org_id)
	if org.is_empty():
		return {"ok": false, "reason": "not_found"}
	var r: Dictionary = organizations.leave(player(), org, {"approved": approved})
	if bool(r.get("ok", false)):
		_persist_organizations()
	r["name"] = String(org.get("name", ""))
	return r

## 缴纳组织会费（缺省清欠全部）。
func pay_org_dues(org_id: String, amount: int = -1) -> Dictionary:
	var entry: Dictionary = organizations.membership(player(), org_id)
	if entry.is_empty():
		return {"ok": false, "reason": "not_member"}
	var owed := int(entry.get("dues_owed", 0))
	var pay := owed if amount < 0 else mini(amount, owed)
	if pay <= 0:
		return {"ok": false, "reason": "nothing_due"}
	if economy.cash(account_id()) < pay:
		return {"ok": false, "reason": "insufficient_funds", "dues": pay}
	economy.add_money(account_id(), -pay, "org_dues:%s" % org_id)
	sync_finances()
	var r: Dictionary = organizations.pay_dues(entry, pay)
	_persist_organizations()
	return r

## 承接并完成一次组织任务：成功计任务数并可能晋升（晋升发放津贴）。
func do_org_task(org_id: String) -> Dictionary:
	var org := find_org(org_id)
	if org.is_empty():
		return {"ok": false, "reason": "not_found"}
	var entry: Dictionary = organizations.membership(player(), org_id)
	if entry.is_empty():
		return {"ok": false, "reason": "not_member"}
	if String(entry.get("pending_task", "")).is_empty():
		organizations.assign_task(org, entry, "organizing")
	var success: bool = rng.next_float() < 0.6
	var r: Dictionary = organizations.complete_task(org, entry, success)
	var promoted := false
	if success and organizations.evaluate_promotion(org, entry):
		var pr: Dictionary = organizations.promote(org, entry)
		promoted = bool(pr.get("ok", false))
		if promoted:
			var stip: int = organizations.stipend(entry)
			if stip > 0:
				economy.add_money(account_id(), stip, "org_stipend:%s" % org_id)
				sync_finances()
	r["promoted"] = promoted
	r["rank_name"] = String((organizations.rank(int(entry.get("rank_index", 0))) as Dictionary).get("name", ""))
	_persist_organizations()
	return r

## 发起集体行动（罢工/请愿/募捐/游行/抵制）；秘密组织可能因失败抬升热度而暴露。
func org_collective_action(org_id: String, action: String) -> Dictionary:
	var org := find_org(org_id)
	if org.is_empty():
		return {"ok": false, "reason": "not_found"}
	var entry: Dictionary = organizations.membership(player(), org_id)
	if entry.is_empty():
		return {"ok": false, "reason": "not_member"}
	var r: Dictionary = organizations.collective_action(org, action, {}, rng)
	if not bool(r.get("ok", false)):
		return r
	if organizations.is_secret(org):
		var ex: Dictionary = organizations.attempt_expose(org, {}, rng)
		if bool(ex.get("exposed", false)):
			var hx: Dictionary = organizations.handle_exposure(player(), org)
			r["exposed"] = true
			r["wanted_level"] = int(hx.get("wanted_level", 0))
	_persist_organizations()
	return r

## 组织面板数据（已加入成员资格 + 可加入组织）。
func organizations_panel_data() -> Dictionary:
	var memberships: Array = []
	for entry in organizations.memberships(player()):
		if not (entry is Dictionary):
			continue
		var org := find_org(String((entry as Dictionary).get("org_id", "")))
		if org.is_empty():
			continue
		var type_def: Dictionary = organizations.type_def(String(org.get("type", "")))
		var rank_def: Dictionary = organizations.rank(int((entry as Dictionary).get("rank_index", 0)))
		memberships.append({
			"id": String(org.get("id", "")),
			"name": String(org.get("name", "")),
			"type": String(type_def.get("name", "")),
			"legality": String(org.get("legality", "")),
			"rank": String(rank_def.get("name", "")),
			"members": int(org.get("members", 0)),
			"influence": "%s%%" % str(snappedf(float(org.get("influence", 0.0)) * 100.0, 0.1)),
			"dues_owed": int((entry as Dictionary).get("dues_owed", 0)),
			"tasks_completed": int((entry as Dictionary).get("tasks_completed", 0)),
		})
	var available: Array = []
	for org in _orgs:
		if not organizations.membership(player(), String((org as Dictionary).get("id", ""))).is_empty():
			continue
		var td: Dictionary = organizations.type_def(String((org as Dictionary).get("type", "")))
		available.append({
			"id": String((org as Dictionary).get("id", "")),
			"name": String((org as Dictionary).get("name", "")),
			"type": String(td.get("name", "")),
			"fee": int(td.get("base_fee", 0)),
			"legality": String((org as Dictionary).get("legality", "")),
		})
	return {"memberships": memberships, "available": available}

## 持久化组织运行态到 state.sim_runtime.organizations。
func _persist_organizations() -> void:
	if state == null or not (state.sim_runtime is Dictionary):
		return
	var arr: Array = []
	for org in _orgs:
		arr.append((org as Dictionary).duplicate(true))
	(state.sim_runtime as Dictionary)["organizations"] = arr

# --- 语言与文化（D20） ---

## 可学语言目录（供解析器链接「学语言 <语言>」）。
func languages_catalog() -> Array:
	var out: Array = []
	for lang in language.languages():
		var def: Dictionary = language.language_def(String(lang))
		out.append({"id": String(lang), "name": String(def.get("name", lang))})
	return out

func language_state() -> Dictionary:
	return _lang_profile

## 学习语言：按课程/沉浸/自学推进分项等级。opts 可含 aptitude。
func study_language(lang: String, method: String, hours: float, opts: Dictionary = {}) -> Dictionary:
	if not language.has_language(lang):
		return {"ok": false, "reason": "unknown_language"}
	if not language.STUDY_METHODS.has(method):
		return {"ok": false, "reason": "unknown_method"}
	var o: Dictionary = opts.duplicate()
	o["day"] = day_index()
	var r: Dictionary = language.study(_lang_profile, lang, method, hours, o)
	if bool(r.get("ok", false)):
		_persist_language()
	return r

## 环境沉浸：以沉浸法按天学习。
func immerse_language(lang: String, days: float) -> Dictionary:
	if not language.has_language(lang):
		return {"ok": false, "reason": "unknown_language"}
	var o: Dictionary = {"day": day_index()}
	var r: Dictionary = language.immerse(_lang_profile, lang, days, o)
	if bool(r.get("ok", false)):
		_persist_language()
	return r

## 参加语言考试：达到目标等级颁发证书。
func take_language_exam(lang: String, target_level: float) -> Dictionary:
	if not language.has_language(lang):
		return {"ok": false, "reason": "unknown_language"}
	var r: Dictionary = language.take_exam(_lang_profile, lang, target_level, {}, rng)
	if bool(r.get("ok", false)):
		_persist_language()
	return r

## 文化适应：按天推进对某文化的适应度并降低文化冲击。
func adapt_culture(culture: String, days: float) -> Dictionary:
	if language.culture_def(culture).is_empty():
		return {"ok": false, "reason": "unknown_culture"}
	var r: Dictionary = language.adapt(_culture, culture, days)
	if bool(r.get("ok", false)):
		_persist_language()
	return r

## 当日节日效果（基于日历，用于商铺/交通/社交/心情联动）。
func today_festival_effects() -> Dictionary:
	var cal: Dictionary = GregorianScript.from_absolute_minutes(now_minutes())
	return language.festival_effects(int(cal.get("month", 1)), int(cal.get("day", 1)))

## 语言与文化面板数据（语言分项/证书/文化适应/今日节日）。
func language_panel_data() -> Dictionary:
	var langs: Array = []
	for lang in language.languages():
		var key := String(lang)
		var def: Dictionary = language.language_def(key)
		langs.append({
			"id": key,
			"name": String(def.get("name", key)),
			"overall": snappedf(language.overall(_lang_profile, key), 0.1),
			"speaking": snappedf(language.component(_lang_profile, key, "speaking"), 0.1),
			"listening": snappedf(language.component(_lang_profile, key, "listening"), 0.1),
			"literacy": snappedf(language.component(_lang_profile, key, "literacy"), 0.1),
		})
	var certs: Array = []
	for c in language.certificates(_lang_profile):
		if not (c is Dictionary):
			continue
		var cd: Dictionary = c
		var ldef: Dictionary = language.language_def(String(cd.get("lang", "")))
		certs.append({"label": "%s 等级 %.0f" % [String(ldef.get("name", cd.get("lang", ""))), float(cd.get("level", 0.0))], "value": "已获证书"})
	var cults: Array = []
	for ck in language.CULTURES.keys():
		var key := String(ck)
		cults.append({
			"name": String((language.CULTURES[ck] as Dictionary).get("name", key)),
			"adaptation": snappedf(language.current_adaptation(_culture, key), 0.01),
		})
	return {
		"languages": langs,
		"certificates": certs,
		"cultures": cults,
		"shock": snappedf(float(_culture.get("shock", 0.0)), 0.01),
		"festival": today_festival_effects(),
	}

## 语言遗忘：跨日推进时对长期未用语言按闲置天数衰减。
func _decay_languages(before_minutes: int, after_minutes: int) -> void:
	if after_minutes / MINUTES_PER_DAY <= before_minutes / MINUTES_PER_DAY:
		return
	var langs: Variant = _lang_profile.get("languages", {})
	if not (langs is Dictionary):
		return
	for lang in (langs as Dictionary).keys():
		var entry: Dictionary = (langs as Dictionary)[lang]
		var last_day: float = float(entry.get("last_used_day", 0.0))
		var idle: float = float(day_index()) - last_day
		if idle > 0.0:
			language.decay(_lang_profile, String(lang), idle)

func _persist_language() -> void:
	if state == null or not (state.sim_runtime is Dictionary):
		return
	(state.sim_runtime as Dictionary)["language"] = language.to_dict(_lang_profile)
	(state.sim_runtime as Dictionary)["culture"] = language.to_dict(_culture)


# --- 残障与养老（D21） ---

func disability_state() -> Dictionary:
	return _disability

## 辅具目录（供解析器链接「装辅具 <辅具>」）。
func disability_devices_catalog() -> Array:
	var out: Array = []
	for key in disability.DEVICES.keys():
		var d: Dictionary = disability.DEVICES[key]
		out.append({"id": String(key), "name": String(d.get("name", key)), "cost": int(d.get("cost", 0))})
	return out

## 养老模式目录（供解析器链接「选养老 <模式>」）。
func care_modes_catalog() -> Array:
	var out: Array = []
	for key in disability.CARE_MODES.keys():
		var d: Dictionary = disability.CARE_MODES[key]
		out.append({"id": String(key), "name": String(d.get("name", key)), "cost_per_month": int(d.get("cost_per_month", 0))})
	return out

## 获得残障（事件/叙事驱动；运行时可调用）。
func acquire_disability(d_type: String, source: String, severity: String) -> Dictionary:
	var r: Dictionary = disability.acquire(_disability, d_type, source, severity)
	if bool(r.get("ok", false)):
		_persist_disability()
	return r

## 装配辅具：扣除花费并提升移动能力。
func fit_disability_device(device_key: String) -> Dictionary:
	var r: Dictionary = disability.fit_device(_disability, device_key)
	if not bool(r.get("ok", false)):
		return r
	var cost := int(r.get("cost", 0))
	if cost > 0:
		if economy.cash(account_id()) < cost:
			(_disability["devices"] as Array).erase(device_key)
			return {"ok": false, "reason": "insufficient_funds", "cost": cost}
		economy.add_money(account_id(), -cost, "disability_device:%s" % device_key)
		sync_finances()
	_persist_disability()
	return r

## 手术/康复训练：部分恢复能力（默认 0.3），扣康复花费。
func disability_surgery(amount: float = 0.3) -> Dictionary:
	var cost := 200000
	if economy.cash(account_id()) < cost:
		return {"ok": false, "reason": "insufficient_funds", "cost": cost}
	economy.add_money(account_id(), -cost, "disability_surgery")
	sync_finances()
	var r: Dictionary = disability.surgery_recovery(_disability, amount)
	_persist_disability()
	return r

## 无障碍改造（居所/常去场所）：减少移动惩罚并扣除改造费。
func set_accessible_place(accessible: bool = true) -> Dictionary:
	if accessible:
		var cost := 150000
		if economy.cash(account_id()) < cost:
			return {"ok": false, "reason": "insufficient_funds", "cost": cost}
		economy.add_money(account_id(), -cost, "disability_accessible")
		sync_finances()
	var r: Dictionary = disability.set_accessible(_disability, accessible)
	_persist_disability()
	return r

## 选择养老模式（居家/社区/机构）。
func choose_care_mode(mode: String) -> Dictionary:
	var r: Dictionary = disability.choose_care_mode(_disability, mode)
	if bool(r.get("ok", false)):
		_persist_disability()
	return r

## 结算 months 个月养老：扣除成本并返回心情/寿命修正。
func settle_care(months: float) -> Dictionary:
	var r: Dictionary = disability.care_outcome(_disability, months)
	if not bool(r.get("ok", false)):
		return r
	var cost := int(r.get("cost", 0))
	if cost > 0:
		if economy.cash(account_id()) < cost:
			return {"ok": false, "reason": "insufficient_funds", "cost": cost}
		economy.add_money(account_id(), -cost, "disability_care")
		sync_finances()
	_persist_disability()
	return r

## 临终关怀。
func hospice_care(quality: float = 0.8) -> Dictionary:
	var r: Dictionary = disability.hospice_care(_disability, quality)
	_persist_disability()
	return r

## 抽取一次护工事件（按当前养老模式质量）。
func roll_caregiver_event() -> Dictionary:
	var mode := String(_disability.get("care_mode", ""))
	var cm: Dictionary = disability.CARE_MODES.get(mode, {})
	var quality := float(cm.get("quality", 0.5))
	_care_incident = disability.caregiver_event(quality, {}, rng)
	return _care_incident

## 追责上次护工事件（赔偿 + 吊销资格/刑责）。
func hold_caregiver_accountable() -> Dictionary:
	var r: Dictionary = disability.hold_accountable(_care_incident)
	if bool(r.get("ok", false)):
		var comp := int(r.get("compensation", 0))
		if comp > 0:
			economy.add_money(account_id(), comp, "caregiver_compensation")
			sync_finances()
		_care_incident = {}
	return r

## 建立监护（仅在丧失决策能力时成立）。
func establish_guardianship(guardian_id: String) -> Dictionary:
	var r: Dictionary = disability.establish_guardianship(_disability, guardian_id)
	if bool(r.get("ok", false)):
		_persist_disability()
	return r

## 残障与养老面板数据。
func disability_panel_data() -> Dictionary:
	var conditions: Array = []
	for c in (_disability.get("conditions", []) as Array):
		if not (c is Dictionary):
			continue
		var cd: Dictionary = c
		conditions.append({
			"type": String(disability.TYPE_NAMES.get(String(cd.get("type", "")), cd.get("type", ""))),
			"source": String(disability.SOURCE_NAMES.get(String(cd.get("source", "")), cd.get("source", ""))),
			"severity": String(disability.SEVERITY_NAMES.get(String(cd.get("severity", "")), cd.get("severity", ""))),
		})
	var devices: Array = []
	for key in (_disability.get("devices", []) as Array):
		var dev: Dictionary = disability.DEVICES.get(str(key), {})
		devices.append({"name": String(dev.get("name", key))})
	var mode_key := String(_disability.get("care_mode", ""))
	var mode_def: Dictionary = disability.CARE_MODES.get(mode_key, {})
	return {
		"conditions": conditions,
		"mobility": snappedf(disability.mobility(_disability), 0.01),
		"devices": devices,
		"recovery": snappedf(float(_disability.get("recovery", 0.0)), 0.01),
		"accessible": bool(_disability.get("accessible", false)),
		"retirement_years": snappedf(float(_disability.get("retirement_years", 0.0)), 0.1),
		"care_mode": String(mode_def.get("name", mode_key)),
		"care_quality": snappedf(float(mode_def.get("quality", 0.0)), 0.01),
		"cognitive": disability.has_cognitive_impairment(_disability),
		"decision_capacity": disability.decision_capacity(_disability),
		"will_valid": disability.is_will_valid(_disability),
		"guardian": String(_disability.get("guardian", "")),
		"hospice": bool(_disability.get("hospice", false)),
	}

func _persist_disability() -> void:
	if state == null or not (state.sim_runtime is Dictionary):
		return
	(state.sim_runtime as Dictionary)["disability"] = disability.to_dict(_disability)


# --- 农业与乡土（D22） ---

func farm_state() -> Dictionary:
	return _farm

## 作物目录（供解析器链接「播种 <作物>」）。
func agri_crops_catalog() -> Array:
	var out: Array = []
	for key in agriculture.CROPS.keys():
		var d: Dictionary = agriculture.CROPS[key]
		out.append({"id": String(key), "name": String(d.get("name", key))})
	return out

## 牲畜目录（供解析器链接「养畜 <牲畜>」）。
func agri_livestock_catalog() -> Array:
	var out: Array = []
	for key in agriculture.LIVESTOCK.keys():
		var d: Dictionary = agriculture.LIVESTOCK[key]
		out.append({"id": String(key), "name": String(d.get("name", key))})
	return out

## 取得土地（承包/购买/流转/租赁）。
func acquire_farm_land(area: float, use: String, mode: String, price_per_area: int, opts: Dictionary = {}) -> Dictionary:
	var r: Dictionary = agriculture.acquire_land(_farm, area, use, mode, price_per_area, opts)
	if bool(r.get("ok", false)):
		_persist_farm()
	return r

## 在指定地块播种。
func plant_crop(land_index: int, crop_key: String, opts: Dictionary = {}) -> Dictionary:
	var r: Dictionary = agriculture.plant(_farm, land_index, crop_key, opts)
	if bool(r.get("ok", false)):
		_persist_farm()
	return r

## 推进作物生长（按天）。
func grow_farm(days: float) -> Dictionary:
	var r: Dictionary = agriculture.grow(_farm, days)
	return r

## 收割指定地块。
func harvest_crop(plot_index: int, opts: Dictionary = {}) -> Dictionary:
	var r: Dictionary = agriculture.harvest(_farm, plot_index, opts)
	if bool(r.get("ok", false)):
		_persist_farm()
	return r

## 增加牲畜存栏。
func add_farm_livestock(animal: String, count: int) -> Dictionary:
	var r: Dictionary = agriculture.add_livestock(_farm, animal, count)
	if bool(r.get("ok", false)):
		_persist_farm()
	return r

## 喂养牲畜。
func feed_farm_livestock(days: float, feed_available: float) -> Dictionary:
	var r: Dictionary = agriculture.feed_livestock(_farm, days, feed_available)
	_persist_farm()
	return r

## 售卖农产品/牲畜。
func sell_produce(item: String, amount: float, channel: String = "market", opts: Dictionary = {}) -> Dictionary:
	var r: Dictionary = agriculture.sell(_farm, item, amount, channel, opts)
	if bool(r.get("ok", false)):
		_persist_farm()
	return r

## 申领农业补贴。
func apply_farm_subsidy(amount: int) -> Dictionary:
	var r: Dictionary = agriculture.apply_subsidy(_farm, amount)
	_persist_farm()
	return r

## 农业与乡土面板数据。
func farm_panel_data() -> Dictionary:
	var lands: Array = []
	for l in (_farm.get("land", []) as Array):
		if not (l is Dictionary):
			continue
		var ld: Dictionary = l
		lands.append({
			"id": String(ld.get("id", "")),
			"area": snappedf(float(ld.get("area", 0.0)), 0.1),
			"use": String(agriculture.LAND_MODE_NAMES.get(String(ld.get("mode", "")), ld.get("mode", ""))),
			"fertility": snappedf(float(ld.get("fertility", 0.0)), 0.01),
			"value": int(ld.get("asset_value", 0)),
		})
	var plots: Array = []
	for p in (_farm.get("plots", []) as Array):
		if not (p is Dictionary):
			continue
		var pd: Dictionary = p
		var crop: Dictionary = agriculture.crop_def(String(pd.get("crop", "")))
		plots.append({
			"name": String(crop.get("name", pd.get("crop", ""))),
			"stage": String(pd.get("stage", "")),
			"elapsed": snappedf(float(pd.get("elapsed", 0.0)), 0.1),
			"growth_days": snappedf(float(pd.get("growth_days", 0.0)), 0.1),
		})
	var livestock: Array = []
	for a in (_farm.get("livestock", []) as Array):
		if not (a is Dictionary):
			continue
		var ad: Dictionary = a
		var def: Dictionary = agriculture.livestock_def(String(ad.get("animal", "")))
		livestock.append({"name": String(def.get("name", ad.get("animal", ""))), "count": int(ad.get("count", 0))})
	var storage: Dictionary = _farm.get("storage", {})
	var inventory: Array = []
	for item in storage.keys():
		var qty := float(storage[item])
		if qty <= 0.0:
			continue
		var cd: Dictionary = agriculture.crop_def(String(item))
		inventory.append({"name": String(cd.get("name", item)), "count": snappedf(qty, 0.1)})
	return {
		"money": int(_farm.get("money", 0)),
		"land_value": agriculture.land_asset_value(_farm),
		"lands": lands,
		"plots": plots,
		"livestock": livestock,
		"inventory": inventory,
		"subsidy": snappedf(float(_farm.get("subsidy", 0.0)), 1.0),
		"year_income": int(_farm.get("year_income", 0)),
		"coop": String(_farm.get("coop", "")),
	}

## 农场按日推进：作物生长并仓储损耗。
func _advance_farm(before_minutes: int, after_minutes: int) -> void:
	var before_day: int = before_minutes / MINUTES_PER_DAY
	var after_day: int = after_minutes / MINUTES_PER_DAY
	if after_day <= before_day:
		return
	var days: float = float(after_day - before_day)
	agriculture.grow(_farm, days)
	agriculture.storage_spoil(_farm, days)

func _persist_farm() -> void:
	if state == null or not (state.sim_runtime is Dictionary):
		return
	(state.sim_runtime as Dictionary)["farm"] = agriculture.to_dict(_farm)


# --- 数字生活与黑客（D23） ---

## 玩家技能等级（按技能 id），用于数字/黑客判定。
func _skill_level(id: String) -> int:
	return skills.level_of(player().get("skills", []), id)

func digital_state() -> Dictionary:
	return _identity

## 内容平台目录（供解析器链接「发布内容 <平台>」）。
func digital_platforms_catalog() -> Array:
	var out: Array = []
	for key in digital.CONTENT_PLATFORMS.keys():
		var d: Dictionary = digital.CONTENT_PLATFORMS[key]
		out.append({"id": String(key), "name": String(d.get("name", key))})
	return out

## 黑客目标目录（供解析器链接「黑客攻击 <目标>」）。
func digital_hack_targets_catalog() -> Array:
	var out: Array = []
	for key in digital.HACK_TARGETS.keys():
		var d: Dictionary = digital.HACK_TARGETS[key]
		out.append({"id": String(key), "name": String(d.get("name", key))})
	return out

## 网络安全职业目录（合法方向）。
func digital_security_jobs_catalog() -> Array:
	var out: Array = []
	for key in digital.SECURITY_JOBS.keys():
		var d: Dictionary = digital.SECURITY_JOBS[key]
		out.append({"id": String(key), "name": String(d.get("name", key))})
	return out

## 开通平台账号。
func open_digital_account(platform: String) -> Dictionary:
	if platform.strip_edges().is_empty():
		return {"ok": false, "reason": "unknown_platform"}
	var r: Dictionary = digital.create_account(_identity, platform, {"real_name": bool(_identity.get("real_name_verified", false))})
	_persist_digital()
	return r

## 实名认证。
func verify_digital_identity() -> Dictionary:
	var r: Dictionary = digital.verify_real_name(_identity, true)
	_persist_digital()
	return r

## 增加数字资产（账号/虚拟物品/加密钱包）。
func add_digital_asset(asset_type: String, value: int) -> Dictionary:
	var r: Dictionary = digital.add_asset(_identity, asset_type, value)
	_persist_digital()
	return r

## 从事网络安全工作（合法方向，无法律风险）。
func digital_security_work(kind: String) -> Dictionary:
	var skill: float = float(_skill_level("hacking")) * 5.0
	var r: Dictionary = digital.security_job(kind, skill)
	if bool(r.get("ok", false)) and int(r.get("income", 0)) > 0:
		economy.add_money(account_id(), int(r["income"]), "security_job")
	_persist_digital()
	return r

## 实施未授权入侵（游戏内虚构抽象判定）。
func digital_hack(target: String) -> Dictionary:
	var skill: float = float(_skill_level("hacking")) * 5.0
	var r: Dictionary = digital.hack(target, skill)
	if bool(r.get("ok", false)) and int(r.get("gain", 0)) > 0:
		economy.add_money(account_id(), int(r["gain"]), "hack")
	_persist_digital()
	return r

## 发布内容（直播/短视频），首次自动开通创作者身份。
func publish_digital_content(platform: String = "short_video") -> Dictionary:
	if _creator.is_empty() or String(_creator.get("platform", "")) != platform:
		_creator = digital.new_creator("player", platform)
	var r: Dictionary = digital.publish_content(_creator)
	if bool(r.get("ok", false)) and int(r.get("income", 0)) > 0:
		economy.add_money(account_id(), int(r["income"]), "content_income")
	_persist_digital()
	return r

## 上网时长结算网络成瘾。
func digital_addiction(hours: float) -> Dictionary:
	var r: Dictionary = digital.internet_addiction(hours)
	_identity["addiction"] = float(r.get("addiction", 0.0))
	_persist_digital()
	return r

## 数字与平台面板数据。
func digital_panel_data() -> Dictionary:
	var accounts: Array = []
	var acct: Dictionary = _identity.get("accounts", {})
	for key in acct.keys():
		var a: Dictionary = acct[key]
		accounts.append({"platform": String(key), "real_name": bool(a.get("real_name", false)), "privacy": snappedf(float(a.get("privacy", 0.0)), 0.01)})
	var assets: Array = []
	for a in (_identity.get("assets", []) as Array):
		if a is Dictionary:
			var ad: Dictionary = a
			assets.append({"type": String(ad.get("type", "")), "value": int(ad.get("value", 0)), "stolen": bool(ad.get("stolen", false))})
	var leaked := 0
	var total := 0
	for d in (_identity.get("data", []) as Array):
		if d is Dictionary:
			total += 1
			if bool((d as Dictionary).get("leaked", false)):
				leaked += 1
	return {
		"real_name_verified": bool(_identity.get("real_name_verified", false)),
		"privacy": snappedf(float(_identity.get("privacy", 0.0)), 0.01),
		"exposure_heat": snappedf(float(_identity.get("exposure_heat", 0.0)), 0.1),
		"addiction": snappedf(float(_identity.get("addiction", 0.0)), 0.01),
		"accounts": accounts,
		"assets": assets,
		"data_total": total,
		"data_leaked": leaked,
		"creator": _creator.duplicate(true),
		"esports": _esports.duplicate(true),
	}

func _persist_digital() -> void:
	if state == null or not (state.sim_runtime is Dictionary):
		return
	(state.sim_runtime as Dictionary)["digital"] = {
		"identity": digital.to_dict(_identity),
		"creator": _creator.duplicate(true),
		"esports": _esports.duplicate(true),
	}


# --- 后期科技（D24） ---

func late_tech_state() -> Dictionary:
	return _late_tech

## 科技阶段目录。
func late_tech_stages_catalog() -> Array:
	var out: Array = []
	for key in late_tech.STAGES:
		out.append({"id": String(key), "name": String(late_tech.stage_def(String(key)).get("name", key))})
	return out

## 科技职业目录（按阶段门控，含技能门槛与薪资）。
func late_tech_careers_catalog() -> Array:
	var out: Array = []
	for key in late_tech.CAREERS.keys():
		var d: Dictionary = late_tech.CAREERS[key]
		out.append({"id": String(key), "name": String(d.get("name", key))})
	return out

## 高风险科技任务目录。
func late_tech_missions_catalog() -> Array:
	var out: Array = []
	for key in late_tech.MISSIONS.keys():
		var d: Dictionary = late_tech.MISSIONS[key]
		out.append({"id": String(key), "name": String(d.get("name", key))})
	return out

## 解锁下一科技阶段（严格顺序）。
func unlock_late_tech_stage() -> Dictionary:
	var idx: int = int(_late_tech.get("stage_index", 0))
	if idx + 1 >= late_tech.stage_count():
		return {"ok": false, "reason": "max_stage"}
	var r: Dictionary = late_tech.unlock_stage(_late_tech, idx + 1)
	if bool(r.get("ok", false)):
		_persist_late_tech()
	return r

## 应聘科技职业。技能等级取该职业所要求技能树的当前等级。
func apply_late_tech_career(career_key: String) -> Dictionary:
	if not late_tech.CAREERS.has(career_key):
		return {"ok": false, "reason": "unknown_career"}
	var def: Dictionary = late_tech.CAREERS[career_key]
	var skill_level: int = _skill_level(String(def.get("skill", "")))
	var r: Dictionary = late_tech.apply_for_career(_late_tech, career_key, skill_level)
	_persist_late_tech()
	return r

## 执行高风险科技任务。技能等级取任务环境对应的技能树等级（用最高职业技能近似）。
func risk_late_tech_mission(mission_key: String) -> Dictionary:
	if not late_tech.MISSIONS.has(mission_key):
		return {"ok": false, "reason": "unknown_mission"}
	var skill_level: int = _late_tech_best_skill()
	var r: Dictionary = late_tech.risk_mission(_late_tech, mission_key, skill_level)
	if bool(r.get("ok", false)) and int(r.get("reward", 0)) > 0:
		economy.add_money(account_id(), int(r["reward"]), "late_tech_mission")
	_persist_late_tech()
	return r

## 生物科技延寿投资。
func invest_biotech_lifespan(investment: float) -> Dictionary:
	var r: Dictionary = late_tech.biotech_lifespan(_late_tech, investment)
	_persist_late_tech()
	return r

## 取职业路径中的最高技能等级（近似玩家科技素养）。
func _late_tech_best_skill() -> int:
	var best: int = 0
	for key in late_tech.CAREERS.keys():
		var def: Dictionary = late_tech.CAREERS[key]
		var lv: int = _skill_level(String(def.get("skill", "")))
		best = maxi(best, lv)
	return best

## 后期科技面板数据。
func late_tech_panel_data() -> Dictionary:
	var stage_key: String = late_tech.current_stage(_late_tech)
	var def: Dictionary = late_tech.stage_def(stage_key)
	var careers: Array = []
	for key in late_tech.CAREERS.keys():
		var cd: Dictionary = late_tech.CAREERS[key]
		careers.append({
			"id": String(key), "name": String(cd.get("name", key)),
			"stage": String(cd.get("stage", "")),
			"unlocked": late_tech.career_unlocked(_late_tech, String(key)),
			"min_level": int(cd.get("min_level", 0)),
			"salary": int(cd.get("salary", 0)),
		})
	var missions: Array = []
	for key in late_tech.MISSIONS.keys():
		var md: Dictionary = late_tech.MISSIONS[key]
		missions.append({
			"id": String(key), "name": String(md.get("name", key)),
			"stage": String(md.get("stage", "")),
			"min_skill": int(md.get("min_skill", 0)),
			"reward": int(md.get("reward", 0)),
		})
	return {
		"stage": stage_key,
		"stage_name": String(def.get("name", stage_key)),
		"stage_index": int(_late_tech.get("stage_index", 0)),
		"unlocked_stages": (_late_tech.get("unlocked_stages", []) as Array).duplicate(),
		"jobs": (def.get("jobs", []) as Array).duplicate(),
		"equipment": (def.get("equipment", []) as Array).duplicate(),
		"places": (def.get("places", []) as Array).duplicate(),
		"lifespan_bonus": snappedf(float(_late_tech.get("lifespan_bonus", 0.0)), 0.1),
		"unemployment_rate": snappedf(float(_late_tech.get("unemployment_rate", 0.0)), 0.001),
		"careers": careers,
		"missions": missions,
	}

func _persist_late_tech() -> void:
	if state == null or not (state.sim_runtime is Dictionary):
		return
	(state.sim_runtime as Dictionary)["late_tech"] = late_tech.to_dict(_late_tech)


# --- 知识产权与媒体（D25） ---

func ip_media_state() -> Dictionary:
	return {"ips": _ips, "outlets": _outlets}

func ip_types_catalog() -> Array:
	var out: Array = []
	for key in ip_media.IP_TYPES.keys():
		var d: Dictionary = ip_media.IP_TYPES[key]
		out.append({"id": String(key), "name": String(d.get("name", key))})
	return out

func media_types_catalog() -> Array:
	var out: Array = []
	for key in ip_media.MEDIA_TYPES.keys():
		var d: Dictionary = ip_media.MEDIA_TYPES[key]
		out.append({"id": String(key), "name": String(d.get("name", key))})
	return out

## 登记知识产权：扣缴登记费，登记后入档。title 缺省用类型名。
func register_ip_asset(ip_type: String, title: String = "") -> Dictionary:
	if not ip_media.IP_TYPES.has(ip_type):
		return {"ok": false, "reason": "unknown_ip_type"}
	var def: Dictionary = ip_media.IP_TYPES[ip_type]
	var fee: int = int(def.get("registration_fee", 0))
	if int(economy.cash(account_id())) < fee:
		return {"ok": false, "reason": "insufficient_funds"}
	var name: String = title
	if name.strip_edges() == "":
		name = "%s%d" % [String(def.get("name", ip_type)), _ips.size() + 1]
	var r: Dictionary = ip_media.register_ip(ip_type, "player", name, {"created_minute": now_minutes()})
	if bool(r.get("ok", false)):
		_ips.append(r["ip"])
		economy.add_money(account_id(), -fee, "ip_registration")
		_persist_ip_media()
	return {"ok": true, "ip": r.get("ip", {}), "fee": fee}

## 授权知识产权：许可费入账。
func license_ip_asset(ip_id: String, deal_size: float, exclusive: bool = false) -> Dictionary:
	var ip: Dictionary = _find_ip(ip_id)
	if ip.is_empty():
		return {"ok": false, "reason": "unknown_ip"}
	var r: Dictionary = ip_media.license_ip(ip, "外部被许可方", deal_size, {"exclusive": exclusive, "minute": now_minutes()})
	if bool(r.get("ok", false)):
		economy.add_money(account_id(), int(r.get("fee", 0)), "ip_license")
		_persist_ip_media()
	return r

## 转让知识产权：成交价入账并变更所有权。
func transfer_ip_asset(ip_id: String, price: int) -> Dictionary:
	var ip: Dictionary = _find_ip(ip_id)
	if ip.is_empty():
		return {"ok": false, "reason": "unknown_ip"}
	var r: Dictionary = ip_media.transfer_ip(ip, "外部买家", price)
	economy.add_money(account_id(), int(r.get("price", 0)), "ip_transfer")
	_persist_ip_media()
	return r

## 质押知识产权：融资额入账。
func pledge_ip_asset(ip_id: String, amount: int) -> Dictionary:
	var ip: Dictionary = _find_ip(ip_id)
	if ip.is_empty():
		return {"ok": false, "reason": "unknown_ip"}
	var r: Dictionary = ip_media.pledge_ip(ip, amount)
	if bool(r.get("ok", false)):
		economy.add_money(account_id(), int(r.get("amount", 0)), "ip_pledge")
		_persist_ip_media()
	return r

## 知识产权维权诉讼：胜诉赔偿入账。
func sue_ip_infringer(ip_id: String, opts: Dictionary = {}) -> Dictionary:
	var ip: Dictionary = _find_ip(ip_id)
	if ip.is_empty():
		return {"ok": false, "reason": "unknown_ip"}
	var r: Dictionary = ip_media.file_lawsuit(ip, opts)
	if bool(r.get("win", false)) and int(r.get("compensation", 0)) > 0:
		economy.add_money(account_id(), int(r["compensation"]), "ip_compensation")
	_persist_ip_media()
	return r

## 开办媒体机构。
func register_media_outlet(media_type: String, name: String = "") -> Dictionary:
	if not ip_media.MEDIA_TYPES.has(media_type):
		return {"ok": false, "reason": "unknown_media_type"}
	var opts: Dictionary = {"reputation": 0.5, "cash": 0}
	if name.strip_edges() != "":
		opts["name"] = name
	var r: Dictionary = ip_media.new_media_outlet(media_type, opts)
	if bool(r.get("ok", false)):
		_outlets.append(r["outlet"])
		_persist_ip_media()
	return r

## 发行作品：票房/销量入账并影响机构声誉。
func release_media_work(outlet_id: String, title: String, quality: float = 0.5, scale: float = 10000000.0) -> Dictionary:
	var outlet: Dictionary = _find_outlet(outlet_id)
	if outlet.is_empty():
		return {"ok": false, "reason": "unknown_outlet"}
	var work: Dictionary = {"title": title, "quality": clampf(quality, 0.0, 1.0)}
	var r: Dictionary = ip_media.release_work(outlet, work, {"scale": scale})
	if bool(r.get("ok", false)) and int(r.get("revenue", 0)) > 0:
		economy.add_money(account_id(), int(r["revenue"]), "media_revenue")
		_persist_ip_media()
	return r

func _find_ip(ip_id: String) -> Dictionary:
	for ip in _ips:
		if ip is Dictionary and String((ip as Dictionary).get("id", "")) == ip_id:
			return ip
	return {}

func _find_outlet(outlet_id: String) -> Dictionary:
	for o in _outlets:
		if o is Dictionary and String((o as Dictionary).get("id", "")) == outlet_id:
			return o
	return {}

func ip_media_panel_data() -> Dictionary:
	var ips: Array = []
	for ip in _ips:
		if ip is Dictionary:
			var d: Dictionary = ip
			ips.append({
				"id": String(d.get("id", "")),
				"type": String(d.get("type", "")),
				"type_name": String(ip_media.IP_TYPES.get(String(d.get("type", "")), {}).get("name", d.get("type", ""))),
				"title": String(d.get("title", "")),
				"status": String(d.get("status", "")),
				"licenses": (d.get("licenses", []) as Array).size(),
				"pledged": bool(d.get("pledged", false)),
				"public_domain": bool(d.get("public_domain", false)),
			})
	var outlets: Array = []
	for o in _outlets:
		if o is Dictionary:
			var od: Dictionary = o
			outlets.append({
				"id": String(od.get("id", "")),
				"name": String(od.get("name", "")),
				"type_name": String(ip_media.MEDIA_TYPES.get(String(od.get("type", "")), {}).get("name", od.get("type", ""))),
				"reputation": snappedf(float(od.get("reputation", 0.0)), 0.001),
				"cash": int(od.get("cash", 0)),
				"works": (od.get("works", []) as Array).size(),
			})
	return {"ips": ips, "outlets": outlets}

func _persist_ip_media() -> void:
	if state == null or not (state.sim_runtime is Dictionary):
		return
	(state.sim_runtime as Dictionary)["ip_media"] = {
		"ips": _ips.duplicate(true),
		"outlets": _outlets.duplicate(true),
	}


# --- 制造业与供应链（D26） ---

func manufacturing_state() -> Dictionary:
	return _factory

func mfg_roles_catalog() -> Array:
	var out: Array = []
	for key in manufacturing.ROLES.keys():
		var d: Dictionary = manufacturing.ROLES[key]
		out.append({"id": String(key), "name": String(d.get("name", key))})
	return out

func mfg_modes_catalog() -> Array:
	var out: Array = []
	for key in manufacturing.MODES.keys():
		var d: Dictionary = manufacturing.MODES[key]
		out.append({"id": String(key), "name": String(d.get("name", key))})
	return out

func mfg_recipes_catalog() -> Array:
	var out: Array = []
	for key in manufacturing.RECIPES.keys():
		var d: Dictionary = manufacturing.RECIPES[key]
		out.append({"id": String(key), "name": String(d.get("name", key))})
	return out

func mfg_materials_catalog() -> Array:
	const MATERIAL_NAMES: Dictionary = {"steel": "钢材", "resin": "树脂", "copper": "铜材"}
	var seen: Dictionary = {}
	var out: Array = []
	for key in manufacturing.RECIPES.keys():
		for mat in manufacturing.input_materials(String(key)):
			var m := String(mat)
			if seen.has(m):
				continue
			seen[m] = true
			out.append({"id": m, "name": String(MATERIAL_NAMES.get(m, m))})
	return out

## 开办工厂：授予所选经营模式资质并注入初始营运资金（工厂为独立资金池）。
func found_factory(mode: String = "own_factory") -> Dictionary:
	if not manufacturing.MODES.has(mode):
		return {"ok": false, "reason": "unknown_mfg_mode"}
	_factory = manufacturing.new_factory(10000000, {"mode": "own_factory"})
	manufacturing.grant_qualification(_factory, String((manufacturing.MODES[mode] as Dictionary)["qualification"]))
	var setr: Dictionary = manufacturing.set_mode(_factory, mode)
	if not bool(setr.get("ok", false)):
		# 资金/资质不足时回落到开厂模式。
		manufacturing.grant_qualification(_factory, "factory_license")
		manufacturing.set_mode(_factory, "own_factory")
	_persist_manufacturing()
	return {"ok": true, "mode": String(_factory.get("mode", "own_factory"))}

func mfg_hire(role: String, count: int) -> Dictionary:
	if _factory.is_empty():
		return {"ok": false, "reason": "no_factory"}
	var r: Dictionary = manufacturing.hire(_factory, role, count)
	if bool(r.get("ok", false)):
		_persist_manufacturing()
	return r

func mfg_fire(role: String, count: int) -> Dictionary:
	if _factory.is_empty():
		return {"ok": false, "reason": "no_factory"}
	var r: Dictionary = manufacturing.fire(_factory, role, count)
	if bool(r.get("ok", false)):
		_persist_manufacturing()
	return r

## 添加覆盖某原料的供应商。
func mfg_add_supplier(material: String) -> Dictionary:
	if _factory.is_empty():
		return {"ok": false, "reason": "no_factory"}
	var r: Dictionary = manufacturing.add_supplier(_factory, {
		"name": "%s 供应商" % material, "materials": [material], "reliability": 0.9, "price_factor": 1.0,
	})
	_persist_manufacturing()
	return r

func mfg_purchase(material: String, qty: float) -> Dictionary:
	if _factory.is_empty():
		return {"ok": false, "reason": "no_factory"}
	# 首次采购该原料时惰性建立供应商，保证「采购原料」开箱可用。
	var covered: bool = false
	for s in (_factory.get("suppliers", []) as Array):
		if (s as Dictionary).get("materials", []).has(material):
			covered = true
			break
	if not covered:
		mfg_add_supplier(material)
	var r: Dictionary = manufacturing.purchase(_factory, material, qty, {"base_unit_cost": 1000})
	if bool(r.get("ok", false)):
		_persist_manufacturing()
	return r

func mfg_produce(recipe_key: String, batches: float = 1.0) -> Dictionary:
	if _factory.is_empty():
		return {"ok": false, "reason": "no_factory"}
	var r: Dictionary = manufacturing.produce(_factory, recipe_key, batches)
	if bool(r.get("ok", false)):
		_persist_manufacturing()
	return r

## 接单：价取配方基准价。
func mfg_accept_order(recipe_key: String, quantity: float) -> Dictionary:
	if _factory.is_empty():
		return {"ok": false, "reason": "no_factory"}
	var def: Dictionary = manufacturing.recipe_def(recipe_key)
	if def.is_empty():
		return {"ok": false, "reason": "unknown_recipe"}
	var r: Dictionary = manufacturing.accept_order(_factory, recipe_key, quantity, int(def.get("price", 0)))
	if bool(r.get("ok", false)):
		_persist_manufacturing()
	return r

func mfg_deliver_order(index: int = 0) -> Dictionary:
	if _factory.is_empty():
		return {"ok": false, "reason": "no_factory"}
	var r: Dictionary = manufacturing.deliver_order(_factory, index)
	if bool(r.get("ok", false)):
		_persist_manufacturing()
	return r

## 切换/升级经营模式。
func mfg_set_mode(mode: String) -> Dictionary:
	if _factory.is_empty():
		return {"ok": false, "reason": "no_factory"}
	var r: Dictionary = manufacturing.upgrade_mode(_factory, mode)
	if not bool(r.get("ok", false)):
		r = manufacturing.set_mode(_factory, mode)
	if bool(r.get("ok", false)):
		_persist_manufacturing()
	elif String(r.get("reason", "")) == "unknown_mode":
		r["reason"] = "unknown_mfg_mode"
	return r

## 制造业面板数据：模式/产能/人员/原料/成品/订单/风险。
func factory_panel_data() -> Dictionary:
	if _factory.is_empty():
		return {}
	var staff: Array = []
	for key in manufacturing.ROLES.keys():
		var n: int = manufacturing.staff_count(_factory, String(key))
		if n > 0:
			staff.append({"id": String(key), "name": String((manufacturing.ROLES[key] as Dictionary).get("name", key)), "count": n})
	var materials: Array = []
	var max_factory := _factory
	for mat in (max_factory.get("materials", {}) as Dictionary).keys():
		var entry: Dictionary = (max_factory["materials"] as Dictionary)[mat]
		if float(entry.get("qty", 0.0)) > 0.0:
			materials.append({"id": String(mat), "qty": snappedf(float(entry.get("qty", 0.0)), 0.1)})
	var products: Array = []
	for rkey in (max_factory.get("products", {}) as Dictionary).keys():
		var qty: float = float((max_factory["products"] as Dictionary)[rkey])
		if qty > 0.0:
			products.append({"id": String(rkey), "name": String(manufacturing.recipe_def(String(rkey)).get("name", rkey)), "qty": snappedf(qty, 0.1)})
	var orders: Array = []
	var idx: int = 0
	for o in (max_factory.get("orders", []) as Array):
		if o is Dictionary:
			var od: Dictionary = o
			orders.append({
				"index": idx, "name": String(manufacturing.recipe_def(String(od.get("recipe", ""))).get("name", od.get("recipe", ""))),
				"quantity": snappedf(float(od.get("quantity", 0.0)), 0.1),
				"delivered": snappedf(float(od.get("delivered", 0.0)), 0.1),
				"fulfilled": bool(od.get("fulfilled", false)),
			})
			idx += 1
	var cap: Dictionary = {}
	var recipe_keys: Array = manufacturing.recipe_keys()
	if not recipe_keys.is_empty():
		cap = manufacturing.capacity(_factory, String(recipe_keys[0]))
	return {
		"money": int(max_factory.get("money", 0)),
		"mode": String(max_factory.get("mode", "")),
		"mode_name": String(manufacturing.MODES.get(String(max_factory.get("mode", "")), {}).get("name", max_factory.get("mode", ""))),
		"headcount": manufacturing.headcount(_factory),
		"labor_factor": snappedf(manufacturing.labor_factor(_factory), 0.01),
		"efficiency": snappedf(manufacturing.effective_efficiency(_factory), 0.01),
		"bottleneck": String(cap.get("bottleneck", "")),
		"effective_capacity": snappedf(float(cap.get("effective_capacity", 0.0)), 0.1),
		"safety": snappedf(float(max_factory.get("safety", 0.0)), 0.01),
		"automation": snappedf(float(max_factory.get("automation", 0.0)), 0.01),
		"active_disruptions": manufacturing.active_disruptions(_factory),
		"staff": staff,
		"materials": materials,
		"products": products,
		"orders": orders,
	}

func _persist_manufacturing() -> void:
	if state == null or not (state.sim_runtime is Dictionary):
		return
	(state.sim_runtime as Dictionary)["manufacturing"] = manufacturing.to_dict(_factory)


# --- 国际贸易、海关与物流（D27） ---

func trade_state() -> Dictionary:
	return {"shipments": _shipments}

func trade_transport_modes_catalog() -> Array:
	var out: Array = []
	for key in trade.TRANSPORT_MODES.keys():
		out.append({"id": String(key), "name": String((trade.TRANSPORT_MODES[key] as Dictionary).get("name", key))})
	return out

func trade_incoterms_catalog() -> Array:
	var out: Array = []
	for code in trade.INCOTERMS:
		out.append({"id": String(code), "name": String(code)})
	return out

func trade_settlements_catalog() -> Array:
	var out: Array = []
	for key in trade.SETTLEMENTS.keys():
		out.append({"id": String(key), "name": String((trade.SETTLEMENTS[key] as Dictionary).get("name", key))})
	return out

func trade_services_catalog() -> Array:
	const NAMES: Dictionary = {"freight_forwarder": "货代", "customs_broker": "报关行", "overseas_warehouse": "海外仓", "cross_border_ecommerce": "跨境电商"}
	var out: Array = []
	for key in trade.SERVICES:
		out.append({"id": String(key), "name": String(NAMES.get(String(key), key))})
	return out

func trade_barriers_catalog() -> Array:
	const NAMES: Dictionary = {"tariff": "加征关税", "quota": "配额", "anti_dumping": "反倾销", "origin": "原产地"}
	var out: Array = []
	for key in trade.BARRIERS:
		out.append({"id": String(key), "name": String(NAMES.get(String(key), key))})
	return out

## 新建出口单据：以货值建单，商品名落单据，返回序号。
func export_shipment(goods: String, value: int) -> Dictionary:
	var s: Dictionary = trade.new_shipment({"id": "shipment_%d" % _shipments.size(), "goods_value": maxi(0, value)})
	s["goods"] = goods if goods != "" else "货物"
	_shipments.append(s)
	_persist_trade()
	return {"ok": true, "index": _shipments.size() - 1, "goods": String(s["goods"]), "goods_value": int(s["goods_value"])}

## 规划运输：报价并写入单据运费（海运/空运/铁路/快递/管道，超载拒绝）。
func plan_trade_transport(index: int, mode: String) -> Dictionary:
	var s: Dictionary = _shipment_at(index)
	if s.is_empty():
		return {"ok": false, "reason": "no_shipment"}
	var quote: Dictionary = trade.estimate_freight(mode, float(s.get("quantity_ton", 1.0)))
	if not bool(quote.get("ok", false)):
		return {"ok": false, "reason": String(quote.get("reason", "over_capacity"))}
	s["transport"] = mode
	s["freight"] = int(quote.get("freight", 0))
	s["transit_days"] = float(quote.get("days", 0.0))
	_persist_trade()
	return {"ok": true, "mode": mode, "freight": int(s["freight"]), "days": float(s["transit_days"])}

## 签订外贸合同：写入贸易术语与结算方式，进入签约阶段。
func sign_trade_contract(index: int, incoterm: String, settlement: String = "letter_of_credit") -> Dictionary:
	var s: Dictionary = _shipment_at(index)
	if s.is_empty():
		return {"ok": false, "reason": "no_shipment"}
	if not trade.INCOTERMS.has(incoterm):
		return {"ok": false, "reason": "unknown_incoterm"}
	if not trade.SETTLEMENTS.has(settlement):
		settlement = "letter_of_credit"
	s["incoterm"] = incoterm
	s["settlement"] = settlement
	s["stage"] = "contract"
	(s["history"] as Array).append("contract")
	_persist_trade()
	return {"ok": true, "incoterm": incoterm, "settlement": settlement, "settlement_name": String((trade.SETTLEMENTS[settlement] as Dictionary).get("name", settlement))}

## 报关并落税：关税+增值税从玩家现金扣除，进入报关阶段。
func declare_shipment(index: int) -> Dictionary:
	var s: Dictionary = _shipment_at(index)
	if s.is_empty():
		return {"ok": false, "reason": "no_shipment"}
	var duties: Dictionary = trade.declare_customs(s)
	var tax: int = int(duties.get("total_tax", 0))
	if economy.cash(account_id()) < tax:
		return {"ok": false, "reason": "insufficient_funds", "total_tax": tax}
	economy.add_money(account_id(), -tax, "customs_tax")
	_persist_trade()
	return {"ok": true, "tariff": int(duties.get("tariff", 0)), "vat": int(duties.get("vat", 0)), "total_tax": tax, "landed_cost": int(duties.get("landed_cost", 0))}

## 清关：进入清关阶段。
func clear_shipment(index: int) -> Dictionary:
	var s: Dictionary = _shipment_at(index)
	if s.is_empty():
		return {"ok": false, "reason": "no_shipment"}
	var r: Dictionary = trade.clear_customs(s)
	_persist_trade()
	return r

## 发货交付：货值作为出口收入入账并进入交付阶段。
func deliver_shipment(index: int) -> Dictionary:
	var s: Dictionary = _shipment_at(index)
	if s.is_empty():
		return {"ok": false, "reason": "no_shipment"}
	var r: Dictionary = trade.deliver(s)
	var revenue: int = maxi(0, int(s.get("goods_value", 0)))
	economy.add_money(account_id(), revenue, "export_revenue")
	_persist_trade()
	return {"ok": true, "revenue": revenue, "stage": String(r.get("stage", "delivery"))}

## 结汇：按结算方式计手续费，从玩家现金扣除并标记已结汇。
func settle_shipment(index: int) -> Dictionary:
	var s: Dictionary = _shipment_at(index)
	if s.is_empty():
		return {"ok": false, "reason": "no_shipment"}
	var method: String = String(s.get("settlement", "letter_of_credit"))
	if method == "":
		method = "letter_of_credit"
	var fee_r: Dictionary = trade.settlement_fee(int(s.get("goods_value", 0)), method)
	var fee: int = int(fee_r.get("fee", 0))
	if economy.cash(account_id()) < fee:
		return {"ok": false, "reason": "insufficient_funds", "fee": fee}
	economy.add_money(account_id(), -fee, "settlement_fee")
	s["settled"] = true
	_persist_trade()
	return {"ok": true, "fee": fee, "method": method, "method_name": String((trade.SETTLEMENTS[method] as Dictionary).get("name", method))}

## 外贸面板数据：单据、阶段、运输、税费、结算。
func trade_panel_data() -> Dictionary:
	if _shipments.is_empty():
		return {}
	var rows: Array = []
	var idx: int = 0
	for s in _shipments:
		var sd: Dictionary = s
		var stage: String = String(sd.get("stage", "inquiry"))
		rows.append({
			"index": idx,
			"goods": String(sd.get("goods", "货物")),
			"goods_value": int(sd.get("goods_value", 0)),
			"stage": stage,
			"stage_name": String(trade.STAGE_NAMES.get(stage, stage)),
			"incoterm": String(sd.get("incoterm", "")),
			"transport": String(sd.get("transport", "")),
			"freight": int(sd.get("freight", 0)),
			"settled": bool(sd.get("settled", false)),
		})
		idx += 1
	return {"shipments": rows}

func _shipment_at(index: int) -> Dictionary:
	var i: int = index
	if i < 0:
		i = _shipments.size() - 1
	if i < 0 or i >= _shipments.size():
		return {}
	return _shipments[i]

func _persist_trade() -> void:
	if state == null or not (state.sim_runtime is Dictionary):
		return
	(state.sim_runtime as Dictionary)["trade"] = {"shipments": _shipments.duplicate(true)}


# --- D28 矿业、能源与资源 ---

func mining_state() -> Dictionary:
	return {"mine": _mine, "energy": _energy}

func mining_minerals_catalog() -> Array:
	var out: Array = []
	for key in mining_energy.mineral_keys():
		var d: Dictionary = mining_energy.mineral_def(String(key))
		out.append({"id": String(key), "name": String(d.get("name", key))})
	return out

func mining_energy_catalog() -> Array:
	var out: Array = []
	for key in mining_energy.energy_keys():
		var d: Dictionary = mining_energy.energy_def(String(key))
		out.append({"id": String(key), "name": String(d.get("name", key))})
	return out

func mining_energy_kinds_catalog() -> Array:
	var out: Array = []
	for key in mining_energy.NEW_ENERGY_KINDS:
		out.append({"id": String(key), "name": String(mining_energy.NEW_ENERGY_NAMES.get(String(key), key))})
	return out

## 开办矿场：独立资金池，预置矿权资质（仍需另行取得矿权）。
func open_mine(mineral: String, capital: int = 100000000) -> Dictionary:
	var m: Dictionary = mining_energy.new_mine(mineral, maxi(0, capital), {"qualifications": [mining_energy.CONCESSION_QUALIFICATION]})
	if m.is_empty():
		return {"ok": false, "reason": "unknown_mineral"}
	_mine = m
	_persist_mining()
	return {"ok": true, "mineral": mineral, "name": String((mining_energy.MINERALS[mineral] as Dictionary).get("name", mineral))}

## 取得矿权（特许经营），需资质与最低资本。
func acquire_mine_concession() -> Dictionary:
	if _mine.is_empty():
		return {"ok": false, "reason": "no_mine"}
	var r: Dictionary = mining_energy.acquire_concession(_mine)
	_persist_mining()
	return r

## 勘探矿场：投入预算揭示储量与品位。
func explore_mine(budget: int) -> Dictionary:
	if _mine.is_empty():
		return {"ok": false, "reason": "no_mine"}
	var r: Dictionary = mining_energy.explore(_mine, maxi(0, budget))
	_persist_mining()
	return r

## 开采矿石：产出自动转运至冶炼环节。
func extract_ore(amount: float) -> Dictionary:
	if _mine.is_empty():
		return {"ok": false, "reason": "no_mine"}
	var r: Dictionary = mining_energy.extract(_mine, maxf(0.0, amount))
	if bool(r.get("ok", false)):
		mining_energy.transport_ore(_mine, float(r.get("ore", 0.0)))
	_persist_mining()
	return r

## 冶炼金属。
func smelt_ore(amount: float) -> Dictionary:
	if _mine.is_empty():
		return {"ok": false, "reason": "no_mine"}
	var r: Dictionary = mining_energy.smelt(_mine, maxf(0.0, amount))
	_persist_mining()
	return r

## 出售精炼金属，收入进矿场资金池。
func sell_metal(amount: float) -> Dictionary:
	if _mine.is_empty():
		return {"ok": false, "reason": "no_mine"}
	var r: Dictionary = mining_energy.sell(_mine, maxf(0.0, amount))
	_persist_mining()
	return r

## 新能源项目：风电/光伏/核电/储能。
func build_energy_project(kind: String, capacity: float) -> Dictionary:
	var p: Dictionary = mining_energy.new_energy_project(kind, maxf(0.0, capacity))
	if p.is_empty():
		return {"ok": false, "reason": "unknown_energy_kind"}
	var projects: Array = _energy.get("projects", [])
	projects.append(p)
	_energy["projects"] = projects
	_persist_mining()
	return {"ok": true, "kind": kind, "name": String(p.get("name", kind)), "capacity": float(p.get("capacity", 0.0))}

## 矿业/能源面板数据：矿场概况、能源价格、新能源项目。
func mining_panel_data() -> Dictionary:
	var out: Dictionary = {}
	if not _mine.is_empty():
		var mineral: String = String(_mine.get("mineral", ""))
		out["mine"] = {
			"mineral": mineral,
			"mineral_name": String((mining_energy.MINERALS.get(mineral, {}) as Dictionary).get("name", mineral)),
			"concession": bool(_mine.get("concession", false)),
			"explored": bool(_mine.get("explored", false)),
			"reserve": float(_mine.get("reserve", 0.0)),
			"grade": float(_mine.get("grade", 0.0)),
			"workers": int(_mine.get("workers", 0)),
			"safety": float(_mine.get("safety", 0.5)),
			"stockpile_ore": float(_mine.get("stockpile_ore", 0.0)),
			"in_transit_ore": float(_mine.get("in_transit_ore", 0.0)),
			"refined_metal": float(_mine.get("refined_metal", 0.0)),
			"revenue": int(_mine.get("revenue", 0)),
		}
	var prices: Dictionary = _energy.get("prices", {})
	var price_rows: Array = []
	for key in mining_energy.energy_keys():
		price_rows.append({
			"key": String(key),
			"name": String((mining_energy.ENERGY_TYPES[key] as Dictionary).get("name", key)),
			"price": int(prices.get(key, 0)),
		})
	out["energy_prices"] = price_rows
	var projects: Array = []
	for p in _energy.get("projects", []):
		projects.append({"name": String(p.get("name", "")), "kind": String(p.get("kind", "")), "capacity": float(p.get("capacity", 0.0))})
	out["projects"] = projects
	return out

func _mining_tick(before_minutes: int, after_minutes: int) -> void:
	var years: float = float(maxi(0, after_minutes - before_minutes)) / 525960.0
	if years <= 0.0:
		return
	mining_energy.tick_energy(_energy, years)
	_persist_mining()

func _persist_mining() -> void:
	if state == null or not (state.sim_runtime is Dictionary):
		return
	(state.sim_runtime as Dictionary)["mining"] = {"mine": _mine.duplicate(true), "energy": _energy.duplicate(true)}


# --- D29 农林牧渔深化 ---

func primary_state() -> Dictionary:
	return {"fishery": _fishery, "forest": _forest, "hunter": _hunter, "ecology": _ecology}

func fish_species_catalog() -> Array:
	var out: Array = []
	for key in primary_industry.FISH_SPECIES.keys():
		out.append({"id": String(key), "name": String((primary_industry.FISH_SPECIES[key] as Dictionary).get("name", key))})
	return out

func game_species_catalog() -> Array:
	var out: Array = []
	for key in primary_industry.GAME_SPECIES.keys():
		out.append({"id": String(key), "name": String((primary_industry.GAME_SPECIES[key] as Dictionary).get("name", key))})
	return out

func forest_types_catalog() -> Array:
	var out: Array = []
	for key in primary_industry.FOREST_TYPES.keys():
		out.append({"id": String(key), "name": String((primary_industry.FOREST_TYPES[key] as Dictionary).get("name", key))})
	return out

func new_fishery() -> Dictionary:
	if not _fishery.is_empty():
		return {"ok": false, "reason": "already_owns"}
	_fishery = primary_industry.new_fishery()
	_persist_primary()
	return {"ok": true, "boats": int(_fishery.get("boats", 0))}

func fish_catch(species: String, amount: float) -> Dictionary:
	if _fishery.is_empty():
		return {"ok": false, "reason": "no_fishery"}
	var r: Dictionary = primary_industry.catch_fish(_fishery, species, maxf(0.0, amount))
	_persist_primary()
	return r

func start_closed_season() -> Dictionary:
	if _fishery.is_empty():
		return {"ok": false, "reason": "no_fishery"}
	var r: Dictionary = primary_industry.start_closed_season(_fishery)
	_persist_primary()
	return r

func new_forest(ftype: String = "timber") -> Dictionary:
	if not _forest.is_empty():
		return {"ok": false, "reason": "already_owns"}
	if not primary_industry.FOREST_TYPES.has(ftype):
		ftype = "timber"
	_forest = primary_industry.new_forest(1000000, {"forest_type": ftype})
	primary_industry.grant_forest_rights(_forest)
	_persist_primary()
	return {"ok": true, "forest_type": ftype, "name": String((primary_industry.FOREST_TYPES[ftype] as Dictionary).get("name", ftype))}

func log_trees(amount: float) -> Dictionary:
	if _forest.is_empty():
		return {"ok": false, "reason": "no_forest"}
	var r: Dictionary = primary_industry.log_trees(_forest, maxf(0.0, amount))
	_persist_primary()
	return r

func reforest(amount: float) -> Dictionary:
	if _forest.is_empty():
		return {"ok": false, "reason": "no_forest"}
	var r: Dictionary = primary_industry.reforest(_forest, maxf(0.0, amount))
	_persist_primary()
	return r

func apply_hunting_license() -> Dictionary:
	if _hunter.is_empty():
		_hunter = primary_industry.new_hunter()
	var r: Dictionary = primary_industry.hunting_license(_hunter)
	_persist_primary()
	return r

func hunt(species: String, amount: float) -> Dictionary:
	if _hunter.is_empty():
		_hunter = primary_industry.new_hunter()
	var r: Dictionary = primary_industry.hunt(_hunter, species, maxf(0.0, amount))
	_persist_primary()
	return r

## 农林牧渔面板数据：渔场/林场/狩猎/生态。
func primary_panel_data() -> Dictionary:
	var out: Dictionary = {}
	if not _fishery.is_empty():
		out["fishery"] = {
			"boats": int(_fishery.get("boats", 0)),
			"resource_ratio": float(_fishery.get("resource_ratio", 1.0)),
			"closed_season": bool(_fishery.get("closed_season", false)),
			"closed_days_left": float(_fishery.get("closed_days_left", 0.0)),
			"overfish": float(_fishery.get("overfish", 0.0)),
		}
	if not _forest.is_empty():
		var ftype: String = String(_forest.get("forest_type", "timber"))
		out["forest"] = {
			"forest_type": ftype,
			"forest_type_name": String((primary_industry.FOREST_TYPES.get(ftype, {}) as Dictionary).get("name", ftype)),
			"area": float(_forest.get("area", 0.0)),
			"trees": float(_forest.get("trees", 0.0)),
			"wood": float(_forest.get("wood", 0.0)),
			"fire_risk": float(_forest.get("fire_risk", 0.0)),
		}
	if not _hunter.is_empty():
		out["hunter"] = {"license": bool(_hunter.get("license", false)), "wanted_level": int(_hunter.get("wanted_level", 0)), "money": int(_hunter.get("money", 0))}
	if not _ecology.is_empty():
		out["ecology"] = {"resource_ratio": float(_ecology.get("resource_ratio", 1.0)), "soil_quality": float(_ecology.get("soil_quality", 1.0)), "erosion": float(_ecology.get("erosion", 0.0))}
	return out

func _primary_tick(before_minutes: int, after_minutes: int) -> void:
	var days: float = float(maxi(0, after_minutes - before_minutes)) / 1440.0
	if days <= 0.0:
		return
	if not _fishery.is_empty():
		primary_industry.recover_resource(_fishery, days)
	if not _forest.is_empty():
		var growth: float = float((primary_industry.FOREST_TYPES.get(String(_forest.get("forest_type", "timber")), {}) as Dictionary).get("growth", 0.0))
		_forest["trees"] = float(_forest.get("trees", 0.0)) + float(_forest.get("area", 0.0)) * growth * days
	_persist_primary()

func _persist_primary() -> void:
	if state == null or not (state.sim_runtime is Dictionary):
		return
	(state.sim_runtime as Dictionary)["primary"] = {
		"fishery": _fishery.duplicate(true), "forest": _forest.duplicate(true),
		"hunter": _hunter.duplicate(true), "ecology": _ecology.duplicate(true),
	}


# --- D30 餐饮与食品工业 ---

func dining_state() -> Dictionary:
	return _restaurant.duplicate(true)

func dining_recipes_catalog() -> Array:
	var out: Array = []
	for key in dining.recipe_keys():
		out.append({"id": String(key), "name": String((dining.RECIPES[key] as Dictionary).get("name", key))})
	return out

func dining_channels_catalog() -> Array:
	var out: Array = []
	for key in dining.channel_keys():
		out.append({"id": String(key), "name": String((dining.CHANNELS[key] as Dictionary).get("name", key))})
	return out

func dining_staff_roles_catalog() -> Array:
	var out: Array = []
	for key in dining.staff_role_keys():
		out.append({"id": String(key), "name": String((dining.STAFF_ROLES[key] as Dictionary).get("name", key))})
	return out

func dining_modes_catalog() -> Array:
	var out: Array = []
	for key in dining.expansion_modes():
		out.append({"id": String(key), "name": String((dining.EXPANSION[key] as Dictionary).get("name", key))})
	return out

func dining_certs_catalog() -> Array:
	var out: Array = []
	for key in dining.certification_keys():
		out.append({"id": String(key), "name": String((dining.CERTIFICATIONS[key] as Dictionary).get("name", key))})
	return out

func dining_marketing_catalog() -> Array:
	var out: Array = []
	for key in dining.MARKETING.keys():
		out.append({"id": String(key), "name": String((dining.MARKETING[key] as Dictionary).get("name", key))})
	return out

func open_restaurant(money: int = 1000000) -> Dictionary:
	if not _restaurant.is_empty():
		return {"ok": false, "reason": "already_owns"}
	_restaurant = dining.new_restaurant(maxi(0, money))
	_persist_dining()
	return {"ok": true, "name": String(_restaurant.get("name", ""))}

func restaurant_add_menu(recipe: String) -> Dictionary:
	if _restaurant.is_empty():
		return {"ok": false, "reason": "no_restaurant"}
	var r: Dictionary = dining.add_to_menu(_restaurant, recipe)
	if bool(r.get("ok", false)):
		_persist_dining()
	return r

func restaurant_set_price(recipe: String, price: int) -> Dictionary:
	if _restaurant.is_empty():
		return {"ok": false, "reason": "no_restaurant"}
	var r: Dictionary = dining.set_price(_restaurant, recipe, maxi(0, price))
	if bool(r.get("ok", false)):
		_persist_dining()
	return r

func restaurant_sell_day(channel: String = "dine_in") -> Dictionary:
	if _restaurant.is_empty():
		return {"ok": false, "reason": "no_restaurant"}
	var r: Dictionary = dining.sell_day(_restaurant, {"channel": channel})
	_persist_dining()
	return r

func restaurant_hire(role: String, count: int) -> Dictionary:
	if _restaurant.is_empty():
		return {"ok": false, "reason": "no_restaurant"}
	var r: Dictionary = dining.hire(_restaurant, role, maxi(0, count))
	if bool(r.get("ok", false)):
		_persist_dining()
	return r

func restaurant_expand(mode: String) -> Dictionary:
	if _restaurant.is_empty():
		return {"ok": false, "reason": "no_restaurant"}
	var r: Dictionary = dining.expand_to(_restaurant, mode)
	if bool(r.get("ok", false)):
		_persist_dining()
	return r

func restaurant_certify(cert: String) -> Dictionary:
	if _restaurant.is_empty():
		return {"ok": false, "reason": "no_restaurant"}
	var r: Dictionary = dining.certify(_restaurant, cert)
	if bool(r.get("ok", false)):
		_persist_dining()
	return r

func restaurant_marketing(kind: String, cost: int) -> Dictionary:
	if _restaurant.is_empty():
		return {"ok": false, "reason": "no_restaurant"}
	var r: Dictionary = dining.marketing_campaign(_restaurant, kind, maxi(0, cost))
	if bool(r.get("ok", false)):
		_persist_dining()
	return r

func restaurant_process(recipe: String, qty: float) -> Dictionary:
	if _restaurant.is_empty():
		return {"ok": false, "reason": "no_restaurant"}
	var r: Dictionary = dining.process_food(_restaurant, recipe, maxf(0.0, qty))
	if bool(r.get("ok", false)):
		_persist_dining()
	return r

func restaurant_distribute(recipe: String, qty: float, channel: String = "retail") -> Dictionary:
	if _restaurant.is_empty():
		return {"ok": false, "reason": "no_restaurant"}
	var r: Dictionary = dining.distribute(_restaurant, recipe, maxf(0.0, qty), channel)
	if bool(r.get("ok", false)):
		_persist_dining()
	return r

## 餐饮面板数据：门店概况/菜单/员工/产品/认证。
func dining_panel_data() -> Dictionary:
	if _restaurant.is_empty():
		return {}
	var out: Dictionary = {
		"name": String(_restaurant.get("name", "")),
		"money": int(_restaurant.get("money", 0)),
		"mode": String(_restaurant.get("mode", "single_shop")),
		"mode_name": String((dining.EXPANSION.get(String(_restaurant.get("mode", "single_shop")), {}) as Dictionary).get("name", "")),
		"stores": int(_restaurant.get("stores", 1)),
		"reputation": float(_restaurant.get("reputation", 50.0)),
		"hygiene": float(_restaurant.get("hygiene", 70.0)),
		"brand": float(_restaurant.get("brand", 40.0)),
		"stars": dining.review_stars(_restaurant),
		"stars_name": dining.star_name(_restaurant),
		"headcount": dining.headcount(_restaurant),
		"turnover": dining.expected_turnover(_restaurant),
	}
	var menu_rows: Array = []
	for recipe in dining.menu_keys(_restaurant):
		var m: Dictionary = dining.recipe_margin(_restaurant, String(recipe))
		menu_rows.append({
			"key": String(recipe),
			"name": String((dining.RECIPES.get(String(recipe), {}) as Dictionary).get("name", recipe)),
			"price": int(m.get("price", 0)), "cost": int(m.get("cost", 0)),
			"margin": float(m.get("gross_margin", 0.0)),
		})
	out["menu"] = menu_rows
	var staff_rows: Array = []
	for role in dining.staff_role_keys():
		var n: int = dining.staff_count(_restaurant, String(role))
		if n > 0:
			staff_rows.append({"role": String(role), "name": String((dining.STAFF_ROLES[role] as Dictionary).get("name", role)), "count": n})
	out["staff"] = staff_rows
	var products: Array = []
	for k in (_restaurant.get("products", {}) as Dictionary).keys():
		products.append({"key": String(k), "qty": float((_restaurant["products"] as Dictionary)[k])})
	out["products"] = products
	out["certifications"] = (_restaurant.get("certifications", []) as Array).duplicate()
	return out

func _persist_dining() -> void:
	if state == null or not (state.sim_runtime is Dictionary):
		return
	(state.sim_runtime as Dictionary)["dining"] = {"restaurant": dining.to_dict(_restaurant)}


# --- D31 时尚、设计与奢侈品 ---

func fashion_state() -> Dictionary:
	return {"brand": _brand, "trend": _trend}

func fashion_disciplines_catalog() -> Array:
	var out: Array = []
	for key in fashion.discipline_keys():
		out.append({"id": String(key), "name": String((fashion.DISCIPLINES[key] as Dictionary).get("name", key))})
	return out

func fashion_positionings_catalog() -> Array:
	var out: Array = []
	for key in fashion.positioning_keys():
		out.append({"id": String(key), "name": String((fashion.POSITIONING[key] as Dictionary).get("name", key))})
	return out

func fashion_luxury_catalog() -> Array:
	var out: Array = []
	for key in fashion.luxury_keys():
		out.append({"id": String(key), "name": String((fashion.LUXURY_ITEMS[key] as Dictionary).get("name", key))})
	return out

func fashion_marketing_catalog() -> Array:
	var out: Array = []
	for key in fashion.MARKETING.keys():
		out.append({"id": String(key), "name": String((fashion.MARKETING[key] as Dictionary).get("name", key))})
	return out

func fashion_seasons_catalog() -> Array:
	var out: Array = []
	for key in fashion.season_keys():
		out.append({"id": String(key), "name": String((fashion.SEASONS[key] as Dictionary).get("name", key))})
	return out

func new_brand(positioning: String, money: int = 1000000) -> Dictionary:
	if not _brand.is_empty():
		return {"ok": false, "reason": "already_owns"}
	if not fashion.POSITIONING.has(positioning):
		positioning = "mass"
	_brand = fashion.new_brand(money, {"positioning": positioning})
	_trend = fashion.new_trend()
	_persist_fashion()
	return {"ok": true, "name": String(_brand.get("name", "")), "positioning": positioning}

func fashion_design(discipline: String) -> Dictionary:
	if _brand.is_empty():
		return {"ok": false, "reason": "no_brand"}
	if not fashion.DISCIPLINES.has(discipline):
		return {"ok": false, "reason": "bad_discipline"}
	var design: Dictionary = fashion.create_design(discipline, player().get("skills", []), _trend)
	if not bool(design.get("ok", false)):
		return design
	(_brand["collections"] as Array).append(design)
	_persist_fashion()
	return design

func fashion_week(season: String = "ss") -> Dictionary:
	if _brand.is_empty():
		return {"ok": false, "reason": "no_brand"}
	var designs: Array = _brand.get("collections", [])
	if designs.is_empty():
		return {"ok": false, "reason": "no_design"}
	var r: Dictionary = fashion.fashion_week(_brand, designs, {"season": season})
	_persist_fashion()
	return r

func fashion_collab(partner_fame: float) -> Dictionary:
	if _brand.is_empty():
		return {"ok": false, "reason": "no_brand"}
	var r: Dictionary = fashion.collab(_brand, clampf(partner_fame, 0.0, 100.0))
	_persist_fashion()
	return r

func fashion_limited_edition(item: String, qty: int) -> Dictionary:
	if _brand.is_empty():
		return {"ok": false, "reason": "no_brand"}
	if not fashion.LUXURY_ITEMS.has(item):
		return {"ok": false, "reason": "unknown_item"}
	var r: Dictionary = fashion.limited_edition(_brand, item, maxi(1, qty))
	_persist_fashion()
	return r

func fashion_open_store(cost: int) -> Dictionary:
	if _brand.is_empty():
		return {"ok": false, "reason": "no_brand"}
	var r: Dictionary = fashion.open_store(_brand, maxi(0, cost), current_region_id())
	if bool(r.get("ok", false)):
		_persist_fashion()
	return r

func fashion_marketing(kind: String, cost: int) -> Dictionary:
	if _brand.is_empty():
		return {"ok": false, "reason": "no_brand"}
	var r: Dictionary = fashion.run_marketing(_brand, kind, maxi(0, cost))
	if bool(r.get("ok", false)):
		_persist_fashion()
	return r

func fashion_renew(strategy: String, cost: int) -> Dictionary:
	if _brand.is_empty():
		return {"ok": false, "reason": "no_brand"}
	var r: Dictionary = fashion.renew_brand(_brand, strategy, maxi(0, cost))
	if bool(r.get("ok", false)):
		_persist_fashion()
	return r

func fashion_authenticate(item: String) -> Dictionary:
	if not fashion.LUXURY_ITEMS.has(item):
		return {"ok": false, "reason": "unknown_item"}
	var entry: Dictionary = (_brand.get("inventory", {}) as Dictionary).get(item, {}) if not _brand.is_empty() else {}
	var rec: Dictionary = {
		"authentic": true,
		"provenance": 0.8,
		"value": int(entry.get("price", int((fashion.LUXURY_ITEMS[item] as Dictionary).get("base_value", 0)))),
	}
	return fashion.authenticate(rec)

func fashion_panel_data() -> Dictionary:
	if _brand.is_empty():
		return {}
	var out: Dictionary = {
		"name": String(_brand.get("name", "")),
		"positioning": String(_brand.get("positioning", "mass")),
		"positioning_name": String((fashion.POSITIONING.get(String(_brand.get("positioning", "mass")), {}) as Dictionary).get("name", "")),
		"money": int(_brand.get("money", 0)),
		"reputation": float(_brand.get("reputation", 50.0)),
		"fame": float(_brand.get("fame", 0.0)),
		"relevance": float(_brand.get("relevance", 80.0)),
		"brand_value": int(_brand.get("brand_value", 0)),
		"premium": fashion.brand_premium(_brand),
		"stores": (_brand.get("stores", []) as Array).size(),
		"trend_phase": String(_trend.get("phase", "")),
		"trend_phase_name": String(fashion.TREND_PHASE_NAMES.get(String(_trend.get("phase", "")), "")),
		"trend_hot": String((fashion.DISCIPLINES.get(String(_trend.get("hot_discipline", "")), {}) as Dictionary).get("name", "")),
	}
	var design_rows: Array = []
	for d in (_brand.get("collections", []) as Array):
		design_rows.append({
			"discipline": String(d.get("discipline", "")),
			"discipline_name": String((fashion.DISCIPLINES.get(String(d.get("discipline", "")), {}) as Dictionary).get("name", "")),
			"score": float(d.get("score", 0.0)), "grade": String(d.get("grade", "")),
		})
	out["designs"] = design_rows
	var inv_rows: Array = []
	for key in (_brand.get("inventory", {}) as Dictionary).keys():
		var inv: Dictionary = (_brand["inventory"] as Dictionary)[key]
		inv_rows.append({"key": String(key), "qty": int(inv.get("qty", 0)), "price": int(inv.get("price", 0))})
	out["inventory"] = inv_rows
	return out

func _persist_fashion() -> void:
	if state == null or not (state.sim_runtime is Dictionary):
		return
	(state.sim_runtime as Dictionary)["fashion"] = {"brand": fashion.to_dict(_brand), "trend": _trend.duplicate(true)}


func sports_state() -> Dictionary:
	return {"player": _pro_player, "club": _sports_club, "rival": _sports_rival, "league": _sports_league}

func sports_injuries_catalog() -> Array:
	var out: Array = []
	for key in sports_industry.INJURIES.keys():
		out.append({"id": String(key), "name": String((sports_industry.INJURIES[key] as Dictionary).get("name", key))})
	return out

func sports_scandals_catalog() -> Array:
	var out: Array = []
	for key in sports_industry.SCANDALS.keys():
		out.append({"id": String(key), "name": String((sports_industry.SCANDALS[key] as Dictionary).get("name", key))})
	return out

func sports_competitions_catalog() -> Array:
	var out: Array = []
	for key in sports_industry.COMPETITIONS.keys():
		out.append({"id": String(key), "name": String((sports_industry.COMPETITIONS[key] as Dictionary).get("name", key))})
	return out

## 开启职业运动生涯：注册球会与地区联赛，签订首份职业合同。
func start_sports_career() -> Dictionary:
	if not _pro_player.is_empty():
		return {"ok": false, "reason": "already_career"}
	var pname := String(player().get("name", "我"))
	_pro_player = sports_industry.new_pro("player", "home_club", {"name": pname, "age": int(player().get("age", 22))})
	_sports_club = sports_industry.new_club("home_club", {"name": "本地球会"})
	_sports_rival = sports_industry.new_club("rival_club", {"name": "同城劲敌"})
	_sports_league = sports_industry.new_league("local_league", "top", {"name": "地区联赛"})
	sports_industry.register_club(_sports_league, _sports_club)
	sports_industry.register_club(_sports_league, _sports_rival)
	sports_industry.schedule_season(_sports_league)
	var wage: int = int(_pro_player.get("wage", 200000))
	sports_industry.sign_pro_contract(_pro_player, _sports_club, wage, 3.0)
	_sports_club["strength"] = sports_industry.club_strength(_sports_club)
	_persist_sports()
	return {"ok": true, "club": String(_sports_club.get("name", "")), "wage": wage}

## 出战一场联赛：推演比分、计入积分榜并为球会结算门票收入。
func sports_play_match() -> Dictionary:
	if _pro_player.is_empty():
		return {"ok": false, "reason": "no_career"}
	if bool(_pro_player.get("disabled", false)):
		return {"ok": false, "reason": "disabled"}
	if float(_pro_player.get("injury_days", 0.0)) > 0.0:
		return {"ok": false, "reason": "injured"}
	if float(_pro_player.get("ban_days", 0.0)) > 0.0:
		return {"ok": false, "reason": "banned"}
	var r: Dictionary = sports_industry.play_match(_sports_league, _sports_club, _sports_rival)
	_pro_player["appearances"] = int(_pro_player.get("appearances", 0)) + 1
	if str(r.get("winner", "")) == String(_sports_club.get("id", "")):
		_pro_player["goals"] = int(_pro_player.get("goals", 0)) + 1
	_sports_club["budget"] = int(_sports_club.get("budget", 0)) + sports_industry.club_matchday_income(_sports_club)
	sports_industry.market_value(_pro_player)
	_persist_sports()
	return r

## 转会至对手球会：结算转会费与经纪人佣金，双方球会互换。
func sports_transfer(fee: int) -> Dictionary:
	if _pro_player.is_empty():
		return {"ok": false, "reason": "no_career"}
	var r: Dictionary = sports_industry.transfer(_pro_player, _sports_rival, maxi(0, fee))
	if bool(r.get("ok", false)):
		var tmp: Dictionary = _sports_club
		_sports_club = _sports_rival
		_sports_rival = tmp
		_sports_club["strength"] = sports_industry.club_strength(_sports_club)
		_persist_sports()
	return r

## 签订代言合同：追加赞助商并抬升身价。
func sports_sponsorship(brand: String, amount: int) -> Dictionary:
	if _pro_player.is_empty():
		return {"ok": false, "reason": "no_career"}
	var b := brand.strip_edges()
	if b == "":
		b = "赞助商"
	var r: Dictionary = sports_industry.sponsorship(_pro_player, {"brand": b, "amount": maxi(0, amount)})
	_persist_sports()
	return r

func sports_injure(severity: String) -> Dictionary:
	if _pro_player.is_empty():
		return {"ok": false, "reason": "no_career"}
	var r: Dictionary = sports_industry.injure(_pro_player, severity)
	if bool(r.get("ok", false)):
		_persist_sports()
	return r

## 运动康复：按天数恢复，清除伤病天数并部分恢复状态。
func sports_rehab(days: float) -> Dictionary:
	if _pro_player.is_empty():
		return {"ok": false, "reason": "no_career"}
	var r: Dictionary = sports_industry.rehab(_pro_player, maxf(0.0, days))
	_persist_sports()
	return r

## 兴奋剂检测：阳性则追加禁赛处罚。
func sports_doping_test() -> Dictionary:
	if _pro_player.is_empty():
		return {"ok": false, "reason": "no_career"}
	var r: Dictionary = sports_industry.doping_test(_pro_player, 0.1)
	if bool(r.get("positive", false)):
		sports_industry.commit_scandal(_pro_player, "doping")
	_persist_sports()
	return r

func sports_retire() -> Dictionary:
	if _pro_player.is_empty():
		return {"ok": false, "reason": "no_career"}
	var r: Dictionary = sports_industry.retire(_pro_player)
	_persist_sports()
	return r

func sports_panel_data() -> Dictionary:
	if _pro_player.is_empty():
		return {}
	var out: Dictionary = {
		"stage": String(_pro_player.get("career_stage", "")),
		"age": int(_pro_player.get("age", 0)),
		"form": float(_pro_player.get("form", 0.0)),
		"market_value": int(_pro_player.get("market_value", 0)),
		"wage": int(_pro_player.get("wage", 0)),
		"injury_days": float(_pro_player.get("injury_days", 0.0)),
		"ban_days": float(_pro_player.get("ban_days", 0.0)),
		"appearances": int(_pro_player.get("appearances", 0)),
		"goals": int(_pro_player.get("goals", 0)),
		"club": String(_sports_club.get("name", "")),
		"club_division": String(_sports_club.get("division", "top")),
		"budget": int(_sports_club.get("budget", 0)),
		"sponsors": (_pro_player.get("sponsors", []) as Array).size(),
	}
	var rows: Array = []
	for row in sports_industry.standings(_sports_league):
		rows.append({
			"id": String(row.get("id", "")),
			"played": int(row.get("played", 0)),
			"points": int(row.get("points", 0)),
			"goals_for": int(row.get("goals_for", 0)),
			"goals_against": int(row.get("goals_against", 0)),
		})
	out["standings"] = rows
	return out

func _persist_sports() -> void:
	if state == null or not (state.sim_runtime is Dictionary):
		return
	(state.sim_runtime as Dictionary)["sports"] = {
		"player": _pro_player.duplicate(true),
		"club": _sports_club.duplicate(true),
		"rival": _sports_rival.duplicate(true),
		"league": _sports_league.duplicate(true),
	}


func events_state() -> Dictionary:
	return {"event": _event, "planner": _planner}

func events_types_catalog() -> Array:
	var out: Array = []
	for key in events_expo.event_type_keys():
		out.append({"id": String(key), "name": String((events_expo.EVENT_TYPES[key] as Dictionary).get("name", key))})
	return out

func events_stages_catalog() -> Array:
	var out: Array = []
	var names: Dictionary = events_expo.stage_names()
	for key in events_expo.STAGES:
		out.append({"id": String(key), "name": String(names.get(String(key), key))})
	return out

func events_sponsor_tiers_catalog() -> Array:
	var out: Array = []
	for key in events_expo.sponsor_tier_keys():
		out.append({"id": String(key), "name": String((events_expo.SPONSOR_TIERS[key] as Dictionary).get("name", key))})
	return out

func events_roles_catalog() -> Array:
	var out: Array = []
	for key in events_expo.career_role_keys():
		out.append({"id": String(key), "name": String((events_expo.CAREER_ROLES[key] as Dictionary).get("name", key))})
	return out

## 开启活动策划职业路径。
func start_event_career(role: String = "planner") -> Dictionary:
	if not _planner.is_empty():
		return {"ok": false, "reason": "already_planner"}
	_planner = events_expo.new_planner(role)
	_persist_events()
	return {"ok": true, "role": String(_planner.get("role", role)), "level": int(_planner.get("level", 1))}

## 筹办一场新活动（覆盖上一场已复盘的活动）。
func events_new(event_type: String) -> Dictionary:
	if not _event.is_empty() and str(_event.get("stage", "")) != "review":
		return {"ok": false, "reason": "in_progress"}
	if not events_expo.EVENT_TYPES.has(event_type):
		return {"ok": false, "reason": "unknown_type"}
	_event = events_expo.new_event(event_type)
	_persist_events()
	return {"ok": true, "type": event_type, "name": String(_event.get("name", ""))}

func events_rent_venue(cost: int) -> Dictionary:
	if _event.is_empty():
		return {"ok": false, "reason": "no_event"}
	var capacity: int = int((events_expo.EVENT_TYPES.get(String(_event.get("type", "")), {}) as Dictionary).get("base_capacity", 10000))
	var venue: Dictionary = {"name": "会展中心", "capacity": capacity, "cost": maxi(0, cost)}
	var r: Dictionary = events_expo.rent_venue(_event, venue)
	if bool(r.get("ok", false)):
		_persist_events()
	return r

func events_approval() -> Dictionary:
	if _event.is_empty():
		return {"ok": false, "reason": "no_event"}
	var r: Dictionary = events_expo.apply_approval(_event, true)
	_persist_events()
	return r

func events_sponsor(tier: String) -> Dictionary:
	if _event.is_empty():
		return {"ok": false, "reason": "no_event"}
	var r: Dictionary = events_expo.add_sponsor(_event, tier)
	if bool(r.get("ok", false)):
		_persist_events()
	return r

func events_sell_tickets(qty: int) -> Dictionary:
	if _event.is_empty():
		return {"ok": false, "reason": "no_event"}
	var r: Dictionary = events_expo.sell_tickets(_event, maxi(0, qty))
	_persist_events()
	return r

func events_set_security(level: float) -> Dictionary:
	if _event.is_empty():
		return {"ok": false, "reason": "no_event"}
	var r: Dictionary = events_expo.set_security(_event, level)
	if bool(r.get("ok", false)):
		_persist_events()
	return r

## 举办活动：确定性推演现场（roll 固定），结算门票/周边/直播与风险。
func events_hold() -> Dictionary:
	if _event.is_empty():
		return {"ok": false, "reason": "no_event"}
	if str(_event.get("stage", "")) == "review":
		return {"ok": false, "reason": "already_held"}
	if not bool(_event.get("approved", false)):
		return {"ok": false, "reason": "not_approved"}
	var r: Dictionary = events_expo.hold_event(_event, 0.1)
	_persist_events()
	return r

## 复盘：结算净利润，若已从业则累计经验并可能升级。
func events_review() -> Dictionary:
	if _event.is_empty():
		return {"ok": false, "reason": "no_event"}
	var r: Dictionary = events_expo.after_action_review(_event)
	if not _planner.is_empty():
		var cp: Dictionary = events_expo.career_progress(_planner, r)
		r["planner"] = cp
	_persist_events()
	return r

func events_panel_data() -> Dictionary:
	if _event.is_empty() and _planner.is_empty():
		return {}
	var out: Dictionary = {}
	if not _event.is_empty():
		var def: Dictionary = events_expo.EVENT_TYPES.get(String(_event.get("type", "")), {})
		out = {
			"type": String(_event.get("type", "")),
			"type_name": String(def.get("name", "")),
			"name": String(_event.get("name", "")),
			"stage": String(_event.get("stage", "")),
			"stage_name": String(events_expo.STAGE_NAMES.get(String(_event.get("stage", "")), "")),
			"capacity": int(_event.get("capacity", 0)),
			"sold": int(_event.get("sold", 0)),
			"ticket_price": int(_event.get("ticket_price", 0)),
			"budget": int(_event.get("budget", 0)),
			"revenue": int(_event.get("revenue", 0)),
			"cost": int(_event.get("cost", 0)),
			"reputation": float(_event.get("reputation", 0.0)),
			"attendance": int(_event.get("attendance", 0)),
			"sponsors": (_event.get("sponsors", []) as Array).size(),
			"incidents": (_event.get("incidents", []) as Array).size(),
		}
	if not _planner.is_empty():
		out["planner_level"] = int(_planner.get("level", 1))
		out["planner_exp"] = int(_planner.get("exp", 0))
		out["planner_events"] = int(_planner.get("events_done", 0))
	return out

func _persist_events() -> void:
	if state == null or not (state.sim_runtime is Dictionary):
		return
	(state.sim_runtime as Dictionary)["events"] = {
		"event": events_expo.to_dict(_event),
		"planner": _planner.duplicate(true),
	}



## 遗产净额（最小货币单位）：现金 + 存款 − 债务 + 房产估值 − 剩余房贷。
func player_estate_minor() -> float:
	var acct := account_id()
	var total: float = float(economy.cash(acct)) + float(economy.bank(acct)) - float(economy.debt(acct))
	for p in property.owned_properties(player()):
		total += float(property.market_value(p))
		var m: Dictionary = p.get("mortgage", {})
		if not m.is_empty():
			total -= float(m.get("remaining", 0))
	return maxf(0.0, total)

## 法定继承人（按 player.family）：配偶/子女/父母/兄弟姐妹。
func legal_heirs() -> Dictionary:
	var fam: Dictionary = player().get("family", {})
	var spouse: Array = []
	var sid := String(fam.get("spouse_id", ""))
	if sid != "":
		spouse.append(sid)
	return {
		"spouse": spouse,
		"children": _string_ids(fam.get("children_ids", [])),
		"parents": _string_ids(fam.get("parent_ids", [])),
		"siblings": _string_ids(fam.get("sibling_ids", [])),
	}

func _string_ids(raw) -> Array:
	var out: Array = []
	if raw is Array:
		for x in raw:
			out.append(String(x))
	return out

## 死亡结算：按遗嘱或法定继承分配遗产，并把本次死亡记入家族史（legacy.history）。
func settle_inheritance() -> Dictionary:
	var estate: float = player_estate_minor()
	var r: Dictionary = inheritance.settle(estate, player().get("will", {}), legal_heirs())
	# 未成年子女监护归属（R51.5）：优先遗嘱/指定监护人，其次法定顺位。
	var guard: Dictionary = legal_guardian()
	r["guardianship"] = guard
	var hist: Array = state.legacy.get("history", [])
	hist.append({
		"kind": "death",
		"name": String(player().get("name", "")),
		"death_minutes": now_minutes(),
		"estate": float(r.get("estate", 0.0)),
		"tax": float(r.get("tax", 0.0)),
		"net": float(r.get("net", 0.0)),
		"escheat": bool(r.get("escheat", false)),
		"allocations": r.get("allocations", []),
		"guardian": String((guard.get("guardian", {}) as Dictionary).get("id", "")),
		"minors": guard.get("minors", []),
	})
	state.legacy["history"] = hist
	_inheritance_settled = true
	return r

## 是否已完成死亡结算。
func inheritance_settled() -> bool:
	return _inheritance_settled

## 人生结算（R12.5）：姓名/年龄/最终称号/大事记时间线 + 遗产估算与继承人。
func death_summary() -> Dictionary:
	var timeline: Array = state.legacy.get("history", []) if state != null else []
	var s: Dictionary = survival.life_summary(player(), {
		"death_minutes": now_minutes(),
		"timeline": timeline,
		"final_title": _final_title(),
	})
	s["estate_minor"] = player_estate_minor()
	s["heirs"] = legal_heirs()
	return s

func _final_title() -> String:
	var job: Dictionary = player().get("job", {})
	var title := String(job.get("title", "")) if job is Dictionary else ""
	return title if title != "" else "凡人"

## 持久化生存运行时（成瘾复发/营养过量天数/死亡标志/遗嘱）到 state.sim_runtime。
func _persist_survival() -> void:
	if state == null or not (state.sim_runtime is Dictionary):
		return
	(state.sim_runtime as Dictionary)["survival"] = survival.to_dict()

# --- 心理与精神健康（D4） ---

## 人格派生标签（阈值/组合，供面板与叙述层）。
func personality_tags() -> Array:
	return personality.derive_tags(player().get("attrs", {}).get("personality", {}))

## 当前情绪状态（平静/焦虑/抑郁/亢奋）。
func emotion_state() -> String:
	var psych: Dictionary = player().get("attrs", {}).get("psychological", {})
	return mental.emotion_state(float(psych.get("mood", 50.0)), float(psych.get("stress", 40.0)))

## 精神疾病目录（供解析器链接「心理咨询 <病种>」）。
func mental_disorders_catalog() -> Array:
	return mental.disorders_catalog()

## 治疗方式目录（咨询/药物/CBT/住院/重症干预）。
func mental_treatment_catalog() -> Array:
	return mental.treatments_catalog()

## 刷新心理结算：推进三维病程、按压力与长期低值掷骰新发、回写玩家心理与精神疾病数组。
## 返回本时段新发作列表。
func _refresh_mental(minutes: int) -> Array:
	var events: Array = []
	if is_dead():
		return events
	mental.advance(minutes, rng)
	var psych: Dictionary = player().get("attrs", {}).get("psychological", {})
	var stress: float = float(psych.get("stress", 40.0))
	# 幸福长期低值抬高精神疾病风险（R44.8）。
	var happy_mult: float = happiness.disorder_risk_multiplier(
		float(psych.get("happiness", 50.0)), float(psych.get("meaning", 50.0)), day_index())
	if stress >= float(MentalHealthScript.STRESS_DISORDER_THRESHOLD) or happy_mult > 1.05:
		for hit in mental.roll_triggers(player().get("attrs", {}).get("personality", {}), stress, now_minutes(), rng, "stress", happy_mult):
			events.append({"type": "mental_disorder", "name": String(hit.get("name", ""))})
	_update_happiness()
	_sync_mental()
	return events

## 依关系/事业/健康/信仰/意义感结算幸福与意义，写入心理属性（R44.7）。
func _update_happiness() -> void:
	if is_dead():
		return
	var attrs: Dictionary = player().get("attrs", {})
	var phys: Dictionary = attrs.get("physiological", {})
	var values: Dictionary = attrs.get("values", {})
	var fam: Dictionary = player().get("family", {})
	# 关系：好感均值映射到 0..100（无关系取人群基线 50）。
	var relations: Array = player().get("relations", [])
	var rel_score: float = 50.0
	if not relations.is_empty():
		var acc: float = 0.0
		for r in relations:
			if r is Dictionary:
				acc += clampf((float(r.get("favor", 0.0)) + 100.0) / 2.0, 0.0, 100.0)
		rel_score = acc / float(relations.size())
	# 事业：有工作按绩效，无业取 40。
	var job: Dictionary = player().get("job", {})
	var career_score: float = 40.0
	if not job.is_empty():
		career_score = clampf(float(job.get("performance", 60.0)), 0.0, 100.0)
	# 信仰：物质—精神轴偏向精神即高。
	var faith_score: float = clampf(float(values.get("material_spiritual", 50.0)), 0.0, 100.0)
	# 皈依后信仰分量随境界抬升（R55.4）。
	var faith_realm: int = spirituality.faith_realm_index(_spirit)
	if String(_spirit.get("faith", "")) != "":
		faith_score = clampf(maxf(faith_score, 60.0 + float(faith_realm) * 8.0), 0.0, 100.0)
	# 意义感分量：追求（精神轴 + 信仰境界）、家庭（有配偶/子女）、成就（数量）、价值观一致性。
	var pursuit: float = clampf(faith_score + float(faith_realm) * 4.0, 0.0, 100.0)
	var family_c: float = 30.0
	if String(fam.get("spouse_id", "")) != "":
		family_c += 35.0
	family_c += minf(35.0, float((fam.get("children_ids", []) as Array).size()) * 15.0)
	var ach_count: int = (player().get("achievements", []) as Array).size()
	var achievement: float = clampf(30.0 + float(ach_count) * 5.0, 0.0, 100.0)
	var consistency: float = clampf(100.0 - absf(float(values.get("conservative_open", 50.0)) - 50.0) * 2.0, 0.0, 100.0)
	happiness.update(player(), {
		"relations": rel_score,
		"career": career_score,
		"health": clampf(float(phys.get("health", 50.0)), 0.0, 100.0),
		"faith": faith_score,
		"pursuit": pursuit,
		"family": family_c,
		"achievement": achievement,
		"values_consistency": consistency,
	})

## 回写 player.health.mental（schema 白名单字段）。
func _sync_mental() -> void:
	var health: Dictionary = player().get("health", {})
	health["mental"] = mental.mental_entries(now_minutes())
	player()["health"] = health

## 持久化精神疾病运行时到 state.sim_runtime。
func _persist_mental() -> void:
	if state == null or not (state.sim_runtime is Dictionary):
		return
	(state.sim_runtime as Dictionary)["mental"] = mental.to_dict()

## 情绪事件调整（如放松/打击）：写入心情与压力，返回调整后状态。
func apply_emotion_event(event: String) -> Dictionary:
	return mental.adjust_mood_stress(player(), event)

## 放松/正念：缓解压力、提振心情（无对应治疗，仅日常调节）。
func relax() -> Dictionary:
	var before: Dictionary = player().get("attrs", {}).get("psychological", {})
	var r: Dictionary = apply_emotion_event("praise")
	_sync_mental()
	return {
		"ok": true,
		"mood": float(r.get("mood", 0.0)),
		"stress": float(r.get("stress", 0.0)),
		"before_stress": float(before.get("stress", 0.0)),
	}

## 强制发作指定精神疾病（供重大事件/疫情心理冲击/认知污染等跨域触发），并回写。
func mental_onset(key: String) -> Dictionary:
	var attrs: Dictionary = player().get("attrs", {})
	var psych: Dictionary = attrs.get("psychological", {})
	var r: Dictionary = mental.onset(key, attrs.get("personality", {}), float(psych.get("stress", 40.0)), now_minutes())
	_sync_mental()
	_persist_mental()
	return r

## 精神疾病治疗：method 为治疗键；key 为空时取最严重活跃病种。会推进治疗时长并结算费用。
func mental_treat(method: String, key: String = "") -> Dictionary:
	if not mental.TREATMENTS.has(method):
		return {"ok": false, "reason": "unknown_treatment"}
	if String(key).is_empty():
		key = mental.most_severe_active_key()
	if String(key).is_empty() or not mental.DISORDERS.has(key):
		return {"ok": false, "reason": "no_active_disorder"}
	var r: Dictionary = mental.treat(key, method, rng, true)
	if not bool(r.get("ok", false)):
		return r
	var t: Dictionary = mental.TREATMENTS[method]
	var cost := int(t.get("cost", 0))
	if cost > 0:
		if economy.cash(account_id()) < cost:
			return {"ok": false, "reason": "insufficient_funds", "cost": cost}
		economy.add_money(account_id(), -cost, "mental:%s" % method)
		sync_finances()
	var minutes := int(t.get("minutes", 0))
	if minutes > 0:
		advance(minutes, {"asleep": method == "hospitalization"})
	_sync_mental()
	r["key_name"] = mental.disorder_name(String(key))
	r["method_name"] = String(t.get("name", method))
	return r

## 精神健康面板数据（情绪/人格/幸福 + 病程列表）。
func mental_panel_data() -> Dictionary:
	var psych: Dictionary = player().get("attrs", {}).get("psychological", {})
	var p: Dictionary = player().get("attrs", {}).get("personality", {})
	var dims: Array = []
	var names: Dictionary = personality.DIM_NAMES
	for dim in personality.BIG_FIVE:
		dims.append({"label": String(names.get(dim, dim)), "value": str(snappedf(float(p.get(dim, 50.0)), 0.1))})
	var tags: Array = []
	for t in personality_tags():
		tags.append(_tag_name(String(t)))
	var cases: Array = []
	for c in mental.all_cases():
		if not (c is Dictionary):
			continue
		var key := String(c.get("key", ""))
		var active := bool(c.get("active", false))
		var phase := "发作期" if active else ("缓解期" if str(c.get("phase", "")) == "remission" else "慢性期")
		cases.append({
			"label": mental.disorder_name(key),
			"value": "%s · 强度%.0f · 间隔%.0f天 · 单次%.0f天 · 发作%d次%s" % [
				phase, float(c.get("intensity", 0.0)),
				float(c.get("frequency_days", 0.0)),
				float(c.get("duration_minutes", 0.0)) / 1440.0,
				int(c.get("episodes", 0)),
				" · 治疗中" if bool(c.get("in_treatment", false)) else "",
			],
		})
	return {
		"emotion": mental.EMOTION_NAMES.get(emotion_state(), "平静"),
		"mood": float(psych.get("mood", 50.0)),
		"stress": float(psych.get("stress", 40.0)),
		"happiness": float(psych.get("happiness", 50.0)),
		"meaning": float(psych.get("meaning", 50.0)),
		"dims": dims,
		"tags": tags,
		"cases": cases,
	}

## 性格标签中文名。
func _tag_name(tag: String) -> String:
	const TAG_NAMES: Dictionary = {
		"perfectionist": "完美主义", "social_butterfly": "社交达人", "lone_wolf": "独行",
		"anxious_type": "敏感焦虑", "open_minded": "开放探索", "agreeable": "温和亲和",
		"risk_taker": "冒险", "resilient": "坚韧稳定", "achiever": "自律成就",
		"dramatic": "情绪外显", "traditional": "传统守成", "solitary_cold": "孤僻冷淡",
	}
	return String(TAG_NAMES.get(tag, tag))

# --- 精神追求与信仰（D15） ---

## 精神追求目录（冥想/修行/哲学阅读/写作/自省/志愿服务/艺术创作）。
func pursuits_catalog() -> Array:
	return spirituality.pursuits_catalog()

## 信仰/哲学流派目录（R55.4）。
func faiths_catalog() -> Array:
	return spirituality.faiths_catalog()

## 精神危机出口目录（宗教/哲学/心理/志愿）。
func crisis_exits_catalog() -> Array:
	return spirituality.crisis_exits_catalog()

## 执行一次精神追求（R55.3、R55.5）：按投入时长降低压力、提升意义/幸福，并可能漂移人格与价值观。
func pursue_spirit(kind: String, minutes: int) -> Dictionary:
	if not spirituality.PURSUITS.has(kind):
		return {"ok": false, "reason": "unknown_pursuit"}
	var attrs: Dictionary = player().get("attrs", {})
	var psych: Dictionary = attrs.get("psychological", {})
	var values: Dictionary = attrs.get("values", {})
	var persona: Dictionary = attrs.get("personality", {})
	var hours: float = maxf(0.0, float(minutes)) / 60.0
	var cum: Dictionary = _spirit.get("persona_drift", {})
	var r: Dictionary = spirituality.pursue(_spirit, kind, float(minutes), rng, persona, cum)
	_spirit["persona_drift"] = cum
	psych["stress"] = clampf(float(psych.get("stress", 40.0)) + float(r.get("stress", 0.0)), 0.0, 100.0)
	psych["mood"] = clampf(float(psych.get("mood", 50.0)) - float(r.get("stress", 0.0)), 0.0, 100.0)
	attrs["psychological"] = psych
	var vdrift: Dictionary = r.get("value_drift", {}) if r.get("value_drift") is Dictionary else {}
	for axis in vdrift.keys():
		spirituality.adjust_values(values, String(axis), hours * float(vdrift[axis]))
	attrs["personality"] = persona
	attrs["values"] = values
	player()["attrs"] = attrs
	_update_happiness()
	_sync_mental()
	_persist_spirituality()
	return {
		"ok": true, "kind": kind, "name": spirituality.pursuit_name(kind),
		"realm": spirituality.realm_name(int(r.get("realm_index", 0))),
		"realm_unlocked": bool(r.get("realm_unlocked", false)),
		"stress": float(r.get("stress", 0.0)), "hours": hours,
		"personality_drifted": bool(r.get("personality_drifted", false)),
	}

## 皈依/加入信仰或哲学流派（R55.4）。
func convert_faith(faith: String) -> Dictionary:
	var r: Dictionary = spirituality.convert(_spirit, faith)
	if bool(r.get("ok", false)):
		_update_happiness()
		_persist_spirituality()
	return r

## 深化信仰：按小时累计深度并解锁境界（R55.4）。
func deepen_faith(minutes: int) -> Dictionary:
	var r: Dictionary = spirituality.deepen_faith(_spirit, float(minutes), rng)
	if not bool(r.get("ok", false)):
		return r
	var attrs: Dictionary = player().get("attrs", {})
	var psych: Dictionary = attrs.get("psychological", {})
	psych["stress"] = clampf(float(psych.get("stress", 40.0)) + float(r.get("stress", 0.0)), 0.0, 100.0)
	attrs["psychological"] = psych
	player()["attrs"] = attrs
	_update_happiness()
	_sync_mental()
	_persist_spirituality()
	r["faith_name"] = spirituality.faith_name(String(_spirit.get("faith", "")))
	r["realm"] = spirituality.realm_name(int(r.get("realm_index", 0)))
	return r

## 当前精神危机（无则返回空事件）。依意义/幸福/中年窗口与信仰动摇判定（R55.6）。
func spirit_crisis() -> Dictionary:
	var psych: Dictionary = player().get("attrs", {}).get("psychological", {})
	var birth: int = int(player().get("birth_minutes", 0))
	var age: float = maxf(0.0, float(now_minutes() - birth) / MINUTES_PER_YEAR)
	var happy: float = float(psych.get("happiness", 50.0))
	var meaning: float = float(psych.get("meaning", 50.0))
	var midlife: float = happiness.midlife_crisis_weight(age, happy, meaning)
	var r: Dictionary = spirituality.check_crisis(_spirit, happy, meaning, midlife, rng)
	if String(r.get("event", "")) != "":
		_spirit["crisis"] = String(r["event"])
		_persist_spirituality()
	return r

## 通过出口化解当前精神危机（宗教/哲学/心理/志愿），提升意义、降低压力（R55.6）。
func resolve_spirit_crisis(exit_kind: String) -> Dictionary:
	var crisis := String(_spirit.get("crisis", ""))
	if crisis.is_empty():
		return {"ok": false, "reason": "no_crisis"}
	var r: Dictionary = spirituality.resolve_crisis(_spirit, crisis, exit_kind)
	if not bool(r.get("ok", false)):
		return r
	var attrs: Dictionary = player().get("attrs", {})
	var psych: Dictionary = attrs.get("psychological", {})
	psych["stress"] = clampf(float(psych.get("stress", 40.0)) + float(r.get("stress", 0.0)), 0.0, 100.0)
	psych["mood"] = clampf(float(psych.get("mood", 50.0)) - float(r.get("stress", 0.0)), 0.0, 100.0)
	attrs["psychological"] = psych
	player()["attrs"] = attrs
	_update_happiness()
	_sync_mental()
	_persist_spirituality()
	r["crisis"] = crisis
	return r

## 精神追求面板数据（价值观三轴/信仰境界/追求深度/危机）。
func spirit_panel_data() -> Dictionary:
	var values: Dictionary = player().get("attrs", {}).get("values", {})
	var axes: Array = []
	for axis in spirituality.VALUES:
		axes.append({"label": String(spirituality.VALUE_NAMES.get(axis, axis)), "value": str(snappedf(float(values.get(axis, 50.0)), 0.1))})
	var pursuits: Array = []
	var depths: Dictionary = _spirit.get("depth", {})
	for kind in spirituality.PURSUITS.keys():
		var hours: float = float(depths.get(kind, 0.0))
		if hours <= 0.0:
			continue
		pursuits.append({"label": spirituality.pursuit_name(String(kind)), "value": "%s · 累计%.1f小时" % [
			spirituality.realm_name(spirituality.realm_index(_spirit, String(kind))), hours]})
	var faith_key := String(_spirit.get("faith", ""))
	var crisis := String(_spirit.get("crisis", ""))
	return {
		"axes": axes,
		"faith": spirituality.faith_name(faith_key),
		"has_faith": faith_key != "",
		"faith_realm": spirituality.realm_name(spirituality.faith_realm_index(_spirit)),
		"faith_depth": float(_spirit.get("faith_depth", 0.0)),
		"pursuits": pursuits,
		"crisis": crisis,
		"crisis_exits": spirituality.crisis_exits_catalog() if crisis != "" else [],
	}

## 精神追求运行时状态（供测试与叙述层读取）。
func spirit_state() -> Dictionary:
	return _spirit

## 随游戏内时钟检查精神危机（R55.6），返回事件列表。
func _refresh_spirit() -> Array:
	var events: Array = []
	if is_dead():
		return events
	var ev := String(spirit_crisis().get("event", ""))
	if ev != "":
		events.append({"type": "spirit_crisis", "name": ev})
	return events

## 持久化精神追求运行时到 state.sim_runtime。
func _persist_spirituality() -> void:
	if state == null or not (state.sim_runtime is Dictionary):
		return
	(state.sim_runtime as Dictionary)["spirituality"] = spirituality.to_dict(_spirit)

# --- 宠物 ---

## 可领养物种目录（供解析「领养 <宠物>」）。
func pet_species_catalog() -> Array:
	var out: Array = []
	for key in pet.SPECIES.keys():
		out.append({"id": String(key), "name": String((pet.SPECIES[key] as Dictionary).get("name", key))})
	return out

func pets() -> Array:
	return player().get("pets", [])

func find_pet(pet_id: String) -> Dictionary:
	for p in pets():
		if typeof(p) == TYPE_DICTIONARY and String(p.get("id", "")) == pet_id:
			return p
	return {}

## 领养宠物：扣款并写入 player.pets（schema 对齐，含 id/content_key）。
func adopt_pet(species: String, pet_name: String = "") -> Dictionary:
	var r: Dictionary = pet.acquire(species, pet_name if pet_name != "" else species)
	if not bool(r.get("ok", false)):
		return r
	var rec: Dictionary = (r["pet"] as Dictionary).duplicate(true)
	rec["id"] = _make_uuid()
	rec["content_key"] = "pet.%s" % species
	rec["adopted_minutes"] = now_minutes()
	var cost := int(rec.get("cost", 0))
	if cost > 0:
		if economy.cash(account_id()) < cost:
			return {"ok": false, "reason": "insufficient_funds", "cost": cost}
		economy.add_money(account_id(), -cost, "pet:buy")
		sync_finances()
	var arr: Array = player().get("pets", [])
	arr.append(rec)
	player()["pets"] = arr
	return {"ok": true, "pet": rec, "cost": cost}

## 喂养全部宠物，返回被喂养的名字。
func feed_pets(amount: float = 30.0) -> Array:
	var done: Array = []
	for p in pets():
		if p is Dictionary and bool(pet.feed(p, amount).get("ok", false)):
			done.append(String(p.get("name", "")))
	return done

## 训练全部宠物，返回被训练的名字。
func train_pets(hours: float = 1.0) -> Array:
	var done: Array = []
	for p in pets():
		if p is Dictionary and bool(pet.train(p, hours, rng).get("ok", false)):
			done.append(String(p.get("name", "")))
	return done

## 随游戏内时钟推进宠物生命周期；返回宠物死亡事件。
func _advance_pets(minutes: int) -> Array:
	var events: Array = []
	for p in pets():
		if not (p is Dictionary) or not bool(p.get("alive", true)):
			continue
		var ev: Dictionary = pet.advance(p, float(minutes) / float(MINUTES_PER_DAY), rng)
		if String(ev.get("event", "")) == "pet_death":
			events.append({"type": "pet_death", "name": String(p.get("name", ""))})
	return events

## 生成确定性 UUID（与 NpcSystem 同格式）。
func _make_uuid() -> String:
	const DIGITS: String = "0123456789abcdef"
	var hex := ""
	for _i in 32:
		hex += DIGITS[int(rng.next_float() * 16.0) % 16]
	return "%s-%s-%s-%s-%s" % [
		hex.substr(0, 8), hex.substr(8, 4), hex.substr(12, 4),
		hex.substr(16, 4), hex.substr(20, 12),
	]

## 妊娠到期则分娩；返回新生儿档案（无变化返回空）。
func _check_delivery() -> Dictionary:
	if is_dead():
		return {}
	var preg: Dictionary = player().get("family", {}).get("pregnancy", {})
	if preg.is_empty() or now_minutes() < int(preg.get("due_minutes", 0)):
		return {}
	return deliver_child()

## 分娩：生成子女 NPC（继承父母能力/人格），落档到 world_delta.npcs 与
## player.family.children_ids，并记入家族史（legacy.lineage/history）。
func deliver_child() -> Dictionary:
	var fam: Dictionary = player().get("family", {})
	var preg: Dictionary = fam.get("pregnancy", {})
	var partner_id := String(preg.get("partner_id", fam.get("spouse_id", "")))
	var spouse := find_person(partner_id)
	var gender := "male" if rng.next_float() < 0.5 else "female"
	_child_seq += 1
	# 子女 NPC 使用独立序号段，避免与熟人（1..N）等个体 id 冲突。
	var child: Dictionary = npcs.generate(_child_seq + 100000, {
		"world_seed": _seed, "region_id": _home_region_id,
		"now_minute": now_minutes(), "individualized": true, "lod_tier": 0,
		"age": 0, "gender": gender,
	})
	var inherited: Dictionary = family.give_birth(player(), spouse, String(child.get("name", "")), gender)
	var attrs: Dictionary = child.get("attributes", {})
	attrs["ability"] = inherited.get("ability", {})
	attrs["personality"] = inherited.get("personality", {})
	child["attributes"] = attrs
	var parents: Array = [String(player().get("id", ""))]
	if partner_id != "":
		parents.append(partner_id)
	child["family"] = {"parent_ids": parents}
	_register_child(child, partner_id)
	fam.erase("pregnancy")
	player()["family"] = fam
	return child

func _register_child(child: Dictionary, partner_id: String = "") -> void:
	var cid := String(child.get("id", ""))
	var npcs_arr: Array = state.world_delta.get("npcs", [])
	npcs_arr.append(child)
	state.world_delta["npcs"] = npcs_arr
	var fam: Dictionary = player().get("family", {})
	var kids: Array = fam.get("children_ids", [])
	if not kids.has(cid):
		kids.append(cid)
	fam["children_ids"] = kids
	player()["family"] = fam
	relations.ensure_relation(player(), cid)
	_link_siblings(child)
	_link_partner_child(child, partner_id)
	var lin: Array = state.legacy.get("lineage", [])
	lin.append({
		"name": String(child.get("name", "")),
		"birth_minutes": int(child.get("birth_minutes", 0)),
		"summary": "出生于 %s" % _home_region_id,
	})
	state.legacy["lineage"] = lin
	var hist: Array = state.legacy.get("history", [])
	hist.append({
		"kind": "birth",
		"name": String(child.get("name", "")),
		"birth_minutes": int(child.get("birth_minutes", 0)),
		"parent_ids": (child.get("family", {}) as Dictionary).get("parent_ids", []),
	})
	state.legacy["history"] = hist

## 族谱反查：把新生儿与其兄弟姐妹互链（双向 sibling_ids）。
func _link_siblings(child: Dictionary) -> void:
	var cid := String(child.get("id", ""))
	for other in children():
		var oid := String(other.get("id", ""))
		if oid == "" or oid == cid:
			continue
		var cf: Dictionary = child.get("family", {})
		var cs: Array = cf.get("sibling_ids", [])
		if not cs.has(oid):
			cs.append(oid)
		cf["sibling_ids"] = cs
		child["family"] = cf
		var of: Dictionary = other.get("family", {})
		var os: Array = of.get("sibling_ids", [])
		if not os.has(cid):
			os.append(cid)
		of["sibling_ids"] = os
		other["family"] = of

## 族谱反查：把新生儿挂到配偶名下（NPC.family.children_ids）。
func _link_partner_child(child: Dictionary, partner_id: String) -> void:
	if partner_id == "":
		return
	var partner := find_person(partner_id)
	if partner.is_empty():
		return
	var cid := String(child.get("id", ""))
	var pf: Dictionary = partner.get("family", {})
	var pkids: Array = pf.get("children_ids", [])
	if not pkids.has(cid):
		pkids.append(cid)
	pf["children_ids"] = pkids
	partner["family"] = pf

# --- 收养与监护（R51 / D11）---

## 养子女（player.family.adopted_ids）。
func adopted_children() -> Array:
	var out: Array = []
	for cid in player().get("family", {}).get("adopted_ids", []):
		var c := find_person(String(cid))
		if not c.is_empty():
			out.append(c)
	return out

## 收养一名子女：生成 NPC（独立序号段），登记为法定子女与养子女，记入家族史。
## 收养不写妊娠/出生记录，仅在 lineage/history 记「收养」条目。
func adopt_child(child_name: String = "", age: int = 3) -> Dictionary:
	_adopt_seq += 1
	var gender := "male" if rng.next_float() < 0.5 else "female"
	var child: Dictionary = npcs.generate(_adopt_seq + ADOPT_SEQ_BASE, {
		"world_seed": _seed, "region_id": _home_region_id,
		"now_minute": now_minutes(), "individualized": true, "lod_tier": 0,
		"age": maxi(0, age), "gender": gender,
	})
	if child_name != "":
		child["name"] = child_name
	child["stage"] = parenting.stage_of(maxi(0, age))
	child["adopted"] = true
	child["family"] = {"parent_ids": [String(player().get("id", ""))]}
	var cid := String(child.get("id", ""))
	var npcs_arr: Array = state.world_delta.get("npcs", [])
	npcs_arr.append(child)
	state.world_delta["npcs"] = npcs_arr
	var fam: Dictionary = player().get("family", {})
	var kids: Array = fam.get("children_ids", [])
	if not kids.has(cid):
		kids.append(cid)
	fam["children_ids"] = kids
	var adopted: Array = fam.get("adopted_ids", [])
	if not adopted.has(cid):
		adopted.append(cid)
	fam["adopted_ids"] = adopted
	player()["family"] = fam
	relations.ensure_relation(player(), cid)
	_link_siblings(child)
	var lin: Array = state.legacy.get("lineage", [])
	lin.append({
		"name": String(child.get("name", "")),
		"birth_minutes": int(child.get("birth_minutes", 0)),
		"summary": "收养于 %s" % _home_region_id,
	})
	state.legacy["lineage"] = lin
	var hist: Array = state.legacy.get("history", [])
	hist.append({
		"kind": "adopt",
		"name": String(child.get("name", "")),
		"adopt_minutes": now_minutes(),
		"parent_ids": [String(player().get("id", ""))],
	})
	state.legacy["history"] = hist
	return {"ok": true, "child": child}

## 指定监护人（player.family.guardian_ids，单值）。指定的对象须存在于世界。
func assign_guardian(person_id: String) -> Dictionary:
	if person_id == "" or find_person(person_id).is_empty():
		return {"ok": false, "reason": "person_not_found"}
	var fam: Dictionary = player().get("family", {})
	fam["guardian_ids"] = [person_id]
	player()["family"] = fam
	return {"ok": true, "guardian_ids": fam["guardian_ids"]}

## 已指定的监护人档案。
func guardians() -> Array:
	var out: Array = []
	for gid in player().get("family", {}).get("guardian_ids", []):
		var g := find_person(String(gid))
		if not g.is_empty():
			out.append(g)
	return out

## 未成年子女（年龄 < ADULT_AGE 且在世）。
func minor_children() -> Array:
	var out: Array = []
	var now := now_minutes()
	for c in children():
		if not bool(c.get("alive", true)):
			continue
		if _child_age(c, now) < ADULT_AGE:
			out.append(c)
	return out

func _child_age(child: Dictionary, now: int) -> int:
	var birth := int(child.get("birth_minutes", 0))
	return maxi(0, int(float(now - birth) / MINUTES_PER_YEAR))

## 未成年子女的法定监护人（R51.5）：优先已指定监护人，其次在世配偶/父母/成年子女/兄弟姐妹/熟人。
func legal_guardian() -> Dictionary:
	var minors: Array = []
	for c in minor_children():
		minors.append(String(c.get("id", "")))
	if minors.is_empty():
		return {"guardian": {}, "minors": [], "ok": false}
	var candidates: Array = []
	for g in guardians():
		candidates.append({"id": String(g.get("id", "")), "name": String(g.get("name", "")), "suitability": 95.0})
	var sid := String(player().get("family", {}).get("spouse_id", ""))
	if sid != "":
		candidates.append({"id": sid, "name": String(spouse().get("name", "")), "suitability": 85.0})
	for pid in player().get("family", {}).get("parent_ids", []):
		var p := find_person(String(pid))
		if not p.is_empty():
			candidates.append({"id": String(pid), "name": String(p.get("name", "")), "suitability": 88.0})
	for c in children():
		if bool(c.get("alive", true)) and _child_age(c, now_minutes()) >= ADULT_AGE:
			candidates.append({"id": String(c.get("id", "")), "name": String(c.get("name", "")), "suitability": 75.0})
	for sib in player().get("family", {}).get("sibling_ids", []):
		var s := find_person(String(sib))
		if not s.is_empty():
			candidates.append({"id": String(sib), "name": String(s.get("name", "")), "suitability": 65.0})
	for a in _acquaintances:
		candidates.append({"id": String(a.get("id", "")), "name": String(a.get("name", "")), "suitability": 45.0})
	return inheritance.guardianship(minors, candidates)

# --- 子女成长与早夭（R51.3/R51.4/R51.8）---

## 按游戏内时钟推进子女成长：整数年龄增长时做年度成长结算，成年后独立。
func _grow_children() -> Array:
	var events: Array = []
	var now := now_minutes()
	for c in children():
		if not bool(c.get("alive", true)):
			continue
		var age := _child_age(c, now)
		if age >= ADULT_AGE:
			if not bool(c.get("independent", false)):
				parenting.reach_adulthood(c)
				events.append({"type": "child_adult", "name": String(c.get("name", ""))})
			continue
		var grown := int(c.get("grown_age", -1))
		if age > grown:
			var care := float(c.get("care_quality", 60.0))
			for _y in range(grown + 1, age + 1):
				_grow_one_year(c, care)
			c["grown_age"] = age
			c["stage"] = parenting.stage_of(age)
	return events

## 单年成长：把 NPC 的 attributes.ability 作为基因写入 ParentingSystem 结算，再回写 properties。
func _grow_one_year(child: Dictionary, care: float) -> void:
	var attrs: Dictionary = child.get("attributes", {})
	child["ability"] = attrs.get("ability", {})
	parenting.raise_child(child, care, 60.0, null)
	attrs["ability"] = child.get("ability", {})
	child["attributes"] = attrs
	child.erase("ability")

## 未成年子女早夭（R51.8）：按推进时长折算年化概率，命中则标记死亡并记入家族史。
func _check_child_mortality(minutes: int) -> Array:
	var events: Array = []
	var minors := minor_children()
	if minors.is_empty():
		return events
	var years: float = float(minutes) / MINUTES_PER_YEAR
	var rate: float = clampf(ParentingScript.EARLY_DEATH_RATE * years, 0.0, ParentingScript.EARLY_DEATH_RATE)
	for c in minors:
		if rng.next_float() >= rate:
			continue
		c["alive"] = false
		c["death_minutes"] = now_minutes()
		events.append({"type": "child_death", "name": String(c.get("name", ""))})
		var hist: Array = state.legacy.get("history", [])
		hist.append({
			"kind": "child_death",
			"name": String(c.get("name", "")),
			"death_minutes": now_minutes(),
		})
		state.legacy["history"] = hist
	return events

## 跨月则结算名下房产（贷款本息/物业/租金/折旧/断供法拍）并回写财务镜像。
func _maybe_settle_property(prev_minutes: int, cur_minutes: int) -> Dictionary:
	if property.owned_properties(player()).is_empty():
		return {}
	if cur_minutes / (SETTLE_INTERVAL_DAYS * MINUTES_PER_DAY) <= prev_minutes / (SETTLE_INTERVAL_DAYS * MINUTES_PER_DAY):
		return {}
	var r: Dictionary = property.monthly_settle(player(), economy, account_id())
	sync_finances()
	return r

## 指定所在区域：登记为活动区并绑定气候带（供旅行/搬迁接线）。
func set_home_region(region_id: String, opts: Dictionary = {}) -> bool:
	if geo != null and geo.count() > 0 and not geo.has_node(region_id):
		return false
	_home_region_id = region_id
	if not opts.has("population"):
		opts = _geo_region_opts(region_id)
	regions.register_region(region_id, opts)
	regions.enter(region_id, now_minutes())
	if not weather.has_region(region_id):
		weather.register_region(region_id, _zone_for_region(region_id))
	_write_player_region(region_id)
	_listings.clear()
	_ensure_property_market()
	return true

## 区域视图（供地图/面板展示）：仅暴露非敏感展示字段。
func regions_view() -> Array:
	var out: Array = []
	if regions == null:
		return out
	for id in regions.region_ids():
		var r = regions.get_region(id)
		if r == null:
			continue
		out.append({
			"region_key": String(id),
			"population": r.population,
			"price_index": r.price_index,
			"economy": r.economy,
			"safety": r.safety,
			"climate": r.climate,
		})
	return out

## 当前区域天气快照（供天气面板）：condition/temperature/humidity/wind/phase[/warning]。
func weather_now() -> Dictionary:
	var rid: String = current_region_id()
	if rid == "" or weather == null or not weather.has_region(rid):
		return {}
	var now: int = now_minutes()
	var st = weather.state_at(rid, now)
	var minute: int = WeatherScript.minute_of_day(now)
	var out: Dictionary = {
		"condition": st.condition_name,
		"temperature": "%d°C" % int(round(st.temperature_c)),
		"humidity": "%d%%" % int(round(st.humidity_pct)),
		"wind": "%.1f m/s" % st.wind_ms,
		"phase": "白昼" if minute >= 360 and minute < 1080 else "夜晚",
		"zone": weather.climate_zone_name(weather.zone_of(rid)),
	}
	var warnings: Array = weather.disaster_warnings(rid, WeatherScript.day_of_minute(now))
	if not warnings.is_empty():
		out["warning"] = String(warnings[0].get("message", ""))
	return out

## 天气面板数据：当前天气 + 未来 7 日预报（structured rows）。
func weather_panel_data() -> Dictionary:
	var out: Dictionary = weather_now()
	if out.is_empty():
		return out
	out["forecast"] = weather_forecast_rows()
	return out

## 未来 N 日预报（供天气面板展示）：[{label, value}]。
func weather_forecast_rows(days: int = 7) -> Array:
	var rid: String = current_region_id()
	if rid == "" or weather == null or not weather.has_region(rid):
		return []
	var fc: Array = weather.forecast(rid, now_minutes(), 0, days)
	var out: Array = []
	for row in fc:
		var day: int = int(row.get("day", 0))
		var lead: int = int(row.get("lead", 0))
		var label: String = "今日" if lead == 0 else ("明日" if lead == 1 else _short_date(day))
		var hi: int = int(round(float(row.get("temperature_high_c", 0.0))))
		var lo: int = int(round(float(row.get("temperature_low_c", 0.0))))
		var prec: float = float(row.get("precipitation_mm", 0.0))
		out.append({
			"label": label,
			"value": "%s %d~%d°C 降水%.1fmm" % [String(row.get("condition_name", "")), lo, hi, prec],
		})
	return out

func _short_date(day_index: int) -> String:
	var cal: Dictionary = GregorianScript.from_absolute_minutes(day_index * MINUTES_PER_DAY)
	return "%d/%d" % [int(cal.get("month", 1)), int(cal.get("day", 1))]

## 把经济运行账户余额回写到 player.finances（最小货币单位 → 主单位）。
func sync_finances() -> void:
	var id := account_id()
	if not economy.has_account(id):
		return
	var scale := float(BaselineScript.MONEY_MINOR_SCALE)
	var f: Dictionary = player().get("finances", {})
	f["cash"] = float(economy.cash(id)) / scale
	f["bank"] = float(economy.bank(id)) / scale
	f["debt"] = float(economy.debt(id)) / scale
	player()["finances"] = f

## 推进 minutes 分钟的游戏内模拟（生理/营养/成瘾/寿命判定），并同步游戏内时钟。
## opts 可含 asleep / labor_intensity / age_years / fatal 等，透传给 Survival。
## 返回 {minutes, dead, dying, events}。
func advance(minutes: int, opts: Dictionary = {}) -> Dictionary:
	var events: Array = []
	if minutes <= 0:
		return {"minutes": 0, "dead": survival.is_dead(), "dying": survival.is_dying(), "events": events}
	var r: Dictionary = survival.advance(player(), minutes, opts)
	var before_minutes: int = now_minutes()
	# 游戏内时钟（存档字段）随模拟推进；UI 日历由 main 镜像到 WorldClock。
	var clock: Dictionary = state.clock
	clock["absolute_minutes"] = int(clock.get("absolute_minutes", 0)) + minutes
	# 活动区域随分钟推进（人口/经济日级结算）并写回存档增量；天气按当前时刻查询式演化，无需 tick。
	regions.tick_minute(int(clock["absolute_minutes"]))
	# 领域实体（案件/工程/灾害/催收/异常/手术）离线补算，随游戏内时钟推进。
	domain_wake.advance_to(int(clock["absolute_minutes"]))
	_persist_regions()
	_persist_survival()
	if bool(r.get("dead", false)) and not _inheritance_settled:
		settle_inheritance()
	if bool(r.get("dead", false)):
		events.append({"type": "death"})
	elif bool(r.get("dying", false)):
		events.append({"type": "dying"})
	else:
		# 生存：妊娠到期分娩。
		var born: Dictionary = _check_delivery()
		if not born.is_empty():
			events.append({"type": "birth", "name": String(born.get("name", ""))})
		# 持有房产按月结算（贷款/物业/租金/折旧/断供法拍）。
		_maybe_settle_property(before_minutes, now_minutes())
		# 子女成长（年度属性结算/成年独立）与早夭。
		events.append_array(_grow_children())
		events.append_array(_check_child_mortality(minutes))
		# 宠物随日推进（饥饿/健康/走失/寿终）。
		events.append_array(_advance_pets(minutes))
		# 精神健康：三维病程推进、压力触发、幸福与意义结算。
		events.append_array(_refresh_mental(minutes))
		# 精神追求：检查精神危机触发（R55.6）。
		events.append_array(_refresh_spirit())
		# 语言：长期未用按闲置天数衰减（R64）。
		_decay_languages(before_minutes, now_minutes())
		# 农业：作物按日生长、仓储按日损耗（R66）。
		_advance_farm(before_minutes, now_minutes())
	# 矿业/能源：能源价格按年周期演化（离线亦结算）。
	_mining_tick(before_minutes, now_minutes())
	# 农林牧渔：渔场资源恢复、林木按日生长。
	_primary_tick(before_minutes, now_minutes())
	_persist_mental()
	_persist_spirituality()
	_persist_language()
	_persist_farm()
	return {
		"minutes": minutes,
		"dead": bool(r.get("dead", false)),
		"dying": bool(r.get("dying", false)),
		"events": events,
	}

func is_dead() -> bool:
	return survival.is_dead()

func is_dying() -> bool:
	return survival.is_dying()
