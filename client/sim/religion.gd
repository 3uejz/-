class_name ReligionSystem
extends RefCounted
## 宗教系统（R53.4–R53.5；design D13）。
##
## 归属、仪式、教义约束（饮食/禁忌/节期）、宗教社区、信仰动摇与改宗、神职晋升；
## 影响日程、社交圈与意义感（联动 D4/D15），并可能与职场产生张力。

## 宗教档案：教义（饮食、禁忌、节期）与神职路径。
const RELIGIONS: Dictionary = {
	"buddhism": {"name": "佛教", "dietary": ["vegetarian"], "taboos": ["杀生", "偷盗"], "festivals": ["佛诞节", "盂兰盆节"], "clergy": true},
	"taoism": {"name": "道教", "dietary": [], "taboos": ["杀生"], "festivals": ["太上老君诞", "三元节"], "clergy": true},
	"christianity": {"name": "基督教", "dietary": [], "taboos": ["婚前性行为"], "festivals": ["圣诞节", "复活节"], "clergy": true},
	"islam": {"name": "伊斯兰教", "dietary": ["halal"], "taboos": ["猪肉", "饮酒"], "festivals": ["开斋节", "古尔邦节"], "clergy": true},
	"hinduism": {"name": "印度教", "dietary": ["vegetarian"], "taboos": ["牛肉"], "festivals": ["排灯节", "洒红节"], "clergy": true},
	"judaism": {"name": "犹太教", "dietary": ["kosher"], "taboos": ["猪肉", "安息日劳作"], "festivals": ["逾越节", "赎罪日"], "clergy": true},
	"folk": {"name": "民间信仰", "dietary": [], "taboos": [], "festivals": ["春节", "清明节"], "clergy": false},
	"none": {"name": "无宗教", "dietary": [], "taboos": [], "festivals": [], "clergy": false},
}

const CLERGY_RANKS: Array = ["信众", "居士/执事", "教士", "牧师/法师", "主教/方丈"]
const RANK_THRESHOLDS: Array = [0.0, 100.0, 300.0, 700.0, 1500.0]


func religions() -> Array:
	return RELIGIONS.keys()


func info(religion_id: String) -> Dictionary:
	return (RELIGIONS.get(religion_id, {}) as Dictionary).duplicate()


func new_membership() -> Dictionary:
	return {"religion": "none", "devotion": 0.0, "doubt": 0.0, "clergy_rank": 0, "converted_from": ""}


## 归属（R53.4）。
func join(state: Dictionary, religion_id: String) -> Dictionary:
	if not RELIGIONS.has(religion_id):
		return {"ok": false, "reason": "unknown_religion"}
	var prev: String = str(state["religion"])
	if prev != "none":
		state["converted_from"] = prev
	state["religion"] = religion_id
	state["devotion"] = 0.0
	state["doubt"] = 0.0
	return {"ok": true, "religion": religion_id, "name": RELIGIONS[religion_id]["name"], "converted_from": prev}


## 仪式/礼拜（R53.4）：提升虔诚，降低压力、提升意义感。
func ritual(state: Dictionary, hours: float = 1.0) -> Dictionary:
	if str(state["religion"]) == "none":
		return {"ok": false, "reason": "no_religion"}
	state["devotion"] = float(state["devotion"]) + maxf(0.0, hours) * 2.0
	state["doubt"] = maxf(0.0, float(state["doubt"]) - maxf(0.0, hours) * 0.5)
	return {"ok": true, "devotion": float(state["devotion"]), "stress": -3.0 * hours, "meaning": 2.0 * hours}


## 教义饮食校验（R53.4）：返回是否允许。
func check_diet(state: Dictionary, food: String) -> Dictionary:
	var rel: String = str(state["religion"])
	var diet: Array = (RELIGIONS.get(rel, {}) as Dictionary).get("dietary", [])
	var taboos: Array = (RELIGIONS.get(rel, {}) as Dictionary).get("taboos", [])
	if diet.has("halal") and food == "pork":
		return {"ok": true, "allowed": false, "reason": "非清真"}
	if diet.has("kosher") and food == "pork":
		return {"ok": true, "allowed": false, "reason": "非洁食"}
	if diet.has("vegetarian") and food in ["meat", "pork", "beef"]:
		return {"ok": true, "allowed": false, "reason": "素食戒律"}
	if taboos.has(food):
		return {"ok": true, "allowed": false, "reason": "教义禁忌"}
	return {"ok": true, "allowed": true}


## 节期日程（R53.4）：是否需守节。
func observe_festival(state: Dictionary, month: int, day: int) -> Dictionary:
	var rel: String = str(state["religion"])
	var festivals: Array = (RELIGIONS.get(rel, {}) as Dictionary).get("festivals", [])
	var idx: int = (month * 31 + day) % maxi(1, festivals.size()) if not festivals.is_empty() else -1
	return {"ok": true, "religion": rel, "festival": festivals[idx] if idx >= 0 else "", "observing": idx >= 0}


## 宗教社区（R53.4、R53.5）：提供社交圈与互助。
func community_effect(state: Dictionary) -> Dictionary:
	var devotion: float = float(state["devotion"])
	return {"social_circle": "religious", "support": clampf(devotion / 10.0, 0.0, 10.0), "meaning_bonus": clampf(devotion / 20.0, 0.0, 5.0)}


## 信仰动摇（R53.5、R55.6）：压力/世俗冲击累积怀疑。
func waver(state: Dictionary, shock: float, rng = null) -> Dictionary:
	state["doubt"] = clampf(float(state["doubt"]) + shock, 0.0, 100.0)
	var roll: float = rng.next_float() if rng != null else 1.0
	var crisis: bool = float(state["doubt"]) > 50.0 and roll < float(state["doubt"]) / 100.0
	return {"ok": true, "doubt": float(state["doubt"]), "crisis": crisis}


## 改宗（R53.4）。
func convert(state: Dictionary, religion_id: String) -> Dictionary:
	return join(state, religion_id)


## 神职晋升（R53.4）。
func clergy_promote(state: Dictionary, rng = null) -> Dictionary:
	var rel: String = str(state["religion"])
	if not bool((RELIGIONS.get(rel, {}) as Dictionary).get("clergy", false)):
		return {"ok": false, "reason": "no_clergy"}
	var rank: int = int(state["clergy_rank"])
	if rank >= CLERGY_RANKS.size() - 1:
		return {"ok": false, "reason": "top_rank"}
	var need: float = float(RANK_THRESHOLDS[rank + 1])
	var roll: float = rng.next_float() if rng != null else 0.0
	if float(state["devotion"]) >= need and roll < 0.8:
		state["clergy_rank"] = rank + 1
		return {"ok": true, "promoted": true, "rank": rank + 1, "name": CLERGY_RANKS[rank + 1]}
	return {"ok": true, "promoted": false, "required_devotion": need}


## 宗教与职场张力（R53.5）：信仰约束越强、职场世俗性越高，张力越大。
func work_tension(state: Dictionary, workplace_religiosity: float) -> Dictionary:
	var devotion: float = float(state["devotion"])
	var tension: float = clampf(devotion * (1.0 - clampf(workplace_religiosity, 0.0, 1.0)) / 5.0, 0.0, 100.0)
	return {"tension": tension, "conflict": tension > 40.0}
