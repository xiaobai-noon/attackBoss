# 打boss（Attack Boss）

Godot 4 职场人生模拟：从实习生晋升到 CEO。核心机制为年度回合与「困局回溯」。

策划文档见 [`docs/职级轮回_游戏策划书.md`](docs/职级轮回_游戏策划书.md)（游戏定名《打boss》）。

## 运行要求

- **Godot 4.3+**（目标 4.7）
- 推荐 **GL Compatibility** 渲染器

## 如何打开运行

1. 安装 [Godot 4](https://godotengine.org/download)
2. 打开 Godot → **Import** → 选择本仓库 `project.godot`
3. 按 **F5** 运行（主场景 `scenes/main_menu.tscn`）
4. 选择「普通模式」或「回溯模式」开始；有存档可「继续游戏」

## 当前开发进度（本地）

| 模块 | 状态 |
|---|---|
| M1 七维数值 | ✅ |
| M2 年/季/周推进 | ✅ |
| M3 事件池（20 事件）+ 加权抽取 | ✅ 轻量 |
| M4 正式晋升门槛表 | ⏳ 暂用简易晋升 |
| M5 困局回溯弹窗 | ⏳ 未做 |
| M6 存档 schema v2 | ✅ 基础 |
| M7 五结局界面 | ⏳ stub |
| M8 NPC 好感 | ✅ 薄实现（事件挂钩） |

## 冒烟测试

```bash
godot --path . --headless --script res://scripts/smoke_test.gd
```

## 文件夹结构

```
attackBoss/
├── docs/                 # 策划书
├── autoload/             # GameState / EventBus
├── data/events.json      # 职场事件
├── scripts/              # EventLoader / smoke_test
└── scenes/               # 主菜单 / 回合界面
```

## License

学习用项目，可按需修改。
