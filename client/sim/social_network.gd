class_name SocialNetworkSystem
extends RefCounted
## 网络社交平台（R50.3、R50.4、R50.10；design D10）。
##
## 覆盖即时通讯、动态朋友圈、论坛贴吧、短视频、直播、兴趣社群、婚恋求职、
## 匿名论坛与暗网入口。发言/互动按影响力与平台传播系数概率扩散，产出对声誉与
## 传闻的效应描述（由调用方交给 ReputationSystem 结算），支持小号匿名与扒皮风险，
## 以及断网时的本地缓存队列。
##
## 本类不直接依赖其他 sim 脚本；效应以结构化返回值交给上层编排。

const BaselineScript = preload("res://sim/baseline.gd")

const RngScript = preload("res://sim/rng.gd")

## 平台定义：spread_coefficient 越高越易扩散；anonymous 表示匿名平台。
const PLATFORMS: Dictionary = {
	"im": {"name": "即时通讯", "spread_coefficient": 0.2, "anonymous": false},
	"moments": {"name": "动态朋友圈", "spread_coefficient": 0.4, "anonymous": false},
	"forum": {"name": "论坛贴吧", "spread_coefficient": 0.6, "anonymous": false},
	"short_video": {"name": "短视频", "spread_coefficient": 0.9, "anonymous": false},
	"livestream": {"name": "直播", "spread_coefficient": 0.8, "anonymous": false},
	"interest_group": {"name": "兴趣社群", "spread_coefficient": 0.3, "anonymous": false},
	"dating_job": {"name": "婚恋求职平台", "spread_coefficient": 0.35, "anonymous": false},
	"anonymous": {"name": "匿名论坛与暗网", "spread_coefficient": 0.7, "anonymous": true},
}

const REACH_CIRCLE: float = BaselineScript.SOCNET_REACH_CIRCLE
const REACH_REGION: float = BaselineScript.SOCNET_REACH_REGION
const TIER_INDEX: Dictionary = {"circle": 1, "region": 2, "public": 3}

var _rng = null
var _posts: Dictionary = {}
var _followers: Dictionary = {}   # "author|platform" -> int
var _seq: int = 0
var _offline_queue: Array = []
var _threads: Dictionary = {}   # target_id -> [{from,to,text,minute,read}]


func _init(seed: int = 0) -> void:
	_rng = RngScript.new(seed)


# --- 平台 ---

func platforms() -> Array:
	return PLATFORMS.keys()


func platform(platform_id: String) -> Dictionary:
	return (PLATFORMS.get(platform_id, {}) as Dictionary).duplicate()


func has_platform(platform_id: String) -> bool:
	return PLATFORMS.has(platform_id)


func is_anonymous_platform(platform_id: String) -> bool:
	return bool((PLATFORMS.get(platform_id, {}) as Dictionary).get("anonymous", false))


# --- 影响力与关注 ---

func followers(author_id: String, platform_id: String) -> int:
	return int(_followers.get("%s|%s" % [author_id, platform_id], 0))


func add_followers(author_id: String, platform_id: String, delta: int) -> int:
	var key: String = "%s|%s" % [author_id, platform_id]
	var next: int = maxi(0, followers(author_id, platform_id) + delta)
	_followers[key] = next
	return next


## 关注数 → 影响力 0..1（对数压缩）。
func influence(author_id: String, platform_id: String) -> float:
	var f: int = followers(author_id, platform_id)
	if f <= 0:
		return 0.0
	return clampf(log(float(f) + 1.0) / log(10001.0), 0.0, 1.0)


# --- 发言与扩散 ---

## 发布一条动态。opts: valence(-1..1)、anonymity、influence(覆盖)、minute、subject_id。
## 返回 post（含 reach/tier/likes/followers_delta/doxxed 与 effects）。
func publish(author_id: String, platform_id: String, content: String, opts: Dictionary = {}) -> Dictionary:
	_seq += 1
	var plat: Dictionary = platform(platform_id)
	var coeff: float = float(plat.get("spread_coefficient", 0.3))
	var anon_platform: bool = bool(plat.get("anonymous", false))
	var anonymity: bool = bool(opts.get("anonymity", false)) or anon_platform
	var valence: float = clampf(float(opts.get("valence", 0.0)), -1.0, 1.0)

	var f: int = followers(author_id, platform_id)
	var infl: float = float(opts.get("influence", clampf(0.2 + influence(author_id, platform_id), 0.0, 1.0)))
	var virality: float = 0.5 + _rng.next_float() * 1.5  # 0.5..2.0
	var reach: float = clampf(infl * coeff * virality, 0.0, 1.0)
	var tier: String = tier_of(reach)
	var tier_idx: int = int(TIER_INDEX.get(tier, 1))

	var likes: int = int(round(reach * float(f) * 0.5))
	var followers_delta: int = int(round(reach * 20.0)) - int(round((1.0 - reach) * 2.0))
	add_followers(author_id, platform_id, followers_delta)

	var doxxed: bool = false
	if anonymity:
		doxxed = _rng.next_float() < doxx_probability(valence, anonymity)
	var display_author: String = author_id
	if anonymity and not doxxed:
		display_author = "anonymous"

	var effects: Dictionary = _effects_for(valence, tier_idx, reach)
	if doxxed:
		effects["infamy"] = float(effects.get("infamy", 0.0)) + 2.0

	var post: Dictionary = {
		"id": "post.%d" % _seq,
		"author_id": author_id,
		"display_author": display_author,
		"platform": platform_id,
		"content": content,
		"valence": valence,
		"anonymity": anonymity,
		"doxxed": doxxed,
		"reach": reach,
		"tier": tier,
		"likes": likes,
		"followers_delta": followers_delta,
		"minute": int(opts.get("minute", 0)),
		"effects": effects,
	}
	_posts[post["id"]] = post
	return post


func tier_of(reach: float) -> String:
	if reach >= REACH_REGION:
		return "public"
	if reach >= REACH_CIRCLE:
		return "region"
	return "circle"


## 发言对声誉的效应（由调用方交给 ReputationSystem.apply_delta）。
func _effects_for(valence: float, tier_idx: int, reach: float) -> Dictionary:
	var magnitude: float = float(tier_idx) * absf(valence)
	if valence >= 0.0:
		return {"fame": magnitude, "status": magnitude * 0.5, "infamy": 0.0, "rumor": reach >= REACH_CIRCLE}
	return {"fame": 0.0, "status": 0.0, "infamy": magnitude, "rumor": reach >= REACH_CIRCLE}


## 小号被扒皮的概率：内容越有争议越高，匿名降低被直接认定的概率但不为零。
func doxx_probability(valence: float, anonymity: bool = true) -> float:
	var controversy: float = absf(clampf(valence, -1.0, 1.0))
	var base: float = 0.05 + 0.35 * controversy
	if not anonymity:
		return 1.0  # 本来实名，无需“扒皮”
	return clampf(base, 0.0, 1.0)


## 为一条扩散到区域及以上的发言生成传闻描述（交给 ReputationSystem.create_rumor）。
func as_rumor(post: Dictionary, subject_id: String) -> Dictionary:
	return {
		"subject_id": subject_id,
		"content": str(post.get("content", "")),
		"valence": float(post.get("valence", 0.0)),
		"credibility": 0.5 + 0.3 * float(post.get("reach", 0.0)),
		"circle": str(post.get("tier", "circle")),
		"minute": int(post.get("minute", 0)),
	}


func get_post(post_id: String) -> Dictionary:
	return _posts.get(post_id, {})


func post_count() -> int:
	return _posts.size()


## 最近动态（按发布顺序倒序），供动态流与面板装配。
func recent_posts(limit: int = 20) -> Array:
	var all: Array = _posts.values()
	var out: Array = []
	var start: int = maxi(0, all.size() - maxi(1, limit))
	for i in range(all.size() - 1, start - 1, -1):
		out.append((all[i] as Dictionary).duplicate(true))
	return out


func to_dict() -> Dictionary:
	return {
		"posts": _posts.duplicate(true),
		"followers": _followers.duplicate(true),
		"offline_queue": _offline_queue.duplicate(true),
		"threads": _threads.duplicate(true),
		"seq": _seq,
	}


func from_dict(data: Dictionary) -> void:
	if data.get("posts", null) is Dictionary:
		_posts = (data["posts"] as Dictionary).duplicate(true)
	if data.get("followers", null) is Dictionary:
		_followers = (data["followers"] as Dictionary).duplicate(true)
	if data.get("offline_queue", null) is Array:
		_offline_queue = (data["offline_queue"] as Array).duplicate(true)
	if data.get("threads", null) is Dictionary:
		_threads = (data["threads"] as Dictionary).duplicate(true)
	_seq = int(data.get("seq", 0))


# --- 私信（D10） ---

## 发送私信：写入对话线程，超长裁剪保留最近 200 条。
func send_direct(target_id: String, text: String, minute: int = 0, from_id: String = "player") -> Dictionary:
	var tid: String = target_id.strip_edges()
	if tid.is_empty():
		return {"ok": false, "reason": "unknown_target"}
	var content: String = text.strip_edges()
	if content.is_empty():
		return {"ok": false, "reason": "empty_message"}
	var list: Array = _threads.get(tid, [])
	list.append({"from": from_id, "to": tid, "text": content, "minute": minute, "read": true})
	if list.size() > 200:
		list = list.slice(list.size() - 200)
	_threads[tid] = list
	return {"ok": true, "target": tid, "message": {"from": from_id, "to": tid, "text": content, "minute": minute}}


## 接收私信：NPC 回复写入同一线程。
func receive_direct(target_id: String, text: String, minute: int = 0) -> Dictionary:
	var tid: String = target_id.strip_edges()
	if tid.is_empty():
		return {"ok": false, "reason": "unknown_target"}
	var list: Array = _threads.get(tid, [])
	list.append({"from": tid, "to": "player", "text": text.strip_edges(), "minute": minute, "read": false})
	_threads[tid] = list
	return {"ok": true, "target": tid}


## 单条对话线程。
func thread(target_id: String) -> Array:
	return (_threads.get(target_id, []) as Array).duplicate(true)


## 未读私信数。
func unread_count() -> int:
	var total: int = 0
	for tid in _threads.keys():
		for m in (_threads[tid] as Array):
			if not bool((m as Dictionary).get("read", true)) and String((m as Dictionary).get("to", "")) == "player":
				total += 1
	return total


## 最近私信摘要。
func recent_threads(limit: int = 5) -> Array:
	var out: Array = []
	for tid in _threads.keys():
		var list: Array = _threads[tid]
		if list.is_empty():
			continue
		var last: Dictionary = list[list.size() - 1]
		out.append({"target": String(tid), "last": String(last.get("text", "")),
			"minute": int(last.get("minute", 0)), "count": list.size()})
	out.sort_custom(func(a, b): return int(a.get("minute", 0)) > int(b.get("minute", 0)))
	if out.size() > limit:
		out = out.slice(0, limit)
	return out


# --- 断网离线队列（R50.10）---

func enqueue(action: Dictionary) -> void:
	_offline_queue.append(action.duplicate(true))


func pending_count() -> int:
	return _offline_queue.size()


func pending() -> Array:
	return _offline_queue.duplicate(true)


## 恢复联网后取回并清空队列。
func flush() -> Array:
	var out: Array = _offline_queue.duplicate(true)
	_offline_queue.clear()
	return out
