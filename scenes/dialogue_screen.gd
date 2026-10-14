extends Control
## 《打boss》对话场景 —— AVG 表现层（垂直切片原型）
##
## 职责边界（严格遵守）：
##   1. 渲染 DialogueEngine 抛出的状态（背景 / 立绘 / 台词 / 选项）
##   2. 收集玩家输入（点击、空格、数字键）并转发给引擎
##   3. 把 effect 节点转发给 GameState 结算
## 本文件**不做任何数值计算**，所有规则都在 GameState / DialogueEngine 里。
##
## 运行方式：Godot 打开项目 → FileSystem 里选中本场景 → F6
## 素材说明：当前为零素材原型，背景与立绘用占位色块。接入美术时替换：
##   背景 → assets/bg/{scene_id}.png
##   立绘 → assets/sprite/{npc_id}/{npc_id}_{emotion}.png

const STORY_PATH := "res://data/story/evt_01_weekly_report.json"

## 打字机速度（字/秒）
const TYPE_SPEED := 46.0

const STAT_NAMES := {
	"performance": "绩效",
	"expertise": "专业",
	"influence": "人脉",
	"reputation": "声望",
	"mind_load": "精神负荷",
	"health": "身心健康",
	"resource": "资源",
}

const SLOT_NAMES := {
	"morning": "上午",
	"afternoon": "下午",
	"overtime": "加班",
	"night": "深夜",
}

const EMOTION_NAMES := {
	"neutral": "平静",
	"pleased": "满意",
	"smug": "得意",
	"annoyed": "不悦",
	"concerned": "忧虑",
	"tired": "疲惫",
}

## 场景表：接入美术后换成 Texture2D 路径即可，键名与剧本 scene 字段一致
const SCENE_STYLE := {
	"office_floor": { "name": "开放办公区", "color": Color(0.11, 0.13, 0.17) },
	"meeting_room": { "name": "三号会议室", "color": Color(0.13, 0.12, 0.16) },
	"pantry": { "name": "茶水间", "color": Color(0.11, 0.14, 0.13) },
	"canteen": { "name": "员工餐厅", "color": Color(0.15, 0.13, 0.11) },
	"elevator": { "name": "电梯厅", "color": Color(0.10, 0.12, 0.16) },
	"boss_office": { "name": "副总办公室", "color": Color(0.15, 0.13, 0.12) },
	"night_office": { "name": "深夜 · 开放办公区", "color": Color(0.07, 0.08, 0.12) },
	"hr_room": { "name": "HR 洽谈间", "color": Color(0.12, 0.12, 0.14) },
	"client_site": { "name": "客户现场", "color": Color(0.12, 0.13, 0.15) },
	"team_event": { "name": "团建场地", "color": Color(0.13, 0.15, 0.12) },
}

## NPC 表：接入立绘后换成贴图路径；color 仅用于占位块
const NPC_STYLE := {
	"shen_tinglan": { "name": "沈听澜", "color": Color(0.28, 0.36, 0.48) },
	"ji_heng": { "name": "季　衡", "color": Color(0.34, 0.30, 0.46) },
	"you_wanxing": { "name": "尤晩星", "color": Color(0.28, 0.40, 0.38) },
	"tang_poxiao": { "name": "唐破晓", "color": Color(0.44, 0.34, 0.28) },
	"liang_xu": { "name": "梁　叙", "color": Color(0.40, 0.38, 0.30) },
	"player": { "name": "你", "color": Color(0.30, 0.34, 0.40) },
}

@onready var _bg: ColorRect = $Bg
@onready var _shots: ShotDirector = %ShotLayer
@onready var _scene_name: Label = %SceneName
@onready var _portrait_left: PanelContainer = %PortraitLeft
@onready var _portrait_right: PanelContainer = %PortraitRight
@onready var _time_label: Label = %TimeLabel
@onready var _dock_label: Label = %DockLabel
@onready var _stats_label: Label = %StatsLabel
@onready var _toast: Label = %ResultToast
@onready var _choices_box: VBoxContainer = %ChoicesBox
@onready var _speaker_wrap: PanelContainer = %SpeakerWrap
@onready var _speaker_label: Label = %SpeakerLabel
@onready var _dialogue_text: RichTextLabel = %DialogueText
@onready var _hint_label: Label = %HintLabel

var _engine: DialogueEngine
var _story_title: String = ""
var _current_scene: String = "office_floor"
var _current_slot: String = "morning"

var _choice_buttons: Array[Button] = []
var _typing := false
var _type_accum := 0.0
var _toast_tween: Tween = null
var _missing_assets: int = 0


func _ready() -> void:
	set_process(false)
	_engine = DialogueEngine.new()
	_engine.stat_getter = _read_stat
	_engine.flag_checker = _check_flag
	_engine.effect_applier = _apply_effects
	_engine.line_shown.connect(_on_line_shown)
	_engine.scene_changed.connect(_on_scene_changed)
	_engine.shot_requested.connect(_on_shot_requested)
	_engine.choices_offered.connect(_on_choices_offered)
	_engine.effects_applied.connect(_on_effects_applied)
	_engine.finished.connect(_on_finished)
	_engine.faulted.connect(_on_faulted)

	# 立绘注册成「视差参与者」：镜头横移时立绘跟着轻微位移，人才像长在场景里
	_shots.asset_missing.connect(_on_asset_missing)
	_shots.register_actor(_portrait_left, 0.70)
	_shots.register_actor(_portrait_right, 0.70)

	EventBus.stats_changed.connect(_refresh_stats)
	_set_portrait(_portrait_left, "", "")
	_set_portrait(_portrait_right, "", "")
	_refresh_stats()
	_start_story()


func _process(delta: float) -> void:
	if not _typing:
		return
	_type_accum += delta * TYPE_SPEED
	var total: int = _dialogue_text.get_total_character_count()
	if int(_type_accum) >= total:
		_finish_typing()
	else:
		_dialogue_text.visible_characters = int(_type_accum)


func _unhandled_input(event: InputEvent) -> void:
	# 结算提示轻微闪烁结束后不拦截输入
	var is_click: bool = event is InputEventMouseButton \
		and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT

	if event is InputEventKey and event.pressed and not event.echo:
		var kc: Key = event.keycode
		if kc == KEY_R:
			_restart()
			get_viewport().set_input_as_handled()
			return
		if _engine != null and _engine.is_waiting_choice() and kc >= KEY_1 and kc <= KEY_9:
			var idx := int(kc) - int(KEY_1)
			if idx < _choice_buttons.size():
				_on_choice_pressed(idx)
				get_viewport().set_input_as_handled()
			return

	if not (is_click or event.is_action_pressed("ui_accept")):
		return

	if _typing:
		_finish_typing()
		get_viewport().set_input_as_handled()
		return
	if _engine != null and _engine.is_waiting_line():
		_engine.advance()
		get_viewport().set_input_as_handled()


# ------------------------------------------------------------------ 启动 / 重启

func _start_story() -> void:
	var story := DialogueEngine.load_story(STORY_PATH)
	if story.is_empty():
		_on_faulted("无法加载剧本：%s" % STORY_PATH)
		return
	_story_title = str(story.get("title", ""))
	_current_slot = str(story.get("slot", "morning"))
	_engine.start(story)
	_refresh_time()


func _restart() -> void:
	_clear_choices()
	_choices_box.visible = false
	_speaker_wrap.visible = false
	_set_portrait(_portrait_left, "", "")
	_set_portrait(_portrait_right, "", "")
	_toast.visible = false
	_missing_assets = 0
	_start_story()


# ------------------------------------------------------------------ 引擎信号处理

func _on_scene_changed(scene_id: String, slot: String) -> void:
	_current_scene = scene_id
	if not slot.is_empty():
		_current_slot = slot
	var style: Dictionary = SCENE_STYLE.get(scene_id, {})
	_bg.color = style.get("color", Color(0.11, 0.13, 0.17))
	_scene_name.text = str(style.get("name", scene_id))
	# 交给镜头导演播该场景的定场镜头；镜头表未登记的场景会保持纯色底（可继续开发）
	if not _shots.play_scene_entry(scene_id):
		_shots.stop()
	# 换场景 = 清台，避免上一场的角色留在新场景里
	_set_portrait(_portrait_left, "", "")
	_set_portrait(_portrait_right, "", "")
	_speaker_wrap.visible = false
	_refresh_time()


func _on_shot_requested(shot_id: String, _params: Dictionary) -> void:
	_shots.play_shot(shot_id)


func _on_asset_missing(path: String) -> void:
	_missing_assets += 1
	push_warning("[素材缺失] %s（占位阶段正常，接入美术后应为 0）" % path)


func _on_line_shown(speaker: String, text: String, emotion: String, side: String) -> void:
	_choices_box.visible = false
	_clear_choices()

	if speaker == "narrator":
		# 旁白：不显示名字牌，立绘保留但压暗（不要清空，否则会闪）
		_speaker_wrap.visible = false
		_dim_portrait(_portrait_left, true)
		_dim_portrait(_portrait_right, true)
	elif speaker == "player":
		_speaker_wrap.visible = true
		_speaker_label.text = "你"
		_dim_portrait(_portrait_left, true)
		_dim_portrait(_portrait_right, true)
	else:
		_speaker_wrap.visible = true
		_speaker_label.text = _speaker_name(speaker)
		var focused := _portrait_left if side == "left" else _portrait_right
		var other := _portrait_right if side == "left" else _portrait_left
		_set_portrait(focused, speaker, emotion)
		_dim_portrait(focused, false)
		_dim_portrait(other, true)
		# 反打：场景配了 reverse 机位就按说话人所在侧切镜头。
		# 没配（或当前是旁白/你）就保持不动 —— 乱切镜头比不切更难看。
		_shots.play_reverse(side)

	_dialogue_text.text = text
	_dialogue_text.visible_characters = 0
	_type_accum = 0.0
	_typing = true
	_hint_label.visible = false
	set_process(true)


func _on_choices_offered(prompt: String, options: Array) -> void:
	_typing = false
	set_process(false)
	_dialogue_text.text = prompt
	_dialogue_text.visible_characters = -1
	_hint_label.visible = false
	_speaker_wrap.visible = false

	_clear_choices()
	for i in options.size():
		var opt: Dictionary = options[i]
		var btn := Button.new()
		btn.text = "%d、%s" % [i + 1, str(opt.get("text", "……"))]
		btn.custom_minimum_size = Vector2(560, 46)
		btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		btn.add_theme_font_size_override("font_size", 17)
		btn.pressed.connect(_on_choice_pressed.bind(i))
		_choices_box.add_child(btn)
		_choice_buttons.append(btn)

	_choices_box.visible = true
	if not _choice_buttons.is_empty():
		_choice_buttons[0].grab_focus()


func _on_effects_applied(summary: Dictionary) -> void:
	_refresh_stats()
	var parts: PackedStringArray = []
	var deltas: Dictionary = summary.get("deltas", {})
	for key in STAT_NAMES.keys():
		var v := int(deltas.get(key, 0))
		if v != 0:
			parts.append("%s %+d" % [STAT_NAMES[key], v])
	var npc_changes: Dictionary = summary.get("npc_changes", {})
	for npc_id in npc_changes.keys():
		parts.append("%s 好感 %+d" % [_speaker_name(str(npc_id)), int(npc_changes[npc_id])])
	if parts.is_empty():
		return
	_show_toast("、".join(parts))


func _on_finished(_node_id: String, meta: Dictionary) -> void:
	_typing = false
	set_process(false)
	_clear_choices()
	_choices_box.visible = false
	_speaker_wrap.visible = false
	_set_portrait(_portrait_left, "", "")
	_set_portrait(_portrait_right, "", "")
	_dialogue_text.text = "【本段结束】%s\n\n按 R 重新播放。\n（后续接日循环：结束后回到 year_hub，推进到下一个时段）\n\n[color=#6E7A88]镜头：%s ｜ 本次缺失素材 %d 张（占位阶段正常，\n按 tools/shotlist.py 生成的拍摄单补齐后归零）[/color]" % [
		str(meta.get("title", "")),
		_shots.current_shot_id,
		_missing_assets,
	]
	_dialogue_text.visible_characters = -1
	_hint_label.visible = false


func _on_faulted(message: String) -> void:
	_typing = false
	set_process(false)
	_clear_choices()
	_choices_box.visible = false
	_dialogue_text.text = "[color=#E0544D]剧本数据错误：%s[/color]" % message
	_dialogue_text.visible_characters = -1
	_hint_label.visible = false


func _on_choice_pressed(index: int) -> void:
	_choices_box.visible = false
	_clear_choices()
	if _engine != null:
		_engine.choose(index)


# ------------------------------------------------------------------ 状态适配器（DialogueEngine ←→ GameState）

func _read_stat(key: String) -> int:
	if key == "rank_index":
		return GameState.rank_index
	if key == "year":
		return GameState.year
	if key.begins_with("favor:"):
		return int(GameState.npc_favors.get(key.substr(6), 40))
	match key:
		"performance": return GameState.performance
		"expertise": return GameState.expertise
		"influence": return GameState.influence
		"reputation": return GameState.reputation
		"mind_load": return GameState.mind_load
		"health": return GameState.health
		"resource": return GameState.resource
	return 0


func _check_flag(flag: String) -> bool:
	return GameState.has_flag(flag)


func _apply_effects(payload: Dictionary) -> Dictionary:
	var deltas: Dictionary = payload.get("deltas", {})
	var npc_effects: Dictionary = payload.get("npc_effects", {})
	var flags_add: Array = payload.get("flags_add", [])
	var flags_remove: Array = payload.get("flags_remove", [])

	GameState.apply_deltas(deltas)
	if not npc_effects.is_empty():
		GameState.apply_npc_effects(npc_effects)
	for flag in flags_add:
		GameState.add_flag(str(flag))
	for flag in flags_remove:
		if GameState.flags.has(str(flag)):
			GameState.flags.erase(str(flag))

	return {
		"deltas": deltas,
		"npc_changes": npc_effects,
		"flags": flags_add,
		"applied": true,
	}


# ------------------------------------------------------------------ 视图工具

func _refresh_time() -> void:
	_time_label.text = "第 %d 年 · Q%d · 周一 · %s" % [
		GameState.year,
		GameState.quarter,
		str(SLOT_NAMES.get(_current_slot, _current_slot)),
	]
	_dock_label.text = _story_title


func _refresh_stats() -> void:
	_stats_label.text = "绩效 %d · 专业 %d · 负荷 %d · 健康 %d" % [
		GameState.performance,
		GameState.expertise,
		GameState.mind_load,
		GameState.health,
	]


func _speaker_name(speaker: String) -> String:
	if speaker == "narrator":
		return ""
	if speaker == "player":
		return "你"
	return str(NPC_STYLE.get(speaker, {}).get("name", speaker))


func _set_portrait(node: PanelContainer, npc_id: String, emotion: String) -> void:
	var name_label: Label = node.get_node("PBox/NameLabel")
	var state_label: Label = node.get_node("PBox/StateLabel")
	if npc_id.is_empty():
		node.visible = false
		name_label.text = ""
		state_label.text = ""
		return
	node.visible = true
	var style: Dictionary = NPC_STYLE.get(npc_id, {})
	name_label.text = str(style.get("name", npc_id))
	state_label.text = str(EMOTION_NAMES.get(emotion, emotion))

	var box := StyleBoxFlat.new()
	box.bg_color = style.get("color", Color(0.2, 0.22, 0.26))
	box.set_corner_radius_all(10)
	box.border_color = Color(1, 1, 1, 0.12)
	box.set_border_width_all(1)
	node.add_theme_stylebox_override("panel", box)


func _dim_portrait(node: PanelContainer, dimmed: bool) -> void:
	if not node.visible:
		return
	node.modulate = Color(1, 1, 1, 0.4) if dimmed else Color(1, 1, 1, 1)


func _finish_typing() -> void:
	_typing = false
	_type_accum = 0.0
	set_process(false)
	_dialogue_text.visible_characters = -1
	_hint_label.visible = true


func _clear_choices() -> void:
	for btn in _choice_buttons:
		if is_instance_valid(btn):
			btn.queue_free()
	_choice_buttons.clear()


func _show_toast(text: String) -> void:
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast.text = text
	_toast.visible = true
	_toast.modulate = Color(1, 1, 1, 1)
	_toast_tween = create_tween()
	_toast_tween.tween_interval(2.4)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.6)
	_toast_tween.tween_callback(func() -> void: _toast.visible = false)
