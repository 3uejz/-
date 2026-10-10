class_name InheritanceSystem
extends RefCounted
## 继承：遗嘱执行、法定继承、遗产税、争产与监护权（R51.5；design D11、D3）。
##
## 无遗嘱按法定顺序：配偶 → 子女 → 父母 → 兄弟姐妹；争议触发 D12 诉讼；
## 遗产税复用 TaxSystem.inheritance_tax；未成年子女需判定监护权。

const BaselineScript = preload("res://sim/baseline.gd")

const TaxScript = preload("res://sim/tax.gd")

const INTESTATE_ORDER: Array = ["spouse", "children", "parents", "siblings"]
const DISPUTE_BASE: float = BaselineScript.INHERIT_DISPUTE_BASE
const DISPUTE_MULTI_HEIR_BONUS: float = BaselineScript.INHERIT_DISPUTE_MULTI_HEIR_BONUS
const DISPUTE_WILL_REDUCTION: float = BaselineScript.INHERIT_DISPUTE_WILL_REDUCTION


## 遗产税（委托 TaxSystem）。
func estate_tax(estate: float) -> float:
	return TaxScript.new().inheritance_tax(estate)


## 结算遗产（R51.5）。will 形如 {"valid":bool,"beneficiaries":[{"id","share"}]}；
## heirs 形如 {"spouse":[id],"children":[id],...}。
func settle(estate: float, will: Dictionary, heirs: Dictionary) -> Dictionary:
	var e: float = maxf(0.0, estate)
	var tax: float = estate_tax(e)
	var net: float = e - tax
	var allocations: Array = []
	if bool(will.get("valid", false)) and not (will.get("beneficiaries", []) as Array).is_empty():
		var total_share: float = 0.0
		var bens: Array = will["beneficiaries"]
		for b in bens:
			total_share += maxf(0.0, float(b.get("share", 0.0)))
		if total_share > 0.0:
			for b in bens:
				var share: float = maxf(0.0, float(b.get("share", 0.0))) / total_share
				allocations.append({"id": str(b.get("id", "")), "amount": net * share, "basis": "will"})
	else:
		for tier in INTESTATE_ORDER:
			var members: Array = heirs.get(tier, [])
			if not members.is_empty():
				for m in members:
					allocations.append({"id": str(m), "amount": net / float(members.size()), "basis": tier})
				break
	var escheat: bool = allocations.is_empty()
	return {"estate": e, "tax": tax, "net": net, "allocations": allocations, "escheat": escheat}


## 争产判定（R51.5）：多继承人或遗嘱存在时概率上升/下降。争议触发 D12 诉讼。
func dispute(allocations: Array, has_will: bool, rng = null) -> Dictionary:
	if allocations.size() <= 1 and not has_will:
		return {"litigation": false, "probability": 0.0}
	var prob: float = DISPUTE_BASE
	if allocations.size() > 1:
		prob += DISPUTE_MULTI_HEIR_BONUS
	if has_will:
		prob -= DISPUTE_WILL_REDUCTION
	prob = clampf(prob, 0.0, 0.95)
	var roll: float = rng.next_float() if rng != null else 1.0
	return {"litigation": roll < prob, "probability": prob}


## 监护权判定（R51.5）：为未成年子女择定监护人（按适配度）。
func guardianship(minor_ids: Array, candidates: Array) -> Dictionary:
	var best: Dictionary = {}
	for c in candidates:
		if best.is_empty() or float(c.get("suitability", 0.0)) > float(best.get("suitability", 0.0)):
			best = c
	return {"guardian": best, "minors": minor_ids.duplicate(), "ok": not best.is_empty()}
