class_name Transport
extends RefCounted
## 十二种交通方式、真实坐标出行计算与枢纽换乘路径（R4、R42.5–R42.7；design D2）。
##
## - 距离：真实经纬度 Haversine 球面距离（复用 GeoData.distance_km）。
## - 耗时 = 距离/速度 + 等待 + 换乘 + 拥堵修正；费用 = 起步价 + 里程费 + 时长费。
## - 枢纽换乘网络为加权有向图，按时间为权重用 Dijkstra 规划多段路径并结算总耗时/费用。
## - 校验证件与车辆条件（R4.3、R4.4）。
##
## headless 可测的纯模型；数值默认见 client/sim/baseline.gd（可远程覆盖）。

const GeoDataScript = preload("res://sim/geo.gd")
const BaselineScript = preload("res://sim/baseline.gd")


## 枢纽换乘网络。节点为公交站/地铁站/火车站/高铁站/机场/港口/长途客运站；
## 边定义交通方式、距离、票价、班次间隔与首末班时间。
class TransportNetwork:
	extends RefCounted

	var hubs: Dictionary = {}        # id -> {id, name, type, location, country_code}
	var adjacency: Dictionary = {}   # from_id -> Array[edge]

	func add_hub(id: String, name: String, hub_type: String, location: Dictionary, country_code: String = "") -> void:
		hubs[id] = {"id": id, "name": name, "type": hub_type, "location": location.duplicate(), "country_code": country_code}
		if not adjacency.has(id):
			adjacency[id] = []

	func has_hub(id: String) -> bool:
		return hubs.has(id)

	func hub(id: String) -> Dictionary:
		return hubs.get(id, {})

	func hub_ids() -> Array:
		return hubs.keys()

	## 添加一条有向边；headway_minutes < 0 时由交通方式默认班次决定。
	func add_edge(from_id: String, to_id: String, mode_key: String, distance_km: float, fare: float,
			headway_minutes: float = -1.0, first_minute: int = 0, last_minute: int = 1440) -> void:
		if not adjacency.has(from_id):
			adjacency[from_id] = []
		adjacency[from_id].append({
			"from": from_id, "to": to_id, "mode": mode_key,
			"distance_km": maxf(0.0, distance_km), "fare": maxf(0.0, fare),
			"headway_minutes": headway_minutes, "first_minute": first_minute, "last_minute": last_minute,
		})

	func add_bidirectional(from_id: String, to_id: String, mode_key: String, distance_km: float, fare: float,
			headway_minutes: float = -1.0, first_minute: int = 0, last_minute: int = 1440) -> void:
		add_edge(from_id, to_id, mode_key, distance_km, fare, headway_minutes, first_minute, last_minute)
		add_edge(to_id, from_id, mode_key, distance_km, fare, headway_minutes, first_minute, last_minute)

	func edges_from(id: String) -> Array:
		return adjacency.get(id, [])


# --- 交通方式 ---

func mode_count() -> int:
	return BaselineScript.TRANSPORT_MODES.size()

func mode_keys() -> Array:
	return BaselineScript.TRANSPORT_MODE_ORDER.duplicate()

func mode_info(mode_key: String) -> Dictionary:
	return BaselineScript.effective_transport_mode(mode_key)

func required_conditions(mode_key: String) -> Array:
	return (BaselineScript.effective_transport_mode(mode_key).get("requires", []) as Array).duplicate()

## 返回缺失的证件/车辆条件（R4.4）。
func missing_conditions(mode_key: String, owned: Array) -> Array:
	var missing: Array = []
	for req in required_conditions(mode_key):
		if not owned.has(req):
			missing.append(req)
	return missing


# --- 单段出行估算 ---

## 基于真实坐标估算某种交通方式的距离/耗时/费用。
## options：speed_kmh（覆盖速度）、congestion_factor（道路拥堵系数 ≥1）、
##          transfer_minutes（附加换乘等待）、owned（已持证件/车辆）。
func estimate_trip(mode_key: String, from_point, to_point, options: Dictionary = {}) -> Dictionary:
	var mode: Dictionary = BaselineScript.effective_transport_mode(mode_key)
	if mode.is_empty():
		return {"ok": false, "error": "unknown_mode", "mode": mode_key, "missing": []}
	var owned: Array = options.get("owned", [])
	var missing: Array = missing_conditions(mode_key, owned)
	var distance: float = GeoDataScript.distance_km(from_point, to_point)
	var speed: float = maxf(0.1, float(options.get("speed_kmh", mode["speed_kmh"])))
	var travel: float = distance / speed * 60.0
	var wait: float = float(mode.get("wait_minutes", 0.0))
	var transfer: float = float(options.get("transfer_minutes", 0.0))
	var congestion: float = 0.0
	if BaselineScript.TRANSPORT_CONGESTION_CATEGORIES.has(String(mode["category"])):
		var factor: float = maxf(1.0, float(options.get("congestion_factor", 1.0)))
		congestion = travel * (factor - 1.0)
	var minutes: float = travel + wait + transfer + congestion
	var cost: float = float(mode["base_fare"]) + float(mode["per_km"]) * distance + float(mode["per_minute"]) * minutes
	return {
		"ok": missing.is_empty(), "error": "" if missing.is_empty() else "missing_conditions",
		"mode": mode_key, "mode_name": String(mode["name"]), "category": String(mode["category"]),
		"distance_km": distance, "speed_kmh": speed, "travel_minutes": travel,
		"wait_minutes": wait, "transfer_minutes": transfer, "congestion_minutes": congestion,
		"minutes": minutes, "minutes_int": int(ceil(minutes)),
		"cost": cost, "currency": String(options.get("currency", "local")),
		"comfort": float(mode["comfort"]), "missing": missing,
	}


# --- 枢纽换乘路径（Dijkstra，以时间为权重）---

## 规划从 from_id 到 to_id 的换乘路径，返回多段明细与总计（R42.7）。
func route(network: TransportNetwork, from_id: String, to_id: String, depart_minute: int = 0,
		transfer_minutes: float = -1.0) -> Dictionary:
	if network == null or not network.has_hub(from_id) or not network.has_hub(to_id):
		return _empty_route("unknown_hub")
	var transfer_default: float = BaselineScript.TRANSPORT_TRANSFER_MINUTES_DEFAULT if transfer_minutes < 0.0 else transfer_minutes

	# 状态 = 节点|入边方式，使换乘等待可计入（切换方式时才追加换乘等待）。
	var start_state: String = from_id + "|"
	var dist: Dictionary = {start_state: 0.0}
	var prev: Dictionary = {}
	var visited: Dictionary = {}

	while true:
		var best_state: String = ""
		var best_time: float = INF
		for state in dist.keys():
			if visited.has(state):
				continue
			if float(dist[state]) < best_time:
				best_time = float(dist[state])
				best_state = state
		if best_state.is_empty():
			break
		visited[best_state] = true
		var parts: PackedStringArray = best_state.split("|")
		var node: String = String(parts[0])
		var incoming: String = String(parts[1]) if parts.size() > 1 else ""
		if node == to_id:
			return _reconstruct(prev, best_state, depart_minute, transfer_default)
		for edge in network.edges_from(node):
			var edge_time: float = _edge_time(edge, incoming, transfer_default)
			var next_state: String = String(edge["to"]) + "|" + String(edge["mode"])
			var candidate: float = best_time + edge_time
			if not dist.has(next_state) or candidate < float(dist[next_state]) - 1e-9:
				dist[next_state] = candidate
				prev[next_state] = {"from_state": best_state, "edge": edge}
	return _empty_route("no_route")


func _edge_time(edge: Dictionary, incoming_mode: String, transfer_minutes: float) -> float:
	var mode: Dictionary = BaselineScript.effective_transport_mode(String(edge["mode"]))
	var speed: float = maxf(0.1, float(mode.get("speed_kmh", 1.0)))
	var travel: float = float(edge["distance_km"]) / speed * 60.0
	var headway: float = float(edge.get("headway_minutes", -1.0))
	if headway < 0.0:
		headway = float(mode.get("headway_minutes", 0.0))
	var wait: float = headway / 2.0 if headway > 0.0 else 0.0
	var transfer: float = transfer_minutes if (not incoming_mode.is_empty() and incoming_mode != String(edge["mode"])) else 0.0
	return travel + wait + transfer


func _reconstruct(prev: Dictionary, goal_state: String, depart_minute: int, transfer_default: float) -> Dictionary:
	var chain: Array = []
	var cursor: String = goal_state
	while prev.has(cursor):
		chain.push_front({"state": cursor, "edge": prev[cursor]["edge"]})
		cursor = String(prev[cursor]["from_state"])

	var segments: Array = []
	var incoming: String = ""
	var total_distance: float = 0.0
	var total_minutes: float = 0.0
	var total_cost: float = 0.0
	var transfers: int = 0
	var minutes_cursor: float = float(depart_minute)
	for item in chain:
		var edge: Dictionary = item["edge"]
		var mode: Dictionary = BaselineScript.effective_transport_mode(String(edge["mode"]))
		var speed: float = maxf(0.1, float(mode.get("speed_kmh", 1.0)))
		var travel: float = float(edge["distance_km"]) / speed * 60.0
		var headway: float = float(edge.get("headway_minutes", -1.0))
		if headway < 0.0:
			headway = float(mode.get("headway_minutes", 0.0))
		var wait: float = headway / 2.0 if headway > 0.0 else 0.0
		var transfer: float = 0.0
		if not incoming.is_empty() and incoming != String(edge["mode"]):
			transfer = transfer_default
			transfers += 1
		var minutes: float = travel + wait + transfer
		var cost: float = float(edge["fare"])
		segments.append({
			"from": String(edge["from"]), "to": String(edge["to"]), "mode": String(edge["mode"]),
			"mode_name": String(mode.get("name", "")), "distance_km": float(edge["distance_km"]),
			"travel_minutes": travel, "wait_minutes": wait, "transfer_minutes": transfer,
			"minutes": minutes, "cost": cost,
		})
		total_distance += float(edge["distance_km"])
		total_minutes += minutes
		total_cost += cost
		incoming = String(edge["mode"])
		minutes_cursor += minutes

	return {
		"ok": true, "error": "", "from": String(chain[0]["edge"]["from"]) if chain.size() > 0 else "",
		"to": goal_state.split("|")[0], "segments": segments, "segment_count": segments.size(),
		"transfers": transfers, "total_distance_km": total_distance,
		"total_minutes": total_minutes, "total_minutes_int": int(ceil(total_minutes)),
		"total_cost": total_cost, "arrival_minute": minutes_cursor,
	}


func _empty_route(error: String) -> Dictionary:
	return {
		"ok": false, "error": error, "segments": [], "segment_count": 0, "transfers": 0,
		"total_distance_km": 0.0, "total_minutes": 0.0, "total_minutes_int": 0,
		"total_cost": 0.0, "arrival_minute": 0.0,
	}


## 构建示例枢纽网络（测试与演示用；真实网络由内容管线注入）。
func build_demo_network() -> TransportNetwork:
	var net := TransportNetwork.new()
	net.add_hub("bj_south", "北京南站", "hsr_station", {"lat": 39.8650, "lon": 116.3786}, "CN")
	net.add_hub("bj_airport", "北京首都机场", "airport", {"lat": 40.0799, "lon": 116.6031}, "CN")
	net.add_hub("sh_hongqiao", "上海虹桥站", "hsr_station", {"lat": 31.1940, "lon": 121.3200}, "CN")
	net.add_hub("sh_pudong", "上海浦东机场", "airport", {"lat": 31.1443, "lon": 121.8083}, "CN")
	net.add_hub("gz_south", "广州南站", "hsr_station", {"lat": 22.9890, "lon": 113.2680}, "CN")
	net.add_hub("sz_north", "深圳北站", "hsr_station", {"lat": 22.6100, "lon": 114.0300}, "CN")
	net.add_bidirectional("bj_south", "sh_hongqiao", "high_speed_rail", 1318.0, 553.0)
	net.add_bidirectional("sh_hongqiao", "sh_pudong", "metro", 40.0, 7.0, 6.0)
	net.add_bidirectional("bj_airport", "sh_pudong", "airplane", 1080.0, 900.0, 120.0)
	net.add_bidirectional("bj_south", "gz_south", "high_speed_rail", 2298.0, 862.0)
	net.add_bidirectional("bj_south", "bj_airport", "metro", 30.0, 5.0, 6.0)
	net.add_bidirectional("gz_south", "sz_north", "high_speed_rail", 102.0, 74.0)
	return net
