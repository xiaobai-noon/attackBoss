extends Node
## 全局事件总线：场景之间解耦通信
## Global event bus for decoupled scene communication

signal day_started(day: int)
signal choice_made(event_id: String, choice_index: int)
signal day_ended(day: int)
signal promoted(new_title: String, rank_index: int)
signal stats_changed()