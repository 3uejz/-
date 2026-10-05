extends "res://tests/test_base.gd"
## 网络社交平台测试（任务 12；R50.3/R50.4/R50.10；design D10）。
## 覆盖：平台齐全、影响力、发言扩散与分层、声誉效应、匿名与扒皮、传闻描述、离线队列。

const SocialScript = preload("res://sim/social_network.gd")

func _suite_name() -> String:
	return "social_network"

func run_tests() -> void:
	_test_platforms()
	_test_influence()
	_test_publish()
	_test_influence_monotonic()
	_test_anonymity_and_doxx()
	_test_as_rumor()
	_test_offline_queue()


func _test_platforms() -> void:
	var sys = SocialScript.new()
	var ps: Array = sys.platforms()
	for need in ["im", "moments", "forum", "short_video", "livestream",
			"interest_group", "dating_job", "anonymous"]:
		check(ps.has(need), "平台存在: " + need)
	check(sys.has_platform("im"), "has_platform true")
	check(sys.is_anonymous_platform("anonymous"), "匿名平台标记")
	check(not sys.is_anonymous_platform("im"), "普通平台非匿名")


func _test_influence() -> void:
	var sys = SocialScript.new()
	check_near(sys.influence("a", "im"), 0.0, 0.0001, "零关注无影响力")
	sys.add_followers("a", "im", 10000)
	check_near(sys.influence("a", "im"), 1.0, 0.001, "万粉接近满影响力")
	check_eq(sys.followers("a", "im"), 10000, "关注数读取")
	sys.add_followers("a", "im", -99999)
	check_eq(sys.followers("a", "im"), 0, "关注数不为负")


func _test_publish() -> void:
	var sys = SocialScript.new(7)
	var post: Dictionary = sys.publish("a", "moments", "今天天气不错", {"valence": 0.5, "minute": 100})
	for key in ["id", "author_id", "platform", "content", "reach", "tier", "likes",
			"followers_delta", "effects", "display_author", "doxxed"]:
		check(post.has(key), "post 含字段: " + key)
	check(float(post["reach"]) >= 0.0 and float(post["reach"]) <= 1.0, "reach 有界")
	check(["circle", "region", "public"].has(str(post["tier"])), "tier 合法")
	check_eq(sys.tier_of(float(post["reach"])), str(post["tier"]), "tier 与 reach 一致")
	var effects: Dictionary = post["effects"]
	check(effects.has("fame") and effects.has("infamy"), "效应含声誉线")
	check_eq(sys.post_count(), 1, "帖子计数")


func _test_influence_monotonic() -> void:
	var low = SocialScript.new(42)
	var p_low: Dictionary = low.publish("a", "short_video", "x", {"influence": 0.1})
	var high = SocialScript.new(42)
	var p_high: Dictionary = high.publish("a", "short_video", "x", {"influence": 1.0})
	check(float(p_high["reach"]) > float(p_low["reach"]), "影响力越高扩散越广")


func _test_anonymity_and_doxx() -> void:
	var sys = SocialScript.new(3)
	var real: Dictionary = sys.publish("a", "im", "hi", {"anonymity": false})
	check_eq(str(real["display_author"]), "a", "实名显示作者")
	check(not bool(real["doxxed"]), "实名不存在扒皮")

	var anon: Dictionary = sys.publish("a", "forum", "爆料", {"anonymity": true, "valence": -0.9})
	check(bool(anon["anonymity"]), "匿名标记")
	check(str(anon["display_author"]) == "a" or str(anon["display_author"]) == "anonymous", "匿名显示为 anonymous 或被扒皮")

	check(sys.doxx_probability(0.0) < sys.doxx_probability(1.0), "争议越大越易被扒")
	check_near(sys.doxx_probability(0.5, false), 1.0, 0.0001, "实名无需扒皮")
	check(sys.doxx_probability(1.0) <= 1.0, "扒皮概率有上界")


func _test_as_rumor() -> void:
	var sys = SocialScript.new(1)
	var post: Dictionary = sys.publish("a", "short_video", "重大消息", {"valence": -0.8, "influence": 1.0})
	var rumor: Dictionary = sys.as_rumor(post, "a")
	check_eq(str(rumor["subject_id"]), "a", "传闻主体")
	check_near(float(rumor["valence"]), -0.8, 0.0001, "传闻情感")
	check(float(rumor["credibility"]) >= 0.5, "可信度随扩散提升")


func _test_offline_queue() -> void:
	var sys = SocialScript.new()
	check_eq(sys.pending_count(), 0, "初始队列空")
	sys.enqueue({"type": "post", "platform": "im"})
	sys.enqueue({"type": "like", "post": "x"})
	check_eq(sys.pending_count(), 2, "入队 2 条")
	var flushed: Array = sys.flush()
	check_eq(flushed.size(), 2, "同步取回 2 条")
	check_eq(sys.pending_count(), 0, "同步后清空")
