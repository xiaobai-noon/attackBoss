extends Control
## 《打boss》主菜单：普通/回溯新游戏、继续、退出

@onready var _title: Label = %TitleLabel
@onready var _subtitle: Label = %SubtitleLabel
@onready var _btn_new: Button = %BtnNewGame
@onready var _btn_new_rewind: Button = %BtnNewRewind
@onready var _btn_continue: Button = %BtnContinue
@onready var _btn_quit: Button = %BtnQuit


func _ready() -> void:
	_title.text = "打boss"
	_subtitle.text = "Attack Boss · 职场人生模拟 · 困局回溯"
	_btn_new.text = "新游戏（普通模式）"
	_btn_new_rewind.text = "新游戏（回溯模式）"
	_btn_new.pressed.connect(_on_new_game.bind(GameState.Mode.NORMAL))
	_btn_new_rewind.pressed.connect(_on_new_game.bind(GameState.Mode.REWIND))
	_btn_continue.pressed.connect(_on_continue)
	_btn_quit.pressed.connect(_on_quit)
	_btn_continue.disabled = not FileAccess.file_exists(GameState.SAVE_PATH)


func _on_new_game(p_mode: GameState.Mode) -> void:
	GameState.new_game(p_mode)
	get_tree().change_scene_to_file("res://scenes/day_screen.tscn")


func _on_continue() -> void:
	if GameState.load_game():
		get_tree().change_scene_to_file("res://scenes/day_screen.tscn")
	else:
		_btn_continue.disabled = true


func _on_quit() -> void:
	get_tree().quit()
