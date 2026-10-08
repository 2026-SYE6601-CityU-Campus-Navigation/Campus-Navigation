#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""阶段 1：从导出包重建室内路径（PDR，行人航位推算）。

**这个脚本是"离线那一半"** —— 它不碰 App，只读轨迹导出包（zip 或 track_*.json），
把阶段 0 采到的原始 IMU 序列变成一条**相对路径**，并画出图来。做它的理由：
离线一轮几秒钟、可以反复调；而每次验证 ArkTS 都要用户在 DevEco 跑一轮，代价差太多。
（阶段 2「因子图 + 绝对定位」在此之上接。）

管线：
  1. 解析采样点，还原出**绝对时间的 IMU 序列**
     ⚠️ accelSeries/gyroSeries 的 t 是**相对本秒窗口起点**的毫秒，而采样点的 timeMs 是
        **窗口结束**时刻 —— 所以样本的绝对时间 = 上一采样点的 timeMs + t（首点用 timeMs-1000 兜底）。
        搞错这一步会让整条序列平移约 1 秒。
  2. 重采样到均匀网格（默认 50Hz）
  3. 步态检测：减去 1 秒滑动均值去掉重力 → 平滑 → 自适应阈值找峰（最小步间隔 250ms）
  4. 步长：Weinberg L = K·(a_max - a_min)^(1/4)（K 可调；阶段 2 的因子图会再吸收尺度）
  5. 朝向：**陀螺向量投影到重力方向**积分（短时）＋ headingDeg 磁力（长时）互补滤波
  6. 航位推算 → 相对路径
  7. 有可用 GPS 锚点时做**相似变换对齐**（转+缩+平移，Umeyama）—— 绝对位置只能靠锚点
  8. 出图 + 打印统计

用法：
  python3 tools/pdr_reconstruct.py <导出包.zip 或 track_*.json> [--out 输出目录] [--K 0.45]
  例：python3 tools/pdr_reconstruct.py "独树阳光里_所选1条_20261004_2141.zip" --out /tmp/pdr

依赖：numpy、matplotlib（本机已装）
"""

import argparse
import json
import math
import os
import sys
import zipfile

import numpy as np
import matplotlib
matplotlib.use("Agg")           # 无显示环境
import matplotlib.pyplot as plt


def _setup_cjk_font():
    """图上要写中文，DejaVu 没有字形（会变成方框）。有 Noto CJK 就用它，没有就退回默认。"""
    from matplotlib import font_manager
    for p in ("/usr/share/fonts/opentype/noto/NotoSerifCJK-Regular.ttc",
              "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc"):
        if os.path.exists(p):
            try:
                font_manager.fontManager.addfont(p)
                plt.rcParams["font.family"] = font_manager.FontProperties(fname=p).get_name()
                plt.rcParams["axes.unicode_minus"] = False
                return
            except Exception:
                pass


_setup_cjk_font()

# ---------------- 可调参数 ----------------
ANCHOR_MAX_ACC = 50.0     # 可用 GPS 锚点的精度门限（与 App 的 Track3D.MAX_ACCURACY_M 一致）
GOOD_ACC = 8.0            # 「强」锚点（对齐时优先用）
GRID_HZ = 50.0            # 重采样网格
MIN_STEP_S = 0.25         # 最小步间隔（秒）；走路最快约 4 步/秒
DC_WIN_S = 1.0            # 去重力的滑动窗
SMOOTH_S = 0.15           # 带通后的平滑窗
PEAK_K = 0.5              # 峰值阈值 = PEAK_K × 标准差
COMP_TAU_S = 10.0         # 互补滤波：磁力修正的时间常数（秒）。越小越信磁力、越大越信陀螺。
                          # 室内磁干扰大，给 10 秒；短轨迹基本靠陀螺、长轨迹靠磁力防漂。
WEINBERG_K = 0.45         # Weinberg 系数（米 / (m/s²)^0.25）
STEP_LEN_MIN = 0.30
STEP_LEN_MAX = 1.20
CORNER_MERGE_S = 1.5      # 相隔小于这个秒数的两个拐点视为同一次误触
# ---- 自检判据（2026-10-05 城大 AC1 那条 10 分钟轨迹逼出来的，见各函数注释）----
WALK_WIN_S = 2.0          # 「在不在走动」用加速度的 2 秒窗标准差判断
WALK_SD = 0.6             # 标准差超过它算在走动（m/s²）
AGREE_WIN_S = 60.0        # 陀螺 vs 磁力 的一致性按 60 秒窗口比
AGREE_TOL_DEG = 45.0      # 单窗内两者净转角差多少度以内算「对得上」
ACCEL_MIN_HZ = 25.0       # 步态检测所需的加速度最低采样率（步频 1.5~2.5Hz → 每步至少 10 个点）


# ---------------- 读包 ----------------
def load_points(path):
    """接受 .zip（导出包）或 .json（单条轨迹）。返回 (points, meta)。"""
    if path.lower().endswith(".zip"):
        with zipfile.ZipFile(path) as z:
            names = [n for n in z.namelist() if os.path.basename(n).startswith("track_")
                     and n.endswith(".json") and "/" not in n]
            if not names:
                raise SystemExit("包里没找到 track_*.json")
            if len(names) > 1:
                print(f"⚠️ 包里有 {len(names)} 条轨迹，只处理第一条：{names[0]}")
            data = json.loads(z.read(names[0]).decode("utf-8"))
            pkg_name = os.path.basename(path)
    else:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        pkg_name = os.path.basename(path)
    return data, pkg_name


def parse_series(s):
    """'t:x:y:z;…' → (t_ms[N], xyz[N,3])"""
    if not s:
        return np.zeros(0), np.zeros((0, 3))
    t, v = [], []
    for seg in s.split(";"):
        if not seg:
            continue
        f = seg.split(":")
        if len(f) < 4:
            continue
        try:
            t.append(float(f[0]))
            v.append((float(f[1]), float(f[2]), float(f[3])))
        except ValueError:
            continue
    return np.array(t), np.array(v)


def build_imu(points):
    """把每秒窗口里的序列拼成绝对时间的 IMU 序列。

    关键细节：序列的 t 相对**窗口起点**，而采样点 timeMs 是**窗口结束**时刻。
    所以窗口起点 = 上一采样点的 timeMs（首点退回 timeMs-1000）。
    """
    ta, va, tg, vg = [], [], [], []
    for i, p in enumerate(points):
        start = points[i - 1]["timeMs"] if i > 0 else p["timeMs"] - 1000
        t, v = parse_series(p.get("accelSeries", ""))
        if len(t):
            ta.append(start + t)
            va.append(v)
        t, v = parse_series(p.get("gyroSeries", ""))
        if len(t):
            tg.append(start + t)
            vg.append(v)
    cat = lambda L, empty: np.concatenate(L) if L else np.zeros(empty)
    ta, va = cat(ta, 0), cat(va, (0, 3))
    tg, vg = cat(tg, 0), cat(vg, (0, 3))
    oa = np.argsort(ta); ta, va = ta[oa], va[oa]
    og = np.argsort(tg); tg, vg = tg[og], vg[og]
    return ta / 1000.0, va, tg / 1000.0, vg     # 秒


def grid_interp(t_src, v_src, t_grid):
    """把 (N,3) 序列按时间线性插值到网格上。"""
    out = np.zeros((len(t_grid), v_src.shape[1]))
    for k in range(v_src.shape[1]):
        out[:, k] = np.interp(t_grid, t_src, v_src[:, k])
    return out


def moving_average(x, win):
    if win < 2:
        return x
    k = np.ones(win) / win
    return np.convolve(x, k, mode="same")


# ---------------- 步态 ----------------
def detect_steps(mag, fs):
    """返回峰值的下标与时刻（秒）。mag 已是均匀网格上的加速度幅值。"""
    dc = moving_average(mag, int(DC_WIN_S * fs))
    band = moving_average(mag - dc, max(1, int(SMOOTH_S * fs)))
    sd = float(np.std(band))
    if sd <= 0:
        return np.zeros(0, dtype=int)
    hi = PEAK_K * sd
    min_gap = max(1, int(MIN_STEP_S * fs))
    peaks = []
    last = -min_gap
    for i in range(1, len(band) - 1):
        if band[i] > hi and band[i] >= band[i - 1] and band[i] > band[i + 1]:
            if i - last >= min_gap:
                peaks.append(i)
                last = i
    return np.array(peaks, dtype=int)


def step_lengths(mag, peaks, fs, K):
    """Weinberg：用每步区间内幅值的极差估步长。"""
    L = np.zeros(len(peaks))
    for j, p in enumerate(peaks):
        a = peaks[j - 1] if j > 0 else 0
        b = peaks[j + 1] if j + 1 < len(peaks) else len(mag) - 1
        lo, hi_ = (a + p) // 2, (p + b) // 2
        seg = mag[lo:max(hi_, lo + 1)]
        rng = float(np.max(seg) - np.min(seg)) if len(seg) else 0.0
        L[j] = K * (rng ** 0.25) if rng > 0 else 0.6
    return np.clip(L, STEP_LEN_MIN, STEP_LEN_MAX)


# ---------------- 朝向 ----------------
def wrap_pi(a):
    """把角度差归到 (-π, π]，避免绕圈的假跳变。"""
    return (a + math.pi) % (2 * math.pi) - math.pi


def net_turn(series):
    """整条角序列的净转角（按最短角差累加，抗 ±360 跳变）。"""
    return sum(wrap_pi(series[i + 1] - series[i]) for i in range(len(series) - 1))


def yaw_rate_series(t_grid, ta, va, tg, vg):
    """世界系下的偏航角速度（rad/s，罗盘方向**顺时针为正**）。

    ⚠️ 符号约定的完整说明见 heading_series 的注释（加速度计静止时指向上方 → 差一个负号）。
    把这段单独抽出来是因为**一致性自检也要用它**（先低通再比净转角）。
    """
    grav = grid_interp(ta, va, t_grid)
    n = np.linalg.norm(grav, axis=1, keepdims=True)
    n[n == 0] = 1
    grav = grav / n
    gyro = grid_interp(tg, vg, t_grid)
    return -np.einsum("ij,ij->i", gyro, grav)          # rad/s（罗盘方向，顺时针为正）


def walking_mask(mag, fs, win_s=WALK_WIN_S, thr=WALK_SD):
    """哪些时刻在走动（加速度的 2 秒窗标准差 > 阈值）。纯函数。

    **为什么需要它**：`总步数 / 总时长` 会被「停下来填表、拍照、打节点」严重稀释 ——
    2026-10-05 城大那条 10 分钟轨迹全程平均只有 1.03 步/秒（看着像步态检测失效），
    而只在走动时间里算是 1.56 步/秒（完全正常）。判据要用后者。
    """
    n = len(mag)
    out = np.zeros(n, dtype=bool)
    w = max(3, int(win_s * fs))
    half = w // 2
    for i in range(0, n, max(1, half)):
        a, b = max(0, i - half), min(n, i + half)
        if b - a < 3:
            continue
        if float(np.std(mag[a:b])) > thr:
            out[a:b] = True
    return out


def windowed_net_turn(yaw_rate, t_grid, h_t, h_v, win_s=AGREE_WIN_S):
    """逐窗比较「陀螺净转角」与「磁力净转角」。返回 [(窗口起点秒, 陀螺°, 磁力°, 差°), …]。

    **为什么不用「全程净转角」比**：长轨迹里来回转弯会互相抵消，全程净转角本身接近 0，
    差一点就是很大的相对差；而且净转角对整圈歧义敏感。城大那条 10 分钟轨迹就是活例 ——
    全程 陀螺 -104° vs 磁力 +34° 看着像 IMU 坏了，**逐窗看 8/10 窗对得上、中位只差 23°**
    （是判据不成立，不是数据不可用）。

    ⚠️ 用的是**原始** yaw（不低通）：PDR 积分的就是它，自检的量必须和它一致；
    而且实测过一版「先 10 秒低通再比」，结果把 49 秒那条从 38° 拉大到 51°、误判成不可信
    （低通本身引入了约 13° 的偏置），而它对 6Hz 那条的结论又毫无改变 —— 净效果是变差。
    """
    if len(h_t) < 2 or len(yaw_rate) < 2:
        return []
    dt = float(t_grid[1] - t_grid[0]) if len(t_grid) > 1 else 0.0
    t0, t_end = float(t_grid[0]), float(t_grid[-1])
    out = []
    k = 0
    while t0 + (k + 1) * win_s <= t_end:
        a, b = t0 + k * win_s, t0 + (k + 1) * win_s
        ia = max(0, int(np.searchsorted(t_grid, a)))
        ib = min(len(yaw_rate), int(np.searchsorted(t_grid, b)))
        sel = (h_t >= a) & (h_t < b)
        if ib - ia >= 2 and int(sel.sum()) >= 2:
            gdeg = math.degrees(float(yaw_rate[ia:ib].sum()) * dt)
            mdeg = math.degrees(net_turn(h_v[sel]))
            out.append((k * win_s, gdeg, mdeg, math.degrees(wrap_pi(math.radians(gdeg - mdeg)))))
        k += 1
    if not out and t_end - t0 >= 5.0:
        # 轨迹比一个窗口还短（如 49 秒那条）：整条当成一个窗口，别什么都不说
        ia = max(0, int(np.searchsorted(t_grid, t0)))
        ib = min(len(yaw_rate), len(t_grid))
        if ib - ia >= 2 and len(h_t) >= 2:
            gdeg = math.degrees(float(yaw_rate[ia:ib].sum()) * dt)
            mdeg = math.degrees(net_turn(h_v))
            out.append((0.0, gdeg, mdeg, math.degrees(wrap_pi(math.radians(gdeg - mdeg)))))
    return out


def window_ok(diff_deg):
    """单窗算不算「陀螺跟住了磁力」：只看**绝对**航向偏差是否在 `AGREE_TOL_DEG` 以内。

    ⚠️ 曾经写成「绝对 45° 与 20%×净转角 取大者」，被**负向验证证明测不出差别**：
    三个真实数据集（城大 10 分钟 / 49 秒 / 6Hz 那条）用纯绝对容差结论完全一样，
    那半条规则没有任何证据支持。而且方向可疑 —— 对航位推算来说，毁掉路径形状的是
    **绝对**航向误差：转 600° 差 40° 和转 20° 差 40°，对路径的影响一样大；
    用相对容差等于在大转角上偷偷放宽。
    """
    return abs(diff_deg) <= AGREE_TOL_DEG


def heading_series(points, t_grid, ta, va, tg, vg):
    """陀螺投影到重力方向积分（短时）＋ headingDeg（长时）互补滤波。

    为什么不直接用 gyro_z：机型握姿不同，yaw 轴未必是器件的 z 轴。
    把陀螺向量投影到**重力方向**（由低通后的加速度估计）上，才是绕世界铅垂线的角速度。

    ⚠️ 符号（2026-10-04 真机数据验证出来的）：加速度计静止时读数指向上方（与重力反向），
    所以 `gyro·(加速度单位向量)` 是**绕"上"轴逆时针为正**；而罗盘航向是北 0°、**顺时针**增大。
    两者差一个负号 —— 漏了这个负号，重建路径会整体镜像、且陀螺与磁力算出的净转角符号相反。
    实测判据：同一条 49s 轨迹，修正后陀螺净转角 +602° 与磁力 +640° 吻合到 6%。
    """
    yaw_rate = yaw_rate_series(t_grid, ta, va, tg, vg)
    dt = np.diff(t_grid, prepend=t_grid[0])
    theta = np.cumsum(yaw_rate * dt)                   # 纯陀螺积分（相对角）

    # 磁力绝对参考。**不做全局 unwrap**：室内磁干扰会让 unwrap 绕出假的整圈，
    # 下面按最短角差逐点修正即可。
    h_t = np.array([p["timeMs"] / 1000.0 for p in points if p.get("headingDeg") is not None])
    h_v = np.array([math.radians(p["headingDeg"]) for p in points if p.get("headingDeg") is not None])
    if len(h_t) < 2:
        return theta, theta                            # 没有磁力参考，只能用陀螺
    h_grid = np.interp(t_grid, h_t, h_v)

    out = np.zeros_like(theta)
    bias = wrap_pi(h_grid[0] - theta[0])               # 起始就与磁力对齐，免得开头转一圈
    for i in range(1, len(t_grid)):
        err = wrap_pi(h_grid[i] - (theta[i] + bias))
        bias += (dt[i] / (dt[i] + COMP_TAU_S)) * err
        out[i] = theta[i] + bias
    return out, theta


# ---------------- 坐标 ----------------
def enu(lat, lng, lat0, lng0):
    """经纬度 → 以 (lat0,lng0) 为原点的东北坐标（米）。"""
    m_lat, m_lng = 110540.0, 111320.0 * math.cos(math.radians(lat0))
    return (lng - lng0) * m_lng, (lat - lat0) * m_lat


def similarity_fit(src, dst):
    """2D 相似变换（缩放+旋转+平移，Umeyama）。src/dst 均为 (N,2)。"""
    mu_s, mu_d = src.mean(0), dst.mean(0)
    s0, d0 = src - mu_s, dst - mu_d
    cov = d0.T @ s0 / len(src)
    U, S, Vt = np.linalg.svd(cov)
    d = np.sign(np.linalg.det(U @ Vt))
    D = np.diag([1.0, d])
    R = U @ D @ Vt
    var_s = (s0 ** 2).sum() / len(src)
    scale = (S * np.array([1.0, d])).sum() / var_s if var_s > 0 else 1.0
    t = mu_d - scale * (R @ mu_s)
    return scale, R, t


# ---------------- 拐点分段（2026-10-05） ----------------
def merge_corners(corner_times, gap_s):
    """把误触合并：相隔小于 gap_s 的两个拐点算一个。返回 (合并后的列表, 合并掉的个数)。"""
    out = []
    for t in sorted(corner_times):
        if not out or t - out[-1] >= gap_s:
            out.append(t)
    return out, len(corner_times) - len(out)


def segment_by_corners(step_t, L, th, corners_s):
    """按拐点把步序列切成段，**段内朝向取圆均值** —— 也就是段内强制走直线。

    这是「一键打拐点」真正买到的东西：把自由积分的逐秒抖动按段抹平。
    返回 (sdx, sdy, legs)；legs = [(段号从1起, 步数, 段长 m, 朝向度)]。
    没有步的段会被跳过，所以 leg 数可能少于「拐点数 + 1」。没有拐点时返回空。
    """
    if not corners_s:
        return [], [], []
    legs_of = [sum(1 for c in corners_s if c <= step_t[i]) for i in range(len(step_t))]
    nleg = (max(legs_of) + 1) if legs_of else 0
    sdx, sdy, legs = [], [], []
    for k in range(nleg):
        idx = [i for i in range(len(step_t)) if legs_of[i] == k]
        if not idx:
            continue
        ang = math.atan2(sum(math.sin(th[i]) for i in idx), sum(math.cos(th[i]) for i in idx))
        dist = float(sum(L[i] for i in idx))
        for i in idx:
            sdx.append(float(L[i] * math.sin(ang)))
            sdy.append(float(L[i] * math.cos(ang)))
        legs.append((k + 1, len(idx), dist, math.degrees(ang) % 360.0))
    return sdx, sdy, legs


# ---------------- 主流程 ----------------
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("package", help="导出包 .zip 或 track_*.json")
    ap.add_argument("--out", default=".", help="图片输出目录")
    ap.add_argument("--K", type=float, default=WEINBERG_K, help="Weinberg 系数")
    args = ap.parse_args()

    data, pkg = load_points(args.package)
    points = data["points"]
    print(f"包：{pkg}")
    print(f"轨迹「{data.get('name')}」 区域={data.get('area')!r} 采样点 {len(points)} 个 "
          f"节点 {len(data.get('tags', []))} 个")

    ta, va, tg, vg = build_imu(points)
    if len(ta) < 10 or len(tg) < 10:
        raise SystemExit("这个包里没有可用的 IMU 序列（是阶段 0 之前采的数据？）")

    t0, t1 = min(ta[0], tg[0]), max(ta[-1], tg[-1])
    fs = GRID_HZ
    t_grid = np.arange(t0, t1, 1.0 / fs)
    mag = np.linalg.norm(grid_interp(ta, va, t_grid), axis=1)
    acc_hz = len(ta) / (ta[-1] - ta[0])
    gyr_hz = len(tg) / (tg[-1] - tg[0])
    print(f"IMU：加速度 {len(ta)} 样本({acc_hz:.1f}Hz) 陀螺 {len(tg)} 样本({gyr_hz:.1f}Hz)  "
          f"时长 {(t1-t0):.1f}s")
    if acc_hz < ACCEL_MIN_HZ:
        print(f"      ⚠️ 加速度只有 {acc_hz:.1f}Hz，低于步态所需（≥{ACCEL_MIN_HZ:.0f}Hz）："
              f"每个步态周期不足 3 个采样点，**波形会混叠**。")
        print(f"         步数或许还数得对，但步长（Weinberg 用幅值极差）不可用 ——"
              f"判死一条轨迹看这一条，比看步频准。")

    # 步态
    peaks = detect_steps(mag, fs)
    if len(peaks) < 2:
        raise SystemExit("没检出步态（步数 < 2）")
    step_t = t_grid[peaks]
    L = step_lengths(mag, peaks, fs, args.K)
    # 步频要按「走动时段」算：全程平均会被停下来填表/拍照/打节点严重稀释
    # （城大那条 10 分钟轨迹全程 1.03 步/秒像失效，走动时其实是 1.56 步/秒）
    wmask = walking_mask(mag, fs)
    walk_s = float(wmask.sum()) / fs
    freq_all = len(peaks) / (t1 - t0)
    n_walk = int(sum(1 for p in peaks if wmask[p]))
    freq_walk = (n_walk / walk_s) if walk_s > 1.0 else freq_all
    print(f"步态：检出 {len(peaks)} 步（{n_walk} 步落在走动时段）；"
          f"步长 中位 {np.median(L):.2f} m（{L.min():.2f}~{L.max():.2f}）；"
          f"推算总里程 {L.sum():.1f} m")
    print(f"      步频：全程 {freq_all:.2f} 步/秒，**走动时 {freq_walk:.2f} 步/秒**"
          f"（走动时长 {walk_s:.0f}s，占全程 {walk_s/(t1-t0)*100:.0f}%）")
    print(f"      ⚠️ 判据看「走动时」那项（正常步态 1.2~2.0 步/秒）；全程平均值会被停顿拉低。")

    # 朝向 + 航位推算
    theta, theta_gyro = heading_series(points, t_grid, ta, va, tg, vg)
    h_t = np.array([p["timeMs"] / 1000.0 for p in points if p.get("headingDeg") is not None])
    h_v = np.array([math.radians(p["headingDeg"]) for p in points if p.get("headingDeg") is not None])
    if len(h_v) > 1:
        wins = windowed_net_turn(yaw_rate_series(t_grid, ta, va, tg, vg), t_grid, h_t, h_v)
        print(f"朝向自检：全程净转角 陀螺 {math.degrees(net_turn(theta_gyro)):+.0f}° vs "
              f"磁力 {math.degrees(net_turn(h_v)):+.0f}°")
        print(f"      （⚠️ 长轨迹上「全程净转角」说明不了什么：来回转弯互相抵消、又对整圈歧义敏感"
              f"—— 判据看下面逐窗的）")
        if wins:
            okn = int(sum(1 for w in wins if window_ok(w[3])))
            med_deg = float(np.median([abs(w[3]) for w in wins]))
            print(f"      逐窗（{int(AGREE_WIN_S)}s × {len(wins)}）：{okn}/{len(wins)} 窗对得上"
                  f"（判据：该窗内两者净转角相差 ≤ {int(AGREE_TOL_DEG)}°）；中位偏差 {med_deg:.0f}°")
            if okn >= len(wins) * 0.8 and len(wins) >= 3:
                print("      → 陀螺跟住了磁力，这段 IMU 可用")
            elif okn >= len(wins) * 0.6:
                print("      → 多半窗口对得上、个别窗有偏差（室内磁干扰），形状可参考但别当精确")
            else:
                print("      → 多数窗口对不上，这段 IMU 不可信，形状别用")
            if len(wins) < 3:
                print(f"      （窗口只有 {len(wins)} 个，这条结论本身也不牢靠）")
    th = np.interp(step_t, t_grid, theta)
    dx = L * np.sin(th)
    dy = L * np.cos(th)
    px = np.concatenate([[0.0], np.cumsum(dx)])
    py = np.concatenate([[0.0], np.cumsum(dy)])

    # ---- 拐点分段（2026-10-05）：段内一定是直线，用整段的平均朝向代替逐秒朝向 ----
    # 这是「一键打拐点」这套东西真正买到的东西：把自由积分的抖动按段抹平。
    # 误触合并：相隔 < CORNER_MERGE_S 的拐点算一个（采集端不拦误触，拦在这里更省事）。
    ct = sorted(c["timeMs"] / 1000.0 for c in data.get("corners", []) if "timeMs" in c)
    merged, dropped = merge_corners(ct, CORNER_MERGE_S)
    seg = None
    if merged:
        sdx, sdy, legs = segment_by_corners(step_t, L, th, merged)
        print(f"拐点：{len(ct)} 个 → 合并误触后 {len(merged)} 个 → 切成 {len(legs)} 段"
              + (f"（合并掉 {dropped} 个）" if dropped else ""))
        for (k, n, dist, ang) in legs:
            print(f"    第{k}段：{n:3d} 步 {dist:5.1f} m  朝向 {ang:5.1f}°")
        if len(sdx) == len(dx):
            seg = (np.concatenate([[0.0], np.cumsum(sdx)]),
                   np.concatenate([[0.0], np.cumsum(sdy)]))
        else:
            print("    ⚠️ 分段点数与步数对不上，退回逐秒积分")
    else:
        print("拐点：这条轨迹没有拐点标记 → 退回逐秒积分（形状会抖得多）")

    # 有拐点就用分段路径，否则逐秒积分
    ux, uy = seg if seg is not None else (px, py)

    # 锚点
    anc = [(p["timeMs"] / 1000.0, p["latitude"], p["longitude"], p.get("accuracy"))
           for p in points
           if p.get("latitude") is not None and p.get("longitude") is not None
           and (p.get("accuracy") is None or p["accuracy"] <= ANCHOR_MAX_ACC)]
    used = None
    si = None
    dst = None
    if len(anc) >= 2:
        lat0, lng0 = anc[0][1], anc[0][2]
        ex, ey = zip(*[enu(a[1], a[2], lat0, lng0) for a in anc])
        dst = np.column_stack([ex, ey])
        # 取每个锚点时刻的 PDR 位置
        si = np.searchsorted(step_t, [a[0] for a in anc])
        si = np.clip(si, 0, len(px) - 1)
        src = np.column_stack([ux[si], uy[si]])
        s, R, t = similarity_fit(src, dst)
        P = (s * (R @ np.column_stack([ux, uy]).T).T) + t
        ux, uy = P[:, 0], P[:, 1]
        used = len(anc)
        print(f"锚点：{len(anc)} 个（强锚点 {sum(1 for a in anc if a[3] is not None and a[3] <= GOOD_ACC)} 个）"
              f" → 已对齐（缩放 {s:.2f}×、旋转 {math.degrees(math.atan2(R[1,0], R[0,0])):.0f}°）")
    else:
        print(f"锚点：只有 {len(anc)} 个可用 GPS 点 —— **没有锚点，路径只有相对形状**"
              f"（这正是采集协议要求「进楼前/出楼后室外静止 30 秒」的原因）")

    # ---- 出图 ----
    os.makedirs(args.out, exist_ok=True)
    fig, ax = plt.subplots(figsize=(7, 9))
    # 有拐点分段、且没做锚点对齐时，把「逐秒积分」画成淡色做对照（同一个相对坐标系才可比）
    if seg is not None and used is None:
        ax.plot(px, py, "-", color="#B0A0A6", lw=1.2, alpha=0.85, label="逐秒积分（未分段，对照）")
    ax.plot(ux, uy, "-", color="#8C1D40", lw=2.0,
            label="拐点分段直线约束" if seg is not None else "PDR 重建路径")
    ax.plot(ux[:-1], uy[:-1], ".", color="#8C1D40", ms=2, alpha=0.4)
    ax.plot(ux[0], uy[0], "^", color="#1F7A3D", ms=11, label="起点")
    if dst is not None:
        ax.plot(dst[:, 0], dst[:, 1], "x", color="#555555", ms=5, alpha=0.5, label="GPS 锚点")
        ax.plot(ux[si], uy[si], "o", color="#C8A02A", ms=7, label="重建路径上的锚点位置")
    ax.set_aspect("equal", adjustable="datalim")
    ax.grid(alpha=0.25)
    ax.set_xlabel("东 (m)")
    ax.set_ylabel("北 (m)")
    ax.set_title(f"PDR 重建：{data.get('name')}\n{len(peaks)} 步 / {t1-t0:.0f}s，"
                 f"里程 {L.sum():.0f} m" + ("（已按锚点对齐）" if used else "（无锚点，仅相对形状）"))
    ax.legend(loc="best", fontsize=9)
    out = os.path.join(args.out, "pdr_" + os.path.splitext(pkg)[0][:40] + ".png")
    fig.tight_layout()
    fig.savefig(out, dpi=130)
    print(f"\n图已保存：{out}")


if __name__ == "__main__":
    main()
