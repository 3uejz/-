class_name EducationSystem
extends RefCounted
## 教育学历与证书（R11；R45.4 职称前置；design D5）。
##
## 学历体系：幼儿园、小学、初中、高中、大专、本科、硕士、博士（顺序递进）。
## 证书体系：身份证、户口本、驾照、护照、教师、会计、律师、医师、护士、厨师、飞行等 30 项。
## 在校学习累积进度，考试按能力与进度生成成绩并推进学历；学历与证书作为职业解锁条件。
##
## 设计取舍：
##   - 学历/证书均以 player["education"] / player["licenses"] 数组存储，条目含 content_key 与 status；
##   - 学历要求按顺序比较（高学历满足低学历要求），证书要求按具体条目；
##   - 考试评分由注入 rng 决定随机项，确定化便于复现与三端对齐。

const BaselineScript = preload("res://sim/baseline.gd")

const DEGREE_DEFS: Array = [
	{"id": "edu.kindergarten", "name": "幼儿园", "prereq": "", "years": 3, "difficulty": 10.0},
	{"id": "edu.primary", "name": "小学", "prereq": "edu.kindergarten", "years": 6, "difficulty": 20.0},
	{"id": "edu.junior", "name": "初中", "prereq": "edu.primary", "years": 3, "difficulty": 30.0},
	{"id": "edu.high_school", "name": "高中", "prereq": "edu.junior", "years": 3, "difficulty": 45.0},
	{"id": "edu.college", "name": "大专", "prereq": "edu.high_school", "years": 3, "difficulty": 35.0},
	{"id": "edu.bachelor", "name": "本科", "prereq": "edu.high_school", "years": 4, "difficulty": 55.0},
	{"id": "edu.master", "name": "硕士", "prereq": "edu.bachelor", "years": 3, "difficulty": 70.0},
	{"id": "edu.doctor", "name": "博士", "prereq": "edu.master", "years": 4, "difficulty": 85.0},
]

const CERT_DEFS: Array = [
	{"id": "license.id_card", "name": "身份证", "difficulty": 5.0},
	{"id": "license.household", "name": "户口本", "difficulty": 5.0},
	{"id": "license.driver_c1", "name": "C1 驾照", "difficulty": 40.0, "fee": 500000},
	{"id": "license.driver_a", "name": "A 驾照", "difficulty": 55.0, "fee": 800000},
	{"id": "license.driver_b", "name": "B 驾照", "difficulty": 50.0, "fee": 700000},
	{"id": "license.passport", "name": "护照", "difficulty": 10.0, "fee": 20000},
	{"id": "license.visa", "name": "签证", "difficulty": 30.0, "fee": 100000},
	{"id": "license.teacher", "name": "教师资格证", "req_education": "edu.bachelor", "difficulty": 60.0, "fee": 30000},
	{"id": "license.accountant", "name": "会计证", "req_education": "edu.college", "difficulty": 55.0, "fee": 40000},
	{"id": "license.lawyer", "name": "律师执业证", "req_education": "edu.bachelor", "difficulty": 75.0, "fee": 60000},
	{"id": "license.doctor", "name": "医师资格证", "req_education": "edu.bachelor", "difficulty": 78.0, "fee": 60000},
	{"id": "license.nurse", "name": "护士证", "req_education": "edu.college", "difficulty": 60.0, "fee": 40000},
	{"id": "license.chef", "name": "厨师证", "difficulty": 45.0, "fee": 30000},
	{"id": "license.pilot", "name": "飞行执照", "req_education": "edu.high_school", "difficulty": 80.0, "fee": 5000000},
	{"id": "license.psych_counselor", "name": "心理咨询师", "req_education": "edu.bachelor", "difficulty": 62.0, "fee": 40000},
	{"id": "license.builder", "name": "建造师", "req_education": "edu.college", "difficulty": 65.0, "fee": 50000},
	{"id": "license.fire", "name": "消防证", "difficulty": 45.0, "fee": 30000},
	{"id": "license.electrician", "name": "电工证", "difficulty": 42.0, "fee": 30000},
	{"id": "license.welder", "name": "焊工证", "difficulty": 40.0, "fee": 30000},
	{"id": "license.security", "name": "保安证", "difficulty": 25.0, "fee": 20000},
	{"id": "license.tour_guide", "name": "导游证", "difficulty": 50.0, "fee": 30000},
	{"id": "license.translator", "name": "翻译证", "difficulty": 65.0, "fee": 40000},
	{"id": "license.lifeguard", "name": "游泳救生员", "difficulty": 45.0, "fee": 30000},
	{"id": "license.fitness_coach", "name": "健身教练证", "difficulty": 45.0, "fee": 30000},
	{"id": "license.forklift", "name": "铲车证", "difficulty": 35.0, "fee": 30000},
	{"id": "license.customs_declare", "name": "报关员", "req_education": "edu.college", "difficulty": 58.0, "fee": 40000},
	{"id": "license.social_worker", "name": "社工证", "req_education": "edu.college", "difficulty": 50.0, "fee": 30000},
	{"id": "license.pharmacist", "name": "药剂师", "req_education": "edu.bachelor", "difficulty": 70.0, "fee": 50000},
	{"id": "license.architect", "name": "建筑师", "req_education": "edu.bachelor", "difficulty": 80.0, "fee": 60000},
	{"id": "license.actuary", "name": "精算师", "req_education": "edu.bachelor", "difficulty": 82.0, "fee": 80000},
]

const STUDY_RATE: float = BaselineScript.EDU_STUDY_RATE
const EXAM_PASS_MARGIN: float = BaselineScript.EDU_EXAM_PASS_MARGIN


var _degrees: Dictionary = {}
var _certs: Dictionary = {}
var _degree_order: Array = []


# --- 目录 ---

func register_starter_catalog() -> int:
	for d in DEGREE_DEFS:
		register_degree(d)
	for c in CERT_DEFS:
		register_certificate(c)
	return _degrees.size() + _certs.size()


func register_degree(def: Dictionary) -> Dictionary:
	var id: String = str(def.get("id", ""))
	if id.is_empty() or str(def.get("name", "")).is_empty():
		return {}
	if not _degrees.has(id):
		_degree_order.append(id)
	_degrees[id] = {
		"id": id, "name": str(def["name"]),
		"prereq": str(def.get("prereq", "")),
		"years": int(def.get("years", 0)),
		"difficulty": float(def.get("difficulty", 50.0)),
	}
	return _degrees[id]


func register_certificate(def: Dictionary) -> Dictionary:
	var id: String = str(def.get("id", ""))
	if id.is_empty() or str(def.get("name", "")).is_empty():
		return {}
	_certs[id] = {
		"id": id, "name": str(def["name"]),
		"req_education": str(def.get("req_education", "")),
		"req_licenses": (def.get("req_licenses", []) as Array).duplicate(),
		"req_skills": (def.get("req_skills", {}) as Dictionary).duplicate(),
		"min_age": float(def.get("min_age", 0.0)),
		"fee": int(def.get("fee", 0)),
		"difficulty": float(def.get("difficulty", 50.0)),
	}
	return _certs[id]


func degree_count() -> int:
	return _degrees.size()


func cert_count() -> int:
	return _certs.size()


func get_degree(id: String) -> Dictionary:
	return _degrees.get(id, {})


func get_certificate(id: String) -> Dictionary:
	return _certs.get(id, {})


func degree_order(id: String) -> int:
	return _degree_order.find(id)


# --- 学历判定 ---

func _graduated_keys(player: Dictionary) -> Array:
	var out: Array = []
	for c in (player.get("education", []) as Array):
		if c is Dictionary and str((c as Dictionary).get("status", "")) == "graduated":
			out.append(str((c as Dictionary).get("content_key", "")))
	return out


## 是否持有至少 required 级别的学历（高学历满足低学历要求）。
func has_degree_at_least(player: Dictionary, required: String) -> bool:
	var req_rank: int = degree_order(required)
	if req_rank < 0:
		return _graduated_keys(player).has(required)
	for key in _graduated_keys(player):
		if degree_order(key) >= req_rank:
			return true
	return false


func credential_key(player: Dictionary, which: String, id: String) -> Dictionary:
	for c in (player.get(which, []) as Array):
		if c is Dictionary and str((c as Dictionary).get("content_key", "")) == id:
			return c
	return {}


func _ability(player: Dictionary) -> Dictionary:
	var attrs: Variant = player.get("attrs", {})
	if attrs is Dictionary:
		var a: Variant = (attrs as Dictionary).get("ability", {})
		if a is Dictionary:
			return a
	return {}


# --- 入学与就读 ---

## 入学：校验前置学历，写入 education 数组（in_progress）。
func enroll(player: Dictionary, degree_id: String, now_minute: int = 0) -> Dictionary:
	var def: Dictionary = get_degree(degree_id)
	if def.is_empty():
		return {"ok": false, "reason": "unknown_degree"}
	if bool(has_degree_at_least(player, degree_id)):
		return {"ok": false, "reason": "already_graduated"}
	var existing: Dictionary = credential_key(player, "education", degree_id)
	if not existing.is_empty() and str(existing.get("status", "")) == "in_progress":
		return {"ok": false, "reason": "already_enrolled"}
	var prereq: String = str(def.get("prereq", ""))
	if not prereq.is_empty() and not bool(has_degree_at_least(player, prereq)):
		return {"ok": false, "reason": "prereq", "need": prereq}
	var cred: Dictionary = {
		"content_key": degree_id, "status": "in_progress",
		"study_progress": 0.0, "enrolled_minutes": now_minute,
	}
	var education: Array = player.get("education", [])
	education.append(cred)
	player["education"] = education
	return {"ok": true, "credential": cred}


## 就读：按智力提高学习进度（0..100）。
func study(credential: Dictionary, hours: float, intelligence: float = 50.0) -> float:
	if credential.is_empty() or str(credential.get("status", "")) != "in_progress":
		return float(credential.get("study_progress", 0.0)) if not credential.is_empty() else 0.0
	var gain: float = maxf(0.0, hours) * STUDY_RATE * (0.5 + intelligence / 100.0)
	credential["study_progress"] = clampf(float(credential.get("study_progress", 0.0)) + gain, 0.0, 100.0)
	return float(credential["study_progress"])


## 考试评分 0..100 = 0.5×智力 + 0.3×学习进度 + 0.2×运气 + 随机项。
func exam_score(intelligence: float, progress: float, luck: float, rng) -> float:
	var roll: float = 0.0
	if rng != null:
		roll = rng.next_float() * 20.0 - 10.0
	return clampf(0.5 * intelligence + 0.3 * clampf(progress, 0.0, 100.0) + 0.2 * luck + roll, 0.0, 100.0)


## 学历考试：达到难度即通过并毕业。
func take_degree_exam(player: Dictionary, degree_id: String, rng, opts: Dictionary = {}) -> Dictionary:
	var def: Dictionary = get_degree(degree_id)
	if def.is_empty():
		return {"ok": false, "reason": "unknown_degree", "passed": false}
	var cred: Dictionary = credential_key(player, "education", degree_id)
	if cred.is_empty():
		return {"ok": false, "reason": "not_enrolled", "passed": false}
	var ability: Dictionary = _ability(player)
	var score: float = exam_score(
		float(opts.get("intelligence", ability.get("intelligence", 50.0))),
		float(cred.get("study_progress", 0.0)),
		float(opts.get("luck", ability.get("luck", 50.0))),
		rng)
	var threshold: float = float(def["difficulty"]) - EXAM_PASS_MARGIN
	var passed: bool = score >= threshold
	if passed:
		cred["status"] = "graduated"
		cred["obtained_minutes"] = int(opts.get("now_minute", 0))
		cred["score"] = score
	return {"ok": true, "passed": passed, "score": score, "threshold": threshold}


# --- 证书 ---

## 报考证书：校验学历/证书/技能/年龄，缴纳费用后考试；通过写入 licenses。
func obtain_certificate(player: Dictionary, cert_id: String, economy, owner_account: String, rng = null, opts: Dictionary = {}) -> Dictionary:
	var def: Dictionary = get_certificate(cert_id)
	if def.is_empty():
		return {"ok": false, "reason": "unknown_certificate", "passed": false}
	if not credential_key(player, "licenses", cert_id).is_empty():
		return {"ok": false, "reason": "already_have", "passed": false}
	var req_edu: String = str(def["req_education"])
	if not req_edu.is_empty() and not bool(has_degree_at_least(player, req_edu)):
		return {"ok": false, "reason": "education", "need": req_edu, "passed": false}
	var held: Array = []
	for c in (player.get("licenses", []) as Array):
		if c is Dictionary:
			held.append(str((c as Dictionary).get("content_key", "")))
	for l in (def["req_licenses"] as Array):
		if not held.has(str(l)):
			return {"ok": false, "reason": "license", "need": str(l), "passed": false}
	var levels: Dictionary = {}
	for s in (player.get("skills", []) as Array):
		if s is Dictionary:
			levels[str((s as Dictionary).get("content_key", ""))] = int((s as Dictionary).get("level", 0))
	for k in (def["req_skills"] as Dictionary).keys():
		if int(levels.get(str(k), 0)) < int(def["req_skills"][k]):
			return {"ok": false, "reason": "skill", "need": str(k), "passed": false}
	var age: float = float(opts.get("age", player.get("age", 0.0)))
	if float(def["min_age"]) > 0.0 and age < float(def["min_age"]):
		return {"ok": false, "reason": "age", "passed": false}
	var fee: int = int(def["fee"])
	if fee > 0:
		if not economy.has_account(owner_account) or economy.liquid(owner_account) < fee:
			return {"ok": false, "reason": "insufficient_funds", "passed": false}
		economy.burn_money(owner_account, fee, "certificate_fee")
	var ability: Dictionary = _ability(player)
	var score: float = exam_score(
		float(opts.get("intelligence", ability.get("intelligence", 50.0))),
		float(opts.get("progress", 50.0)),
		float(opts.get("luck", ability.get("luck", 50.0))),
		rng)
	var threshold: float = float(def["difficulty"])
	var passed: bool = score >= threshold
	if passed:
		var licenses: Array = player.get("licenses", [])
		licenses.append({
			"content_key": cert_id, "status": "graduated",
			"obtained_minutes": int(opts.get("now_minute", 0)), "score": score,
		})
		player["licenses"] = licenses
	return {"ok": true, "passed": passed, "score": score, "threshold": threshold, "fee": fee}
