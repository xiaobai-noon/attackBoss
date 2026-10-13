class_name EventLoader
extends RefCounted
## 从 data/events.json 加载职场事件
## Load workplace events from data/events.json

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


## 随机取一个事件；无事件时返回空字典
static func pick_random(events: Array = []) -> Dictionary:
	var list: Array = events if not events.is_empty() else load_events()
	if list.is_empty():
		return {}
	return list[randi() % list.size()]
