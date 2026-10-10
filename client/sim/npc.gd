class_name NpcSystem
extends RefCounted
## NPC 个体生成与生命周期（R18、R50；design「NPC 生成与区域模拟」三级 LOD）。
##
## 全人口由世界种子确定性生成，可随时按索引重建（Tier 2）；
## 与玩家产生关系的 NPC 调用 individualize() 永久个体化（Tier 0），不随 LOD 降级。
## 本类只负责个体模型，不直接依赖 Autoload；区域批量人口由 RegionManager 接入。

const RngScript = preload("res://sim/rng.gd")
const BaselineScript = preload("res://sim/baseline.gd")
const GregorianScript = preload("res://sim/gregorian.gd")

const MINUTES_PER_YEAR: float = 365.25 * 1440.0
const MASK: int = BaselineScript.NPC_MASK

## 生命阶段。
const STAGE_CHILD: String = "child"
const STAGE_STUDENT: String = "student"
const STAGE_ADULT: String = "adult"
const STAGE_SENIOR: String = "senior"

const SURNAMES: Array = [
	"王", "李", "张", "刘", "陈", "杨", "赵", "黄", "周", "吴",
	"徐", "孙", "胡", "朱", "高", "林", "何", "郭", "马", "罗",
	"梁", "宋", "郑", "谢", "韩", "唐", "冯", "于", "董", "萧",
]
const GIVEN_MALE: Array = [
	"伟", "强", "磊", "军", "洋", "勇", "杰", "涛", "明", "超",
	"鹏", "华", "毅", "浩", "宇", "航", "晨", "睿", "轩", "博",
	"文", "武", "斌", "峰", "亮", "刚", "健", "龙", "凯", "翔",
]
const GIVEN_FEMALE: Array = [
	"芳", "娜", "敏", "静", "丽", "娟", "艳", "霞", "婷", "雪",
	"琳", "颖", "倩", "悦", "欣", "怡", "彤", "茜", "妍", "蕾",
	"梅", "兰", "菊", "荷", "月", "薇", "瑶", "萱", "晴", "柔",
]
const GIVEN_NEUTRAL: Array = [
	"清", "云", "风", "岚", "川", "野", "一", "平", "安", "宁",
]

const TRAITS: Array = [
	"温和", "急躁", "节俭", "慷慨", "乐观", "悲观", "勤奋", "懒散",
	"谨慎", "冒险", "内向", "外向", "固执", "随和", "诚实", "狡黠",
	"浪漫", "务实", "忠诚", "多疑", "自律", "散漫", "幽默", "严肃",
]

## 成年职业池（内容键）。
const ADULT_JOBS: Array = [
	"job.teacher", "job.doctor", "job.engineer", "job.shopkeeper", "job.farmer",
	"job.driver", "job.cook", "job.clerk", "job.nurse", "job.police",
	"job.soldier", "job.programmer", "job.waiter", "job.worker", "job.artist",
	"job.accountant", "job.journalist", "job.lawyer",
]

const STAGE_JOB: Dictionary = {
	"child": "", "student": "job.student", "adult": "", "senior": "",
}

## 年龄分带权重：[0,14]/[15,29]/[30,49]/[50,64]/[65,100]。
const AGE_BANDS: Array = [[0, 14, 0.18], [15, 29, 0.22], [30, 49, 0.30], [50, 64, 0.18], [65, 100, 0.12]]

var _rng = null


# --- 生成 ---

## 生成第 index 个 NPC。opts:
##   world_seed、region_id、now_minute（默认 0）、individualized（默认 false）、
##   lod_tier（默认 2）、age（覆盖年龄）、gender（覆盖性别）。
func generate(index: int, opts: Dictionary = {}) -> Dictionary:
	var world_seed: int = int(opts.get("world_seed", 0))
	var region_id: String = str(opts.get("region_id", "region.default"))
	var now: int = int(opts.get("now_minute", 0))
	_rng = RngScript.new(_mix_seed(world_seed, region_id, index))

	var gender: String = str(opts.get("gender", _sample_gender()))
	var age: int = int(opts.get("age", _sample_age()))
	var birth: int = now - int(round(float(age) * MINUTES_PER_YEAR))
	var stage: String = life_stage(age)
	var name: String = _make_name(gender)
	var job: String = _pick_job(stage, age)
	var home_key: String = "loc.%s.residence" % region_id

	var npc: Dictionary = {
		"id": _uuid(),
		"name": name,
		"gender": gender,
		"birth_minutes": birth,
		"alive": true,
		"job": job,
		"traits": _pick_traits(),
		"attributes": _make_attributes(age),
		"home": {"region_id": region_id, "location_key": home_key},
		"schedule": default_schedule(stage, age, region_id),
		"relations": [],
		"individualized": bool(opts.get("individualized", false)),
		"lod_tier": int(opts.get("lod_tier", 2)),
	}
	return npc


## 批量生成同区域人口（Tier 0 活动区或按需重建）。
func generate_cohort(count: int, opts: Dictionary = {}) -> Array:
	var out: Array = []
	for i in maxi(0, count):
		out.append(generate(i, opts))
	return out


func _mix_seed(world_seed: int, region_id: String, index: int) -> int:
	var h: int = int(region_id.hash()) & 0xFFFFFFFF
	return (world_seed + h * 2654435761 + index * 40503) & MASK


# --- 抽样 ---

func _sample_gender() -> String:
	var r: float = _rng.next_float()
	if r < 0.49:
		return "male"
	if r < 0.98:
		return "female"
	if r < 0.99:
		return "nonbinary"
	return "other"


func _sample_age() -> int:
	var r: float = _rng.next_float()
	var acc: float = 0.0
	for band in AGE_BANDS:
		acc += float(band[2])
		if r < acc:
			var lo: int = int(band[0])
			var hi: int = int(band[1])
			return lo + int(_rng.next_float() * float(hi - lo + 1))
	return 30


func _pick(pool: Array) -> String:
	if pool.is_empty():
		return ""
	return str(pool[mini(pool.size() - 1, int(_rng.next_float() * float(pool.size())))])


func _make_name(gender: String) -> String:
	var surname: String = _pick(SURNAMES)
	var given: String
	if gender == "male":
		given = _pick(GIVEN_MALE)
	elif gender == "female":
		given = _pick(GIVEN_FEMALE)
	else:
		given = _pick(GIVEN_NEUTRAL) if _rng.next_float() < 0.5 else _pick(GIVEN_MALE)
	return surname + given


func _pick_traits() -> Array:
	var n: int = 3 + int(_rng.next_float() * 3.0)  # 3..5
	var out: Array = []
	var guard: int = 0
	while out.size() < n and guard < 40:
		guard += 1
		var t: String = _pick(TRAITS)
		if not out.has(t):
			out.append(t)
	return out


func _pick_job(stage: String, age: int) -> String:
	if stage == STAGE_CHILD or stage == STAGE_SENIOR:
		return ""
	if stage == STAGE_STUDENT:
		return "job.student"
	# 成年：少数仍在校或失业。
	var r: float = _rng.next_float()
	if r < 0.05 and age < 26:
		return "job.student"
	if r < 0.08:
		return ""
	return _pick(ADULT_JOBS)


func _score() -> float:
	return 5.0 + _rng.next_float() * 90.0


func _make_attributes(age: int) -> Dictionary:
	var ability_scale: float = clampf(float(age) / 18.0, 0.3, 1.0)
	var decline: float = maxf(0.0, float(age - 30)) * 0.4
	return {
		"physiological": {
			"health": _bound(_score() - decline),
			"stamina": _bound(_score() - decline),
			"hunger": 20.0 + _rng.next_float() * 30.0,
			"thirst": 20.0 + _rng.next_float() * 30.0,
			"cleanliness": _bound(_score()),
			"sleep_debt": _rng.next_float() * 30.0,
		},
		"nutrition": {
			"protein": _bound(_score()), "carbs": _bound(_score()), "fat": _bound(_score()),
			"vitamins": _bound(_score()), "minerals": _bound(_score()),
		},
		"psychological": {
			"mood": _bound(_score()), "stress": _rng.next_float() * 50.0,
			"happiness": _bound(_score()), "meaning": _bound(_score()),
		},
		"ability": {
			"intelligence": _bound(_score() * ability_scale + 10.0),
			"charm": _bound(_score() * ability_scale),
			"physique": _bound(_score() * ability_scale - maxf(0.0, float(age - 40)) * 0.5),
			"willpower": _bound(_score()),
			"luck": _bound(_score()),
		},
		"personality": {
			"openness": _bound(_score()), "conscientiousness": _bound(_score()),
			"extraversion": _bound(_score()), "agreeableness": _bound(_score()),
			"neuroticism": _bound(_score()),
		},
		"values": {
			"selfish_altruistic": _bound(_score()),
			"conservative_open": _bound(_score()),
			"material_spiritual": _bound(_score()),
		},
	}


static func _bound(value: float) -> float:
	return clampf(value, 0.0, 100.0)


# --- 年龄与阶段 ---

func age_years(npc: Dictionary, now_minute: int) -> float:
	var birth: int = int(npc.get("birth_minutes", 0))
	if not bool(npc.get("alive", true)):
		var death: int = int(npc.get("death_minutes", now_minute))
		return maxf(0.0, float(death - birth) / MINUTES_PER_YEAR)
	return maxf(0.0, float(now_minute - birth) / MINUTES_PER_YEAR)


func life_stage(age: int) -> String:
	if age < 6:
		return STAGE_CHILD
	if age < 23:
		return STAGE_STUDENT
	if age < 65:
		return STAGE_ADULT
	return STAGE_SENIOR


# --- 日程 ---

## 活动 → 地点类型（生成 location_key 用）。
const ACTIVITY_LOCATION: Dictionary = {
	"sleep": "home", "breakfast": "home", "dinner": "home", "leisure": "home",
	"play": "home", "nap": "home", "housework": "home",
	"exercise": "public", "social": "public",
	"work": "workplace", "school": "school", "study": "school",
	"lunch": "restaurant", "commute": "transit",
}

## 生成日程片段（start/end 分钟-of-day，activity，可选 location_key）。
## 传入 region_id 时为每段补上地点键，体现“按时间段驱动位置与行为”。
func default_schedule(stage: String, _age: int = 0, region_id: String = "") -> Array:
	match stage:
		STAGE_CHILD:
			return _sched_child(region_id)
		STAGE_STUDENT:
			return _sched_student(region_id)
		STAGE_SENIOR:
			return _sched_senior(region_id)
		_:
			return _sched_worker(region_id)


func _location_for(activity: String, region_id: String) -> String:
	if region_id == "":
		return ""
	var kind: String = str(ACTIVITY_LOCATION.get(activity, "public"))
	return "loc.%s.%s" % [region_id, kind]


func _seg(start: int, end: int, activity: String, region_id: String = "") -> Dictionary:
	var seg: Dictionary = {
		"start_minute_of_day": start, "end_minute_of_day": end, "activity": activity,
	}
	var loc: String = _location_for(activity, region_id)
	if loc != "":
		seg["location_key"] = loc
	return seg


func _sched_worker(region_id: String = "") -> Array:
	return [
		_seg(0, 390, "sleep", region_id), _seg(390, 450, "breakfast", region_id),
		_seg(450, 540, "commute", region_id), _seg(540, 720, "work", region_id),
		_seg(720, 780, "lunch", region_id), _seg(780, 1080, "work", region_id),
		_seg(1080, 1140, "commute", region_id), _seg(1140, 1200, "dinner", region_id),
		_seg(1200, 1320, "leisure", region_id), _seg(1320, 1440, "sleep", region_id),
	]


func _sched_student(region_id: String = "") -> Array:
	return [
		_seg(0, 420, "sleep", region_id), _seg(420, 480, "breakfast", region_id),
		_seg(480, 720, "school", region_id), _seg(720, 780, "lunch", region_id),
		_seg(780, 1020, "school", region_id), _seg(1020, 1140, "study", region_id),
		_seg(1140, 1200, "dinner", region_id), _seg(1200, 1320, "leisure", region_id),
		_seg(1320, 1440, "sleep", region_id),
	]


func _sched_child(region_id: String = "") -> Array:
	return [
		_seg(0, 420, "sleep", region_id), _seg(420, 480, "breakfast", region_id),
		_seg(480, 720, "play", region_id), _seg(720, 780, "lunch", region_id),
		_seg(780, 900, "nap", region_id), _seg(900, 1140, "play", region_id),
		_seg(1140, 1200, "dinner", region_id), _seg(1200, 1290, "leisure", region_id),
		_seg(1290, 1440, "sleep", region_id),
	]


func _sched_senior(region_id: String = "") -> Array:
	return [
		_seg(0, 420, "sleep", region_id), _seg(420, 480, "breakfast", region_id),
		_seg(480, 600, "exercise", region_id), _seg(600, 720, "leisure", region_id),
		_seg(720, 780, "lunch", region_id), _seg(780, 900, "nap", region_id),
		_seg(900, 1080, "social", region_id), _seg(1080, 1140, "housework", region_id),
		_seg(1140, 1200, "dinner", region_id), _seg(1200, 1290, "leisure", region_id),
		_seg(1290, 1440, "sleep", region_id),
	]


## 某分钟-of-day 的活动；无匹配返回 {}。
func activity_at(npc: Dictionary, minute_of_day: int) -> Dictionary:
	var m: int = posmod(minute_of_day, GregorianScript.MINUTES_PER_DAY)
	for entry in npc.get("schedule", []):
		var start: int = int(entry.get("start_minute_of_day", 0))
		var end: int = int(entry.get("end_minute_of_day", 0))
		if m >= start and m < end:
			return entry
	return {}


# --- 个体化与 LOD ---

## 与玩家产生关系后永久个体化：不再随 LOD 降级重建。
func individualize(npc: Dictionary) -> Dictionary:
	npc["individualized"] = true
	npc["lod_tier"] = 0
	return npc


## 设置 LOD 层级；个体化 NPC 恒为 Tier 0。
func set_lod(npc: Dictionary, tier: int) -> Dictionary:
	if bool(npc.get("individualized", false)):
		npc["lod_tier"] = 0
	else:
		npc["lod_tier"] = clampi(tier, 0, 2)
	return npc


func is_individualized(npc: Dictionary) -> bool:
	return bool(npc.get("individualized", false))


# --- 生命周期事件 ---

## 应用生命事件。支持 death / migrate / change_job / illness / recover。
## 返回 {ok, type}；未知事件返回 ok=false。
func apply_life_event(npc: Dictionary, event: String, opts: Dictionary = {}) -> Dictionary:
	match event:
		"death":
			if not bool(npc.get("alive", true)):
				return {"ok": false, "type": event, "reason": "already_dead"}
			npc["alive"] = false
			npc["death_minutes"] = int(opts.get("minute", 0))
			return {"ok": true, "type": event}
		"migrate":
			var home: Dictionary = npc.get("home", {})
			home["region_id"] = str(opts.get("region_id", home.get("region_id", "")))
			if opts.has("location_key"):
				home["location_key"] = str(opts["location_key"])
			npc["home"] = home
			return {"ok": true, "type": event}
		"change_job":
			npc["job"] = str(opts.get("job", ""))
			return {"ok": true, "type": event}
		"illness":
			var phys: Dictionary = npc["attributes"]["physiological"]
			phys["health"] = clampf(float(phys.get("health", 50.0)) - float(opts.get("severity", 20.0)), 0.0, 100.0)
			return {"ok": true, "type": event}
		"recover":
			var phys2: Dictionary = npc["attributes"]["physiological"]
			phys2["health"] = clampf(float(phys2.get("health", 50.0)) + float(opts.get("amount", 20.0)), 0.0, 100.0)
			return {"ok": true, "type": event}
		_:
			return {"ok": false, "type": event, "reason": "unknown_event"}


# --- 工具 ---

## 生成确定性 UUID（16 字节，8-4-4-4-12 十六进制）。
func _uuid() -> String:
	var hex: String = ""
	const DIGITS: String = "0123456789abcdef"
	for _i in 32:
		hex += DIGITS[int(_rng.next_float() * 16.0) % 16]
	return "%s-%s-%s-%s-%s" % [
		hex.substr(0, 8), hex.substr(8, 4), hex.substr(12, 4),
		hex.substr(16, 4), hex.substr(20, 12),
	]
