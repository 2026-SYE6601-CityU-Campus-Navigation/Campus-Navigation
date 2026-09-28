# -*- coding: utf-8 -*-
"""
导航图路引 —— 把轨迹记录变成「已探索路径图」，只沿已记录的边规划路引。

理念：每一条轨迹就像探照灯，照亮建筑内部的一小段结构。标签（门/电梯/门禁）是图的节点，
相邻标签之间的轨迹段是图的边。路引规划只能沿「已探索的边」行走——没有被轨迹覆盖的
区域视为未探索，绝不把两点凭空直线相连（就像高德导航只用实际道路一样）。

用法:
    python nav_graph.py                      默认：门·独树阳光里 2栋大门 → 门·410的门
    python nav_graph.py "大门" "410"         按名称（子串）指定起终点
    python nav_graph.py --graph              打印当前已探索的导航图（节点与边）
    python nav_graph.py --llm "大门" "410"   在模板路径基础上，让本地模型润色成自然语言

依赖: 仅标准库（--llm 需要本地 Ollama 已运行）。
"""
import sys
import os
import json
import math
import glob
import bisect
import urllib.request
from datetime import datetime

import generate_guidance as gg

TRACK_ROOT = os.environ.get("NAV_TRACK_ROOT", r"D:\CityUproject\TrajectoryData")
OLLAMA = "http://localhost:11434"
CHAT_MODEL = "qwen3:8b"

MIRROR = {"稍向左转": "稍向右转", "稍向右转": "稍向左转", "左转": "右转", "右转": "左转",
          "掉头（向左后方）": "掉头（向右后方）", "掉头（向右后方）": "掉头（向左后方）",
          "直行": "直行"}


# ---------------- 轨迹 → 导航图 ----------------

def node_sig(node):
    """节点合并签名：完全相同的名称才视为同一节点（不靠位置猜测）。"""
    return node["name"].replace(" ", "")


def build_graph():
    """扫描全部轨迹，构建导航图。同名节点或类型相同且相距<30m的节点合并。"""
    files = sorted(glob.glob(os.path.join(TRACK_ROOT, "**", "*.json"), recursive=True))
    if not files:
        print("在 {} 下没有找到轨迹 JSON 文件。".format(TRACK_ROOT))
        sys.exit(1)

    nodes = []   # {"name": ..., "lat": ..., "lon": ..., "tracks": [来源轨迹数]}
    edges = {}   # (a_id, b_id) -> {"fwd": {...}, "rev": {...}, "source": 轨迹名}
    g = {}       # 邻接表

    for f in files:
        with open(f, encoding="utf-8") as fh:
            track = json.load(fh)
        tname = track.get("name", os.path.basename(f))
        ns, pts, _t0 = gg.extract_nodes(track)
        if len(ns) < 2:
            continue
        segs = gg.segment_data(ns, pts)
        words = gg.departure_words(ns, segs)

        # 节点映射：轨迹节点 → 图节点 id（只有完全同名才合并，保证"已确认的同一地点"才连通）
        ids = []
        for nd in ns:
            full_sig = node_sig(nd)
            target = None
            for j, existing in enumerate(nodes):
                if existing["name"].replace(" ", "") == full_sig:
                    target = j
                    break
            if target is None:
                nodes.append({"name": nd["name"], "lat": nd.get("lat"), "lon": nd.get("lon"),
                              "tracks": [tname]})
                target = len(nodes) - 1
            else:
                if tname not in nodes[target]["tracks"]:
                    nodes[target]["tracks"].append(tname)
                # 备注更具体的名字优先保留
                if len(nd["name"]) > len(nodes[target]["name"]):
                    nodes[target]["name"] = nd["name"]
            ids.append(target)

        # 边（只沿轨迹相邻节点建边——这是"只采用已探索路径"的核心）
        for i in range(len(ns) - 1):
            a, b = ids[i], ids[i + 1]
            if a == b:
                continue
            key = (a, b) if a < b else (b, a)
            if key in edges:
                continue  # 已探索过该边，保留首次记录
            s = segs[i]
            fwd = {"dt": abs(s["dt"]), "dist": s.get("dist"), "h": s.get("h"),
                   "word": words[i], "noisy": s["noisy"]}
            rev = {"dt": abs(s["dt"]), "dist": s.get("dist"),
                   "h": None if s.get("h") is None else -s["h"],
                   "word": MIRROR.get(words[i], words[i]), "noisy": s["noisy"]}
            edges[key] = {"fwd": fwd, "rev": rev, "source": tname}
            g.setdefault(a, []).append(b)
            g.setdefault(b, []).append(a)

    return nodes, edges, g


def match_node(nodes, query):
    """按名称子串匹配节点；多个候选时报歧义。"""
    q = query.replace(" ", "")
    cands = [i for i, n in enumerate(nodes) if q in n["name"].replace(" ", "")]
    if not cands:
        return None
    if len(cands) == 1:
        return cands[0]
    # 完全相等优先
    exact = [i for i in cands if nodes[i]["name"].replace(" ", "") == q]
    if len(exact) == 1:
        return exact[0]
    print("「{}」匹配到多个节点，请写具体一点：".format(query))
    for i in cands:
        print("  - {}".format(nodes[i]["name"]))
    sys.exit(1)


def find_path(g, start, end):
    """BFS 最短路径（按边数最少），只沿已探索的边。"""
    if start == end:
        return [start]
    parent = {start: None}
    queue = [start]
    while queue:
        cur = queue.pop(0)
        for nb in g.get(cur, []):
            if nb not in parent:
                parent[nb] = cur
                if nb == end:
                    path = [end]
                    while parent[path[-1]] is not None:
                        path.append(parent[path[-1]])
                    return list(reversed(path))
                queue.append(nb)
    return None  # 不连通 = 两点之间没有已探索的路径


def get_edge(edges, a, b):
    key = (a, b) if a < b else (b, a)
    e = edges[key]
    if a < b:
        return e["fwd"], e["rev"]  # fwd = a→b, rev = b→a
    return e["rev"], e["fwd"]     # 反了


def render_path(nodes, edges, path, start, end):
    lines = []
    lines.append("【导航路引】{} → {}".format(nodes[start]["name"], nodes[end]["name"]))
    total_s = 0
    steps = []
    for a, b in zip(path, path[1:]):
        seg, _ = get_edge(edges, a, b)
        total_s += seg["dt"]
        steps.append((a, b, seg))
    lines.append("已沿已探索路径规划：{}（共 {} 段，全程约 {} 秒 ≈ {} 分钟）。".format(
        " → ".join(nodes[i]["name"] for i in path), len(steps), int(total_s),
        round(total_s / 60, 1)))
    lines.append("")
    for k, (a, b, s) in enumerate(steps, 1):
        na, nb = nodes[a]["name"], nodes[b]["name"]
        lines.append("第 {} 段 · {} → {}".format(k, na, nb))
        if s["noisy"]:
            h = ""
            if s["h"] is not None and abs(s["h"]) >= 1.5:
                direction = "上升" if s["h"] > 0 else "下降"
                h = "（{}约{}米）".format(direction, abs(s["h"]))
            lines.append("  此段为电梯/通道（约 {} 秒{}），按乘坐电梯描述。".format(s["dt"], h))
        else:
            h = ""
            if s["h"] is not None and abs(s["h"]) >= 1.5:
                direction = "上升" if s["h"] > 0 else "下降"
                h = "，{}约{}米".format(direction, abs(s["h"]))
            lines.append("  出发方向：{}；步行约 {} 秒{}，到达「{}」。".format(
                s["word"], s["dt"], h, nb))
        lines.append("")
    lines.append("注意事项：本路引仅依据已探索路径生成（未经轨迹记录的岔路不在其中）；")
    lines.append("依据轨迹：《" + "》《".join(
        sorted({edges[(a, b) if a < b else (b, a)]["source"] for a, b in zip(path, path[1:])})) + "》。")
    return "\n".join(lines)


def print_graph(nodes, edges, g):
    print("已探索导航图：{} 个节点，{} 条边".format(len(nodes), len(edges)))
    # 连通分量
    seen = set()
    comps = []
    for i in range(len(nodes)):
        if i in seen:
            continue
        comp, queue = [], [i]
        seen.add(i)
        while queue:
            cur = queue.pop(0)
            comp.append(cur)
            for nb in g.get(cur, []):
                if nb not in seen:
                    seen.add(nb)
                    queue.append(nb)
        comps.append(comp)
    print("连通分量：{} 个".format(len(comps)))
    for ci, comp in enumerate(comps, 1):
        print("\n[分量 {}]".format(ci))
        for i in comp:
            print("  节点「{}」  {}".format(nodes[i]["name"], "、".join(nodes[i]["tracks"])))
        for a in comp:
            for b in g.get(a, []):
                if b > a:
                    s, _ = get_edge(edges, a, b)
                    print("  边「{}」—「{}」：约 {} 秒".format(nodes[a]["name"], nodes[b]["name"], s["dt"]))


# ---------------- 可选：LLM 润色 ----------------

LLM_SYSTEM = (
    "你是一位经验丰富的校园导航助手，为新生口述步行路引。请把用户提供的结构化路径规划结果，"
    "改写成高质量的自然语言路引。写作规范："
    "1) 开头用一句话总览（含全程约几分钟）；"
    "2) 分步骤，每一步一段，用自然句子衔接（如「进门后直行大约半分钟，右手边就是门禁」），"
    "不要机械罗列「第1段」这类标签；"
    "3) 方向只许用「直行/稍向左转/稍向右转/左转/右转/掉头」，把数据里的数字融入句子，"
    "不要单独列出「耗时30.7秒」这种条目；"
    "4) 电梯单独成句，说明楼层与升降（如「在一楼乘电梯上四楼，约一分钟」）；"
    "5) 结尾用一句注意事项收尾（如刷卡、按已探索路径生成）；"
    "6) 语气亲切简洁，像给朋友指路，不添加参考资料里没有的路段与细节；"
    "7) 全程中文，总长 150~250 字。"
)


def llm_polish(plan_text):
    body = json.dumps(
        {"model": CHAT_MODEL,
         "messages": [{"role": "system", "content": LLM_SYSTEM},
                      {"role": "user", "content": "路径规划结果如下，请改写：\n" + plan_text}],
         "stream": False, "options": {"temperature": 0.3, "num_ctx": 8192}}
    ).encode("utf-8")
    req = urllib.request.Request(OLLAMA + "/api/chat", data=body,
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=300) as r:
        return json.loads(r.read().decode("utf-8"))["message"]["content"]


def main():
    args = sys.argv[1:]
    nodes, edges, g = build_graph()

    if "--graph" in args:
        print_graph(nodes, edges, g)
        return

    use_llm = "--llm" in args
    queries = [a for a in args if not a.startswith("--")]
    q_start = queries[0] if len(queries) > 0 else "2栋大门"
    q_end = queries[1] if len(queries) > 1 else "410"

    start = match_node(nodes, q_start)
    end = match_node(nodes, q_end)
    if start is None:
        print("找不到起点「{}」。可用 --graph 查看已探索的节点。".format(q_start))
        sys.exit(1)
    if end is None:
        print("找不到终点「{}」。可用 --graph 查看已探索的节点。".format(q_end))
        sys.exit(1)

    path = find_path(g, start, end)
    if path is None:
        print("「{}」和「{}」之间还没有已探索的连通路径。".format(nodes[start]["name"], nodes[end]["name"]))
        print("（这正是『只采用已记录路径』的体现——多录几条轨迹，把中间区域照亮后即可连通。）")
        sys.exit(1)

    plan = render_path(nodes, edges, path, start, end)
    print(plan)
    if use_llm:
        print("=" * 60)
        print("【模型润色版】")
        try:
            print(llm_polish(plan))
        except urllib.error.URLError as e:
            print("调用本地 Ollama 失败（{}）。".format(OLLAMA))
            print("错误:", e)


if __name__ == "__main__":
    main()
