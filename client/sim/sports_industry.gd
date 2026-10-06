class_name SportsIndustrySystem
extends RefCounted
## 体育产业与赛事（R76；design D32）。
##
## 与 sports.gd 的运动员个人生涯（训练/参赛/排名/奖金）互补，本模块聚焦职业化与产业层：
##   - 运动员职业化：青训 → 职业合同 → 转会 → 巅峰 → 退役，含经纪人、薪酬、赞助、转会费；
##   - 赛事体系：联赛、杯赛、奥运会、世界杯、全运会，国家队征召与赛程积分、升降级；
##   - 丑闻与合规：兴奋剂、假球、赌球、转会黑幕，药检、禁赛与法律后果；
##   - 伤病：影响竞技状态与生涯长度，严重可致残，含康复与复出；
##   - 俱乐部经营：收购经营，盈亏由成绩、门票、转播、赞助与青训决定；
##   - 边界：降级与破产、球迷冲突、裁判争议、职业体育与学业冲突。
##
## 设计取舍：
##   - 球员、俱乐部、联赛均为纯数据 Dictionary，便于存读档与 headless 测试；
##   - 比赛结果默认按双方实力确定性推导（主场优势），额外随机只由外部 rng 注入，可复现；
##   - 丑闻后果集中在 SCANDALS 表（禁赛天数/罚款/是否涉法），investigate 统一裁决。

const CAREER_STAGES: Array = ["youth", "pro_contract", "transfer", "peak", "retire"]
const CAREER_STAGE_NAMES: Dictionary = {
	"youth": "青训", "pro_contract": "职业合同", "transfer": "转会",
	"peak": "巅峰", "retire": "退役",
}

## 赛事体系：
const COMPETITIONS: Dictionary = {
	"league": {"name": "联赛", "national": false},
	"cup": {"name": "杯赛", "national": false},
	"olympics": {"name": "奥运会", "national": true},
	"world_cup": {"name": "世界杯", "national": true},
	"national_games": {"name": "全运会", "national": true},
}

## 联赛分级：升降级名额。
const DIVISIONS: Dictionary = {
	"top": {"name": "顶级联赛", "promote": 0, "relegate": 2},
	"second": {"name": "次级联赛", "promote": 2, "relegate": 2},
	"third": {"name": "第三级联赛", "promote": 2, "relegate": 0},
}

## 丑闻与合规：禁赛天数、罚款、是否涉法。
const SCANDALS: Dictionary = {
	"doping": {"name": "兴奋剂", "ban_days": 730, "fine": 1000000, "legal": false},
	"match_fixing": {"name": "假球", "ban_days": 365, "fine": 2000000, "legal": true},
	"gambling": {"name": "赌球", "ban_days": 180, "fine": 1500000, "legal": true},
	"transfer_fraud": {"name": "转会黑幕", "ban_days": 0, "fine": 3000000, "legal": true},
}

## 伤病分级：停赛天数、状态惩罚、是否致残。
const INJURIES: Dictionary = {
	"minor": {"name": "轻伤", "days": 14.0, "form_penalty": 5.0, "permanent": false},
	"moderate": {"name": "中度伤病", "days": 60.0, "form_penalty": 12.0, "permanent": false},
	"severe": {"name": "重伤", "days": 240.0, "form_penalty": 25.0, "permanent": false},
	"career_ending": {"name": "致残", "days": 0.0, "form_penalty": 100.0, "permanent": true},
}

const PEAK_AGE_MIN: int = 24
const PEAK_AGE_MAX: int = 30
const HOME_ADVANTAGE: float = 5.0
const BASE_MARKET_VALUE: int = 5000000
const AGENT_FEE_RATE: float = 0.10
const CLUB_BASE_SPONSOR: int = 5000000
const BROADCAST_BASE: int = 8000000
const TICKET_BASE_PRICE: int = 10000


# --- 数据表 ---

func career_stages() -> Array:
	return CAREER_STAGES.duplicate()


func competition_keys() -> Array:
	return COMPETITIONS.keys()


func competition_def(competition: String) -> Dictionary:
	if not COMPETITIONS.has(competition):
		return {}
	return (COMPETITIONS[competition] as Dictionary).duplicate(true)


func division_keys() -> Array:
	return DIVISIONS.keys()


func division_def(division: String) -> Dictionary:
	if not DIVISIONS.has(division):
		return {}
	return (DIVISIONS[division] as Dictionary).duplicate(true)


func scandal_keys() -> Array:
	return SCANDALS.keys()


func scandal_def(kind: String) -> Dictionary:
	if not SCANDALS.has(kind):
		return {}
	return (SCANDALS[kind] as Dictionary).duplicate(true)


func injury_keys() -> Array:
	return INJURIES.keys()


func injury_def(severity: String) -> Dictionary:
	if not INJURIES.has(severity):
		return {}
	return (INJURIES[severity] as Dictionary).duplicate(true)


# --- 运动员与俱乐部 ---

func new_pro(player_id: String, club_id: String = "", opts: Dictionary = {}) -> Dictionary:
	return {
		"id": player_id,
		"name": str(opts.get("name", player_id)),
		"position": str(opts.get("position", "midfielder")),
		"club": club_id,
		"career_stage": "pro_contract",
		"age": maxi(16, int(opts.get("age", 20))),
		"wage": maxi(0, int(opts.get("wage", 1000000))),
		"contract_years": maxf(0.0, float(opts.get("contract_years", 3.0))),
		"market_value": maxi(0, int(opts.get("market_value", BASE_MARKET_VALUE))),
		"form": clampf(float(opts.get("form", 60.0)), 0.0, 100.0),
		"appearances": 0,
		"goals": 0,
		"injury_days": 0.0,
		"last_injury": "",
		"ban_days": 0.0,
		"disabled": false,
		"doping": false,
		"agent": str(opts.get("agent", "")),
		"sponsors": [],
		"national_team": "",
		"enrolled": bool(opts.get("enrolled", false)),
	}


func new_club(club_id: String, opts: Dictionary = {}) -> Dictionary:
	return {
		"id": club_id,
		"name": str(opts.get("name", club_id)),
		"division": str(opts.get("division", "top")),
		"points": 0,
		"played": 0,
		"won": 0,
		"drawn": 0,
		"lost": 0,
		"goals_for": 0,
		"goals_against": 0,
		"budget": maxi(0, int(opts.get("budget", 10000000))),
		"ticket_price": maxi(0, int(opts.get("ticket_price", TICKET_BASE_PRICE))),
		"attendance": maxi(0, int(opts.get("attendance", 20000))),
		"fans": maxi(0, int(opts.get("fans", 50000))),
		"squad": [],
		"strength": clampf(float(opts.get("strength", 60.0)), 0.0, 100.0),
		"youth_academy": clampf(float(opts.get("youth_academy", 0.5)), 0.0, 1.0),
		"reputation": clampf(float(opts.get("reputation", 50.0)), 0.0, 100.0),
		"bankrupt": false,
	}


func player_strength(player: Dictionary) -> float:
	if bool(player.get("disabled", false)) or float(player.get("ban_days", 0.0)) > 0.0:
		return 5.0
	return clampf(float(player.get("form", 60.0)), 0.0, 100.0)


func club_strength(club: Dictionary) -> float:
	var squad: Array = club.get("squad", [])
	if squad.is_empty():
		return clampf(float(club.get("strength", 60.0)), 0.0, 100.0)
	var total: float = 0.0
	for p in squad:
		total += player_strength(p)
	return total / float(squad.size())


# --- 职业化 ---

func new_league(league_id: String, division: String = "top", opts: Dictionary = {}) -> Dictionary:
	return {
		"id": league_id,
		"name": str(opts.get("name", league_id)),
		"division": division,
		"season": 0,
		"clubs": [],
		"standings": {},
		"fixtures": [],
	}


func register_club(league: Dictionary, club: Dictionary) -> Dictionary:
	var clubs: Array = league["clubs"]
	if not clubs.has(str(club["id"])):
		clubs.append(str(club["id"]))
	var standings: Dictionary = league["standings"]
	standings[str(club["id"])] = {
		"id": str(club["id"]), "played": 0, "won": 0, "drawn": 0, "lost": 0,
		"goals_for": 0, "goals_against": 0, "points": 0,
	}
	return {"ok": true, "clubs": clubs.size()}


## 青训产出：青训等级越高，潜力评分越高。
func youth_graduate(club: Dictionary, rng = null, opts: Dictionary = {}) -> Dictionary:
	var luck: float = _roll(float(opts.get("luck", -1.0)), rng) * 20.0
	var potential: float = clampf(40.0 + float(club.get("youth_academy", 0.5)) * 40.0 + luck, 0.0, 100.0)
	var player: Dictionary = new_pro("youth_%d" % (int(club.get("_youth_seq", 0)) + 1), str(club["id"]), {
		"age": 17, "wage": 200000, "market_value": int(potential * 100000.0),
		"form": potential * 0.6,
	})
	player["career_stage"] = "youth"
	player["potential"] = potential
	club["_youth_seq"] = int(club.get("_youth_seq", 0)) + 1
	(club["squad"] as Array).append(player)
	club["strength"] = club_strength(club)
	return {"ok": true, "player": player, "potential": potential}


## 签订职业合同：青训转入职业，约定月薪与年限。
func sign_pro_contract(player: Dictionary, club: Dictionary, wage: int, years: float) -> Dictionary:
	if str(player.get("career_stage", "")) not in ["youth", "pro_contract", "transfer", "peak"]:
		return {"ok": false, "reason": "bad_stage"}
	var w: int = maxi(0, wage)
	player["club"] = str(club["id"])
	player["wage"] = w
	player["contract_years"] = maxf(0.1, years)
	player["career_stage"] = "pro_contract"
	if not (club["squad"] as Array).has(player):
		(club["squad"] as Array).append(player)
	return {"ok": true, "wage": w, "contract_years": float(player["contract_years"])}


## 身价估值：状态、年龄窗口与合同剩余共同决定。
func market_value(player: Dictionary, opts: Dictionary = {}) -> int:
	var age: int = int(player.get("age", 24))
	var age_factor: float = 1.0
	if age < PEAK_AGE_MIN:
		age_factor = 0.8 + 0.05 * float(age - 16)
	elif age <= PEAK_AGE_MAX:
		age_factor = 1.3
	else:
		age_factor = maxf(0.2, 1.3 - 0.1 * float(age - PEAK_AGE_MAX))
	var form_factor: float = 0.5 + clampf(float(player.get("form", 0.0)), 0.0, 100.0) / 100.0
	var value: int = int(float(BASE_MARKET_VALUE) * age_factor * form_factor * float(opts.get("value_factor", 1.0)))
	player["market_value"] = maxi(0, value)
	return int(player["market_value"])


## 转会：结算转会费与经纪人佣金，可含转会黑幕。
func transfer(player: Dictionary, to_club: Dictionary, fee: int, opts: Dictionary = {}) -> Dictionary:
	if bool(player.get("disabled", false)):
		return {"ok": false, "reason": "disabled"}
	var amount: int = maxi(0, fee)
	var agent_fee: int = int(round(float(amount) * float(opts.get("agent_fee_rate", AGENT_FEE_RATE))))
	var fraud: bool = bool(opts.get("fraud", false))
	player["club"] = str(to_club["id"])
	player["career_stage"] = "transfer"
	if not (to_club["squad"] as Array).has(player):
		(to_club["squad"] as Array).append(player)
	to_club["strength"] = club_strength(to_club)
	return {
		"ok": true, "fee": amount, "agent_fee": agent_fee,
		"to_club": str(to_club["id"]), "fraud": fraud,
	}


## 续约/报价：薪酬与年限，低薪可能被拒。
func offer_contract(player: Dictionary, wage: int, years: float, opts: Dictionary = {}) -> Dictionary:
	var expected: int = int(float(player.get("market_value", BASE_MARKET_VALUE)) * 0.05)
	var ratio: float = 1.0
	if expected > 0:
		ratio = float(maxi(0, wage)) / float(expected)
	var acceptable: bool = bool(opts.get("force", false)) or ratio >= 0.6
	if acceptable:
		player["wage"] = maxi(0, wage)
		player["contract_years"] = maxf(0.1, years)
	return {"ok": true, "accepted": acceptable, "expected_wage": expected, "ratio": ratio}


func retire(player: Dictionary, opts: Dictionary = {}) -> Dictionary:
	player["career_stage"] = "retire"
	var pension: int = int(opts.get("pension", int(player.get("wage", 0)) * 12))
	return {"ok": true, "stage": "retire", "pension": maxi(0, pension)}


func sponsorship(player: Dictionary, deal: Dictionary) -> Dictionary:
	var amount: int = maxi(0, int(deal.get("amount", 0)))
	var rec: Dictionary = {
		"brand": str(deal.get("brand", "赞助商")),
		"amount": amount,
		"years": maxf(0.0, float(deal.get("years", 1.0))),
	}
	(player["sponsors"] as Array).append(rec)
	player["market_value"] = int(player.get("market_value", 0)) + amount / 10
	return {"ok": true, "sponsor": rec}


# --- 赛事体系 ---

func schedule_season(league: Dictionary) -> Dictionary:
	var clubs: Array = (league["clubs"] as Array).duplicate()
	var fixtures: Array = []
	for i in clubs.size():
		for j in range(i + 1, clubs.size()):
			fixtures.append({"home": str(clubs[i]), "away": str(clubs[j]), "played": false})
	league["fixtures"] = fixtures
	league["season"] = int(league.get("season", 0)) + 1
	return {"ok": true, "fixtures": fixtures.size()}


## 比赛：按双方实力与主场优势推演比分；可用 opts 覆盖或用 rng 注入随机。
func play_match(league: Dictionary, home: Dictionary, away: Dictionary, rng = null, opts: Dictionary = {}) -> Dictionary:
	var home_str: float = club_strength(home) + HOME_ADVANTAGE
	var away_str: float = club_strength(away)
	var noise_home: float = _noise(rng) * 10.0
	var noise_away: float = _noise(rng) * 10.0
	var home_score: int = int(opts.get("home_score", clampi(int(round((home_str + noise_home) / 30.0)), 0, 9)))
	var away_score: int = int(opts.get("away_score", clampi(int(round((away_str + noise_away) / 30.0)), 0, 9)))
	var standings: Dictionary = league["standings"]
	var h: Dictionary = standings.get(str(home["id"]), _empty_row(str(home["id"])))
	var a: Dictionary = standings.get(str(away["id"]), _empty_row(str(away["id"])))
	h["played"] = int(h["played"]) + 1
	a["played"] = int(a["played"]) + 1
	h["goals_for"] = int(h["goals_for"]) + home_score
	h["goals_against"] = int(h["goals_against"]) + away_score
	a["goals_for"] = int(a["goals_for"]) + away_score
	a["goals_against"] = int(a["goals_against"]) + home_score
	var winner: String = "draw"
	if home_score > away_score:
		h["won"] = int(h["won"]) + 1
		h["points"] = int(h["points"]) + 3
		a["lost"] = int(a["lost"]) + 1
		winner = str(home["id"])
	elif away_score > home_score:
		a["won"] = int(a["won"]) + 1
		a["points"] = int(a["points"]) + 3
		h["lost"] = int(h["lost"]) + 1
		winner = str(away["id"])
	else:
		h["drawn"] = int(h["drawn"]) + 1
		a["drawn"] = int(a["drawn"]) + 1
		h["points"] = int(h["points"]) + 1
		a["points"] = int(a["points"]) + 1
	standings[str(home["id"])] = h
	standings[str(away["id"])] = a
	league["standings"] = standings
	return {"ok": true, "home_score": home_score, "away_score": away_score, "winner": winner}


func _empty_row(club_id: String) -> Dictionary:
	return {"id": club_id, "played": 0, "won": 0, "drawn": 0, "lost": 0, "goals_for": 0, "goals_against": 0, "points": 0}


## 积分榜：按积分、净胜球、进球数降序。
func standings(league: Dictionary) -> Array:
	var rows: Array = []
	for key in (league["standings"] as Dictionary).keys():
		rows.append((league["standings"] as Dictionary)[key])
	rows.sort_custom(func(a, b):
		var pa: int = int(a["points"])
		var pb: int = int(b["points"])
		if pa != pb:
			return pa > pb
		var da: int = int(a["goals_for"]) - int(a["goals_against"])
		var db: int = int(b["goals_for"]) - int(b["goals_against"])
		if da != db:
			return da > db
		return int(a["goals_for"]) > int(b["goals_for"]))
	return rows


## 升降级：顶级末位降入次级，次级前位升入顶级。
func apply_promotion_relegation(top_league: Dictionary, second_league: Dictionary, clubs_by_id: Dictionary) -> Dictionary:
	var top_rows: Array = standings(top_league)
	var second_rows: Array = standings(second_league)
	var top_relegate: int = int((DIVISIONS["top"] as Dictionary)["relegate"])
	var second_promote: int = int((DIVISIONS["second"] as Dictionary)["promote"])
	var relegated: Array = []
	var promoted: Array = []
	var n_down: int = mini(top_relegate, top_rows.size())
	for i in range(top_rows.size() - n_down, top_rows.size()):
		relegated.append(str((top_rows[i] as Dictionary)["id"]))
	for i in mini(second_promote, second_rows.size()):
		promoted.append(str((second_rows[i] as Dictionary)["id"]))
	for cid in relegated:
		if clubs_by_id.has(cid):
			(clubs_by_id[cid] as Dictionary)["division"] = "second"
	for cid in promoted:
		if clubs_by_id.has(cid):
			(clubs_by_id[cid] as Dictionary)["division"] = "top"
	return {"ok": true, "relegated": relegated, "promoted": promoted}


## 国家队征召：状态达标且未禁赛/未致残才可入选。
func national_callup(player: Dictionary, nation: String, opts: Dictionary = {}) -> Dictionary:
	if bool(player.get("disabled", false)):
		return {"ok": false, "reason": "disabled"}
	if float(player.get("ban_days", 0.0)) > 0.0:
		return {"ok": false, "reason": "banned"}
	var threshold: float = float(opts.get("form_threshold", 65.0))
	if float(player.get("form", 0.0)) < threshold:
		return {"ok": false, "reason": "form_too_low", "form": float(player.get("form", 0.0))}
	player["national_team"] = nation
	return {"ok": true, "nation": nation, "form": float(player.get("form", 0.0))}


## 国际赛事（简化）：按实力推演名次，返回冠军与奖励。
func international_tournament(competition: String, teams: Array, rng = null, opts: Dictionary = {}) -> Dictionary:
	if not COMPETITIONS.has(competition):
		return {"ok": false, "reason": "unknown_competition"}
	var best: Dictionary = {}
	var best_strength: float = -1.0
	for t in teams:
		var strength: float = float((t as Dictionary).get("strength", 50.0)) + _noise(rng) * 8.0
		if strength > best_strength:
			best_strength = strength
			best = (t as Dictionary).duplicate()
	var champion: String = str(best.get("name", best.get("id", "")))
	return {"ok": true, "competition": competition, "champion": champion, "reward": int(opts.get("reward", 30000000))}


# --- 丑闻与合规 ---

func doping_test(player: Dictionary, roll: float, opts: Dictionary = {}) -> Dictionary:
	if not bool(player.get("doping", false)):
		return {"ok": true, "positive": false}
	var hit: bool = roll < clampf(float(opts.get("detect_chance", 0.6)), 0.0, 1.0)
	if hit:
		player["ban_days"] = float((SCANDALS["doping"] as Dictionary)["ban_days"])
	return {"ok": true, "positive": hit, "ban_days": float(player.get("ban_days", 0.0))}


func set_doping(player: Dictionary, on: bool = true) -> Dictionary:
	player["doping"] = on
	return {"ok": true, "doping": on}


## 违规裁决：按丑闻类型施加禁赛、罚款，涉法的追加法律责任。
func commit_scandal(player: Dictionary, kind: String, rng = null, opts: Dictionary = {}) -> Dictionary:
	if not SCANDALS.has(kind):
		return {"ok": false, "reason": "unknown_scandal"}
	var def: Dictionary = SCANDALS[kind]
	var ban: float = float(def["ban_days"])
	var fine: int = int(def["fine"])
	player["ban_days"] = maxf(float(player.get("ban_days", 0.0)), ban)
	var legal: bool = bool(def["legal"])
	var prison_days: float = 0.0
	if legal:
		prison_days = float(opts.get("prison_days", 90.0))
	return {"ok": true, "kind": kind, "ban_days": ban, "fine": fine, "legal": legal, "prison_days": prison_days}


## 假球/赌球/转会黑幕被调查：按 roll 命中则披露并处罚。
func investigate(kind: String, roll: float, opts: Dictionary = {}) -> Dictionary:
	if not SCANDALS.has(kind):
		return {"ok": false, "reason": "unknown_scandal"}
	var def: Dictionary = SCANDALS[kind]
	var risk: float = clampf(float(opts.get("risk", 0.5)), 0.0, 1.0)
	var exposed: bool = roll < risk or bool(opts.get("force", false))
	if not exposed:
		return {"ok": true, "kind": kind, "exposed": false}
	return {
		"ok": true, "kind": kind, "exposed": true,
		"ban_days": float(def["ban_days"]), "fine": int(def["fine"]), "legal": bool(def["legal"]),
	}


# --- 伤病 ---

func injury_risk(player: Dictionary, opts: Dictionary = {}) -> float:
	var base: float = float(opts.get("base_risk", 0.08))
	var age: int = int(player.get("age", 24))
	if age > PEAK_AGE_MAX:
		base *= 1.0 + 0.1 * float(age - PEAK_AGE_MAX)
	return clampf(base, 0.0, 0.95)


## 施加伤病：设置停赛天数与状态惩罚，career_ending 直接致残。
func injure(player: Dictionary, severity: String, opts: Dictionary = {}) -> Dictionary:
	if not INJURIES.has(severity):
		return {"ok": false, "reason": "unknown_severity"}
	var def: Dictionary = INJURIES[severity]
	var days: float = float(def["days"])
	player["injury_days"] = maxf(float(player.get("injury_days", 0.0)), days)
	player["form"] = clampf(float(player.get("form", 60.0)) - float(def["form_penalty"]), 0.0, 100.0)
	player["last_injury"] = severity
	if bool(def["permanent"]):
		player["disabled"] = true
	return {
		"ok": true, "severity": severity, "days": days,
		"form": float(player["form"]), "permanent": bool(def["permanent"]),
	}


## 复出：按天数康复，康复后清除伤病天数并部分恢复状态。
func rehab(player: Dictionary, days: float) -> Dictionary:
	if bool(player.get("disabled", false)):
		return {"ok": false, "reason": "disabled"}
	var remaining: float = maxf(0.0, float(player.get("injury_days", 0.0)) - maxf(0.0, days))
	player["injury_days"] = remaining
	if remaining <= 0.0:
		player["form"] = clampf(float(player.get("form", 0.0)) + 5.0, 0.0, 100.0)
		return {"ok": true, "recovered": true, "form": float(player["form"])}
	return {"ok": true, "recovered": false, "remaining_days": remaining}


# --- 俱乐部经营 ---

func club_matchday_income(club: Dictionary) -> int:
	return maxi(0, int(club.get("attendance", 0))) * maxi(0, int(club.get("ticket_price", 0)))


## 赛季收入：转播（按名次）、赞助、门票与青训输送分成。
func club_season_income(club: Dictionary, placement: int, opts: Dictionary = {}) -> Dictionary:
	var broadcast: int = int(float(BROADCAST_BASE) * float(opts.get("broadcast_factor", 1.0)))
	var sponsor: int = int(float(CLUB_BASE_SPONSOR) * (1.0 + float(club.get("reputation", 50.0)) / 100.0))
	var matchday: int = 0
	var matches: int = maxi(0, int(opts.get("home_matches", 15)))
	matchday = club_matchday_income(club) * matches
	var prize: int = 0
	if placement >= 1 and placement <= 4:
		prize = int(float(BROADCAST_BASE) * (5.0 - float(placement)))
	var youth: int = int(float(club.get("youth_academy", 0.5)) * 1000000.0)
	var total: int = broadcast + sponsor + matchday + prize + youth
	return {
		"ok": true, "broadcast": broadcast, "sponsor": sponsor, "matchday": matchday,
		"prize": prize, "youth": youth, "total": total,
	}


## 俱乐部财务：收入 − 薪资 − 运营；预算转负即破产。
func club_finance(club: Dictionary, placement: int, opts: Dictionary = {}) -> Dictionary:
	var income: Dictionary = club_season_income(club, placement, opts)
	var payroll: int = maxi(0, int(club.get("wage_bill", int(income["total"]) * 0.6)))
	var operations: int = maxi(0, int(opts.get("operations", 2000000)))
	var net: int = int(income["total"]) - payroll - operations
	club["budget"] = int(club.get("budget", 0)) + net
	if int(club["budget"]) < 0:
		club["bankrupt"] = true
	return {"ok": true, "income": income, "payroll": payroll, "operations": operations, "net": net, "budget": int(club["budget"]), "bankrupt": bool(club["bankrupt"])}


func club_bankrupt(club: Dictionary, opts: Dictionary = {}) -> Dictionary:
	if not bool(club.get("bankrupt", false)) and int(club.get("budget", 0)) >= 0:
		return {"ok": false, "reason": "solvent"}
	club["bankrupt"] = true
	var division: String = str(club.get("division", "top"))
	if division == "top":
		club["division"] = "second"
	elif division == "second":
		club["division"] = "third"
	club["squad"] = []
	return {"ok": true, "bankrupt": true, "division": str(club["division"])}


# --- 边界 ---

## 球迷文化与球场冲突：罚款并损伤声誉。
func fan_violence(club: Dictionary, roll: float, opts: Dictionary = {}) -> Dictionary:
	var risk: float = clampf(float(opts.get("risk", 0.15)), 0.0, 1.0)
	if roll >= risk and not bool(opts.get("force", false)):
		return {"ok": true, "incident": false}
	var fine: int = maxi(0, int(opts.get("fine", 500000)))
	var fan_loss: float = clampf(float(opts.get("fan_loss", 0.05)), 0.0, 1.0)
	club["budget"] = int(club.get("budget", 0)) - fine
	club["fans"] = maxi(0, int(float(club.get("fans", 0)) * (1.0 - fan_loss)))
	club["reputation"] = clampf(float(club.get("reputation", 50.0)) - 8.0, 0.0, 100.0)
	return {"ok": true, "incident": true, "fine": fine, "fans": int(club["fans"]), "reputation": float(club["reputation"])}


## 裁判争议：影响比赛公信力，可能申诉罚款。
func referee_controversy(result: Dictionary, roll: float, opts: Dictionary = {}) -> Dictionary:
	var risk: float = clampf(float(opts.get("risk", 0.2)), 0.0, 1.0)
	var disputed: bool = roll < risk or bool(opts.get("force", false))
	return {"ok": true, "disputed": disputed, "protest_fee": int(opts.get("protest_fee", 100000)) if disputed else 0}


## 职业体育与学业冲突：投入训练压缩学业，未毕业者受影响。
func academic_conflict(player: Dictionary, opts: Dictionary = {}) -> Dictionary:
	if not bool(player.get("enrolled", false)):
		return {"ok": true, "conflict": false}
	var penalty: float = clampf(float(opts.get("gpa_penalty", 10.0)), 0.0, 100.0)
	player["gpa"] = clampf(float(player.get("gpa", 70.0)) - penalty, 0.0, 100.0)
	var can_continue: bool = float(player.get("gpa", 70.0)) >= float(opts.get("gpa_floor", 60.0))
	if not can_continue:
		player["enrolled"] = false
	return {"ok": true, "conflict": true, "gpa": float(player["gpa"]), "can_continue": can_continue}


func _noise(rng) -> float:
	if rng == null:
		return 0.0
	return rng.next_float() * 2.0 - 1.0


func _roll(forced: float, rng) -> float:
	if forced >= 0.0:
		return clampf(forced, 0.0, 1.0)
	if rng != null:
		return rng.next_float()
	return 0.0


func to_dict(data: Dictionary) -> Dictionary:
	return data.duplicate(true)


func from_dict(data: Dictionary) -> Dictionary:
	return data.duplicate(true)
