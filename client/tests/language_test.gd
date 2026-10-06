extends "res://tests/test_base.gd"
## 语言与文化测试（任务 29；R64；design D20）。
## 覆盖：语言/方法/节日/文化数据表、学习与分项成长、考试与职业解锁、长期不用遗忘、
##       方言门槛与误会、节日效果、文化差异与适应曲线、跨文化与冲突。

const LangScript = preload("res://sim/language.gd")


func _suite_name() -> String:
	return "language"


func run_tests() -> void:
	_test_tables()
	_test_study_and_components()
	_test_exam_and_careers()
	_test_forgetting()
	_test_dialect_and_misunderstanding()
	_test_festivals()
	_test_culture_and_cross_culture()


func _test_tables() -> void:
	var sys = LangScript.new()
	check_eq(sys.languages().size(), 5, "五种语言")
	check_eq(LangScript.COMPONENTS.size(), 3, "分项口语/听力/读写")
	check_eq(LangScript.STUDY_METHODS.size(), 3, "三种学习方法")
	check_eq(LangScript.FESTIVALS.size(), 6, "六个节日")
	check_eq(LangScript.CULTURES.size(), 5, "五种文化")
	check(sys.has_language("zh"), "包含汉语")
	check(not sys.has_language("xx"), "未知语言被拒")
	sys.new_profile()
	var p: Dictionary = sys.new_profile()
	check_eq(p["languages"].size(), 5, "档案含全部语言")


func _test_study_and_components() -> void:
	var sys = LangScript.new()
	var p: Dictionary = sys.new_profile()
	check_near(sys.overall(p, "en"), 0.0, 1e-6, "初始零级")
	var s1: Dictionary = sys.study(p, "en", "course", 10.0, {"aptitude": 1.0})
	check(bool(s1["ok"]), "课程学习成功")
	check(sys.overall(p, "en") > 0.0, "学习提升总分")
	check(sys.component(p, "en", "literacy") > sys.component(p, "en", "speaking"), "课程偏重读写")
	var after_first: float = sys.overall(p, "en")
	var s2: Dictionary = sys.study(p, "en", "course", 10.0, {"aptitude": 1.0})
	var gain1: float = after_first
	var gain2: float = sys.overall(p, "en") - after_first
	check(gain2 < gain1, "水平越高增益越小")
	var s3: Dictionary = sys.study(p, "en", "immersion", 10.0, {})
	check(bool(s3["ok"]), "环境沉浸可用")
	check(not bool(sys.study(p, "en", "bogus", 1.0)["ok"]), "未知方法被拒")
	check(not bool(sys.study(p, "xx", "course", 1.0)["ok"]), "未知语言被拒")


func _test_exam_and_careers() -> void:
	var sys = LangScript.new()
	var p: Dictionary = sys.new_profile()
	sys.set_level(p, "ja", 90.0, 90.0, 90.0)
	check_near(sys.overall(p, "ja"), 90.0, 1e-6, "设定等级")
	check(not sys.has_certificate(p, "ja", 1.0), "初始无证书")
	var exam: Dictionary = sys.take_exam(p, "ja", 85.0, {"roll": 0.5})
	check(bool(exam["passed"]), "等级足够通过考试")
	check(sys.has_certificate(p, "ja", 85.0), "颁发证书")
	check(sys.meets_professional(p, "ja", "medical"), "达医学术语门槛")
	check(not sys.meets_professional(p, "fr", "medical"), "未学语言未达术语门槛")
	var careers: Array = sys.unlocked_careers(p, "ja")
	check(careers.has("immigration") and careers.has("translation"), "解锁移民与翻译职业")
	# 低水平考试失败。
	var p2: Dictionary = sys.new_profile()
	var exam2: Dictionary = sys.take_exam(p2, "fr", 60.0, {"roll": 0.5})
	check(not bool(exam2["passed"]), "等级不足考试失败")


func _test_forgetting() -> void:
	var sys = LangScript.new()
	var p: Dictionary = sys.new_profile()
	sys.set_level(p, "es", 60.0, 60.0, 60.0)
	var before: float = sys.overall(p, "es")
	var short_idle: Dictionary = sys.decay(p, "es", 10.0)
	check(not bool(short_idle["decayed"]), "宽限期内不遗忘")
	var long_idle: Dictionary = sys.decay(p, "es", 395.0)
	check(bool(long_idle["decayed"]), "长期不用遗忘")
	check(sys.overall(p, "es") < before, "遗忘降低总分")


func _test_dialect_and_misunderstanding() -> void:
	var sys = LangScript.new()
	var p: Dictionary = sys.new_profile()
	sys.set_level(p, "zh", 50.0, 50.0, 50.0)
	var plain: Dictionary = sys.communication(p, "zh", {"difficulty": 50.0})
	var local: Dictionary = sys.communication(p, "zh", {"difficulty": 50.0, "local": true, "knows_dialect": true})
	check(float(local["effective_level"]) > float(plain["effective_level"]), "方言本地降低门槛")
	check(float(local["success"]) > float(plain["success"]), "方言提高交流成功率")
	var mis: Dictionary = sys.misunderstanding(p, "zh", 80.0)
	check(bool(mis["misunderstood"]), "语言不通造成误会")
	check(float(mis["relation_delta"]) < 0.0, "误会降低关系")
	var nomis: Dictionary = sys.misunderstanding(p, "zh", 40.0)
	check(not bool(nomis["misunderstood"]), "水平足够不误会")


func _test_festivals() -> void:
	var sys = LangScript.new()
	var spring: Dictionary = sys.festival_effects(1, 1)
	check(bool(spring["is_festival"]), "春节是节日")
	check(not bool(spring["shops_open"]), "春节商铺歇业")
	check(float(spring["mood"]) > 0.0, "春节提升心情")
	check(float(spring["spending"]) > 1.0, "节庆消费高峰")
	check((spring["festivals"] as Array).size() == 1, "当日节日匹配")
	var ordinary: Dictionary = sys.festival_effects(3, 3)
	check(not bool(ordinary["is_festival"]), "平日无节日")
	check(bool(ordinary["shops_open"]), "平日商铺营业")
	check_eq(sys.festivals_on(9, 15).size(), 1, "中秋匹配")


func _test_culture_and_cross_culture() -> void:
	var sys = LangScript.new()
	check_near(sys.social_modifier("cn", "cn"), 1.0, 1e-6, "同文化无差异")
	check(sys.social_modifier("jp", "ae") < 1.0, "文化差异降低社交")
	var st: Dictionary = sys.new_cultural_state()
	check_near(sys.current_adaptation(st, "us"), 0.0, 1e-6, "初始未适应")
	sys.adapt(st, "us", 365.0)
	check(sys.current_adaptation(st, "us") > 0.0, "适应度上升")
	check(float(st["shock"]) < 1.0, "文化冲击下降")
	check(float(sys.current_adaptation(st, "us")) > float(sys.current_adaptation(st, "us")) - 1.0, "适应单调")
	var p: Dictionary = sys.new_profile()
	sys.set_level(p, "en", 30.0, 30.0, 30.0)
	var tr: Dictionary = sys.translate(p, "en", 80.0)
	check(not bool(tr["success"]), "等级不足翻译失败")
	var marriage: Dictionary = sys.intercultural_marriage("cn", "jp", 0.2, 0.2)
	check(float(marriage["harmony"]) >= 0.0, "跨国婚姻和谐度")
	var conflict: Dictionary = sys.cultural_conflict("jp", "ae", 0.0, 0.0, {"roll": 0.0})
	check(bool(conflict["conflict"]), "适应不足触发文化冲突")
	check(float(conflict["relation_delta"]) < 0.0, "冲突降关系")
