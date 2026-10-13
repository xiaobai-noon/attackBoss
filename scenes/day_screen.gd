extends Control
## 《打boss》回合主界面：年/季/周 → 事件 → 选择 → 结算 → 推进
## 当前为 M1~M3 可玩胶水；困局回溯 / 正式结局在后续模块接入

@onready var _day_label: Label = %DayLabel
@onready var _title_label: Label = %JobTitleLabel
@onready var _stats_label: Label = %StatsLabel
@onready var _event_title: Label = %EventTitle
@onready var _event_body: Label = %EventBody
@onready var _btn_choice_a: Button = %BtnChoiceA
@onready var _btn_choice_b: Button = %BtnChoiceB
@onready var _btn_choice_c: Button = %BtnChoiceC
@onready var _result_label: Label = %ResultLabel
@onready var _btn_continue: Button = %BtnContinue
@onready var _choices_box: VBoxContainer = %ChoicesBox
@onready var _result_box: VBoxContainer = %ResultBox

const STAT_KEYS: Array[String] = [
	"performance", "expertise", "influence", "reputation",
	"mind_load", "health", "resource",
]
const STAT_NAMES := {
	"performance": "绩效",
	"expertise": "专业",
	"influence": "人脉",
	"reputation": "声望",
	"mind_load": "精神负荷",
	"health": "身心健康",
	"resource": "资源",
}

var _events: Array = []
var _current_event: Dictionary = {}
var _phase: String = "choice"  # choice | result | win
var _year_end_note: String = ""


func _ready() -> void:
	_events = EventLoader.load_events()
	_btn_choice_a.pressed.connect(_on_choice.bind(0))
	_btn_choice_b.pressed.connect(_on_choice.bind(1))
	_btn_choice_c.pressed.connect(_on_choice.bind(2))
	_btn_continue.pressed.connect(_on_continue_pressed)
	EventBus.stats_changed.connect(_refresh_stats)
	EventBus.year_ended.connect(_on_year_ended)
	_refresh_stats()
	_start_week()


func _refresh_stats() -> void:
	_day_label.text = "第 %d 年 · Q%d · 第 %d 周" % [GameState.year, GameState.quarter, GameState.week]
	var mode_txt := "回溯" if GameState.mode == GameState.Mode.REWIND else "普通"
	_title_label.text = "职位：%s  |  模式：%s" % [GameState.job_title, mode_txt]
	_stats_label.text = "绩效 %d  |  专业 %d  |  人脉 %d  |  声望 %d\n精神负荷 %d  |  身心健康 %d  |  资源 %d" % [
		GameState.performance, GameState.expertise, GameState.influence, GameState.reputation,
		GameState.mind_load, GameState.health, GameState.resource,
	]


func _on_year_ended(ended_year: int) -> void:
	_year_end_note = "第 %d 年已结束：属性已按年末规则结算。" % ended_year


func _start_week() -> void:
	_phase = "choice"
	_result_box.visible = false
	_choices_box.visible = true
	_result_label.text = ""
	_current_event = EventLoader.pick_weighted(
		_events,
		GameState.rank_index,
		GameState.mind_load,
		GameState.year_triggered_events
	)
	if _current_event.is_empty():
		_event_title.text = "（无事件）"
		_event_body.text = "请检查 data/events.json"
		_btn_choice_a.disabled = true
		_btn_choice_b.disabled = true
		_btn_choice_c.visible = false
		return
	_event_title.text = str(_current_event.get("title", "事件"))
	_event_body.text = str(_current_event.get("body", ""))
	var choices: Array = _current_event.get("choices", [])
	_btn_choice_a.disabled = false
	_btn_choice_b.disabled = false
	_btn_choice_a.text = str(choices[0].get("text", "选项 A")) if choices.size() > 0 else "选项 A"
	_btn_choice_b.text = str(choices[1].get("text", "选项 B")) if choices.size() > 1 else "选项 B"
	_btn_choice_b.visible = choices.size() > 1
	if choices.size() > 2:
		_btn_choice_c.visible = true
		_btn_choice_c.disabled = false
		_btn_choice_c.text = str(choices[2].get("text", "选项 C"))
	else:
		_btn_choice_c.visible = false


func _on_choice(index: int) -> void:
	if _phase != "choice":
		return
	var choices: Array = _current_event.get("choices", [])
	if index < 0 or index >= choices.size():
		return
	var choice: Dictionary = choices[index]
	var effects: Dictionary = choice.get("effects", {})
	GameState.apply_deltas(effects)

	var npc_effects: Dictionary = choice.get("npc_effects", {})
	if not npc_effects.is_empty():
		GameState.apply_npc_effects(npc_effects)

	for flag in choice.get("flags_add", []):
		GameState.add_flag(str(flag))
		## 统计用衍生标记
		if str(flag) == "reform_seed":
			GameState.add_flag("reform_seeds")
		if str(flag) == "dark_choice":
			GameState.add_flag("dark_choices")

	var eid := str(_current_event.get("id", ""))
	if not eid.is_empty() and not GameState.year_triggered_events.has(eid):
		GameState.year_triggered_events.append(eid)

	EventBus.event_resolved.emit(eid, index)
	EventBus.choice_made.emit(eid, index)

	var parts: PackedStringArray = []
	for key in STAT_KEYS:
		var v := int(effects.get(key, 0))
		if v != 0:
			parts.append("%s %+d" % [STAT_NAMES.get(key, key), v])
	_result_label.text = "选择结果：%s" % ("、".join(parts) if parts.size() > 0 else "无属性变化")

	GameState.save_game()

	_phase = "result"
	_choices_box.visible = false
	_result_box.visible = true

	if GameState.is_ceo():
		_phase = "win"
		_result_label.text += "\n\n🎊 你成为了 CEO。《打boss》主线通关（结局分支后续模块完善）。"
		_btn_continue.text = "返回主菜单"
	elif GameState.mind_load >= 100:
		_phase = "win"
		_result_label.text += "\n\n精神负荷已满——困局沉沦（正式结局界面后续接入）。"
		_btn_continue.text = "返回主菜单"
	elif GameState.health <= 0:
		_phase = "win"
		_result_label.text += "\n\n身心健康归零——需要离场或淘汰判定（后续模块）。"
		_btn_continue.text = "返回主菜单"
	else:
		_btn_continue.text = "进入下一周"


func _on_continue_pressed() -> void:
	if _phase == "win":
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
		return
	var prev_rank := GameState.rank_index
	var prev_year := GameState.year
	GameState.advance_week()
	if GameState.year > prev_year:
		var note := _year_end_note
		if GameState.rank_index > prev_rank:
			note += "\n🎉 升职为「%s」！" % GameState.job_title
		if not note.is_empty():
			## 年末提示并入下一周开始前的结果态已翻页，写入事件区短暂可见
			_event_body.text = note + "\n\n" + _event_body.text
		_year_end_note = ""
	_refresh_stats()
	_start_week()
