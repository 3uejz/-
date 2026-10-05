class_name CrimeSystem
extends RefCounted
## 犯罪：民事/治安/刑事三类、犯罪指令、案底与通缉（R22；design D12）。
##
## 覆盖偷窃、抢劫、诈骗、斗殴、伤害、走私、逃税等犯罪指令，按技能与概率判定成败；
## 案底影响就业与社会关系；支持跨区域通缉、追诉期、自首、潜逃、改名与行贿；
## 另含腐败、行贿与被陷害等灰色路径。
##
## 设计取舍：
##   - 技能取 0..20；成功率 = 0.4 + (技能 − 难度)/20，clamp 0.05..0.95。
##   - 案底/通缉等状态保存在本实例，供司法与监狱系统消费。

const CATEGORIES: Array = ["civil", "public_order", "criminal"]
const CATEGORY_NAMES: Dictionary = {"civil": "民事", "public_order": "治安", "criminal": "刑事"}

## 犯罪表。difficulty 0..20；penalty 为刑期天数与罚金（最小货币单位）区间；statute_years 追诉期。
const CRIMES: Dictionary = {
	"theft": {"name": "偷窃", "category": "criminal", "difficulty": 6.0, "detect": 0.3, "penalty": {"days": [5, 180], "fine": [50000, 500000]}, "statute_years": 5},
	"robbery": {"name": "抢劫", "category": "criminal", "difficulty": 12.0, "detect": 0.5, "penalty": {"days": [1095, 3650], "fine": [100000, 1000000]}, "statute_years": 15},
	"fraud": {"name": "诈骗", "category": "criminal", "difficulty": 9.0, "detect": 0.35, "penalty": {"days": [180, 1825], "fine": [100000, 2000000]}, "statute_years": 10},
	"assault": {"name": "斗殴", "category": "public_order", "difficulty": 5.0, "detect": 0.4, "penalty": {"days": [1, 30], "fine": [20000, 200000]}, "statute_years": 3},
	"injury": {"name": "伤害", "category": "criminal", "difficulty": 8.0, "detect": 0.45, "penalty": {"days": [180, 1095], "fine": [100000, 1000000]}, "statute_years": 10},
	"smuggling": {"name": "走私", "category": "criminal", "difficulty": 13.0, "detect": 0.4, "penalty": {"days": [365, 3650], "fine": [200000, 5000000]}, "statute_years": 15},
	"tax_evasion": {"name": "逃税", "category": "criminal", "difficulty": 10.0, "detect": 0.35, "penalty": {"days": [0, 1095], "fine": [200000, 5000000]}, "statute_years": 10},
	"corruption": {"name": "腐败", "category": "criminal", "difficulty": 11.0, "detect": 0.3, "penalty": {"days": [365, 3650], "fine": [500000, 5000000]}, "statute_years": 15},
	"bribery": {"name": "行贿", "category": "criminal", "difficulty": 9.0, "detect": 0.3, "penalty": {"days": [180, 1825], "fine": [200000, 2000000]}, "statute_years": 10},
	"framing": {"name": "陷害", "category": "criminal", "difficulty": 12.0, "detect": 0.35, "penalty": {"days": [180, 1825], "fine": [100000, 1000000]}, "statute_years": 10},
	"deceive": {"name": "欺诈", "category": "civil", "difficulty": 7.0, "detect": 0.25, "penalty": {"days": [0, 0], "fine": [10000, 500000]}, "statute_years": 3},
	"disturbance": {"name": "寻衅滋事", "category": "public_order", "difficulty": 4.0, "detect": 0.5, "penalty": {"days": [1, 15], "fine": [5000, 50000]}, "statute_years": 2},
}


func _init() -> void:
	pass


func crimes_count() -> int:
	return CRIMES.size()


func _clamp01(v: float) -> float:
	return clampf(v, 0.0, 1.0)


## 实施犯罪（R22.3）：依技能与概率判定成败，可能被察觉。
func attempt(crime: String, skill: float, rng = null, opts: Dictionary = {}) -> Dictionary:
	if not CRIMES.has(crime):
		return {"ok": false, "reason": "unknown_crime"}
	var c: Dictionary = CRIMES[crime]
	var difficulty: float = float(c["difficulty"])
	var prob: float = clampf(0.4 + (clampf(skill, 0.0, 20.0) - difficulty) / 20.0, 0.05, 0.95)
	var roll: float = rng.next_float() if rng != null else 0.0
	var success: bool = roll < prob
	var detect_prob: float = float(c["detect"]) * (0.5 if success else 1.0)
	var roll2: float = rng.next_float() if rng != null else 1.0
	var detected: bool = (roll2 < detect_prob) or (not success and roll2 < detect_prob + 0.3)
	return {"ok": true, "crime": crime, "success": success, "detected": detected, "probability": prob}


## 记录案底（R22.4）。
func add_record(state: Dictionary, crime: String, region: String, minute: int, evidence_strength: float = 1.0) -> Dictionary:
	var rec: Dictionary = {"crime": crime, "region": region, "minute": minute, "evidence": clampf(evidence_strength, 0.0, 1.0)}
	var records: Array = state.get("records", [])
	records.append(rec)
	state["records"] = records
	return rec


func has_record(state: Dictionary) -> bool:
	return not (state.get("records", []) as Array).is_empty()


## 案底对就业与社会关系的影响（R22.4）。
func record_effects(state: Dictionary) -> Dictionary:
	var n: int = (state.get("records", []) as Array).size()
	return {"employment_penalty": clampf(n * 20.0, 0.0, 80.0), "social_penalty": clampf(n * 15.0, 0.0, 70.0)}


## 追诉期判定（R22.5）。
func statute_expired(record: Dictionary, now_minute: int) -> bool:
	var years: float = float(CRIMES.get(str(record.get("crime", "")), {}).get("statute_years", 5.0))
	var elapsed: float = float(now_minute - int(record.get("minute", 0))) / (365.25 * 1440.0)
	return elapsed > years


## 通缉（R22.5）：跨区域独立记录。
func add_wanted(state: Dictionary, crime: String, region: String, level: int = 1) -> void:
	var wanted: Dictionary = state.get("wanted", {})
	wanted[region] = {"crime": crime, "level": clampi(level, 1, 5)}
	state["wanted"] = wanted


func wanted_level(state: Dictionary, region: String) -> int:
	return int((state.get("wanted", {}) as Dictionary).get(region, {}).get("level", 0))


func is_wanted(state: Dictionary) -> bool:
	return not (state.get("wanted", {}) as Dictionary).is_empty()


## 自首（R22.5）：减轻处罚。
func self_surrender(state: Dictionary, region: String) -> Dictionary:
	var wanted: Dictionary = state.get("wanted", {})
	if not wanted.has(region):
		return {"ok": false, "reason": "not_wanted"}
	var entry: Dictionary = wanted[region]
	wanted.erase(region)
	state["wanted"] = wanted
	state["surrendered"] = true
	return {"ok": true, "crime": str(entry.get("crime", "")), "discount": 0.3}


## 潜逃（R22.5）：转移至他区域并降低当地追缉，但提高整体风险。
func flee(state: Dictionary, from_region: String, to_region: String) -> Dictionary:
	var wanted: Dictionary = state.get("wanted", {})
	if wanted.has(from_region):
		var entry: Dictionary = wanted[from_region]
		wanted.erase(from_region)
		wanted[to_region] = entry
		state["wanted"] = wanted
	state["fled"] = true
	return {"ok": true, "region": to_region}


## 改名（R22.5）：规避身份关联，收窄追缉强度。
func change_name(state: Dictionary) -> Dictionary:
	state["aliases"] = int(state.get("aliases", 0)) + 1
	var wanted: Dictionary = state.get("wanted", {})
	for region in wanted.keys():
		wanted[region]["level"] = maxi(1, int(wanted[region].get("level", 1)) - 1)
	state["wanted"] = wanted
	return {"ok": true, "aliases": int(state["aliases"])}


## 行贿（R22.6）：可能成功脱罪或加罪。
func bribe(official_corruption: float, amount: float, rng = null) -> Dictionary:
	var prob: float = clampf(official_corruption * 0.6 + amount / 5000000.0, 0.05, 0.95)
	var roll: float = rng.next_float() if rng != null else 1.0
	var success: bool = roll < prob
	var roll2: float = rng.next_float() if rng != null else 1.0
	var exposed: bool = roll2 < 0.1
	return {"ok": true, "success": success, "exposed": exposed, "probability": prob}
