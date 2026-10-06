class_name FuneralSystem
extends RefCounted
## 殡葬、器官捐献与纪念（R86；design D42）。
##
## 覆盖：
##   - 殡葬方式：葬礼、火化、土葬、海葬、树葬，以及墓地购买；由死亡流程触发
##     （以入参 death_info 字典呼应，不直接依赖死亡系统）；
##   - 器官与遗体捐献：生前登记、伦理与法律流程、家属可撤销、器官分配与移植；
##   - 纪念：纪念碑、家族墓、祭扫、数字纪念/虚拟墓园，影响家庭关系与意义感；
##   - 遗嘱执行：按生前意愿与家属决议执行殡葬；
##   - 殡葬行业：殡仪馆/墓地/丧葬用品、暴利与监管、陋习与改革；
##   - 边界：遗产不足无法下葬、捐献争议、无人认领遗体。
##
## 设计取舍：
##   - 全部殡葬、捐献、纪念数据为纯 Dictionary，便于存读档与 headless 测试；
##   - 与死亡系统的衔接只通过入参 death_info（estate 等）完成，不反向依赖；
##   - 与家庭系统（D11）只通过返回的家庭关系增量表达，不维护成员列表；
##   - 伦理审查、捐献争议、查处暴利等随机项由外部注入 roll/rng，缺省确定化。

## 殡葬方式。land 表示是否占用墓地/林地；eco 为节地生态。
const FUNERAL_METHODS: Dictionary = {
	"funeral": {"name": "葬礼", "cost": 30000, "land": 0, "eco": false},
	"cremation": {"name": "火化", "cost": 20000, "land": 0, "eco": true},
	"burial": {"name": "土葬", "cost": 60000, "land": 1, "eco": false},
	"sea_burial": {"name": "海葬", "cost": 10000, "land": 0, "eco": true},
	"tree_burial": {"name": "树葬", "cost": 15000, "land": 1, "eco": true},
}

## 墓位类型。
const GRAVE_TYPES: Dictionary = {
	"standard": {"name": "普通墓", "price": 200000, "years": 20},
	"premium": {"name": "高档墓", "price": 1000000, "years": 50},
	"family": {"name": "家族墓", "price": 3000000, "years": 100},
}

## 可捐献器官。
const DONATION_ORGANS: Array = ["heart", "liver", "kidney", "cornea", "lung", "pancreas"]
const ORGAN_NAMES: Dictionary = {
	"heart": "心脏", "liver": "肝脏", "kidney": "肾脏",
	"cornea": "角膜", "lung": "肺", "pancreas": "胰腺",
}

## 纪念形式。
const MEMORIAL_KINDS: Array = ["monument", "family_grave", "digital_cemetery", "virtual_grave"]
const MEMORIAL_NAMES: Dictionary = {
	"monument": "纪念碑", "family_grave": "家族墓",
	"digital_cemetery": "数字纪念", "virtual_grave": "虚拟墓园",
}


func new_state() -> Dictionary:
	return {
		"deceased": {},
		"funeral": {
			"method": "", "grave": "", "arranged": false, "executed": false,
			"cost": 0, "paid": 0, "affordable": true, "reason": "",
		},
		"donation": {
			"registered": false, "ethics_reviewed": false, "ethics_approved": false,
			"legal": false, "revoked": false, "organs": [], "allocated": [], "dispute": false,
		},
		"memorials": [],
		"digital": {"created": false, "visits": 0},
		"wishes": {"method": "", "grave": "", "donation": false, "organs": []},
		"industry": {},
		"unclaimed": false,
		"family_relations": 0.0,
		"meaning": 0.0,
	}


func methods() -> Array:
	return FUNERAL_METHODS.keys()


func method_def(key: String) -> Dictionary:
	if not FUNERAL_METHODS.has(key):
		return {}
	return (FUNERAL_METHODS[key] as Dictionary).duplicate(true)


func grave_types() -> Array:
	return GRAVE_TYPES.keys()


func grave_def(key: String) -> Dictionary:
	if not GRAVE_TYPES.has(key):
		return {}
	return (GRAVE_TYPES[key] as Dictionary).duplicate(true)


func donation_organs() -> Array:
	return DONATION_ORGANS.duplicate()


func memorial_kinds() -> Array:
	return MEMORIAL_KINDS.duplicate()


func _roll(forced: float, rng) -> float:
	if forced >= 0.0:
		return clampf(forced, 0.0, 1.0)
	if rng != null:
		return rng.next_float()
	return 0.0


# --- 殡葬安排与执行 ---

## 安排殡葬：按生前意愿或家属决议选择方式与墓位，结算费用与遗产是否足够。
func arrange_funeral(death_info: Dictionary, state: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var method: String = str(opts.get("method", ""))
	if method == "":
		method = str((state.get("wishes", {}) as Dictionary).get("method", ""))
	if method == "" or not FUNERAL_METHODS.has(method):
		method = "cremation"
	var grave: String = str(opts.get("grave", (state.get("wishes", {}) as Dictionary).get("grave", "")))
	if grave != "" and not GRAVE_TYPES.has(grave):
		grave = ""
	var cost: int = int((FUNERAL_METHODS[method] as Dictionary)["cost"])
	var grave_cost: int = int((GRAVE_TYPES[grave] as Dictionary)["price"]) if grave != "" else 0
	var total: int = cost + grave_cost
	var estate: int = int(death_info.get("estate", opts.get("estate", 0)))
	var affordable: bool = estate >= total
	var f: Dictionary = state["funeral"]
	f["method"] = method
	f["grave"] = grave
	f["cost"] = total
	f["affordable"] = affordable
	f["arranged"] = true
	f["executed"] = false
	f["reason"] = "" if affordable else "insufficient_estate"
	state["deceased"] = death_info.duplicate(true)
	return {
		"ok": true, "method": method, "name": str((FUNERAL_METHODS[method] as Dictionary)["name"]),
		"grave": grave, "cost": total, "affordable": affordable, "reason": str(f["reason"]),
	}


## 执行殡葬：遗产不足时拒绝下葬（除非走公益救助），成功后结算意义与家庭关系。
func execute_funeral(state: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var f: Dictionary = state["funeral"]
	if not bool(f.get("arranged", false)):
		return {"ok": false, "reason": "not_arranged"}
	var public_assist: bool = bool(opts.get("public_assistance", false))
	if not bool(f.get("affordable", true)) and not public_assist:
		f["reason"] = "insufficient_estate"
		return {"ok": false, "reason": "insufficient_estate"}
	f["executed"] = true
	f["paid"] = 0 if public_assist else int(f["cost"])
	var meaning: float = 5.0
	if str(f.get("grave", "")) != "":
		meaning += 5.0
	state["meaning"] = float(state.get("meaning", 0.0)) + meaning
	state["family_relations"] = float(state.get("family_relations", 0.0)) + 3.0
	return {
		"ok": true, "method": str(f["method"]), "executed": true, "paid": int(f["paid"]),
		"public_assistance": public_assist, "meaning": meaning,
		"family_relations": float(state["family_relations"]),
	}


# --- 器官与遗体捐献 ---

## 生前登记捐献。
func register_donation(state: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var d: Dictionary = state["donation"]
	var organs: Array = opts.get("organs", DONATION_ORGANS).duplicate()
	for o in organs:
		if not DONATION_ORGANS.has(str(o)):
			return {"ok": false, "reason": "unknown_organ", "organ": str(o)}
	d["registered"] = true
	d["revoked"] = false
	d["organs"] = organs
	return {"ok": true, "registered": true, "organs": organs}


## 伦理与法律流程审查。默认高概率通过，可注入 roll 覆盖。
func review_ethics(state: Dictionary, opts: Dictionary = {}, rng = null) -> Dictionary:
	var d: Dictionary = state["donation"]
	if not bool(d.get("registered", false)):
		return {"ok": false, "reason": "not_registered"}
	var approved: bool = _roll(float(opts.get("roll", -1.0)), rng) < float(opts.get("pass_rate", 0.9))
	var legal_ok: bool = approved and bool(opts.get("legal_compliant", true))
	d["ethics_reviewed"] = true
	d["ethics_approved"] = approved
	d["legal"] = legal_ok
	return {"ok": true, "approved": approved, "legal": legal_ok, "reason": "" if approved else "ethics_rejected"}


## 家属撤销捐献：生前不可撤销（除非强制），死后家属可撤销。
func revoke_donation(state: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var d: Dictionary = state["donation"]
	if not bool(d.get("registered", false)):
		return {"ok": false, "reason": "not_registered"}
	var deceased: bool = bool(opts.get("deceased", false))
	if not deceased and not bool(opts.get("force", false)):
		return {"ok": false, "reason": "donor_alive"}
	d["revoked"] = true
	d["registered"] = false
	return {"ok": true, "revoked": true, "by": str(opts.get("by", "family"))}


## 器官分配：仅在合法有效且未撤销时，按受者紧迫度匹配器官。
func allocate_organs(state: Dictionary, recipients: Array, opts: Dictionary = {}) -> Dictionary:
	var d: Dictionary = state["donation"]
	if bool(d.get("revoked", false)) or not bool(d.get("ethics_reviewed", false)) or not bool(d.get("ethics_approved", false)):
		return {"ok": false, "reason": "donation_unavailable"}
	var organs: Array = (d.get("organs", []) as Array).duplicate()
	var pool: Array = recipients.duplicate(true)
	var allocated: Array = []
	for organ in organs:
		var best: Dictionary = {}
		for r in pool:
			var rec: Dictionary = r
			if str(rec.get("organ", "")) != str(organ):
				continue
			if best.is_empty() or float(rec.get("urgency", 0.0)) > float(best.get("urgency", 0.0)):
				best = rec
		if not best.is_empty():
			allocated.append({"organ": str(organ), "recipient_id": str(best.get("id", "")), "urgency": float(best.get("urgency", 0.0))})
			pool.erase(best)
	d["allocated"] = allocated
	return {"ok": true, "allocated": allocated, "count": allocated.size()}


## 移植接口：供医疗系统消费，返回成败与排异。
func transplant(recipient: Dictionary, organ: String, opts: Dictionary = {}, rng = null) -> Dictionary:
	var ok: bool = _roll(float(opts.get("roll", -1.0)), rng) >= float(opts.get("rejection_rate", 0.15))
	return {
		"ok": true, "organ": organ, "organ_name": str(ORGAN_NAMES.get(organ, organ)),
		"recipient_id": str(recipient.get("id", "")), "success": ok, "rejection": not ok,
	}


# --- 纪念 ---

## 建立纪念：纪念碑/家族墓/数字纪念/虚拟墓园，提升意义感与家庭关系。
func build_memorial(state: Dictionary, kind: String, opts: Dictionary = {}) -> Dictionary:
	if not MEMORIAL_KINDS.has(kind):
		return {"ok": false, "reason": "unknown_kind"}
	var m: Dictionary = {
		"kind": kind, "name": str(opts.get("name", MEMORIAL_NAMES[kind])),
		"day": int(opts.get("day", 0)), "visits": 0,
	}
	(state["memorials"] as Array).append(m)
	var meaning: float = 8.0
	var rel: float = 5.0
	state["meaning"] = float(state.get("meaning", 0.0)) + meaning
	state["family_relations"] = float(state.get("family_relations", 0.0)) + rel
	return {"ok": true, "memorial": m, "meaning": meaning, "family_relations": rel}


## 祭扫：累计访问与追思，小幅提升意义感与家庭关系。
func tomb_sweeping(state: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var kind: String = str(opts.get("kind", "family_grave"))
	var found: Dictionary = {}
	for m in state.get("memorials", []):
		if str((m as Dictionary).get("kind", "")) == kind:
			found = m
			break
	if found.is_empty():
		return {"ok": false, "reason": "no_memorial"}
	found["visits"] = int(found.get("visits", 0)) + 1
	state["meaning"] = float(state.get("meaning", 0.0)) + 2.0
	state["family_relations"] = float(state.get("family_relations", 0.0)) + 1.0
	return {"ok": true, "kind": kind, "visits": int(found["visits"])}


## 数字纪念/虚拟墓园：线上追思，累计访问量。
func create_digital_memorial(state: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var d: Dictionary = state["digital"]
	d["created"] = true
	d["visits"] = int(d.get("visits", 0)) + int(opts.get("visits", 1))
	return {"ok": true, "created": true, "visits": int(d["visits"])}


# --- 遗嘱执行 ---

## 按生前意愿执行殡葬与捐献；无效遗嘱仅返回建议。
func execute_will(will: Dictionary, death_info: Dictionary, state: Dictionary) -> Dictionary:
	var valid: bool = bool(will.get("valid", false))
	var method: String = str(will.get("funeral_method", ""))
	var grave: String = str(will.get("grave", ""))
	var wants_donation: bool = bool(will.get("donation", false))
	if valid:
		if method != "" and FUNERAL_METHODS.has(method):
			(state["wishes"] as Dictionary)["method"] = method
		if grave != "" and GRAVE_TYPES.has(grave):
			(state["wishes"] as Dictionary)["grave"] = grave
		(state["wishes"] as Dictionary)["donation"] = wants_donation
		if wants_donation:
			register_donation(state, {"organs": will.get("organs", DONATION_ORGANS)})
	return {
		"ok": true, "valid": valid, "executed": valid,
		"funeral_method": method, "grave": grave, "donation": wants_donation,
		"beneficiaries": (will.get("beneficiaries", []) as Array).duplicate(true),
		"deceased_id": str(death_info.get("id", "")),
	}


# --- 殡葬行业 ---

## 开设殡仪馆/墓地经营体。
func new_funeral_home(name: String, opts: Dictionary = {}) -> Dictionary:
	return {
		"name": name,
		"price_mult": float(opts.get("price_mult", 1.0)),
		"balance": maxi(0, int(opts.get("balance", 0))),
		"reputation": clampf(float(opts.get("reputation", 0.5)), 0.0, 1.0),
		"sales": 0, "profit": 0,
		"regulated": false, "violations": 0,
	}


## 报价：基础成本 × 溢价倍数。
func quote_service(home: Dictionary, method: String, opts: Dictionary = {}) -> Dictionary:
	if not FUNERAL_METHODS.has(method):
		return {"ok": false, "reason": "unknown_method"}
	var base: int = int((FUNERAL_METHODS[method] as Dictionary)["cost"])
	var price: int = int(round(float(base) * float(home.get("price_mult", 1.0))))
	return {"ok": true, "method": method, "price": price, "cost": base}


## 成交结算：入账并累计利润；溢价越高越易触发监管。
func settle_sale(home: Dictionary, method: String, opts: Dictionary = {}) -> Dictionary:
	var q: Dictionary = quote_service(home, method, opts)
	if not bool(q["ok"]):
		return q
	var price: int = int(q["price"])
	var cost: int = int(q["cost"])
	var profit: int = price - cost
	home["balance"] = int(home.get("balance", 0)) + price
	home["sales"] = int(home.get("sales", 0)) + 1
	home["profit"] = int(home.get("profit", 0)) + profit
	var excessive: bool = price > int(round(float(cost) * 2.0))
	if excessive:
		home["violations"] = int(home.get("violations", 0)) + 1
	return {"ok": true, "price": price, "profit": profit, "excessive": excessive, "balance": int(home["balance"])}


## 监管查处：暴利被查处后罚款、降声誉。
func regulate_market(home: Dictionary, opts: Dictionary = {}, rng = null) -> Dictionary:
	var detected: bool = _roll(float(opts.get("roll", -1.0)), rng) < float(opts.get("detect_rate", 0.5))
	var fine: int = 0
	if detected:
		fine = int(round(float(opts.get("fine", 200000)) * (1.0 + float(home.get("violations", 0)))))
		home["balance"] = int(home.get("balance", 0)) - fine
		home["reputation"] = clampf(float(home.get("reputation", 0.0)) - 0.4, 0.0, 1.0)
		home["regulated"] = true
		home["violations"] = 0
	return {"ok": true, "detected": detected, "fine": fine, "reputation": float(home.get("reputation", 0.0))}


## 殡葬陋习改革：抑制铺张与暴利，提升公众满意度。
func reform_customs(state: Dictionary, opts: Dictionary = {}) -> Dictionary:
	if not state.has("industry") or (state["industry"] as Dictionary).is_empty():
		return {"ok": false, "reason": "no_industry"}
	var home: Dictionary = state["industry"]
	home["price_mult"] = clampf(float(home.get("price_mult", 1.0)) - float(opts.get("price_cut", 0.2)), 0.5, 3.0)
	home["reputation"] = clampf(float(home.get("reputation", 0.0)) + 0.2, 0.0, 1.0)
	return {"ok": true, "price_mult": float(home["price_mult"]), "reputation": float(home["reputation"])}


# --- 边界情况 ---

## 无人认领遗体：走公益火化或无名安置。
func unclaimed_body(state: Dictionary, opts: Dictionary = {}) -> Dictionary:
	if not bool(opts.get("unclaimed", false)):
		return {"ok": false, "reason": "not_unclaimed"}
	state["unclaimed"] = true
	var action: String = str(opts.get("action", "public_cremation"))
	return {
		"ok": true, "action": action, "anonymous": action == "public_cremation",
		"cost": maxi(0, int(opts.get("cost", 0))),
	}


## 捐献争议：家属反对与登记冲突时进入争议流程。
func donation_dispute(state: Dictionary, opts: Dictionary = {}, rng = null) -> Dictionary:
	var d: Dictionary = state["donation"]
	d["dispute"] = true
	var resolved: bool = _roll(float(opts.get("roll", -1.0)), rng) < float(opts.get("resolve_rate", 0.6))
	if resolved and bool(opts.get("revoke", false)):
		d["revoked"] = true
		d["registered"] = false
	return {"ok": true, "dispute": true, "resolved": resolved, "revoked": bool(d.get("revoked", false))}


# --- 序列化 ---

func to_dict(state: Dictionary) -> Dictionary:
	return state.duplicate(true)


func from_dict(data: Dictionary) -> Dictionary:
	return data.duplicate(true)
