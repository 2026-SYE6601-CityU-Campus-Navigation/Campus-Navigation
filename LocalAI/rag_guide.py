# -*- coding: utf-8 -*-
"""
本地 RAG 问答 —— 轨迹知识库向量检索 + 本地大模型生成（检索增强生成）。

用法:
    python rag_guide.py --build                 扫描轨迹目录，建立向量索引（knowledge_store.json）
    python rag_guide.py "从大门怎么去410"         检索 + 生成答案（会先打印检索到的参考资料）
    python rag_guide.py --dry-run "问题"          只看检索结果，不调用生成模型（调试用）

依赖: 仅标准库；需要本地 Ollama 已运行，且已拉取：
      - qwen3-embedding:0.6b （向量模型，用于检索）
      - qwen3:8b            （生成模型，用于作答）
"""
import sys
import os
import json
import math
import glob
import urllib.request
from datetime import datetime

import generate_guidance as gg

OLLAMA = "http://localhost:11434"
EMBED_MODEL = "qwen3-embedding:0.6b"
CHAT_MODEL = "qwen3:8b"
TRACK_ROOT = os.environ.get("RAG_TRACK_ROOT", r"D:\CityUproject\TrajectoryData")
STORE = os.environ.get("RAG_STORE", r"D:\CityUproject\LocalAI\knowledge_store.json")
TOP_K = 5

SYSTEM_PROMPT = (
    "你是校园导航问答助手。请只依据「参考资料」回答问题。规则："
    "1) 参考资料中的节点块同时含正向（录制方向）与反向描述；若用户的行进方向与录制方向相反，"
    "使用反向描述中的方向词与高度变化。"
    "2) 若某条轨迹的节点链覆盖用户要求的完整路径，必须按起点→终点的顺序逐步描述经过的"
    "每一个节点（门、门禁、电梯、楼层变化、转向等），不得跳过中间节点。"
    "3) 方向只用「直行/稍向左转/稍向右转/左转/右转/掉头」，绝不输出角度数值。"
    "4) 参考资料没有的信息要明确说「资料中没有相关记录」，不要编造。"
    "5) 末尾注明依据的资料编号（如：依据 [1][3][4]）。"
)


def ollama_embed(text, model=EMBED_MODEL):
    """调用本地 Ollama 向量模型，返回浮点向量。"""
    body = json.dumps({"model": model, "prompt": text}).encode("utf-8")
    req = urllib.request.Request(OLLAMA + "/api/embeddings", data=body,
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=120) as r:
        return json.loads(r.read().decode("utf-8"))["embedding"]


def ollama_chat(system, user, model=CHAT_MODEL):
    body = json.dumps(
        {"model": model,
         "messages": [{"role": "system", "content": system},
                      {"role": "user", "content": user}],
         "stream": False,
         "options": {"temperature": 0.3, "num_ctx": 8192}}
    ).encode("utf-8")
    req = urllib.request.Request(OLLAMA + "/api/chat", data=body,
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=300) as r:
        return json.loads(r.read().decode("utf-8"))["message"]["content"]


def cosine(a, b):
    dot = sum(x * y for x, y in zip(a, b))
    na = math.sqrt(sum(x * x for x in a))
    nb = math.sqrt(sum(y * y for y in b))
    return dot / (na * nb) if na and nb else 0.0


def height_phrase(s):
    if s.get("h") is None or abs(s["h"]) < 1.5:
        return ""
    direction = "上升" if s["h"] > 0 else "下降"
    return "，高度{}约{}米".format(direction, abs(s["h"]))


def height_phrase_rev(s):
    """反向行走时的高度短语（方向取反）。"""
    if s.get("h") is None or abs(s["h"]) < 1.5:
        return ""
    direction = "下降" if s["h"] > 0 else "上升"
    return "，高度{}约{}米".format(direction, abs(s["h"]))


def chunkify_track(track, path):
    """把一条轨迹切成「概览块 + 每节点块」，返回文本块列表。"""
    nodes, pts, t0 = gg.extract_nodes(track)
    segs = gg.segment_data(nodes, pts)
    words = gg.departure_words(nodes, segs)
    area = track.get("area", "")
    tname = track.get("name", os.path.basename(path))
    date = datetime.fromtimestamp(track.get("startedAt", t0) / 1000.0).strftime("%Y-%m-%d %H:%M")

    chunks = []

    # 轨迹概览块
    dist = 0.0
    gps = [p for p in pts if "latitude" in p and "longitude" in p]
    for a, b in zip(gps, gps[1:]):
        d = gg.haversine(a["latitude"], a["longitude"], b["latitude"], b["longitude"])
        dt = (b["timeMs"] - a["timeMs"]) / 1000.0
        if dt > 0 and d / dt < 10:
            dist += d
    chain = " → ".join(n["name"] for n in nodes)
    overview = (
        "【轨迹概览】《{}》，区域：{}，录制于 {}，时长约 {} 秒，共 {} 个采样点，"
        "累计位移约 {} 米。途经节点（录制顺序）：{}。"
        "该轨迹可正向或反向用于路线问答，反向即从「{}」出发到「{}」。"
    ).format(tname, area, date, round((track.get("endedAt", t0) - t0) / 1000.0, 1),
             len(pts), round(dist, 1), chain, nodes[-1]["name"], nodes[0]["name"])
    chunks.append({"type": "overview", "source": path, "text": overview})

    # 反向方向词（镜像：左↔右互换，直行/电梯标记不变）
    mirror = {"稍向左转": "稍向右转", "稍向右转": "稍向左转", "左转": "右转", "右转": "左转",
              "掉头（向左后方）": "掉头（向右后方）", "掉头（向右后方）": "掉头（向左后方）",
              "直行": "直行"}
    rev_words = [mirror.get(w, w) for w in words]

    # 节点块（同时含正向与反向描述）
    for i, nd in enumerate(nodes):
        parts = ["【导航节点】{}（区域：{}，出自轨迹《{}》）。".format(nd["name"], area, tname)]
        # 正向（录制方向）
        if i == 0:
            parts.append("沿录制方向，本节点是起点；")
        else:
            s = segs[i - 1]
            parts.append("沿录制方向，从「{}」到本节点约 {} 秒{}；".format(
                nodes[i - 1]["name"], abs(s["dt"]), height_phrase(s)))
        if i < len(nodes) - 1:
            s = segs[i]
            parts.append("继续沿录制方向走到「{}」约 {} 秒{}，出发方向：{}。".format(
                nodes[i + 1]["name"], abs(s["dt"]), height_phrase(s), words[i]))
        else:
            parts.append("沿录制方向，本节点是终点。")
        # 反向
        if i > 0:
            s = segs[i - 1]
            parts.append("反向行走时，从「{}」到本节点约 {} 秒{}；".format(
                nodes[i - 1]["name"], abs(s["dt"]), height_phrase_rev(s)))
            if i < len(nodes) - 1:
                parts.append("从本节点反向前往「{}」的出发方向：{}。".format(
                    nodes[i - 1]["name"], rev_words[i - 1]))
        chunks.append({"type": "node", "source": path, "text": "".join(parts)})

    return chunks


def build():
    files = sorted(glob.glob(os.path.join(TRACK_ROOT, "**", "*.json"), recursive=True))
    if not files:
        print("在 {} 下没有找到轨迹 JSON 文件。".format(TRACK_ROOT))
        sys.exit(1)
    chunks = []
    for i, f in enumerate(files, 1):
        print("[{}/{}] 读取 {}".format(i, len(files), f))
        with open(f, encoding="utf-8") as fh:
            track = json.load(fh)
        chunks.extend(chunkify_track(track, f))
    print("共切出 {} 个文本块，开始向量化（模型 {}）...".format(len(chunks), EMBED_MODEL))
    for j, c in enumerate(chunks, 1):
        try:
            c["embedding"] = ollama_embed(c["text"])
        except urllib.error.URLError as e:
            print("向量化失败：{}".format(e))
            print("请先拉取向量模型：D:\\Ollama\\ollama.exe pull {}".format(EMBED_MODEL))
            sys.exit(1)
        if j % 5 == 0 or j == len(chunks):
            print("  向量化进度 {}/{}".format(j, len(chunks)))
    store = {
        "builtAt": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "embedModel": EMBED_MODEL,
        "sourceRoot": TRACK_ROOT,
        "chunks": chunks,
    }
    with open(STORE, "w", encoding="utf-8") as fh:
        json.dump(store, fh, ensure_ascii=False, indent=1)
    print("索引已保存：{}（{} 块）".format(STORE, len(chunks)))


def retrieve(query, store, k=TOP_K):
    qv = ollama_embed(query)
    scored = [(cosine(qv, c["embedding"]), c) for c in store["chunks"]]
    scored.sort(key=lambda x: x[0], reverse=True)
    return scored[:k]


def expand_by_track(hits, store, cap_tracks=3, cap_chunks=16):
    """命中块按轨迹补全：同一轨迹的所有块都纳入，保证节点链完整。"""
    best = {}
    for score, c in hits:
        best[c["source"]] = max(best.get(c["source"], 0.0), score)
    chosen = sorted(best, key=lambda s: -best[s])[:cap_tracks]
    picked = []
    for src in chosen:
        blocks = [c for c in store["chunks"] if c["source"] == src]
        blocks.sort(key=store["chunks"].index)  # 保持建库时的顺序（概览在前、节点按链序）
        picked.extend(blocks)
    return picked[:cap_chunks]


def main():
    args = sys.argv[1:]
    if "--build" in args:
        build()
        return
    dry = "--dry-run" in args
    question = " ".join(a for a in args if not a.startswith("--"))
    if not question:
        print("用法：python rag_guide.py --build  或  python rag_guide.py \"你的问题\"（可加 --dry-run）")
        return
    if not os.path.exists(STORE):
        print("还没有索引文件。请先运行：python rag_guide.py --build")
        return
    with open(STORE, encoding="utf-8") as fh:
        store = json.load(fh)

    print("问题：{}".format(question))
    print("=" * 60)
    try:
        hits = retrieve(question, store)
        picked = expand_by_track(hits, store)
    except urllib.error.URLError as e:
        print("检索失败（{}）。请确认 Ollama 已启动且已拉取 {}。".format(OLLAMA, EMBED_MODEL))
        print("错误:", e)
        return
    print("检索到的参考资料（按轨迹补全，共 {} 条）：".format(len(picked)))
    for rank, c in enumerate(picked, 1):
        src = os.path.basename(c["source"])
        print("  [{}]「{}」{}: {}".format(rank, src, c["type"], c["text"][:70]))
    print("=" * 60)
    if dry:
        print("（--dry-run 模式，跳过生成）")
        return
    refs = "\n".join("[{}] {}".format(rank, c["text"]) for rank, c in enumerate(picked, 1))
    user = "问题：{}\n\n参考资料（按相关度从高到低）：\n{}".format(question, refs)
    print("正在生成答案（模型 {}）...".format(CHAT_MODEL))
    print(ollama_chat(SYSTEM_PROMPT, user))


if __name__ == "__main__":
    main()
