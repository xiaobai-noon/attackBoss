extends Node
## 玩家全局状态：属性、天数、职级、存档
## Player global state: stats, day, rank, save/load

const SAVE_PATH := "user://save.json"

## 职级列表：实习生 → … → CEO
const RANKS: Array[String] = [
	"实习生",
	"初级职员",
	"正式员工",
	"高级专员",
	"主管",
	"经理",
	"总监",
	"副总裁",
	"CEO",
]

var skill: int = 10
var network: int = 5
var stress: int = 0
var money: int = 1000
var day: int = 1
var rank_index: int = 0

var job_title: String:
	get:
		return RANKS[clampi(rank_index, 0, RANKS.size() - 1)]


func _ready() -> void:
	pass


## 应用属性变化（可为负）
func apply_deltas(deltas: Dictionary) -> void:
	skill = maxi(0, skill + int(deltas.get("skill", 0)))
	network = maxi(0, network + int(deltas.get("network", 0)))
	stress = clampi(stress + int(deltas.get("stress", 0)), 0, 100)
	money = money + int(deltas.get("money", 0))
	EventBus.stats_changed.emit()


## 进入下一天
func advance_day() -> void:
	day += 1
	EventBus.day_started.emit(day)


## 尝试晋升：技能+人脉达标则升一级
func try_promote() -> bool:
	if rank_index >= RANKS.size() - 1:
		return false
	# 简单规则：每级需要 skill >= 15 + rank*10, network >= 8 + rank*5
	var need_skill := 15 + rank_index * 10
	var need_network := 8 + rank_index * 5
	if skill >= need_skill and network >= need_network and stress < 80:
		rank_index += 1
		EventBus.promoted.emit(job_title, rank_index)
		EventBus.stats_changed.emit()
		return true
	return false


## 是否已当上 CEO（通关）
func is_ceo() -> bool:
	return rank_index >= RANKS.size() - 1


## 开始新游戏
func new_game() -> void:
	skill = 10
	network = 5
	stress = 0
	money = 1000
	day = 1
	rank_index = 0
	EventBus.stats_changed.emit()
	EventBus.day_started.emit(day)


## 保存到 user://save.json
func save_game() -> bool:
	var data := {
		"skill": skill,
		"network": network,
		"stress": stress,
		"money": money,
		"day": day,
		"rank_index": rank_index,
	}
	var json := JSON.stringify(data, "\t")
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("无法写入存档: %s" % SAVE_PATH)
		return false
	file.store_string(json)
	file.close()
	return true


## 从 user://save.json 加载
func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return false
	var text := file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	var data: Dictionary = parsed
	skill = int(data.get("skill", 10))
	network = int(data.get("network", 5))
	stress = int(data.get("stress", 0))
	money = int(data.get("money", 1000))
	day = int(data.get("day", 1))
	rank_index = int(data.get("rank_index", 0))
	EventBus.stats_changed.emit()
	return true