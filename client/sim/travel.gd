class_name TravelSystem
extends RefCounted
## 旅行系统（R54.4–R54.6、R28.4；design D14）。
##
## 目的地选择、交通与住宿预订、行程规划、景点、意外与旅行保险；按日结算开销与事件；
## 结束生成见闻记录、图鉴条目并提升心情与见识。签证联动 D13，出行方式联动 D2。

## 目的地（category: local 本地 / domestic 国内 / abroad 出国 / adventure 探险）。
const DESTINATIONS: Dictionary = {
	"city_park": {"name": "城市公园", "category": "local", "distance_km": 10, "base_days": 1, "base_cost": 5000, "sights": ["湖心亭", "花海"], "visa_required": false},
	"suburb_hotspring": {"name": "近郊温泉", "category": "local", "distance_km": 60, "base_days": 2, "base_cost": 30000, "sights": ["温泉谷", "古寺"], "visa_required": false},
	"ancient_town": {"name": "古镇", "category": "domestic", "distance_km": 800, "base_days": 3, "base_cost": 80000, "sights": ["石板街", "廊桥", "老街夜市"], "visa_required": false},
	"beach_resort": {"name": "海滨度假", "category": "domestic", "distance_km": 1500, "base_days": 5, "base_cost": 200000, "sights": ["沙滩", "海洋馆", "夜市"], "visa_required": false},
	"mountain": {"name": "名山", "category": "domestic", "distance_km": 1200, "base_days": 4, "base_cost": 150000, "sights": ["云海", "古刹", "日出"], "visa_required": false},
	"paris": {"name": "巴黎", "category": "abroad", "distance_km": 9500, "base_days": 7, "base_cost": 800000, "sights": ["埃菲尔铁塔", "卢浮宫", "塞纳河"], "visa_required": true},
	"tokyo": {"name": "东京", "category": "abroad", "distance_km": 2100, "base_days": 6, "base_cost": 600000, "sights": ["浅草寺", "涩谷", "富士山"], "visa_required": true},
	"new_york": {"name": "纽约", "category": "abroad", "distance_km": 11000, "base_days": 8, "base_cost": 1000000, "sights": ["自由女神", "时代广场", "中央公园"], "visa_required": true},
	"dubai": {"name": "迪拜", "category": "abroad", "distance_km": 6500, "base_days": 5, "base_cost": 700000, "sights": ["哈利法塔", "沙漠冲沙", "黄金市场"], "visa_required": true},
	"everest_base": {"name": "珠峰大本营", "category": "adventure", "distance_km": 3000, "base_days": 12, "base_cost": 1500000, "sights": ["冰川", "星空", "雪峰"], "visa_required": true},
	"amazon": {"name": "亚马逊雨林", "category": "adventure", "distance_km": 16000, "base_days": 14, "base_cost": 2000000, "sights": ["雨林", "野生动物", "河流"], "visa_required": true},
	"antarctica": {"name": "南极", "category": "adventure", "distance_km": 18000, "base_days": 18, "base_cost": 6000000, "sights": ["冰川", "企鹅", "极光"], "visa_required": true},
}

## 交通方式。
const TRANSPORT: Dictionary = {
	"bus": {"name": "长途巴士", "cost_per_km": 50, "comfort": 0.4, "speed_kmh": 70},
	"train": {"name": "火车", "cost_per_km": 120, "comfort": 0.7, "speed_kmh": 200},
	"car": {"name": "自驾", "cost_per_km": 100, "comfort": 0.6, "speed_kmh": 90},
	"flight": {"name": "飞机", "cost_per_km": 300, "comfort": 0.8, "speed_kmh": 800},
	"ship": {"name": "邮轮", "cost_per_km": 200, "comfort": 0.9, "speed_kmh": 40},
}

## 住宿档次。
const LODGING: Dictionary = {
	"hostel": {"name": "青旅", "cost_per_night": 8000, "comfort": 0.3},
	"guesthouse": {"name": "民宿", "cost_per_night": 20000, "comfort": 0.6},
	"hotel": {"name": "酒店", "cost_per_night": 50000, "comfort": 0.8},
	"luxury": {"name": "豪华度假村", "cost_per_night": 200000, "comfort": 1.0},
}

## 旅中意外（R54.6）。
const EVENTS: Array = ["delay", "cancel", "lost_luggage", "illness", "accident", "situation_change"]
const EVENT_COST: Dictionary = {"delay": 5000, "cancel": 30000, "lost_luggage": 20000, "illness": 50000, "accident": 200000, "situation_change": 100000}


func destinations() -> Array:
	return DESTINATIONS.keys()


func destination_info(id: String) -> Dictionary:
	return (DESTINATIONS.get(id, {}) as Dictionary).duplicate()


func transport_modes() -> Array:
	return TRANSPORT.keys()


func lodging_options() -> Array:
	return LODGING.keys()


## 规划行程（R54.4）。
func plan_trip(destination_id: String, transport_id: String, lodging_id: String, days: int, insured: bool = false) -> Dictionary:
	if not DESTINATIONS.has(destination_id) or not TRANSPORT.has(transport_id) or not LODGING.has(lodging_id):
		return {"ok": false, "reason": "invalid_option"}
	var d: Dictionary = DESTINATIONS[destination_id]
	var nights: int = maxi(1, days if days > 0 else int(d["base_days"]))
	return {"ok": true, "destination": destination_id, "transport": transport_id, "lodging": lodging_id, "days": days if days > 0 else int(d["base_days"]), "nights": nights, "insured": insured, "visited": []}


## 预订总成本（R54.4）。
func booking_cost(destination_id: String, transport_id: String, nights: int, transport_round_trip: bool = true) -> Dictionary:
	if not DESTINATIONS.has(destination_id) or not TRANSPORT.has(transport_id):
		return {"ok": false, "reason": "invalid_option"}
	var d: Dictionary = DESTINATIONS[destination_id]
	var t: Dictionary = TRANSPORT[transport_id]
	var trips: int = 2 if transport_round_trip else 1
	var transport_cost: int = int(round(float(d["distance_km"]) * float(t["cost_per_km"]))) * trips
	var days: int = nights + 1
	var lodging_cost: int = int(LODGING["hotel"]["cost_per_night"]) * nights
	return {"ok": true, "transport_cost": transport_cost, "lodging_estimate": lodging_cost, "per_day_estimate": int(d["base_cost"]), "total_estimate": transport_cost + lodging_cost + int(d["base_cost"]) * days}


## 按日结算（R54.4、R54.6）。
func daily_settlement(trip: Dictionary, money: int, rng = null) -> Dictionary:
	var d: Dictionary = DESTINATIONS[str(trip["destination"])]
	var lodging: Dictionary = LODGING[str(trip["lodging"])]
	var per_day: int = int(d["base_cost"]) + int(lodging["cost_per_night"])
	var roll: float = rng.next_float() if rng != null else 1.0
	var event: String = ""
	var extra: int = 0
	if roll < 0.25:
		var ev_idx: int = int(roll * 100.0) % EVENTS.size()
		event = str(EVENTS[ev_idx])
		extra = int(EVENT_COST[event])
		if bool(trip.get("insured", false)):
			extra = int(extra * 0.2)
	var total: int = per_day + extra
	return {"ok": true, "day_cost": total, "event": event, "extra_cost": extra, "covered_by_insurance": bool(trip.get("insured", false)) and event != "", "affordable": money >= total}


## 结束行程（R54.5）：见闻、图鉴与心情/见识提升。
func finish_trip(trip: Dictionary) -> Dictionary:
	var d: Dictionary = DESTINATIONS[str(trip["destination"])]
	var days: int = maxi(1, int(trip["days"]))
	var category: String = str(d["category"])
	var mood_gain: float = 8.0 + float(days) * 0.5
	var insight_gain: float = minf(15.0, float(days) * 1.0)
	return {"ok": true, "destination": trip["destination"], "name": d["name"], "mood": mood_gain, "insight": insight_gain, "codex_entries": (d["sights"] as Array).duplicate(), "category": category}
