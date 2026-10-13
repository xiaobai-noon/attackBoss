extends Node
## GameState —— 《打boss》玩家进度与七维数值
## M1：数值定义、apply_deltas、初始化、职级名、NPC 好感空壳
## M2：年/季/周推进与年末恢复衰减（晋升正式逻辑在 M4，此处仅占位）

const SAVE_PATH := "user://save.json"
const SAVE_SCHEMA_VERSION := 2

## 职级链（策划书 §5）
const RANKS: Array[String] = [
	"实习生",
	"专员",
	"高级专员",
	"部门主管",
	"事业部经理",
	"区域总监",
	"集团副总裁",
	"CEO",
]

## 各职级年薪津贴（年末 resource 加成）
const RANK_STIPEND: Array[int] = [800, 2000, 3500, 5500, 8000, 12000, 18000, 0]

## 游玩模式
enum Mode { NORMAL, REWIND }

var mode: Mode = Mode.NORMAL

## —— 七维数值 ——
var performance: int = 40
var expertise: int = 35
var influence: int = 20
var reputation: int = 25
var mind_load: int = 0
var health: int = 80
var resource: int = 3000

var rank_index: int = 0
var year: int = 1
var quarter: int = 1
var week: int = 1
var rewind_count: int = 0

## 标记与 NPC（M7/M8 会用；M1 先给空壳）
var flags: Array[String] = []
var npc_favors: Dictionary = {}
var year_triggered_events: Array[String] = []
var eval_fail_streak: int = 0

var job_title: String:
	get:
		return RANKS[clampi(rank_index, 0, RANKS.size() - 1)]


func _ready() -> void:
	_ensure_npc_defaults()


func _ensure_npc_defaults() -> void:
	## 五名核心 NPC 初始好感（策划书 §6.6）
	var defaults := {
		"shen_tinglan": 40,
		"ji_heng": 35,
		"you_wanxing": 40,
		"tang_poxiao": 45,
		"liang_xu": 40,
	}
	for k in defaults.keys():
		if not npc_favors.has(k):
			npc_favors[k] = int(defaults[k])


## 将策划 effects 字典应用到七维（M1 主 API）
func apply_deltas(deltas: Dictionary) -> void:
	performance = _clamp_stat(performance + int(deltas.get("performance", 0)))
	expertise = _clamp_stat(expertise + int(deltas.get("expertise", 0)))
	influence = _clamp_stat(influence + int(deltas.get("influence", 0)))
	reputation = _clamp_stat(reputation + int(deltas.get("reputation", 0)))
	mind_load = _clamp_stat(mind_load + int(deltas.get("mind_load", 0)))
	health = _clamp_stat(health + int(deltas.get("health", 0)))
	resource = maxi(0, resource + int(deltas.get("resource", 0)))
	EventBus.stats_changed.emit()


func _clamp_stat(v: int) -> int:
	return clampi(v, 0, 100)


func add_flag(flag: String) -> void:
	if not flags.has(flag):
		flags.append(flag)


func has_flag(flag: String) -> bool:
	return flags.has(flag)


## 应用 NPC 好感变化（M8 薄实现，事件结算可先调用）
func apply_npc_effects(npc_effects: Dictionary) -> void:
	for npc_id in npc_effects.keys():
		var cur := int(npc_favors.get(npc_id, 40))
		var next_v := clampi(cur + int(npc_effects[npc_id]), 0, 100)
		npc_favors[npc_id] = next_v
		EventBus.npc_favor_changed.emit(str(npc_id), next_v)


func new_game(p_mode: Mode = Mode.NORMAL) -> void:
	mode = p_mode
	performance = 40
	expertise = 35
	influence = 20
	reputation = 25
	mind_load = 0
	health = 80
	resource = 3000
	rank_index = 0
	year = 1
	quarter = 1
	week = 1
	rewind_count = 0
	flags.clear()
	year_triggered_events.clear()
	eval_fail_streak = 0
	npc_favors.clear()
	_ensure_npc_defaults()
	EventBus.stats_changed.emit()
	EventBus.calendar_advanced.emit(year, quarter, week)


## —— M2：年度回合推进 ——

## 推进一周；跨季/跨年时自动结算
func advance_week() -> void:
	week += 1
	if week > 3:
		week = 1
		quarter += 1
	if quarter > 4:
		_year_end_pipeline()
		year += 1
		quarter = 1
		week = 1
	EventBus.calendar_advanced.emit(year, quarter, week)


## 年末恢复/衰减（策划 §4.2）；正式晋升在 M4
func _year_end_pipeline() -> void:
	## 绩效重置为职级基线，再轻微保留本年表现（简化）
	var base_perf := 40 + rank_index * 3
	performance = _clamp_stat(base_perf + clampi(performance - base_perf, -10, 10))
	## 人脉/声望自然衰减
	influence = _clamp_stat(influence - 5)
	reputation = _clamp_stat(reputation - 3)
	## 精神负荷不自然下降
	## 身心健康休假恢复
	health = _clamp_stat(health + 10)
	## 职级津贴
	var stipend := 0
	if rank_index >= 0 and rank_index < RANK_STIPEND.size():
		stipend = RANK_STIPEND[rank_index]
	resource = maxi(0, resource + stipend)
	## 清空本年已触发事件
	year_triggered_events.clear()
	## M4 占位：临时简易晋升（完整门槛表在 PromotionService）
	var promoted := _temp_try_promote()
	EventBus.stats_changed.emit()
	EventBus.year_ended.emit(year)
	if promoted:
		EventBus.promotion_result.emit(true, job_title)
		EventBus.promoted.emit(job_title, rank_index)


## 临时晋升规则（M4 前过渡用，勿当最终数值）
func _temp_try_promote() -> bool:
	if rank_index >= RANKS.size() - 1:
		return false
	var need_perf := 50 + rank_index * 5
	var need_exp := 40 + rank_index * 6
	var mind_penalty := 8 if mind_load >= 70 else 0
	var score := (
		performance * 0.35
		+ expertise * 0.25
		+ influence * 0.15
		+ reputation * 0.15
		+ health * 0.10
		- mind_penalty
	)
	var need_score := 52.0 + rank_index * 6.0
	if performance >= need_perf and expertise >= need_exp and score >= need_score and health >= 25:
		rank_index += 1
		return true
	if score < 35.0 + rank_index * 3.0:
		eval_fail_streak += 1
	else:
		eval_fail_streak = 0
	return false


func is_ceo() -> bool:
	return rank_index >= RANKS.size() - 1


## —— 存档（schema v2；完整字段校验在 M6 加强）——

func save_game() -> bool:
	var data := {
		"schema_version": SAVE_SCHEMA_VERSION,
		"mode": int(mode),
		"performance": performance,
		"expertise": expertise,
		"influence": influence,
		"reputation": reputation,
		"mind_load": mind_load,
		"health": health,
		"resource": resource,
		"rank_index": rank_index,
		"year": year,
		"quarter": quarter,
		"week": week,
		"rewind_count": rewind_count,
		"flags": flags.duplicate(),
		"npc_favors": npc_favors.duplicate(),
		"year_triggered_events": year_triggered_events.duplicate(),
		"eval_fail_streak": eval_fail_streak,
	}
	var json := JSON.stringify(data, "\t")
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("无法写入存档: %s" % SAVE_PATH)
		return false
	file.store_string(json)
	file.close()
	return true


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
	## 拒绝旧四维存档（schema < 2）
	if int(data.get("schema_version", 1)) < SAVE_SCHEMA_VERSION:
		push_warning("存档版本过旧，请开始新游戏")
		return false
	mode = Mode.REWIND if int(data.get("mode", 0)) == int(Mode.REWIND) else Mode.NORMAL
	performance = int(data.get("performance", 40))
	expertise = int(data.get("expertise", 35))
	influence = int(data.get("influence", 20))
	reputation = int(data.get("reputation", 25))
	mind_load = int(data.get("mind_load", 0))
	health = int(data.get("health", 80))
	resource = int(data.get("resource", 3000))
	rank_index = int(data.get("rank_index", 0))
	year = int(data.get("year", 1))
	quarter = int(data.get("quarter", 1))
	week = int(data.get("week", 1))
	rewind_count = int(data.get("rewind_count", 0))
	flags.assign(data.get("flags", []))
	npc_favors = data.get("npc_favors", {})
	year_triggered_events.assign(data.get("year_triggered_events", []))
	eval_fail_streak = int(data.get("eval_fail_streak", 0))
	_ensure_npc_defaults()
	EventBus.stats_changed.emit()
	EventBus.calendar_advanced.emit(year, quarter, week)
	return true
