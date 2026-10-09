class_name AuthorityMap
extends RefCounted
## 权威边界登记与合并（R52，OI-2 混合权威；gaps 系统性问题 8）。
##
## 逐域声明：谁权威（客户端本地玩法 / 后端全球与宏观）、离线是否允许近似、上线合并策略与锚点字段。
## 用途：
##   - 运行时判断某域是否可以在离线时自行推进（local_may_approximate）；
##   - 上线时按域合并本地与服务端状态（merge），避免"全球人口被本地近似覆盖"或反之；
##   - 作为跨端一致性测试与文档的机器可读来源。

const CLIENT: String = "client"
const SERVER: String = "server"
const SHARED: String = "shared"

const POLICY_SERVER_WINS: String = "server_wins"
const POLICY_CLIENT_WINS: String = "client_wins"
const POLICY_SERVER_IF_PRESENT: String = "server_if_present"

## 域配置：authority / offline（离线是否允许近似）/ policy / anchor / note。
const DOMAINS: Dictionary = {
	"local_play": {
		"authority": CLIENT, "offline": true, "policy": POLICY_CLIENT_WINS,
		"anchor": "", "note": "玩家所在地的精细玩法，客户端权威可离线"
	},
	"population": {
		"authority": SERVER, "offline": true, "policy": POLICY_SERVER_WINS,
		"anchor": "absolute_minutes", "note": "全球人口后端权威，离线用同模型近似"
	},
	"macro_economy": {
		"authority": SERVER, "offline": true, "policy": POLICY_SERVER_WINS,
		"anchor": "absolute_minutes", "note": "GDP/通胀/利率/失业等宏观指标"
	},
	"global_trade": {
		"authority": SERVER, "offline": true, "policy": POLICY_SERVER_WINS,
		"anchor": "absolute_minutes", "note": "跨境贸易与海关"
	},
	"carbon_market": {
		"authority": SERVER, "offline": false, "policy": POLICY_SERVER_WINS,
		"anchor": "absolute_minutes", "note": "碳市场与碳价，需服务端撮合"
	},
	"region_healthcare": {
		"authority": SERVER, "offline": true, "policy": POLICY_SERVER_IF_PRESENT,
		"anchor": "absolute_minutes", "note": "区域医疗承载力，离线近似上线校正"
	},
	"urban_planning": {
		"authority": SERVER, "offline": false, "policy": POLICY_SERVER_WINS,
		"anchor": "absolute_minutes", "note": "城市规划变更需服务端裁决"
	},
	"transport_infra": {
		"authority": SERVER, "offline": true, "policy": POLICY_SERVER_IF_PRESENT,
		"anchor": "absolute_minutes", "note": "交通基建进度，离线近似上线校正"
	},
	"disaster": {
		"authority": SHARED, "offline": true, "policy": POLICY_SERVER_IF_PRESENT,
		"anchor": "absolute_minutes", "note": "灾害同时改区域与宏观，服务端存在则以其为准"
	},
	"epidemic": {
		"authority": SHARED, "offline": true, "policy": POLICY_SERVER_IF_PRESENT,
		"anchor": "absolute_minutes", "note": "流行病传播，服务端存在则以其为准"
	},
	"sports_league": {
		"authority": SERVER, "offline": false, "policy": POLICY_SERVER_WINS,
		"anchor": "absolute_minutes", "note": "联赛赛程与结果需服务端统一"
	},
	"content_pack": {
		"authority": SERVER, "offline": false, "policy": POLICY_SERVER_WINS,
		"anchor": "", "note": "内容包版本以服务端为准"
	},
}

## 已知域列表。
static func domains() -> Array:
	return DOMAINS.keys()

static func config_for(domain: String) -> Dictionary:
	return DOMAINS.get(domain, {})

static func authority_for(domain: String) -> String:
	return str(config_for(domain).get("authority", CLIENT))

static func is_known(domain: String) -> bool:
	return DOMAINS.has(domain)

## 该域离线时是否允许客户端近似推进。未知域默认允许（本地玩法）。
static func local_may_approximate(domain: String) -> bool:
	var cfg: Dictionary = config_for(domain)
	if cfg.is_empty():
		return true
	return bool(cfg.get("offline", true))

## 该域的锚点字段（无则返回空串）。
static func anchor_for(domain: String) -> String:
	return str(config_for(domain).get("anchor", ""))

## 单个值的权威解析：server_value 为 null 表示服务端未提供。
## 返回 {value, source}，source ∈ {client, server}。
static func resolve(domain: String, local_value: Variant, server_value: Variant) -> Dictionary:
	var cfg: Dictionary = config_for(domain)
	var policy: String = str(cfg.get("policy", POLICY_CLIENT_WINS))
	var server_present: bool = server_value != null
	if policy == POLICY_SERVER_WINS:
		if server_present:
			return {"value": server_value, "source": SERVER}
		return {"value": local_value, "source": CLIENT}
	if policy == POLICY_SERVER_IF_PRESENT:
		if server_present:
			return {"value": server_value, "source": SERVER}
		return {"value": local_value, "source": CLIENT}
	return {"value": local_value, "source": CLIENT}

## 按域合并本地快照与服务端快照。
## server_doc 形如 {"domains": {domain: value}, "absolute_minutes": int}。
## 返回 {merged: {domain: value}, sources: {domain: source}, anchor_minute: int}。
static func merge(local_doc: Dictionary, server_doc: Dictionary) -> Dictionary:
	var server_domains: Dictionary = Dictionary(server_doc.get("domains", {}))
	var merged: Dictionary = {}
	var sources: Dictionary = {}
	var keys: Array = []
	for k in local_doc.keys():
		keys.append(k)
	for k in server_domains.keys():
		if not keys.has(k):
			keys.append(k)
	for domain in keys:
		var has_local: bool = local_doc.has(domain)
		var has_server: bool = server_domains.has(domain)
		var local_v: Variant = local_doc.get(domain) if has_local else null
		var server_v: Variant = server_domains.get(domain) if has_server else null
		var r: Dictionary = resolve(domain, local_v, server_v)
		merged[domain] = r["value"]
		sources[domain] = r["source"]
	return {
		"merged": merged,
		"sources": sources,
		"anchor_minute": int(server_doc.get("absolute_minutes", 0)),
	}
