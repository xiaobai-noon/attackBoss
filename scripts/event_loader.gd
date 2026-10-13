class_name EventLoader
extends RefCounted
## 从 data/events.json 加载职场事件（《打boss》）
## M3 轻量：加载、职级过滤、权重抽取、本年不重复

const EVENTS_PATH := "res://data/events.json"


## 加载事件数组；失败时返回空数组
static func load_events() -> Array:
	if not FileAccess.file_exists(EVENTS_PATH):
		push_error("事件文件不存在: %s" % EVENTS_PATH)
		return []
	var file := FileAccess.open(EVENTS_PATH, FileAccess.READ)
	if file == null:
		push_error("无法打开事件文件: %s" % EVENTS_PATH)
		return []
	var text := file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_ARRAY:
		push_error("events.json 格式错误，应为数组")
		return []
	return parsed


## 按职级过滤可用事件
static func filter_for_rank(events: Array, rank_index: int) -> Array:
	var out: Array = []
	for e in events:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var min_r := int(e.get("min_rank", 0))
		var max_r := int(e.get("max_rank", 7))
		if rank_index >= min_r and rank_index <= max_r:
			out.append(e)
	return out


## 加权随机；exclude_ids 用于本年已触发；高精神负荷提高负面权重
static func pick_weighted(
	events: Array,
	rank_index: int,
	mind_load: int,
	exclude_ids: Array = []
) -> Dictionary:
	var pool: Array = filter_for_rank(events, rank_index)
	if pool.is_empty():
		pool = events.duplicate()
	var weighted: Array = []
	var total := 0
	for e in pool:
		var eid := str(e.get("id", ""))
		if exclude_ids.has(eid):
			continue
		var w := int(e.get("weight", 10))
		if bool(e.get("mind_load_weight_bonus", false)) and mind_load >= 40:
			w = int(ceil(w * (1.25 if mind_load < 70 else 1.6)))
		if w <= 0:
			continue
		weighted.append({"e": e, "w": w})
		total += w
	if weighted.is_empty():
		## 本年事件抽完则允许重复
		return pick_random(filter_for_rank(events, rank_index))
	var roll := randi() % total
	var acc := 0
	for item in weighted:
		acc += int(item["w"])
		if roll < acc:
			return item["e"]
	return weighted[weighted.size() - 1]["e"]


## 随机取一个事件；无事件时返回空字典
static func pick_random(events: Array = []) -> Dictionary:
	var list: Array = events if not events.is_empty() else load_events()
	if list.is_empty():
		return {}
	return list[randi() % list.size()]
