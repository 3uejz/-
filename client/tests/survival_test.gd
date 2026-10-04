extends "res://tests/test_base.gd"
## 生理生存、营养、成瘾与死亡测试（任务 7.1）。
## 覆盖：六项生理衰减与速率、营养有界/进食/失衡、成瘾 craving 与戒断、健康归零死亡与死亡冻结、
## 临终状态与动词门控、遗嘱形式与人生总结、远程配置覆盖与边界 clamp。

const SurvivalScript = preload("res://sim/survival.gd")
const BaselineScript = preload("res://sim/baseline.gd")
const GameStateScript = preload("res://autoload/game_state.gd")

func _suite_name() -> String:
	return "survival"

func run_tests() -> void:
	_test_physiological_decay_rates()
	_test_starvation_dehydration_health()
	_test_sleep_debt_threshold()
	_test_nutrition_decay_and_bounds()
	_test_eat_nutrition_first()
	_test_nutrition_imbalance_and_excess()
	_test_addiction_craving_and_stages()
	_test_addiction_withdrawal()
	_test_addiction_treatment_and_relapse()
	_test_death_and_freeze()
	_test_dying_state_and_verbs()
	_test_will_forms_and_life_summary()
	_test_lifespan_estimate()
	_test_remote_config_and_clamp()
	_test_state_roundtrip()


func _new_player() -> Dictionary:
	return GameStateScript.default_player()


# --- 1. 六项生理衰减速率 ---

func _test_physiological_decay_rates() -> void:
	var s = SurvivalScript.new(1)
	var player := _new_player()
	s.decay_physiological(player, 60, {"asleep": false, "labor_intensity": 0.0, "age_years": 25.0})
	var p: Dictionary = player["attrs"]["physiological"]
	check_near(float(p["hunger"]), 100.0 - BaselineScript.HUNGER_DECAY_PER_MIN * 60.0, 1e-6, "饱食按 −0.21/分钟衰减")
	check_near(float(p["thirst"]), 100.0 - BaselineScript.THIRST_DECAY_PER_MIN * 60.0, 1e-6, "口渴按 −0.42/分钟衰减")
	check_near(float(p["cleanliness"]), 100.0 - BaselineScript.CLEANLINESS_DECAY_PER_MIN * 60.0, 1e-6, "清洁衰减")
	check_near(float(p["sleep_debt"]), BaselineScript.SLEEP_DEBT_GAIN_PER_HOUR, 1e-6, "清醒睡眠债累积")
	check_near(float(p["stamina"]), 100.0, 1e-6, "体力静息恢复到上限并 clamp")

	# 8 小时清空饱食、4 小时清空口渴（design 标定）。
	var player2 := _new_player()
	s.decay_physiological(player2, 240, {"asleep": false, "age_years": 25.0})
	var p2: Dictionary = player2["attrs"]["physiological"]
	check_near(float(p2["thirst"]), 0.0, 1e-6, "口渴约 4 游戏小时清空")
	check(float(p2["hunger"]) > 0.0, "4 小时时饱食尚未清空")

	# 睡眠恢复睡眠债、体力。
	var player3 := _new_player()
	player3["attrs"]["physiological"]["sleep_debt"] = 30.0
	player3["attrs"]["physiological"]["stamina"] = 20.0
	s.decay_physiological(player3, 60, {"asleep": true, "age_years": 25.0})
	var p3: Dictionary = player3["attrs"]["physiological"]
	check_near(float(p3["sleep_debt"]), 30.0 - BaselineScript.SLEEP_DEBT_RECOVER_PER_HOUR, 1e-6, "睡眠恢复睡眠债")
	check_near(float(p3["stamina"]), 20.0 + BaselineScript.STAMINA_REGEN_ASLEEP_PER_HOUR, 1e-6, "睡眠恢复体力")


# --- 2. 饥渴扣血：口渴高于饥饿 ---

func _test_starvation_dehydration_health() -> void:
	var s = SurvivalScript.new(2)
	var starving := _new_player()
	starving["attrs"]["physiological"]["hunger"] = 0.0
	starving["attrs"]["physiological"]["health"] = 50.0
	s.decay_physiological(starving, 60, {"age_years": 25.0})
	check_near(float(starving["attrs"]["physiological"]["health"]), 50.0 - BaselineScript.STARVE_HEALTH_PER_HOUR, 1e-6, "饥饿归零扣血")

	var dehydrated := _new_player()
	dehydrated["attrs"]["physiological"]["thirst"] = 0.0
	dehydrated["attrs"]["physiological"]["health"] = 50.0
	s.decay_physiological(dehydrated, 60, {"age_years": 25.0})
	var dh: float = float(dehydrated["attrs"]["physiological"]["health"])
	check_near(dh, 50.0 - BaselineScript.DEHYDRATE_HEALTH_PER_HOUR, 1e-6, "口渴归零扣血")
	check((50.0 - dh) > (50.0 - float(starving["attrs"]["physiological"]["health"])), "口渴扣血快于饥饿")

	# 温饱时随年龄递减恢复。
	var healing := _new_player()
	healing["attrs"]["physiological"]["hunger"] = 80.0
	healing["attrs"]["physiological"]["thirst"] = 80.0
	healing["attrs"]["physiological"]["health"] = 50.0
	s.decay_physiological(healing, 60, {"age_years": 25.0})
	check(float(healing["attrs"]["physiological"]["health"]) > 50.0, "温饱时健康缓慢恢复")


# --- 3. 睡眠债超阈降低智力与心情 ---

func _test_sleep_debt_threshold() -> void:
	var s = SurvivalScript.new(3)
	var player := _new_player()
	var p: Dictionary = player["attrs"]["physiological"]
	p["sleep_debt"] = BaselineScript.SLEEP_DEBT_THRESHOLD + 10.0
	var before_int: float = float(player["attrs"]["ability"]["intelligence"])
	var before_mood: float = float(player["attrs"]["psychological"]["mood"])
	s.decay_physiological(player, 60, {"asleep": false, "age_years": 25.0})
	check(float(player["attrs"]["ability"]["intelligence"]) < before_int, "睡眠债超阈降低智力")
	check(float(player["attrs"]["psychological"]["mood"]) < before_mood, "睡眠债超阈降低心情")

	# 睡眠充足时心情缓慢恢复。
	var rested := _new_player()
	rested["attrs"]["physiological"]["sleep_debt"] = 0.0
	rested["attrs"]["psychological"]["mood"] = 50.0
	s.decay_physiological(rested, 60, {"asleep": true, "age_years": 25.0})
	check(float(rested["attrs"]["psychological"]["mood"]) > 50.0, "睡眠充足心情恢复")


# --- 4. 营养每日衰减与有界 ---

func _test_nutrition_decay_and_bounds() -> void:
	var s = SurvivalScript.new(4)
	var player := _new_player()
	for key in SurvivalScript.NUTRIENTS:
		player["attrs"]["nutrition"][key] = 50.0
	s.update_nutrition(player, 1.0, {"age_years": 20.0})
	for key in SurvivalScript.NUTRIENTS:
		var decay: float = float(BaselineScript.NUTRITION_DECAY_PER_DAY[key])
		check_near(float(player["attrs"]["nutrition"][key]), 50.0 - decay, 1e-6, "营养 %s 每日衰减" % key)

	# 有界：长期衰减不会低于 0，过量进食不会高于 100。
	var player2 := _new_player()
	player2["attrs"]["nutrition"]["protein"] = 1.0
	s.update_nutrition(player2, 10.0, {"age_years": 20.0})
	check(float(player2["attrs"]["nutrition"]["protein"]) >= 0.0, "营养下界 clamp 到 0")
	s.eat(player2, {"protein": 999.0, "satiety": 0.0})
	check_near(float(player2["attrs"]["nutrition"]["protein"]), 100.0, 1e-6, "营养上界 clamp 到 100")


# --- 5. 进食：先营养后饱食，超量为过量 ---

func _test_eat_nutrition_first() -> void:
	var s = SurvivalScript.new(5)
	var player := _new_player()
	for key in SurvivalScript.NUTRIENTS:
		player["attrs"]["nutrition"][key] = 90.0
	player["attrs"]["physiological"]["hunger"] = 50.0
	var report: Dictionary = s.eat(player, {"protein": 20.0, "carbs": 5.0, "satiety": 30.0})
	check(bool(report["applied"]), "进食成功")
	check_near(float(player["attrs"]["nutrition"]["protein"]), 100.0, 1e-6, "营养储备封顶")
	check_near(float(report["over"]["protein"]), 10.0, 1e-6, "超出储量计为过量")
	check_near(float(player["attrs"]["nutrition"]["carbs"]), 95.0, 1e-6, "未超部分正常补充")
	check_near(float(player["attrs"]["physiological"]["hunger"]), 80.0, 1e-6, "补足营养后补饱食")
	check_near(float(report["satiety_added"]), 30.0, 1e-6, "饱食增量")


# --- 6. 营养失衡分级与长期过量 ---

func _test_nutrition_imbalance_and_excess() -> void:
	var s = SurvivalScript.new(6)
	var player := _new_player()
	player["attrs"]["nutrition"]["protein"] = 10.0
	player["attrs"]["nutrition"]["carbs"] = 25.0
	player["attrs"]["nutrition"]["fat"] = 60.0
	var status: Dictionary = s.nutrition_status(player)
	check_eq(str(status["protein"]["level"]), "severe", "低于 15 为重度失衡")
	check_eq(str(status["protein"]["disease_key"]), "disease.protein_deficiency", "蛋白质缺失对应疾病")
	check_eq(str(status["carbs"]["level"]), "light", "低于 30 为轻度失衡")
	check_eq(str(status["fat"]["level"]), "normal", "正常范围无失衡")

	# 连续过量：禁用衰减以便稳定高于 85，累计达阈值日。
	BaselineScript.apply_remote_config({
		"nutrition_decay_per_day": {"protein": 0.0, "carbs": 0.0, "fat": 0.0, "vitamins": 0.0, "minerals": 0.0},
	})
	var player2 := _new_player()
	for key in SurvivalScript.NUTRIENTS:
		player2["attrs"]["nutrition"][key] = 90.0
	s.update_nutrition(player2, BaselineScript.NUTRITION_EXCESS_DAYS_REQUIRED, {"age_years": 20.0})
	var risks: Dictionary = s.excess_risks()
	check(risks.has("protein"), "长期过量蛋白质计入风险")
	check_eq(int(risks.size()), 5, "五项营养均计入过量风险")
	BaselineScript.clear_overrides()


# --- 7. 成瘾 craving 与阶段 ---

func _test_addiction_craving_and_stages() -> void:
	var s = SurvivalScript.new(7)
	var player := _new_player()
	check_eq(s.addiction_phase(player, "tobacco"), "未接触", "初始未接触")
	var r1: Dictionary = s.addict(player, "tobacco", 1.0)
	check(float(r1["craving"]) > 0.0, "使用后 craving 上升")
	check_eq(int(r1["stage"]), SurvivalScript.AddictionStage.OCCASIONAL, "低 craving 为偶尔")
	check_eq(s.addiction_phase(player, "tobacco"), "偶尔", "偶尔阶段中文名")

	# 耐受使累积加快：同等剂量的增量应不小于首次。
	var r2: Dictionary = s.addict(player, "tobacco", 1.0)
	var d1: float = float(r1["craving"])
	var d2: float = float(r2["craving"]) - d1
	check(d2 >= d1 - 1e-9, "耐受使累积不减速")
	check(float(player["health"]["addictions"][0]["tolerance"]) > 0.0, "耐受增长")

	# 阶段阈值（20 依赖 / 60 重度）。
	check_eq(s.addiction_stage(0.0), SurvivalScript.AddictionStage.NONE, "0 未接触")
	check_eq(s.addiction_stage(30.0), SurvivalScript.AddictionStage.DEPENDENT, "30 依赖")
	check_eq(s.addiction_stage(80.0), SurvivalScript.AddictionStage.SEVERE, "80 重度")


# --- 8. 戒断：心情/意志/体力下降，恢复退出 ---

func _test_addiction_withdrawal() -> void:
	var s = SurvivalScript.new(8)
	var player := _new_player()
	while float(s.get_addiction(player, "tobacco").get("craving", 0.0)) < BaselineScript.ADDICTION_DEPENDENT_MIN:
		s.addict(player, "tobacco", 1.0)
	var before_mood: float = float(player["attrs"]["psychological"]["mood"])
	var before_will: float = float(player["attrs"]["ability"]["willpower"])
	var before_stamina: float = float(player["attrs"]["physiological"]["stamina"])

	s.advance_now(int(BaselineScript.ADDICTION_WITHDRAWAL_TRIGGER_HOURS * 60.0) + 60)
	s.update_addictions(player, 60, {})
	check_eq(s.addiction_phase(player, "tobacco"), "戒断中", "停用后进入戒断中")
	check(float(player["attrs"]["psychological"]["mood"]) < before_mood, "戒断降低心情")
	check(float(player["attrs"]["ability"]["willpower"]) < before_will, "戒断降低意志")
	check(float(player["attrs"]["physiological"]["stamina"]) < before_stamina, "生理成瘾戒断降低体力")

	# 戒断期结束后退出（赌博/网络无生理戒断，体力不变）。
	s.update_addictions(player, 8 * 1440, {})
	check(s.addiction_phase(player, "tobacco") != "戒断中", "戒断期满退出戒断")

	var gamer := _new_player()
	while float(s.get_addiction(gamer, "gambling").get("craving", 0.0)) < BaselineScript.ADDICTION_DEPENDENT_MIN:
		s.addict(gamer, "gambling", 1.0)
	var gamer_stamina: float = float(gamer["attrs"]["physiological"]["stamina"])
	s.advance_now(24 * 60)
	s.update_addictions(gamer, 60, {})
	check_near(float(gamer["attrs"]["physiological"]["stamina"]), gamer_stamina, 1e-6, "心理成瘾无生理戒断")


# --- 9. 治疗与复发 ---

func _test_addiction_treatment_and_relapse() -> void:
	var s = SurvivalScript.new(9)
	var player := _new_player()
	s.addict(player, "drug", 10.0)
	var before: float = float(s.get_addiction(player, "drug")["craving"])
	var result: Dictionary = s.treat_addiction(player, "drug", "inpatient")
	check(bool(result["ok"]), "治疗执行成功")
	check(float(result["craving"]) < before, "住院治疗降低 craving")
	var relapsed: bool = s.relapse(player, "drug")
	check(typeof(relapsed) == TYPE_BOOL, "复发判定返回布尔")
	check(s.get_addiction(player, "drug")["craving"] >= float(result["craving"]), "复发不降低 craving")


# --- 10. 死亡与死亡冻结 ---

func _test_death_and_freeze() -> void:
	var s = SurvivalScript.new(10)
	var player := _new_player()
	player["attrs"]["physiological"]["health"] = 0.0
	var ev: Dictionary = s.evaluate(player, {})
	check(bool(ev["dead"]), "健康归零触发死亡")
	check(not bool(ev["dying"]), "死亡优先于临终")

	var before: Dictionary = player["attrs"].duplicate(true)
	var after: Dictionary = s.advance(player, 100000, {})
	check(bool(after["frozen"]), "死亡后推进被冻结")
	check_eq(int(after["advanced_minutes"]), 0, "冻结时不推进时间")
	check(_deep_equal(before, player["attrs"]), "冻结后属性不变")

	# 饥渴叠加致死。
	var s2 = SurvivalScript.new(11)
	var starved := _new_player()
	starved["attrs"]["physiological"]["hunger"] = 0.0
	starved["attrs"]["physiological"]["thirst"] = 0.0
	starved["attrs"]["physiological"]["health"] = 5.0
	var ev2: Dictionary = s2.advance(starved, 120, {"age_years": 30.0})
	check(bool(ev2["dead"]), "长期饥渴导致健康归零死亡")


# --- 11. 临终状态与动词门控 ---

func _test_dying_state_and_verbs() -> void:
	var s = SurvivalScript.new(12)
	var player := _new_player()
	player["attrs"]["physiological"]["health"] = 5.0
	var ev: Dictionary = s.evaluate(player, {"treatment_available": false})
	check(bool(ev["dying"]), "健康≤10 且无治疗进入临终")
	check(not bool(ev["dead"]), "临终尚未死亡")
	check(not s.verb_allowed("工作"), "临终锁定体力型动词")
	check(s.verb_allowed("告别"), "临终开放告别")
	check(s.verb_allowed("立遗嘱"), "临终开放立遗嘱")
	check(s.verb_allowed("器官捐献"), "临终开放器官捐献")

	# 确诊绝症同样进入临终；寿命将尽 + 健康低亦可。
	var s2 = SurvivalScript.new(13)
	var player2 := _new_player()
	player2["attrs"]["physiological"]["health"] = 80.0
	check(bool(s2.evaluate(player2, {"terminal_disease": true})["dying"]), "确诊绝症进入临终")
	var s3 = SurvivalScript.new(14)
	var player3 := _new_player()
	player3["attrs"]["physiological"]["health"] = 20.0
	check(bool(s3.evaluate(player3, {"lifespan_years": 40.0, "age_years": 39.0})["dying"]), "寿命将尽且健康低进入临终")


# --- 12. 遗嘱形式与人生总结 ---

func _test_will_forms_and_life_summary() -> void:
	var s = SurvivalScript.new(15)
	var player := _new_player()
	# 非临终：口头遗嘱无效，缺见证的打印遗嘱无效。
	check(not bool(s.validate_will("oral", {"witnessed": true})["valid"]), "非临终口头遗嘱无效")
	check(not bool(s.validate_will("printed", {})["valid"]), "打印遗嘱需见证")
	check(not bool(s.make_will("printed", {})["ok"]), "无效遗嘱不予保存")

	# 公证遗嘱有效且优先级最高。
	var notarized: Dictionary = s.validate_will("notarized", {})
	var holographic: Dictionary = s.validate_will("holographic", {})
	check(bool(notarized["valid"]), "公证遗嘱有效")
	check(int(notarized["priority"]) > int(holographic["priority"]), "公证效力高于自书")
	check(not bool(notarized["challengeable"]), "公证遗嘱不可挑战")
	check(bool(holographic["challengeable"]), "自书遗嘱可被挑战")
	var made: Dictionary = s.make_will("notarized", {"organ_donation": true})
	check(bool(made["ok"]) and s.has_valid_will(), "遗嘱保存成功")

	# 临终后口头遗嘱（有见证）有效。
	var dying = SurvivalScript.new(16)
	var dying_player := _new_player()
	dying_player["attrs"]["physiological"]["health"] = 3.0
	dying.evaluate(dying_player, {"treatment_available": false})
	check(bool(dying.validate_will("oral", {"witnessed": true})["valid"]), "临终口头遗嘱有效")
	check(not bool(dying.validate_will("oral", {})["valid"]), "临终口头遗嘱仍需见证")

	# 人生总结报告字段。
	player["name"] = "测试者"
	var summary: Dictionary = s.life_summary(player, {"age_years": 80.0, "final_title": "善终者", "timeline": [{"at": 1, "text": "出生"}]})
	check_eq(str(summary["name"]), "测试者", "总结含姓名")
	check_near(float(summary["age_years"]), 80.0, 1e-6, "总结含年龄")
	check_eq(str(summary["final_title"]), "善终者", "总结含最终称号")
	check_eq(int((summary["timeline"] as Array).size()), 1, "总结含大事记时间线")
	check(bool(summary["has_will"]), "总结标注是否有遗嘱")


# --- 13. 年龄与寿命估计 ---

func _test_lifespan_estimate() -> void:
	var s = SurvivalScript.new(17)
	var player := _new_player()
	s.advance_now(int(SurvivalScript.MINUTES_PER_YEAR))
	check_near(s.age_years(player), 1.0, 1e-6, "1 年后年龄为 1 岁")
	check_near(s.estimate_lifespan_years(), BaselineScript.LIFESPAN_BASE_YEARS, 1e-6, "默认寿命约 78 岁")
	check_near(s.estimate_lifespan_years(5.0, 2.0, 1.0, 3.0), BaselineScript.LIFESPAN_BASE_YEARS + 5.0, 1e-6, "寿命按 health_hist+medical+luck−disease 修正")
	s.sync_lifespan_estimate(player, 2.0)
	check_eq(int(player["health"]["lifespan_estimate_minutes"]), s.lifespan_estimate_minutes(2.0), "寿命估计写回 player.health")


# --- 14. 远程配置覆盖与区间 clamp ---

func _test_remote_config_and_clamp() -> void:
	var s = SurvivalScript.new(18)
	BaselineScript.apply_remote_config({"ranges": {"attribute": [0, 10]}})
	var player := _new_player()
	player["attrs"]["physiological"]["hunger"] = 100.0
	s.decay_physiological(player, 1, {"age_years": 25.0})
	check(float(player["attrs"]["physiological"]["hunger"]) <= 10.0, "远程区间覆盖后 clamp 到上界")

	BaselineScript.apply_remote_config({"starve_health_per_hour": 1000.0})
	var player2 := _new_player()
	player2["attrs"]["physiological"]["hunger"] = 0.0
	player2["attrs"]["physiological"]["health"] = 80.0
	s.decay_physiological(player2, 1, {"age_years": 25.0})
	check(float(player2["attrs"]["physiological"]["health"]) < 80.0, "远程覆盖扣血速率生效")
	BaselineScript.clear_overrides()

	# 恢复默认后区间为 0..100。
	check_eq(int(BaselineScript.effective_range("attribute")[1]), 100, "清除覆盖恢复默认上界")


# --- 15. 状态序列化往返 ---

func _test_state_roundtrip() -> void:
	var s = SurvivalScript.new(19)
	var player := _new_player()
	s.advance_now(1234)
	s.addict(player, "alcohol", 2.0)
	var risk_player := _new_player()
	BaselineScript.apply_remote_config({
		"nutrition_decay_per_day": {"protein": 0.0, "carbs": 0.0, "fat": 0.0, "vitamins": 0.0, "minerals": 0.0},
	})
	for key in SurvivalScript.NUTRIENTS:
		risk_player["attrs"]["nutrition"][key] = 90.0
	s.update_nutrition(risk_player, BaselineScript.NUTRITION_EXCESS_DAYS_REQUIRED, {})
	BaselineScript.clear_overrides()
	s.evaluate(player, {"lifespan_years": 100.0})

	var snapshot: Dictionary = s.to_dict()
	var s2 = SurvivalScript.new(0)
	s2.from_dict(snapshot)
	check_eq(s2.now_minute(), s.now_minute(), "时钟往返")
	check_eq(s2.is_dead(), s.is_dead(), "死亡标志往返")
	check(_deep_equal(s2.to_dict(), snapshot), "生存状态往返等价")

	# 往返后继续推进保持一致性（成瘾运行态仍在）。
	var p_a := _new_player()
	var p_b := _new_player()
	s.addict(p_a, "tobacco", 1.0)
	s2.addict(p_b, "tobacco", 1.0)
	check_near(float(s.get_addiction(p_a, "tobacco")["craving"]), float(s2.get_addiction(p_b, "tobacco")["craving"]), 1e-9, "往返后成瘾推进一致")


## 深度相等（兼容 JSON 数字 float 与 int）。
func _deep_equal(a: Variant, b: Variant) -> bool:
	var ta: int = typeof(a)
	var tb: int = typeof(b)
	if ta != tb:
		if (ta == TYPE_INT or ta == TYPE_FLOAT) and (tb == TYPE_INT or tb == TYPE_FLOAT):
			return float(a) == float(b)
		return false
	if ta == TYPE_DICTIONARY:
		var da: Dictionary = a
		var db: Dictionary = b
		if da.size() != db.size():
			return false
		for key in da.keys():
			if not db.has(key) or not _deep_equal(da[key], db[key]):
				return false
		return true
	if ta == TYPE_ARRAY:
		var aa: Array = a
		var ab: Array = b
		if aa.size() != ab.size():
			return false
		for i in aa.size():
			if not _deep_equal(aa[i], ab[i]):
				return false
		return true
	return a == b
