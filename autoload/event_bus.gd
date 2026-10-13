extends Node
## 全局事件总线 —— 《打boss》
## 场景与系统之间只通过信号通信，避免循环依赖。

signal stats_changed
signal calendar_advanced(year: int, quarter: int, week: int)
signal year_ended(year: int)
signal event_resolved(event_id: String, choice_index: int)
signal promotion_result(success: bool, new_title: String)
signal major_failure(reason: String)
signal rewind_offered(reason: String)
signal rewind_executed(rewind_count: int, mind_load: int)
signal ending_triggered(ending_id: String)
signal npc_favor_changed(npc_id: String, favor: int)

## 兼容旧场景信号（后续模块会逐步移除）
signal day_started(day: int)
signal choice_made(event_id: String, choice_index: int)
signal day_ended(day: int)
signal promoted(new_title: String, rank_index: int)
