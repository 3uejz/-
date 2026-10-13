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

const MINUTES_PER_DAY: int = 1440
## 所在城市熟人名册容量（首发单城社交/婚恋链接）。
const ACQUAINTANCE_COUNT: int = 8
## 所在城市在售房源数量（确定性生成，供看房/买房）。
const PROPERTY_LISTING_COUNT: int = 5
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
