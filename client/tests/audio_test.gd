extends "res://tests/test_base.gd"
## 音频与音乐测试（任务 43；R99；design「音频与音乐」）。

const AudioScript = preload("res://sim/audio.gd")


func _suite_name() -> String:
	return "audio"


func run_tests() -> void:
	_test_volumes()
	_test_bgm_resolve()
	_test_bgm_transition()
	_test_sfx()
	_test_ambient()
	_test_assets_and_no_voice()
	_test_persistence()


func _test_volumes() -> void:
	var sys = AudioScript.new()
	var m: Dictionary = sys.new_mixer()
	check_eq(sys.CHANNELS.size(), 3 + 1, "四类通道")
	check(bool(sys.set_volume(m, "bgm", 0.5)["ok"]), "设置 BGM 音量")
	check_near(sys.volume_of(m, "bgm"), 0.5, 1e-6, "读取 BGM 音量")
	check_near(sys.volume_of(m, "master"), 1.0, 1e-6, "主音量默认满")
	sys.set_volume(m, "sfx", 2.0)
	check_near(sys.volume_of(m, "sfx"), 1.0, 1e-6, "音量上限钳制")
	sys.set_volume(m, "ambient", -1.0)
	check_near(sys.volume_of(m, "ambient"), 0.0, 1e-6, "音量下限钳制")
	check(not bool(sys.set_volume(m, "bogus", 0.5)["ok"]), "未知通道报错")
	check_near(sys.volume_db(m, "ambient"), -80.0, 1e-6, "静音转 dB")


func _test_bgm_resolve() -> void:
	var sys = AudioScript.new()
	check_eq(sys.resolve_bgm("city", "modern"), "bgm_city_modern", "城市现代 BGM")
	check_eq(sys.resolve_bgm("battle", "ancient"), "bgm_battle_ancient", "战斗古代 BGM")
	check_eq(sys.resolve_bgm("city", "unknown_era"), sys.BGM_DEFAULT, "未知时代回落默认")
	check_eq(sys.resolve_bgm("unknown_scene", "modern"), sys.BGM_DEFAULT, "未知场景回落默认")


func _test_bgm_transition() -> void:
	var sys = AudioScript.new()
	var m: Dictionary = sys.new_mixer()
	sys.play_bgm(m, "bgm_city_modern", 0.0)
	check(bool(sys.play_bgm(m, "bgm_city_modern", 0.0)["ok"]) == false, "同曲目不重触发")
	sys.play_bgm(m, "bgm_city_ancient", 2.0)
	var half: Dictionary = sys.tick(m, 1.0)
	check_eq(str(half["bgm_incoming"]), "bgm_city_ancient", "过渡目标为新城曲")
	check_near(float(half["bgm_incoming_gain"]), 0.5, 1e-6, "过渡过半新曲增益 0.5")
	var done: Dictionary = sys.tick(m, 1.0)
	check_eq(str(done["bgm_track"]), "bgm_city_ancient", "过渡完成切换 current")
	check_eq(str(done["bgm_incoming"]), "", "过渡完成清空 incoming")
	check_near(float(done["bgm_gain"]), 1.0, 1e-6, "过渡完成满增益")


func _test_sfx() -> void:
	var sys = AudioScript.new()
	var m: Dictionary = sys.new_mixer()
	var r: Dictionary = sys.play_sfx(m, "battle_hit")
	check(bool(r["ok"]), "播放战斗音效")
	check_eq(str(r["asset"]), "sfx_battle_hit", "音效资源 id")
	check(not bool(sys.play_sfx(m, "nope")["ok"]), "未知音效报错")


func _test_ambient() -> void:
	var sys = AudioScript.new()
	var layers: Dictionary = sys.resolve_ambient("city", "clear")
	var total: float = 0.0
	for w in layers.values():
		total += float(w)
	check_near(total, 1.0, 1e-6, "环境音权重归一化")
	var rainy: Dictionary = sys.resolve_ambient("city", "rain")
	check(rainy.has("amb_rain"), "雨天叠加雨声")
	check(float(rainy["amb_rain"]) > float(rainy.get("amb_city_traffic", 0.0)), "雨声权重提升")
	var m: Dictionary = sys.new_mixer()
	sys.set_ambient(m, "wilderness", "wind")
	sys.tick(m, 1.0)
	var state: Dictionary = sys.tick(m, 0.5)
	check(float(state["ambient_blend"]) >= 1.0, "环境音混合推进至完成")
	check((state["ambient"] as Dictionary).size() > 0, "环境音当前层非空")


func _test_assets_and_no_voice() -> void:
	var sys = AudioScript.new()
	var assets: Array = sys.audio_assets()
	check(assets.size() >= 10, "音频资源表非空")
	var uniq: Dictionary = {}
	for a in assets:
		uniq[a] = true
	check_eq(uniq.size(), assets.size(), "资源 id 去重")
	var manifest: Dictionary = sys.content_pack_manifest("audio_core")
	check_eq(str(manifest["kind"]), "audio", "内容包类型")
	check(bool(manifest["voice"]) == false, "明确不含语音")


func _test_persistence() -> void:
	var sys = AudioScript.new()
	var m: Dictionary = sys.new_mixer()
	sys.set_volume(m, "bgm", 0.33)
	sys.set_ambient(m, "home", "fog")
	var clone: Dictionary = sys.from_dict(sys.to_dict(m))
	check_near(sys.volume_of(clone, "bgm"), 0.33, 1e-6, "音量序列化往返")
	check_eq((clone["ambient"]["target"] as Dictionary).size(), (m["ambient"]["target"] as Dictionary).size(), "环境音序列化往返")
