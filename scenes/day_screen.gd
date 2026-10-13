extends Control
## 每日循环：显示状态 → 随机事件 → 选择 → 结算 / 晋升 → 下一天
## Day loop: stats → random event → choice → settle / promote → next day

@onready var _day_label: Label = %DayLabel
@onready var _title_label: Label = %JobTitleLabel
@onready var _stats_label: Label = %StatsLabel
@onready var _event_title: Label = %EventTitle
@onready var _event_body: Label = %EventBody
@onready var _btn_choice_a: Button = %BtnChoiceA
@onready var _btn_choice_b: Button = %BtnChoiceB
@onready var _result_label: Label = %ResultLabel
@onready var _btn_continue: Button = %BtnContinue
@onready var _choices_box: VBoxContainer = %ChoicesBox
@onready var _result_box: VBoxContainer = %ResultBox

var _events: Array = []
var _current_event: Dictionary = {}
var _phase: String = "choice"  # choice | result | win


func _ready() -> void:
	_events = EventLoader.load_events()
	_btn_choice_a.pressed.connect(_on_choice.bind(0))
	_btn_choice_b.pressed.connect(_on_choice.bind(1))
	_btn_continue.pressed.connect(_on_continue_pressed)
	EventBus.stats_changed.connect(_refresh_stats)
	_refresh_stats()
	_start_day()


func _refresh_stats() -> void:
	_day_label.text = "第 %d 天" % GameState.day
	_title_label.text = "职位：%s" % GameState.job_title
	_stats_label.text = "技能 %d  |  人脉 %d  |  压力 %d  |  金钱 %d" % [
		GameState.skill, GameState.network, GameState.stress, GameState.money
	]


func _start_day() -> void:
	_phase = "choice"
	_result_box.visible = false
	_choices_box.visible = true
	_result_label.text = ""
	_current_event = EventLoader.pick_random(_events)
	if _current_event.is_empty():
		_event_title.text = "（无事件）"
		_event_body.text = "请检查 data/events.json"
		_btn_choice_a.disabled = true
		_btn_choice_b.disabled = true
		return
	_event_title.text = str(_current_event.get("title", "事件"))
	_event_body.text = str(_current_event.get("body", ""))
	var choices: Array = _current_event.get("choices", [])
	_btn_choice_a.disabled = false
	_btn_choice_b.disabled = false
	_btn_choice_a.text = str(choices[0].get("text", "选项 A")) if choices.size() > 0 else "选项 A"
	_btn_choice_b.text = str(choices[1].get("text", "选项 B")) if choices.size() > 1 else "选项 B"
	_btn_choice_b.visible = choices.size() > 1


func _on_choice(index: int) -> void:
	if _phase != "choice":
		return
	var choices: Array = _current_event.get("choices", [])
	if index < 0 or index >= choices.size():
		return
	var choice: Dictionary = choices[index]
	var effects: Dictionary = choice.get("effects", {})
	GameState.apply_deltas(effects)
	EventBus.choice_made.emit(str(_current_event.get("id", "")), index)

	# 简要结果文案
	var parts: PackedStringArray = []
	for key in ["skill", "network", "stress", "money"]:
		var v := int(effects.get(key, 0))
		if v != 0:
			var name_cn := {"skill": "技能", "network": "人脉", "stress": "压力", "money": "金钱"}[key]
			parts.append("%s %+d" % [name_cn, v])
	_result_label.text = "选择结果：%s" % ("、".join(parts) if parts.size() > 0 else "无明显变化")

	# 晋升检测
	var promoted := GameState.try_promote()
	if promoted:
		_result_label.text += "\n🎉 晋升为【%s】！" % GameState.job_title

	GameState.save_game()
	EventBus.day_ended.emit(GameState.day)

	_phase = "result"
	_choices_box.visible = false
	_result_box.visible = true

	if GameState.is_ceo():
		_phase = "win"
		_result_label.text += "\n\n🏆 恭喜！你成为了 CEO，打工人逆袭成功！"
		_btn_continue.text = "返回主菜单"
	else:
		_btn_continue.text = "进入下一天"


func _on_continue_pressed() -> void:
	if _phase == "win":
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
		return
	GameState.advance_day()
	_start_day()