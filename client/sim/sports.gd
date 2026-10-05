class_name SportsSystem
extends RefCounted
## 体育独立生涯：训练、赛事、排名、奖金、伤病与年龄窗口（R45.7；design D5、D32）。
##
## 训练提升体能与技术；赛事按实力与运气决定名次与奖金；伤病与年龄窗口限制生涯。
## 兴奋剂可短期提升但存在药检风险。
##
## 设计取舍：
##   - 运动员状态存于独立字典；随机性由注入 rng 决定，便于复现与三端对齐。

const SPORTS: Array = ["track", "swimming", "ball", "combat", "gymnastics"]
const SPORT_NAMES: Dictionary = {
	"track": "田径", "swimming": "游泳", "ball": "球类",
	"combat": "格斗", "gymnastics": "体操",
}

const PEAK_MIN_AGE: int = 22
const PEAK_MAX_AGE: int = 28
const AGE_DECLINE_RATE: float = 0.97
const AGE_FLOOR: float = 0.3
const TRAIN_RATE: float = 0.4
const INJURY_PENALTY: float = 8.0
const INJURY_BASE_RISK: float = 0.02
const DOPING_BOOST: float = 10.0
const DOPING_BAN_CHANCE: float = 0.3


func new_athlete(sport: String) -> Dictionary:
	return {
		"sport": sport, "physique": 50.0, "technique": 50.0,
		"ranking": 999, "prize_total": 0, "injuries": 0,
		"doping": false, "banned": false,
	}


## 年龄窗口系数：22..28 为巅峰，之后逐年衰减，下限 0.3。
func age_factor(age: float) -> float:
	if age < float(PEAK_MIN_AGE):
		return clampf(0.5 + (age - 16.0) * 0.05, 0.5, 1.0)
	if age <= float(PEAK_MAX_AGE):
		return 1.0
	return maxf(AGE_FLOOR, pow(AGE_DECLINE_RATE, age - float(PEAK_MAX_AGE)))


func injury_risk(athlete: Dictionary, age: float, intensity: float = 1.0) -> float:
	var risk: float = INJURY_BASE_RISK * maxf(0.0, intensity)
	if age > float(PEAK_MAX_AGE):
		risk *= 1.0 + 0.05 * (age - float(PEAK_MAX_AGE))
	if bool(athlete.get("doping", false)):
		risk *= 1.3
	return clampf(risk, 0.0, 0.9)


## 训练：按年龄窗口与强度提升体能/技术，并可能受伤。
func train(athlete: Dictionary, hours: float, age: float, rng = null, opts: Dictionary = {}) -> Dictionary:
	if bool(athlete.get("banned", false)):
		return {"ok": false, "reason": "banned"}
	var factor: float = age_factor(age)
	var gain: float = maxf(0.0, hours) * TRAIN_RATE * factor
	var doping_bonus: float = DOPING_BOOST * factor if bool(athlete.get("doping", false)) else 0.0
	athlete["physique"] = clampf(float(athlete["physique"]) + gain * 0.5 + doping_bonus * 0.5, 0.0, 100.0)
	athlete["technique"] = clampf(float(athlete["technique"]) + gain * 0.5 + doping_bonus * 0.5, 0.0, 100.0)
	var injured: bool = false
	var risk: float = injury_risk(athlete, age, float(opts.get("intensity", 1.0)))
	if rng != null and rng.next_float() < risk:
		injured = true
		athlete["injuries"] = int(athlete["injuries"]) + 1
		athlete["physique"] = clampf(float(athlete["physique"]) - INJURY_PENALTY, 0.0, 100.0)
		athlete["technique"] = clampf(float(athlete["technique"]) - INJURY_PENALTY, 0.0, 100.0)
	return {"ok": true, "physique": float(athlete["physique"]), "technique": float(athlete["technique"]), "injured": injured}


## 参赛：按实力、年龄窗口与运气决定名次（越小越好）与奖金。
func compete(athlete: Dictionary, rng = null, opts: Dictionary = {}) -> Dictionary:
	if bool(athlete.get("banned", false)):
		return {"ok": false, "reason": "banned"}
	var age: float = float(opts.get("age", 25.0))
	var luck: float = (rng.next_float() * 20.0 - 10.0) if rng != null else 0.0
	var strength: float = (
		float(athlete["physique"]) * 0.5 + float(athlete["technique"]) * 0.5
	) * age_factor(age) + luck - float(athlete["injuries"]) * 2.0
	var rank: int = clampi(1 + int(round((100.0 - strength) / 4.0)), 1, 200)
	var prize: int = 0
	if rank <= 50:
		prize = int((50 - rank + 1) * 200000)
	athlete["ranking"] = rank
	athlete["prize_total"] = int(athlete["prize_total"]) + prize
	return {"ok": true, "rank": rank, "prize": prize, "strength": maxf(0.0, strength)}


## 使用兴奋剂。
func take_doping(athlete: Dictionary) -> Dictionary:
	athlete["doping"] = true
	return {"ok": true}


## 药检：阳性则禁赛。
func doping_test(athlete: Dictionary, rng = null) -> Dictionary:
	if not bool(athlete.get("doping", false)):
		return {"ok": true, "positive": false}
	var roll: float = rng.next_float() if rng != null else 0.0
	if roll < DOPING_BAN_CHANCE:
		athlete["banned"] = true
		return {"ok": true, "positive": true, "banned": true}
	return {"ok": true, "positive": false}
