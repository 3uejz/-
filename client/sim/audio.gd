class_name AudioSystem
extends RefCounted
## 音频与音乐（R99；design「音频与音乐」）。
##
## 纯逻辑模型：BGM 按场景与时代分组解析、淡入淡出/交叉过渡；动作/战斗/UI/事件音效；
## 环境音按地点与天气分层动态混合；三类通道（bgm/sfx/ambient）与主音量可独立设置。
## 明确不含语音。资源以逻辑 id 引用，纳入内容包差量体系（content_pack_manifest）。
## 运行时 AudioDirector（任务 23/47）据此模型驱动 AudioStreamPlayer。

const CHANNELS: Array = ["master", "bgm", "sfx", "ambient"]

const BGM_TABLE: Dictionary = {
	"city": {"ancient": "bgm_city_ancient", "modern": "bgm_city_modern", "future": "bgm_city_future"},
	"wilderness": {"ancient": "bgm_wild_ancient", "modern": "bgm_wild_modern", "future": "bgm_wild_future"},
	"home": {"ancient": "bgm_home_ancient", "modern": "bgm_home_modern", "future": "bgm_home_future"},
	"battle": {"ancient": "bgm_battle_ancient", "modern": "bgm_battle_modern", "future": "bgm_battle_future"},
}
const BGM_DEFAULT: String = "bgm_default"

const SFX_TABLE: Dictionary = {
	"ui_click": "sfx_ui_click", "ui_confirm": "sfx_ui_confirm", "ui_cancel": "sfx_ui_cancel",
	"action": "sfx_action", "battle_hit": "sfx_battle_hit", "battle_win": "sfx_battle_win",
	"battle_lose": "sfx_battle_lose", "event_alert": "sfx_event_alert", "item_get": "sfx_item_get",
}

const AMBIENT_TABLE: Dictionary = {
	"city": {"amb_city_traffic": 0.6, "amb_crowd": 0.4},
	"wilderness": {"amb_wind": 0.5, "amb_birds": 0.3, "amb_leaves": 0.4},
	"home": {"amb_room_tone": 0.5},
	"water": {"amb_water": 0.7, "amb_wind": 0.2},
}
const WEATHER_LAYERS: Dictionary = {
	"rain": {"amb_rain": 0.8}, "storm": {"amb_rain": 1.0, "amb_thunder": 0.6},
	"wind": {"amb_wind": 0.7}, "snow": {"amb_wind": 0.4, "amb_snow": 0.5},
	"clear": {}, "fog": {"amb_fog": 0.3},
}

const DEFAULT_VOLUMES: Dictionary = {"master": 1.0, "bgm": 0.8, "sfx": 0.9, "ambient": 0.7}


func new_mixer() -> Dictionary:
	return {
		"volumes": DEFAULT_VOLUMES.duplicate(),
		"bgm": {"current": "", "incoming": "", "fade_total": 0.0, "fade_remaining": 0.0, "gain": 0.0},
		"ambient": {"current": {}, "target": {}, "blend": 0.0},
	}


func set_volume(mixer: Dictionary, channel: String, value: float) -> Dictionary:
	if not CHANNELS.has(channel):
		return {"ok": false, "reason": "unknown_channel"}
	(mixer["volumes"] as Dictionary)[channel] = clampf(value, 0.0, 1.0)
	return {"ok": true, "channel": channel, "value": float((mixer["volumes"] as Dictionary)[channel])}


func volume_of(mixer: Dictionary, channel: String) -> float:
	return float((mixer["volumes"] as Dictionary).get(channel, 1.0))


func volume_db(mixer: Dictionary, channel: String) -> float:
	var v: float = volume_of(mixer, channel)
	if v <= 0.0:
		return -80.0
	return linear_to_db(v)


# --- BGM ---

## 按场景与时代解析 BGM；缺省回落到场景→默认，绝不返回空。
func resolve_bgm(scene: String, era: String) -> String:
	if BGM_TABLE.has(scene):
		var by_era: Dictionary = BGM_TABLE[scene]
		if by_era.has(era):
			return str(by_era[era])
	return BGM_DEFAULT


## 切换 BGM；支持淡入淡出/交叉过渡（fade<=0 立即切换）。同一曲目不重触发。
func play_bgm(mixer: Dictionary, track: String, fade: float = 0.0) -> Dictionary:
	var bgm: Dictionary = mixer["bgm"]
	if track == "" or track == str(bgm["current"]) and str(bgm["incoming"]) == "":
		return {"ok": false, "reason": "same_track"}
	if fade <= 0.0:
		bgm["current"] = track
		bgm["incoming"] = ""
		bgm["fade_total"] = 0.0
		bgm["fade_remaining"] = 0.0
		bgm["gain"] = 1.0
		return {"ok": true, "immediate": true, "track": track}
	bgm["incoming"] = track
	bgm["fade_total"] = fade
	bgm["fade_remaining"] = fade
	return {"ok": true, "immediate": false, "track": track, "fade": fade}


# --- 音效 ---

func play_sfx(mixer: Dictionary, sfx_id: String) -> Dictionary:
	if not SFX_TABLE.has(sfx_id):
		return {"ok": false, "reason": "unknown_sfx"}
	return {"ok": true, "asset": SFX_TABLE[sfx_id], "volume": volume_of(mixer, "sfx")}


# --- 环境音 ---

## 按地点与天气解析分层环境音，权重归一化。
func resolve_ambient(location: String, weather: String) -> Dictionary:
	var layers: Dictionary = {}
	for k in (AMBIENT_TABLE.get(location, {}) as Dictionary):
		layers[k] = float(AMBIENT_TABLE[location][k])
	for k in (WEATHER_LAYERS.get(weather, {}) as Dictionary):
		layers[k] = float(layers.get(k, 0.0)) + float(WEATHER_LAYERS[weather][k])
	var total: float = 0.0
	for w in layers.values():
		total += float(w)
	if total > 0.0:
		for k in layers.keys():
			layers[k] = float(layers[k]) / total
	return layers


## 设定目标环境音混合（随时间在 tick 中平滑逼近）。
func set_ambient(mixer: Dictionary, location: String, weather: String) -> Dictionary:
	(mixer["ambient"] as Dictionary)["target"] = resolve_ambient(location, weather)
	(mixer["ambient"] as Dictionary)["blend"] = 0.0
	return {"ok": true, "target": (mixer["ambient"] as Dictionary)["target"]}


# --- 时间推进 ---

## 推进淡入淡出与环境音混合；返回当前各通道实时增益供播放器使用。
func tick(mixer: Dictionary, dt: float) -> Dictionary:
	var bgm: Dictionary = mixer["bgm"]
	if str(bgm["incoming"]) != "" and float(bgm["fade_remaining"]) > 0.0:
		bgm["fade_remaining"] = maxf(0.0, float(bgm["fade_remaining"]) - dt)
		if float(bgm["fade_remaining"]) <= 0.0:
			bgm["current"] = bgm["incoming"]
			bgm["incoming"] = ""
			bgm["gain"] = 1.0
	var ambient: Dictionary = mixer["ambient"]
	ambient["blend"] = minf(1.0, float(ambient["blend"]) + dt)
	if float(ambient["blend"]) >= 1.0:
		ambient["current"] = (ambient["target"] as Dictionary).duplicate()
	return {
		"bgm_track": str(bgm["current"]), "bgm_gain": float(bgm["gain"]),
		"bgm_incoming": str(bgm["incoming"]),
		"bgm_incoming_gain": (1.0 - float(bgm["fade_remaining"]) / float(bgm["fade_total"])) if str(bgm["incoming"]) != "" and float(bgm["fade_total"]) > 0.0 else 0.0,
		"ambient": (ambient["current"] as Dictionary).duplicate(),
		"ambient_blend": float(ambient["blend"]),
	}


# --- 内容包差量 ---

## 本系统引用的全部音频逻辑 id（供内容包打包/校验）。
func audio_assets() -> Array:
	var out: Array = [BGM_DEFAULT]
	for by_era in BGM_TABLE.values():
		for asset in (by_era as Dictionary).values():
			if not out.has(asset):
				out.append(asset)
	for asset in SFX_TABLE.values():
		if not out.has(asset):
			out.append(asset)
	for tbl in [AMBIENT_TABLE, WEATHER_LAYERS]:
		for layers in tbl.values():
			for asset in (layers as Dictionary).keys():
				if not out.has(asset):
					out.append(asset)
	return out


## 内容包清单片段：明确无语音（R99.4）。
func content_pack_manifest(pack_id: String) -> Dictionary:
	return {"pack_id": pack_id, "kind": "audio", "voice": false, "assets": audio_assets()}


func to_dict(mixer: Dictionary) -> Dictionary:
	return mixer.duplicate(true)


func from_dict(data: Dictionary) -> Dictionary:
	var mixer: Dictionary = new_mixer()
	for ch in CHANNELS:
		if (data.get("volumes", {}) as Dictionary).has(ch):
			(mixer["volumes"] as Dictionary)[ch] = float(data["volumes"][ch])
	if data.has("bgm"):
		mixer["bgm"] = (data["bgm"] as Dictionary).duplicate(true)
	if data.has("ambient"):
		mixer["ambient"] = (data["ambient"] as Dictionary).duplicate(true)
	return mixer
