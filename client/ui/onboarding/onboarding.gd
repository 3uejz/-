extends Control
## 开档分步向导（R33、R57）：起始年龄、外貌占位、天赋点选、家境与出生地。
## 仅首个存档出现，可跳过；逻辑在 OnboardingModel，场景只做结构与接线。
## 3D 捏脸仅占位面板，不建美术资源（资源见任务 23）。

const ModelScript = preload("res://ui/onboarding/onboarding_model.gd")

@onready var _age_option: OptionButton = $Panel/AgeSection/AgeOption
@onready var _age_label: Label = $Panel/AgeSection/AgeLabel
@onready var _appearance_hint: Label = $Panel/AppearanceSection/AppearanceHint
@onready var _talent_points: Label = $Panel/TalentSection/TalentPoints
@onready var _talent_list: VBoxContainer = $Panel/TalentSection/TalentList
@onready var _family_random: CheckBox = $Panel/FamilySection/FamilyRandom
@onready var _family_tier: OptionButton = $Panel/FamilySection/FamilyTier
@onready var _birth_random: CheckBox = $Panel/BirthSection/BirthRandom
@onready var _birth_place: LineEdit = $Panel/BirthSection/BirthPlace
@onready var _random_button: Button = $Panel/Buttons/RandomButton
@onready var _skip_button: Button = $Panel/Buttons/SkipButton
@onready var _start_button: Button = $Panel/Buttons/StartButton

var model
var _on_complete: Callable = Callable()

func _ready() -> void:
	model = ModelScript.new()
	_setup()
	_connect_nodes()

func set_complete_handler(handler: Callable) -> void:
	_on_complete = handler

func _setup() -> void:
	if is_instance_valid(_age_option):
		_age_option.clear()
		_age_option.add_item("成年（18 岁）", 0)
		_age_option.add_item("童年（6 岁）", 1)
		_age_option.add_item("出生（0 岁）", 2)
		_age_option.select(0)
	if is_instance_valid(_appearance_hint):
		_appearance_hint.text = "外貌捏脸（3D 占位）：参数结构已预留，美术资源见任务 23"
	if is_instance_valid(_family_tier):
		_family_tier.clear()
		for tier in ModelScript.FAMILY_MODES:
			if tier != "random":
				_family_tier.add_item(tier)
	if is_instance_valid(_birth_place):
		_birth_place.placeholder_text = "留空则全国随机"
	_build_talents()
	_refresh()

func _connect_nodes() -> void:
	if is_instance_valid(_age_option):
		_age_option.item_selected.connect(_on_age_selected)
	if is_instance_valid(_family_random):
		_family_random.toggled.connect(func(on: bool) -> void: model.set_family_mode("random" if on else "specified"))
	if is_instance_valid(_birth_random):
		_birth_random.toggled.connect(func(on: bool) -> void: model.set_birthplace_mode("random" if on else "specified"))
	if is_instance_valid(_random_button):
		_random_button.pressed.connect(_on_randomize)
	if is_instance_valid(_skip_button):
		_skip_button.pressed.connect(_on_skip)
	if is_instance_valid(_start_button):
		_start_button.pressed.connect(_on_start)

func _build_talents() -> void:
	if not is_instance_valid(_talent_list):
		return
	for id in ModelScript.TALENTS.keys():
		var talent_id := String(id)
		var info: Dictionary = ModelScript.TALENTS[id]
		var check := CheckBox.new()
		var suffix := ""
		if bool(info["negative"]):
			suffix = "（负特质 +%d 点）" % absi(int(info["cost"]))
		else:
			suffix = "（消耗 %d 点）" % int(info["cost"])
		check.text = "%s %s" % [String(info["name"]), suffix]
		check.toggled.connect(func(on: bool) -> void: _on_talent_toggled(talent_id, on))
		_talent_list.add_child(check)

func _on_age_selected(index: int) -> void:
	var modes: Array = ["adult", "child", "birth"]
	model.set_start_mode(String(modes[index]))
	_refresh()

func _on_talent_toggled(id: String, on: bool) -> void:
	if on:
		var result: Dictionary = model.select_talent(id)
		if not result["ok"]:
			append_hint(String(result["error"]), "warning")
	else:
		model.deselect_talent(id)
	_refresh()

func _on_randomize() -> void:
	model.randomize_all(Time.get_ticks_msec())
	if is_instance_valid(_birth_place):
		_birth_place.text = model.birthplace
	_refresh()

func _on_skip() -> void:
	model.skipped = true
	_finish()

func _on_start() -> void:
	if not model.can_confirm():
		append_hint("天赋点不足，请调整选择", "danger")
		return
	_finish()

func _finish() -> void:
	if _on_complete.is_valid():
		_on_complete.call(model)

func _refresh() -> void:
	if is_instance_valid(_age_label):
		_age_label.text = "起始年龄：%d 岁" % model.start_age
	if is_instance_valid(_talent_points):
		_talent_points.text = "剩余天赋点：%d" % model.remaining_points()
	if is_instance_valid(_start_button):
		_start_button.disabled = not model.can_confirm()

## 向导内提示（占位，实际可路由到主界面叙事流）。
func append_hint(text: String, _type: String = "info") -> void:
	if is_instance_valid(_age_label):
		_age_label.tooltip_text = text
