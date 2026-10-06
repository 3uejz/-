class_name IpMediaSystem
extends RefCounted
## 知识产权与媒体工业（R69；design D25）。
##
## 覆盖：
##   - IP 类型：版权/专利/商标/商业秘密；可登记、授权、转让、质押并产生许可费
##     （专利登记可与 ResearchSystem 呼应，本系统独立可测，不直接依赖它）；
##   - 侵权处理：监测 → 取证 → 诉讼 → 赔偿 → 禁令；胜率由证据、律师与法院倾向决定；
##   - 媒体机构：新闻社/出版社/影视公司/MCN/平台；作品发行复用公司经营与作品发行入参；
##   - 舆论与公关：票房/销量影响声誉与收入，负面报道触发声誉危机，含危机公关与撤稿；
##   - 内容审查与合规：平台审核、内容合规、版权下架与言论法律风险；
##   - 边界：抢注与恶意诉讼、抄袭被揭露、媒体造谣担责、版权到期进入公有领域。
##
## 设计取舍：
##   - IP 与媒体机构均为纯数据 Dictionary，便于存读档与 headless 测试；
##   - 时间以分钟计，版权年限换算 365×1440 分钟，商业秘密不设期限；
##   - 诉讼胜率 = 证据 + 律师 + 法院倾向 的线性加权，简单可解释；
##   - 随机项统一由 opts 的 roll 或外部 rng 注入，缺省确定化，便于断言；
##   - 与既有系统解耦：公司经营、作品质量、声望效应均以入参或结构化返回值交给上层编排。

const IP_COPYRIGHT: String = "copyright"
const IP_PATENT: String = "patent"
const IP_TRADEMARK: String = "trademark"
const IP_TRADE_SECRET: String = "trade_secret"

## IP 类型：保护年限（0 表示无限期）、登记费、基准许可费率。
const IP_TYPES: Dictionary = {
	"copyright": {"name": "版权", "term_years": 50, "registration_fee": 10000, "license_rate": 0.10},
	"patent": {"name": "专利", "term_years": 20, "registration_fee": 50000, "license_rate": 0.15},
	"trademark": {"name": "商标", "term_years": 10, "registration_fee": 20000, "license_rate": 0.08},
	"trade_secret": {"name": "商业秘密", "term_years": 0, "registration_fee": 5000, "license_rate": 0.12},
}

## 媒体机构类型：营收模式、声誉敏感度。
const MEDIA_TYPES: Dictionary = {
	"news_agency": {"name": "新闻社", "revenue_model": "advertising", "reputation_sensitivity": 0.8},
	"publisher": {"name": "出版社", "revenue_model": "sales", "reputation_sensitivity": 0.6},
	"film_company": {"name": "影视公司", "revenue_model": "box_office", "reputation_sensitivity": 0.7},
	"mcn": {"name": "MCN", "revenue_model": "creator_cut", "reputation_sensitivity": 0.9},
	"platform": {"name": "平台", "revenue_model": "commission", "reputation_sensitivity": 0.5},
}

const MINUTES_PER_YEAR: int = 365 * 1440

var _seq: int = 0


func _roll(forced: float, rng) -> float:
	if forced >= 0.0:
		return clampf(forced, 0.0, 1.0)
	if rng != null:
		return rng.next_float()
	return 0.0


# --- IP 登记与生命周期 ---

## 登记知识产权。term_years 缺省取类型基线；商业秘密不设到期。
func register_ip(ip_type: String, owner: String, title: String, opts: Dictionary = {}) -> Dictionary:
	if not IP_TYPES.has(ip_type):
		return {"ok": false, "reason": "unknown_ip_type"}
	var def: Dictionary = IP_TYPES[ip_type]
	var created: int = int(opts.get("created_minute", 0))
	var term: int = int(opts.get("term_years", int(def["term_years"])))
	var expiry: int = created + term * MINUTES_PER_YEAR if term > 0 else 0
	_seq += 1
	var ip: Dictionary = {
		"id": str(opts.get("id", "ip.%s.%d" % [ip_type, _seq])),
		"type": ip_type,
		"owner": owner,
		"title": title,
		"status": "registered",
		"created_minute": created,
		"expiry_minute": expiry,
		"public_domain": false,
		"licenses": [],
		"pledged": false,
		"pledge_amount": 0,
		"evidence": clampf(float(opts.get("evidence", 0.0)), 0.0, 1.0),
	}
	return {"ok": true, "ip": ip}


## 续展（仅有限期 IP）。返回新的到期时间。
func renew_ip(ip: Dictionary, now_minute: int, years: int) -> Dictionary:
	if bool(ip.get("public_domain", false)) or int(ip.get("expiry_minute", 0)) <= 0:
		return {"ok": false, "reason": "perpetual_or_expired"}
	var y: int = maxi(0, years)
	ip["expiry_minute"] = maxi(int(ip["expiry_minute"]), now_minute) + y * MINUTES_PER_YEAR
	return {"ok": true, "expiry_minute": int(ip["expiry_minute"])}


## 到期判定：有限期 IP 到时进入公有领域。
func expire_ip(ip: Dictionary, now_minute: int) -> Dictionary:
	var expiry: int = int(ip.get("expiry_minute", 0))
	if expiry <= 0:
		return {"ok": false, "reason": "perpetual"}
	if now_minute < expiry:
		return {"ok": false, "reason": "not_expired", "remaining_minutes": expiry - now_minute}
	ip["public_domain"] = true
	ip["status"] = "public_domain"
	return {"ok": true, "public_domain": true}


# --- 许可、转让与质押 ---

## 许可费 = 交易规模 × 类型费率 × （独占加成）。
func license_fee(ip: Dictionary, deal_size: float, opts: Dictionary = {}) -> Dictionary:
	var def: Dictionary = IP_TYPES.get(str(ip.get("type", "")), {})
	var rate: float = float(def.get("license_rate", 0.1))
	var factor: float = 1.5 if bool(opts.get("exclusive", false)) else 1.0
	var fee: int = int(round(maxf(0.0, deal_size) * rate * factor))
	return {"ok": true, "fee": fee, "rate": rate, "exclusive": bool(opts.get("exclusive", false))}


## 授权：记录被许可方、交易规模与许可费。
func license_ip(ip: Dictionary, licensee: String, deal_size: float, opts: Dictionary = {}) -> Dictionary:
	if bool(ip.get("public_domain", false)):
		return {"ok": false, "reason": "public_domain"}
	var fee: Dictionary = license_fee(ip, deal_size, opts)
	(ip["licenses"] as Array).append({
		"licensee": licensee, "deal_size": maxf(0.0, deal_size),
		"fee": int(fee["fee"]), "exclusive": bool(fee["exclusive"]),
		"minute": int(opts.get("minute", 0)),
	})
	return {"ok": true, "fee": int(fee["fee"]), "licenses": (ip["licenses"] as Array).size()}


## 转让：所有权变更并记录成交价。
func transfer_ip(ip: Dictionary, buyer: String, price: int) -> Dictionary:
	var seller: String = str(ip.get("owner", ""))
	ip["owner"] = buyer
	ip["transfer_price"] = maxi(0, price)
	return {"ok": true, "from": seller, "to": buyer, "price": maxi(0, price)}


## 质押：以 IP 作为担保物融资。
func pledge_ip(ip: Dictionary, amount: int) -> Dictionary:
	if bool(ip.get("public_domain", false)):
		return {"ok": false, "reason": "public_domain"}
	ip["pledged"] = true
	ip["pledge_amount"] = maxi(0, amount)
	return {"ok": true, "pledged": true, "amount": maxi(0, amount)}


# --- 侵权监测与诉讼 ---

## 侵权监测：相似度越高越易被发现，逻辑取证提升证据强度。
func monitor_infringement(ip: Dictionary, suspect: String, opts: Dictionary = {}, rng = null) -> Dictionary:
	var similarity: float = clampf(float(opts.get("similarity", 0.5)), 0.0, 1.0)
	var roll: float = _roll(float(opts.get("roll", -1.0)), rng)
	var detected: bool = roll < similarity
	var evidence: float = clampf(similarity * 0.8 + clampf(float(opts.get("forensics", 0.5)), 0.0, 1.0) * 0.2, 0.0, 1.0)
	return {"ok": true, "detected": detected, "evidence_strength": evidence, "suspect": suspect}


## 诉讼：胜率由证据、律师能力与法院倾向线性决定。
## 胜诉后结算赔偿与禁令；败诉无赔偿。
func file_lawsuit(ip: Dictionary, opts: Dictionary = {}, rng = null) -> Dictionary:
	var evidence: float = clampf(float(opts.get("evidence", ip.get("evidence", 0.5))), 0.0, 1.0)
	var lawyer: float = clampf(float(opts.get("lawyer_skill", 0.5)), 0.0, 1.0)
	var court: float = clampf(float(opts.get("court_bias", 0.5)), 0.0, 1.0)
	var prob: float = clampf(0.2 + evidence * 0.35 + lawyer * 0.25 + court * 0.20, 0.05, 0.95)
	var roll: float = _roll(float(opts.get("roll", -1.0)), rng)
	var win: bool = roll < prob
	var damage_base: float = maxf(0.0, float(opts.get("damage_base", 1000000.0)))
	var compensation: int = int(round(damage_base * (0.5 + evidence * 0.5))) if win else 0
	var injunction: bool = win and bool(opts.get("seek_injunction", true))
	return {
		"ok": true, "win": win, "probability": prob,
		"compensation": compensation, "injunction": injunction,
	}


## 主动维权：先监测再决定是否诉讼的组合入口（可选便捷封装）。
func enforce_ip(ip: Dictionary, suspect: String, opts: Dictionary = {}, rng = null) -> Dictionary:
	var monitor: Dictionary = monitor_infringement(ip, suspect, opts, rng)
	if not bool(monitor["detected"]):
		return {"ok": true, "action": "none", "monitor": monitor}
	var lawsuit: Dictionary = file_lawsuit(ip, opts, rng)
	return {"ok": true, "action": "lawsuit", "monitor": monitor, "lawsuit": lawsuit}


# --- 媒体机构与作品发行 ---

func new_media_outlet(media_type: String, opts: Dictionary = {}) -> Dictionary:
	if not MEDIA_TYPES.has(media_type):
		return {"ok": false, "reason": "unknown_media_type"}
	_seq += 1
	return {
		"ok": true,
		"outlet": {
			"id": str(opts.get("id", "media.%d" % _seq)),
			"type": media_type,
			"name": str(opts.get("name", (MEDIA_TYPES[media_type] as Dictionary)["name"])),
			"reputation": clampf(float(opts.get("reputation", 0.5)), 0.0, 1.0),
			"cash": maxi(0, int(opts.get("cash", 0))),
			"works": [],
			"articles": [],
		},
	}


## 作品发行：票房/销量与声誉由质量、宣发、舆论与运气共同决定。
func release_work(outlet: Dictionary, work: Dictionary, opts: Dictionary = {}, rng = null) -> Dictionary:
	var quality: float = clampf(float(work.get("quality", 0.5)), 0.0, 1.0)
	var hype: float = clampf(float(opts.get("hype", 0.5)), 0.0, 1.0)
	var opinion: float = clampf(float(opts.get("opinion", 0.0)), -1.0, 1.0)
	var roll: float = _roll(float(opts.get("roll", -1.0)), rng)
	var performance: float = clampf(quality * 0.5 + hype * 0.3 + roll * 0.2 + opinion * 0.1, 0.0, 1.0)
	var scale: float = maxf(0.0, float(opts.get("scale", 10000000.0)))
	var revenue: int = int(round(scale * performance))
	var sensitivity: float = float((MEDIA_TYPES.get(str(outlet.get("type", "")), {}) as Dictionary).get("reputation_sensitivity", 0.5))
	var rep_delta: float = (performance - 0.5) * 0.2 * sensitivity
	outlet["cash"] = int(outlet.get("cash", 0)) + revenue
	outlet["reputation"] = clampf(float(outlet.get("reputation", 0.5)) + rep_delta, 0.0, 1.0)
	(outlet["works"] as Array).append({
		"title": str(work.get("title", "")), "quality": quality,
		"performance": performance, "revenue": revenue,
	})
	return {
		"ok": true, "performance": performance, "revenue": revenue,
		"reputation_delta": rep_delta, "box_office": revenue if str(outlet["type"]) == "film_company" else 0,
		"sales": revenue if str(outlet["type"]) == "publisher" else 0,
	}


# --- 舆论、公关与撤稿 ---

## 负面报道：按严重度与可信度打击目标声誉，超阈触发声誉危机。
func negative_report(target: Dictionary, severity: float, opts: Dictionary = {}) -> Dictionary:
	var sev: float = clampf(severity, 0.0, 1.0)
	var credibility: float = clampf(float(opts.get("credibility", 0.5)), 0.0, 1.0)
	var hit: float = sev * credibility
	target["reputation"] = clampf(float(target.get("reputation", 0.5)) - hit * 0.6, 0.0, 1.0)
	return {
		"ok": true, "reputation_delta": -hit * 0.6,
		"crisis": hit >= float(opts.get("crisis_threshold", 0.3)),
	}


## 危机公关：策略决定基础恢复力，预算提高成功率。
func crisis_pr(target: Dictionary, strategy: String, opts: Dictionary = {}, rng = null) -> Dictionary:
	var strategies: Dictionary = {"apologize": 0.6, "deny": 0.2, "legal": 0.35, "silence": 0.1}
	var base: float = float(strategies.get(strategy, 0.2))
	var budget: float = clampf(float(opts.get("budget", 0.0)), 0.0, 1.0)
	var success_prob: float = clampf(base + budget * 0.3, 0.0, 0.95)
	var roll: float = _roll(float(opts.get("roll", -1.0)), rng)
	var success: bool = roll < success_prob
	var rep_delta: float = 0.0
	if success:
		rep_delta = base * 0.5
		target["reputation"] = clampf(float(target.get("reputation", 0.5)) + rep_delta, 0.0, 1.0)
	var cost: int = int(round(budget * 1000000.0))
	return {
		"ok": true, "strategy": strategy, "success": success,
		"probability": success_prob, "reputation_delta": rep_delta, "cost": cost,
	}


## 发布稿件（供撤稿引用）。
func publish_article(outlet: Dictionary, title: String, opts: Dictionary = {}) -> Dictionary:
	_seq += 1
	var article: Dictionary = {
		"id": str(opts.get("id", "article.%d" % _seq)),
		"title": title,
		"retracted": false,
		"minute": int(opts.get("minute", 0)),
	}
	(outlet["articles"] as Array).append(article)
	return {"ok": true, "article": article}


## 撤稿：更正错误报道，但承担声誉与成本惩罚。
func retract(outlet: Dictionary, article_id: String, opts: Dictionary = {}) -> Dictionary:
	for a in (outlet["articles"] as Array):
		var article: Dictionary = a
		if str(article["id"]) == article_id:
			if bool(article["retracted"]):
				return {"ok": false, "reason": "already_retracted"}
			article["retracted"] = true
			outlet["reputation"] = clampf(float(outlet["reputation"]) - 0.1, 0.0, 1.0)
			return {"ok": true, "retracted": true, "cost": int(opts.get("cost", 100000))}
	return {"ok": false, "reason": "article_not_found"}


# --- 内容审查与合规 ---

## 平台审核：风险随严格度提高更易被拒；版权侵权直接下架。
func moderate_content(content: String, opts: Dictionary = {}) -> Dictionary:
	if bool(opts.get("copyright_infringement", false)):
		return {"ok": true, "approved": false, "action": "takedown", "reason": "copyright", "content": content}
	var risk: float = clampf(float(opts.get("risk", 0.3)), 0.0, 1.0)
	var strictness: float = clampf(float(opts.get("policy_strictness", 0.5)), 0.0, 1.0)
	var approved: bool = risk < (1.0 - strictness)
	if approved:
		return {"ok": true, "approved": true, "action": "allow", "content": content}
	return {"ok": true, "approved": false, "action": "reject", "reason": "content_violation", "content": content}


## 版权下架：对侵权内容执行下架。
func copyright_takedown(content: String, ip: Dictionary) -> Dictionary:
	if bool(ip.get("public_domain", false)):
		return {"ok": false, "reason": "public_domain"}
	return {"ok": true, "action": "takedown", "content": content, "ip_id": str(ip.get("id", ""))}


# --- 边界：抢注、恶意诉讼、抄袭与造谣 ---

## 商标抢注争议：先使用证据充分可挑战抢注。
func trademark_squatting(existing_brand: String, squatter: String, opts: Dictionary = {}) -> Dictionary:
	var prior_use: float = clampf(float(opts.get("prior_use", 0.5)), 0.0, 1.0)
	return {
		"ok": true, "squatting": true, "brand": existing_brand, "squatter": squatter,
		"challenge_wins": prior_use >= 0.5, "prior_use": prior_use,
	}


## 恶意诉讼：原告证据薄弱时败诉并承担赔偿责任。
func malicious_lawsuit(defendant: String, opts: Dictionary = {}, rng = null) -> Dictionary:
	var plaintiff_evidence: float = clampf(float(opts.get("plaintiff_evidence", 0.1)), 0.0, 1.0)
	var prob: float = clampf(plaintiff_evidence, 0.05, 0.95)
	var roll: float = _roll(float(opts.get("roll", -1.0)), rng)
	var plaintiff_wins: bool = roll < prob
	var cost: int = int(round(maxf(0.0, float(opts.get("damage_base", 500000.0))))) if not plaintiff_wins else 0
	return {
		"ok": true, "defendant": defendant, "plaintiff_wins": plaintiff_wins,
		"malicious": not plaintiff_wins, "defendant_damages": cost,
	}


## 抄袭被揭露：作品声誉受损并可能触发赔偿。
func plagiarism_exposed(work: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var severity: float = clampf(float(opts.get("severity", 0.7)), 0.0, 1.0)
	work["plagiarized"] = true
	return {
		"ok": true, "plagiarized": true,
		"reputation_delta": -severity, "damages": int(round(severity * float(opts.get("damage_base", 1000000.0)))),
	}


## 媒体造谣担责：报道失实被证伪后，媒体承担罚金与声誉损失。
func defamation_liability(outlet: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var proven_false: bool = bool(opts.get("proven_false", true))
	if not proven_false:
		return {"ok": true, "liable": false, "fine": 0, "reputation_delta": 0.0}
	var severity: float = clampf(float(opts.get("severity", 0.6)), 0.0, 1.0)
	var fine: int = int(round(severity * float(opts.get("max_fine", 2000000.0))))
	outlet["reputation"] = clampf(float(outlet.get("reputation", 0.5)) - severity * 0.4, 0.0, 1.0)
	return {"ok": true, "liable": true, "fine": fine, "reputation_delta": -severity * 0.4}


func to_dict(ip: Dictionary) -> Dictionary:
	return ip.duplicate(true)


func from_dict(data: Dictionary) -> Dictionary:
	return data.duplicate(true)
