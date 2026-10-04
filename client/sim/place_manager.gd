class_name PlaceManager
extends RefCounted
## 场所类型与查询（R3.6、R42.3、R42.4；design D2）。
##
## 维护 13 大类、100+ 类场所类型（design：场所类型为 Resource 语义的纯模型），
## 每类定义可用动词、开放时间、价格体系、容量、安全与 3D 场景/插画绑定。
## 场所实例绑定到六级地理的建筑节点，供地图与动词系统查询。
##
## headless 可测的纯模型，不依赖 Autoload；数值默认见 client/sim/baseline.gd。

const GeoDataScript = preload("res://sim/geo.gd")
const SplitMix64Script = preload("res://sim/rng.gd")

## 13 类场所（design D2 场所类型节选类别）。
enum PlaceCategory { HOUSING = 0, FOOD, RETAIL, MEDICAL, EDUCATION, GOVERNMENT, TRANSPORT, ENTERTAINMENT, RELIGIOUS, INDUSTRY, FINANCE, NATURE, SPECIAL }

const CATEGORY_CODES: Array = ["housing", "food", "retail", "medical", "education", "government", "transport", "entertainment", "religious", "industry", "finance", "nature", "special"]
const CATEGORY_NAMES: Array = ["居住", "餐饮", "零售", "医疗", "教育", "政务", "交通", "文娱", "宗教", "产业", "金融", "自然", "特殊"]

## 场所类型目录：类别 → {类型键: 名称}，共 13×8 = 104 类（R42.3：不少于 100 类）。
const PLACE_CATALOG: Dictionary = {
	"housing": {"apartment": "公寓", "community": "小区", "villa": "别墅", "dorm": "宿舍", "nursing_home": "养老院", "shelter": "救助站", "hotel": "酒店", "hostel": "旅社"},
	"food": {"chinese_restaurant": "中餐厅", "fast_food": "快餐", "hotpot": "火锅", "cafe": "咖啡厅", "bar": "酒吧", "night_market": "夜市", "canteen": "食堂", "bakery": "面包店"},
	"retail": {"supermarket": "超市", "convenience_store": "便利店", "mall": "商场", "bookstore": "书店", "pharmacy": "药店", "flower_shop": "花店", "tobacco_alcohol": "烟酒店", "hardware_store": "五金店"},
	"medical": {"general_hospital": "综合医院", "specialty_hospital": "专科医院", "clinic": "诊所", "dental_clinic": "牙科", "psych_clinic": "心理诊所", "emergency_center": "急救中心", "drugstore": "药房", "blood_station": "血站"},
	"education": {"kindergarten": "幼儿园", "primary_school": "小学", "middle_school": "中学", "university": "大学", "vocational_school": "职校", "training_center": "培训机构", "library": "图书馆", "research_institute": "研究所"},
	"government": {"police_station": "派出所", "court": "法院", "procuratorate": "检察院", "government_office": "政府机关", "civil_affairs": "民政局", "tax_office": "税务局", "vehicle_office": "车管所", "embassy": "大使馆"},
	"transport": {"metro_station": "地铁站", "bus_stop": "公交站", "train_station": "火车站", "hsr_station": "高铁站", "airport": "机场", "port": "港口", "gas_station": "加油站", "parking_lot": "停车场"},
	"entertainment": {"cinema": "影院", "ktv": "KTV", "gym": "健身房", "internet_cafe": "网吧", "amusement_park": "游乐场", "museum": "博物馆", "art_gallery": "美术馆", "theater": "剧院"},
	"religious": {"temple": "寺庙", "church": "教堂", "mosque": "清真寺", "taoist_temple": "道观", "shrine": "神社", "synagogue": "犹太会堂", "monastery": "修道院", "cemetery": "公墓"},
	"industry": {"factory": "工厂", "mine": "矿区", "farm": "农场", "fishing_port": "渔港", "warehouse": "仓库", "power_plant": "发电站", "construction_site": "工地", "refinery": "炼油厂"},
	"finance": {"bank": "银行", "securities": "证券营业部", "insurance": "保险公司", "pawnshop": "当铺", "micro_loan": "小贷", "exchange": "交易所", "atm": "自动取款机", "credit_union": "信用社"},
	"nature": {"park": "公园", "mountain": "山", "lake": "湖", "beach": "海滩", "forest": "森林", "desert": "沙漠", "river": "河流", "hot_spring": "温泉"},
	"special": {"black_market": "黑市", "casino": "赌场", "nightclub": "夜店", "anomaly_site": "异常收容点", "secret_society": "秘密结社", "auction_house": "拍卖行", "gambling_den": "赌档", "smuggling_point": "走私点"},
}

## 各类别默认属性（可用动词 / 开放时间 / 容量 / 安全 / 价格系数）。
const CATEGORY_DEFAULTS: Dictionary = {
	"housing": {"verbs": ["进入", "居住", "休息", "租", "买", "卖"], "start": 0, "end": 1440, "capacity": 200, "safety": 75.0, "price_scale": 1.0},
	"food": {"verbs": ["进入", "吃", "喝", "买", "打工"], "start": 360, "end": 1380, "capacity": 120, "safety": 70.0, "price_scale": 1.0},
	"retail": {"verbs": ["进入", "买", "卖", "打工"], "start": 480, "end": 1320, "capacity": 150, "safety": 72.0, "price_scale": 1.0},
	"medical": {"verbs": ["进入", "看病", "买药", "住院"], "start": 0, "end": 1440, "capacity": 300, "safety": 80.0, "price_scale": 1.2},
	"education": {"verbs": ["进入", "上课", "报名", "自习"], "start": 420, "end": 1260, "capacity": 500, "safety": 85.0, "price_scale": 1.0},
	"government": {"verbs": ["进入", "办事", "办证", "咨询"], "start": 540, "end": 1080, "capacity": 200, "safety": 90.0, "price_scale": 1.0},
	"transport": {"verbs": ["进入", "乘车", "买票", "候车"], "start": 300, "end": 1440, "capacity": 1000, "safety": 78.0, "price_scale": 1.0},
	"entertainment": {"verbs": ["进入", "娱乐", "买票", "打工"], "start": 600, "end": 1500, "capacity": 300, "safety": 65.0, "price_scale": 1.3},
	"religious": {"verbs": ["进入", "祈祷", "参拜", "捐赠"], "start": 300, "end": 1200, "capacity": 200, "safety": 88.0, "price_scale": 1.0},
	"industry": {"verbs": ["进入", "工作", "打工", "参观"], "start": 480, "end": 1320, "capacity": 800, "safety": 55.0, "price_scale": 1.0},
	"finance": {"verbs": ["进入", "存取", "换汇", "办理"], "start": 540, "end": 1020, "capacity": 120, "safety": 85.0, "price_scale": 1.0},
	"nature": {"verbs": ["进入", "游览", "休息", "采集"], "start": 0, "end": 1440, "capacity": 2000, "safety": 68.0, "price_scale": 1.0},
	"special": {"verbs": ["进入", "交易", "赌博", "打听"], "start": 1080, "end": 1680, "capacity": 80, "safety": 25.0, "price_scale": 1.5},
}

## 少数类型的开放时间/可用动词覆盖（跨夜用 end > 1440 表示）。
const TYPE_OVERRIDES: Dictionary = {
	"night_market": {"start": 1020, "end": 1560},
	"bar": {"start": 1080, "end": 1680},
	"nightclub": {"start": 1200, "end": 1800},
	"ktv": {"start": 1080, "end": 1740},
	"casino": {"start": 0, "end": 1440},
	"convenience_store": {"start": 0, "end": 1440},
	"atm": {"start": 0, "end": 1440},
	"emergency_center": {"start": 0, "end": 1440},
	"hotel": {"start": 0, "end": 1440},
	"anomaly_site": {"start": 0, "end": 1440},
}

# 程序化布点时的类别权重（合计 100）。
const CATEGORY_WEIGHTS: Dictionary = {
	"housing": 14, "food": 18, "retail": 16, "medical": 6, "education": 8,
	"government": 4, "transport": 4, "entertainment": 10, "religious": 3,
	"industry": 5, "finance": 5, "nature": 4, "special": 3,
}


## 场所类型定义（Resource 语义的纯模型）。
class PlaceType:
	extends RefCounted

	var key: String = ""
	var name: String = ""
	var category: String = ""
	var available_verbs: Array = []
	var open_hours: Dictionary = {}
	var price_system: Dictionary = {}
	var capacity: int = 0
	var safety: float = 0.0
	var scene_binding: String = ""
	var icon_binding: String = ""

	func to_dict() -> Dictionary:
		return {
			"key": key, "name": name, "category": category,
			"available_verbs": available_verbs.duplicate(), "open_hours": open_hours.duplicate(true),
			"price_system": price_system.duplicate(true), "capacity": capacity, "safety": safety,
			"scene_binding": scene_binding, "icon_binding": icon_binding,
		}


## 场所实例，绑定到六级地理的建筑节点。
class Place:
	extends RefCounted

	var id: String = ""
	var name: String = ""
	var type_key: String = ""
	var category: String = ""
	var geo_id: String = ""
	var location: Dictionary = {}
	var open_hours: Dictionary = {}
	var capacity: int = 0
	var safety: float = 0.0
	var price_system: Dictionary = {}
	var tags: Array = []
	var favorite: bool = false

	## 是否在给定世界分钟营业（支持跨夜，end 可 > 1440）。
	func is_open_at(minute: int) -> bool:
		var start: int = int(open_hours.get("start_minute", 0))
		var end: int = int(open_hours.get("end_minute", 1440))
		if start == end:
			return true
		var m: int = posmod(minute, 1440)
		var end_norm: int = posmod(end, 1440)
		if start < end_norm:
			return m >= start and m < end_norm
		return m >= start or m < end_norm

	func to_dict() -> Dictionary:
		return {
			"id": id, "name": name, "type_key": type_key, "category": category,
			"geo_id": geo_id, "location": location.duplicate(), "open_hours": open_hours.duplicate(true),
			"capacity": capacity, "safety": safety, "price_system": price_system.duplicate(true),
			"tags": tags.duplicate(), "favorite": favorite,
		}


var _types: Dictionary = {}   # type_key -> PlaceType
var _places: Dictionary = {}  # place_id -> Place


func _init() -> void:
	_build_types()


func _build_types() -> void:
	for category in CATEGORY_CODES:
		var entries: Dictionary = PLACE_CATALOG[category]
		var defaults: Dictionary = CATEGORY_DEFAULTS[category]
		for type_key in entries.keys():
			var t := PlaceType.new()
			t.key = String(type_key)
			t.name = String(entries[type_key])
			t.category = String(category)
			t.available_verbs = (defaults["verbs"] as Array).duplicate()
			var start: int = int(defaults["start"])
			var end: int = int(defaults["end"])
			if TYPE_OVERRIDES.has(t.key):
				var ov: Dictionary = TYPE_OVERRIDES[t.key]
				start = int(ov.get("start", start))
				end = int(ov.get("end", end))
			t.open_hours = {"start_minute": start, "end_minute": end}
			t.price_system = {"scale": float(defaults["price_scale"]), "currency": "local"}
			t.capacity = int(defaults["capacity"])
			t.safety = float(defaults["safety"])
			t.scene_binding = "res://content/scenes/places/%s.tscn" % t.key
			t.icon_binding = "res://content/icons/places/%s.svg" % t.key
			_types[t.key] = t


# --- 类型查询 ---

func type_count() -> int:
	return _types.size()

func categories() -> Array:
	return CATEGORY_CODES.duplicate()

func get_type(type_key: String) -> PlaceType:
	return _types.get(type_key)

func has_type(type_key: String) -> bool:
	return _types.has(type_key)

func types_in_category(category: String) -> Array:
	var out: Array = []
	for key in _types.keys():
		if (_types[key] as PlaceType).category == category:
			out.append(key)
	out.sort()
	return out

func category_of(type_key: String) -> String:
	var t: PlaceType = _types.get(type_key)
	return t.category if t != null else ""


# --- 场所实例 ---

func register_place(type_key: String, geo_id: String, opts: Dictionary = {}) -> Place:
	var t: PlaceType = _types.get(type_key)
	if t == null:
		return null
	var place := Place.new()
	place.type_key = type_key
	place.category = t.category
	place.geo_id = geo_id
	var base_name: String = String(opts.get("name", t.name))
	place.name = base_name
	place.location = (opts.get("location", {}) as Dictionary).duplicate()
	place.open_hours = (opts.get("open_hours", t.open_hours) as Dictionary).duplicate(true)
	place.capacity = int(opts.get("capacity", t.capacity))
	place.safety = float(opts.get("safety", t.safety))
	place.price_system = (opts.get("price_system", t.price_system) as Dictionary).duplicate(true)
	place.tags = (opts.get("tags", []) as Array).duplicate()
	var id: String = String(opts.get("id", "%s#%s" % [geo_id, type_key]))
	var suffix: int = 1
	while _places.has(id):
		suffix += 1
		id = "%s#%s%d" % [geo_id, type_key, suffix]
	place.id = id
	_places[id] = place
	return place

func get_place(id: String) -> Place:
	return _places.get(id)

func place_count() -> int:
	return _places.size()

func all_places() -> Array:
	return _places.keys()

func places_in_geo(geo_id: String) -> Array:
	var out: Array = []
	for id in _places.keys():
		if (_places[id] as Place).geo_id == geo_id:
			out.append(_places[id])
	return out

func places_of_type(type_key: String) -> Array:
	var out: Array = []
	for id in _places.keys():
		if (_places[id] as Place).type_key == type_key:
			out.append(_places[id])
	return out

func places_in_category(category: String) -> Array:
	var out: Array = []
	for id in _places.keys():
		if (_places[id] as Place).category == category:
			out.append(_places[id])
	return out

func set_favorite(place_id: String, value: bool = true) -> bool:
	var place: Place = _places.get(place_id)
	if place == null:
		return false
	place.favorite = value
	return true

func favorites() -> Array:
	var out: Array = []
	for id in _places.keys():
		if (_places[id] as Place).favorite:
			out.append(id)
	return out

## 组合查询（R42：按类别/类型/地理前缀/营业时间/容量过滤）。
func query(filters: Dictionary = {}) -> Array:
	var category: String = String(filters.get("category", ""))
	var type_key: String = String(filters.get("type_key", ""))
	var geo_id: String = String(filters.get("geo_id", ""))
	var geo_prefix: String = String(filters.get("geo_prefix", ""))
	var open_at: int = int(filters.get("open_at", -1))
	var min_capacity: int = int(filters.get("min_capacity", -1))
	var out: Array = []
	for id in _places.keys():
		var place: Place = _places[id]
		if not category.is_empty() and place.category != category:
			continue
		if not type_key.is_empty() and place.type_key != type_key:
			continue
		if not geo_id.is_empty() and place.geo_id != geo_id:
			continue
		if not geo_prefix.is_empty() and not place.geo_id.begins_with(geo_prefix):
			continue
		if open_at >= 0 and not place.is_open_at(open_at):
			continue
		if min_capacity >= 0 and place.capacity < min_capacity:
			continue
		out.append(place)
	return out

## 为地理节点中的建筑确定性地布点（同种子可复现），返回新增场所数量。
func attach_to_geo(geo, world_seed: int = 0, places_per_building: int = 1) -> int:
	var building_level: int = 5  # GeoData.GeographicLevel.BUILDING
	var created: int = 0
	for id in geo.node_ids():
		var node = geo.get_node(id)
		if node == null or node.level != building_level:
			continue
		var rng = SplitMix64Script.new(GeoDataScript.stable_hash("place:%d:%s:%d" % [world_seed, id, places_per_building]))
		for _i in range(maxi(1, places_per_building)):
			var category: String = _weighted_category(rng)
			var keys: Array = types_in_category(category)
			var type_key: String = String(keys[int(floor(rng.next_float() * float(keys.size()))) % keys.size()])
			var t: PlaceType = _types[type_key]
			register_place(type_key, id, {
				"name": "%s（%s）" % [t.name, String(node.name)],
				"location": node.location,
				"open_hours": t.open_hours,
			})
			created += 1
	return created


func _weighted_category(rng) -> String:
	var total: int = 0
	for category in CATEGORY_CODES:
		total += int(CATEGORY_WEIGHTS.get(category, 0))
	var roll: float = rng.next_float() * float(total)
	var acc: float = 0.0
	for category in CATEGORY_CODES:
		acc += float(CATEGORY_WEIGHTS.get(category, 0))
		if roll < acc:
			return String(category)
	return String(CATEGORY_CODES[CATEGORY_CODES.size() - 1])
