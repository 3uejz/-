class_name GoldfingerSystem
extends RefCounted
## 金手指系统（可选元层，R100；design「金手指系统」）。
##
## 独立于 D44 异常体系与世界观的网文式元层：开档开关、按稀有度抽取与保底、重抽、
## 积分成长与每日上限、升级与商城兑换、模块注册表（MetaSystem）、强度预算校验、
## 单条/总开关与中途关闭语义（持续型即时失效、一次性不回收）；每代轮回重抽、不入家族史。
##
## 内容不硬编码：库由外部传入 def 数组（content/catalog/goldfingers.json → GoldfingerDef）。
## 随机性由注入 roll/rng 决定，缺省确定化（roll=0.0），便于复现与测试。

const BaselineScript = preload("res://sim/baseline.gd")

const RARITIES: Array = ["common", "rare", "epic", "legendary"]
const RARITY_NAMES: Dictionary = {"common": "普通", "rare": "稀有", "epic": "史诗", "legendary": "传说"}
const BASE_DISTRIBUTION: Dictionary = {"common": 0.60, "rare": 0.25, "epic": 0.12, "legendary": 0.03}
const RARITY_BUDGET: Dictionary = {"common": 100.0, "rare": 250.0, "epic": 600.0, "legendary": 1500.0}

const MODULES: Array = ["quest", "shop", "checkin", "appraisal", "space", "craft"]
const MODULE_NAMES: Dictionary = {
	"quest": "任务", "shop": "积分商城", "checkin": "签到抽奖",
	"appraisal": "属性可视化/鉴定", "space": "空间", "craft": "合成",
}

const FREE_REROLLS: int = BaselineScript.GOLDFINGER_FREE_REROLLS
const PITY_EPIC_AT: int = BaselineScript.GOLDFINGER_PITY_EPIC_AT
const PITY_LEGENDARY_AT: int = BaselineScript.GOLDFINGER_PITY_LEGENDARY_AT
const DEFAULT_DAILY_CAP: int = BaselineScript.GOLDFINGER_DEFAULT_DAILY_CAP


func rarities() -> Array:
	return RARITIES.duplicate()


func new_state() -> Dictionary:
	return {
		"enabled": false, "points": 0, "daily_points_gained": 0,
		"rerolls_used": 0, "pity_counter": 0, "draw_count": 0,
		"gen": 1, "items": [], "meta_achievements": false,
	}


# --- 模式开关 ---

## 开档开关：默认关闭，仅开档时可启用（R100.1）。
func set_mode(state: Dictionary, enabled: bool) -> Dictionary:
	state["enabled"] = enabled
	state["meta_achievements"] = enabled
	if not enabled:
		state["items"] = []
	return {"ok": true, "enabled": enabled}


# --- 抽取 ---

## 合并远程覆盖后的稀有度分布。
func distribution(override: Dictionary = {}) -> Dictionary:
	var dist: Dictionary = BASE_DISTRIBUTION.duplicate()
	for r in RARITIES:
		if override.has(r):
			dist[r] = maxf(0.0, float(override[r]))
	var total: float = 0.0
	for v in dist.values():
		total += float(v)
	if total <= 0.0:
		return BASE_DISTRIBUTION.duplicate()
	for r in RARITIES:
		dist[r] = float(dist[r]) / total
	return dist


## 从远程配置 values（点分键）解析稀有度分布。
func distribution_from_remote(values: Dictionary) -> Dictionary:
	var override: Dictionary = {}
	for r in RARITIES:
		var key: String = "goldfinger.distribution." + r
		if values.has(key):
			override[r] = float(values[key])
	return distribution(override)


## 从远程配置 values 解析抽取/保底/重抽/上限配置（R100.2）。
func config_from_remote(values: Dictionary) -> Dictionary:
	return {
		"distribution": distribution_from_remote(values),
		"pity_epic_at": int(values.get("goldfinger.pity.epic_at", PITY_EPIC_AT)),
		"pity_legendary_at": int(values.get("goldfinger.pity.legendary_at", PITY_LEGENDARY_AT)),
		"reroll_cost": int(values.get("goldfinger.reroll_cost", 0)),
		"daily_cap": int(values.get("goldfinger.points.daily_cap", DEFAULT_DAILY_CAP)),
	}


## 约束过滤后的候选池（era / prerequisites / incompatible）。
func eligible(defs: Array, ctx: Dictionary = {}) -> Array:
	var owned: Array = ctx.get("owned", [])
	var era: int = int(ctx.get("era", 0))
	var out: Array = []
	for def in defs:
		if not _constraints_ok(def, era, owned):
			continue
		out.append(def)
	return out


func _constraints_ok(def: Dictionary, era: int, owned: Array) -> bool:
	var c: Dictionary = def.get("constraints", {})
	if c.has("era_min") and era < int(c["era_min"]):
		return false
	if c.has("era_max") and era > int(c["era_max"]):
		return false
	for pre in c.get("prerequisites", []):
		if not owned.has(str(pre)):
			return false
	for inc in c.get("incompatible", []):
		if owned.has(str(inc)):
			return false
	return true


## 抽取一条金手指（R100.2）；支持稀有度保底与远程分布覆盖。
func draw(state: Dictionary, defs: Array, opts: Dictionary = {}) -> Dictionary:
	if not bool(state["enabled"]):
		return {"ok": false, "reason": "mode_disabled"}
	var pool: Array = eligible(defs, {"owned": _owned_keys(state), "era": int(opts.get("era", 0))})
	if pool.is_empty():
		return {"ok": false, "reason": "empty_pool"}
	var forced: String = str(opts.get("forced_rarity", ""))
	var pity_triggered: bool = false
	var rarity: String = forced
	if rarity == "":
		if int(state["pity_counter"]) >= PITY_LEGENDARY_AT:
			rarity = "legendary"
			pity_triggered = true
		elif int(state["pity_counter"]) >= PITY_EPIC_AT:
			rarity = "epic"
			pity_triggered = true
		else:
			rarity = _pick_rarity(distribution(opts.get("distribution", {})), _roll(opts, "roll_rarity", 0.0))
	var candidates: Array = _of_rarity(pool, rarity)
	if candidates.is_empty():
		candidates = pool
		rarity = str(candidates[0].get("rarity", "common"))
	var pick: Dictionary = candidates[_pick_index(candidates.size(), _roll(opts, "roll_pick", 0.0))]
	var item: Dictionary = _make_item(pick, int(opts.get("minute", 0)))
	state["items"].append(item)
	state["draw_count"] = int(state["draw_count"]) + 1
	if RARITIES.find(rarity) >= 2:
		state["pity_counter"] = 0
	else:
		state["pity_counter"] = int(state["pity_counter"]) + 1
	return {"ok": true, "item": item, "rarity": rarity, "pity_triggered": pity_triggered}


## 重抽（R100.2）：先消耗免费次数，用尽后消耗积分配置项。
func reroll(state: Dictionary, defs: Array, opts: Dictionary = {}) -> Dictionary:
	if not bool(state["enabled"]):
		return {"ok": false, "reason": "mode_disabled"}
	var cost: int = int(opts.get("reroll_cost", 0))
	var used_free: bool = int(state["rerolls_used"]) < FREE_REROLLS
	if not used_free:
		if int(state["points"]) < cost:
			return {"ok": false, "reason": "insufficient_points", "cost": cost}
		state["points"] = int(state["points"]) - cost
	state["rerolls_used"] = int(state["rerolls_used"]) + 1
	# 丢弃最近一次抽取后重新抽。
	if not (state["items"] as Array).is_empty():
		(state["items"] as Array).pop_back()
	var r: Dictionary = draw(state, defs, opts)
	r["free"] = used_free
	r["cost"] = 0 if used_free else cost
	return r


func _pick_rarity(dist: Dictionary, roll: float) -> String:
	var acc: float = 0.0
	for r in RARITIES:
		acc += float(dist[r])
		if roll < acc:
			return r
	return RARITIES[RARITIES.size() - 1]


func _of_rarity(pool: Array, rarity: String) -> Array:
	var out: Array = []
	for d in pool:
		if str(d.get("rarity", "common")) == rarity:
			out.append(d)
	return out


func _pick_index(n: int, roll: float) -> int:
	return clampi(int(floor(roll * float(n))), 0, maxi(0, n - 1))


func _roll(opts: Dictionary, key: String, fallback: float) -> float:
	if opts.has(key):
		return clampf(float(opts[key]), 0.0, 0.999999)
	var rng = opts.get("rng", null)
	if rng != null:
		return clampf(float(rng.next_float()), 0.0, 0.999999)
	return fallback


func _make_item(def: Dictionary, minute: int) -> Dictionary:
	return {
		"content_key": str(def.get("content_key", "")),
		"rarity": str(def.get("rarity", "common")),
		"level": 1, "points_invested": 0,
		"modules": (def.get("modules", []) as Array).duplicate(),
		"enabled": true, "obtained_minutes": minute,
	}


func _owned_keys(state: Dictionary) -> Array:
	var out: Array = []
	for it in state["items"]:
		out.append(str(it["content_key"]))
	return out


# --- 积分 ---

## 产出积分（R100.4）：受每日上限约束。
func grant_points(state: Dictionary, amount: int, cap: int = DEFAULT_DAILY_CAP) -> Dictionary:
	if not bool(state["enabled"]):
		return {"ok": false, "reason": "mode_disabled"}
	var remain: int = maxi(0, cap - int(state["daily_points_gained"]))
	var granted: int = clampi(amount, 0, remain)
	state["points"] = int(state["points"]) + granted
	state["daily_points_gained"] = int(state["daily_points_gained"]) + granted
	return {"ok": true, "granted": granted, "capped": amount - granted, "points": int(state["points"])}


func reset_daily(state: Dictionary) -> void:
	state["daily_points_gained"] = 0


## 升级金手指（R100.4）：依据 def.growth.upgrade_costs。
func upgrade(state: Dictionary, def: Dictionary, content_key: String) -> Dictionary:
	var item: Dictionary = _find_item(state, content_key)
	if item.is_empty():
		return {"ok": false, "reason": "not_owned"}
	var growth: Dictionary = def.get("growth", {})
	var max_level: int = int(growth.get("max_level", 1))
	var level: int = int(item["level"])
	if level >= max_level:
		return {"ok": false, "reason": "max_level"}
	var costs: Array = growth.get("upgrade_costs", [])
	var cost: int = int(costs[level - 1]) if level - 1 < costs.size() else 0
	if int(state["points"]) < cost:
		return {"ok": false, "reason": "insufficient_points", "cost": cost}
	state["points"] = int(state["points"]) - cost
	item["level"] = level + 1
	item["points_invested"] = int(item.get("points_invested", 0)) + cost
	return {"ok": true, "level": int(item["level"]), "cost": cost}


## 商城兑换（R100.3/4）：消耗积分换取一件物品/能力（由上层结算效果，这里只扣分记账）。
func exchange(state: Dictionary, cost: int, payload: Dictionary = {}) -> Dictionary:
	if int(state["points"]) < cost:
		return {"ok": false, "reason": "insufficient_points", "cost": cost}
	state["points"] = int(state["points"]) - cost
	return {"ok": true, "cost": cost, "payload": payload}


# --- 开关（R100.5）---

## 单个金手指禁用/启用；关闭后持续型效果即时失效，一次性已获得不回收。
func toggle_item(state: Dictionary, content_key: String, enabled: bool) -> Dictionary:
	var item: Dictionary = _find_item(state, content_key)
	if item.is_empty():
		return {"ok": false, "reason": "not_owned"}
	item["enabled"] = enabled
	return {"ok": true, "content_key": content_key, "enabled": enabled}


## 当前生效的持续型效果（仅启用中的条目）；一次性效果由上层在获得时结算，不在此列。
func active_continuous_effects(state: Dictionary, defs: Array) -> Array:
	var out: Array = []
	for it in state["items"]:
		if not bool(it["enabled"]):
			continue
		var def: Dictionary = _find_def(defs, str(it["content_key"]))
		for eff in def.get("effects", []):
			if str(eff.get("mode", "instant")) == "continuous":
				var e: Dictionary = eff.duplicate(true)
				e["content_key"] = it["content_key"]
				out.append(e)
	return out


## 模块注册表（MetaSystem）：启用条目声明的面板模块并集。
func module_registry(state: Dictionary) -> Dictionary:
	var reg: Dictionary = {}
	for it in state["items"]:
		if not bool(it["enabled"]):
			continue
		for m in it.get("modules", []):
			reg[str(m)] = true
	return reg


# --- 强度预算（R100，规模化到 300+）---

## 单条金手指效果总 cost 是否在其稀有度预算内。
func budget_ok(def: Dictionary) -> Dictionary:
	var rarity: String = str(def.get("rarity", "common"))
	var budget: float = float(RARITY_BUDGET.get(rarity, 0.0))
	var total: float = 0.0
	for eff in def.get("effects", []):
		total += float(eff.get("cost", 0.0))
	return {"ok": total <= budget, "rarity": rarity, "cost": total, "budget": budget}


# --- 轮回（R100.6）---

## 每代轮回重抽：清空积分、条目与保底，保留模式开关；不进入家族史。
func new_generation(state: Dictionary) -> Dictionary:
	var enabled: bool = bool(state["enabled"])
	state["items"] = []
	state["points"] = 0
	state["daily_points_gained"] = 0
	state["rerolls_used"] = 0
	state["pity_counter"] = 0
	state["draw_count"] = 0
	state["gen"] = int(state["gen"]) + 1
	state["enabled"] = enabled
	return {"ok": true, "gen": int(state["gen"]), "enabled": enabled}


## 成就单独标记（R100.7）。
func achievement_tag(state: Dictionary) -> String:
	return "goldfinger" if bool(state["enabled"]) else ""


func _find_item(state: Dictionary, content_key: String) -> Dictionary:
	for it in state["items"]:
		if str(it["content_key"]) == content_key:
			return it
	return {}


func _find_def(defs: Array, content_key: String) -> Dictionary:
	for d in defs:
		if str(d.get("content_key", "")) == content_key:
			return d
	return {}


func to_dict(state: Dictionary) -> Dictionary:
	return state.duplicate(true)


func from_dict(data: Dictionary) -> Dictionary:
	var state: Dictionary = new_state()
	state["enabled"] = bool(data.get("enabled", false))
	state["points"] = int(data.get("points", 0))
	state["daily_points_gained"] = int(data.get("daily_points_gained", 0))
	state["rerolls_used"] = int(data.get("rerolls_used", 0))
	state["pity_counter"] = int(data.get("pity_counter", 0))
	state["draw_count"] = int(data.get("draw_count", 0))
	state["gen"] = int(data.get("gen", 1))
	state["meta_achievements"] = bool(data.get("meta_achievements", state["enabled"]))
	state["items"] = (data.get("items", []) as Array).duplicate(true)
	return state
