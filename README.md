# 打boss（Attack Boss）

Godot 4 职场人生模拟：从实习生晋升到 CEO。核心机制为年度回合与「困局回溯」。

**当前目标：α 垂直切片** —— 3 场景 / 3 事件 / 1 结局 / 约 14 分钟，可发布到 itch.io 的短篇。
范围定义见 [`docs/α切片范围.md`](docs/α切片范围.md)，**凡与"完整版"描述冲突，以它为准**。

## 运行要求

- **Godot 4.3+**（目标 4.7）
- 推荐 **GL Compatibility** 渲染器
- ⚠️ **首次运行前必须处理中文字体**：Godot 4 内置默认字体不含完整中文字形，直接跑大概率显示方块。
  见 [`docs/UI设计方案.md`](docs/UI设计方案.md) 的 U0 步骤（引入思源黑体 SC + 建 `game_theme.tres`）。

## 如何打开运行

1. 安装 [Godot 4](https://godotengine.org/download)
2. 打开 Godot → **Import** → 选择本仓库 `project.godot`
3. 按 **F5** 运行（主场景 `scenes/main_menu.tscn`）
4. 单独调试对话界面：在 FileSystem 里选中 `scenes/dialogue_screen.tscn`，按 **F6**
   （操作：空格/点击继续 · `1/2/3` 直选 · `R` 重播）

## 当前开发进度（本地）

| 模块 | 状态 |
|---|---|
| M1 七维数值 | ✅ |
| M2 年/季/周推进 | ✅ |
| M3 事件池（20 事件）+ 加权抽取 | ✅ 轻量 |
| M4 正式晋升门槛表 | ⏳ 暂用简易晋升 |
| M5 困局回溯弹窗 | ⏳ 未做（α 不做，排 β） |
| M6 存档 schema v2 | ✅ 基础 |
| M7 五结局界面 | ⏳ stub（α 只做 1 个结局） |
| M8 NPC 好感 | ✅ 薄实现（事件挂钩） |
| **表现层改造：对话图 + 镜头导演** | ⚠️ 代码已写，**未实机验证** |

## 文件夹结构

```
attackBoss/
├── docs/                     # 全部设计与预算文档（见下方索引）
├── autoload/                 # GameState / EventBus
├── data/
│   ├── events.json           # 20 个职场事件（索引 + 权重 + 选项效果）
│   ├── shots.json            # 镜头表：4 场景 / 17 镜头（含 scope 范围标记）
│   └── story/                # 对话剧本（对话图 JSON）
├── scripts/                  # EventLoader / dialogue_engine（对话图执行器）
│                             # / shot_director（镜头导演） / smoke_test
├── scenes/                   # 主菜单 / 回合界面 / dialogue_screen（AVG 界面）
├── tools/                    # 预算与资产模型（Python，可复算）
├── resources/                # 运行时资源
└── ui/                       # 主题、字体、组件（待建，见 UI 方案 U0~U5）
```

## 文档索引

按「先决策、后执行」排列：

| 文档 | 回答的问题 |
|---|---|
| [`职级轮回_游戏策划书.md`](docs/职级轮回_游戏策划书.md) | 游戏是什么（**唯一的需求源头**） |
| [`个人开发可行性.md`](docs/个人开发可行性.md) | 在 ¥2,000~3,000 / 单人约束下，**能不能做完** |
| [`α切片范围.md`](docs/α切片范围.md) | **现在具体做什么**（3 场景 / 3 事件 / 1 结局） |
| [`静态帧影像规格.md`](docs/静态帧影像规格.md) | 画面怎么做（素材规格、镜头语言、动效边界、视频准入） |
| [`对话与场景系统设计.md`](docs/对话与场景系统设计.md) | 玩法怎么表达（对话图 schema、日循环） |
| [`UI设计方案.md`](docs/UI设计方案.md) | 界面怎么长出来（L0 字体 → L1 主题 → L2 组件 → L3 场景） |
| [`拍摄单.md`](docs/拍摄单.md) | **要生产多少素材**（自动生成，勿手改） |
| [`FMV预算分析.md`](docs/FMV预算分析.md) | 团队口径预算（¥22.9 万）— 规律参考，**非当前口径** |
| [`减法组合预算.md`](docs/减法组合预算.md) | 减法组合团队口径（¥19.2 万）— **非当前口径** |

## 常用命令

```bash
# 冒烟测试（数值层，无需图形界面）
godot --path . --headless --script res://scripts/smoke_test.gd

# 校验镜头表 + 剧本，并重新生成 docs/拍摄单.md
python tools/shotlist.py
python tools/shotlist.py --no-write          # 只校验，不落盘

# 成本模型（改参数表即可重出全部结论）
python tools/solo_feasibility.py             # 个人开发可行性（当前口径）
python tools/subtractive_budget.py           # 减法组合团队口径
python tools/fmv_budget.py                   # FMV 团队口径
```

## 开发纪律

- **先文档后代码**：改玩法先改策划书，改画面先改影像规格
- **一次一模块**：不铺全套界面，跟着 M1~M8 与 α 范围走
- **范围锁定**：α 之外的功能一律不做，见 `docs/α切片范围.md` 第 7 节
- **命名**：UI 文案中文，标识符英文
- **禁止 IP 污染**：所有角色、公司、桥段原创，不影射真实企业与人

## License

学习用项目，可按需修改。
