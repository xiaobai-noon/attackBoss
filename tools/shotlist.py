#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
《打boss》拍摄单生成器 / 镜头表校验器

做三件事：
  1. 校验 data/shots.json —— schema、运动学约束（过扫/除零）、move 标签与数值是否自相矛盾
  2. 扫描 data/story/*.json —— 对话图完整性 + 镜头引用完整性 + 缺登记场景
  3. 汇总"到底要生产多少素材" —— 分层图 / 静物特写 / 立绘 / 视频，并给生成次数与费用估算
     输出 docs/拍摄单.md，可以直接当生产清单用

用法：
  python tools/shotlist.py
  python tools/shotlist.py --img-price 0.20 --clip-price 0.80 --img-rate 0.35 --clip-rate 0.40
  python tools/shotlist.py --no-write          # 只打印，不落盘

单价默认值来源见 docs/FMV预算分析.md 第二节，可按实际账单覆盖。
"""
from __future__ import annotations

import argparse
import io
import json
import math
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SHOTS_PATH = ROOT / "data" / "shots.json"
STORY_DIR = ROOT / "data" / "story"
OUT_PATH = ROOT / "docs" / "拍摄单.md"

MIN_ZOOM = 1.02
VALID_CUTS = {"cut", "fade", "flash"}
VALID_NODE_TYPES = {"bg", "shot", "line", "choice", "effect", "branch", "goto", "end"}
SPEAKER_SPECIAL = {"narrator", "player"}

# 每个场景的标准分层。少一层不算错（静物特写只要一层），但要能解释。
STANDARD_LAYERS = ("far", "mid", "near")


# ---------------------------------------------------------------- 工具

def load_json(p: Path):
    with io.open(p, encoding="utf-8") as f:
        return json.load(f)


def mag(v) -> float:
    return math.sqrt(v[0] ** 2 + v[1] ** 2)


def in_range(v, lo, hi) -> bool:
    return lo <= v[0] <= hi and lo <= v[1] <= hi


# ---------------------------------------------------------------- 1. 镜头表校验

def validate_shots(table: dict):
    errors: list[str] = []
    warnings: list[str] = []
    shots_index: dict[str, dict] = {}

    if int(table.get("version", 0)) < 1:
        errors.append("shots.json 缺 version 字段")

    depth = table.get("depth", {})
    if not depth:
        errors.append("shots.json 缺 depth 视差系数表")
    for k, v in depth.items():
        if not (0.0 < float(v) <= 1.2):
            errors.append(f"depth.{k} = {v} 超出合理区间 (0, 1.2]")
    max_depth_default = max(depth.values()) if depth else 1.0

    moves = table.get("moves", {})
    scenes = table.get("scenes", {})
    if not scenes:
        errors.append("shots.json 没有任何场景")

    for scene_id, scene in scenes.items():
        shots = scene.get("shots", {})
        if not shots:
            warnings.append(f"场景 {scene_id} 未定义任何镜头")
            continue
        entry = str(scene.get("entry", ""))
        if not entry:
            errors.append(f"{scene_id}: 缺 entry（定场镜头）")
        elif entry not in shots:
            errors.append(f"{scene_id}: entry「{entry}」不在该场景镜头表里")

        for side, sid in scene.get("reverse", {}).items():
            if side not in ("left", "right"):
                errors.append(f"{scene_id}: reverse 只支持 left/right，出现「{side}」")
            if sid not in shots:
                errors.append(f"{scene_id}: reverse.{side} → 不存在的镜头「{sid}」")

        for shot_id, shot in shots.items():
            if shot_id in shots_index:
                errors.append(f"镜头 id 重复：{shot_id}（{scene_id} 与 {shots_index[shot_id]['scene']}）")
            shots_index[shot_id] = {"scene": scene_id, "shot": shot, "id": shot_id}
            errors += [f"{shot_id}: {e}" for e in _validate_one_shot(
                shot_id, shot, depth, max_depth_default, moves)]

    return errors, warnings, shots_index


def _validate_one_shot(shot_id, shot, depth, max_depth_default, moves):
    errs: list[str] = []

    if not str(shot.get("label", "")).strip():
        errs.append("缺 label（拍摄单靠它给美术讲清楚要什么画面）")

    move = str(shot.get("move", ""))
    if move not in moves:
        errs.append(f"move「{move}」不在 moves 枚举里")

    zoom = shot.get("zoom", [])
    if not (isinstance(zoom, list) and len(zoom) == 2):
        errs.append("zoom 必须是 [起点, 终点]")
        return errs
    z0, z1 = float(zoom[0]), float(zoom[1])
    if z0 < MIN_ZOOM or z1 < MIN_ZOOM:
        errs.append(f"zoom {zoom} 低于 {MIN_ZOOM}：会露图片边缘，且 z=1 会触发除零")

    focus = shot.get("focus", [])
    if not (isinstance(focus, list) and len(focus) == 2 and in_range([float(focus[0]), float(focus[1])], 0.0, 1.0)):
        errs.append(f"focus {focus} 必须是 [x, y] 且都在 0~1")

    pan = shot.get("pan", [])
    if not (isinstance(pan, list) and len(pan) == 2 and all(isinstance(p, list) and len(p) == 2 for p in pan)):
        errs.append("pan 必须是 [[x0,y0],[x1,y1]]")
        return errs
    p0 = [float(pan[0][0]), float(pan[0][1])]
    p1 = [float(pan[1][0]), float(pan[1][1])]

    if float(shot.get("dur", 0)) <= 0:
        errs.append("dur 必须 > 0")

    cut = str(shot.get("cut", "cut"))
    if cut not in VALID_CUTS:
        errs.append(f"cut「{cut}」不合法，可选 {sorted(VALID_CUTS)}")

    grade = shot.get("grade", [])
    if grade:
        if not (isinstance(grade, list) and len(grade) == 2):
            errs.append("grade 必须是 [\"#RRGGBB\", 透明度]")
        else:
            hexs = str(grade[0])
            if not (hexs.startswith("#") and len(hexs) == 7):
                errs.append(f"grade 颜色「{hexs}」应为 #RRGGBB")
            if not (0.0 <= float(grade[1]) <= 1.0):
                errs.append("grade 透明度必须 0~1")

    layers = shot.get("layers", {})
    if not layers:
        errs.append("layers 为空：这个镜头没有任何图可画")
    for lname, lpath in layers.items():
        if lname not in depth:
            errs.append(f"图层名「{lname}」不在 depth 表里")
        if not str(lpath).startswith("res://"):
            errs.append(f"图层路径必须是 res:// 开头：{lpath}")

    clip = str(shot.get("clip", ""))
    if clip and not clip.endswith(".ogv"):
        errs.append(f"clip「{clip}」必须是 .ogv —— Godot 4 核心只支持 Ogg Theora，"
                    "H.264/WebM 一律要先用 ffmpeg 转码")
    if bool(shot.get("clip_candidate", False)) and float(shot.get("clip_dur", 0)) <= 0:
        errs.append("标了 clip_candidate 就必须给 clip_dur（秒），否则视频预算算不出来")

    # —— 过扫约束：|pan| × 最大图层深度 ≤ (zoom - 1) / 2 ——
    dmax = max([float(depth.get(k, max_depth_default)) for k in layers] or [max_depth_default])
    for z, p, tag in ((z0, p0, "起点"), (z1, p1, "终点")):
        room = (z - 1.0) / 2.0 - 0.002
        need = mag(p) * dmax
        if need > room:
            errs.append(
                f"{tag}过扫不足：pan {p} × 深度 {dmax:.2f} 需要 {need:.4f} 的余量，"
                f"但 zoom {z:.3f} 只给了 {room:.4f}。把 zoom 提到 ≥ {1 + 2 * need:.3f}，或把 pan 缩小到 {room / dmax:.4f}"
            )

    # —— move 标签必须和数值说得一致，否则拍摄单会误导美术 ——
    dz = z1 - z0
    dpan = [p1[0] - p0[0], p1[1] - p0[1]]
    pmag = max(mag(p0), mag(p1))
    shake = float(shot.get("shake", 0))

    def bad(msg):
        errs.append(f"move=\"{move}\" 与数值不符：{msg}")

    if move == "in":
        if dz <= 0.005:
            bad("推近要求 zoom 递增")
        if pmag > 0.02:
            bad("推近不该有位移，pan 应接近 0")
    elif move == "out":
        if dz >= -0.005:
            bad("拉远要求 zoom 递减")
        if pmag > 0.02:
            bad("拉远不该有位移")
    elif move == "pan_l":
        if dpan[0] >= -0.005:
            bad("左移要求 pan.x 递减")
    elif move == "pan_r":
        if dpan[0] <= 0.005:
            bad("右移要求 pan.x 递增")
    elif move == "tilt_u":
        if dpan[1] >= -0.005:
            bad("上摇要求 pan.y 递减")
    elif move == "tilt_d":
        if dpan[1] <= 0.005:
            bad("下摇要求 pan.y 递增")
    elif move == "hold":
        if abs(dz) > 0.012:
            bad("定镜微呼吸的 zoom 变化应 ≤ 0.012（要的是「活着」，不是推拉）")
        if pmag > 0.006:
            bad("定镜不该位移")
    elif move == "push_shake":
        if dz <= 0.02:
            bad("推近 + 震动要求明显推近")
        if shake <= 0:
            bad("push_shake 必须给 shake 振幅")

    # hold 类镜头必须 loop，否则播完就死在最后一帧
    if move == "hold" and not bool(shot.get("loop", False)):
        errs.append("move=hold 的镜头应设 loop=true，否则微呼吸会停")

    return errs


# ---------------------------------------------------------------- 2. 剧本扫描 + 对话图校验

def walk_graph(nodes, entry, max_depth=200):
    """穷举所有分支路径，返回 (路径列表, 异常列表)"""
    results, problems = [], []

    def walk(nid, path, depth):
        if depth > max_depth:
            problems.append(f"深度超过 {max_depth}，疑似环：{' -> '.join(path[-4:])}")
            return
        n = nodes.get(nid)
        if n is None:
            problems.append(f"断链：{path[-1] if path else entry} -> 不存在的 {nid}")
            return
        t = n.get("type")
        if t == "end":
            results.append(path)
            return
        if t == "choice":
            for i, o in enumerate(n.get("options", []), 1):
                walk(str(o.get("goto", "")), path + [f"{nid}#选{i}"], depth + 1)
            return
        if t == "branch":
            for c in n.get("conditions", []):
                walk(str(c.get("goto", "")), path + [f"{nid}#cond"], depth + 1)
            walk(str(n.get("default", "")), path + [f"{nid}#default"], depth + 1)
            return
        nxt = str(n.get("goto", "") or n.get("next", ""))
        if not nxt:
            problems.append(f"{nid}: 非 end 节点却没有出口")
            return
        walk(nxt, path + [nid], depth + 1)

    walk(entry, [], 0)
    return results, problems


def scan_stories(shots_index):
    errors: list[str] = []
    warnings: list[str] = []
    used_shots: set[str] = set()
    used_scenes: dict[str, set[str]] = {}      # scene -> {story_id}
    portraits: dict[str, set[str]] = {}        # npc -> {emotion}
    stories = []

    for p in sorted(STORY_DIR.glob("*.json")):
        story = load_json(p)
        sid = str(story.get("id", p.stem))
        nodes = story.get("nodes", {})
        entry = str(story.get("entry", ""))

        if entry not in nodes:
            errors.append(f"{sid}: entry「{entry}」不存在")
            continue

        # 节点类型 / 引用
        for nid, n in nodes.items():
            t = str(n.get("type", ""))
            if t not in VALID_NODE_TYPES:
                errors.append(f"{sid}.{nid}: 未知节点类型「{t}」")
            if t == "shot":
                target = str(n.get("shot", ""))
                if not target:
                    errors.append(f"{sid}.{nid}: shot 节点缺 shot 字段")
                elif target not in shots_index:
                    errors.append(f"{sid}.{nid}: 引用了镜头表里不存在的镜头「{target}」")
                else:
                    used_shots.add(target)
            if t == "bg":
                scene = str(n.get("scene", ""))
                if scene:
                    used_scenes.setdefault(scene, set()).add(sid)
            if t == "line":
                sp = str(n.get("speaker", "narrator"))
                if sp not in SPEAKER_SPECIAL:
                    portraits.setdefault(sp, set()).add(str(n.get("emotion", "neutral")))

        paths, problems = walk_graph(nodes, entry)
        for pb in problems:
            errors.append(f"{sid}: {pb}")
        if not paths:
            errors.append(f"{sid}: 没有任何一条路径能走到 end")

        stories.append({
            "id": sid, "file": p.name, "title": str(story.get("title", "")),
            "nodes": len(nodes), "paths": len(paths),
            "shot_nodes": sum(1 for n in nodes.values() if n.get("type") == "shot"),
            "line_nodes": sum(1 for n in nodes.values() if n.get("type") == "line"),
        })

    return errors, warnings, used_shots, used_scenes, portraits, stories


# ---------------------------------------------------------------- 3. 素材清单

def build_requirements(table, shots_index, used_shots, used_scenes, portraits):
    depth = table.get("depth", {})
    scenes = table.get("scenes", {})

    # 范围标记：scope.alpha.scenes 里的场景属于当前要做的 α 切片，其余为预留。
    # 没有 scope 块时不做区分（全部视为 α），保持向后兼容。
    alpha_scenes = set((table.get("scope", {}).get("alpha", {}) or {}).get("scenes", []))
    has_scope = bool(alpha_scenes)

    def scope_of(scene_id: str) -> str:
        return "α" if (not has_scope or scene_id in alpha_scenes) else "预留"

    # 场景分层图
    bg_rows = []
    for scene_id, scene in sorted(scenes.items()):
        for sname, shot in sorted(scene.get("shots", {}).items()):
            layers = shot.get("layers", {})
            for lname, lpath in sorted(layers.items()):
                bg_rows.append({
                    "scene": scene_id,
                    "scene_name": str(scene.get("name", scene_id)),
                    "shot": sname,
                    "layer": lname,
                    "path": str(lpath),
                    "used": (sname in used_shots),
                    "kind": "静物特写" if len(layers) == 1 else "分层场景",
                    "scope": scope_of(scene_id),
                })

    stills = {r["path"] for r in bg_rows}
    used_stills = {r["path"] for r in bg_rows if r["used"]}
    alpha_stills = {r["path"] for r in bg_rows if r["scope"] == "α"}
    clips = []
    for sname, rec in sorted(shots_index.items()):
        shot = rec["shot"]
        if str(shot.get("clip", "")):
            clips.append({"shot": sname, "path": str(shot["clip"]), "dur": float(shot.get("clip_dur", 0))})
        elif bool(shot.get("clip_candidate", False)):
            clips.append({"shot": sname, "path": "(待生成)", "dur": float(shot.get("clip_dur", 0))})

    missing_scenes = sorted(s for s in used_scenes if s not in scenes)
    unused_shots = sorted(set(shots_index) - used_shots)

    return {
        "bg_rows": bg_rows,
        "stills": stills, "used_stills": used_stills, "alpha_stills": alpha_stills,
        "clips": clips,
        "missing_scenes": missing_scenes,
        "unused_shots": unused_shots,
        "portraits": portraits,
        "scope": table.get("scope", {}),
    }


# ---------------------------------------------------------------- 4. 渲染

def render(table, req, stats, args) -> str:
    L: list[str] = []
    A = L.append
    src = table.get("source_size", [2560, 1440])
    dsg = table.get("design_size", [1280, 720])

    n_portrait = sum(len(v) for v in req["portraits"].values())
    n_still = len(req["stills"])
    gen_still = math.ceil(n_still / args.img_rate) if args.img_rate > 0 else n_still
    cost_still = gen_still * args.img_price

    clip_sec = sum(c["dur"] for c in req["clips"])
    gen_clip = math.ceil(clip_sec / args.clip_rate) if args.clip_rate > 0 else clip_sec
    cost_clip = gen_clip * args.clip_price

    A("# 《打boss》拍摄单（自动生成）")
    A("")
    A("> 由 `tools/shotlist.py` 从 `data/shots.json` + `data/story/*.json` 反推得出。")
    A("> 改完剧本或镜头表重跑一次即可，不要手改本文件。")
    A("")
    A("## 一、总量")
    A("")
    A("| 项 | 数量 | 说明 |")
    A("|---|---|---|")
    A(f"| 出图规格 | {src[0]} × {src[1]} | 设计分辨率 {dsg[0]}×{dsg[1]} 的 2 倍，"
      "引擎要从同一张图裁出近/中/特写 |")
    A(f"| 场景分层图 | **{n_still}** 张 | 含静物特写 |")
    A(f"| 其中 **α 范围** | **{len(req['alpha_stills'])}** 张 | 当前唯一在做的范围（见 `docs/α切片范围.md`） |")
    A(f"| 其中已被剧本引用 | {len(req['used_stills'])} 张 | 剩余是 α 内但剧本尚未写到的场景 |")
    A(f"| 立绘（角色 × 表情） | **{n_portrait}** 张 | {len(req['portraits'])} 个角色 |")
    A(f"| 视频层 | **{len(req['clips'])}** 条 / {clip_sec:.0f} 秒 | 仅结局独白与立场反转 |")
    A(f"| 剧本总数 | {len(stats['stories'])} 个 | 共 "
      f"{sum(s['nodes'] for s in stats['stories'])} 节点 / "
      f"{sum(s['shot_nodes'] for s in stats['stories'])} 次切镜 |")
    A("")

    scope = req.get("scope", {})
    alpha_cfg = (scope.get("alpha", {}) or {}) if scope else {}
    if alpha_cfg:
        A(f"### 当前范围：{alpha_cfg.get('name', 'α')}")
        A("")
        A(f"- **场景**：{'、'.join(f'`{s}`' for s in alpha_cfg.get('scenes', []))}")
        A(f"- **事件**：{'、'.join(f'`{e}`' for e in alpha_cfg.get('events', []))}")
        A(f"- **结局**：`{alpha_cfg.get('ending', '')}`")
        if alpha_cfg.get("note"):
            A(f"- {alpha_cfg['note']}")
        reserved = scope.get("reserved", {}) or {}
        if reserved.get("scenes"):
            A(f"- **预留不做**：{'、'.join(f'`{s}`' for s in reserved['scenes'])}"
              + (f" —— {reserved['note']}" if reserved.get("note") else ""))
        A("")
    A("## 二、费用估算（含抽卡损耗）")
    A("")
    A("| 项 | 需求 | 可用率 | 实际生成 | 单价 | 小计 |")
    A("|---|---|---|---|---|---|")
    A(f"| 静态生图 | {n_still} 张 | {args.img_rate:.0%} | {gen_still} 张 | "
      f"¥{args.img_price:.2f}/张 | **¥{cost_still:,.0f}** |")
    A(f"| 数字人 / 视频 | {clip_sec:.0f} 秒 | {args.clip_rate:.0%} | {gen_clip:.0f} 秒 | "
      f"¥{args.clip_price:.2f}/秒 | **¥{cost_clip:,.0f}** |")
    A(f"| **合计** | | | | | **¥{cost_still + cost_clip:,.0f}** |")
    A("")
    A(f"口径：单价与可用率默认值取自 `docs/FMV预算分析.md`（静态生图可用率 {args.img_rate:.0%}、"
      f"数字人 {args.clip_rate:.0%}）。**这两个数是全表最不确定的参数**，"
      "建议先花几千块压测 20 张图 / 20 段对白，拿到真实数字后用 CLI 覆盖。")
    A("")
    A("> 范围口径：本表区分「α 范围」与「预留」。α 是当前唯一在做的范围，"
      "定义见 [`α切片范围.md`](α切片范围.md)；预留部分**不要提前生产**。")
    A("")

    # —— 场景分层图 ——
    A("## 三、场景分层图")
    A("")
    A("图层含义：`far` 远景（窗外/走廊尽头，动最少）· `mid` 中景（房间主体）· "
      "`near` 近景（靠镜头的家具）· `over` 前景遮挡（文件堆、门框、显示器背面，动最多）。")
    A("")
    used = [r for r in req["bg_rows"] if r["used"]]
    rest = [r for r in req["bg_rows"] if not r["used"]]
    alpha_rows = [r for r in req["bg_rows"] if r["scope"] == "α"]
    reserved_rows = [r for r in req["bg_rows"] if r["scope"] != "α"]
    groups = (("α 范围 · 当前要做", alpha_rows), ("预留 · α 不做", reserved_rows)) \
        if req.get("scope") else (("剧本已引用（优先做）", used), ("预留（暂不阻塞开发）", rest))
    for group, rows in groups:
        if not rows:
            continue
        A(f"### {group}")
        A("")
        A("| 场景 | 镜头 | 层 | 类型 | 剧本引用 | 文件 |")
        A("|---|---|---|---|---|---|")
        for r in rows:
            A(f"| {r['scene_name']} | `{r['shot']}` | {r['layer']} | {r['kind']} | "
              f"{'✓' if r['used'] else '—'} | `{r['path'].replace('res://', '')}` |")
        A("")

    # —— 立绘 ——
    A("## 四、立绘")
    A("")
    if req["portraits"]:
        A("| 角色 | 需要表情 | 张数 |")
        A("|---|---|---|")
        for npc, emos in sorted(req["portraits"].items()):
            A(f"| {npc} | {', '.join(sorted(emos))} | {len(emos)} |")
        A("")
        A("**立绘只出正面定妆一套**，不做多角度。不同景别靠同一张图的裁切实现；"
          "视频层由可灵数字人以同一张立绘为输入驱动 —— 脸是同一张脸，"
          "AI 跨镜头一致性风险在这里被结构性消掉。")
    else:
        A("（剧本里还没有 NPC 台词）")
    A("")

    # —— 视频层 ——
    A("## 五、视频层（8% 预算）")
    A("")
    if req["clips"]:
        A("| 镜头 | 时长 | 文件 / 状态 |")
        A("|---|---|---|")
        for c in req["clips"]:
            A(f"| `{c['shot']}` | {c['dur']:.1f}s | {c['path']} |")
    else:
        A("**当前 0 条。** 这是符合预期的 —— 视频层是最后才做的，而且只在剧本用 "
          "`\"clip_candidate\": true` 明确标注时才计入。")
    A("")
    A("准入三条硬标准（全中才允许用视频，否则一律静态帧）：")
    A("")
    A("1. 只在**立场反转**（关系/态度发生不可逆扭转）或**结局独白**；")
    A("2. 是**中近景**，不出现大幅肢体动作或走动；")
    A("3. 该台词的时长 ≥ 3 秒（太短的镜头不值得付转码与包体代价）。")
    A("")
    A("技术红线：Godot 4 核心**只支持 Ogg Theora（.ogv）**，不支持 H.264 / WebM。"
      "可灵返回的 MP4 必须走 ffmpeg 转码：")
    A("")
    A("```bash")
    A("# 1080p 30fps，Theora 是纯 CPU 解码，分辨率再高就得吃性能")
    A("ffmpeg -i in.mp4 -c:v libtheora -q:v 8 -c:a libvorbis -q:a 5 -r 30 out.ogv")
    A("```")
    A("")

    # —— 剧本概览 ——
    A("## 六、剧本概览")
    A("")
    A("| 剧本 | 标题 | 节点 | 台词 | 切镜 | 可达路径 |")
    A("|---|---|---|---|---|---|")
    for s in stats["stories"]:
        A(f"| `{s['id']}` | {s['title']} | {s['nodes']} | {s['line_nodes']} | "
          f"{s['shot_nodes']} | {s['paths']} |")
    A("")
    if stats["unused_shots"]:
        A(f"预留未用镜头（{len(stats['unused_shots'])} 个）："
          + "、".join(f"`{s}`" for s in stats["unused_shots"]))
        A("")

    # —— 校验结果 ——
    A("## 七、校验结果")
    A("")
    if stats["missing_scenes"]:
        A("### 待补登记的场景（剧本用了，但 shots.json 里没有镜头）")
        A("")
        for s in stats["missing_scenes"]:
            A(f"- `{s}` —— 该场景目前只显示纯色底，需要补 entry / reverse / shots")
        A("")
    if stats["errors"]:
        A(f"### 错误（{len(stats['errors'])} 条）")
        A("")
        for e in stats["errors"]:
            A(f"- {e}")
        A("")
    else:
        A("镜头表与剧本校验：**全部通过**（schema、过扫约束、move 标签自洽、镜头引用、对话图可达性）。")
        A("")
    if stats["warnings"]:
        A(f"### 提示（{len(stats['warnings'])} 条）")
        A("")
        for w in stats["warnings"]:
            A(f"- {w}")
        A("")

    return "\n".join(L)


# ---------------------------------------------------------------- main

def main() -> int:
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass

    ap = argparse.ArgumentParser(description="生成《打boss》拍摄单并校验镜头表")
    ap.add_argument("--img-price", type=float, default=0.20, help="静态生图单价（元/张）")
    ap.add_argument("--clip-price", type=float, default=0.80, help="视频单价（元/秒）")
    ap.add_argument("--img-rate", type=float, default=0.35, help="静态生图可用率")
    ap.add_argument("--clip-rate", type=float, default=0.40, help="数字人可用率")
    ap.add_argument("--no-write", action="store_true", help="只打印，不写 docs/拍摄单.md")
    args = ap.parse_args()

    if not SHOTS_PATH.exists():
        print(f"[FAIL] 找不到镜头表：{SHOTS_PATH}", file=sys.stderr)
        return 1
    table = load_json(SHOTS_PATH)

    errs, warns, index = validate_shots(table)
    serrs, swarns, used_shots, used_scenes, portraits, stories = scan_stories(index)
    errs += serrs
    warns += swarns

    req = build_requirements(table, index, used_shots, used_scenes, portraits)
    stats = {
        "errors": errs, "warnings": warns,
        "missing_scenes": req["missing_scenes"], "unused_shots": req["unused_shots"],
        "stories": stories,
    }

    md = render(table, req, stats, args)

    print("─" * 72)
    print("镜头表校验")
    print("─" * 72)
    print(f"  场景 {len(table.get('scenes', {}))} 个 ｜ 镜头 {len(index)} 个 ｜ 剧本 {len(stories)} 个")
    print(f"  错误 {len(errs)} 条 ｜ 提示 {len(warns)} 条")
    for e in errs:
        print(f"  [错误] {e}")
    for w in warns:
        print(f"  [提示] {w}")

    print()
    print("─" * 72)
    print("素材需求")
    print("─" * 72)
    n_still = len(req["stills"])
    n_port = sum(len(v) for v in req["portraits"].values())
    gen_still = math.ceil(n_still / args.img_rate) if args.img_rate > 0 else n_still
    print(f"  场景分层图 {n_still} 张（α 范围 {len(req['alpha_stills'])} 张，已引用 {len(req['used_stills'])}）"
          f"  → 按可用率 {args.img_rate:.0%} 需生成 {gen_still} 张 ≈ ¥{gen_still * args.img_price:,.0f}")
    print(f"  立绘 {n_port} 张（{len(req['portraits'])} 个角色）")
    print(f"  视频层 {len(req['clips'])} 条")
    if req["missing_scenes"]:
        print(f"  待补登记场景：{', '.join(req['missing_scenes'])}")

    if not args.no_write:
        OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
        with io.open(OUT_PATH, "w", encoding="utf-8") as f:
            f.write(md)
        print()
        print(f"  已写出：{OUT_PATH.relative_to(ROOT).as_posix()}")

    return 1 if errs else 0


if __name__ == "__main__":
    sys.exit(main())
