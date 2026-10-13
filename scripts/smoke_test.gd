extends SceneTree
## 《打boss》无头冒烟测试（M1 数值 + M2 日历 + 事件加载 + 存读档）
## Run: godot --path <project> --headless --script res://scripts/smoke_test.gd
## Note: --script 时用 /root/GameState，勿直接写全局标识符。

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("[smoke] start 《打boss》")

	var gs: Node = root.get_node_or_null("GameState")
	if gs == null:
		_finish(false, "GameState autoload missing at /root/GameState")
		return

	## —— M1：初始值 ——
	gs.call("new_game", 0)  # Mode.NORMAL = 0
	if int(gs.get("performance")) != 40 or int(gs.get("expertise")) != 35 \
			or int(gs.get("influence")) != 20 or int(gs.get("reputation")) != 25 \
			or int(gs.get("mind_load")) != 0 or int(gs.get("health")) != 80 \
			or int(gs.get("resource")) != 3000:
		_finish(false, "M1 new_game initial stats mismatch")
		return
	if str(gs.get("job_title")) != "实习生":
		_finish(false, "M1 rank title expected 实习生")
		return
	var favors: Dictionary = gs.get("npc_favors")
	if int(favors.get("tang_poxiao", 0)) != 45 or int(favors.get("ji_heng", 0)) != 35:
		_finish(false, "M1 npc default favors mismatch")
		return
	print("[smoke] M1 new_game OK")

	## —— M1：apply_deltas clamp ——
	gs.call("apply_deltas", {
		"performance": 200,
		"resource": -999999,
		"mind_load": 50,
		"health": -10,
	})
	if int(gs.get("performance")) != 100:
		_finish(false, "M1 performance should clamp to 100")
		return
	if int(gs.get("resource")) != 0:
		_finish(false, "M1 resource should floor at 0")
		return
	if int(gs.get("mind_load")) != 50:
		_finish(false, "M1 mind_load apply failed")
		return
	if int(gs.get("health")) != 70:
		_finish(false, "M1 health apply failed")
		return
	print("[smoke] M1 apply_deltas clamp OK")

	## —— M2：推进 12 周跨年 ——
	gs.call("new_game", 0)
	for i in range(12):
		gs.call("advance_week")
	if int(gs.get("year")) != 2 or int(gs.get("quarter")) != 1 or int(gs.get("week")) != 1:
		_finish(false, "M2 after 12 weeks expected Y2Q1W1 got Y%dQ%dW%d" % [
			gs.get("year"), gs.get("quarter"), gs.get("week")
		])
		return
	## 年末 health +10（初始 80 → 不超过 100）
	if int(gs.get("health")) < 80:
		_finish(false, "M2 year-end health should recover, got %d" % gs.get("health"))
		return
	print("[smoke] M2 calendar OK year=%d" % gs.get("year"))

	## —— 事件加载 ——
	var loader = load("res://scripts/event_loader.gd")
	if loader == null:
		_finish(false, "failed to load event_loader.gd")
		return
	var events: Array = loader.load_events()
	if events.size() < 10:
		_finish(false, "events too few: %d" % events.size())
		return
	for e in events:
		var title := str(e.get("title", ""))
		if title.is_empty() or title.find("\ufffd") >= 0:
			_finish(false, "bad event title: %s" % e.get("id", "?"))
			return
		var choices: Array = e.get("choices", [])
		if choices.size() < 2:
			_finish(false, "event needs >=2 choices: %s" % e.get("id", "?"))
			return
	var picked: Dictionary = loader.pick_weighted(events, 0, 0, [])
	if picked.is_empty():
		_finish(false, "pick_weighted returned empty")
		return
	print("[smoke] events loaded=%d sample=%s" % [events.size(), picked.get("id", "")])

	## —— 结算一轮事件效果 ——
	gs.call("new_game", 1)  # REWIND
	var choice0: Dictionary = events[0].get("choices", [{}])[0]
	gs.call("apply_deltas", choice0.get("effects", {}))
	gs.call("apply_npc_effects", choice0.get("npc_effects", {}))
	print("[smoke] sample settle rank=%s perf=%d mind=%d" % [
		gs.get("job_title"), gs.get("performance"), gs.get("mind_load")
	])

	## —— 存读档 roundtrip ——
	var snap := {
		"performance": int(gs.get("performance")),
		"expertise": int(gs.get("expertise")),
		"influence": int(gs.get("influence")),
		"reputation": int(gs.get("reputation")),
		"mind_load": int(gs.get("mind_load")),
		"health": int(gs.get("health")),
		"resource": int(gs.get("resource")),
		"rank_index": int(gs.get("rank_index")),
		"year": int(gs.get("year")),
		"quarter": int(gs.get("quarter")),
		"week": int(gs.get("week")),
		"mode": int(gs.get("mode")),
	}
	if not bool(gs.call("save_game")):
		_finish(false, "save_game failed")
		return
	gs.set("performance", 1)
	gs.set("resource", 1)
	if not bool(gs.call("load_game")):
		_finish(false, "load_game failed")
		return
	for k in snap.keys():
		if int(gs.get(k)) != int(snap[k]):
			_finish(false, "save/load mismatch on %s: got %s want %s" % [k, gs.get(k), snap[k]])
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
