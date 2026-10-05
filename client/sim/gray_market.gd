class_name GrayMarketSystem
extends RefCounted
## 灰产与黑市（R26；design D12/D14）。
##
## 黑市买卖、赌博、高利贷与走私产业链；结算收益与风险并累积违法记录与恶名；
## 被查获时返回刑事信息，供 CrimeSystem/JusticeSystem 触发法律后果。

## 黑市商品（legal=false 属违禁品）。
const BLACK_MARKET: Dictionary = {
	"counterfeit_bag": {"name": "高仿包", "price": 80000, "resale": 150000, "legal": false},
	"fake_watch": {"name": "假名表", "price": 200000, "resale": 400000, "legal": false},
	"stolen_phone": {"name": "赃物手机", "price": 30000, "resale": 60000, "legal": false},
	"illegal_drug": {"name": "违禁药品", "price": 500000, "resale": 1200000, "legal": false},
	"wildlife": {"name": "野生动物制品", "price": 800000, "resale": 2000000, "legal": false},
	"weapon": {"name": "管制器械", "price": 1500000, "resale": 3000000, "legal": false},
	"tax_free_goods": {"name": "水货电子", "price": 100000, "resale": 180000, "legal": true},
}

## 赌博项目（house_edge 庄家优势）。
const GAMBLING: Dictionary = {
	"dice": {"name": "掷骰", "house_edge": 0.03, "skill_factor": 0.0},
	"poker": {"name": "扑克", "house_edge": 0.05, "skill_factor": 0.4},
	"mahjong": {"name": "麻将", "house_edge": 0.05, "skill_factor": 0.5},
	"lottery": {"name": "彩票", "house_edge": 0.5, "skill_factor": 0.0},
	"casino": {"name": "赌场", "house_edge": 0.08, "skill_factor": 0.1},
	"sports_betting": {"name": "体育博彩", "house_edge": 0.1, "skill_factor": 0.3},
}

const LOAN_INTEREST_DAILY: float = 0.01
const SMUGGLING_ROUTES: Dictionary = {
	"electronics": {"name": "电子产品", "investment": 500000, "profit": 0.6, "heat": 10.0},
	"luxury": {"name": "奢侈品", "investment": 1000000, "profit": 0.8, "heat": 15.0},
	"medicine": {"name": "走私药品", "investment": 800000, "profit": 1.2, "heat": 25.0},
	"wildlife": {"name": "野生动物", "investment": 1500000, "profit": 1.5, "heat": 35.0},
	"weapons": {"name": "军火", "investment": 3000000, "profit": 2.0, "heat": 50.0},
}

const GAMBLING_ADDICTION_THRESHOLD: float = 60.0


func black_market_goods() -> Array:
	return BLACK_MARKET.keys()


func goods_info(id: String) -> Dictionary:
	return (BLACK_MARKET.get(id, {}) as Dictionary).duplicate()


func gambling_games() -> Array:
	return GAMBLING.keys()


func smuggling_routes() -> Array:
	return SMUGGLING_ROUTES.keys()


## 黑市买入（R26.1、R26.2）：产生恶名与热度。
func buy(state: Dictionary, good_id: String, quantity: int) -> Dictionary:
	if not BLACK_MARKET.has(good_id):
		return {"ok": false, "reason": "unknown_good"}
	var g: Dictionary = BLACK_MARKET[good_id]
	var qty: int = maxi(1, quantity)
	var cost: int = int(g["price"]) * qty
	state["heat"] = clampf(float(state.get("heat", 0.0)) + (5.0 if not bool(g["legal"]) else 1.0) * qty, 0.0, 100.0)
	state["inventory"] = state.get("inventory", {})
	state["inventory"][good_id] = int(state["inventory"].get(good_id, 0)) + qty
	return {"ok": true, "good": good_id, "quantity": qty, "cost": cost, "heat": float(state["heat"]), "illegal": not bool(g["legal"])}


## 黑市卖出（R26.2）。
func sell(state: Dictionary, good_id: String, quantity: int) -> Dictionary:
	if not BLACK_MARKET.has(good_id):
		return {"ok": false, "reason": "unknown_good"}
	var inv: Dictionary = state.get("inventory", {})
	var qty: int = mini(maxi(1, quantity), int(inv.get(good_id, 0)))
	if qty <= 0:
		return {"ok": false, "reason": "no_inventory"}
	var g: Dictionary = BLACK_MARKET[good_id]
	var revenue: int = int(g["resale"]) * qty
	inv[good_id] = int(inv[good_id]) - qty
	state["heat"] = clampf(float(state.get("heat", 0.0)) + (5.0 if not bool(g["legal"]) else 1.0) * qty, 0.0, 100.0)
	return {"ok": true, "good": good_id, "quantity": qty, "revenue": revenue, "heat": float(state["heat"])}


## 赌博（R26.1、R26.2）；skill 0..100 抵消部分庄家优势。
func gamble(state: Dictionary, game_id: String, bet: int, skill: float = 0.0, rng = null) -> Dictionary:
	if not GAMBLING.has(game_id):
		return {"ok": false, "reason": "unknown_game"}
	var g: Dictionary = GAMBLING[game_id]
	var edge: float = clampf(float(g["house_edge"]) - clampf(skill, 0.0, 100.0) / 100.0 * float(g["skill_factor"]), 0.0, 0.9)
	var roll: float = rng.next_float() if rng != null else 0.5
	var won: bool = roll > edge
	var payout: int = 0
	if won:
		payout = int(round(float(bet) * (1.0 + edge + 0.5)))
	state["heat"] = clampf(float(state.get("heat", 0.0)) + (2.0 if game_id in ["casino", "lottery"] else 1.0), 0.0, 100.0)
	state["gambling_addiction"] = clampf(float(state.get("gambling_addiction", 0.0)) + 3.0, 0.0, 100.0)
	return {"ok": true, "game": game_id, "bet": bet, "won": won, "payout": payout, "edge": edge, "addiction": float(state["gambling_addiction"])}


## 高利贷借入（R26.1）。
func loan_shark_borrow(state: Dictionary, amount: int, term_days: int) -> Dictionary:
	var interest: int = int(round(float(amount) * LOAN_INTEREST_DAILY * float(term_days)))
	var loan: Dictionary = {"principal": amount, "interest": interest, "due": amount + interest, "term_days": term_days, "repaid": false, "overdue_days": 0}
	state["loans"] = state.get("loans", [])
	state["loans"].append(loan)
	state["heat"] = clampf(float(state.get("heat", 0.0)) + 3.0, 0.0, 100.0)
	return {"ok": true, "principal": amount, "interest": interest, "due": amount + interest}


## 高利贷还款。
func repay(state: Dictionary, loan: Dictionary, amount: int) -> Dictionary:
	loan["due"] = maxi(0, int(loan["due"]) - amount)
	if int(loan["due"]) <= 0:
		loan["repaid"] = true
	return {"ok": true, "remaining": int(loan["due"]), "repaid": bool(loan["repaid"]) }


## 逾期推进与催收（R26.2、R26.3；联动灰色催收 D12）。
func loan_overdue(state: Dictionary, days: int, rng = null) -> Dictionary:
	state["loans"] = state.get("loans", [])
	var collections: int = 0
	for loan in state["loans"]:
		if bool(loan["repaid"]):
			continue
		loan["overdue_days"] = int(loan["overdue_days"]) + days
		if int(loan["overdue_days"]) > int(loan["term_days"]):
			loan["due"] = int(round(float(loan["due"]) * (1.0 + LOAN_INTEREST_DAILY * days * 2.0)))
			collections += 1
	return {"ok": true, "collections": collections}


## 走私（R26.1、R26.3）：投入资金，成败由风险与运气决定；被查获返回刑事信息。
func smuggle(state: Dictionary, route_id: String, risk_mitigation: float = 0.0, rng = null) -> Dictionary:
	if not SMUGGLING_ROUTES.has(route_id):
		return {"ok": false, "reason": "unknown_route"}
	var r: Dictionary = SMUGGLING_ROUTES[route_id]
	var heat: float = float(state.get("heat", 0.0))
	var catch_prob: float = clampf(float(r["heat"]) / 100.0 + heat / 200.0 - clampf(risk_mitigation, 0.0, 1.0) * 0.3, 0.05, 0.9)
	var roll: float = rng.next_float() if rng != null else 2.0
	if roll < catch_prob:
		state["heat"] = clampf(heat + 25.0, 0.0, 100.0)
		return {"ok": true, "caught": true, "loss": int(r["investment"]), "seriousness": int(r["heat"]) / 10.0, "crime": "smuggling", "criminal": true}
	var profit: int = int(round(float(r["investment"]) * float(r["profit"])))
	state["heat"] = clampf(heat + int(r["heat"]) / 4.0, 0.0, 100.0)
	return {"ok": true, "caught": false, "profit": profit, "heat": float(state["heat"])}


## 违法记录与恶名累积（R26.2）。
func infamy(state: Dictionary) -> Dictionary:
	var heat: float = clampf(float(state.get("heat", 0.0)), 0.0, 100.0)
	return {"heat": heat, "infamy_gain": heat / 10.0, "wanted": heat >= 70.0}
