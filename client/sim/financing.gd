class_name FinancingSystem
extends RefCounted
## 创业融资状态机：种子/天使 → A/B/C 轮 → 对赌 → 稀释 → IPO 或并购退出（R47.7-8；design D7）。
##
## 要点：
##   - 融资链路：种子或天使轮出让约 10%–20%，经 A/B/C 轮渐次稀释（R47.7）；
##   - 每轮估值由营收、增长与市场情绪决定；
##   - 对赌失败触发回购或控制权丧失，创始人可能被踢出局（R47.8）；
##   - 退出：IPO 或并购，按持股比例向创始人分配收益。
##
## 设计取舍：
##   - 股权表 cap table 为独立字典，与 CompanySystem 的公司状态解耦，便于测试与存档；
##   - 融资款经 EconomySystem.issue_money 注入公司账户（外部资金进入，非转账）；
##   - 回购支出经 burn_money 回收；退出收益经 issue_money 注入创始人账户；
##   - 无状态机随机，概率性交由注入 rng（当前实现为确定性规则）。

const BaselineScript = preload("res://sim/baseline.gd")

const STAGES: Array = ["seed", "angel", "a", "b", "c"]

## 各轮出让比例区间（占投后股权）。
const EQUITY_RANGE: Dictionary = {
	"seed": [0.10, 0.20],
	"angel": [0.10, 0.20],
	"a": [0.10, 0.20],
	"b": [0.08, 0.15],
	"c": [0.05, 0.12],
}

const CONTROL_THRESHOLD: float = BaselineScript.FIN_CONTROL_THRESHOLD
const VAM_REPURCHASE_RATIO: float = BaselineScript.FIN_VAM_REPURCHASE_RATIO
const VAM_CONTROL_TRANSFER: float = BaselineScript.FIN_VAM_CONTROL_TRANSFER
const REVENUE_MULTIPLE: float = BaselineScript.FIN_REVENUE_MULTIPLE
const ANNUALIZE_DAYS: int = BaselineScript.FIN_ANNUALIZE_DAYS
const GROWTH_BONUS_CAP: float = BaselineScript.FIN_GROWTH_BONUS_CAP
const SENTIMENT_MIN: float = BaselineScript.FIN_SENTIMENT_MIN
const SENTIMENT_MAX: float = BaselineScript.FIN_SENTIMENT_MAX
const MIN_VALUATION: int = BaselineScript.FIN_MIN_VALUATION

const EXITS: Array = ["ipo", "acquired"]


# --- 股权表 ---

## 新建股权表：创始人 100% 持股。
func new_cap_table(company_id: String = "") -> Dictionary:
	return {
		"company_id": company_id,
		"holders": [
			{"id": "founder", "name": "创始人", "type": "founder", "equity": 1.0, "invested": 0},
		],
		"rounds": [],
		"stage": "",
		"valuation": 0,
		"total_raised": 0,
		"control": true,
		"exited": false,
		"exit_kind": "",
	}


func founder_equity(cap: Dictionary) -> float:
	for h in cap.get("holders", []):
		if str((h as Dictionary).get("type", "")) == "founder":
			return float((h as Dictionary).get("equity", 0.0))
	return 0.0


func investor_equity(cap: Dictionary) -> float:
	var total: float = 0.0
	for h in cap.get("holders", []):
		if str((h as Dictionary).get("type", "")) == "investor":
			total += float((h as Dictionary).get("equity", 0.0))
	return total


func holder_equity(cap: Dictionary, id: String) -> float:
	for h in cap.get("holders", []):
		if str((h as Dictionary).get("id", "")) == id:
			return float((h as Dictionary).get("equity", 0.0))
	return 0.0


# --- 估值 ---

func _latest_revenue(company: Dictionary) -> int:
	var history: Array = company.get("revenue_history", [])
	if history.is_empty():
		return 0
	return int((history[history.size() - 1] as Dictionary).get("revenue", 0))


func _growth(company: Dictionary) -> float:
	var history: Array = company.get("revenue_history", [])
	if history.size() < 2:
		return 0.0
	var prev: int = int((history[history.size() - 2] as Dictionary).get("revenue", 0))
	var latest: int = int((history[history.size() - 1] as Dictionary).get("revenue", 0))
	if prev <= 0:
		return 0.0
	return float(latest - prev) / float(prev)


## 估值 = 年化营收 × 倍数 × (1 + 增长) × 市场情绪，下限 MIN_VALUATION。
## growth < 0 时由营收历史推导。
func estimate_valuation(company: Dictionary, sentiment: float = 1.0, growth: float = -1.0) -> int:
	var annual_revenue: int = _latest_revenue(company) * ANNUALIZE_DAYS
	var g: float = growth if growth >= 0.0 else _growth(company)
	g = clampf(g, 0.0, GROWTH_BONUS_CAP)
	var s: float = clampf(sentiment, SENTIMENT_MIN, SENTIMENT_MAX)
	var value: float = float(annual_revenue) * REVENUE_MULTIPLE * (1.0 + g) * s
	return maxi(MIN_VALUATION, int(value))


# --- 融资轮 ---

func next_stage(cap: Dictionary) -> String:
	var idx: int = STAGES.find(str(cap.get("stage", "")))
	if idx < 0:
		return STAGES[0]
	if idx + 1 >= STAGES.size():
		return ""
	return STAGES[idx + 1]


## 进行下一轮融资。opts：stage、equity_pct、valuation、sentiment、investor_id、name。
## 成功后按出让比例稀释既有股东，融资款注入公司账户。
func raise_round(cap: Dictionary, company: Dictionary, economy, opts: Dictionary = {}) -> Dictionary:
	if bool(cap.get("exited", false)):
		return {"ok": false, "reason": "exited"}
	var expected: String = next_stage(cap)
	if expected.is_empty():
		return {"ok": false, "reason": "no_more_rounds"}
	var stage: String = str(opts.get("stage", expected))
	if stage != expected or not EQUITY_RANGE.has(stage):
		return {"ok": false, "reason": "bad_stage", "expected": expected}
	var band: Array = EQUITY_RANGE[stage]
	var pct: float = clampf(float(opts.get("equity_pct", (float(band[0]) + float(band[1])) * 0.5)), float(band[0]), float(band[1]))
	var sentiment: float = float(opts.get("sentiment", 1.0))
	var valuation: int = int(opts.get("valuation", estimate_valuation(company, sentiment)))
	if valuation <= 0:
		return {"ok": false, "reason": "zero_valuation"}
	var investment: int = int(float(valuation) * pct)
	var investor_id: String = str(opts.get("investor_id", "inv." + stage))
	# 稀释既有股东并新增投资人。
	var holders: Array = cap.get("holders", [])
	var scaled: Array = []
	for h in holders:
		var hh: Dictionary = h
		hh["equity"] = float(hh.get("equity", 0.0)) * (1.0 - pct)
		scaled.append(hh)
	var found: bool = false
	for h in scaled:
		if str((h as Dictionary).get("id", "")) == investor_id:
			(h as Dictionary)["equity"] = float((h as Dictionary).get("equity", 0.0)) + pct
			(h as Dictionary)["invested"] = int((h as Dictionary).get("invested", 0)) + investment
			found = true
			break
	if not found:
		scaled.append({
			"id": investor_id,
			"name": str(opts.get("name", investor_id)),
			"type": "investor",
			"equity": pct,
			"invested": investment,
			"stage": stage,
		})
	cap["holders"] = scaled
	cap["stage"] = stage
	cap["valuation"] = valuation
	cap["total_raised"] = int(cap.get("total_raised", 0)) + investment
	cap["control"] = founder_equity(cap) >= CONTROL_THRESHOLD
	var rounds: Array = cap.get("rounds", [])
	rounds.append({
		"stage": stage, "valuation": valuation, "equity_pct": pct,
		"investment": investment, "investor_id": investor_id,
	})
	cap["rounds"] = rounds
	# 融资款注入公司。
	var account: String = str(company.get("account", ""))
	if not account.is_empty():
		economy.issue_money(account, investment, "financing." + stage)
	return {
		"ok": true, "stage": stage, "valuation": valuation, "equity_pct": pct,
		"investment": investment, "founder_equity": founder_equity(cap),
		"control": bool(cap["control"]),
	}


## 期权池等定向稀释：所有既有股东按 pct 出让，份额归入新持有人。
func dilute(cap: Dictionary, pct: float, holder_id: String = "esop", name: String = "期权池") -> Dictionary:
	if pct <= 0.0 or pct >= 1.0:
		return {"ok": false, "reason": "bad_pct"}
	var holders: Array = cap.get("holders", [])
	for h in holders:
		(h as Dictionary)["equity"] = float((h as Dictionary).get("equity", 0.0)) * (1.0 - pct)
	holders.append({"id": holder_id, "name": name, "type": "investor", "equity": pct, "invested": 0})
	cap["holders"] = holders
	cap["control"] = founder_equity(cap) >= CONTROL_THRESHOLD
	return {"ok": true, "founder_equity": founder_equity(cap)}


# --- 对赌 ---

## 对赌结算：实际营收达标则通过；失败时公司有资力则回购，否则创始人让渡控制权。
func settle_vam(cap: Dictionary, company: Dictionary, economy, target_revenue: int, actual_revenue: int, opts: Dictionary = {}) -> Dictionary:
	if bool(cap.get("exited", false)):
		return {"ok": false, "reason": "exited"}
	if actual_revenue >= target_revenue:
		return {"ok": true, "passed": true}
	var remedy: String = str(opts.get("remedy", "auto"))
	var cost: int = int(float(cap.get("valuation", 0)) * VAM_REPURCHASE_RATIO)
	var account: String = str(company.get("account", ""))
	var can_buyback: bool = cost > 0 and not account.is_empty() and economy.liquid(account) >= cost
	if remedy == "auto":
		remedy = "repurchase" if can_buyback else "control"
	if remedy == "repurchase":
		if not can_buyback:
			return {"ok": false, "reason": "insufficient_funds", "cost": cost}
		economy.burn_money(account, cost, "vam_repurchase")
		return {"ok": true, "passed": false, "remedy": "repurchase", "cost": cost}
	# 失去控制权：从创始人处向投资人让渡份额。
	var transfer: float = clampf(float(opts.get("transfer", VAM_CONTROL_TRANSFER)), 0.0, 1.0)
	var holders: Array = cap.get("holders", [])
	var investors: Array = []
	var founder_index: int = -1
	for i in holders.size():
		var h: Dictionary = holders[i]
		if str(h.get("type", "")) == "founder":
			founder_index = i
		elif str(h.get("type", "")) == "investor":
			investors.append(i)
	if founder_index < 0:
		return {"ok": false, "reason": "no_founder"}
	var actual_transfer: float = minf(transfer, float(holders[founder_index].get("equity", 0.0)))
	holders[founder_index]["equity"] = float(holders[founder_index].get("equity", 0.0)) - actual_transfer
	if not investors.is_empty():
		var each: float = actual_transfer / float(investors.size())
		for i in investors:
			holders[i]["equity"] = float(holders[i].get("equity", 0.0)) + each
	cap["holders"] = holders
	var equity: float = founder_equity(cap)
	var kicked_out: bool = equity < CONTROL_THRESHOLD
	cap["control"] = not kicked_out
	return {"ok": true, "passed": false, "remedy": "control", "founder_equity": equity, "kicked_out": kicked_out}


# --- 退出 ---

## IPO 或并购退出：按创始人持股比例分配退出收益，注入创始人账户。
func exit(cap: Dictionary, company: Dictionary, economy, kind: String, opts: Dictionary = {}) -> Dictionary:
	if bool(cap.get("exited", false)):
		return {"ok": false, "reason": "exited"}
	if not EXITS.has(kind):
		return {"ok": false, "reason": "bad_kind"}
	var valuation: int = int(opts.get("valuation", cap.get("valuation", 0)))
	if valuation <= 0:
		return {"ok": false, "reason": "zero_valuation"}
	var equity: float = founder_equity(cap)
	var proceeds: int = int(float(valuation) * equity)
	var owner_account: String = str(opts.get("owner_account", "owner"))
	if proceeds > 0:
		economy.issue_money(owner_account, proceeds, "exit." + kind)
	cap["exited"] = true
	cap["exit_kind"] = kind
	cap["valuation"] = valuation
	return {"ok": true, "kind": kind, "valuation": valuation, "proceeds": proceeds, "founder_equity": equity}


func to_dict(cap: Dictionary) -> Dictionary:
	return cap.duplicate(true)
