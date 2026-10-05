class_name PoliticsSystem
extends RefCounted
## 从政路径（R53.1–R53.3、R25.1–R25.2；design D13）。
##
## 五级职级（村/社区→街道/区→市→省→国家）；声望、关系网、政策立场、政绩与派系
## 影响晋升与选举；政策博弈含提案、投票、拉票、施压；贪腐与丑闻有被查处风险，
## 结果可交给刑事司法系统（D12）；政策立场产出对税率/福利/就业的修正。

const TIERS: Array = [
	{"id": "village", "name": "村/社区", "min_status": 0.0, "min_network": 0.0, "min_age": 18},
	{"id": "district", "name": "街道/区", "min_status": 25.0, "min_network": 20.0, "min_age": 25},
	{"id": "city", "name": "市", "min_status": 45.0, "min_network": 40.0, "min_age": 32},
	{"id": "province", "name": "省", "min_status": 65.0, "min_network": 60.0, "min_age": 42},
	{"id": "nation", "name": "国家", "min_status": 85.0, "min_network": 80.0, "min_age": 50},
]

const FACTIONS: Array = ["reform", "moderate", "conservative"]
const FACTION_NAMES: Dictionary = {"reform": "改革派", "moderate": "中间派", "conservative": "保守派"}

const POLICY_ACTIONS: Array = ["propose", "vote", "campaign", "pressure"]

## 政策立场 → 税负/福利/就业修正（R25.1）。
const POLICY_MODIFIERS: Dictionary = {
	"reform": {"tax": -0.05, "welfare": 0.1, "employment": 0.1},
	"moderate": {"tax": 0.0, "welfare": 0.0, "employment": 0.0},
	"conservative": {"tax": 0.05, "welfare": -0.1, "employment": -0.05},
}


func new_career() -> Dictionary:
	return {
		"tier": -1, "faction": "moderate", "reputation": 0.0, "network": 0.0,
		"achievements": 0.0, "corruption": 0.0, "scandal": 0.0, "in_office": false,
	}


func tier_name(index: int) -> String:
	if index < 0 or index >= TIERS.size():
		return "平民"
	return str(TIERS[index]["name"])


func tier_count() -> int:
	return TIERS.size()


## 进入基层（R53.1）。需声望/关系网/年龄满足。
func enter(career: Dictionary, status: float, network: float, age: int) -> Dictionary:
	var t: Dictionary = TIERS[0]
	if status < float(t["min_status"]) or network < float(t["min_network"]) or age < int(t["min_age"]):
		return {"ok": false, "reason": "not_eligible"}
	career["tier"] = 0
	career["in_office"] = true
	career["reputation"] = status
	career["network"] = network
	return {"ok": true, "tier": 0, "name": tier_name(0)}


## 选举/选拔（R53.1）：声望、关系网与派系匹配决定胜率。
func campaign(career: Dictionary, rng = null) -> Dictionary:
	if int(career["tier"]) < 0:
		return {"ok": false, "reason": "not_in_politics"}
	var prob: float = clampf(0.25 + float(career["reputation"]) / 200.0 + float(career["network"]) / 250.0 + float(career["achievements"]) / 400.0, 0.05, 0.9)
	var roll: float = rng.next_float() if rng != null else 0.0
	var won: bool = roll < prob
	if won:
		career["reputation"] = clampf(float(career["reputation"]) + 3.0, 0.0, 100.0)
	return {"ok": true, "won": won, "probability": prob}


## 晋升（R53.1）。
func promote(career: Dictionary, age: int, rng = null) -> Dictionary:
	var cur: int = int(career["tier"])
	if cur < 0:
		return {"ok": false, "reason": "not_in_politics"}
	var next: int = cur + 1
	if next >= TIERS.size():
		return {"ok": false, "reason": "top_tier"}
	var t: Dictionary = TIERS[next]
	if float(career["reputation"]) < float(t["min_status"]) or float(career["network"]) < float(t["min_network"]) or age < int(t["min_age"]):
		return {"ok": false, "reason": "requirements_not_met", "required": t}
	var prob: float = clampf(0.2 + float(career["achievements"]) / 200.0 + float(career["network"]) / 300.0 - float(career["scandal"]) / 100.0, 0.05, 0.9)
	var roll: float = rng.next_float() if rng != null else 0.0
	if roll < prob:
		career["tier"] = next
		return {"ok": true, "promoted": true, "tier": next, "name": tier_name(next)}
	return {"ok": true, "promoted": false, "probability": prob}


## 政策博弈：提案/投票/拉票/施压（R53.2）。
func policy_game(career: Dictionary, action: String, support: float, opposition: float = 0.0, rng = null) -> Dictionary:
	if not POLICY_ACTIONS.has(action):
		return {"ok": false, "reason": "unknown_action"}
	if not bool(career["in_office"]):
		return {"ok": false, "reason": "not_in_office"}
	var faction_fit: float = 1.0 if action != "pressure" else 0.7
	var score: float = clampf(float(support) - float(opposition) + float(career["network"]) / 100.0, -1.0, 1.0) * faction_fit
	var roll: float = rng.next_float() if rng != null else 0.0
	var passed: bool = (score > 0.0) and (roll < clampf(0.4 + score, 0.05, 0.95))
	if passed and action == "propose":
		career["achievements"] = float(career["achievements"]) + 5.0
	return {"ok": true, "action": action, "passed": passed, "score": score}


## 贪腐（R53.3）：收钱换取关系网，抬高查处风险。
func accept_bribe(career: Dictionary, amount: int) -> Dictionary:
	career["corruption"] = clampf(float(career["corruption"]) + float(amount) / 100000.0, 0.0, 100.0)
	career["network"] = clampf(float(career["network"]) + float(amount) / 200000.0, 0.0, 100.0)
	return {"ok": true, "amount": amount, "corruption": float(career["corruption"])}


## 丑闻与查处（R53.3）：命中则接入刑事系统。
func check_scandal(career: Dictionary, rng = null) -> Dictionary:
	var prob: float = clampf(float(career["corruption"]) / 200.0 + float(career["scandal"]) / 300.0, 0.0, 0.8)
	var roll: float = rng.next_float() if rng != null else 1.0
	var caught: bool = roll < prob
	if caught:
		career["scandal"] = float(career["scandal"]) + 20.0
		career["reputation"] = clampf(float(career["reputation"]) - 20.0, 0.0, 100.0)
		return {"ok": true, "caught": true, "criminal": true, "probability": prob}
	return {"ok": true, "caught": false, "probability": prob}


## 政策立场产出经济修正（R25.1、R25.4）。
func policy_modifiers(career: Dictionary) -> Dictionary:
	return (POLICY_MODIFIERS.get(str(career["faction"]), POLICY_MODIFIERS["moderate"]) as Dictionary).duplicate()


## 卸任（R53.1）。
func retire(career: Dictionary) -> Dictionary:
	career["in_office"] = false
	return {"ok": true, "tier": int(career["tier"])}
