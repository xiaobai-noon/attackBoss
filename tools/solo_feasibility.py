# -*- coding: utf-8 -*-
"""
《职级轮回》个人开发可行性模型
==============================================================
硬约束：
  · 现金预算 ¥2,000 ~ ¥3,000（一次性，非月付）
  · 无外部人力，只有 1 人 + AI 辅助

本模型回答四个问题：
  1. 这笔钱够买到多少内容？（钱是不是约束）
  2. 一个人 + AI 要花多少小时？（时间才是约束）
  3. 全职 / 业余两种投入下，各规模需要多久？
  4. 原策划书的规模要不要裁？

数据来源：
  · API 单价与资产需求 → tools/subtractive_budget.py（同一套口径）
  · 团队工时基准      → 同上 LABOR_V3（¥750/人天口径）
  · AI 加速系数        → 见 AI_SPEEDUP 注释（有实证依据）
  · α 范围锁定值       → docs/α切片范围.md

用法：python tools/solo_feasibility.py
"""

BUDGET_LOW = 2000
BUDGET_HIGH = 3000

HOURS_PER_MANDAY = 8.0      # 团队口径「1 人天」= 8 小时
FULL_TIME_H = 6.0           # 全职个人：每天有效产出工时（不是 8，留思考/休息/杂事）
PART_TIME_H = 3.0           # 业余个人：下班后 + 周末摊平
HOURS_FULL_DAY = 6.0
HOURS_PART_DAY = 3.0

# ---------------- AI 加速系数 ----------------
# 依据：
#   代码 2.5x  —— 本项目已有实证：dialogue_engine.gd(372) + shot_director.gd(490)
#                + dialogue_screen.gd(451) + 3 个 Python 工具，AI 实际耗时约 1 小时，
#                人力估算约 8~10 人天。但「AI 写的代码未实机验证」需打折，故取 2.5 而非 5。
#   生图/分层 3.0x —— 切图补边可脚本化（沿切缝外扩 8%），是本路线最可自动化的一环。
#   音效配乐 3.0x —— AI 音乐生成已成熟，免去授权采购。
#   编剧 2.0x  —— AI 能起草台词与分支，但结构设计和「好不好玩」的判断不可替代。
#   动效编排 2.0x —— 镜头表可批量生成，但每个镜头的节奏感要人眼过。
#   美术指导 1.2x —— 审美判断几乎不可加速，这是硬瓶颈。
AI_SPEEDUP = {
    "编剧": 2.0,
    "生图/分层": 3.0,
    "动效编排": 2.0,
    "音效配乐": 3.0,
    "UI/程序": 2.5,
    "美术指导": 1.2,
}

# ---------------- 团队工时基准（来自 subtractive_budget.py · LABOR_V3）--------
TEAM_LABOR = {
    "α 垂直切片": {"编剧": 9,  "生图/分层": 6,  "动效编排": 8,  "音效配乐": 5,
                   "UI/程序": 16, "美术指导": 4},
    "β 抢先体验": {"编剧": 28, "生图/分层": 19, "动效编排": 24, "音效配乐": 12,
                   "UI/程序": 38, "美术指导": 11},
    "1.0 完整版": {"编剧": 68, "生图/分层": 32, "动效编排": 45, "音效配乐": 20,
                   "UI/程序": 62, "美术指导": 20},
}

# ---------------- API 需求（来自 subtractive_budget.py · full_cost）--------
# api = 静态图 + 关键视频 + TTS + 音色克隆 + 音效（全 TTS 口径）
# 注意：api 与 days 是参与计算的字段；scenes/cuts/portraits/props/vids 只作
#       说明性元数据，供人核对范围是否被偷换，不参与任何算式。
#       α 的取值必须与 docs/α切片范围.md 第 2/6 节一致（3 场景 / 15 镜头 / 9 立绘 / 1 视频）。
API_NEED = {
    "α 垂直切片": dict(api=148, events=3,  minutes=14, days=48,
                       scenes=3,  cuts=15,  portraits=9,  props=4,  vids=1),
    "β 抢先体验": dict(api=294, events=12, minutes=56, days=132,
                       scenes=12, cuts=48,  portraits=25, props=16, vids=4),
    "1.0 完整版": dict(api=489, events=20, minutes=97, days=247,
                       scenes=22, cuts=88,  portraits=36, props=26, vids=8),
}

# ---------------- α 切片范围（锁定值，见 docs/α切片范围.md）----------------
# 三个场景 id 对应 data/shots.json 的 scenes 键；事件 id 对应 data/events.json。
ALPHA_SCOPE = {
    "场景": [("三号会议室", "meeting_room"), ("开放办公区", "office_floor"), ("茶水间", "pantry")],
    "事件": [("周报扩写运动", "weekly_report_inflation"),
             ("成果署名之争", "credit_dispute"),
             ("茶水间版本流言", "pantry_rumor_version")],
    "结局": [("清醒离场（路径 A 主动离职）", "quit_clear")],
    "职级": "rank 0~2（实习生 / 专员 / 高级专员）",
    "预留不做": ["night_office 深夜办公区", "困局回溯弹窗", "其余 4 个结局", "其余 17 个事件"],
}


# ---------------- 预算分配（¥2,500 中位方案）----------------
# 「内容生成」与「工具」分离，看钱到底花在哪
SPEND_CONTENT = [
    ("生图 API（约 1,000 张额度）", 200),
    ("关键节点视频 API（可灵数字人）", 400),
    ("TTS + 8 条音色克隆", 100),
    ("音效生成", 100),
]
SPEND_TOOLS = [
    ("AI 编程助手订阅（12 个月）", 1800),
    ("引擎/美术/音频工具", 0),      # Godot · Krita · Audacity · DaVinci 全免费
    ("BGM", 0),                     # AI 生成
]
SPEND_LATER = [
    ("Steam 上架费（β 上线前再付）", 700),
]


def solo_hours(scale):
    """个人 + AI 的有效工时（小时）与角色明细"""
    detail = {}
    total_md = 0.0
    for role, team_md in TEAM_LABOR[scale].items():
        eff = team_md / AI_SPEEDUP[role]
        detail[role] = (team_md, AI_SPEEDUP[role], eff)
        total_md += eff
    return total_md, total_md * HOURS_PER_MANDAY, detail


def calendar(hours, h_per_day):
    return hours / h_per_day


def money(x):
    return f"\u00a5{x:,.0f}"


def main():
    print("=" * 88)
    print("《职级轮回》个人开发可行性模型 —— 预算 \u00a52,000~3,000 · 无外部人力 · 1 人 + AI")
    print("=" * 88)

    scales = list(API_NEED)

    # ---------- 1. 钱是不是约束 ----------
    print("\n" + "-" * 88)
    print("【1】钱够不够？（缺口分析）")
    print("-" * 88)
    print(f"  {'规模':<12}{'API 需求':>11}{'占预算':>10}{'预算倍数':>10}")
    for s in scales:
        a = API_NEED[s]["api"]
        print(f"  {s:<12}{money(a):>11}{a / BUDGET_LOW:>9.1%}"
              f"{BUDGET_LOW / a:>9.1f}x")
    print(f"\n  预算中位 \u00a52,500")
    print(f"  → 即使做到 1.0 完整版，内容生成只花 "
          f"{money(API_NEED['1.0 完整版']['api'])}，占预算 "
          f"{API_NEED['1.0 完整版']['api'] / 2500:.1%}")
    print(f"  → 结论：**钱不是约束，富余 5 倍以上**")

    # ---------- 2. 预算分配 ----------
    print("\n" + "-" * 88)
    print("【2】\u00a52,500 实际怎么花")
    print("-" * 88)
    content = sum(v for _, v in SPEND_CONTENT)
    tools = sum(v for _, v in SPEND_TOOLS)
    for label, v in SPEND_CONTENT:
        print(f"  {'内容生成':<10}{label:<34}{money(v):>9}")
    print(f"  {'':<10}{'小计':<34}{money(content):>9}")
    for label, v in SPEND_TOOLS:
        print(f"  {'工具':<10}{label:<34}{money(v):>9}")
    print(f"  {'':<10}{'小计':<34}{money(tools):>9}")
    print(f"  {'后置':<10}{SPEND_LATER[0][0]:<34}{money(SPEND_LATER[0][1]):>9}")
    print(f"\n  ▶ 内容生成合计 {money(content)} | 工具合计 {money(tools)}"
          f" | 总计 {money(content + tools)}")
    print(f"  ▶ 真正花在「做出内容」上的钱只有 {money(content)}，"
          f"占预算 {content / 2500:.0%}")
    print(f"  ▶ 若 AI 助手已有（或走免费额度），总支出可压到 "
          f"{money(content)} 以内")

    # ---------- 3. 个人工时 ----------
    print("\n" + "-" * 88)
    print("【3】一个人 + AI 要花多少工时（这是真正的约束）")
    print("-" * 88)
    for s in scales:
        md, h, detail = solo_hours(s)
        print(f"\n  [{s}]  团队口径 {API_NEED[s]['days']} 人天 "
              f"→ 个人有效 {md:.1f} 人天 / {h:,.0f} 小时")
        print(f"  {'角色':<12}{'团队人天':>10}{'AI 加速':>9}{'个人有效':>10}")
        for role, (tm, sp, ef) in detail.items():
            print(f"  {role:<12}{tm:>10}{sp:>8.1f}x{ef:>10.1f}")
        print(f"  {'合计':<12}{API_NEED[s]['days']:>10}"
              f"{API_NEED[s]['days'] / md:>8.1f}x{md:>10.1f}")

    # ---------- 4. 日历时间 ----------
    print("\n" + "-" * 88)
    print("【4】日历时间（累计，不是相加）")
    print("-" * 88)
    print(f"  {'规模':<12}{'有效工时':>10}{'全职 6h/天':>14}{'业余 3h/天':>14}")
    for s in scales:
        md, h, _ = solo_hours(s)
        f_days = calendar(h, HOURS_FULL_DAY)
        p_days = calendar(h, HOURS_PART_DAY)
        print(f"  {s:<12}{h:>9,.0f}h{f_days:>10.0f} 天 / {f_days / 30:.1f} 月"
              f"{p_days:>10.0f} 天 / {p_days / 30:.1f} 月")

    print(f"\n  注：全职按每天 6 小时有效产出（不是 8）——个人开发要留出")
    print(f"      找资料、试错、休息、被生活打断的时间。业余按每天 3 小时。")

    # ---------- 5. 规模裁剪 ----------
    print("\n" + "-" * 88)
    print("【5】原策划书规模 vs 个人产能")
    print("-" * 88)
    design = dict(events=20, endings=5, ranks=8, npcs=5, scenes=22, minutes=97)
    alpha = dict(events=3, endings=1, ranks=3, npcs=4, scenes=3, minutes=14)
    print(f"  {'维度':<16}{'策划书 1.0':>14}{'α 切片':>12}{'裁剪':>10}")
    for k, label in [("events", "事件数"), ("endings", "结局数"),
                     ("ranks", "职级档位"), ("npcs", "NPC 数"),
                     ("scenes", "场景数"), ("minutes", "成片分钟")]:
        print(f"  {label:<16}{design[k]:>14}{alpha[k]:>12}"
              f"{alpha[k] / design[k]:>9.0%}")

    print(f"\n  α 切片具体是什么（锁定值，见 docs/α切片范围.md）：")
    for group in ("场景", "事件", "结局"):
        items = "、".join(f"{n}（{i}）" for n, i in ALPHA_SCOPE[group])
        print(f"    {group}：{items}")
    print(f"    职级：{ALPHA_SCOPE['职级']}")
    print(f"    明确不做：{'、'.join(ALPHA_SCOPE['预留不做'])}")

    # ---------- 6. 机会成本 ----------
    print("\n" + "-" * 88)
    print("【6】隐性成本：你自己的时间（必须知道）")
    print("-" * 88)
    print(f"  {'规模':<12}{'有效人天':>10}{'按\u00a5750/人天':>16}{'现金支出':>12}{'真实总投入':>14}")
    for s in scales:
        md, h, _ = solo_hours(s)
        shadow = md * 750
        cash = API_NEED[s]["api"]
        print(f"  {s:<12}{md:>10.1f}{money(shadow):>16}{money(cash):>12}"
              f"{money(shadow + cash):>14}")
    print(f"\n  ▶ 1.0 完整版：现金只花 {money(API_NEED['1.0 完整版']['api'])}，")
    print(f"     但你的时间值 {money(solo_hours('1.0 完整版')[0] * 750)}。"
          f"**真实成本是时间，不是钱。**")

    # ---------- 7. 可行性判定 ----------
    print("\n" + "-" * 88)
    print("【7】可行性判定")
    print("-" * 88)
    print(f"  {'规模':<12}{'现金':>10}{'全职':>12}{'业余':>12}{'判定':>16}")
    for s in scales:
        md, h, _ = solo_hours(s)
        f_m = calendar(h, HOURS_FULL_DAY) / 30
        p_m = calendar(h, HOURS_PART_DAY) / 30
        if f_m <= 2:
            verdict = "✓ 推荐先做"
        elif f_m <= 5:
            verdict = "○ 可行，需坚持"
        elif f_m <= 9:
            verdict = "△ 全年投入"
        else:
            verdict = "✗ 不建议一次性做"
        print(f"  {s:<12}{money(API_NEED[s]['api']):>10}"
              f"{f_m:>9.1f} 月{p_m:>9.1f} 月{verdict:>16}")

    # ---------- 8. 成功率 ----------
    print("\n" + "-" * 88)
    print("【8】风险：个人项目真正的杀手（按致命程度排序）")
    print("-" * 88)
    risks = [
        ("范围蔓延", "拿 20 事件的项目设计当目标，做到第 5 个事件就熄火",
         "强制砍到 3 事件 / α 必须「可发布」而非「可玩」"),
        ("无正反馈循环", "花 3 个月搭引擎，看不到任何成品，动力耗尽",
         "第 2 周就要有能玩的 14 分钟，哪怕复用同一张图"),
        ("单点故障", "生病 / 加班 / 生活事件，项目直接停摆",
         "每周固定 2 个「保底推进日」，只推进不返工"),
        ("完美主义返工", "一张图抽 20 次，一段动效调 2 小时",
         "定量铁律：每张图抽 5 次即止，不许第 6 次"),
        ("技术未验证", "现有引擎代码未跑过，可能开局卡在报错",
         "第 0 步：装 Godot，F6 跑通 dialogue_screen（半天）"),
        ("题材自我怀疑", "做了 2 个月开始觉得「这不好玩」",
         "α 发布到 itch.io，用陌生人的反馈替代自我判断"),
    ]
    for i, (name, desc, fix) in enumerate(risks, 1):
        print(f"  {i}. {name}")
        print(f"     风险：{desc}")
        print(f"     对策：{fix}")

    print("\n" + "=" * 88)
    print(f"一句话结论：\u00a52,000~3,000 买得到这条路线需要的全部内容")
    print(f"（1.0 完整版也只要 {money(API_NEED['1.0 完整版']['api'])}），")
    print(f"所以钱不是门槛 —— 门槛是「一个人 6 个月不熄火」。")
    print(f"因此第一步不是花钱，是把规模砍到 4 周内能跑完的 α 切片。")
    print("=" * 88)


if __name__ == "__main__":
    main()
