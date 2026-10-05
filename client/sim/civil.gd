class_name CivilSystem
extends RefCounted
## 民事纠纷与诉讼（R52；design D12）。
##
## 九类纠纷；处理链协商→调解→起诉→执行，各阶段有和解概率与成本，可请律师或自行；
## 完整诉讼：立案、举证、开庭、判决、上诉、执行；多维证据链与律师能力修正胜率；
## 执行不能、失信被执行人限高限消、财产查封拍卖。

const DISPUTE_TYPES: Array = ["contract", "debt", "tort", "marital_property", "neighbor", "labor", "consumer", "property", "ip"]
const TYPE_NAMES: Dictionary = {
	"contract": "合同", "debt": "债务", "tort": "侵权", "marital_property": "婚姻财产",
	"neighbor": "邻里", "labor": "劳动争议", "consumer": "消费维权", "property": "房产纠纷", "ip": "知识产权",
}
const STAGES: Array = ["negotiate", "mediate", "litigate", "enforcement"]
const LAWYER_FEE_PER_LEVEL: int = 200000


func types_count() -> int:
	return DISPUTE_TYPES.size()


## 新建纠纷。
func new_claim(dispute_type: String, amount: int, plaintiff: String, defendant: String) -> Dictionary:
	return {"type": dispute_type, "amount": amount, "plaintiff": plaintiff, "defendant": defendant, "stage": "negotiate", "settled": false, "won": false, "appealed": false}


## 协商（R52.2）。
func negotiate(claim: Dictionary, lawyer_level: int, rng = null) -> Dictionary:
	return _settle_stage(claim, 0.3, lawyer_level, rng)


## 调解（R52.2）。
func mediate(claim: Dictionary, lawyer_level: int, rng = null) -> Dictionary:
	return _settle_stage(claim, 0.5, lawyer_level, rng)


func _settle_stage(claim: Dictionary, base: float, lawyer_level: int, rng) -> Dictionary:
	var prob: float = clampf(base + clampf(lawyer_level, 0, 5) * 0.06, 0.05, 0.95)
	var roll: float = rng.next_float() if rng != null else 1.0
	var settled: bool = roll < prob
	claim["settled"] = settled
	claim["stage"] = "enforcement" if settled else "mediate"
	return {"ok": true, "settled": settled, "probability": prob, "stage": claim["stage"], "lawyer_cost": lawyer_level * LAWYER_FEE_PER_LEVEL}


## 起诉与判决（R52.2、R52.3）：多维证据链 + 双方律师能力决定胜率。
func litigate(claim: Dictionary, evidence_strength: float, lawyer_level: int, opponent_lawyer: int, rng = null) -> Dictionary:
	claim["stage"] = "litigate"
	var prob: float = 0.5 + (clampf(evidence_strength, 0.0, 1.0) - 0.5) * 0.6 + (float(lawyer_level) - float(opponent_lawyer)) * 0.06
	prob = clampf(prob, 0.05, 0.95)
	var roll: float = rng.next_float() if rng != null else 0.0
	var won: bool = roll < prob
	claim["won"] = won
	var judgment: Dictionary = {
		"won": won, "award": int(round(float(claim["amount"]) * prob)) if won else 0,
		"cost": lawyer_level * LAWYER_FEE_PER_LEVEL, "probability": prob,
	}
	return judgment


## 上诉（R52.3）。
func appeal(claim: Dictionary, judgment: Dictionary, lawyer_level: int, rng = null) -> Dictionary:
	claim["appealed"] = true
	var prob: float = clampf(0.3 + clampf(lawyer_level, 0, 5) * 0.08, 0.1, 0.8)
	var roll: float = rng.next_float() if rng != null else 1.0
	if not bool(judgment["won"]) and roll < prob:
		claim["won"] = true
		return {"ok": true, "overturned": true, "award": int(round(float(claim["amount"]) * 0.8))}
	return {"ok": true, "overturned": false, "award": int(judgment.get("award", 0))}


## 执行（R52.8）：债务人资产不足则执行不能，进入失信被执行人。
func enforce(judgment: Dictionary, debtor_assets: int) -> Dictionary:
	var award: int = int(judgment.get("award", 0))
	if award <= 0:
		return {"ok": true, "recovered": 0, "execution_failure": false}
	var recovered: int = mini(award, maxi(0, debtor_assets))
	var failure: bool = recovered < award
	return {"ok": true, "recovered": recovered, "execution_failure": failure, "outstanding": award - recovered}


## 失信被执行人限高限消（R52.8）。
func dishonest_restrictions(state: Dictionary, outstanding: int) -> Dictionary:
	if outstanding <= 0:
		return {"restricted": false}
	state["dishonest"] = true
	return {"restricted": true, "no_high_consumption": true, "no_flight_rail": true, "outstanding": outstanding}


## 财产查封拍卖（R52.8）。
func seize_auction(assets: int, claim_amount: int) -> Dictionary:
	var seized: int = mini(assets, claim_amount)
	return {"ok": true, "seized": seized, "auctioned": seized > 0, "recovered": seized}
