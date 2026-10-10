class_name WarSystem
extends RefCounted
## 战争与征兵（R60；design D16）。
##
## 覆盖：
##   - 国际关系状态机：和平 → 紧张 → 局部冲突 → 全面战争 → 停战/占领；
##     由领土争端、经济、同盟、意识形态与随机事件驱动，含结盟/制裁/断交/军备竞赛/代理人战争；
##   - 征兵：抽签或志愿，条件含年龄/健康/学历/户籍，缓征免役（在读/残障/独生/关键岗位），
##     拒征逃兵法律后果，可申请替代服役（民役）；
##   - 前线：训练→驻防→作战 tick→伤亡/军功→晋升，兵种与战术影响结果，被俘与战俘交换；
##   - 战争经济：军工岗位、物资配给、物价冲击、黑市抬头、战后重建基金、税收与国债上升；
##   - 占领与战后：占领区法律与税制变更，区域人口与建筑按统计快进补损失，战后重建与赔款。
##
## 设计取舍：
##   - 本类只维护“世界层”战争状态（国家关系、战争、征兵政策、战时经济），
##     个人军旅状态由 MilitarySystem 维护，二者通过 conscript()/front_casualty() 衔接；
##   - 国家以字符串 code 标识，关系键取两码排序后用 "|" 连接，保证 (a,b) 与 (b,a) 同键；
##   - 一切随机经外部 rng 注入，缺省时退化为确定性取值，便于 headless 测试复现；
##   - 张紧度 tension 为 0..100，状态由张紧度 + 是否交战 + 是否停战/占领推导，避免多处写入不一致。

const BaselineScript = preload("res://sim/baseline.gd")

const MilitaryScript = preload("res://sim/military.gd")

# --- 状态机 ---

const STANCE_PEACE: String = "peace"
const STANCE_TENSION: String = "tension"
const STANCE_LIMITED: String = "limited_conflict"
const STANCE_TOTAL: String = "total_war"
const STANCE_CEASEFIRE: String = "ceasefire"
const STANCE_OCCUPATION: String = "occupation"

const STANCE_NAMES: Dictionary = {
	"peace": "和平", "tension": "紧张", "limited_conflict": "局部冲突",
	"total_war": "全面战争", "ceasefire": "停战", "occupation": "占领",
}

const TENSION_THRESHOLD: float = BaselineScript.WAR_TENSION_THRESHOLD          # ≥ 转为紧张
const LIMITED_CONFLICT_TENSION: float = BaselineScript.WAR_LIMITED_CONFLICT_TENSION   # ≥ 局部冲突
const TOTAL_WAR_TENSION: float = BaselineScript.WAR_TOTAL_WAR_TENSION          # ≥ 全面战争
const DECLARE_WAR_MIN_TENSION: float = BaselineScript.WAR_DECLARE_WAR_MIN_TENSION    # 宣战最低张紧度

## 驱动因子权重（领土/经济/同盟/意识形态/随机）。
const DRIVER_WEIGHTS: Dictionary = {
	"territorial": 1.5, "economy": 1.0, "alliance": 1.2, "ideology": 0.8, "random": 1.0,
}

# --- 征兵 ---

const CONSCRIPTION_VOLUNTEER: String = "volunteer"
const CONSCRIPTION_LOTTERY: String = "lottery"

const DRAFT_MIN_AGE: float = BaselineScript.WAR_DRAFT_MIN_AGE
const DRAFT_MAX_AGE: float = BaselineScript.WAR_DRAFT_MAX_AGE
const DRAFT_MIN_HEALTH: float = BaselineScript.WAR_DRAFT_MIN_HEALTH

const DEFER_STUDENT: String = "student"
const DEFER_DISABLED: String = "disabled"
const DEFER_ONLY_CHILD: String = "only_child"
const DEFER_KEY_JOB: String = "key_job"
const ALL_DEFERMENTS: Array = [DEFER_STUDENT, DEFER_DISABLED, DEFER_ONLY_CHILD, DEFER_KEY_JOB]

## 关键岗位（免役）。与 jobs.gd 的岗位键对齐。
const KEY_JOBS: Array = [
	"job.doctor", "job.nurse", "job.teacher", "job.firefighter", "job.police",
	"job.engineer", "job.scientist", "job.power_grid", "job.waterworks", "job.railway",
]

# --- 前线 ---

const MINUTES_PER_YEAR: float = 365.25 * 1440.0

## 兵种作战修正（与 MilitarySystem.BRANCHES 的 combat 语义一致）。
const TACTICS: Dictionary = {
	"frontal": {"name": "正面强攻", "attack": 1.2, "defense": 0.9, "casualty": 1.3},
	"defensive": {"name": "阵地防御", "attack": 0.8, "defense": 1.3, "casualty": 0.7},
	"flanking": {"name": "侧翼包抄", "attack": 1.1, "defense": 0.8, "casualty": 1.0},
	"guerrilla": {"name": "游击袭扰", "attack": 0.9, "defense": 1.1, "casualty": 0.6},
}

# --- 战争经济 ---

const DEFENSE_JOBS_PER_MOBILIZATION: float = BaselineScript.WAR_DEFENSE_JOBS_PER_MOBILIZATION
const PRICE_SHOCK_PER_MOBILIZATION: float = BaselineScript.WAR_PRICE_SHOCK_PER_MOBILIZATION
const BLACK_MARKET_PER_MOBILIZATION: float = BaselineScript.WAR_BLACK_MARKET_PER_MOBILIZATION
const RATIONING_MOBILIZATION_THRESHOLD: float = BaselineScript.WAR_RATIONING_MOBILIZATION_THRESHOLD
const DEBT_PER_YEAR_PER_MOBILIZATION: int = BaselineScript.WAR_DEBT_PER_YEAR_PER_MOBILIZATION  # 最小货币单位


# =====================================================================
# 世界初始化与关系
# =====================================================================

## 建立世界战争状态：初始化所有国家对为和平，默认志愿兵役。
func new_world(countries: Array) -> Dictionary:
	var relations: Dictionary = {}
	for i in countries.size():
		for j in range(i + 1, countries.size()):
			relations[pair_key(str(countries[i]), str(countries[j]))] = _default_relation()
	return {
		"relations": relations,
		"wars": [],
		"conscription": {"policy": CONSCRIPTION_VOLUNTEER, "quota": 0, "deferments": ALL_DEFERMENTS.duplicate(), "active": false},
		"economy": {"mobilization": 0.0, "debt": 0, "inflation": 0.0, "reconstruction_fund": 0, "rationing": false},
		"events": [],
	}


static func pair_key(a: String, b: String) -> String:
	return (a + "|" + b) if a <= b else (b + "|" + a)


func _default_relation() -> Dictionary:
	return {
		"tension": 0.0, "at_war": false, "ceasefire": false, "alliance": false,
		"sanction": false, "occupier": "", "occupied_regions": [], "war_since": -1,
	}


func ensure_relation(state: Dictionary, a: String, b: String) -> Dictionary:
	var relations: Dictionary = state["relations"]
	var key: String = pair_key(a, b)
	if not relations.has(key):
		relations[key] = _default_relation()
	return relations[key]


func relation(state: Dictionary, a: String, b: String) -> Dictionary:
	return ensure_relation(state, a, b)


## 由张紧度与交战/停战/占领标志推导当前状态。
func compute_stance(rel: Dictionary) -> String:
	if str(rel.get("occupier", "")) != "":
		return STANCE_OCCUPATION
	var tension: float = float(rel.get("tension", 0.0))
	if bool(rel.get("at_war", false)):
		return STANCE_TOTAL if tension >= TOTAL_WAR_TENSION else STANCE_LIMITED
	if bool(rel.get("ceasefire", false)):
		return STANCE_CEASEFIRE
	if tension >= TOTAL_WAR_TENSION:
		return STANCE_TOTAL
	if tension >= LIMITED_CONFLICT_TENSION:
		return STANCE_LIMITED
	if tension >= TENSION_THRESHOLD:
		return STANCE_TENSION
	return STANCE_PEACE


func stance(state: Dictionary, a: String, b: String) -> String:
	return compute_stance(relation(state, a, b))


# =====================================================================
# 关系演化与外交
# =====================================================================

## 按驱动因子调整张紧度，返回是否触发状态跃迁。
func apply_drivers(state: Dictionary, a: String, b: String, drivers: Dictionary, rng = null) -> Dictionary:
	var delta: float = 0.0
	for k in drivers.keys():
		var weight: float = float(DRIVER_WEIGHTS.get(str(k), 1.0))
		delta += float(drivers[k]) * weight
	if rng != null:
		delta += (rng.next_float() - 0.5) * 2.0 * float(DRIVER_WEIGHTS["random"])
	return adjust_tension(state, a, b, delta)


func adjust_tension(state: Dictionary, a: String, b: String, delta: float) -> Dictionary:
	var rel: Dictionary = ensure_relation(state, a, b)
	var before: String = compute_stance(rel)
	rel["tension"] = clampf(float(rel.get("tension", 0.0)) + delta, 0.0, 100.0)
	var after: String = compute_stance(rel)
	var escalated: bool = before != after
	if escalated:
		_log(state, "stance", "%s-%s: %s → %s" % [a, b, STANCE_NAMES.get(before, before), STANCE_NAMES.get(after, after)])
	return {"tension": float(rel["tension"]), "stance": after, "before": before, "escalated": escalated}


## 结盟：降低张紧度并解除制裁。
func form_alliance(state: Dictionary, a: String, b: String) -> Dictionary:
	var rel: Dictionary = ensure_relation(state, a, b)
	rel["alliance"] = true
	rel["sanction"] = false
	rel["tension"] = clampf(float(rel["tension"]) - 10.0, 0.0, 100.0)
	return {"ok": true, "alliance": true, "tension": float(rel["tension"])}


## 制裁：severity 0..1，提升张紧度并记状态。
func impose_sanction(state: Dictionary, a: String, b: String, severity: float = 0.6) -> Dictionary:
	var rel: Dictionary = ensure_relation(state, a, b)
	rel["sanction"] = true
	var result: Dictionary = adjust_tension(state, a, b, 10.0 * clampf(severity, 0.0, 1.0))
	return {"ok": true, "sanction": true, "tension": float(result["tension"]), "stance": str(result["stance"])}


## 断交：解除同盟并大幅提升张紧度。
func sever_relations(state: Dictionary, a: String, b: String) -> Dictionary:
	var rel: Dictionary = ensure_relation(state, a, b)
	rel["alliance"] = false
	var result: Dictionary = adjust_tension(state, a, b, 15.0)
	return {"ok": true, "alliance": false, "tension": float(result["tension"]), "stance": str(result["stance"])}


## 军备竞赛：双方军费上升，张紧度缓升。
func arms_race(state: Dictionary, a: String, b: String, intensity: float = 1.0) -> Dictionary:
	var result: Dictionary = adjust_tension(state, a, b, 8.0 * clampf(intensity, 0.0, 2.0))
	return {"ok": true, "tension": float(result["tension"]), "stance": str(result["stance"]), "defense_spending": int(300000000.0 * clampf(intensity, 0.0, 2.0))}


## 代理人战争：在他国境内扶持，张紧度按强度上升。
func proxy_war(state: Dictionary, a: String, b: String, intensity: float = 1.0) -> Dictionary:
	var result: Dictionary = adjust_tension(state, a, b, 15.0 * clampf(intensity, 0.0, 2.0))
	return {"ok": true, "tension": float(result["tension"]), "stance": str(result["stance"]), "proxy": true}


## 宣战：需张紧度达到门槛、未在交战、未被占领。
func declare_war(state: Dictionary, attacker: String, defender: String, minute: int) -> Dictionary:
	var rel: Dictionary = ensure_relation(state, attacker, defender)
	if str(rel.get("occupier", "")) != "":
		return {"ok": false, "reason": "occupied"}
	if bool(rel.get("at_war", false)):
		return {"ok": false, "reason": "already_at_war"}
	if float(rel["tension"]) < DECLARE_WAR_MIN_TENSION:
		return {"ok": false, "reason": "tension_too_low", "tension": float(rel["tension"])}
	rel["at_war"] = true
	rel["ceasefire"] = false
	rel["war_since"] = minute
	var war: Dictionary = {
		"attacker": attacker, "defender": defender, "start": minute,
		"tactic_a": "frontal", "tactic_b": "defensive",
		"casualties": {attacker: 0, "defender": 0}, "territory": 0.0,
	}
	(state["wars"] as Array).append(war)
	_log(state, "war", "%s 对 %s 宣战" % [attacker, defender])
	return {"ok": true, "war": war, "stance": compute_stance(rel)}


func active_war_count(state: Dictionary) -> int:
	return (state["wars"] as Array).size()


## 停战：结束交战并进入停战状态。
func ceasefire(state: Dictionary, a: String, b: String, minute: int) -> Dictionary:
	var rel: Dictionary = ensure_relation(state, a, b)
	if not bool(rel.get("at_war", false)):
		return {"ok": false, "reason": "not_at_war"}
	rel["at_war"] = false
	rel["ceasefire"] = true
	rel["tension"] = clampf(float(rel["tension"]) - 30.0, 0.0, 100.0)
	_remove_war(state, a, b)
	_log(state, "ceasefire", "%s 与 %s 停战" % [a, b])
	return {"ok": true, "stance": compute_stance(rel), "tension": float(rel["tension"])}


## 占领：胜方占领败方 regions，法律与税制变更。
func occupy(state: Dictionary, winner: String, loser: String, regions: Array, opts: Dictionary = {}) -> Dictionary:
	var rel: Dictionary = ensure_relation(state, winner, loser)
	rel["at_war"] = false
	rel["ceasefire"] = false
	rel["occupier"] = winner
	rel["tension"] = 100.0
	var occupied: Array = rel.get("occupied_regions", [])
	for r in regions:
		if not occupied.has(r):
			occupied.append(r)
	rel["occupied_regions"] = occupied
	_remove_war(state, winner, loser)
	var law: String = str(opts.get("new_law", "occupied_martial_law"))
	var tax_rate: float = float(opts.get("new_tax_rate", 0.35))
	_log(state, "occupation", "%s 占领 %s（法律=%s，税率=%.2f）" % [winner, loser, law, tax_rate])
	return {"ok": true, "occupier": winner, "occupied_regions": occupied, "new_law": law, "new_tax_rate": tax_rate}


func _remove_war(state: Dictionary, a: String, b: String) -> void:
	var wars: Array = state["wars"]
	for i in range(wars.size() - 1, -1, -1):
		var w: Dictionary = wars[i]
		if (str(w["attacker"]) == a and str(w["defender"]) == b) or (str(w["attacker"]) == b and str(w["defender"]) == a):
			wars.remove_at(i)


func _log(state: Dictionary, event_type: String, text: String) -> void:
	(state["events"] as Array).append({"type": event_type, "text": text})
	if (state["events"] as Array).size() > 64:
		(state["events"] as Array).pop_front()


# =====================================================================
# 征兵
# =====================================================================

func set_conscription_policy(state: Dictionary, policy: String, opts: Dictionary = {}) -> Dictionary:
	if policy != CONSCRIPTION_VOLUNTEER and policy != CONSCRIPTION_LOTTERY:
		return {"ok": false, "reason": "unknown_policy"}
	var c: Dictionary = state["conscription"]
	c["policy"] = policy
	c["quota"] = int(opts.get("quota", 0))
	if opts.has("deferments"):
		var ds: Array = []
		for d in (opts["deferments"] as Array):
			if ALL_DEFERMENTS.has(str(d)):
				ds.append(str(d))
		c["deferments"] = ds
	c["active"] = policy == CONSCRIPTION_LOTTERY and int(c["quota"]) > 0
	return {"ok": true, "policy": policy, "quota": int(c["quota"]), "deferments": c["deferments"], "active": bool(c["active"])}


## 征兵条件评估：年龄/健康/缓征免役。返回 eligible 与原因列表。
func draft_assessment(player: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var reasons: Array = []
	var age: float = float(opts.get("age", player.get("age", -1.0)))
	if age >= 0.0 and (age < DRAFT_MIN_AGE or age > DRAFT_MAX_AGE):
		reasons.append("age")
	var health: float = _health(player)
	if health < DRAFT_MIN_HEALTH:
		reasons.append("health")
	var deferments: Array = opts.get("deferments", ALL_DEFERMENTS)
	if deferments.has(DEFER_STUDENT) and _is_student(player):
		reasons.append(DEFER_STUDENT)
	if deferments.has(DEFER_DISABLED) and _is_disabled(player):
		reasons.append(DEFER_DISABLED)
	if deferments.has(DEFER_ONLY_CHILD) and bool(player.get("only_child", false)):
		reasons.append(DEFER_ONLY_CHILD)
	if deferments.has(DEFER_KEY_JOB) and KEY_JOBS.has(str(player.get("job", ""))):
		reasons.append(DEFER_KEY_JOB)
	return {"eligible": reasons.is_empty(), "reasons": reasons}


func _health(player: Dictionary) -> float:
	var attrs: Variant = player.get("attrs", {})
	if attrs is Dictionary:
		var g: Variant = (attrs as Dictionary).get("physiological", {})
		if g is Dictionary:
			return float((g as Dictionary).get("health", 100.0))
	return 100.0


func _is_student(player: Dictionary) -> bool:
	var edu: Variant = player.get("education", [])
	if edu is Array:
		for e in (edu as Array):
			if e is Dictionary and str((e as Dictionary).get("status", "")) == "enrolled":
				return true
	return false


func _is_disabled(player: Dictionary) -> bool:
	if bool(player.get("disabled", false)):
		return true
	var traits: Variant = player.get("traits", [])
	if traits is Array:
		return (traits as Array).has("disabled")
	return false


## 抽签：从候选人中按配额选取合格者，返回入选 id 列表与缓征数。
func select_draftees(candidates: Array, quota: int, rng = null, opts: Dictionary = {}) -> Dictionary:
	var eligible: Array = []
	for c in candidates:
		var d: Dictionary = c
		if bool(draft_assessment(d, opts)["eligible"]):
			eligible.append(d)
	var order: Array = eligible.duplicate()
	_shuffle(order, rng)
	var selected: Array = []
	for i in mini(quota, order.size()):
		selected.append((order[i] as Dictionary).get("id", i))
	return {"selected": selected, "eligible": eligible.size(), "deferred": candidates.size() - eligible.size(), "quota": quota}


func _shuffle(arr: Array, rng) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j: int = int(rng.next_float() * float(i + 1)) if rng != null else i
		j = clampi(j, 0, i)
		var tmp: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


## 征召个人入伍：不合格转民役，合格入军籍（复用 MilitarySystem）。
func conscript(player: Dictionary, minute: int, opts: Dictionary = {}) -> Dictionary:
	var military = MilitaryScript.new()
	var assessment: Dictionary = draft_assessment(player, opts)
	if not bool(assessment["eligible"]):
		var months: int = int(opts.get("civil_service_months", 24))
		player["alternative_service"] = {"months": months, "started_minutes": minute}
		return {"ok": true, "assigned": "alternative_service", "months": months, "reasons": assessment["reasons"]}
	var branch: String = str(opts.get("branch", "army"))
	var enlist: Dictionary = military.enlist(player, branch, minute, opts)
	if not bool(enlist.get("ok", false)):
		player["alternative_service"] = {"months": int(opts.get("civil_service_months", 24)), "started_minutes": minute}
		return {"ok": true, "assigned": "alternative_service", "reasons": enlist.get("missing", [])}
	(player["military"] as Dictionary)["conscripted"] = true
	(player["military"] as Dictionary)["conscripted_minutes"] = minute
	return {"ok": true, "assigned": "military", "branch": branch}


## 拒征/逃兵：法律后果（联动 D12）。
func refuse_draft(player: Dictionary, minute: int) -> Dictionary:
	var legal: Variant = player.get("legal", {})
	if not (legal is Dictionary):
		legal = {"wanted_level": 0, "criminal_record": false, "in_prison": false}
	(legal as Dictionary)["criminal_record"] = true
	(legal as Dictionary)["wanted_level"] = int((legal as Dictionary).get("wanted_level", 0)) + 2
	player["legal"] = legal
	player["draft_refused_minutes"] = minute
	return {"ok": true, "wanted_level": int((legal as Dictionary)["wanted_level"]), "criminal_record": true}


# =====================================================================
# 前线
# =====================================================================

## 单次作战 tick：按兵力、战力、补给与战术结算双方损失与优势。
func front_tick(war: Dictionary, forces: Dictionary, rng = null, opts: Dictionary = {}) -> Dictionary:
	var side_a: Dictionary = forces.get("a", {})
	var side_b: Dictionary = forces.get("b", {})
	var tactic_a: Dictionary = TACTICS.get(str(opts.get("tactic_a", war.get("tactic_a", "frontal"))), TACTICS["frontal"])
	var tactic_b: Dictionary = TACTICS.get(str(opts.get("tactic_b", war.get("tactic_b", "defensive"))), TACTICS["defensive"])
	var power_a: float = _side_power(side_a, tactic_a, true)
	var power_b: float = _side_power(side_b, tactic_b, false)
	var total: float = maxf(1.0, power_a + power_b)
	var roll: float = rng.next_float() if rng != null else 0.5
	var adv_a: float = (power_a - power_b) / total + (roll - 0.5) * 0.1
	var base_loss: float = float(opts.get("intensity", 1.0)) * 0.05
	var troops_a: float = maxf(1.0, float(side_a.get("troops", 1)))
	var troops_b: float = maxf(1.0, float(side_b.get("troops", 1)))
	var loss_a: int = int(troops_a * base_loss * float(tactic_a["casualty"]) * (1.0 - clampf(adv_a, -0.5, 0.5)))
	var loss_b: int = int(troops_b * base_loss * float(tactic_b["casualty"]) * (1.0 + clampf(adv_a, -0.5, 0.5)))
	loss_a = maxi(0, loss_a)
	loss_b = maxi(0, loss_b)
	var attacker: String = str(war.get("attacker", "a"))
	var defender: String = str(war.get("defender", "b"))
	var casualties: Dictionary = war.get("casualties", {})
	casualties[attacker] = int(casualties.get(attacker, 0)) + loss_a
	casualties[defender] = int(casualties.get(defender, 0)) + loss_b
	war["casualties"] = casualties
	war["territory"] = clampf(float(war.get("territory", 0.0)) + adv_a * 0.05, -1.0, 1.0)
	war["tactic_a"] = str(opts.get("tactic_a", war.get("tactic_a", "frontal")))
	war["tactic_b"] = str(opts.get("tactic_b", war.get("tactic_b", "defensive")))
	return {
		"ok": true, "loss_a": loss_a, "loss_b": loss_b, "advantage_a": adv_a,
		"merit_a": float((loss_b + 1)) * 0.1, "merit_b": float((loss_a + 1)) * 0.1,
		"territory": float(war["territory"]), "casualties": casualties,
	}


func _side_power(side: Dictionary, tactic: Dictionary, attacking: bool) -> float:
	var troops: float = maxf(0.0, float(side.get("troops", 0)))
	var quality: float = maxf(0.1, float(side.get("power", 1.0)))
	var supply: float = clampf(float(side.get("supply", 1.0)), 0.1, 1.5)
	var mult: float = float(tactic["attack"]) if attacking else float(tactic["defense"])
	return troops * quality * supply * mult


## 将前线伤亡写入个人：负伤降健康、阵亡归零，并标记 PTSD 风险（联动 D4）。
func front_casualty(player: Dictionary, severity: float, rng = null, opts: Dictionary = {}) -> Dictionary:
	var roll: float = rng.next_float() if rng != null else 0.0
	var s: float = clampf(severity, 0.0, 1.0)
	var kia: bool = roll < s * 0.1
	var wound: float = 30.0 * s
	if kia:
		_set_health(player, 0.0)
	else:
		_set_health(player, maxf(0.0, _health(player) - wound))
		if roll < s * 0.4:
			player["ptsd"] = true
	if kia:
		player["kia_minutes"] = int(opts.get("minute", -1))
	return {"ok": true, "kia": kia, "wound": wound, "ptsd": bool(player.get("ptsd", false))}


func _set_health(player: Dictionary, value: float) -> void:
	var attrs: Variant = player.get("attrs", {})
	if attrs is Dictionary:
		var g: Variant = (attrs as Dictionary).get("physiological", {})
		if g is Dictionary:
			(g as Dictionary)["health"] = clampf(value, 0.0, 100.0)


## 被俘与战俘交换：返回可交换数量。
func exchange_pow(pow_count: int, rng = null, opts: Dictionary = {}) -> Dictionary:
	var max_rate: float = clampf(float(opts.get("rate", 0.6)), 0.0, 1.0)
	var roll: float = rng.next_float() if rng != null else 0.5
	var exchanged: int = int(float(pow_count) * max_rate * (0.5 + roll * 0.5))
	return {"ok": true, "exchanged": exchanged, "remaining": maxi(0, pow_count - exchanged)}


# =====================================================================
# 战争经济
# =====================================================================

## 按交战数与动员度计算战时经济影响。
func war_economy_effects(state: Dictionary) -> Dictionary:
	var wars: int = active_war_count(state)
	var econ: Dictionary = state["economy"]
	var mobilization: float = clampf(float(econ.get("mobilization", 0.0)), 0.0, 1.0)
	var scale: float = clampf(mobilization + float(wars) * 0.15, 0.0, 1.0)
	return {
		"active_wars": wars,
		"defense_jobs": int(scale * DEFENSE_JOBS_PER_MOBILIZATION),
		"price_shock": scale * PRICE_SHOCK_PER_MOBILIZATION,
		"black_market": scale * BLACK_MARKET_PER_MOBILIZATION,
		"rationing": scale >= RATIONING_MOBILIZATION_THRESHOLD,
		"debt_per_year": int(scale * float(DEBT_PER_YEAR_PER_MOBILIZATION)),
	}


func set_mobilization(state: Dictionary, level: float) -> Dictionary:
	var econ: Dictionary = state["economy"]
	econ["mobilization"] = clampf(level, 0.0, 1.0)
	econ["rationing"] = float(econ["mobilization"]) >= RATIONING_MOBILIZATION_THRESHOLD
	return {"ok": true, "mobilization": float(econ["mobilization"]), "rationing": bool(econ["rationing"])}


## 推进战时经济：国债、通胀、重建基金随时间与交战数增长。
func tick_economy(state: Dictionary, years: float, opts: Dictionary = {}) -> Dictionary:
	var econ: Dictionary = state["economy"]
	var effects: Dictionary = war_economy_effects(state)
	var y: float = maxf(0.0, years)
	econ["debt"] = int(econ.get("debt", 0)) + int(float(effects["debt_per_year"]) * y)
	var inflation_growth: float = float(effects["price_shock"]) * 0.2 * y
	econ["inflation"] = clampf(float(econ.get("inflation", 0.0)) + inflation_growth, -0.5, 5.0)
	var war_tax: int = int(opts.get("war_tax_per_year", 0))
	econ["reconstruction_fund"] = int(econ.get("reconstruction_fund", 0)) + int(float(war_tax) * y)
	return {
		"ok": true, "debt": int(econ["debt"]), "inflation": float(econ["inflation"]),
		"reconstruction_fund": int(econ["reconstruction_fund"]), "defense_jobs": int(effects["defense_jobs"]),
	}


## 战后重建：人口与建筑按年增长恢复，返回恢复量与赔款。
func postwar_recovery(losses: Dictionary, years: float, opts: Dictionary = {}) -> Dictionary:
	var y: float = maxf(0.0, years)
	var pop_rate: float = clampf(float(opts.get("population_recovery_rate", 0.02)), 0.0, 0.2)
	var build_rate: float = clampf(float(opts.get("building_recovery_rate", 0.05)), 0.0, 0.3)
	var pop_loss: int = int(losses.get("population", 0))
	var build_loss: int = int(losses.get("buildings", 0))
	var pop_recovered: int = int(float(pop_loss) * clampf(pop_rate * y, 0.0, 1.0))
	var build_recovered: int = int(float(build_loss) * clampf(build_rate * y, 0.0, 1.0))
	var reparations: int = int(opts.get("reparations", 0))
	return {
		"ok": true, "population_recovered": pop_recovered, "buildings_recovered": build_recovered,
		"population_remaining_loss": pop_loss - pop_recovered, "buildings_remaining_loss": build_loss - build_recovered,
		"reparations": reparations,
	}


func to_dict(state: Dictionary) -> Dictionary:
	return state.duplicate(true)


func from_dict(data: Dictionary) -> Dictionary:
	return data.duplicate(true)
