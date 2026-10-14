class_name ShotDirector
extends Control
## 《打boss》镜头导演（Shot Director）
##
## 把「静态帧 + 引擎动效」这套视觉方案里的"动"部分全部收在这一个类里。
## 它读 data/shots.json（镜头表），按镜头定义驱动分层贴图，
## 用「缩放 + 缩放锚点 + 相机位移」三个量做出推 / 拉 / 摇 / 横移 / 定镜微呼吸。
##
## 为什么不用 Tween：
##   震动（shake）需要每帧叠加随机偏移，而 Tween 会持续写回绝对值，两者会互相打架。
##   手动在 _process 里算一遍插值，逻辑更短也更可控。
##
## 运动学模型（一句话）：
##   屏幕变换 = 以 focus 为锚点缩放 zoom，再整体平移 pan 个屏宽。
##   Godot 的 Control 只有 scale + pivot_offset 两个可写量，两者等价转换：
##       pivot_offset = focus * size + pan * size / (1 - zoom)
##   因为 (1-zoom) 为负，相机右移会让锚点左移 —— 这正是"移动相机"的直觉。
##
## 需求约束（由 tools/shotlist.py 校验，运行时也会 clamp）：
##   zoom >= 1.02，且 |pan| * max_depth <= (zoom - 1) / 2，否则会露出图片边缘。

# ---------------------------------------------------------------- 信号

## 一个镜头开始播放
signal shot_started(shot_id: String, label: String)
## 镜头引用的某个图层图片不存在（零素材阶段会大量出现，属于正常）
signal asset_missing(path: String)
## 镜头表加载失败
signal table_faulted(message: String)

# ---------------------------------------------------------------- 常量

const DEFAULT_TABLE := "res://data/shots.json"
## 最小的过扫倍率。等于 1 会让 (1-zoom) 除零，也会在平移时露边。
const MIN_ZOOM := 1.02
## 切镜淡入时长（秒）
const FADE_IN := 0.28
## 图层名字 → 绘制顺序。列表靠后的画在上面。
const LAYER_ORDER := ["far", "mid", "near", "over"]

# ---------------------------------------------------------------- 状态

## 镜头表原始数据
var table: Dictionary = {}
## shot_id -> { scene: String, shot: Dictionary }
var index: Dictionary = {}
var depth_map: Dictionary = {}

var current_shot_id: String = ""
var current_scene: String = ""

var _layers: Dictionary = {}          # layer_name -> TextureRect
var _tex_cache: Dictionary = {}       # path -> Texture2D 或 null（记录"已确认缺失"）
var _missing_reported: Dictionary = {}

var _clip: VideoStreamPlayer
var _grade: ColorRect
var _flash: ColorRect

var _actors: Array = []               # [{ node: Control, depth: float, base: Vector2, ready: bool }]

var _active := false
var _t := 0.0
var _dir := 1.0
var _dur := 6.0
var _zoom := Vector2(1.08, 1.15)
var _focus := Vector2(0.5, 0.5)
var _pan := [Vector2.ZERO, Vector2.ZERO]
var _shake := 0.0
var _shake_decay := 1.0
var _loop := false
var _fade_t := 1.0
var _flash_t := 0.0

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_children()
	resized.connect(_on_resized)
	if not load_table(DEFAULT_TABLE):
		table_faulted.emit("镜头表加载失败：%s" % DEFAULT_TABLE)
	set_process(true)


# ---------------------------------------------------------------- 建图层

func _build_children() -> void:
	for layer_name in LAYER_ORDER:
		var tr := TextureRect.new()
		tr.name = "L_" + layer_name
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.visible = false
		tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(tr)
		_layers[layer_name] = tr

	_clip = VideoStreamPlayer.new()
	_clip.name = "Clip"
	_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clip.expand = true
	_clip.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_clip.visible = false
	_clip.finished.connect(_on_clip_finished)
	add_child(_clip)

	_grade = ColorRect.new()
	_grade.name = "Grade"
	_grade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grade.color = Color(0, 0, 0, 0)
	_grade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_grade)

	_flash = ColorRect.new()
	_flash.name = "Flash"
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.color = Color(1, 1, 1, 0)
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_flash)


# ---------------------------------------------------------------- 加载镜头表

func load_table(path: String = DEFAULT_TABLE) -> bool:
	if not FileAccess.file_exists(path):
		push_error("[ShotDirector] 镜头表不存在: %s" % path)
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("[ShotDirector] 无法打开镜头表: %s" % path)
		return false
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("[ShotDirector] 镜头表根节点必须是对象")
		return false

	table = parsed
	index.clear()
	depth_map = table.get("depth", {"far": 0.22, "mid": 0.5, "near": 0.8, "over": 1.0})

	var scenes: Dictionary = table.get("scenes", {})
	for scene_id in scenes.keys():
		var scene: Dictionary = scenes[scene_id]
		var shots: Dictionary = scene.get("shots", {})
		for shot_id in shots.keys():
			if index.has(shot_id):
				push_warning("[ShotDirector] 镜头 id 重复：%s" % shot_id)
			index[shot_id] = {"scene": scene_id, "shot": shots[shot_id]}
	return true


# ---------------------------------------------------------------- 外部注册（视差参与者）

## 把外部节点注册为「视差参与者」。立绘容器、前景 UI 装饰都可以挂进来。
## depth 越大，随相机移动得越多（越靠近镜头）。
func register_actor(node: Control, depth: float = 0.6) -> void:
	if node == null:
		return
	for rec in _actors:
		if rec["node"] == node:
			rec["depth"] = depth
			return
	_actors.append({"node": node, "depth": depth, "base": Vector2.ZERO, "ready": false})
	call_deferred("_capture_actor_bases")


func unregister_actor(node: Control) -> void:
	if node == null:
		return
	for i in range(_actors.size() - 1, -1, -1):
		if _actors[i]["node"] == node:
			_actors.remove_at(i)


func _capture_actor_bases() -> void:
	for rec in _actors:
		var n: Control = rec["node"]
		if is_instance_valid(n):
			rec["base"] = n.position
			rec["ready"] = true


func _on_resized() -> void:
	_capture_actor_bases()
	# 尺寸变化后立刻按当前进度重画一帧，避免停在错位的画面上
	if _active:
		_apply_frame(_current_zoom(), _current_pan(), _shake)


# ---------------------------------------------------------------- 播放

## 播放一个镜头。返回是否成功命中镜头表。
## skip_cut = true 时不重放切镜/淡入（用于同一镜头内续播）
func play_shot(shot_id: String, skip_cut: bool = false) -> bool:
	if shot_id.is_empty():
		return false
	if not index.has(shot_id):
		push_warning("[ShotDirector] 镜头表中不存在：%s" % shot_id)
		return false
	var entry: Dictionary = index[shot_id]
	var shot: Dictionary = entry["shot"]
	current_shot_id = shot_id
	current_scene = str(entry["scene"])

	_dur = maxf(0.1, float(shot.get("dur", 6.0)))
	_zoom = _as_vec2(shot.get("zoom", [1.08, 1.15]))
	_zoom.x = maxf(MIN_ZOOM, _zoom.x)
	_zoom.y = maxf(MIN_ZOOM, _zoom.y)
	_focus = _as_vec2(shot.get("focus", [0.5, 0.5]))
	_pan = _as_pan(shot.get("pan", [[0.0, 0.0], [0.0, 0.0]]))
	_shake = float(shot.get("shake", 0.0))
	_loop = bool(shot.get("loop", false))
	_t = 0.0
	_dir = 1.0
	_active = true

	_apply_grade(shot.get("grade", []))
	_play_clip_or_stills(shot, skip_cut)
	shot_started.emit(shot_id, str(shot.get("label", shot_id)))
	return true


## 进入某个场景的定场镜头
func play_scene_entry(scene_id: String) -> bool:
	if current_scene == scene_id and _active:
		return true
	var scenes: Dictionary = table.get("scenes", {})
	if not scenes.has(scene_id):
		push_warning("[ShotDirector] 镜头表未登记场景：%s" % scene_id)
		current_scene = scene_id
		return false
	var scene: Dictionary = scenes[scene_id]
	var entry_id := str(scene.get("entry", ""))
	if entry_id.is_empty():
		var shots: Dictionary = scene.get("shots", {})
		if shots.is_empty():
			return false
		entry_id = str(shots.keys()[0])
	return play_shot(entry_id)


## 反打：按说话人所在侧切到对应机位。场景未配 reverse 时**保持当前镜头不动**
## —— 旁白与无配对机位的情况都不应该乱切镜头。
func play_reverse(side: String) -> bool:
	if side != "left" and side != "right":
		return false
	var scenes: Dictionary = table.get("scenes", {})
	if not scenes.has(current_scene):
		return false
	var reverse: Dictionary = scenes[current_scene].get("reverse", {})
	var shot_id := str(reverse.get(side, ""))
	if shot_id.is_empty():
		return false
	if shot_id == current_shot_id and _active:
		return true
	return play_shot(shot_id)


func stop() -> void:
	_active = false
	if _clip != null and _clip.playing:
		_clip.stop()


# ---------------------------------------------------------------- 每帧驱动

func _process(delta: float) -> void:
	# 淡入 / 闪白即使镜头已停也要收尾
	if _fade_t < 1.0:
		_fade_t = minf(1.0, _fade_t + delta / FADE_IN)
		_apply_fade()
	if _flash_t > 0.0:
		_flash_t = maxf(0.0, _flash_t - delta / 0.35)
		_flash.color = Color(1.0, 1.0, 1.0, _flash_t * 0.55)

	if not _active:
		return

	_t += delta * _dir
	if _loop:
		if _t >= _dur:
			_t = _dur
			_dir = -1.0
		elif _t <= 0.0:
			_t = 0.0
			_dir = 1.0
	else:
		_t = minf(_t, _dur)

	var shake_now := _shake * maxf(0.0, 1.0 - _t / _dur)
	_apply_frame(_current_zoom(), _current_pan(), shake_now)

	if not _loop and _t >= _dur:
		_shake = 0.0


func _current_zoom() -> float:
	# 用 smoothstep 做缓入缓出。线性推拉会有"机器感"。
	var k := _dur if _dur > 0.0 else 1.0
	var u := clampf(_t / k, 0.0, 1.0)
	var e := u * u * (3.0 - 2.0 * u)
	return lerpf(_zoom.x, _zoom.y, e)


func _current_pan() -> Vector2:
	var k := _dur if _dur > 0.0 else 1.0
	var u := clampf(_t / k, 0.0, 1.0)
	var e := u * u * (3.0 - 2.0 * u)
	return _pan[0].lerp(_pan[1], e)


## 把「缩放 / 锚点 / 相机位移」写进每个可见图层，并同步视差参与者
func _apply_frame(z: float, pan: Vector2, shake_px: float) -> void:
	z = maxf(MIN_ZOOM, z)
	var denom := 1.0 - z                      # 必然为负
	var shake_off := Vector2.ZERO
	if shake_px > 0.0:
		shake_off = Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)) * shake_px

	for layer_name in _layers.keys():
		var node: TextureRect = _layers[layer_name]
		if not node.visible:
			continue
		var dep := float(depth_map.get(layer_name, 0.5))
		var pan_layer := pan * dep
		var pivot := Vector2(
			_focus.x * size.x + (pan_layer.x * size.x + shake_off.x) / denom,
			_focus.y * size.y + (pan_layer.y * size.y + shake_off.y) / denom,
		)
		node.scale = Vector2(z, z)
		node.pivot_offset = pivot

	for rec in _actors:
		var n: Control = rec["node"]
		if not is_instance_valid(n):
			continue
		if not bool(rec["ready"]):
			rec["base"] = n.position
			rec["ready"] = true
		var dep2 := float(rec["depth"])
		var off := Vector2(pan.x * size.x, pan.y * size.y) * dep2 + shake_off
		n.position = Vector2(rec["base"]) + off


# ---------------------------------------------------------------- 图层与素材

func _play_clip_or_stills(shot: Dictionary, skip_cut: bool) -> void:
	var clip_path := str(shot.get("clip", ""))
	if not clip_path.is_empty() and ResourceLoader.exists(clip_path):
		var stream = load(clip_path)
		if stream != null:
			_hide_stills()
			_clip.stream = stream
			_clip.visible = true
			_clip.play()
			_fade_t = 1.0
			return

	# 无视频（或视频还没做）→ 退回静态分层。这一步是整条流水线的保险丝：
	# 视频层可以后期一条条补，补之前游戏完全可用。
	if _clip.playing:
		_clip.stop()
	_clip.visible = false

	var layers: Dictionary = shot.get("layers", {})
	var any_visible := false
	for layer_name in _layers.keys():
		var node: TextureRect = _layers[layer_name]
		if not layers.has(layer_name):
			node.visible = false
			continue
		var tex := _load_texture(str(layers[layer_name]))
		if tex == null:
			node.visible = false
			continue
		node.texture = tex
		node.visible = true
		any_visible = true

	# 缺图时不黑屏：保留上一帧，方便零素材阶段调演出
	if not any_visible:
		return

	_fade_t = 1.0 if skip_cut else 0.0
	var cut := str(shot.get("cut", "cut"))
	if cut == "flash":
		_flash_t = 1.0
	if cut != "fade":
		_fade_t = 1.0
	_apply_fade()


func _hide_stills() -> void:
	for layer_name in _layers.keys():
		(_layers[layer_name] as TextureRect).visible = false


func _apply_fade() -> void:
	var a := _fade_t
	if _clip.visible:
		_clip.modulate = Color(1, 1, 1, a)
	for layer_name in _layers.keys():
		var node: TextureRect = _layers[layer_name]
		if node.visible:
			node.modulate = Color(1, 1, 1, a)


func _load_texture(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if _tex_cache.has(path):
		return _tex_cache[path]
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		var res = load(path)
		if res is Texture2D:
			tex = res
	if tex == null and not _missing_reported.has(path):
		_missing_reported[path] = true
		asset_missing.emit(path)
	_tex_cache[path] = tex
	return tex


func _on_clip_finished() -> void:
	# 视频播完停在最后一帧上：切回该镜头的静态版，避免回到黑屏
	if current_shot_id.is_empty() or not index.has(current_shot_id):
		return
	var shot: Dictionary = index[current_shot_id]["shot"]
	_t = _dur
	_play_clip_or_stills(_copy_without_clip(shot), true)


func _copy_without_clip(shot: Dictionary) -> Dictionary:
	var d := shot.duplicate(true)
	d["clip"] = ""
	return d


func _apply_grade(grade: Variant) -> void:
	if typeof(grade) != TYPE_ARRAY or grade.size() < 2:
		_grade.color = Color(0, 0, 0, 0)
		return
	var hex := str(grade[0])
	var alpha := clampf(float(grade[1]), 0.0, 1.0)
	var c := Color.from_string(hex, Color(0.04, 0.05, 0.07))
	c.a = alpha
	_grade.color = c


# ---------------------------------------------------------------- 工具

func _as_vec2(v: Variant) -> Vector2:
	if typeof(v) == TYPE_ARRAY and v.size() >= 2:
		return Vector2(float(v[0]), float(v[1]))
	return Vector2(0.5, 0.5)


func _as_pan(v: Variant) -> Array:
	if typeof(v) == TYPE_ARRAY and v.size() >= 2:
		return [_as_vec2(v[0]), _as_vec2(v[1])]
	return [Vector2.ZERO, Vector2.ZERO]


## 供调试面板 / 自动化测试读取
func debug_state() -> Dictionary:
	return {
		"shot": current_shot_id,
		"scene": current_scene,
		"t": _t,
		"dur": _dur,
		"zoom": _current_zoom(),
		"pan": _current_pan(),
		"active": _active,
		"clip": _clip.visible,
		"visible_layers": _visible_layer_names(),
	}


func _visible_layer_names() -> Array:
	var out: Array = []
	for layer_name in _layers.keys():
		if (_layers[layer_name] as TextureRect).visible:
			out.append(layer_name)
	return out
