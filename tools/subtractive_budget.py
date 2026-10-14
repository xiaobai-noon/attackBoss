# -*- coding: utf-8 -*-
"""
《职级轮回》减法组合 —— 成本模型 v3
==============================================================
减法组合定义（详见 docs/静态帧影像规格.md）：
  画面  = 静态帧 + 引擎动效          （《隐形守护者》路线）
  题材  = 规则叙事                   （《诡舍》路线）
  视频  = 仅「结局独白 / 立场反转」两类关键节点保留（可灵数字人）

对比基准：tools/fmv_budget.py 的「分层混合」模式
  —— 该模式只把「环境空镜」静态化，A/B 类镜头仍走视频生成。

口径纪律：
  · 主表统一使用 TTS 配音，两侧同标准；真人配音作为独立变量单列。
  · 人力单价 ¥750/人天，为「小团队/自由职业综合日成本」。
  · 不含项目负责人自身的机会成本。

用法：python tools/subtractive_budget.py
"""

DAY_RATE = 750          # 元/人天
LAYERS = 4              # 分层数：far / mid / near / over
FX = 7.2

# ---------------- 单价基准（与 fmv_budget.py 同源，2026-10）----------------
PRICE = {
    "image":       0.20,      # 可灵 Image 3.0            ¥/张
    "avatar":      0.80,      # 可灵数字人 1080P          ¥/秒
    "lipsync":     0.10,      # 可灵对口型 ¥0.5/5秒       ¥/秒
    "tts_char":    0.00072,   # MiniMax speech-2.8-hd     ¥/字
    "voice_clone": 10.80,     # MiniMax 声音克隆          ¥/条
    "sfx":         0.25,      # 可灵文生音效              ¥/次
    "human_line":  45.0,      # 真人配音（中低端棚）      ¥/句
}

# 生成可用率（决定实际调用次数 = 需求数 ÷ 可用率）
U = dict(
    scene=0.40,      # 场景整图（构图 + 风格 + 光线都要对）
    portrait=0.45,   # 立绘（额外要求角色一致性）
    prop=0.50,       # 静物特写（无人物，最稳）
    avatar=0.40,     # 数字人对口型（沿用基准假设）
)

# ---------------- 基准：分层混合（来源 tools/fmv_budget.py · hybrid）--------
BASE = {
    "α 垂直切片": dict(api=1559,  days=52,  other=6000, minutes=14,
                       chars=1451, lines=73,  events=3,  base_shots=118),
    "β 抢先体验": dict(api=4888,  days=156, other=6000, minutes=56,
                       chars=5400, lines=270, events=12, base_shots=514),
    "1.0 完整版": dict(api=7948,  days=287, other=6000, minutes=97,
                       chars=8978, lines=449, events=20, base_shots=906),
}
BASE_LABOR = {
    "α 垂直切片": {"编剧": 8,  "抽卡/Prompt": 12, "剪辑后期": 10, "音效配乐": 5,
                   "UI/程序": 12, "美术指导": 5},
    "β 抢先体验": {"编剧": 25, "抽卡/Prompt": 45, "剪辑后期": 32, "音效配乐": 12,
                   "UI/程序": 28, "美术指导": 14},
    "1.0 完整版": {"编剧": 60, "抽卡/Prompt": 78, "剪辑后期": 58, "音效配乐": 20,
                   "UI/程序": 45, "美术指导": 26},
}

# ---------------- 减法组合：静态资产需求 ----------------
# scene_versions = 场景数 × 平均时段版本数（同一房间的上午/下午/夜晚要分别出图）
# chars/emos     = 主要角色数 × 表情数
# props          = 静物特写（线索物件、白板、报表…）
# vids/vid_sec   = 关键节点视频段数 × 平均秒数
CFG = {
    "α 垂直切片": dict(scene_versions=5,  chars=3, emos=4, props=6,
                       vids=1, vid_sec=15),
    "β 抢先体验": dict(scene_versions=12, chars=5, emos=5, props=16,
                       vids=4, vid_sec=16),
    "1.0 完整版": dict(scene_versions=22, chars=6, emos=6, props=26,
                       vids=8, vid_sec=17),
}

# 减法组合人力（人天）
# 关键结构变化：
#   抽卡/Prompt  →  生图/分层   视频抽卡(可用率 25~40%)换成生图(40~50%)，单位产出快得多
#   剪辑后期     →  动效编排   从「剪视频」变成「给镜头配 zoom/focus/pan/dur」
#   UI/程序             ↑     新增镜头导演、动效系统、镜头表编辑
LABOR_V3 = {
    "α 垂直切片": {"编剧": 9,  "生图/分层": 6,  "动效编排": 8,  "音效配乐": 5,
                   "UI/程序": 16, "美术指导": 4},
    "β 抢先体验": {"编剧": 28, "生图/分层": 19, "动效编排": 24, "音效配乐": 12,
                   "UI/程序": 38, "美术指导": 11},
    "1.0 完整版": {"编剧": 68, "生图/分层": 32, "动效编排": 45, "音效配乐": 20,
                   "UI/程序": 62, "美术指导": 20},
}

CORE_DUB_SHARE = 0.40      # 主角 + 核心 NPC 的台词占比（用于真人配音增量）


def assets(scale):
    """静态资产需求 → (整图数, 切图层数, 立绘数, 静物数, 实际生图调用数)"""
    c = CFG[scale]
    scene_img = c["scene_versions"]
    layer_cuts = scene_img * LAYERS
    portrait_n = c["chars"] * c["emos"]
    prop_n = c["props"]
    calls = (scene_img / U["scene"]
             + portrait_n / U["portrait"]
             + prop_n / U["prop"])
    return scene_img, layer_cuts, portrait_n, prop_n, calls


def api_static(scale):
    _, cuts, pn, prop_n, calls = assets(scale)
    return calls * PRICE["image"], calls, cuts, pn, prop_n


def api_video(scale):
    c = CFG[scale]
    seg, sec = c["vids"], c["vids"] * c["vid_sec"]
    cost = sec / U["avatar"] * (PRICE["avatar"] + PRICE["lipsync"])
    return cost, seg, sec


def api_tts(scale):
    """统一口径：全 TTS"""
    b = BASE[scale]
    return b["chars"] * PRICE["tts_char"] * 1.5, PRICE["voice_clone"] * 8


def api_sfx(scale):
    n = BASE[scale]["events"] * 8 + 40
    return n * PRICE["sfx"], n


def dub_routes(scale):
    """三条配音路线 → (全TTS, 核心真人+其余TTS, 全真人)"""
    b = BASE[scale]
    all_tts = b["chars"] * PRICE["tts_char"] * 1.5
    core = b["lines"] * CORE_DUB_SHARE * PRICE["human_line"]
    all_human = b["lines"] * PRICE["human_line"]
    return all_tts, core, all_human


def full_cost(scale):
    img, calls, cuts, pn, prop_n = api_static(scale)
    vid, seg, sec = api_video(scale)
    tts, clone = api_tts(scale)
    sfx, sfx_n = api_sfx(scale)
    api = img + vid + tts + clone + sfx
    days_v3 = sum(LABOR_V3[scale].values())
    labor_v3 = days_v3 * DAY_RATE
    other = BASE[scale]["other"]
    return dict(img=img, vid=vid, tts=tts, clone=clone, sfx=sfx,
                api=api, days=days_v3, labor=labor_v3, other=other,
                total=api + labor_v3 + other,
                calls=calls, cuts=cuts, seg=seg, sec=sec, pn=pn, prop_n=prop_n)


def base_total(scale):
    b = BASE[scale]
    return b["api"] + b["days"] * DAY_RATE + b["other"]


def money(x):
    return f"\u00a5{x:,.0f}"


def pct(a, b):
    return f"{(a / b - 1):+.1%}" if b else "-"


def main():
    print("=" * 86)
    print("《职级轮回》减法组合成本模型 v3 —— 静态帧 + 引擎动效 + 关键节点视频")
    print(f"汇率 1USD={FX}CNY | 人力 {DAY_RATE} 元/人天 | 分层 {LAYERS} 层 | 配音口径：全 TTS")
    print("=" * 86)

    scales = list(CFG)

    # ---------- 1. 静态资产需求 ----------
    print("\n" + "-" * 86)
    print("【1】静态资产需求（减法组合）")
    print("-" * 86)
    print(f"  {'规模':<12}{'场景整图':>9}{'切图层数':>9}{'立绘':>7}{'静物':>7}"
          f"{'实际生图调用':>13}{'关键视频段':>11}{'关键视频秒':>11}")
    for s in scales:
        _, calls, cuts, pn, prop_n = api_static(s)
        _, seg, sec = api_video(s)
        print(f"  {s:<12}{CFG[s]['scene_versions']:>9}{cuts:>9}{pn:>7}{prop_n:>7}"
              f"{calls:>13.0f}{seg:>11}{sec:>11}")

    # ---------- 2. API 成本对比 ----------
    print("\n" + "-" * 86)
    print("【2】API 生成成本对比（配音统一为 TTS）")
    print("-" * 86)
    print(f"  {'规模':<12}{'基准·分层混合':>15}{'减法组合':>11}{'差额':>12}{'降幅':>10}")
    for s in scales:
        r = full_cost(s)
        b = BASE[s]["api"]
        print(f"  {s:<12}{money(b):>15}{money(r['api']):>11}"
              f"{money(r['api'] - b):>12}{pct(r['api'], b):>10}")

    print("\n  减法组合 API 明细")
    print(f"  {'规模':<12}{'静态图':>10}{'关键视频':>11}{'TTS':>8}"
          f"{'音色克隆':>10}{'音效':>8}{'合计':>10}")
    for s in scales:
        r = full_cost(s)
        print(f"  {s:<12}{money(r['img']):>10}{money(r['vid']):>11}"
              f"{money(r['tts']):>8}{money(r['clone']):>10}"
              f"{money(r['sfx']):>8}{money(r['api']):>10}")

    print(f"\n  → 视频生成 API 降幅：1.0 完整版 {money(BASE['1.0 完整版']['api'])}"
          f" → {money(full_cost('1.0 完整版')['api'])}"
          f"（{pct(full_cost('1.0 完整版')['api'], BASE['1.0 完整版']['api'])}）")

    # ---------- 3. 人力结构对比 ----------
    print("\n" + "-" * 86)
    print("【3】人力结构对比（人天）—— 本模型的核心")
    print("-" * 86)
    order = ["编剧", "生图/分层", "动效编排", "音效配乐", "UI/程序", "美术指导"]
    pairs = {"生图/分层": "抽卡/Prompt", "动效编排": "剪辑后期"}
    for s in scales:
        print(f"\n  [{s}]")
        print(f"  {'角色':<14}{'基准':>10}{'减法组合':>12}{'变化':>10}")
        for role in order:
            bv = BASE_LABOR[s].get(pairs.get(role, role), 0)
            nv = LABOR_V3[s][role]
            print(f"  {role:<14}{bv:>10}{nv:>12}{nv - bv:>+10}")
        tb, tn = sum(BASE_LABOR[s].values()), sum(LABOR_V3[s].values())
        print(f"  {'合计':<14}{tb:>10}{tn:>12}{tn - tb:>+10}"
              f"   ({tn * DAY_RATE:,} 元)")

    # ---------- 4. 全成本对比 ----------
    print("\n" + "-" * 86)
    print("【4】项目全成本对比")
    print("-" * 86)
    print(f"  {'规模':<12}{'基准全成本':>15}{'减法组合':>14}{'差额':>13}{'降幅':>10}")
    for s in scales:
        r = full_cost(s)
        bt = base_total(s)
        print(f"  {s:<12}{money(bt):>15}{money(r['total']):>14}"
              f"{money(r['total'] - bt):>13}{pct(r['total'], bt):>10}")

    for s in scales:
        r = full_cost(s)
        print(f"\n  [{s}] 构成")
        print(f"    API 生成+素材 {money(r['api']):>12}   {r['api'] / r['total']:>6.1%}")
        print(f"    人力投入      {money(r['labor']):>12}   {r['labor'] / r['total']:>6.1%}"
              f"   ({r['days']} 人天)")
        print(f"    其他一次性    {money(r['other']):>12}   {r['other'] / r['total']:>6.1%}")
        print(f"    合计          {money(r['total']):>12}")

    # ---------- 5. 配音路线（独立变量） ----------
    print("\n" + "-" * 86)
    print("【5】配音路线（与画面减法无关，可独立决策）")
    print("-" * 86)
    print(f"  {'规模':<12}{'全 TTS':>10}{'核心真人+其余TTS':>18}{'全真人':>12}"
          f"{'核心方案增量':>14}")
    for s in scales:
        a, c, h = dub_routes(s)
        print(f"  {s:<12}{money(a):>10}{money(c):>18}{money(h):>12}"
              f"{money(c - a):>14}")
    print(f"\n  注：「核心真人」= 主角 + 2 名核心 NPC，台词占比按 {CORE_DUB_SHARE:.0%} 估。")
    print(f"      若采此方案，1.0 完整版全成本变为 "
          f"{money(full_cost('1.0 完整版')['total'] + dub_routes('1.0 完整版')[1] - dub_routes('1.0 完整版')[0])}")

    # ---------- 6. 单位成片成本 ----------
    print("\n" + "-" * 86)
    print("【6】单位成片成本（对标真人实拍）")
    print("-" * 86)
    print(f"  {'口径':<32}{'总投入':>14}{'成片':>8}{'元/分钟':>12}")
    for s in scales:
        r = full_cost(s)
        m = BASE[s]["minutes"]
        print(f"  {'减法组合 · ' + s:<32}{money(r['total']):>14}"
              f"{str(m) + '分':>8}{r['total'] / m:>12,.0f}")
    print(f"  {'真人实拍 · 《完蛋》对标':<32}{money(5000000):>14}"
          f"{'~350分':>8}{5000000 / 350:>12,.0f}")
    print("  注：α 档元/分钟偏高，因为 ¥6,000 一次性支出与引擎开发摊在 14 分钟上。")

    # ---------- 7. 敏感性 ----------
    print("\n" + "-" * 86)
    print("【7】敏感性分析（1.0 完整版）")
    print("-" * 86)
    r = full_cost("1.0 完整版")
    fixed_labor = (LABOR_V3["1.0 完整版"]["编剧"]
                   + LABOR_V3["1.0 完整版"]["音效配乐"]
                   + LABOR_V3["1.0 完整版"]["UI/程序"]
                   + LABOR_V3["1.0 完整版"]["美术指导"]) * DAY_RATE

    print(f"\n  (a) 静态图生成量放大 —— 几乎不影响预算")
    print(f"  {'情景':<24}{'图 API':>11}{'全成本':>14}{'绝对变化':>12}")
    for label, mult in [("0.7x", 0.7), ("基准 1.0x", 1.0),
                        ("1.5x", 1.5), ("2.0x", 2.0), ("4.0x", 4.0)]:
        img = r["img"] * mult
        t = r["total"] - r["img"] + img
        print(f"  {label:<24}{money(img):>11}{money(t):>14}"
              f"{money(t - r['total']):>12}")

    print(f"\n  (b) 生图/分层 + 动效编排 人力 —— 本模型最大不确定项")
    print(f"  {'情景':<24}{'该两项人天':>11}{'全成本':>14}{'相对基准':>11}")
    two = LABOR_V3["1.0 完整版"]["生图/分层"] + LABOR_V3["1.0 完整版"]["动效编排"]
    for label, mult in [("0.7x（模板化顺利）", 0.7), ("基准 1.0x", 1.0),
                        ("1.5x（返工偏多）", 1.5), ("2.0x（新手期）", 2.0)]:
        d = two * mult
        t = r["api"] + fixed_labor + d * DAY_RATE + r["other"]
        print(f"  {label:<24}{d:>11.0f}{money(t):>14}{t / r['total']:>10.1%}")

    print(f"\n  对照：基准模型的「抽卡可用率」翻倍 → 全成本 +3%")
    print(f"        本模型的「静态图量」  翻 4 倍 → 全成本 "
          f"{(r['total'] + r['img'] * 3) / r['total'] - 1:+.2%}")

    # ---------- 8. 不确定性结构 ----------
    print("\n" + "-" * 86)
    print("【8】不确定性结构变化（1.0 完整版）")
    print("-" * 86)
    b = BASE["1.0 完整版"]
    print(f"  {'口径':<30}{'基准·分层混合':>20}{'减法组合':>20}")
    print(f"  {'需「抽卡」的关键生成量':<30}{'906 段视频':>20}"
          f"{'187 张图 + 8 段视频':>20}")
    print(f"  {'高不确定环节占镜头比例':<30}{'82%（A类口型）':>20}{'1%（仅关键节点）':>20}")
    print(f"  {'API 依赖度':<30}{b['api'] / base_total('1.0 完整版'):>19.1%}"
          f"{r['api'] / r['total']:>20.1%}")
    print(f"  {'人力占比':<30}"
          f"{b['days'] * DAY_RATE / base_total('1.0 完整版'):>19.1%}"
          f"{r['labor'] / r['total']:>20.1%}")
    print(f"\n  → 外部不确定项（AI 模型行为，你控制不了）几乎归零；")
    print(f"     剩余不确定项是内部工时（你自己团队的速度），可通过 α 切片实测收敛。")

    # ---------- 9. 回本 ----------
    print("\n" + "-" * 86)
    print("【9】回本测算（Steam 30% 分成后净收入）")
    print("-" * 86)
    print(f"  {'售价':<8}{'规模':<14}{'全成本':>14}{'单套净收':>12}{'回本销量':>12}")
    for price in (42, 58):
        net = price * 0.70
        for s in scales:
            t = full_cost(s)["total"]
            print(f"  {money(price):<8}{s:<14}{money(t):>14}"
                  f"{money(net):>12}{t / net:>10,.0f} 套")
        print()

    print("=" * 86)
    print("注：LABOR_V3 的「生图/分层」「动效编排」为结构性估算。")
    print("    做完 α 切片后，用实际工时替换这两项，全表即自动重算。")
    print("=" * 86)


if __name__ == "__main__":
    main()
