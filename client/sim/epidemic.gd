class_name EpidemicSystem
extends RefCounted
## 流行病与公共卫生（R61；design D17）。
##
## 覆盖：
##   - 区域 SEIR（易感/潜伏/感染/移除）传播模型，参数 beta/sigma/gamma + 死亡率/免疫期/变异率，跨区域按交通流扩散；
##   - 疫情阶段：爆发 → 扩散 → 峰值 → 回落 → 消退，及预警分级；
##   - 防疫政策：隔离/停工/停课/口罩/出行限制/疫苗强制，强制生效并带来经济代价与民意反弹；
##   - 医疗资源：检测/疫苗/住院/公卫职业，床位/医护/呼吸机为区域资源；
##   - 医院挤兑：占用率超阈值后死亡率上升、就医成功率下降；
##   - 个人应对（防护/就医/接种/囤药/居家）经 MedicalSystem 与防护系数衔接。
##
## 设计取舍：
##   - 区域疫情状态为纯数据 Dictionary，便于存读档与 headless 测试；
##   - 政策对传播率的抑制用独立的 POLICY_BETA_REDUCTION 权重叠加，便于配置；
##   - 挤兑死亡率惩罚用占用率超阈值的线性附加，简单可解释；
##   - 所有随机（疫苗接种意愿、变异）均由外部 rng 注入，缺省时确定化。

const STAGE_SUSCEPTIBLE: String = "susceptible"
const STAGE_OUTBREAK: String = "outbreak"
const STAGE_SPREADING: String = "spreading"
const STAGE_PEAK: String = "peak"
const STAGE_DECLINING: String = "declining"
const STAGE_RESOLVED: String = "resolved"

const STAGE_NAMES: Dictionary = {
	"susceptible": "无疫情", "outbreak": "爆发", "spreading": "扩散",
	"peak": "峰值", "declining": "回落", "resolved": "消退",
}

## 防疫政策 → 对传播率的相对抑制权重（可叠加）。
const POLICY_BETA_REDUCTION: Dictionary = {
	"quarantine": 0.30, "lockdown": 0.60, "school_closure": 0.20,
	"mask": 0.15, "travel_restriction": 0.25, "vaccine_mandate": 0.10,
}

## 防疫政策 → 每日经济代价系数（用于经济伤疤累积）。
const POLICY_ECONOMY_COST: Dictionary = {
	"quarantine": 0.02, "lockdown": 0.05, "school_closure": 0.02,
	"mask": 0.002, "travel_restriction": 0.03, "vaccine_mandate": 0.004,
}

const DEFAULT_PARAMS: Dictionary = {
	"beta": 0.5, "sigma": 0.2, "gamma": 0.1, "mortality": 0.01,
	"immunity_days": 180.0, "mutation_rate": 0.001,
}

const ALERT_NONE: int = 0
const ALERT_WATCH: int = 1
const ALERT_ALERT: int = 2
const ALERT_EMERGENCY: int = 3


## 新建区域疫情状态。医疗资源默认按人口规模推导。
func new_region(population: int, params: Dictionary = {}, opts: Dictionary = {}) -> Dictionary:
	var p: Dictionary = DEFAULT_PARAMS.duplicate(true)
	for k in params.keys():
		p[k] = params[k]
	var pop: float = maxf(1.0, float(population))
	var policies: Dictionary = {}
	for k in POLICY_BETA_REDUCTION.keys():
		policies[k] = false
	return {
		"population": population,
		"susceptible": pop, "exposed": 0.0, "infectious": 0.0, "removed": 0.0,
		"deaths": 0, "vaccinated": 0.0, "params": p, "policies": policies,
		"stage": STAGE_SUSCEPTIBLE, "alert_level": ALERT_NONE,
		"peak_infectious": 0.0, "economy_scar": 0.0, "public_trust": 1.0,
		"resources": {
			"beds": int(pop / 1000.0), "doctors": int(pop / 500.0),
			"ventilators": int(pop / 20000.0), "test_kits": int(pop / 100.0),
			"vaccine_stock": int(opts.get("vaccine_stock", int(pop / 250.0))),
		},
		"vaccine_hesitancy": float(opts.get("vaccine_hesitancy", 0.2)),
	}


# --- 传播 ---

## 注入初始感染（输入病例）。
func seed(region: Dictionary, count: float) -> Dictionary:
	var c: float = minf(float(count), float(region["susceptible"]))
	region["exposed"] = float(region["exposed"]) + c
	region["susceptible"] = float(region["susceptible"]) - c
	if str(region["stage"]) == STAGE_SUSCEPTIBLE and c > 0.0:
		region["stage"] = STAGE_OUTBREAK
	return {"ok": true, "exposed": float(region["exposed"]), "stage": str(region["stage"])}


## 有效传播率：基础 beta 经政策抑制与变异放大。
func effective_beta(region: Dictionary) -> float:
	var beta: float = float((region["params"] as Dictionary)["beta"])
	var reduction: float = 0.0
	var policies: Dictionary = region["policies"]
	for k in policies.keys():
		if bool(policies[k]):
			reduction += float(POLICY_BETA_REDUCTION.get(k, 0.0))
	reduction = clampf(reduction, 0.0, 0.95)
	return beta * (1.0 - reduction)


## 医院占用率（感染人数 / 床位）。
func hospital_occupancy(region: Dictionary) -> float:
	var beds: float = maxf(1.0, float((region["resources"] as Dictionary)["beds"]))
	return float(region["infectious"]) / beds


## 挤兑惩罚系数：占用率 ≤1 时为 1，超阈值后线性放大。
func surge_factor(region: Dictionary) -> float:
	var occupancy: float = hospital_occupancy(region)
	if occupancy <= 1.0:
		return 1.0
	return 1.0 + (occupancy - 1.0) * 0.5


## 推进 days 天的 SEIR。返回本步统计。
func step(region: Dictionary, days: float, rng = null, opts: Dictionary = {}) -> Dictionary:
	var d: float = maxf(0.0, days)
	var n: float = maxf(1.0, float(region["population"]))
	var s: float = float(region["susceptible"])
	var e: float = float(region["exposed"])
	var i: float = float(region["infectious"])
	var r: float = float(region["removed"])
	var params: Dictionary = region["params"]
	var beta: float = effective_beta(region)
	var sigma: float = float(params["sigma"])
	var gamma: float = float(params["gamma"])
	var mortality: float = float(params["mortality"])
	var new_exposed: float = clampf(beta * s * i / n * d, 0.0, s)
	var new_infectious: float = clampf(sigma * e * d, 0.0, e)
	var surge: float = surge_factor(region)
	var new_removed: float = clampf(gamma * i * d * (1.0 / surge), 0.0, i)
	var new_deaths: float = clampf(mortality * i * d * surge, 0.0, maxf(0.0, i - new_removed))
	s -= new_exposed
	e += new_exposed - new_infectious
	i += new_infectious - new_removed - new_deaths
	r += new_removed
	region["susceptible"] = maxf(0.0, s)
	region["exposed"] = maxf(0.0, e)
	region["infectious"] = maxf(0.0, i)
	region["removed"] = maxf(0.0, r)
	region["deaths"] = int(region["deaths"]) + int(round(new_deaths))
	region["peak_infectious"] = maxf(float(region["peak_infectious"]), float(region["infectious"]))
	_update_stage(region)
	region["alert_level"] = alert_level(region)
	_accumulate_economy(region, d)
	return {
		"ok": true, "exposed": float(region["exposed"]), "infectious": float(region["infectious"]),
		"removed": float(region["removed"]), "deaths": int(region["deaths"]),
		"new_deaths": int(round(new_deaths)), "occupancy": hospital_occupancy(region),
		"surge": surge, "stage": str(region["stage"]), "alert_level": int(region["alert_level"]),
	}


func _update_stage(region: Dictionary) -> void:
	var i: float = float(region["infectious"])
	var peak: float = float(region["peak_infectious"])
	if i <= 0.5 and float(region["removed"]) > 0.0:
		region["stage"] = STAGE_RESOLVED
	elif i <= 0.0:
		region["stage"] = STAGE_SUSCEPTIBLE
	elif peak <= 0.0:
		region["stage"] = STAGE_OUTBREAK
	elif i >= peak * 0.98:
		region["stage"] = STAGE_PEAK
	elif i > float(region["removed"]) * 0.01:
		region["stage"] = STAGE_SPREADING
	else:
		region["stage"] = STAGE_DECLINING


func _accumulate_economy(region: Dictionary, days: float) -> void:
	var cost: float = 0.0
	var policies: Dictionary = region["policies"]
	for k in policies.keys():
		if bool(policies[k]):
			cost += float(POLICY_ECONOMY_COST.get(k, 0.0))
	region["economy_scar"] = clampf(float(region["economy_scar"]) + cost * days / 365.0, 0.0, 1.0)


## 预警分级：按感染率与医院占用率。
func alert_level(region: Dictionary) -> int:
	var prevalence: float = float(region["infectious"]) / maxf(1.0, float(region["population"]))
	var occupancy: float = hospital_occupancy(region)
	if prevalence >= 0.02 or occupancy >= 1.5:
		return ALERT_EMERGENCY
	if prevalence >= 0.005 or occupancy >= 1.0:
		return ALERT_ALERT
	if prevalence >= 0.0005:
		return ALERT_WATCH
	return ALERT_NONE


# --- 政策 ---

func set_policy(region: Dictionary, policy: String, enabled: bool) -> Dictionary:
	if not POLICY_BETA_REDUCTION.has(policy):
		return {"ok": false, "reason": "unknown_policy"}
	var policies: Dictionary = region["policies"]
	var was: bool = bool(policies.get(policy, false))
	policies[policy] = enabled
	# 民意反弹：政策由关转开时下降，解除时缓慢回升。
	if enabled and not was:
		region["public_trust"] = clampf(float(region["public_trust"]) - 0.02, 0.0, 1.0)
	return {
		"ok": true, "policy": policy, "enabled": enabled,
		"effective_beta": effective_beta(region), "public_trust": float(region["public_trust"]),
	}


func active_policies(region: Dictionary) -> Array:
	var out: Array = []
	var policies: Dictionary = region["policies"]
	for k in policies.keys():
		if bool(policies[k]):
			out.append(k)
	return out


# --- 疫苗与资源 ---

## 接种：按意愿接受率从易感人群转入免疫（记入 vaccinated）。
func vaccinate(region: Dictionary, doses: int, rng = null) -> Dictionary:
	var hesitancy: float = clampf(float(region["vaccine_hesitancy"]), 0.0, 1.0)
	var acceptance: float = 1.0 - hesitancy
	if rng != null:
		acceptance = clampf(acceptance + (rng.next_float() - 0.5) * 0.1, 0.0, 1.0)
	var stock: int = int((region["resources"] as Dictionary).get("vaccine_stock", 0))
	var usable: int = mini(doses, stock)
	var effective: float = minf(float(usable) * acceptance, float(region["susceptible"]))
	region["susceptible"] = maxf(0.0, float(region["susceptible"]) - effective)
	region["removed"] = float(region["removed"]) + effective
	region["vaccinated"] = float(region["vaccinated"]) + effective
	(region["resources"] as Dictionary)["vaccine_stock"] = maxi(0, stock - usable)
	return {"ok": true, "vaccinated": int(round(effective)), "remaining_stock": int((region["resources"] as Dictionary)["vaccine_stock"])}


func add_resources(region: Dictionary, deltas: Dictionary) -> Dictionary:
	var res: Dictionary = region["resources"]
	for k in deltas.keys():
		if res.has(k):
			res[k] = int(res[k]) + int(deltas[k])
	return {"ok": true, "resources": res.duplicate()}


## 跨区域扩散：按交通流把感染导出到目标区域。
func cross_region_spread(src: Dictionary, dst: Dictionary, travelers: float) -> Dictionary:
	var share: float = clampf(travelers / maxf(1.0, float(src["population"])), 0.0, 0.5)
	var exported: float = float(src["infectious"]) * share
	var dst_s: float = float(dst["susceptible"])
	var moved: float = minf(exported, dst_s)
	dst["exposed"] = float(dst["exposed"]) + moved
	dst["susceptible"] = dst_s - moved
	if moved > 0.0 and str(dst["stage"]) == STAGE_SUSCEPTIBLE:
		dst["stage"] = STAGE_OUTBREAK
	return {"ok": true, "exported": exported, "imported": moved}


## 病毒变异：放大传播率。
func mutate(region: Dictionary, factor: float) -> Dictionary:
	var params: Dictionary = region["params"]
	params["beta"] = float(params["beta"]) * (1.0 + maxf(0.0, factor))
	return {"ok": true, "beta": float(params["beta"])}


## 免疫衰减：removed 中按免疫期比例回归易感。
func wane_immunity(region: Dictionary, days: float) -> Dictionary:
	var immunity_days: float = maxf(1.0, float((region["params"] as Dictionary)["immunity_days"]))
	var waned: float = float(region["removed"]) * clampf(days / immunity_days, 0.0, 1.0) * 0.1
	region["removed"] = maxf(0.0, float(region["removed"]) - waned)
	region["susceptible"] = float(region["susceptible"]) + waned
	return {"ok": true, "waned": waned}


func to_dict(region: Dictionary) -> Dictionary:
	return region.duplicate(true)


func from_dict(data: Dictionary) -> Dictionary:
	return data.duplicate(true)
