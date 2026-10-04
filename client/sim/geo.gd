class_name GeoData
extends RefCounted
## 六级地理与多国差异模型（R3、R42；design D2）。
##
## 层级：国家 → 省/州 → 城市 → 区县 → 街道 → 建筑；建筑为最小可进入单元。
## 核心城市手工设计（manual=true），其余按世界种子程序生成，同种子可复现。
## 地理底图为现实地球（真实经纬度），允许按需修改；国家间在语言/法律/货币/证件/文化/时区上完整差异。
##
## 本类是 headless 可测的纯模型，不依赖 Autoload；数值默认见 client/sim/baseline.gd。

const RngScript = preload("res://sim/rng.gd")
const BaselineScript = preload("res://sim/baseline.gd")

## 六级地理层级（design.md Data Models: GeographicLevel）。
enum GeographicLevel { COUNTRY = 0, PROVINCE = 1, CITY = 2, DISTRICT = 3, STREET = 4, BUILDING = 5 }

const LEVEL_NAMES: Array = ["国家", "省/州", "城市", "区县", "街道", "建筑"]
const LEVEL_CODES: Array = ["country", "province", "city", "district", "street", "building"]

# FNV-1a 64 位常量（补码有符号十进制，避免十六进制字面量超过 INT64_MAX 解析失败）。
const FNV_OFFSET: int = -3750763034362895579  # 0xCBF29CE484222325
const FNV_PRIME: int = 1099511628211          # 0x100000001B3
const MASK: int = -1                          # 0xFFFFFFFFFFFFFFFF

# 程序生成名称用的后缀池（仅生成区用；核心城市均为真实名称）。
const PROVINCE_SUFFIXES: Array = ["省", "州", "郡", "府", "道"]
const CITY_SUFFIXES: Array = ["市", "城", "镇"]
const DISTRICT_SUFFIXES: Array = ["区", "县", "旗"]
const STREET_SUFFIXES: Array = ["街道", "路", "巷", "大道"]
const BUILDING_SUFFIXES: Array = ["楼", "大厦", "中心", "馆", "站", "园", "阁", "苑"]
const BASE_SYLLABLES: Array = ["安", "宁", "华", "兴", "昌", "永", "新", "和", "平", "泰", "清", "明", "云", "山", "河", "海", "金", "玉", "德", "福"]

# 国家档案：语言、法律、货币、证件、文化、时区（R3.8）。cities 为核心手工城市（真实经纬度）。
const CORE_COUNTRIES: Array = [
	{"code": "CN", "name": "中国", "languages": ["zh-CN"], "legal_system": "civil_law", "currency": "CNY", "timezone": "Asia/Shanghai", "utc_offset_minutes": 480, "documents": ["id_card", "passport", "driver_license"], "culture": ["集体主义", "儒家", "中餐文化"], "drive_side": "right", "price_scale": 1.0, "cities": [
		{"province": "北京市", "name": "北京", "key": "beijing", "lat": 39.9042, "lon": 116.4074, "population": 21540000, "districts": ["东城区", "西城区", "朝阳区", "海淀区"]},
		{"province": "上海市", "name": "上海", "key": "shanghai", "lat": 31.2304, "lon": 121.4737, "population": 24870000, "districts": ["黄浦区", "浦东新区", "徐汇区"]},
		{"province": "广东省", "name": "广州", "key": "guangzhou", "lat": 23.1291, "lon": 113.2644, "population": 18680000, "districts": ["天河区", "越秀区", "海珠区"]},
		{"province": "广东省", "name": "深圳", "key": "shenzhen", "lat": 22.5431, "lon": 114.0579, "population": 17560000, "districts": ["福田区", "南山区", "罗湖区"]},
	]},
	{"code": "US", "name": "美国", "languages": ["en-US"], "legal_system": "common_law", "currency": "USD", "timezone": "America/New_York", "utc_offset_minutes": -300, "documents": ["state_id", "passport", "driver_license", "ssn"], "culture": ["个人主义", "多元移民", "快餐文化"], "drive_side": "right", "price_scale": 1.6, "cities": [
		{"province": "纽约州", "name": "纽约", "key": "new_york", "lat": 40.7128, "lon": -74.0060, "population": 8804000, "districts": ["曼哈顿", "布鲁克林", "皇后区"]},
		{"province": "加利福尼亚州", "name": "洛杉矶", "key": "los_angeles", "lat": 34.0522, "lon": -118.2437, "population": 3979000, "districts": ["好莱坞", "圣莫尼卡", "长滩"]},
	]},
	{"code": "JP", "name": "日本", "languages": ["ja-JP"], "legal_system": "civil_law", "currency": "JPY", "timezone": "Asia/Tokyo", "utc_offset_minutes": 540, "documents": ["my_number", "passport", "driver_license"], "culture": ["集团主义", "神道佛教", "和食文化"], "drive_side": "left", "price_scale": 1.3, "cities": [
		{"province": "东京都", "name": "东京", "key": "tokyo", "lat": 35.6762, "lon": 139.6503, "population": 13960000, "districts": ["新宿区", "涩谷区", "港区"]},
	]},
	{"code": "GB", "name": "英国", "languages": ["en-GB"], "legal_system": "common_law", "currency": "GBP", "timezone": "Europe/London", "utc_offset_minutes": 0, "documents": ["nino", "passport", "driver_license"], "culture": ["绅士文化", "下午茶", "足球文化"], "drive_side": "left", "price_scale": 1.7, "cities": [
		{"province": "英格兰", "name": "伦敦", "key": "london", "lat": 51.5074, "lon": -0.1278, "population": 8982000, "districts": ["威斯敏斯特", "卡姆登", "格林威治"]},
	]},
	{"code": "FR", "name": "法国", "languages": ["fr-FR"], "legal_system": "civil_law", "currency": "EUR", "timezone": "Europe/Paris", "utc_offset_minutes": 60, "documents": ["cni", "passport", "driver_license"], "culture": ["自由平等博爱", "葡萄酒文化", "时尚"], "drive_side": "right", "price_scale": 1.5, "cities": [
		{"province": "法兰西岛", "name": "巴黎", "key": "paris", "lat": 48.8566, "lon": 2.3522, "population": 2148000, "districts": ["第一区", "第八区", "蒙马特"]},
	]},
	{"code": "DE", "name": "德国", "languages": ["de-DE"], "legal_system": "civil_law", "currency": "EUR", "timezone": "Europe/Berlin", "utc_offset_minutes": 60, "documents": ["personalausweis", "passport", "driver_license"], "culture": ["秩序", "啤酒文化", "工业传统"], "drive_side": "right", "price_scale": 1.4, "cities": [
		{"province": "柏林州", "name": "柏林", "key": "berlin", "lat": 52.5200, "lon": 13.4050, "population": 3645000, "districts": ["米特区", "夏洛滕堡", "克罗伊茨贝格"]},
	]},
	{"code": "SG", "name": "新加坡", "languages": ["en-SG", "zh-CN", "ms-SG"], "legal_system": "common_law", "currency": "SGD", "timezone": "Asia/Singapore", "utc_offset_minutes": 480, "documents": ["nric", "passport", "driver_license"], "culture": ["多元种族", "花园城市", "小贩文化"], "drive_side": "left", "price_scale": 1.8, "cities": [
		{"province": "新加坡", "name": "新加坡", "key": "singapore", "lat": 1.3521, "lon": 103.8198, "population": 5704000, "districts": ["中区", "东区", "西区"]},
	]},
	{"code": "AU", "name": "澳大利亚", "languages": ["en-AU"], "legal_system": "common_law", "currency": "AUD", "timezone": "Australia/Sydney", "utc_offset_minutes": 600, "documents": ["medicare", "passport", "driver_license"], "culture": ["户外文化", "多元移民", "咖啡文化"], "drive_side": "left", "price_scale": 1.6, "cities": [
		{"province": "新南威尔士州", "name": "悉尼", "key": "sydney", "lat": -33.8688, "lon": 151.2093, "population": 5312000, "districts": ["中央商务区", "邦迪", "帕拉马塔"]},
	]},
	{"code": "RU", "name": "俄罗斯", "languages": ["ru-RU"], "legal_system": "civil_law", "currency": "RUB", "timezone": "Europe/Moscow", "utc_offset_minutes": 180, "documents": ["internal_passport", "passport", "driver_license"], "culture": ["东正教", "文学传统", "伏特加文化"], "drive_side": "right", "price_scale": 1.1, "cities": [
		{"province": "莫斯科市", "name": "莫斯科", "key": "moscow", "lat": 55.7558, "lon": 37.6173, "population": 12615000, "districts": ["中央区", "阿尔巴特区", "特维尔区"]},
	]},
	{"code": "IN", "name": "印度", "languages": ["hi-IN", "en-IN"], "legal_system": "common_law", "currency": "INR", "timezone": "Asia/Kolkata", "utc_offset_minutes": 330, "documents": ["aadhaar", "passport", "driver_license"], "culture": ["种姓传统", "印度教", "香料文化"], "drive_side": "left", "price_scale": 0.8, "cities": [
		{"province": "马哈拉施特拉邦", "name": "孟买", "key": "mumbai", "lat": 19.0760, "lon": 72.8777, "population": 20411000, "districts": ["南区", "西区", "安泰里"]},
	]},
	{"code": "BR", "name": "巴西", "languages": ["pt-BR"], "legal_system": "civil_law", "currency": "BRL", "timezone": "America/Sao_Paulo", "utc_offset_minutes": -180, "documents": ["cpf", "passport", "driver_license"], "culture": ["桑巴", "足球", "狂欢节"], "drive_side": "right", "price_scale": 0.9, "cities": [
		{"province": "圣保罗州", "name": "圣保罗", "key": "sao_paulo", "lat": -23.5505, "lon": -46.6333, "population": 12330000, "districts": ["中心区", "保利斯塔", "伊比拉布埃拉"]},
	]},
	{"code": "ZA", "name": "南非", "languages": ["en-ZA", "af-ZA"], "legal_system": "common_law", "currency": "ZAR", "timezone": "Africa/Johannesburg", "utc_offset_minutes": 120, "documents": ["id_book", "passport", "driver_license"], "culture": ["彩虹之国", "部落传统", "葡萄酒"], "drive_side": "left", "price_scale": 0.9, "cities": [
		{"province": "西开普省", "name": "开普敦", "key": "cape_town", "lat": -33.9249, "lon": 18.4241, "population": 4618000, "districts": ["市中心", "桌山", "坎普斯湾"]},
	]},
	{"code": "AE", "name": "阿联酋", "languages": ["ar-AE", "en-AE"], "legal_system": "islamic_law", "currency": "AED", "timezone": "Asia/Dubai", "utc_offset_minutes": 240, "documents": ["emirates_id", "passport", "driver_license"], "culture": ["伊斯兰", "贝都因传统", "奢华消费"], "drive_side": "right", "price_scale": 1.7, "cities": [
		{"province": "迪拜酋长国", "name": "迪拜", "key": "dubai", "lat": 25.2048, "lon": 55.2708, "population": 3331000, "districts": ["德伊勒", "布尔迪拜", "朱美拉"]},
	]},
	{"code": "KR", "name": "韩国", "languages": ["ko-KR"], "legal_system": "civil_law", "currency": "KRW", "timezone": "Asia/Seoul", "utc_offset_minutes": 540, "documents": ["resident_id", "passport", "driver_license"], "culture": ["宗家传统", "泡菜文化", "应援文化"], "drive_side": "right", "price_scale": 1.3, "cities": [
		{"province": "首尔特别市", "name": "首尔", "key": "seoul", "lat": 37.5665, "lon": 126.9780, "population": 9729000, "districts": ["江南区", "钟路区", "麻浦区"]},
	]},
	{"code": "EG", "name": "埃及", "languages": ["ar-EG"], "legal_system": "islamic_law", "currency": "EGP", "timezone": "Africa/Cairo", "utc_offset_minutes": 120, "documents": ["national_id", "passport", "driver_license"], "culture": ["古埃及文明", "伊斯兰", "尼罗河农业"], "drive_side": "right", "price_scale": 0.6, "cities": [
		{"province": "开罗省", "name": "开罗", "key": "cairo", "lat": 30.0444, "lon": 31.2357, "population": 9540000, "districts": ["市中心", "吉萨", "新开罗"]},
	]},
	{"code": "MX", "name": "墨西哥", "languages": ["es-MX"], "legal_system": "civil_law", "currency": "MXN", "timezone": "America/Mexico_City", "utc_offset_minutes": -360, "documents": ["curp", "passport", "driver_license"], "culture": ["玛雅阿兹特克", "玉米文化", "亡灵节"], "drive_side": "right", "price_scale": 0.8, "cities": [
		{"province": "墨西哥城", "name": "墨西哥城", "key": "mexico_city", "lat": 19.4326, "lon": -99.1332, "population": 9209000, "districts": ["历史中心", "波朗科", "科约阿坎"]},
	]},
]


## 国家档案（R3.8：语言/法律/货币/证件/文化/时区）。
class CountryProfile:
	extends RefCounted

	var code: String = ""
	var name: String = ""
	var languages: Array = []
	var legal_system: String = ""
	var currency: String = ""
	var timezone: String = ""
	var utc_offset_minutes: int = 0
	var documents: Array = []
	var culture: Array = []
	var drive_side: String = "right"
	var price_scale: float = 1.0
	var capital_lat: float = 0.0
	var city_ids: Array = []

	func to_dict() -> Dictionary:
		return {
			"code": code, "name": name, "languages": languages.duplicate(),
			"legal_system": legal_system, "currency": currency,
			"timezone": timezone, "utc_offset_minutes": utc_offset_minutes,
			"documents": documents.duplicate(), "culture": culture.duplicate(),
			"drive_side": drive_side, "price_scale": price_scale,
			"city_ids": city_ids.duplicate(),
		}


## 单个地理节点（design.md：区域属性含人口、经济、物价系数、气候、治安、就业率、文化）。
class GeoNode:
	extends RefCounted

	var id: String = ""
	var level: int = 0
	var name: String = ""
	var aliases: Array = []
	var parent_id: String = ""
	var country_code: String = ""
	var location: Dictionary = {}      # geo_point: {lat, lon, alt_m?}
	var attributes: Dictionary = {}    # population/economy/price_index/climate/safety/employment/culture
	var children: Array = []
	var manual: bool = false           # 核心手工设计（R3.5）
	var description: String = ""
	var open_hours: Dictionary = {}    # 开放时间（建筑/地点）
	var available_verbs: Array = []    # 可用动词（R3.6）
	var price_system: Dictionary = {}  # 价格体系（R3.6）

	func to_dict() -> Dictionary:
		return {
			"id": id, "level": level, "level_name": GeoData.LEVEL_NAMES[level] if level < GeoData.LEVEL_NAMES.size() else "",
			"name": name, "aliases": aliases.duplicate(), "parent_id": parent_id,
			"country_code": country_code, "location": location.duplicate(),
			"attributes": attributes.duplicate(true), "manual": manual,
			"description": description, "open_hours": open_hours.duplicate(true),
			"available_verbs": available_verbs.duplicate(), "price_system": price_system.duplicate(true),
		}


var seed: int = 0
var _nodes: Dictionary = {}         # id -> GeoNode
var _countries: Dictionary = {}     # code -> CountryProfile


## 按世界种子生成全球地理。核心城市手工，其余程序生成；同种子结果可复现。
func generate(world_seed: int = 0) -> void:
	_nodes.clear()
	_countries.clear()
	seed = world_seed
	for country_def in CORE_COUNTRIES:
		_build_country(country_def)
	_ensure_minimum_locations()


# --- 构建 ---

func _build_country(def: Dictionary) -> void:
	var code: String = String(def["code"])
	var cc: String = code.to_lower()
	var profile := CountryProfile.new()
	profile.code = code
	profile.name = String(def["name"])
	profile.languages = (def["languages"] as Array).duplicate()
	profile.legal_system = String(def["legal_system"])
	profile.currency = String(def["currency"])
	profile.timezone = String(def["timezone"])
	profile.utc_offset_minutes = int(def["utc_offset_minutes"])
	profile.documents = (def["documents"] as Array).duplicate()
	profile.culture = (def["culture"] as Array).duplicate()
	profile.drive_side = String(def["drive_side"])
	profile.price_scale = float(def["price_scale"])
	_countries[code] = profile

	var cities: Array = def["cities"]
	var capital: Dictionary = cities[0]
	profile.capital_lat = float(capital["lat"])
	var country_node := _add_node(cc, GeographicLevel.COUNTRY, profile.name, "", code,
		float(capital["lat"]), float(capital["lon"]), true,
		{"population": _sum_city_population(cities), "economy": 0.7, "price_index": profile.price_scale,
		"climate": _climate_for_lat(float(capital["lat"])), "safety": 70.0, "employment": 0.93,
		"culture": profile.culture.duplicate(), "currency": profile.currency, "timezone_offset_minutes": profile.utc_offset_minutes})
	country_node.aliases = [String(capital.get("name", "")) + "所在国"]
	country_node.description = "%s（%s），货币 %s，时区 %s。" % [profile.name, code, profile.currency, profile.timezone]

	# 核心手工城市：真实经纬度与真实行政区。
	for city_def in cities:
		_build_manual_city(profile, country_node, city_def)

	# 程序生成其余区域（同种子可复现）。
	_build_generated_regions(profile, country_node, cities)


func _build_manual_city(profile: CountryProfile, country_node: GeoNode, city_def: Dictionary) -> void:
	var cc: String = profile.code.to_lower()
	var city_key: String = String(city_def["key"])
	var province_id: String = "%s.%s.prov" % [cc, city_key]
	var city_id: String = "%s.%s" % [cc, city_key]
	var lat: float = float(city_def["lat"])
	var lon: float = float(city_def["lon"])
	var province_name: String = String(city_def["province"])
	var city_name: String = String(city_def["name"])
	var pop: int = int(city_def["population"])

	_add_node(province_id, GeographicLevel.PROVINCE, province_name, country_node.id, profile.code, lat, lon, true,
		_gen_region_attributes(profile, GeographicLevel.PROVINCE, pop * 4))
	var city_node := _add_node(city_id, GeographicLevel.CITY, city_name, province_id, profile.code, lat, lon, true,
		_gen_region_attributes(profile, GeographicLevel.CITY, pop))
	city_node.aliases = [city_name + "市", city_key]
	city_node.description = "%s%s，人口约 %d 万。" % [province_name, city_name, int(round(float(pop) / 10000.0))]
	(city_node.available_verbs as Array).append_array(["去", "看", "居住", "工作", "求职"])
	profile.city_ids.append(city_id)

	var districts: Array = city_def["districts"]
	for di in districts.size():
		var district_id: String = "%s.d%d" % [city_id, di]
		var district_name: String = String(districts[di])
		_add_node(district_id, GeographicLevel.DISTRICT, district_name, city_id, profile.code,
			_jitter(lat, di), _jitter(lon, di + 1), true,
			_gen_region_attributes(profile, GeographicLevel.DISTRICT, int(pop / districts.size())))
		# 每个核心区县生成若干真实命名的街道与建筑，保证建筑为最小可进入单元。
		for si in 2:
			var street_id: String = "%s.s%d" % [district_id, si]
			var street_name: String = "%s%s路" % [district_name, BASE_SYLLABLES[(di * 2 + si) % BASE_SYLLABLES.size()]]
			_add_node(street_id, GeographicLevel.STREET, street_name, district_id, profile.code,
				_jitter(lat, di + si + 2), _jitter(lon, di + si + 3), true,
				_gen_region_attributes(profile, GeographicLevel.STREET, int(pop / (districts.size() * 2))))
			for bi in 2:
				var building_id: String = "%s.b%d" % [street_id, bi]
				var building_name: String = "%s%s号%s" % [street_name, str(bi + 1), BUILDING_SUFFIXES[(di + si + bi) % BUILDING_SUFFIXES.size()]]
				var bnode := _add_node(building_id, GeographicLevel.BUILDING, building_name, street_id, profile.code,
					_jitter(lat, di + si + bi + 5), _jitter(lon, di + si + bi + 6), true,
					_gen_region_attributes(profile, GeographicLevel.BUILDING, 10 + di + si + bi))
				bnode.open_hours = {"start_minute": 0, "end_minute": 1440}
				bnode.available_verbs = ["进入", "看", "使用"]
				bnode.price_system = {"currency": profile.currency, "scale": profile.price_scale}


func _build_generated_regions(profile: CountryProfile, country_node: GeoNode, core_cities: Array) -> void:
	var rng = _rng_for("fill:%s:%d" % [profile.code, seed])
	var capital: Dictionary = core_cities[0]
	var base_lat: float = float(capital["lat"])
	var base_lon: float = float(capital["lon"])
	var province_count: int = 2 + _rand_int(rng, 3)
	for pi in province_count:
		var province_id: String = "%s.gen.p%d" % [profile.code.to_lower(), pi]
		var province_name: String = _gen_name(rng, PROVINCE_SUFFIXES)
		var plat: float = _clamp_lat(base_lat + (rng.next_float() - 0.5) * 10.0)
		var plon: float = _wrap_lon(base_lon + (rng.next_float() - 0.5) * 14.0)
		var ppop: int = 500000 + _rand_int(rng, 8000000)
		_add_node(province_id, GeographicLevel.PROVINCE, province_name, country_node.id, profile.code, plat, plon, false,
			_gen_region_attributes(profile, GeographicLevel.PROVINCE, ppop))

		var city_count: int = 1 + _rand_int(rng, 2)
		for ci in city_count:
			var city_id: String = "%s.gen.c%d" % [province_id, ci]
			var city_name: String = _gen_name(rng, CITY_SUFFIXES)
			var clat: float = _clamp_lat(plat + (rng.next_float() - 0.5) * 4.0)
			var clon: float = _wrap_lon(plon + (rng.next_float() - 0.5) * 5.0)
			var cpop: int = 80000 + _rand_int(rng, 2500000)
			_add_node(city_id, GeographicLevel.CITY, city_name, province_id, profile.code, clat, clon, false,
				_gen_region_attributes(profile, GeographicLevel.CITY, cpop))
			profile.city_ids.append(city_id)

			var district_count: int = 2 + _rand_int(rng, 3)
			for di in district_count:
				var district_id: String = "%s.d%d" % [city_id, di]
				_add_node(district_id, GeographicLevel.DISTRICT, _gen_name(rng, DISTRICT_SUFFIXES), city_id, profile.code,
					_clamp_lat(clat + (rng.next_float() - 0.5) * 1.0), _wrap_lon(clon + (rng.next_float() - 0.5) * 1.2), false,
					_gen_region_attributes(profile, GeographicLevel.DISTRICT, int(cpop / district_count)))
				var street_count: int = 1 + _rand_int(rng, 2)
				for si in street_count:
					var street_id: String = "%s.s%d" % [district_id, si]
					var slat: float = _clamp_lat(clat + (rng.next_float() - 0.5) * 0.4)
					var slon: float = _wrap_lon(clon + (rng.next_float() - 0.5) * 0.5)
					_add_node(street_id, GeographicLevel.STREET, _gen_name(rng, STREET_SUFFIXES), district_id, profile.code,
						slat, slon, false, _gen_region_attributes(profile, GeographicLevel.STREET, int(cpop / (district_count * 3))))
					var building_count: int = 2 + _rand_int(rng, 3)
					for bi in building_count:
						var building_id: String = "%s.b%d" % [street_id, bi]
						var bnode := _add_node(building_id, GeographicLevel.BUILDING, _gen_name(rng, BUILDING_SUFFIXES), street_id, profile.code,
							_clamp_lat(slat + (rng.next_float() - 0.5) * 0.1), _wrap_lon(slon + (rng.next_float() - 0.5) * 0.12), false,
							_gen_region_attributes(profile, GeographicLevel.BUILDING, 5 + _rand_int(rng, 200)))
						bnode.open_hours = {"start_minute": 0, "end_minute": 1440}
						bnode.available_verbs = ["进入", "看", "使用"]
						bnode.price_system = {"currency": profile.currency, "scale": profile.price_scale}


## 兜底：若生成数量不足 R3.2 下限，则补充程序生成的省/市/区/街/建筑。
func _ensure_minimum_locations() -> void:
	var guard: int = 0
	while count() < BaselineScript.GEO_MIN_TOTAL_LOCATIONS and guard < 100:
		guard += 1
		var rng = _rng_for("pad:%d:%d" % [seed, guard])
		var country_codes: Array = _countries.keys()
		var code: String = String(country_codes[guard % country_codes.size()])
		var profile: CountryProfile = _countries[code]
		var cc: String = code.to_lower()
		var country_node: GeoNode = _nodes.get(cc)
		var lat: float = float(country_node.location.get("lat", 0.0))
		var lon: float = float(country_node.location.get("lon", 0.0))
		var pid: String = "%s.pad%d" % [cc, guard]
		_add_node(pid, GeographicLevel.PROVINCE, _gen_name(rng, PROVINCE_SUFFIXES), cc, profile.code,
			_clamp_lat(lat + (rng.next_float() - 0.5) * 6.0), _wrap_lon(lon + (rng.next_float() - 0.5) * 8.0), false,
			_gen_region_attributes(profile, GeographicLevel.PROVINCE, 100000 + _rand_int(rng, 2000000)))
		var cid: String = "%s.c0" % pid
		_add_node(cid, GeographicLevel.CITY, _gen_name(rng, CITY_SUFFIXES), pid, profile.code,
			_clamp_lat(lat + (rng.next_float() - 0.5) * 2.0), _wrap_lon(lon + (rng.next_float() - 0.5) * 3.0), false,
			_gen_region_attributes(profile, GeographicLevel.CITY, 50000 + _rand_int(rng, 400000)))
		for i in 4:
			var did: String = "%s.d%d" % [cid, i]
			_add_node(did, GeographicLevel.DISTRICT, _gen_name(rng, DISTRICT_SUFFIXES), cid, profile.code,
				_clamp_lat(lat), _wrap_lon(lon), false, _gen_region_attributes(profile, GeographicLevel.DISTRICT, 20000))
			for j in 4:
				var sid: String = "%s.s%d" % [did, j]
				_add_node(sid, GeographicLevel.STREET, _gen_name(rng, STREET_SUFFIXES), did, profile.code,
					_clamp_lat(lat), _wrap_lon(lon), false, _gen_region_attributes(profile, GeographicLevel.STREET, 5000))
				for k in 4:
					_add_node("%s.b%d" % [sid, k], GeographicLevel.BUILDING, _gen_name(rng, BUILDING_SUFFIXES), sid, profile.code,
						_clamp_lat(lat), _wrap_lon(lon), false, _gen_region_attributes(profile, GeographicLevel.BUILDING, 20))


# --- 节点 ---

func _add_node(id: String, level: int, name: String, parent_id: String, country_code: String,
		lat: float, lon: float, manual: bool, attributes: Dictionary) -> GeoNode:
	var node := GeoNode.new()
	node.id = id
	node.level = level
	node.name = name
	node.parent_id = parent_id
	node.country_code = country_code
	node.location = {"lat": lat, "lon": lon}
	node.manual = manual
	node.attributes = attributes
	_nodes[id] = node
	if not parent_id.is_empty() and _nodes.has(parent_id):
		var parent: GeoNode = _nodes[parent_id]
		if not parent.children.has(id):
			parent.children.append(id)
	return node


# --- 属性与命名生成 ---

func _gen_region_attributes(profile: CountryProfile, level: int, population: int) -> Dictionary:
	var rng = _rng_for("attr:%s:%d:%d:%d" % [profile.code, level, population, seed])
	return {
		"population": maxi(0, population),
		"economy": clampf(0.2 + rng.next_float() * 0.8, 0.0, 1.0),
		"price_index": profile.price_scale * (0.85 + rng.next_float() * 0.3),
		"climate": _climate_for_lat(profile.capital_lat),
		"safety": clampf(40.0 + rng.next_float() * 55.0, 0.0, 100.0),
		"employment": clampf(0.82 + rng.next_float() * 0.15, 0.0, 1.0),
		"culture": profile.culture.duplicate(),
		"currency": profile.currency,
		"timezone_offset_minutes": profile.utc_offset_minutes,
	}

func _climate_for_lat(lat: float) -> String:
	var a: float = absf(lat)
	if a < 23.5:
		return "tropical"
	if a < 35.0:
		return "subtropical"
	if a < 50.0:
		return "temperate"
	if a < 66.5:
		return "cold"
	return "polar"

func _gen_name(rng, suffixes: Array) -> String:
	var base: String = String(BASE_SYLLABLES[_rand_int(rng, BASE_SYLLABLES.size())])
	if rng.next_float() < 0.5:
		base += String(BASE_SYLLABLES[_rand_int(rng, BASE_SYLLABLES.size())])
	return base + String(suffixes[_rand_int(rng, suffixes.size())])

func _rand_int(rng, count: int) -> int:
	if count <= 0:
		return 0
	return int(floor(rng.next_float() * float(count))) % count

func _jitter(base: float, step: int) -> float:
	# 确定性微偏移，避免同一城市各区县坐标完全重合（不依赖 rng，便于核心城市稳定）。
	var delta: float = (float(step % 7) - 3.0) * 0.01
	return base + delta

func _clamp_lat(lat: float) -> float:
	return clampf(lat, -89.9, 89.9)

func _wrap_lon(lon: float) -> float:
	return fposmod(lon + 180.0, 360.0) - 180.0

func _sum_city_population(cities: Array) -> int:
	var total: int = 0
	for c in cities:
		total += int(c["population"])
	return total


# --- 查询 ---

func count() -> int:
	return _nodes.size()

func has_node(id: String) -> bool:
	return _nodes.has(id)

func get_node(id: String) -> GeoNode:
	return _nodes.get(id)

func node_ids() -> Array:
	return _nodes.keys()

func children_of(id: String) -> Array:
	var node: GeoNode = _nodes.get(id)
	return node.children.duplicate() if node != null else []

func nodes_at_level(level: int) -> Array:
	var out: Array = []
	for id in _nodes.keys():
		if (_nodes[id] as GeoNode).level == level:
			out.append(id)
	return out

func find_by_name(name: String, level: int = -1) -> Array:
	var out: Array = []
	for id in _nodes.keys():
		var node: GeoNode = _nodes[id]
		if level >= 0 and node.level != level:
			continue
		if node.name == name or node.aliases.has(name):
			out.append(id)
	return out

func country_of(id: String) -> String:
	var node: GeoNode = _nodes.get(id)
	return node.country_code if node != null else ""

## 返回从根到该节点的 id 路径（含自身）。
func path_of(id: String) -> Array:
	var path: Array = []
	var cursor: String = id
	while not cursor.is_empty() and _nodes.has(cursor):
		path.push_front(cursor)
		cursor = (_nodes[cursor] as GeoNode).parent_id
	return path

func country_profile(code: String) -> CountryProfile:
	return _countries.get(code)

func countries() -> Array:
	return _countries.keys()

## 某国当地时间（分钟）：UTC 分钟 + 标准时偏移。
func local_minute(country_code: String, utc_minute: int) -> int:
	var profile: CountryProfile = _countries.get(country_code)
	if profile == null:
		return utc_minute
	return utc_minute + profile.utc_offset_minutes

func currency_of(country_code: String) -> String:
	var profile: CountryProfile = _countries.get(country_code)
	return profile.currency if profile != null else ""

## 在指定层级中查找距给定坐标最近的节点。
func nearest(lat: float, lon: float, level: int) -> GeoNode:
	var best: GeoNode = null
	var best_d: float = INF
	for id in _nodes.keys():
		var node: GeoNode = _nodes[id]
		if level >= 0 and node.level != level:
			continue
		var d: float = distance_km(lat, lon, float(node.location.get("lat", 0.0)), float(node.location.get("lon", 0.0)))
		if d < best_d:
			best_d = d
			best = node
	return best

## 确定性签名：所有节点 id 排序拼接，用于同种子可复现校验。
func signature() -> String:
	var ids: Array = _nodes.keys()
	ids.sort()
	return "|".join(PackedStringArray(ids))


# --- 距离与随机 ---

## Haversine 球面距离（公里）；入参为经纬度或含 lat/lon 的字典（geo_point）。
static func distance_km(a, b, c: float = NAN, d: float = NAN) -> float:
	var lat1: float
	var lon1: float
	var lat2: float
	var lon2: float
	if a is Dictionary and b is Dictionary:
		lat1 = float((a as Dictionary).get("lat", 0.0))
		lon1 = float((a as Dictionary).get("lon", 0.0))
		lat2 = float((b as Dictionary).get("lat", 0.0))
		lon2 = float((b as Dictionary).get("lon", 0.0))
	else:
		lat1 = float(a)
		lon1 = float(b)
		lat2 = float(c)
		lon2 = float(d)
	var p1: float = deg_to_rad(lat1)
	var p2: float = deg_to_rad(lat2)
	var dp: float = deg_to_rad(lat2 - lat1)
	var dl: float = deg_to_rad(lon2 - lon1)
	var h: float = sin(dp / 2.0) * sin(dp / 2.0) + cos(p1) * cos(p2) * sin(dl / 2.0) * sin(dl / 2.0)
	return BaselineScript.effective_earth_radius_km() * 2.0 * atan2(sqrt(h), sqrt(maxf(0.0, 1.0 - h)))


## 稳定 64 位字符串散列（FNV-1a），避免依赖引擎 hash() 的版本差异。
static func stable_hash(text: String) -> int:
	var h: int = FNV_OFFSET
	for i in text.length():
		h = h ^ text.unicode_at(i)
		h = (h * FNV_PRIME) & MASK
	return h

func _rng_for(key: String):
	return RngScript.new(stable_hash(key + ":" + str(seed)))
