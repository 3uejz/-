class_name FashionSystem
extends RefCounted
## 时尚、设计与奢侈品（R75；design D31）。
##
## 覆盖：
##   - 设计路径：服装、珠宝、工业、平面、家居，作品由技能、灵感与潮流契合度评分（联动 D5）；
##   - 时尚周期：时装周、联名、代言、限量与品牌溢价；区分引领潮流与跟潮；季节性；
##   - 奢侈品市场：鉴定真伪、仿品、二手流通、拍卖与收藏保值；
##   - 品牌经营：品牌定位、门店、营销、代言人管理、品牌老化与复兴；
##   - 边界：抄袭指控（联动 D25）、明星代言翻车、假货侵权、奢侈品保值与泡沫。
##
## 设计取舍：
##   - 品牌与作品为纯数据 Dictionary，便于存读档与 headless 测试；
##   - 作品评分 = 技能权重 × 技能归一 + 灵感权重 × 灵感 + 潮流契合权重 × 契合度 − 抄袭惩罚，
##     权重合计为 1，评分 clamp 到 [0, 100]，可比对；
##   - 潮流状态机（新兴→上升→顶峰→退潮）与鉴定/拍卖均为确定性；随机项由外部 rng 或强制值驱动。

const DISCIPLINES: Dictionary = {
	"apparel": {"name": "服装设计", "skill": "skill.design_apparel"},
	"jewelry": {"name": "珠宝设计", "skill": "skill.design_jewelry"},
	"industrial": {"name": "工业设计", "skill": "skill.design_industrial"},
	"graphic": {"name": "平面设计", "skill": "skill.design_graphic"},
	"home": {"name": "家居设计", "skill": "skill.design_home"},
}

## 品牌定位：溢价系数、门店门槛与老化速度。
const POSITIONING: Dictionary = {
	"mass": {"name": "大众", "premium": 1.0, "min_capital": 0, "aging_rate": 0.04},
	"premium": {"name": "轻奢", "premium": 1.6, "min_capital": 2000000, "aging_rate": 0.03},
	"luxury": {"name": "奢侈", "premium": 3.0, "min_capital": 10000000, "aging_rate": 0.02},
	"niche": {"name": "设计师品牌", "premium": 2.2, "min_capital": 500000, "aging_rate": 0.05},
}

const SEASONS: Dictionary = {
	"ss": {"name": "春夏季", "demand": 1.0},
	"aw": {"name": "秋冬季", "demand": 1.1},
	"resort": {"name": "度假系列", "demand": 0.9},
}

## 时尚周期阶段：新兴/上升/顶峰/退潮。
const TREND_PHASES: Array = ["emerging", "rising", "peak", "declining"]
const TREND_PHASE_NAMES: Dictionary = {"emerging": "新兴", "rising": "上升", "peak": "顶峰", "declining": "退潮"}

## 奢侈品类目。
const LUXURY_ITEMS: Dictionary = {
	"handbag": {"name": "手袋", "base_value": 50000, "volatility": 0.20},
	"watch": {"name": "腕表", "base_value": 200000, "volatility": 0.15},
	"jewelry": {"name": "珠宝", "base_value": 300000, "volatility": 0.10},
	"apparel": {"name": "成衣", "base_value": 20000, "volatility": 0.35},
	"sneaker": {"name": "限量运动鞋", "base_value": 8000, "volatility": 0.60},
}

const AUTH_GENUINE: String = "genuine"
const AUTH_COUNTERFEIT: String = "counterfeit"
const AUTH_UNCERTAIN: String = "uncertain"

## 营销方式：品牌提升与反噬。
const MARKETING: Dictionary = {
	"ads": {"name": "广告", "fame": 2.0, "backlash": 0.0},
	"influencer": {"name": "网红种草", "fame": 4.0, "backlash": 0.25},
	"event": {"name": "大秀活动", "fame": 6.0, "backlash": 0.05},
	"charity": {"name": "公益形象", "fame": 3.0, "backlash": 0.0},
}

const SKILL_WEIGHT: float = 0.45
const INSPIRATION_WEIGHT: float = 0.20
const TREND_WEIGHT: float = 0.35
const PLAGIARISM_PENALTY: float = 35.0
const BASE_ORDER_VALUE: int = 5000
const BUBBLE_THRESHOLD: float = 1.8


# --- 数据表 ---

func discipline_keys() -> Array:
	return DISCIPLINES.keys()


func discipline_def(discipline: String) -> Dictionary:
	if not DISCIPLINES.has(discipline):
		return {}
	return (DISCIPLINES[discipline] as Dictionary).duplicate(true)


func positioning_keys() -> Array:
	return POSITIONING.keys()


func positioning_def(positioning: String) -> Dictionary:
	if not POSITIONING.has(positioning):
		return {}
	return (POSITIONING[positioning] as Dictionary).duplicate(true)


func season_keys() -> Array:
	return SEASONS.keys()


func trend_phase_names() -> Dictionary:
	return TREND_PHASE_NAMES.duplicate(true)


func luxury_keys() -> Array:
	return LUXURY_ITEMS.keys()


func luxury_def(item: String) -> Dictionary:
	if not LUXURY_ITEMS.has(item):
		return {}
	return (LUXURY_ITEMS[item] as Dictionary).duplicate(true)


# --- 品牌 ---

func new_brand(money: int = 1000000, opts: Dictionary = {}) -> Dictionary:
	var positioning: String = str(opts.get("positioning", "mass"))
	if not POSITIONING.has(positioning):
		positioning = "mass"
	return {
		"money": money,
		"name": str(opts.get("name", "无名品牌")),
		"positioning": positioning,
		"reputation": clampf(float(opts.get("reputation", 50.0)), 0.0, 100.0),
		"fame": clampf(float(opts.get("fame", 30.0)), 0.0, 100.0),
		"brand_value": maxi(0, int(opts.get("brand_value", 1000000))),
		"age_years": 0.0,
		"relevance": clampf(float(opts.get("relevance", 80.0)), 0.0, 100.0),
		"marketing": 1.0,
		"stores": [],
		"endorsers": [],
		"collections": [],
		"inventory": {},
	}


func brand_premium(brand: Dictionary) -> float:
	var pos: float = float((POSITIONING.get(str(brand.get("positioning", "mass")), {}) as Dictionary).get("premium", 1.0))
	var fame_factor: float = 1.0 + clampf(float(brand.get("fame", 0.0)), 0.0, 100.0) / 200.0
	var rel_factor: float = 0.6 + clampf(float(brand.get("relevance", 80.0)), 0.0, 100.0) / 250.0
	return pos * fame_factor * rel_factor


# --- 设计 ---

func _skill_level(skills: Array, discipline: String) -> float:
	var skill_id: String = str((DISCIPLINES.get(discipline, {}) as Dictionary).get("skill", ""))
	for s in skills:
		if str((s as Dictionary).get("content_key", "")) == skill_id:
			return float((s as Dictionary).get("level", 0))
	return 0.0


## 潮流契合唱：作品学科命中热门学科时按阶段给分，否则为基线。
func trend_fit(discipline: String, trend: Dictionary) -> float:
	if trend.is_empty():
		return 0.5
	var hot: String = str(trend.get("hot_discipline", ""))
	if hot != discipline:
		return 0.25
	var phase: String = str(trend.get("phase", "emerging"))
	match phase:
		"emerging":
			return 1.0
		"rising":
			return 0.9
		"peak":
			return 0.8
		"declining":
			return 0.4
	return 0.5


## 创作作品：评分 = 技能×0.45 + 灵感×0.20 + 潮流契合×0.35 − 抄袭惩罚。
func create_design(discipline: String, skills: Array, trend: Dictionary = {}, rng = null, opts: Dictionary = {}) -> Dictionary:
	if not DISCIPLINES.has(discipline):
		return {"ok": false, "reason": "bad_discipline"}
	var skill_level: float = float(opts.get("skill_level", _skill_level(skills, discipline)))
	var inspiration: float = float(opts.get("inspiration", -1.0))
	if inspiration < 0.0:
		inspiration = (rng.next_float() * 100.0) if rng != null else 50.0
	var fit: float = float(opts.get("trend_fit", trend_fit(discipline, trend)))
	var plagiarized: bool = bool(opts.get("plagiarized", false))
	var similarity: float = clampf(float(opts.get("similarity", 0.0)), 0.0, 1.0)
	var penalty: float = PLAGIARISM_PENALTY * similarity if plagiarized else 0.0
	var score: float = clampf(
		SKILL_WEIGHT * clampf(skill_level / 20.0 * 100.0, 0.0, 100.0)
		+ INSPIRATION_WEIGHT * clampf(inspiration, 0.0, 100.0)
		+ TREND_WEIGHT * clampf(fit, 0.0, 1.0) * 100.0
		- penalty,
		0.0, 100.0)
	return {
		"ok": true, "discipline": discipline, "score": score, "grade": grade_of(score),
		"inspiration": inspiration, "trend_fit": fit, "plagiarized": plagiarized, "similarity": similarity,
	}


static func grade_of(score: float) -> String:
	if score >= 85.0:
		return "masterpiece"
	if score >= 70.0:
		return "excellent"
	if score >= 50.0:
		return "competent"
	return "mediocre"


# --- 时尚周期 ---

func new_trend(opts: Dictionary = {}) -> Dictionary:
	var phase: String = str(opts.get("phase", TREND_PHASES[0]))
	if not TREND_PHASES.has(phase):
		phase = TREND_PHASES[0]
	var season: String = str(opts.get("season", "ss"))
	if not SEASONS.has(season):
		season = "ss"
	return {
		"hot_discipline": str(opts.get("hot_discipline", "apparel")),
		"phase": phase, "season": season,
		"intensity": clampf(float(opts.get("intensity", 0.5)), 0.0, 1.0),
	}


## 推进潮流：新兴→上升→顶峰→退潮→新周期（换热门学科）。
func advance_trend(trend: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var idx: int = TREND_PHASES.find(str(trend.get("phase", "emerging")))
	if idx < 0 or idx >= TREND_PHASES.size() - 1:
		var keys: Array = DISCIPLINES.keys()
		var next_hot: String = str(opts.get("next_hot", keys[(keys.find(str(trend.get("hot_discipline", "apparel"))) + 1) % keys.size()]))
		trend["phase"] = TREND_PHASES[0]
		trend["hot_discipline"] = next_hot
		trend["intensity"] = clampf(float(trend.get("intensity", 0.5)) + 0.1, 0.0, 1.0)
	else:
		trend["phase"] = TREND_PHASES[idx + 1]
	return {"ok": true, "phase": str(trend["phase"]), "hot_discipline": str(trend["hot_discipline"])}


## 引领 vs 跟潮：品牌在新兴/上升期以高声誉发布为引领，顶峰/退潮期发布为跟潮。
func leading_or_following(brand: Dictionary, trend: Dictionary) -> String:
	var phase: String = str(trend.get("phase", "emerging"))
	var rep: float = clampf(float(brand.get("reputation", 50.0)), 0.0, 100.0)
	if (phase == "emerging" or phase == "rising") and rep >= 60.0:
		return "leading"
	return "following"


## 时装周：按作品评分与品牌影响力结算订单、热度与品牌溢价。
func fashion_week(brand: Dictionary, designs: Array, opts: Dictionary = {}) -> Dictionary:
	var season: String = str(opts.get("season", "ss"))
	var season_demand: float = float((SEASONS.get(season, {}) as Dictionary).get("demand", 1.0))
	var total_score: float = 0.0
	for d in designs:
		total_score += float((d as Dictionary).get("score", 0.0))
	var avg: float = total_score / maxf(1.0, float(designs.size()))
	var premium: float = brand_premium(brand)
	var orders: int = int(round(avg * float(designs.size()) * BASE_ORDER_VALUE * premium * season_demand / 100.0))
	brand["fame"] = clampf(float(brand.get("fame", 0.0)) + avg / 20.0, 0.0, 100.0)
	brand["relevance"] = clampf(float(brand.get("relevance", 80.0)) + 2.0, 0.0, 100.0)
	return {"ok": true, "season": season, "avg_score": avg, "orders": orders, "premium": premium, "fame": float(brand["fame"])}


## 联名：合作方声誉越高，热度与收入越高。
func collab(brand: Dictionary, partner_fame: float, opts: Dictionary = {}) -> Dictionary:
	var p: float = clampf(partner_fame, 0.0, 100.0)
	var hype: float = (p / 100.0) * float(opts.get("hype_factor", 1.0))
	var revenue: int = int(round(hype * float(opts.get("base_revenue", 5000000))))
	brand["money"] = int(brand["money"]) + revenue
	brand["fame"] = clampf(float(brand.get("fame", 0.0)) + hype * 10.0, 0.0, 100.0)
	return {"ok": true, "hype": hype, "revenue": revenue, "fame": float(brand["fame"])}


## 限量发售：稀缺提升品牌价值与溢价，库存计入。
func limited_edition(brand: Dictionary, item_key: String, qty: int, base_value: int = 0) -> Dictionary:
	var amount: int = maxi(1, qty)
	var value: int = maxi(1, base_value if base_value > 0 else int((LUXURY_ITEMS.get(item_key, {}) as Dictionary).get("base_value", 10000)))
	var scarcity: float = clampf(1000.0 / float(amount), 0.0, 5.0)
	var price: int = int(round(float(value) * (1.0 + scarcity * 0.2)))
	var inventory: Dictionary = brand["inventory"]
	var entry: Dictionary = inventory.get(item_key, {"qty": 0, "price": price})
	entry["qty"] = int(entry.get("qty", 0)) + amount
	entry["price"] = price
	inventory[item_key] = entry
	brand["brand_value"] = int(brand.get("brand_value", 0)) + price * amount / 10
	brand["relevance"] = clampf(float(brand.get("relevance", 80.0)) + 3.0, 0.0, 100.0)
	return {"ok": true, "item": item_key, "qty": amount, "scarcity": scarcity, "price": price}


# --- 品牌经营 ---

func open_store(brand: Dictionary, cost: int, region_id: String = "") -> Dictionary:
	var amount: int = maxi(0, cost)
	if int(brand.get("money", 0)) < amount:
		return {"ok": false, "reason": "insufficient_funds", "cost": amount}
	brand["money"] = int(brand["money"]) - amount
	(brand["stores"] as Array).append({"region_id": region_id, "cost": amount})
	brand["relevance"] = clampf(float(brand.get("relevance", 80.0)) + 1.0, 0.0, 100.0)
	return {"ok": true, "stores": (brand["stores"] as Array).size()}


func run_marketing(brand: Dictionary, kind: String, cost: int, rng = null, opts: Dictionary = {}) -> Dictionary:
	if not MARKETING.has(kind):
		return {"ok": false, "reason": "unknown_marketing"}
	var def: Dictionary = MARKETING[kind]
	var spend: int = maxi(0, cost)
	if int(brand.get("money", 0)) < spend:
		return {"ok": false, "reason": "insufficient_funds", "cost": spend}
	brand["money"] = int(brand["money"]) - spend
	var gain: float = float(def["fame"]) * clampf(float(spend) / 1000000.0, 0.0, 3.0)
	brand["fame"] = clampf(float(brand.get("fame", 0.0)) + gain, 0.0, 100.0)
	brand["relevance"] = clampf(float(brand.get("relevance", 80.0)) + gain * 0.5, 0.0, 100.0)
	var backlash: bool = false
	var risk: float = float(def["backlash"])
	if risk > 0.0:
		backlash = _roll(float(opts.get("roll", -1.0)), rng) < risk
	if backlash:
		brand["reputation"] = clampf(float(brand.get("reputation", 50.0)) - 10.0, 0.0, 100.0)
	return {"ok": true, "kind": kind, "fame": float(brand["fame"]), "backlash": backlash}


## 品牌老化：时间推移使相关度下降。
func brand_aging(brand: Dictionary, years: float) -> Dictionary:
	var y: float = maxf(0.0, years)
	var rate: float = float((POSITIONING.get(str(brand.get("positioning", "mass")), {}) as Dictionary).get("aging_rate", 0.04))
	brand["age_years"] = float(brand.get("age_years", 0.0)) + y
	brand["relevance"] = clampf(float(brand.get("relevance", 80.0)) - rate * y * 10.0, 0.0, 100.0)
	return {"ok": true, "age_years": float(brand["age_years"]), "relevance": float(brand["relevance"])}


## 品牌复兴：投入重塑相关度与声誉。
func renew_brand(brand: Dictionary, strategy: String, cost: int, opts: Dictionary = {}) -> Dictionary:
	var spend: int = maxi(0, cost)
	if int(brand.get("money", 0)) < spend:
		return {"ok": false, "reason": "insufficient_funds", "cost": spend}
	var gain: float = clampf(float(spend) / 500000.0, 0.0, 30.0)
	if strategy == "designer_change":
		gain *= 1.2
	elif strategy == "heritage":
		gain *= 0.8
	brand["money"] = int(brand["money"]) - spend
	brand["relevance"] = clampf(float(brand.get("relevance", 80.0)) + gain, 0.0, 100.0)
	brand["reputation"] = clampf(float(brand.get("reputation", 50.0)) + gain * 0.3, 0.0, 100.0)
	return {"ok": true, "relevance": float(brand["relevance"]), "reputation": float(brand["reputation"])}


# --- 代言人 ---

## 签约代言人：付出成本获得热度；代言人丑闻风险随之提升。
func endorse(brand: Dictionary, celebrity: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var cost: int = maxi(0, int(celebrity.get("cost", opts.get("cost", 1000000))))
	if int(brand.get("money", 0)) < cost:
		return {"ok": false, "reason": "insufficient_funds", "cost": cost}
	brand["money"] = int(brand["money"]) - cost
	var fame: float = clampf(float(celebrity.get("fame", 50.0)), 0.0, 100.0)
	var rec: Dictionary = {
		"id": str(celebrity.get("id", "star")),
		"name": str(celebrity.get("name", "代言人")),
		"fame": fame,
		"scandal_risk": clampf(float(celebrity.get("scandal_risk", 0.2)), 0.0, 1.0),
		"active": true,
	}
	(brand["endorsers"] as Array).append(rec)
	brand["fame"] = clampf(float(brand.get("fame", 0.0)) + fame / 20.0, 0.0, 100.0)
	return {"ok": true, "endorser": rec, "cost": cost}


## 代言翻车：按 roll 命中风险则解除代言、声誉与热度受损。
func endorser_scandal(brand: Dictionary, roll: float, opts: Dictionary = {}) -> Dictionary:
	var endorsers: Array = brand["endorsers"]
	if endorsers.is_empty():
		return {"ok": false, "reason": "no_endorser"}
	var target: Dictionary = endorsers[0]
	var risk: float = clampf(float(target.get("scandal_risk", 0.2)), 0.0, 1.0)
	var r: float = clampf(roll, 0.0, 1.0)
	if r >= risk and not bool(opts.get("force", false)):
		return {"ok": true, "scandal": false, "risk": risk}
	target["active"] = false
	brand["reputation"] = clampf(float(brand.get("reputation", 50.0)) - 15.0, 0.0, 100.0)
	brand["fame"] = clampf(float(brand.get("fame", 0.0)) - 8.0, 0.0, 100.0)
	return {"ok": true, "scandal": true, "endorser": str(target.get("name", "")), "reputation": float(brand["reputation"])}


# --- 奢侈品市场 ---

## 鉴定真伪：provenance ∈ [0,1] 提升判真置信；可用 opts.roll 强制判定。
func authenticate(item: Dictionary, opts: Dictionary = {}, rng = null) -> Dictionary:
	var authentic: bool = bool(item.get("authentic", true))
	var provenance: float = clampf(float(item.get("provenance", 0.5)), 0.0, 1.0)
	var genuine_confidence: float = clampf(0.5 + provenance * 0.4, 0.0, 0.95)
	var roll: float = _roll(float(opts.get("roll", -1.0)), rng)
	var result: String = AUTH_GENUINE
	if authentic:
		if roll <= genuine_confidence:
			result = AUTH_GENUINE
		else:
			result = AUTH_UNCERTAIN
	else:
		if roll < provenance * 0.4:
			result = AUTH_COUNTERFEIT
		else:
			result = AUTH_UNCERTAIN
	return {"ok": true, "result": result, "confidence": genuine_confidence, "authentic": authentic}


## 二手流通：按品相折价。
func secondhand_price(item: Dictionary, condition: float) -> Dictionary:
	var value: int = maxi(0, int(item.get("value", item.get("base_value", 0))))
	var cond: float = clampf(condition, 0.0, 1.0)
	var price: int = int(round(float(value) * (0.3 + cond * 0.6)))
	return {"ok": true, "price": price, "condition": cond}


## 拍卖：高于保留价则成交，成交价为最高出价。
func auction(item: Dictionary, bids: Array, opts: Dictionary = {}) -> Dictionary:
	var reserve: int = maxi(0, int(opts.get("reserve", int(item.get("value", 0)))))
	var highest: int = 0
	for b in bids:
		highest = maxi(highest, int(b))
	var sold: bool = highest >= reserve and highest > 0
	return {"ok": true, "sold": sold, "price": highest, "reserve": reserve}


## 收藏保值：按年化收益复利估值；偏离基准超过阈值标记泡沫风险。
func collectible_value(base_value: int, years: float, annual_return: float = 0.05) -> Dictionary:
	var v: float = float(maxi(0, base_value)) * pow(1.0 + annual_return, maxf(0.0, years))
	var value: int = int(round(v))
	var bubble: bool = annual_return > BUBBLE_THRESHOLD * 0.05
	return {"ok": true, "value": value, "annual_return": annual_return, "bubble_risk": bubble}


## 假货侵权：仿品分流正品销量，造成损失；品牌声誉受冲击。
func counterfeit_hit(brand: Dictionary, base_loss: int, opts: Dictionary = {}) -> Dictionary:
	var loss: int = maxi(0, base_loss)
	var patent: bool = bool(opts.get("patent", false))
	if patent:
		var recovered: int = int(float(loss) * 0.8)
		brand["money"] = int(brand["money"]) + recovered
		return {"ok": true, "loss": loss, "recovered": recovered, "litigation": true}
	brand["reputation"] = clampf(float(brand.get("reputation", 50.0)) - 5.0, 0.0, 100.0)
	return {"ok": true, "loss": loss, "recovered": 0, "litigation": false}


# --- 边界：抄袭指控 ---

## 抄袭指控：相似度越高越可能被认定，判定后品牌声誉下滑并可能被判赔。
func plagiarism_accusation(brand: Dictionary, design: Dictionary, similarity: float, rng = null, opts: Dictionary = {}) -> Dictionary:
	var sim: float = clampf(similarity, 0.0, 1.0)
	if sim < 0.5 and not bool(opts.get("force", false)):
		return {"ok": true, "accused": false, "similarity": sim}
	var threshold: float = clampf(sim * 0.8, 0.0, 1.0)
	var roll: float = _roll(float(opts.get("roll", -1.0)), rng)
	var guilty: bool = roll < threshold or bool(opts.get("force", false))
	var damages: int = 0
	if guilty:
		damages = int(round(float(maxi(0, int(design.get("value", 1000000)))) * sim))
		brand["reputation"] = clampf(float(brand.get("reputation", 50.0)) - 12.0 * sim, 0.0, 100.0)
		brand["money"] = int(brand["money"]) - damages
	return {"ok": true, "accused": true, "guilty": guilty, "similarity": sim, "damages": damages, "reputation": float(brand["reputation"])}


func _roll(forced: float, rng) -> float:
	if forced >= 0.0:
		return clampf(forced, 0.0, 1.0)
	if rng != null:
		return rng.next_float()
	return 0.0


func to_dict(brand: Dictionary) -> Dictionary:
	return brand.duplicate(true)


func from_dict(data: Dictionary) -> Dictionary:
	return data.duplicate(true)
