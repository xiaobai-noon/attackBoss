# -*- coding: utf-8 -*-
"""
《职级轮回》FMV 模式 —— AI 视频生成预算模型  v2
=========================================================
v2 修正：
  - 把「人力」纳入模型（v1 只算了 API 钱，会严重低估）
  - 配音给出 TTS / 真人配音 两条路线对比
  - 增加「每分钟成片成本」指标，用于与真人实拍对标
  - 固定成本与变动成本分离，观察规模摊薄效应

单价来源（2026-10 官方价，写死在 PRICE 表，改一处全表更新）：
  可灵 Kling 3.0  1080P 无声 ¥0.8/秒 / 有声 ¥1.2/秒   klingai.com/dev/pricing
  可灵 Kling 2.6  1080P 无声 ¥0.5/秒
  可灵 数字人      1080P ¥0.8/秒    对口型 ¥0.5/5秒≈¥0.1/秒
  可灵 Image 3.0   ¥0.2/张          文生音效 ¥0.25/次
  即梦 Seedance2.5 ¥7.56/5秒(720P)≈¥1.51/秒   火山引擎官方
  即梦 Seedance2.0 ≈¥0.9/秒
  MiniMax TTS speech-2.8-hd  $100/M chars ≈ ¥0.00072/字   声音克隆 $1.5/条
"""

FX = 7.2

PRICE = {
    "avatar_1080":   0.80,
    "lipsync_1080":  0.10,
    "i2v_hi_1080":   0.80,
    "i2v_lo_1080":   0.50,
    "i2v_seedance":  1.51,
    "t2v_env_1080":  0.50,
    "image":         0.20,
    "tts_per_char":  0.00072,
    "voice_clone":   10.80,
    "sfx_per_call":  0.25,
}

USABLE = {"avatar": 0.40, "i2v": 0.25, "env": 0.50, "image": 0.35}
LEARNING = 1.0

EVENT_SHOTS = [
    ("C", 2, 6), ("A", 4, 8), ("B", 2, 6), ("A", 3, 6), ("C", 1, 5),
    ("A", 4, 8), ("B", 2, 6), ("A", 3, 6), ("B", 3, 8), ("A", 3, 10), ("C", 1, 6),
]

AMBIENT_SHOTS_PER_SLOT = 3
AMBIENT_SLOT_SEC = 5
SLOTS_PER_DAY = 3
CHAR_PER_SEC_DUB = 4.5
CHARS_PER_LINE = 20          # 平均每句台词字数（用于真人配音计价）

SCALES = {
    "α 垂直切片": {"events": 3,  "ambient_days": 2,  "extra_min": 3},
    "β 抢先体验": {"events": 12, "ambient_days": 18, "extra_min": 8},
    "1.0 完整版": {"events": 20, "ambient_days": 36, "extra_min": 15},
}

# ---- 人力模型（人天 x 元/人天）----
DAY_RATE = 750  # 小团队/自由职业综合日成本
LABOR = {
    "α 垂直切片": {"编剧": 8,  "抽卡/Prompt": 12, "剪辑后期": 10, "音效配乐": 5,
                   "UI/程序": 12, "美术指导": 5},
    "β 抢先体验": {"编剧": 25, "抽卡/Prompt": 45, "剪辑后期": 32, "音效配乐": 12,
                   "UI/程序": 28, "美术指导": 14},
    "1.0 完整版": {"编剧": 60, "抽卡/Prompt": 78, "剪辑后期": 58, "音效配乐": 20,
                   "UI/程序": 45, "美术指导": 26},
}

# 其他一次性支出（元）
OTHER_FIXED = {
    "Steam 上架费": 700,
    "BGM 授权/生成+混音": 800,
    "软件与工具订阅": 1500,
    "合规/法务（用户协议、隐私）": 3000,
}


def event_profile():
    agg = {"A": [0, 0], "B": [0, 0], "C": [0, 0]}
    for t, n, s in EVENT_SHOTS:
        agg[t][0] += n
        agg[t][1] += n * s
    return agg


def cost_shots(shots, mode):
    """shots: {tag: (段数, 秒数)}"""
    total = 0.0
    if mode == "pure":
        plan = [("A", PRICE["avatar_1080"], USABLE["avatar"]),
                ("B", PRICE["i2v_hi_1080"], USABLE["i2v"]),
                ("C", PRICE["t2v_env_1080"], USABLE["env"])]
    else:
        plan = [("A", PRICE["avatar_1080"], USABLE["avatar"]),
                ("B", PRICE["i2v_lo_1080"], USABLE["i2v"]),
                ("C", None, USABLE["image"])]
    for tag, unit, usable in plan:
        n, s = shots.get(tag, (0, 0))
        if n == 0:
            continue
        if unit is None:  # 静态图
            total += (n / usable * LEARNING) * PRICE["image"]
        else:
            total += (s / usable * LEARNING) * unit
    return total


def build(cfg, mode):
    prof = event_profile()
    n_ev = cfg["events"]

    ev_shots = {t: (prof[t][0] * n_ev, prof[t][1] * n_ev) for t in "ABC"}
    n_amb = cfg["ambient_days"] * SLOTS_PER_DAY * AMBIENT_SHOTS_PER_SLOT
    amb_shots = {"C": (n_amb, n_amb * AMBIENT_SLOT_SEC)}
    if cfg["extra_min"] > 10:
        ex_shots = {"A": (8, 60), "B": (8, 70), "C": (6, 45)}
    else:
        ex_shots = {"A": (6, 40), "B": (6, 50), "C": (4, 30)}

    ev = cost_shots(ev_shots, mode)
    amb = cost_shots(amb_shots, mode)
    ex = cost_shots(ex_shots, mode)

    # 配音
    talk_sec = ev_shots["A"][1] + ex_shots["A"][1]
    chars = talk_sec * CHAR_PER_SEC_DUB * 0.75
    tts = chars * PRICE["tts_per_char"] * 1.5      # 1.5 = 重录冗余
    lines = chars / CHARS_PER_LINE
    human_dub = lines * 45                          # 真人配音 45 元/句（中低端棚）
    clone = PRICE["voice_clone"] * 8

    # 美术资产（一次性）
    art_n = 6 * 24 + 12 * 12 + 40
    art = (art_n / USABLE["image"]) * PRICE["image"]

    sfx = (n_ev * 8 + 40) * PRICE["sfx_per_call"]

    minutes = (sum(ev_shots[t][1] for t in "ABC") + amb_shots["C"][1]
               + sum(ex_shots[t][1] for t in "ABC")) / 60
    shots = sum(ev_shots[t][0] for t in "ABC") + n_amb + sum(ex_shots[t][0] for t in "ABC")

    return {"ev": ev, "amb": amb, "ex": ex, "tts": tts, "human_dub": human_dub,
            "clone": clone, "art": art, "sfx": sfx,
            "minutes": minutes, "shots": shots, "chars": chars, "lines": lines}


def fmt(x):
    return f"¥{x:,.0f}"


if __name__ == "__main__":
    prof = event_profile()
    print("=" * 80)
    print("《职级轮回》FMV 预算模型 v2 —— AI 视频生成")
    print(f"汇率 1USD={FX}CNY | 学习曲线={LEARNING} | 人力单价 {DAY_RATE} 元/人天")
    print("=" * 80)

    print("\n【单事件镜头结构】")
    for t, name in [("A", "对口型对白"), ("B", "动作/情绪"), ("C", "环境空镜")]:
        n, s = prof[t]
        print(f"  {t} {name:<10} {n:>3} 段 {s:>4}s")
    print(f"  合计 {sum(prof[t][0] for t in 'ABC')} 段 / "
          f"{sum(prof[t][1] for t in 'ABC')}s = {sum(prof[t][1] for t in 'ABC')/60:.1f} 分钟")

    res = {(m, s): build(c, m) for m in ("pure", "hybrid") for s, c in SCALES.items()}

    # ---------- 生成成本 ----------
    for mode, mname in [("pure", "纯 FMV（全部镜头视频生成）"),
                        ("hybrid", "分层混合（环境层→静态图+引擎推拉）")]:
        print("\n" + "─" * 80)
        print(f"■ API 生成成本 —— {mname}")
        print("─" * 80)
        print(f"  {'规模':<12}{'成片':>8}{'镜头':>7}{'事件':>10}{'环境':>9}"
              f"{'固定':>9}{'配音':>7}{'美术':>8}{'音效':>7}{'合计':>10}")
        for s in SCALES:
            r = res[(mode, s)]
            tot = r["ev"] + r["amb"] + r["ex"] + r["tts"] + r["clone"] + r["art"] + r["sfx"]
            print(f"  {s:<12}{r['minutes']:>6.0f}分{r['shots']:>7}{fmt(r['ev']):>10}"
                  f"{fmt(r['amb']):>9}{fmt(r['ex']):>9}{fmt(r['tts']):>7}"
                  f"{fmt(r['art']):>8}{fmt(r['sfx']):>7}{fmt(tot):>10}")

    # ---------- 全成本（含人力） ----------
    print("\n" + "─" * 80)
    print("■ 项目全成本 —— 分层混合模式（API + 人力 + 其他）")
    print("─" * 80)
    hdr = f"  {'项目':<18}" + "".join(f"{s:>17}" for s in SCALES)
    print(hdr)
    rows = []
    for s in SCALES:
        r = res[("hybrid", s)]
        api = r["ev"] + r["amb"] + r["ex"] + r["tts"] + r["clone"] + r["art"] + r["sfx"]
        labor = sum(LABOR[s].values()) * DAY_RATE
        other = sum(OTHER_FIXED.values())
        rows.append((api, labor, other, api + labor + other))
    for i, label in enumerate(["API 生成+素材", "人力投入", "其他一次性", "合计"]):
        print(f"  {label:<18}" + "".join(f"{fmt(rows[j][i]):>19}" for j in range(3)))

    print("\n  人力明细（人天）")
    print(f"  {'角色':<16}" + "".join(f"{s:>17}" for s in SCALES))
    for role in LABOR["1.0 完整版"]:
        print(f"  {role:<16}" + "".join(f"{LABOR[s][role]:>14} 人天" for s in SCALES))

    # ---------- 单位成本 ----------
    print("\n" + "─" * 80)
    print("■ 单位成片成本（用于与真人实拍对标）")
    print("─" * 80)
    print(f"  {'口径':<34}{'总投入':>14}{'成片时长':>10}{'元/分钟':>12}")
    for j, s in enumerate(SCALES):
        r = res[("hybrid", s)]
        print(f"  {'AI 路径 · ' + s:<34}{fmt(rows[j][3]):>14}"
              f"{r['minutes']:>8.0f}分{r['minutes'] and rows[j][3]/r['minutes']:>12,.0f}")
    print(f"  {'真人实拍 · 《完蛋》对标':<34}{'¥5,000,000':>14}{'~350分':>10}{'14,286':>12}")
    print("  注：《完蛋》制作成本约 500 万、影视承制占近 60%，影片素材约 350 分钟量级")

    # ---------- 配音路线 ----------
    print("\n" + "─" * 80)
    print("■ 配音路线对比")
    print("─" * 80)
    print(f"  {'规模':<12}{'台词字数':>10}{'句数':>8}{'TTS(MiniMax)':>16}"
          f"{'真人配音':>14}{'差额':>14}")
    for s in SCALES:
        r = res[("hybrid", s)]
        print(f"  {s:<12}{r['chars']:>10,.0f}{r['lines']:>8,.0f}"
              f"{fmt(r['tts']):>16}{fmt(r['human_dub']):>14}"
              f"{fmt(r['human_dub'] - r['tts']):>14}")

    # ---------- 敏感性 ----------
    print("\n" + "─" * 80)
    print("■ 敏感性：抽卡可用率（1.0 完整版 · 分层混合）")
    print("─" * 80)
    base = res[("hybrid", "1.0 完整版")]
    base_api = base["ev"] + base["amb"] + base["ex"]
    labor = sum(LABOR["1.0 完整版"].values()) * DAY_RATE
    other = sum(OTHER_FIXED.values())
    non_api = (base["tts"] + base["clone"] + base["art"] + base["sfx"]) + labor + other
    print(f"  {'情景':<30}{'视频API':>14}{'项目全成本':>14}{'相对基准':>12}")
    for label, mult in [("乐观 0.7x（团队极熟练）", 0.7), ("基准 1.0x（当前假设）", 1.0),
                        ("保守 1.5x（新手期）", 1.5), ("悲观 2.0x（一致性难控）", 2.0)]:
        v = base_api * mult
        t = v + non_api
        print(f"  {label:<30}{fmt(v):>14}{fmt(t):>14}{t/(base_api+non_api):>11.0%}")
    print(f"\n  结论：视频 API 只占全成本 "
          f"{base_api/(base_api+non_api):.1%}，抽卡倍率翻倍对总预算影响约 "
          f"{(base_api*2+non_api)/(base_api+non_api)-1:.0%}")

    # ---------- 品质档位 ----------
    print("\n" + "─" * 80)
    print("■ 品质档位对比（1.0 完整版 · 分层混合）")
    print("─" * 80)
    # (A类单价, A可用率, B类单价, B可用率, 配音方案, 人力系数)
    QUALITY = {
        "经济档": (0.40, 0.50, 0.30, 0.30, "tts",   0.85),
        "标准档": (0.80, 0.40, 0.80, 0.25, "tts",   1.00),
        "品质档": (1.20, 0.30, 1.51, 0.20, "human", 1.50),
    }

    def quality_total(q):
        pa, ua, pb, ub, dub, hf = q
        r = res[("hybrid", "1.0 完整版")]
        prof = event_profile()
        n_ev = SCALES["1.0 完整版"]["events"]

        def seg(sec, unit, usable):
            return sec / usable * LEARNING * unit

        a_sec = prof["A"][1] * n_ev + 60
        b_sec = prof["B"][1] * n_ev + 70
        c_sec = prof["C"][1] * n_ev + 36 * 3 * 3 * 5 + 45
        api = seg(a_sec, pa, ua) + seg(b_sec, pb, ub) + (c_sec / 3 / 5) / 0.35 * PRICE["image"]
        api += r["clone"] + r["art"] + r["sfx"]
        if dub == "tts":
            api += r["tts"]
        else:
            api += r["human_dub"]
        labor = sum(LABOR["1.0 完整版"].values()) * DAY_RATE * hf
        return api, labor, api + labor + sum(OTHER_FIXED.values())

    print(f"  {'档位':<10}{'视频API':>12}{'配音':>12}{'人力':>14}{'全成本':>14}")
    for name, q in QUALITY.items():
        api, labor, tot = quality_total(q)
        print(f"  {name:<10}{fmt(api):>12}{q[4]:>12}{fmt(labor):>14}{fmt(tot):>14}")
    print("  注：经济档 = Kling 2.6 720P + TTS；品质档 = Kling 3.0 Omni 1080P 有声 + 真人配音")

    # ---------- 分支结构杠杆 ----------
    print("\n" + "─" * 80)
    print("■ 分支结构对成本的影响（1.0 完整版）")
    print("─" * 80)
    ev_api = res[("hybrid", "1.0 完整版")]["ev"]
    ev_shots_n = 20 * 28
    print(f"  {'结构':<34}{'事件镜头':>10}{'事件API':>12}{'抽卡+剪辑人天':>16}{'推算全成本':>14}")
    base_labor = (LABOR["1.0 完整版"]["抽卡/Prompt"]
                  + LABOR["1.0 完整版"]["剪辑后期"]) * DAY_RATE
    fixed_rest = rows[2][3] - (ev_api + base_labor)
    for label, mult in [("分支-收束（当前设计）1.0x", 1.0),
                        ("半合并（共享中段）1.8x", 1.8),
                        ("独立路径树 3.0x", 3.0)]:
        print(f"  {label:<34}{ev_shots_n*mult:>10,.0f}{fmt(ev_api*mult):>12}"
              f"{base_labor*mult/DAY_RATE:>13,.0f} 人天"
              f"{fmt(ev_api*mult + base_labor*mult + fixed_rest):>14}")

    # ---------- 回本 ----------
    print("\n" + "─" * 80)
    print("■ 回本测算（Steam 30% 分成后净收入）")
    print("─" * 80)
    print(f"  {'售价':<8}{'规模':<14}{'项目全成本':>14}{'单套净收':>12}{'回本销量':>12}")
    for price in (42, 58, 68):
        net = price * 0.70
        for j, s in enumerate(SCALES):
            t = rows[j][3]
            print(f"  ¥{price:<7}{s:<14}{fmt(t):>14}{fmt(net):>12}"
                  f"{t/net:>10,.0f} 套")
        print()
