extends Control
## 主菜单：新游戏 / 继续 / 退出
## Main menu: New Game / Continue / Quit

@onready var _title: Label = %TitleLabel
@onready var _subtitle: Label = %SubtitleLabel
@onready var _btn_new: Button = %BtnNewGame
@onready var _btn_continue: Button = %BtnContinue
@onready var _btn_quit: Button = %BtnQuit


func _ready() -> void:
	_title.text = "打工人上位"
	_subtitle.text = "AttackBoss · 职场人生模拟"
	_btn_new.pressed.connect(_on_new_game)
	_btn_continue.pressed.connect(_on_continue)
	_btn_quit.pressed.connect(_on_quit)
	# 有存档才启用「继续」
	_btn_continue.disabled = not FileAccess.file_exists(GameState.SAVE_PATH)


func _on_new_game() -> void:
	GameState.new_game()
	get_tree().change_scene_to_file("res://scenes/day_screen.tscn")


func _on_continue() -> void:
	if GameState.load_game():
		get_tree().change_scene_to_file("res://scenes/day_screen.tscn")
	else:
		_btn_continue.disabled = true


func _on_quit() -> void:
	get_tree().quit()
