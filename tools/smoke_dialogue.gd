extends SceneTree
## Headless smoke: load evt_01_weekly_report via DialogueEngine and advance/choose to finished.
## Usage: Godot --headless --path . --script res://tools/smoke_dialogue.gd

const STORY_PATH := "res://data/story/evt_01_weekly_report.json"
const MAX_ACTIONS := 200

var _eng: DialogueEngine
var _lines := 0
var _choices := 0
var _effects := 0
var _shots := 0
var _scenes := 0
var _fail_msg := ""
var _stats := {
	"performance": 40,
	"expertise": 35,
	"influence": 20,
	"reputation": 25,
	"mind_load": 0,
	"health": 80,
	"resource": 3000,
	"rank_index": 0,
	"year": 1,
}
var _flags: Array = []
var _favors := {
	"shen_tinglan": 40,
	"ji_heng": 35,
	"you_wanxing": 40,
	"tang_poxiao": 45,
	"liang_xu": 40,
}


func _initialize() -> void:
	print("[smoke] Dialogue AVG headless smoke starting...")
	_eng = DialogueEngine.new()
	_eng.stat_getter = Callable(self, "_read_stat")
	_eng.flag_checker = Callable(self, "_check_flag")
	_eng.effect_applier = Callable(self, "_apply_effects")

	_eng.line_shown.connect(func(_s, _t, _e, _side): _lines += 1)
	_eng.choices_offered.connect(func(_p, _o): _choices += 1)
	_eng.effects_applied.connect(func(_sum): _effects += 1)
	_eng.shot_requested.connect(func(_id, _p): _shots += 1)
	_eng.scene_changed.connect(func(_sc, _sl): _scenes += 1)
	_eng.finished.connect(func(_nid, meta):
		print("[smoke] finished meta=%s" % str(meta))
	)
	_eng.faulted.connect(func(msg):
		_fail_msg = msg
		print("[smoke] FAULTED: %s" % msg)
	)

	var story := DialogueEngine.load_story(STORY_PATH)
	if story.is_empty():
		printerr("[smoke] FAIL: could not load %s" % STORY_PATH)
		quit(2)
		return
	if not _eng.start(story):
		printerr("[smoke] FAIL: start returned false / fault=%s" % _eng.fault_message)
		quit(3)
		return

	var actions := 0
	while actions < MAX_ACTIONS and not _eng.is_finished() and not _eng.has_faulted():
		actions += 1
		if _eng.is_waiting_line():
			_eng.advance()
		elif _eng.is_waiting_choice():
			var n: int = _eng._pending_choices.size()
			var pick := 1 if n > 1 else 0
			print("[smoke] choose index=%d of %d" % [pick, n])
			_eng.choose(pick)
		else:
			printerr("[smoke] FAIL: idle wait_state=%s current=%s" % [_eng.wait_state, _eng.current_id])
			quit(4)
			return

	if _eng.has_faulted():
		printerr("[smoke] FAIL: faulted after %d actions: %s" % [actions, _fail_msg])
		quit(5)
		return
	if not _eng.is_finished():
		printerr("[smoke] FAIL: not finished after %d actions (current=%s)" % [actions, _eng.current_id])
		quit(6)
		return

	print("[smoke] PASS actions=%d lines=%d choices=%d effects=%d shots=%d scenes=%d" % [
		actions, _lines, _choices, _effects, _shots, _scenes
	])
	print("[smoke] stub_stats perf=%d exp=%d mind=%d health=%d flags=%s" % [
		int(_stats["performance"]), int(_stats["expertise"]),
		int(_stats["mind_load"]), int(_stats["health"]), str(_flags)
	])
	quit(0)


func _read_stat(key: String) -> int:
	if key.begins_with("favor:"):
		return int(_favors.get(key.substr(6), 40))
	return int(_stats.get(key, 0))


func _check_flag(flag: String) -> bool:
	return _flags.has(flag)


func _apply_effects(payload: Dictionary) -> Dictionary:
	var deltas: Dictionary = payload.get("deltas", {})
	for k in deltas.keys():
		if _stats.has(k):
			_stats[k] = int(_stats[k]) + int(deltas[k])
	var npc_effects: Dictionary = payload.get("npc_effects", {})
	for npc_id in npc_effects.keys():
		var cur := int(_favors.get(npc_id, 40))
		_favors[npc_id] = clampi(cur + int(npc_effects[npc_id]), 0, 100)
	for flag in payload.get("flags_add", []):
		var fs := str(flag)
		if not _flags.has(fs):
			_flags.append(fs)
	for flag in payload.get("flags_remove", []):
		var fr := str(flag)
		if _flags.has(fr):
			_flags.erase(fr)
	return {
		"deltas": deltas,
		"npc_changes": npc_effects,
		"flags": payload.get("flags_add", []),
		"applied": true,
	}