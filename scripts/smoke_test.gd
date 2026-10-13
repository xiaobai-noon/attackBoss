extends SceneTree
## Headless smoke test for AttackBoss.
## Run: Godot --path <project> --headless --script res://scripts/smoke_test.gd
## Note: --script compiles before autoload identifiers are registered, so access
## GameState via /root/GameState after the tree is ready.

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ok := true
	var err_msg := ""
	print("[smoke] start")

	var gs: Node = root.get_node_or_null("GameState")
	if gs == null:
		ok = false
		err_msg = "GameState autoload missing at /root/GameState"
		_finish(ok, err_msg)
		return

	var events: Array = []
	var loader = load("res://scripts/event_loader.gd")
	if loader == null:
		ok = false
		err_msg = "failed to load event_loader.gd"
		_finish(ok, err_msg)
		return

	events = loader.load_events()
	if events.is_empty():
		ok = false
		err_msg = "events empty"
		_finish(ok, err_msg)
		return

	print("[smoke] loaded %d events" % events.size())
	for e in events:
		var title := str(e.get("title", ""))
		if title.is_empty() or title.find("\ufffd") >= 0:
			ok = false
			err_msg = "bad event title: %s" % e.get("id", "?")
			_finish(ok, err_msg)
			return
		print("[smoke] event %s -> %s" % [e.get("id", ""), title])

	gs.call("new_game")
	print("[smoke] new_game day=%d rank=%s skill=%d network=%d stress=%d money=%d" % [
		gs.get("day"), gs.get("job_title"), gs.get("skill"), gs.get("network"), gs.get("stress"), gs.get("money")
	])

	for i in range(3):
		var ev: Dictionary = events[randi() % events.size()]
		var choices: Array = ev.get("choices", [])
		if choices.is_empty():
			ok = false
			err_msg = "event has no choices: %s" % ev.get("id", "")
			_finish(ok, err_msg)
			return
		var effects: Dictionary = choices[0].get("effects", {})
		gs.call("apply_deltas", effects)
		var promoted: bool = bool(gs.call("try_promote"))
		print("[smoke] day=%d event=%s choice0 effects=%s promoted=%s rank=%s stats={skill:%d,network:%d,stress:%d,money:%d}" % [
			gs.get("day"), ev.get("id", ""), str(effects), str(promoted), gs.get("job_title"),
			gs.get("skill"), gs.get("network"), gs.get("stress"), gs.get("money")
		])
		gs.call("advance_day")

	var snap_skill: int = int(gs.get("skill"))
	var snap_network: int = int(gs.get("network"))
	var snap_stress: int = int(gs.get("stress"))
	var snap_money: int = int(gs.get("money"))
	var snap_day: int = int(gs.get("day"))
	var snap_rank: int = int(gs.get("rank_index"))

	if not bool(gs.call("save_game")):
		ok = false
		err_msg = "save_game failed"
		_finish(ok, err_msg)
		return

	gs.set("skill", -1)
	gs.set("network", -1)
	if not bool(gs.call("load_game")):
		ok = false
		err_msg = "load_game failed"
		_finish(ok, err_msg)
		return

	if int(gs.get("skill")) != snap_skill or int(gs.get("network")) != snap_network \
			or int(gs.get("stress")) != snap_stress or int(gs.get("money")) != snap_money \
			or int(gs.get("day")) != snap_day or int(gs.get("rank_index")) != snap_rank:
		ok = false
		err_msg = "save/load mismatch: got skill=%d network=%d stress=%d money=%d day=%d rank=%d" % [
			gs.get("skill"), gs.get("network"), gs.get("stress"), gs.get("money"), gs.get("day"), gs.get("rank_index")
		]
		_finish(ok, err_msg)
		return

	print("[smoke] save/load roundtrip OK")
	_finish(true, "")


func _finish(ok: bool, err_msg: String) -> void:
	if ok:
		print("[smoke] SUCCESS")
		quit(0)
	else:
		push_error("[smoke] FAIL: %s" % err_msg)
		print("[smoke] FAIL: %s" % err_msg)
		quit(1)
