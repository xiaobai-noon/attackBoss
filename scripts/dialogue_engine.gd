class_name DialogueEngine
extends RefCounted
## 《打boss》对话图执行器（Dialogue Graph VM）
##
## 设计原则：本类**不引用** GameState / EventBus / 任何 UI 节点。
## 状态读写通过宿主动态注入的 Callable 完成，因此可以在 --headless 下单独测试。
##
## 节点类型：bg | shot | line | choice | effect | branch | goto | end
##
## shot 节点 = 喊一个镜头（见 data/shots.json + scripts/shot_director.gd）。
## 它是**非阻塞**的：发完信号立刻顺延，表现为层在动，台词照常打字。
## 需要"等这一镜头演完"时不要用 wait，直接紧跟一个 line 节点——台词本身就是节拍器。
##
## 宿主接入示例（见 scenes/dialogue_screen.gd）：
##   var eng := DialogueEngine.new()
##   eng.stat_getter  = func(key: String) -> int: return GameState.get_stat(key)
##   eng.flag_checker = func(flag: String) -> bool: return GameState.has_flag(flag)
##   eng.effect_applier = func(payload: Dictionary) -> Dictionary: return GameState.apply_story_effects(payload)
##   eng.line_shown.connect(_render_line)
##   eng.start(DialogueEngine.load_story("res://data/story/xxx.json"))
##
## 驱动方式（由表现层调用）：
##   eng.advance()      # 玩家点击/按键，推进到下一句
##   eng.choose(index)  # 玩家选择第 index 个选项

# ---------------------------------------------------------------- 信号

## 需要显示一句台词（表现层渲染后等待 advance()）
signal line_shown(speaker: String, text: String, emotion: String, side: String)
## 场景/时段切换（表现层换背景图与光照）
signal scene_changed(scene_id: String, slot: String)
## 请求切镜头（表现层交给 ShotDirector 播）
signal shot_requested(shot_id: String, params: Dictionary)
## 抛出选项（表现层生成按钮，等待 choose(index)）
signal choices_offered(prompt: String, options: Array)
## 一次数值结算完成（表现层飘字提示）
signal effects_applied(summary: Dictionary)
## 剧本结束
signal finished(node_id: String, meta: Dictionary)
## 数据错误（表现层显示红色提示，便于作者定位）
signal faulted(message: String)

# ---------------------------------------------------------------- 常量

const TYPE_BG := "bg"
const TYPE_SHOT := "shot"
const TYPE_LINE := "line"
const TYPE_CHOICE := "choice"
const TYPE_EFFECT := "effect"
const TYPE_BRANCH := "branch"
const TYPE_GOTO := "goto"
const TYPE_END := "end"

const WAIT_NONE := ""
const WAIT_LINE := "line"
const WAIT_CHOICE := "choice"
const WAIT_FAULT := "fault"

## 单次 resume 允许执行的最大节点数，用于捕获数据层面的死循环
const MAX_STEPS_PER_RESUME := 256

# ---------------------------------------------------------------- 状态适配器（宿主注入）

## func(key: String) -> int
## key 可以是七维之一（performance/expertise/...），或 "rank_index" / "year"，或 "favor:<npc_id>"
var stat_getter: Callable = Callable()
## func(flag: String) -> bool
var flag_checker: Callable = Callable()
## func(payload: Dictionary) -> Dictionary
##   payload = { deltas, npc_effects, flags_add, flags_remove, node_id }
##   return  = { deltas, npc_changes, flags, applied }   —— 仅用于 UI 显示
var effect_applier: Callable = Callable()

# ---------------------------------------------------------------- 运行态

var story_id: String = ""
var title: String = ""
var nodes: Dictionary = {}
var current_id: String = ""
var wait_state: String = WAIT_NONE
var fault_message: String = ""

var _node: Dictionary = {}
var _pending_choices: Array = []
var _finished: bool = false

# ---------------------------------------------------------------- 加载

## 从磁盘读取剧本 JSON；失败返回空字典并 push_error
static func load_story(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("剧本文件不存在: %s" % path)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("无法打开剧本: %s" % path)
		return {}
	var text := file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("剧本 JSON 根节点应为对象: %s" % path)
		return {}
	return parsed

# ---------------------------------------------------------------- 生命周期

## 开始播放一份剧本；返回是否成功启动
func start(story: Dictionary) -> bool:
	if story.is_empty():
		return _fault("剧本为空")
	if typeof(story.get("nodes")) != TYPE_DICTIONARY:
		return _fault("剧本缺少 nodes 字段")
	story_id = str(story.get("id", ""))
	title = str(story.get("title", ""))
	nodes = story["nodes"]
	_finished = false
	wait_state = WAIT_NONE
	fault_message = ""
	_pending_choices = []
	current_id = str(story.get("entry", ""))
	if current_id.is_empty() or not nodes.has(current_id):
		return _fault("entry 节点不存在或未指定: 「%s」" % current_id)
	_resume()
	return wait_state != WAIT_FAULT

## 玩家点击 / 按键：推进到下一句
func advance() -> void:
	if wait_state != WAIT_LINE:
		return
	wait_state = WAIT_NONE
	_step_next()
	_resume()

## 玩家选择第 index 个选项
func choose(index: int) -> void:
	if wait_state != WAIT_CHOICE:
		return
	if index < 0 or index >= _pending_choices.size():
		return
	var option: Dictionary = _pending_choices[index]
	wait_state = WAIT_NONE
	_pending_choices = []

	## 选项可内联结算（等价于紧跟一个 effect 节点）
	if option.has("deltas") or option.has("npc_effects") or option.has("flags_add"):
		var summary := _apply_effects({
			"deltas": option.get("deltas", {}),
			"npc_effects": option.get("npc_effects", {}),
			"flags_add": option.get("flags_add", []),
			"flags_remove": option.get("flags_remove", []),
			"node_id": current_id,
		})
		effects_applied.emit(summary)

	var target := str(option.get("goto", ""))
	if target.is_empty():
		_end_story()
		return
	current_id = target
	_resume()

# ---------------------------------------------------------------- 查询

func is_waiting_line() -> bool:
	return wait_state == WAIT_LINE

func is_waiting_choice() -> bool:
	return wait_state == WAIT_CHOICE

func is_finished() -> bool:
	return _finished

func has_faulted() -> bool:
	return wait_state == WAIT_FAULT

# ---------------------------------------------------------------- 主循环

func _resume() -> void:
	var steps := 0
	while true:
		if _finished or wait_state != WAIT_NONE:
			return
		steps += 1
		if steps > MAX_STEPS_PER_RESUME:
			_fault("对话图疑似死循环，已中断（停在节点 %s）" % current_id)
			return
		if not nodes.has(current_id):
			_fault("节点不存在: 「%s」" % current_id)
			return
		_node = nodes[current_id]
		if typeof(_node) != TYPE_DICTIONARY:
			_fault("节点不是对象: 「%s」" % current_id)
			return
		var node_type := str(_node.get("type", ""))
		match node_type:
			TYPE_BG:
				_do_bg()
			TYPE_SHOT:
				_do_shot()
			TYPE_LINE:
				_do_line()
				return
			TYPE_CHOICE:
				_do_choice()
				return
			TYPE_EFFECT:
				_do_effect()
			TYPE_BRANCH:
				_do_branch()
			TYPE_GOTO:
				_do_goto()
			TYPE_END:
				_end_story()
				return
			_:
				_fault("未知节点类型「%s」@ %s" % [node_type, current_id])
				return

# ---------------------------------------------------------------- 各节点实现

func _do_bg() -> void:
	scene_changed.emit(str(_node.get("scene", "")), str(_node.get("slot", "")))
	_step_next()

## 切镜头。非阻塞：喊完就顺延，镜头在背景层自己演。
## 可选 params（透传给 ShotDirector）：
##   { "hold_until": 1.2 }  之类的调参留口，当前实现只用 shot_id
func _do_shot() -> void:
	var shot_id := str(_node.get("shot", ""))
	if shot_id.is_empty():
		push_warning("[DialogueEngine] shot 节点缺少 shot 字段 @ %s" % current_id)
	else:
		shot_requested.emit(shot_id, _node.get("params", {}))
	_step_next()

func _do_line() -> void:
	line_shown.emit(
		str(_node.get("speaker", "narrator")),
		str(_node.get("text", "")),
		str(_node.get("emotion", "neutral")),
		str(_node.get("side", "left")),
	)
	wait_state = WAIT_LINE

func _do_choice() -> void:
	var raw: Array = _node.get("options", [])
	_pending_choices = []
	for item in raw:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var show_if = item.get("show_if", {})
		if typeof(show_if) == TYPE_DICTIONARY and not show_if.is_empty():
			if not _eval_condition(show_if):
				continue
		_pending_choices.append(item)
	if _pending_choices.is_empty():
		_fault("选项全部被条件过滤，无路可走 @ %s" % current_id)
		return
	wait_state = WAIT_CHOICE
	choices_offered.emit(str(_node.get("prompt", "")), _pending_choices.duplicate())

func _do_effect() -> void:
	var summary := _apply_effects({
		"deltas": _node.get("deltas", {}),
		"npc_effects": _node.get("npc_effects", {}),
		"flags_add": _node.get("flags_add", []),
		"flags_remove": _node.get("flags_remove", []),
		"node_id": current_id,
	})
	effects_applied.emit(summary)
	_step_next()

func _do_branch() -> void:
	for cond in _node.get("conditions", []):
		if typeof(cond) != TYPE_DICTIONARY:
			continue
		if _eval_condition(cond):
			var target := str(cond.get("goto", ""))
			if target.is_empty():
				_end_story()
				return
			current_id = target
			return
	var fallback := str(_node.get("default", ""))
	if fallback.is_empty():
		_end_story()
		return
	current_id = fallback

func _do_goto() -> void:
	var target := str(_node.get("goto", ""))
	if target.is_empty():
		_end_story()
		return
	current_id = target

func _end_story() -> void:
	_finished = true
	wait_state = WAIT_NONE
	finished.emit(current_id, {
		"story_id": story_id,
		"title": title,
		"ending": str(_node.get("ending", "")),
	})

# ---------------------------------------------------------------- 工具

## 顺延到 next；无 next 视为剧本结束
func _step_next() -> void:
	var nxt := str(_node.get("next", ""))
	if nxt.is_empty():
		_end_story()
	else:
		current_id = nxt

func _apply_effects(payload: Dictionary) -> Dictionary:
	if effect_applier.is_valid():
		var result = effect_applier.call(payload)
		if typeof(result) == TYPE_DICTIONARY:
			return result
	return {
		"deltas": payload.get("deltas", {}),
		"npc_changes": payload.get("npc_effects", {}),
		"flags": payload.get("flags_add", []),
		"applied": false,
	}

## 条件表达式：同一对象内多个键为「逻辑与」
##   { "stat": "mind_load", "op": ">=", "value": 70 }
##   { "favor": "shen_tinglan", "op": ">=", "value": 60 }
##   { "flag": "reform_seed" }
func _eval_condition(cond: Dictionary) -> bool:
	if cond.has("flag"):
		if not _check_flag(str(cond["flag"])):
			return false
	if cond.has("stat"):
		var op := str(cond.get("op", ">="))
		if not _compare(_read_stat(str(cond["stat"])), op, int(cond.get("value", 0))):
			return false
	if cond.has("favor"):
		var op2 := str(cond.get("op", ">="))
		if not _compare(_read_stat("favor:" + str(cond["favor"])), op2, int(cond.get("value", 0))):
			return false
	return true

func _read_stat(key: String) -> int:
	if stat_getter.is_valid():
		return int(stat_getter.call(key))
	return 0

func _check_flag(flag: String) -> bool:
	if flag_checker.is_valid():
		return bool(flag_checker.call(flag))
	return false

func _compare(a: int, op: String, b: int) -> bool:
	match op:
		">=": return a >= b
		">": return a > b
		"<=": return a <= b
		"<": return a < b
		"==": return a == b
		"!=": return a != b
	return false

func _fault(message: String) -> bool:
	fault_message = message
	wait_state = WAIT_FAULT
	push_error("[DialogueEngine] %s" % message)
	faulted.emit(message)
	return false
