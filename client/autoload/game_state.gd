extends Node
## 单一状态对象（Autoload）。
## 字段结构以 shared/schemas/save.schema.json 为准（additionalProperties=false，勿加顶层字段）。
## 供模拟层与存档层共享；业务系统按 tasklist 逐步挂载。

const SCHEMA_VERSION: int = 2
const GAME_VERSION: String = "0.0.1"

var meta: Dictionary = {}
var clock: Dictionary = {}
var player: Dictionary = {}
var world_delta: Dictionary = {}
var rng: Dictionary = {}
var legacy: Dictionary = {}

func new_game(seed: int, playthrough_id: String = "") -> void:
	var now: String = Time.get_datetime_string_from_system(true, true) + "Z"
	meta = {
		"schema_version": SCHEMA_VERSION,
		"game_version": GAME_VERSION,
		"content_version": 1,
		"playthrough_id": playthrough_id if playthrough_id != "" else Uuid.v7(),
		"seed": seed,
		"created_at": now,
		"updated_at": now,
		"config": {},
	}
	clock = {"absolute_minutes": 0, "speed": 1, "paused": false}
	player = default_player()
	world_delta = {
		"regions": [],
		"npcs": [],
		"economy": {},
		"organizations": [],
		"world_events": [],
		"news": [],
		"cases": [],
		"disasters": [],
		"anomalies": [],
		"factories": [],
		"ips": [],
		"sports": [],
		"orders": [],
		"itineraries": [],
		"medical_records": [],
		"projects": [],
		"awards": [],
	}
	rng = {"streams": {}}
	legacy = {"generation": 0, "talents": [], "unlocks": [], "lineage": [], "history": []}

func get_state() -> Dictionary:
	return to_dict()

func to_dict() -> Dictionary:
	return {
		"meta": meta,
		"clock": clock,
		"player": player,
		"world_delta": world_delta,
		"rng": rng,
		"legacy": legacy,
	}

func from_dict(doc: Dictionary) -> void:
	meta = doc.get("meta", {})
	clock = doc.get("clock", {})
	player = doc.get("player", {})
	world_delta = doc.get("world_delta", {})
	rng = doc.get("rng", {"streams": {}})
	legacy = doc.get("legacy", {})

## 默认玩家（结构与 player.schema.json 对齐）。
static func default_player() -> Dictionary:
	return {
		"id": Uuid.v7(),
		"name": "无名",
		"gender": "nonbinary",
		"sexuality": "unknown",
		"birth_minutes": 0,
		"nation": "nation.unknown",
		"mother_tongue": "language.unknown",
		"appearance": {"appearance_score": 50.0, "temperament": 50.0, "params": {}},
		"attrs": {
			"physiological": {
				"health": 100.0, "stamina": 100.0, "hunger": 100.0,
				"thirst": 100.0, "cleanliness": 100.0, "sleep_debt": 0.0,
			},
			"nutrition": {
				"protein": 50.0, "carbs": 50.0, "fat": 50.0,
				"vitamins": 50.0, "minerals": 50.0,
			},
			"psychological": {"mood": 60.0, "stress": 20.0, "happiness": 50.0, "meaning": 50.0},
			"ability": {
				"intelligence": 50.0, "charm": 50.0, "physique": 50.0,
				"willpower": 50.0, "luck": 50.0,
			},
			"personality": {
				"openness": 50.0, "conscientiousness": 50.0, "extraversion": 50.0,
				"agreeableness": 50.0, "neuroticism": 50.0,
			},
			"values": {
				"selfish_altruistic": 50.0, "conservative_open": 50.0, "material_spiritual": 50.0,
			},
		},
		"skills": [],
		"talents": [],
		"education": [],
		"licenses": [],
		"job": {},
		"finances": {"cash": 1000.0, "bank": 0.0, "debt": 0.0, "loans": [], "leases": [], "insurances": [], "investments": []},
		"assets": [],
		"inventory": [],
		"equipment": [],
		"relations": [],
		"health": {"diseases": [], "mental": [], "addictions": [], "treatments": [], "injuries": []},
		"legal": {"wanted_level": 0, "criminal_record": false, "in_prison": false, "active_case_ids": [], "record_entries": []},
		"achievements": [],
		"family": {},
		"memory": [],
		"pets": [],
		"military": {},
		"disabilities": [],
		"lands": [],
		"digital_assets": [],
		"cases": [],
		"credit_score": 650,
		"will": {},
		"orders": [],
		"itineraries": [],
		"awards": [],
		"medical_records": [],
		"disability_level": 0,
	}
