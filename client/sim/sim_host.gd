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

const MINUTES_PER_DAY: int = 1440
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

var _seeded: bool = false
var _seed: int = 0
var _home_region_id: String = ""

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

## 建立世界运行时：种子确定性生成六级地理，登记玩家所在城市为活动区域（含气候带），
## 使区域人口/经济与天气随游戏内时钟演化（R5/R50、D1/D2）。地理不入档，同种子可复现。
func _ensure_world_geo() -> void:
	if state == null:
		return
	if geo.count() == 0:
		geo.generate(_seed)
	regions.configure_population(_seed)
	_home_region_id = _resolve_home_region_id()
	if _home_region_id != "" and not regions.has_region(_home_region_id):
		regions.register_region(_home_region_id, _geo_region_opts(_home_region_id))
		regions.enter(_home_region_id, now_minutes())
	if _home_region_id != "" and not weather.has_region(_home_region_id):
		weather.register_region(_home_region_id, _zone_for_region(_home_region_id))

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

## 玩家所在区域：由 player.nation 解析国家，取其首个核心城市；无效时降级首发默认国家。
func _resolve_home_region_id() -> String:
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
	# 游戏内时钟（存档字段）随模拟推进；UI 日历由 main 镜像到 WorldClock。
	var clock: Dictionary = state.clock
	clock["absolute_minutes"] = int(clock.get("absolute_minutes", 0)) + minutes
	# 活动区域随分钟推进（人口/经济日级结算）；天气按当前时刻查询式演化，无需 tick。
	regions.advance_now(minutes)
	regions.tick_minute(int(clock["absolute_minutes"]))
	if bool(r.get("dead", false)):
		events.append({"type": "death"})
	elif bool(r.get("dying", false)):
		events.append({"type": "dying"})
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
