# -*- coding: utf-8 -*-
"""
轨迹描述生成器 —— 读取 Harmony 轨迹 JSON，统计运动特征，调用本地 Ollama 生成中文轨迹描述。

用法:
    python describe_trajectory.py                扫描 Harmony 文件夹，描述最新一条轨迹
    python describe_trajectory.py <轨迹文件.json>  描述指定文件
    python describe_trajectory.py --all           描述全部轨迹
    python describe_trajectory.py --dry-run       只打印统计与提示词，不调用模型（调试用）

依赖: 仅标准库；需要本机 Ollama 已运行且已有模型（默认 qwen3:8b）。
"""
import sys
import os
import json
import math
import glob
import urllib.request

OLLAMA_URL = "http://localhost:11434/api/chat"
MODEL = "qwen3:8b"
HARMONY_DIR = r"D:\CityUproject\TrajectoryData\Harmony"

SYSTEM_PROMPT = (
    "你是校园轨迹分析师。用户给你一段运动轨迹的统计数据与关键路径点（Harmony 手机 App 采集，"
    "1Hz 采样，含 GPS、气压、地磁、朝向、WiFi 等）。请用中文输出结构化描述，包含六部分："
    "1) 轨迹概览（时间、时长、区域、点数）；2) 运动方式与速度（步行/骑行/静止判断及依据）；"
    "3) 路径形状与关键转向（起点→经过→终点，直线/环线/折返）；4) 高度/楼层变化（据气压推算，"
    "注明约数）；5) 特殊事件（标签、GPS 中断、WiFi 环境变化等）；6) 一句话总结。"
    "数据含传感器噪声，措辞用“约/可能/大致”。总长 300 字左右，直接输出描述，不要复述原始数据。"
)


def haversine(lat1, lon1, lat2, lon2):
    r = 6371000.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp = math.radians(lat2 - lat1)
    dl = math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(math.sqrt(a))


def find_latest_track(root):
    files = [f for f in glob.glob(os.path.join(root, "**", "*.json"), recursive=True)]
    if not files:
        return None
    return max(files, key=os.path.getmtime)


def analyze(track):
    """从轨迹 JSON 提取统计特征，返回 dict。"""
    pts = track.get("points", [])
    n = len(pts)
    t0 = track.get("startedAt", pts[0]["timeMs"] if pts else 0)
    t1 = track.get("endedAt", pts[-1]["timeMs"] if pts else t0)
    duration_s = (t1 - t0) / 1000.0

    gps = [p for p in pts if "latitude" in p and "longitude" in p]
    dist = 0.0
    speeds = []
    for a, b in zip(gps, gps[1:]):
        d = haversine(a["latitude"], a["longitude"], b["latitude"], b["longitude"])
        dt = (b["timeMs"] - a["timeMs"]) / 1000.0
        if dt <= 0:
            continue
        v = d / dt
        if v < 10:  # 过滤 GPS 跳变毛刺（>10 m/s 视为定位错误）
            dist += d
            speeds.append(v)

    # 气压 → 相对高度（1 hPa ≈ 8.43 m，海平面附近）
    ps = [p["pressureHpa"] for p in pts if "pressureHpa" in p]
    p_start, p_end = (round(ps[0], 2), round(ps[-1], 2)) if ps else (None, None)
    h_rel = round((ps[0] - ps[-1]) * 8.43, 1) if len(ps) > 1 else None
    p_range = round((max(ps) - min(ps)) * 8.43, 1) if len(ps) > 1 else None

    # 朝向：平均航向与明显转向次数
    hdgs = [p["headingDeg"] for p in pts if "headingDeg" in p]
    if hdgs:
        sx = sum(math.sin(math.radians(h)) for h in hdgs)
        sy = sum(math.cos(math.radians(h)) for h in hdgs)
        mean_hdg = (math.degrees(math.atan2(sx, sy)) + 360) % 360
    else:
        mean_hdg = None
    turns = 0
    for a, b in zip(hdgs, hdgs[1:]):
        d = abs(b - a) % 360
        if d > 180:
            d = 360 - d
        if d > 45:
            turns += 1

    # WiFi 环境变化
    wf = [p.get("wifiTop", "") for p in pts if p.get("wifiTop")]
    wifi_changes = sum(1 for a, b in zip(wf, wf[1:]) if a != b)

    # 停顿：连续 10s 以上位移极小
    stops = 0
    run = 0
    for a, b in zip(gps, gps[1:]):
        if haversine(a["latitude"], a["longitude"], b["latitude"], b["longitude"]) < 1.0:
            run += 1
        else:
            if run >= 10:
                stops += 1
            run = 0
    if run >= 10:
        stops += 1

    # 关键路径点（均匀抽样 + 首尾，压缩到 ≤25 个；跳过 GPS 跳变点）
    step = max(1, n // 20)
    idx = list(range(0, n, step))
    if idx[-1] != n - 1:
        idx.append(n - 1)
    waypoints = []
    prev_latlon = None
    for i in idx:
        p = pts[i]
        t = p["timeMs"]
        mm = (t - t0) // 60000
        ss = ((t - t0) // 1000) % 60
        wp = {"t": "{}:{:02d}".format(int(mm), int(ss))}
        latlon = None
        if "latitude" in p:
            latlon = (p["latitude"], p["longitude"])
        if latlon and prev_latlon and i not in (0, n - 1):
            if haversine(prev_latlon[0], prev_latlon[1], latlon[0], latlon[1]) > 30:
                continue  # 跳变点，跳过
        if latlon:
            wp["latlon"] = "{:.5f},{:.5f}".format(latlon[0], latlon[1])
            prev_latlon = latlon
        wp["hdg"] = int(round(p.get("headingDeg", 0)))
        waypoints.append(wp)

    # 用户标签 → 可读文本
    tag_strs = []
    for tg in track.get("tags", []):
        off = (tg.get("timeMs", 0) - t0) // 1000
        mm, ss = int(off // 60), int(off % 60)
        note = tg.get("note", "")
        tag_strs.append("t={}:{:02d} {}{}".format(mm, ss, tg.get("tagType", ""),
                                                  "（{}）".format(note) if note else ""))

    return {
        "name": track.get("name", ""),
        "area": track.get("area", ""),
        "n": n,
        "duration_s": round(duration_s, 1),
        "gps_count": len(gps),
        "distance_m": round(dist, 1),
        "speed_avg": round(dist / max(duration_s, 1), 2),
        "speed_max": round(max(speeds), 2) if speeds else None,
        "stops": stops,
        "p_start": p_start, "p_end": p_end,
        "h_rel": h_rel, "p_range": p_range,
        "mean_hdg": int(round(mean_hdg)) if mean_hdg is not None else None,
        "turns": turns,
        "wifi_changes": wifi_changes,
        "tags": tag_strs,
        "waypoints": waypoints,
    }


def build_prompt(s):
    lines = []
    lines.append("轨迹文件：{name}（区域：{area}）".format(**s))
    lines.append("时长 {duration_s} 秒，共 {n} 个采样点（其中 GPS 有效 {gps_count} 点）。".format(**s))
    lines.append(
        "累计位移约 {distance_m} 米，平均速度约 {speed_avg} m/s，峰值 {speed_max} m/s；"
        "明显停顿 {stops} 次。".format(**s)
    )
    if s["h_rel"] is not None:
        lines.append(
            "气压 {p_start} → {p_end} hPa，相对高度变化约 {h_rel} 米，全程气压波动折合约 {p_range} 米。".format(**s)
        )
    lines.append("平均航向约 {mean_hdg}°，明显转向（>45°）{turns} 次；WiFi 环境切换 {wifi_changes} 次。".format(**s))
    if s["tags"]:
        lines.append("用户标签：{}".format("、".join(str(t) for t in s["tags"])))
    lines.append("关键路径点（时间 起点偏移、经纬度、朝向°）：")
    for wp in s["waypoints"]:
        bits = ["t={}".format(wp["t"])]
        if "latlon" in wp:
            bits.append(wp["latlon"])
        bits.append("hdg={}".format(wp["hdg"]))
        lines.append("  " + " ".join(bits))
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
    all_flag = "--all" in args
    files = [a for a in args if not a.startswith("--")]

    if not files:
        if all_flag:
            files = sorted(
                glob.glob(os.path.join(HARMONY_DIR, "**", "*.json"), recursive=True)
            )
        else:
            latest = find_latest_track(HARMONY_DIR)
            if not latest:
                print("在 {} 下没有找到轨迹 JSON 文件。".format(HARMONY_DIR))
                sys.exit(1)
            files = [latest]

    for f in files:
        print("=" * 60)
        print("轨迹文件:", f)
        with open(f, encoding="utf-8") as fh:
            track = json.load(fh)
        stats = analyze(track)
        prompt = build_prompt(stats)
        if dry:
            print(prompt)
            continue
        try:
            print(call_ollama(prompt))
        except urllib.error.URLError as e:
            print("调用本地 Ollama 失败（{}）。请确认 Ollama 已启动且已拉取模型 {}。".format(OLLAMA_URL, MODEL))
            print("调试可加 --dry-run 查看生成的提示词。")
            print("错误:", e)


if __name__ == "__main__":
    main()
