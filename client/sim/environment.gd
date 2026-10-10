class_name EnvironmentSystem
extends RefCounted
## 环保、碳排与可持续发展（R81；design D37）。
##
## 覆盖：
##   - 市政环保：垃圾分类/回收/污水处理/空气治理/排污许可；
##   - 企业碳排：碳排属性、超标购买配额或受罚、碳交易、碳足迹核算与 ESG 评级；
##   - 从业：环保企业/环保 NGO/绿色能源/环保工程；
##   - 后果：污染曝光影响区域健康、声誉与法律后果，支持环境诉讼；
##   - 可持续：绿色补贴、低碳转型成本与机遇；
##   - 边界：偷排与数据造假、环保投入挤压利润、绿色补贴骗补、邻避效应。
##
## 设计取舍：
##   - 城市环保状态与企业碳排状态均为纯数据 Dictionary，便于存读档与 headless 测试；
##   - ESG 得分对企业碳排强度单调递减，便于属性测试；
##   - 偷排/造假以隐蔽标记存在，结合隐蔽度与 roll 判定是否被查获，形成“偷排—查获—追责”闭环；
##   - 碳交易在系统内维护单个企业的配额/信用，跨企业市场由后端宏观系统承接（不在此重复）。

const CAREER_ENV_COMPANY: String = "env_company"
const CAREER_ENV_NGO: String = "env_ngo"
const CAREER_GREEN_ENERGY: String = "green_energy"
const CAREER_ENV_ENGINEERING: String = "env_engineering"

const CAREERS: Dictionary = {
	"env_company": {"name": "环保企业", "base_cost": 1000000, "margin": 0.20},
	"env_ngo": {"name": "环保 NGO", "base_cost": 100000, "margin": 0.05},
	"green_energy": {"name": "绿色能源", "base_cost": 5000000, "margin": 0.18},
	"env_engineering": {"name": "环保工程", "base_cost": 2000000, "margin": 0.15},
}

const BaselineScript = preload("res://sim/baseline.gd")

const DEFAULT_CARBON_PRICE: int = BaselineScript.ENV_DEFAULT_CARBON_PRICE
const FINE_MULTIPLIER: float = BaselineScript.ENV_CARBON_FINE_MULTIPLIER


# --- 数据表 ---

func career_keys() -> Array:
	return CAREERS.keys()


func career_def(key: String) -> Dictionary:
	if not CAREERS.has(key):
		return {}
	return (CAREERS[key] as Dictionary).duplicate(true)


func _roll(forced: float, rng) -> float:
	if forced >= 0.0:
		return clampf(forced, 0.0, 1.0)
	if rng != null:
		return rng.next_float()
	return 0.0


# --- 市政环保 ---

func new_city_env(population: int, opts: Dictionary = {}) -> Dictionary:
	return {
		"population": maxi(0, population),
		"garbage_sorting": clampf(float(opts.get("garbage_sorting", 0.3)), 0.0, 1.0),
		"recycling_rate": clampf(float(opts.get("recycling_rate", 0.2)), 0.0, 1.0),
		"sewage_treatment": clampf(float(opts.get("sewage_treatment", 0.5)), 0.0, 1.0),
		"air_quality": clampf(float(opts.get("air_quality", 0.6)), 0.0, 1.0),
		"pollution": clampf(float(opts.get("pollution", 0.2)), 0.0, 1.0),
		"health_index": clampf(float(opts.get("health_index", 1.0)), 0.0, 1.0),
		"reputation": clampf(float(opts.get("reputation", 1.0)), 0.0, 1.0),
		"lawsuit_open": false,
		"permits": {},
		"projects": [],
	}


func set_garbage_sorting(city: Dictionary, rate: float) -> Dictionary:
	city["garbage_sorting"] = clampf(rate, 0.0, 1.0)
	return {"ok": true, "garbage_sorting": float(city["garbage_sorting"])}


## 回收：按分类率与回收率从垃圾中回收资源。
func recycle(city: Dictionary, generated: float, opts: Dictionary = {}) -> Dictionary:
	var sorting: float = clampf(float(city.get("garbage_sorting", 0.0)), 0.0, 1.0)
	var rate: float = clampf(float(city.get("recycling_rate", 0.0)), 0.0, 1.0)
	var recovered: float = maxf(0.0, generated) * sorting * rate
	return {"ok": true, "recovered": recovered, "landfill": maxf(0.0, generated) - recovered}


func treat_sewage(city: Dictionary, rate: float) -> Dictionary:
	city["sewage_treatment"] = clampf(rate, 0.0, 1.0)
	# 污水处理削减水体污染。
	city["pollution"] = clampf(float(city["pollution"]) - (1.0 - float(city["sewage_treatment"])) * 0.05, 0.0, 1.0)
	return {"ok": true, "sewage_treatment": float(city["sewage_treatment"])}


## 空气治理：投入越大，空气质量越高、污染越低（边际递减）。
func air_control(city: Dictionary, investment: int) -> Dictionary:
	var gain: float = clampf(float(maxi(0, investment)) / 5000000.0, 0.0, 0.4)
	city["air_quality"] = clampf(float(city["air_quality"]) + gain, 0.0, 1.0)
	city["pollution"] = clampf(float(city["pollution"]) - gain * 0.5, 0.0, 1.0)
	return {"ok": true, "air_quality": float(city["air_quality"]), "pollution": float(city["pollution"])}


## 排污许可：登记排放源与允许额度。
func issue_permit(city: Dictionary, source: String, allowance: float) -> Dictionary:
	(city["permits"] as Dictionary)[source] = {"allowance": maxf(0.0, allowance), "used": 0.0}
	return {"ok": true, "source": source, "allowance": maxf(0.0, allowance)}


## 综合污染指数：越高污染越重（0..1）。
func pollution_index(city: Dictionary) -> float:
	var p: float = clampf(float(city.get("pollution", 0.0)), 0.0, 1.0)
	var air_penalty: float = (1.0 - clampf(float(city.get("air_quality", 0.5)), 0.0, 1.0)) * 0.3
	return clampf(p + air_penalty, 0.0, 1.0)


# --- 企业碳排 ---

func new_enterprise(name: String, opts: Dictionary = {}) -> Dictionary:
	return {
		"name": name,
		"emissions": maxf(0.0, float(opts.get("emissions", 100.0))),
		"quota": maxf(0.0, float(opts.get("quota", 100.0))),
		"credits": float(opts.get("credits", 0.0)),
		"carbon_price": int(opts.get("carbon_price", DEFAULT_CARBON_PRICE)),
		"carbon_cost": 0,
		"fines": 0,
		"green_investment": 0,
		"esg": clampf(float(opts.get("esg", 60.0)), 0.0, 100.0),
		"fraud": false,
		"illegal_discharge": false,
	}


func set_emissions(ent: Dictionary, amount: float) -> Dictionary:
	ent["emissions"] = maxf(0.0, amount)
	return {"ok": true, "emissions": float(ent["emissions"]), "balance": carbon_balance(ent)}


## 碳平衡 = 实际排放 −（配额 + 已购信用）。正值代表超标。
func carbon_balance(ent: Dictionary) -> float:
	return float(ent.get("emissions", 0.0)) - (float(ent.get("quota", 0.0)) + float(ent.get("credits", 0.0)))


## 合规结算：超标时购买配额或接受罚款。opts: mode(buy/fine)/price/fine_per_unit。
func compliance(ent: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var balance: float = carbon_balance(ent)
	if balance <= 0.0:
		return {"ok": true, "compliant": true, "balance": balance, "action": "none", "cost": 0}
	var price: float = float(opts.get("price", ent.get("carbon_price", DEFAULT_CARBON_PRICE)))
	var mode: String = str(opts.get("mode", "buy"))
	if mode == "fine":
		var fine: int = int(round(balance * price * float(opts.get("fine_per_unit", FINE_MULTIPLIER))))
		ent["fines"] = int(ent.get("fines", 0)) + fine
		ent["esg"] = clampf(float(ent.get("esg", 60.0)) - 10.0, 0.0, 100.0)
		return {"ok": true, "compliant": false, "balance": balance, "action": "fine", "cost": fine, "fines": int(ent["fines"])}
	var cost: int = int(round(balance * price))
	ent["credits"] = float(ent.get("credits", 0.0)) + balance
	ent["carbon_cost"] = int(ent.get("carbon_cost", 0)) + cost
	return {"ok": true, "compliant": true, "balance": 0.0, "action": "buy", "cost": cost, "credits": float(ent["credits"])}


## 碳交易：credits 为正买入、为负卖出。返回成本（正）或收益（负）。
func carbon_trade(ent: Dictionary, credits: float, price: int = -1, opts: Dictionary = {}) -> Dictionary:
	var p: int = price if price >= 0 else int(ent.get("carbon_price", DEFAULT_CARBON_PRICE))
	var amount: float = credits
	var cash: int = int(round(amount * float(p)))
	ent["credits"] = float(ent.get("credits", 0.0)) + amount
	ent["carbon_cost"] = int(ent.get("carbon_cost", 0)) + cash
	return {"ok": true, "credits": float(ent["credits"]), "price": p, "cash": cash, "balance": carbon_balance(ent)}


## 碳足迹核算：总量与按范围拆分的示意值。
func carbon_footprint(ent: Dictionary) -> Dictionary:
	var total: float = float(ent.get("emissions", 0.0))
	var scope1: float = total * BaselineScript.ENV_FOOTPRINT_SCOPE1
	var scope2: float = total * BaselineScript.ENV_FOOTPRINT_SCOPE2
	var scope3: float = total * BaselineScript.ENV_FOOTPRINT_SCOPE3
	return {"total": total, "scope1": scope1, "scope2": scope2, "scope3": scope3}


## ESG 评级：碳排强度越低得分越高，绿色投入加分，罚款/造假/偷排减分。
func esg_rating(ent: Dictionary) -> Dictionary:
	var quota: float = maxf(1.0, float(ent.get("quota", 1.0)))
	var ratio: float = float(ent.get("emissions", 0.0)) / quota
	var score: float = BaselineScript.ENV_ESG_SCORE_MAX * clampf(1.0 - ratio * BaselineScript.ENV_ESG_EMISSION_PENALTY, 0.0, 1.0)
	score += clampf(float(ent.get("green_investment", 0)) / BaselineScript.ENV_ESG_GREEN_INVESTMENT_UNIT, 0.0, BaselineScript.ENV_ESG_GREEN_INVESTMENT_CAP)
	score -= float(ent.get("fines", 0)) / BaselineScript.ENV_ESG_FINE_DIVISOR
	if bool(ent.get("fraud", false)):
		score -= BaselineScript.ENV_ESG_FRAUD_PENALTY
	if bool(ent.get("illegal_discharge", false)):
		score -= BaselineScript.ENV_ESG_ILLEGAL_PENALTY
	score = clampf(score, 0.0, 100.0)
	var grade: String = "D"
	if score >= BaselineScript.ENV_ESG_GRADE_A:
		grade = "A"
	elif score >= BaselineScript.ENV_ESG_GRADE_B:
		grade = "B"
	elif score >= BaselineScript.ENV_ESG_GRADE_C:
		grade = "C"
	ent["esg"] = score
	return {"ok": true, "score": score, "grade": grade}


## 碳数据申报：低报即构成数据造假标记，可能被查获。
func report_carbon(ent: Dictionary, reported: float, opts: Dictionary = {}, rng = null) -> Dictionary:
	var actual: float = float(ent.get("emissions", 0.0))
	var understated: bool = reported < actual - 0.001
	var detected: bool = false
	if understated:
		ent["fraud"] = true
		var risk: float = clampf(float(opts.get("detect_risk", 0.3)), 0.0, 1.0)
		detected = _roll(float(opts.get("roll", -1.0)), rng) < risk
	return {"ok": true, "reported": reported, "actual": actual, "understated": understated, "detected": detected, "fraud": bool(ent.get("fraud", false))}


# --- 从业 ---

func new_career_org(kind: String, opts: Dictionary = {}) -> Dictionary:
	if not CAREERS.has(kind):
		return {"ok": false, "reason": "unknown_career"}
	var def: Dictionary = CAREERS[kind]
	return {
		"ok": true,
		"org": {
			"kind": kind, "name": str(opts.get("name", def["name"])),
			"funds": maxi(0, int(opts.get("funds", 0))),
			"reputation": clampf(float(opts.get("reputation", 0.5)), 0.0, 1.0),
			"emission_cut": 0.0, "projects": [],
		},
	}


## 承接环保项目：成本与营收随预算与声誉变化，绿色技术降低排放。
func run_project(org: Dictionary, name: String, budget: int, opts: Dictionary = {}) -> Dictionary:
	var def: Dictionary = CAREERS.get(str(org.get("kind", "")), {})
	var margin: float = float(def.get("margin", 0.15))
	var revenue: int = int(round(float(maxi(0, budget)) * (1.0 + margin)))
	var cut: float = float(opts.get("emission_cut", 0.0)) * (1.0 + float(org.get("reputation", 0.0)))
	var project: Dictionary = {"name": name, "budget": maxi(0, budget), "revenue": revenue, "emission_cut": cut}
	(org["projects"] as Array).append(project)
	org["funds"] = int(org.get("funds", 0)) + revenue - maxi(0, budget)
	org["emission_cut"] = float(org.get("emission_cut", 0.0)) + cut
	org["reputation"] = clampf(float(org.get("reputation", 0.0)) + 0.02, 0.0, 1.0)
	return {"ok": true, "project": project, "profit": revenue - maxi(0, budget), "funds": int(org["funds"])}


# --- 后果与诉讼 ---

## 污染事件：抬高区域污染、压低空气质量与健康。
func pollute(city: Dictionary, severity: float, opts: Dictionary = {}) -> Dictionary:
	var sev: float = clampf(severity, 0.0, 1.0)
	city["pollution"] = clampf(float(city["pollution"]) + sev * 0.3, 0.0, 1.0)
	city["air_quality"] = clampf(float(city["air_quality"]) - sev * 0.2, 0.0, 1.0)
	city["health_index"] = clampf(float(city["health_index"]) - sev * 0.1, 0.0, 1.0)
	var event: Dictionary = {"source": str(opts.get("source", "")), "severity": sev, "minute": int(opts.get("minute", 0))}
	(city["projects"] as Array).append(event)
	return {"ok": true, "pollution": float(city["pollution"]), "health_index": float(city["health_index"])}


## 污染曝光：按污染指数结算健康、声誉与法律后果。
func expose_pollution(city: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var idx: float = pollution_index(city)
	var reputation_delta: float = -round(idx * 30.0)
	city["reputation"] = clampf(float(city["reputation"]) + reputation_delta / 100.0, 0.0, 1.0)
	var health_effect: float = -round(idx * 20.0) / 100.0
	city["health_index"] = clampf(float(city["health_index"]) + health_effect, 0.0, 1.0)
	var legal: bool = idx >= 0.5 or bool(opts.get("illegal", false))
	if legal:
		city["lawsuit_open"] = true
	return {
		"ok": true, "pollution_index": idx, "health_effect": health_effect,
		"reputation_delta": reputation_delta, "legal": legal,
		"lawsuit_open": bool(city["lawsuit_open"]),
	}


## 环境诉讼：按污染指数判定责任与赔偿。
func environmental_lawsuit(city: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var idx: float = pollution_index(city)
	var liable: bool = idx >= 0.5
	var compensation: int = int(round(idx * float(opts.get("base_compensation", 2000000))))
	if liable:
		city["reputation"] = clampf(float(city["reputation"]) - 0.1, 0.0, 1.0)
	return {"ok": true, "liable": liable, "compensation": compensation, "pollution_index": idx}


# --- 可持续与边界 ---

## 绿色补贴：申请与发放；骗补会被查获。
func green_subsidy(org: Dictionary, amount: int, opts: Dictionary = {}, rng = null) -> Dictionary:
	var granted: int = maxi(0, amount)
	var claim: bool = bool(opts.get("fraud", false))
	var detected: bool = false
	if claim:
		detected = _roll(float(opts.get("roll", -1.0)), rng) < clampf(float(opts.get("detect_risk", 0.4)), 0.0, 1.0)
		if detected:
			granted = 0
			org["reputation"] = clampf(float(org.get("reputation", 0.0)) - 0.25, 0.0, 1.0)
			org["fraud"] = true
		else:
			org["reputation"] = clampf(float(org.get("reputation", 0.0)) + 0.05, 0.0, 1.0)
	org["funds"] = int(org.get("funds", 0)) + granted
	return {"ok": true, "granted": granted, "fraud": claim, "detected": detected, "funds": int(org["funds"])}


## 低碳转型：投入换减排，并带来绿色机遇溢价。
func low_carbon_transition(ent: Dictionary, investment: int, opts: Dictionary = {}) -> Dictionary:
	var inv: int = maxi(0, investment)
	var cut: float = clampf(float(inv) / 1000000.0 * float(opts.get("cut_per_million", 5.0)), 0.0, float(ent.get("emissions", 0.0)))
	ent["emissions"] = maxf(0.0, float(ent.get("emissions", 0.0)) - cut)
	ent["green_investment"] = int(ent.get("green_investment", 0)) + inv
	ent["carbon_cost"] = int(ent.get("carbon_cost", 0)) + inv
	var opportunity: int = int(round(float(inv) * clampf(float(opts.get("opportunity_rate", 0.1)), 0.0, 1.0)))
	return {"ok": true, "cost": inv, "emission_cut": cut, "emissions": float(ent["emissions"]), "opportunity": opportunity}


## 偷排：以隐蔽标记存在并提高排放，可能被查获。
func illegal_discharge(ent: Dictionary, amount: float, opts: Dictionary = {}, rng = null) -> Dictionary:
	ent["emissions"] = maxf(0.0, float(ent.get("emissions", 0.0)) + maxf(0.0, amount))
	ent["illegal_discharge"] = true
	var detected: bool = _roll(float(opts.get("roll", -1.0)), rng) < clampf(float(opts.get("detect_risk", 0.3)), 0.0, 1.0)
	if detected:
		ent["illegal_discharge"] = false
		ent["fines"] = int(ent.get("fines", 0)) + int(round(maxf(0.0, amount) * float(ent.get("carbon_price", DEFAULT_CARBON_PRICE)) * FINE_MULTIPLIER))
	return {"ok": true, "emissions": float(ent["emissions"]), "detected": detected, "fines": int(ent.get("fines", 0))}


## 环保投入挤压利润：投入占营收比例越高，当期利润率越低。
func investment_profit_squeeze(base_margin: float, investment_ratio: float) -> Dictionary:
	var ratio: float = clampf(investment_ratio, 0.0, 1.0)
	var margin: float = clampf(base_margin, 0.0, 1.0) * (1.0 - ratio)
	return {"ok": true, "margin": margin, "compressed_by": clampf(base_margin, 0.0, 1.0) - margin}


## 邻避效应：设施越靠近居民/规模越大，反对越强，可能延期或取消。
func nimby(city: Dictionary, project: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var scale: float = clampf(float(opts.get("scale", 0.5)), 0.0, 1.0)
	var near: float = clampf(float(opts.get("near_residents", 0.5)), 0.0, 1.0)
	var reputation: float = clampf(float(city.get("reputation", 0.5)), 0.0, 1.0)
	var opposition: float = clampf(scale * 0.5 + near * 0.5 - reputation * 0.2, 0.0, 1.0)
	var delay_days: int = int(round(opposition * float(opts.get("max_delay_days", 365))))
	var cancelled: bool = opposition >= float(opts.get("cancel_threshold", 0.85))
	return {"ok": true, "opposition": opposition, "delay_days": delay_days, "cancelled": cancelled}


# --- 序列化 ---

func to_dict(state: Dictionary) -> Dictionary:
	return state.duplicate(true)


func from_dict(data: Dictionary) -> Dictionary:
	return data.duplicate(true)
