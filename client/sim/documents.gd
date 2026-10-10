class_name DocumentSystem
extends RefCounted
## 证件与权利（R24；design D13）。
##
## 维护身份证、户口、驾照、护照、签证、产权证与营业执照；按行为校验所需证件，
## 缺证时给出办理途径；支持有效期、续办、跨法域换发与整容后人像比对失败。

const BaselineScript = preload("res://sim/baseline.gd")

const MINUTES_PER_YEAR: int = BaselineScript.DOC_MINUTES_PER_YEAR
const PHOTO_MATCH_THRESHOLD: float = BaselineScript.DOC_PHOTO_MATCH_THRESHOLD

## 证件事典。
const DOCUMENTS: Dictionary = {
	"id_card": {"name": "身份证", "authority": "公安", "validity_years": 10, "requirements": [], "fee": 20},
	"household": {"name": "户口簿", "authority": "公安", "validity_years": -1, "requirements": ["id_card"], "fee": 0},
	"driver_license": {"name": "驾驶证", "authority": "车管所", "validity_years": 6, "requirements": ["id_card"], "fee": 100},
	"passport": {"name": "护照", "authority": "出入境管理", "validity_years": 10, "requirements": ["id_card"], "fee": 120},
	"visa": {"name": "签证", "authority": "使领馆", "validity_years": 1, "requirements": ["passport"], "fee": 1000},
	"property_cert": {"name": "不动产权证", "authority": "不动产登记", "validity_years": -1, "requirements": ["id_card", "household"], "fee": 5000},
	"business_license": {"name": "营业执照", "authority": "市场监管", "validity_years": 5, "requirements": ["id_card"], "fee": 300},
}

## 需人像核验的证件。
const PHOTO_DOCS: Array = ["id_card", "passport", "driver_license"]

## 行为 → 所需证件（R24.2）。
const ACTIONS: Dictionary = {
	"open_bank_account": ["id_card"],
	"buy_car": ["id_card", "driver_license"],
	"buy_house": ["id_card", "household"],
	"travel_abroad": ["passport", "visa"],
	"start_company": ["id_card", "business_license"],
	"drive": ["driver_license"],
	"marry": ["id_card", "household"],
}


func doc_types() -> Array:
	return DOCUMENTS.keys()


func doc_info(doc_type: String) -> Dictionary:
	return (DOCUMENTS.get(doc_type, {}) as Dictionary).duplicate()


func new_registry(jurisdiction: String = "CN") -> Dictionary:
	return {"jurisdiction": jurisdiction, "held": {}}


## 证件是否有效（已持有且未过期）。
func has(registry: Dictionary, doc_type: String, now_minute: int = 0) -> bool:
	var held: Dictionary = registry.get("held", {})
	if not held.has(doc_type):
		return false
	var rec: Dictionary = held[doc_type]
	var years: int = int((DOCUMENTS.get(doc_type, {}) as Dictionary).get("validity_years", -1))
	if years < 0:
		return true
	var issued: int = int(rec.get("issued", 0))
	return now_minute < issued + years * MINUTES_PER_YEAR


## 办理/签发证件（R24.1）。前置证件缺失时返回 ok=false 与 missing。
func issue(registry: Dictionary, doc_type: String, now_minute: int = 0) -> Dictionary:
	if not DOCUMENTS.has(doc_type):
		return {"ok": false, "reason": "unknown_document"}
	var info: Dictionary = DOCUMENTS[doc_type]
	var missing: Array = []
	for req in info["requirements"]:
		if not has(registry, req, now_minute):
			missing.append(req)
	if not missing.is_empty():
		return {"ok": false, "reason": "missing_prerequisites", "missing": missing, "guidance": guidance_for(missing[0])}
	registry["held"][doc_type] = {"issued": now_minute, "jurisdiction": registry.get("jurisdiction", "CN")}
	return {"ok": true, "doc_type": doc_type, "fee": int(info["fee"]), "issued": now_minute}


## 校验某行为所需证件（R24.2、R24.3）。
func validate(registry: Dictionary, action: String, now_minute: int = 0) -> Dictionary:
	if not ACTIONS.has(action):
		return {"ok": false, "reason": "unknown_action"}
	var required: Array = ACTIONS[action]
	var missing: Array = []
	for doc_type in required:
		if not has(registry, doc_type, now_minute):
			missing.append(doc_type)
	if missing.is_empty():
		return {"ok": true, "action": action}
	var guidance: Array = []
	for doc_type in missing:
		guidance.append(guidance_for(doc_type))
	return {"ok": false, "reason": "missing_documents", "missing": missing, "guidance": guidance}


## 办理途径（R24.3）。
func guidance_for(doc_type: String) -> Dictionary:
	var info: Dictionary = DOCUMENTS.get(doc_type, {})
	return {"doc_type": doc_type, "name": info.get("name", doc_type), "authority": info.get("authority", ""), "fee": int(info.get("fee", 0)), "requirements": info.get("requirements", [])}


## 续办过期证件。
func renew(registry: Dictionary, doc_type: String, now_minute: int = 0) -> Dictionary:
	if not DOCUMENTS.has(doc_type):
		return {"ok": false, "reason": "unknown_document"}
	registry["held"][doc_type] = {"issued": now_minute, "jurisdiction": registry.get("jurisdiction", "CN")}
	return {"ok": true, "doc_type": doc_type, "issued": now_minute}


## 人像比对（R24；联动 D45）：整容后相似度不足则需重办。
func photo_match(registry: Dictionary, doc_type: String, similarity: float) -> Dictionary:
	var held: Dictionary = registry.get("held", {})
	if not held.has(doc_type):
		return {"ok": false, "reason": "not_held"}
	var match: bool = similarity >= PHOTO_MATCH_THRESHOLD
	return {"ok": true, "match": match, "needs_reissue": not match and PHOTO_DOCS.has(doc_type), "similarity": similarity}


func to_dict(registry: Dictionary) -> Dictionary:
	return registry.duplicate(true)


func from_dict(data: Dictionary) -> Dictionary:
	return {"jurisdiction": str(data.get("jurisdiction", "CN")), "held": (data.get("held", {}) as Dictionary).duplicate(true)}
