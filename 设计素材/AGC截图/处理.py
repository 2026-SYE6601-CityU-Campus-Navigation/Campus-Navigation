# -*- coding: utf-8 -*-
"""把真机截图处理成 AGC 上架可用的竖向截图（9:16，1080×1920）。

为什么需要它：
  手机截屏是 9:19.9（测试机 Mate 80 = 1280×2832），而 AGC 要求竖向截图
  宽高比 9:16、最低 1080×1920。直接缩放会把人拉变形；本工程的做法是
    1) 先按比例去掉顶部状态栏、底部手势条（比例可调；设 0 即保留）；
    2) 按比例缩放到高 1920，左右用「截图边缘采样色」补到 1080，让两侧自然融合。
  **不裁上下内容** —— 本工程页面标题与右下角「开始记录」按钮贴近边缘，
  按 9:16 硬裁会把它们切掉（裁剪版已实测不可用）。

用法：
  1) 把真机截图原图丢进  设计素材/AGC截图/原图/     （jpg/jpeg/png/webp 都行）
  2) python3 处理.py                    # 用默认目录
     python3 处理.py 输入目录 输出目录    # 或指定目录
  3) 成品在  设计素材/AGC截图/输出/     （1080×1920 JPG，9:16，远小于 5MB）

依赖：Pillow（pip install pillow --break-system-packages）

注意：AGC 要求竖向截图 3~10 张；空状态页面（房间 0 / 轨迹 0）观感差，
     建议先用真机采点数据，再截「首页 / 区域详情 / 三维轨迹 / 节点标注 /
     轨迹详情 / 实时传感器 / 相册」这几页。
"""

import os
import sys
import glob
from PIL import Image

# ============ 配置（按需改这里） ============
IN_DIR  = os.path.join(os.path.dirname(os.path.abspath(__file__)), "原图")
OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "输出")

TW, TH = 1080, 1920      # AGC 竖向截图最小尺寸（9:16）
TRIM_TOP_FRAC = 0.039    # 去掉顶部状态栏（占原图高度比例）；设 0 保留
TRIM_BOT_FRAC = 0.025    # 去掉底部手势条；设 0 保留
JPEG_QUALITY  = 92       # 输出质量
EXTS = (".jpg", ".jpeg", ".png", ".webp")
# ===========================================


def edge_color(im):
    """取图像左边缘中部的颜色，作为左右补边色（截图背景多为纯色，能自然融合）。"""
    w, h = im.size
    strip = im.convert("RGB").crop((0, h // 2 - 60, min(4, w), h // 2 + 60))
    return strip.resize((1, 1)).getpixel((0, 0))


def to_916(im):
    """按比例去状态栏/手势条 -> 等比缩放 -> 居中放到 1080×1920，两侧补边色。"""
    w, h = im.size

    top = round(h * TRIM_TOP_FRAC)
    bot = round(h * TRIM_BOT_FRAC)
    if top or bot:
        im = im.crop((0, top, w, h - bot))
    w, h = im.size

    # contain 缩放：取较小的比例，保证整图都能放进画布
    scale = min(TW / w, TH / h)
    nw, nh = max(1, round(w * scale)), max(1, round(h * scale))
    im2 = im.convert("RGB").resize((nw, nh), Image.LANCZOS)

    canvas = Image.new("RGB", (TW, TH), edge_color(im2))
    canvas.paste(im2, ((TW - nw) // 2, (TH - nh) // 2))
    return canvas


def main():
    in_dir, out_dir = IN_DIR, OUT_DIR
    if len(sys.argv) >= 2:
        in_dir = sys.argv[1]
    if len(sys.argv) >= 3:
        out_dir = sys.argv[2]

    os.makedirs(in_dir, exist_ok=True)
    os.makedirs(out_dir, exist_ok=True)

    files = sorted(
        p for p in glob.glob(os.path.join(in_dir, "*"))
        if p.lower().endswith(EXTS)
    )
    if not files:
        print(f"没找到图片。把真机截图放进：{in_dir}")
        return

    for p in files:
        name = os.path.splitext(os.path.basename(p))[0]
        out = to_916(Image.open(p))
        dst = os.path.join(out_dir, f"{name}.jpg")
        out.save(dst, "JPEG", quality=JPEG_QUALITY)
        w, h = out.size
        print(f"{os.path.basename(p)} -> {name}.jpg  {w}x{h} 9:16  "
              f"{os.path.getsize(dst) // 1024}KB")

    print(f"\n共 {len(files)} 张，输出在：{out_dir}")


if __name__ == "__main__":
    main()
