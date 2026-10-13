# 打工人逆袭（AttackBoss）

Godot 4 职场生涯模拟游戏垂直切片骨架：每天面对一个职场事件，做选择 → 属性变化 → 尝试晋升 → 冲向 CEO。

## 环境要求

- **Godot 4.3+**（兼容 Godot 4.x / 目标 4.7）
- 推荐使用 **GL Compatibility** 渲染器（已在 `project.godot` 中配置，适合 2D/UI）

## 如何打开与运行

1. 安装 [Godot 4](https://godotengine.org/download)
2. 打开 Godot → **Import** / **导入** → 选择本仓库中的 `project.godot`
3. 点击 **运行**（F5）。主场景为 `scenes/main_menu.tscn`
4. 主菜单点「新游戏」进入每日循环；有存档时可点「继续游戏」

## 文件夹结构

```
attackBoss/
├── project.godot          # 工程配置、Autoload
├── autoload/
│   ├── game_state.gd      # 玩家属性、天数、职级、存档
│   └── event_bus.gd       # 全局信号总线
├── data/
│   └── events.json        # 职场事件数据
├── scripts/
│   └── event_loader.gd    # 加载 / 随机抽取事件
├── scenes/
│   ├── main_menu.tscn     # 主菜单
│   ├── main_menu.gd
│   ├── day_screen.tscn    # 每日事件界面
│   └── day_screen.gd
├── ui/                    # 可放自定义 UI 组件
├── resources/             # 可放 Resource / Theme 等
└── README.md
```

## 玩法简述

- **属性**：技能、人脉、压力、金钱
- **职级**：实习生 → 初级职员 → … → CEO
- **每天**：随机事件 → 选一项 → 结算效果 → 检查晋升 → 下一天
- **通关**：升到 CEO 后返回主菜单（当前为通关 stub）
- **存档**：`user://save.json`（由 `GameState.save_game` / `load_game` 读写）

晋升规则（可在 `autoload/game_state.gd` 的 `try_promote` 中改）：

- 需要 `skill >= 15 + rank*10` 且 `network >= 8 + rank*5`，且 `stress < 80`

## 如何添加新事件

编辑 `data/events.json`，追加一个对象，例如：

```json
{
  "id": "my_new_event",
  "title": "事件标题",
  "body": "事件描述文案……",
  "choices": [
    {
      "text": "选项一的文案",
      "effects": { "skill": 5, "network": 0, "stress": 3, "money": 0 }
    },
    {
      "text": "选项二的文案",
      "effects": { "skill": 0, "network": 5, "stress": -2, "money": -50 }
    }
  ]
}
```

字段说明：

| 字段 | 说明 |
|------|------|
| `id` | 唯一标识（字符串） |
| `title` / `body` | 标题与正文（中文即可） |
| `choices` | 通常 2 个选项 |
| `effects` | 对 skill / network / stress / money 的增量（可为负） |

保存后重新运行即可；`EventLoader` 会自动加载全部事件并随机抽取。

## 扩展建议

- 在 `ui/` 做更漂亮的属性条、弹窗
- 用 `resources/` 做 Theme、自定义 Resource 类型的事件
- 按 `job_title` / `day` 过滤事件池，增加剧情分支

## License

学习用骨架，可按需自行修改。