# -*- coding: utf-8 -*-
"""
路引生成器 —— 读取 Harmony 轨迹 JSON，提取关键节点（门/电梯/门禁等标签），
调用本地 Ollama 生成面向用户的分步导航路引。

用法:
    python generate_guidance.py <轨迹文件.json>            按轨迹录制方向生成
    python generate_guidance.py <轨迹文件.json> --reverse  反向（如"大门 → 410门口"）
    python generate_guidance.py --dry-run                  只打印中间数据与提示词，不调用模型

依赖: 仅标准库；需要本机 Ollama 已运行（模型默认 qwen3:8b）。
"""
import sys
import os
import json
import math
import glob
import bisect
import urllib.request

OLLAMA_URL = "http://localhost:11434/api/chat"
MODEL = "qwen3:8b"
HARMONY_DIR = r"D:\CityUproject\TrajectoryData\Harmony"

SYSTEM_PROMPT = (
    "你是校园导航助手，为普通用户（新生）生成清晰友好的步行路引。"
    "用户会给你一段轨迹的节点序列（每个节点含：名称、出发方向、距上一节点耗时/位移/高度变化）。"
    "请输出：1) 标题与总体说明（全程耗时、距离约数）；2) 分步导航——每个节点一段，"
    "说明如何走到下一个节点、到达后要做什么（进门/刷卡/乘电梯按几楼等）；"
    "3) 楼层与电梯提示；4) 注意事项；5) 一句话总结。"
    "方向描述规则：只允许使用「直行」「稍向左转」「稍向右转」「左转」「右转」「掉头」这些词，"
    "绝对不要输出任何角度数值或东南西北方位词。"
    "数据来自真实轨迹，室内 GPS 不准，位移以耗时估算（步行约 1.2 m/s）为准并注明约数；"
    "高度变化每 3 米约一层；标为电梯段的节点之间无行走方向，按乘坐电梯描述。"
    "措辞自然，避免机械罗列数据。"
)


def haversine(lat1, lon1, lat2, lon2):
    r = 6371000.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp = math.radians(lat2 - lat1)
    dl = math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(math.sqrt(a))


def circ_mean(angles):
    """角度的圆周平均，返回 0~360。"""
    if not angles:
        return None
    sx = sum(math.sin(math.radians(a)) for a in angles)
    sy = sum(math.cos(math.radians(a)) for a in angles)
    return (math.degrees(math.atan2(sx, sy)) + 360) % 360


def turn_word(delta):
    """转向角（正=左）→ 用户友好的方向词。"""
    d = ((delta + 180) % 360) - 180
    a = abs(d)
    if a <= 25:
        return "直行"
    if a <= 70:
        return "稍向左转" if d > 0 else "稍向右转"
    if a <= 135:
        return "左转" if d > 0 else "右转"
    return "掉头（向左后方）" if d > 0 else "掉头（向右后方）"


def segment_data(order, pts):
    """按行走顺序返回每段统计（含段内平均朝向与噪声标记）。供路引与 RAG 共用。"""
    segs = []
    for a, b in zip(order, order[1:]):
        s = seg_stats(a, b, pts, 0)
        lo, hi = min(a["ms"], b["ms"]), max(a["ms"], b["ms"])
        inside = [p for p in pts if lo <= p["timeMs"] < hi]
        s["seg_hdg"] = circ_mean([p["headingDeg"] for p in inside if "headingDeg" in p])
        s["noisy"] = s["turns"] > 15  # 电梯段/朝向噪声段
        segs.append(s)
    return segs


def departure_words(order, segs):
    """每个节点（除终点外）的出发方向词。"""
    words = []
    for i in range(len(order) - 1):
        if segs[i]["noisy"]:
            words.append("（电梯/朝向不稳定段，按乘坐电梯描述，无需方向）")
            continue
        if i == 0:
            ref = order[0].get("hdg")
            delta = (segs[i]["seg_hdg"] - ref) if (segs[i]["seg_hdg"] is not None and ref is not None) else 0
        else:
            prev = segs[i - 1]
            if prev["noisy"] or prev["seg_hdg"] is None or segs[i]["seg_hdg"] is None:
                delta = 0
            else:
                delta = segs[i]["seg_hdg"] - prev["seg_hdg"]
        words.append(turn_word(delta))
    return words


def mmss(ms, t0):
    off = (ms - t0) // 1000
    return "{}:{:02d}".format(int(off // 60), int(off % 60))


def extract_nodes(track):
    """从标签提取节点；首尾补充轨迹起点/终点。"""
    t0 = track.get("startedAt", 0)
    pts = track.get("points", [])
    times = [p["timeMs"] for p in pts]

    def nearest(ms):
        i = bisect.bisect_left(times, ms)
        if i >= len(times):
            return pts[-1]
        if i > 0 and ms - times[i - 1] < times[i] - ms:
            return pts[i - 1]
        return pts[i]

    nodes = []
    for tg in track.get("tags", []):
        ms = tg.get("timeMs", t0)
        p = nearest(ms) if pts else {}
        name = tg.get("tagType", "节点")
        if tg.get("note"):
            name += "·" + tg["note"]
        nodes.append({
            "name": name,
            "t": mmss(ms, t0),
            "ms": ms,
            "lat": tg.get("latitude"),
            "lon": tg.get("longitude"),
            "hdg": tg.get("headingDeg"),
            "pressure": p.get("pressureHpa"),
        })
    # 补首尾
    if pts:
        if not nodes or nodes[0]["ms"] - t0 > 5000:
            p = pts[0]
            nodes.insert(0, {"name": "轨迹起点", "t": mmss(p["timeMs"], t0), "ms": p["timeMs"],
                             "lat": p.get("latitude"), "lon": p.get("longitude"),
                             "hdg": p.get("headingDeg"), "pressure": p.get("pressureHpa")})
        if nodes[-1]["ms"] < pts[-1]["timeMs"] - 5000:
            p = pts[-1]
            nodes.append({"name": "轨迹终点", "t": mmss(p["timeMs"], t0), "ms": p["timeMs"],
                          "lat": p.get("latitude"), "lon": p.get("longitude"),
                          "hdg": p.get("headingDeg"), "pressure": p.get("pressureHpa")})
    return nodes, pts, t0


def seg_stats(a, b, pts, t0):
    """两节点间的耗时/位移/高度变化/转向次数。"""
    dt = (b["ms"] - a["ms"]) / 1000.0
    dist = None
    if a["lat"] is not None and b["lat"] is not None:
        dist = round(haversine(a["lat"], a["lon"], b["lat"], b["lon"]), 1)
    h = None
    if a["pressure"] is not None and b["pressure"] is not None:
        # 正 = 沿行走方向上升（海拔越高气压越低），1 hPa ≈ 8.43 m
        h = round((a["pressure"] - b["pressure"]) * 8.43, 1)
    turns = 0
    lo, hi = min(a["ms"], b["ms"]), max(a["ms"], b["ms"])
    inside = [p for p in pts if lo <= p["timeMs"] <= hi]
    for p, q in zip(inside, inside[1:]):
        if "headingDeg" in p and "headingDeg" in q:
            d = abs(q["headingDeg"] - p["headingDeg"]) % 360
            if d > 180:
                d = 360 - d
            if d > 45:
                turns += 1
    return {"dt": round(dt, 1), "dist": dist, "h": h, "turns": turns}


def build_prompt(track, nodes, reverse):
    order = list(reversed(nodes)) if reverse else nodes
    pts = track.get("points", [])
    segs = segment_data(order, pts)
    words = departure_words(order, segs)

    lines = []
    lines.append("轨迹区域：{}，录制方向{}。请按下列节点顺序生成路引（顺序已按目标方向排好）。".format(
        track.get("area", ""), "的反向" if reverse else ""))
    lines.append("起点：{}；终点：{}。".format(order[0]["name"], order[-1]["name"]))
    lines.append("节点序列（「出发方向」指离开该节点、前往下一节点的方向）：")
    for i, n in enumerate(order):
        bits = ["{}. {}（{}）".format(i + 1, n["name"], n["t"])]
        if i < len(order) - 1:
            bits.append("→ 出发方向：{}".format(words[i]))
        else:
            bits.append("（终点）")
        if i > 0:
            s = segs[i - 1]
            extra = ["耗时{}秒".format(abs(s["dt"]))]
            if s["dist"] is not None:
                extra.append("直线位移约{}米".format(s["dist"]))
            if s["h"] is not None:
                if abs(s["h"]) < 1.5:
                    extra.append("高度基本持平")
                else:
                    direction = "上升" if s["h"] > 0 else "下降"
                    extra.append("高度{}约{}米".format(direction, abs(s["h"])))
            bits.append("；距上一节点：" + "，".join(extra))
        lines.append("  " + "".join(bits))
    return "\n".join(lines)


def call_ollama(prompt):
    body = json.dumps(
        {
            "model": MODEL,
            "messages": [
                {"role": "system", "content": SYSTEM_PROMPT},
                {"role": "user", "content": prompt},
            ],
            "stream": False,
            "options": {"temperature": 0.3, "num_ctx": 8192},
        }
    ).encode("utf-8")
    req = urllib.request.Request(OLLAMA_URL, data=body, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=300) as r:
        return json.loads(r.read().decode("utf-8"))["message"]["content"]


def main():
    args = sys.argv[1:]
    dry = "--dry-run" in args
    reverse = "--reverse" in args
    files = [a for a in args if not a.startswith("--")]

    if not files:
        cands = sorted(glob.glob(os.path.join(HARMONY_DIR, "**", "*.json"), recursive=True))
        if not cands:
            print("在 {} 下没有找到轨迹 JSON 文件。".format(HARMONY_DIR))
            sys.exit(1)
        files = [max(cands, key=os.path.getmtime)]

    for f in files:
        print("=" * 60)
        print("轨迹文件:", f)
        with open(f, encoding="utf-8") as fh:
            track = json.load(fh)
        nodes, pts, t0 = extract_nodes(track)
        if len(nodes) < 2:
            print("该轨迹标签节点不足 2 个，无法生成路引。建议在 App 里多打几个标签（门/电梯/门禁）。")
            continue
        prompt = build_prompt(track, nodes, reverse)
        if dry:
            print(prompt)
            continue
        try:
            print(call_ollama(prompt))
        except urllib.error.URLError as e:
            print("调用本地 Ollama 失败（{}）。请确认 Ollama 已启动。调试可加 --dry-run。".format(OLLAMA_URL))
            print("错误:", e)


if __name__ == "__main__":
    main()
