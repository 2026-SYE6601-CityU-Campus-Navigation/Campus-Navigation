# 图标设计源（可重新生成，改主色只需改这里）
# 生成三版草稿：python3 生成图标.py     # 输出到 outputs/icon-drafts
# 采纳方案 C 写进工程：python3 写入工程.py  # 写 AppScope 分层图标 + 平面兜底
# 依赖 Pillow：pip install pillow --break-system-packages

# -*- coding: utf-8 -*-
"""生成 RoomMarker 的 App 图标草稿（HarmonyOS 分层图标：前景/背景 1024×1024）。
三个方向：A 深红底 + 白色定位针（针内是楼层）；B 深红底 + 白色建筑塔楼 + 金针；C 浅底 + 深红图形。"""
from PIL import Image, ImageDraw, ImageFont
import os

S = 1024          # 图标画布（官方标准 1024×1024）
SS = 3            # 超采样倍数，先画 3 倍再缩，边缘才干净
RED       = (140, 29, 64)
RED_LIGHT = (170, 48, 84)
RED_DARK  = (110, 22, 51)
CREAM     = (251, 247, 242)
CREAM_2   = (243, 234, 226)
GOLD      = (226, 168, 58)
WHITE     = (255, 255, 255)

OUT = '/sessions/nifty-exciting-tesla/mnt/outputs/icon-drafts'
os.makedirs(OUT, exist_ok=True)

def vertical_gradient(size, top, bottom):
    img = Image.new('RGB', (1, size), top)
    d = ImageDraw.Draw(img)
    for y in range(size):
        t = y / (size - 1)
        d.point((0, y), fill=tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
    return img.resize((size, size), Image.BILINEAR)

def wheel_gradient(size, inner, outer, center_frac=0.35):
    """中心略亮的径向渐变，让纯色底看起来有体积"""
    img = Image.new('RGB', (size, size), outer)
    d = ImageDraw.Draw(img)
    cx = cy = size / 2
    maxr = size * 0.72
    for i in range(int(maxr), 0, -1):
        t = i / maxr
        if t < center_frac:
            f = (center_frac - t) / center_frac
            col = tuple(int(inner[k] + (outer[k] - inner[k]) * (1 - f)) for k in range(3))
            d.ellipse((cx - i, cy - i, cx + i, cy + i), fill=col)
    return img

def new_layer():
    return Image.new('RGBA', (S * SS, S * SS), (0, 0, 0, 0))

def u(v):                      # 按超采样放大坐标
    return v * SS

def pin(d, cx, cy, r, fill, hole_r, hole_fill=None, bars=None, bar_h=0.10, bar_w=1.28, bar_gap=0.32):
    """定位针：圆 + 尖尾；hole 透明(或指定色)；针孔里可叠楼层横条"""
    cx, cy, r = u(cx), u(cy), u(r)
    hr = r * hole_r
    # 尾部三角（顶点在上圆心处，避免看到接缝）
    d.polygon([(cx - r * 0.66, cy + r * 0.72), (cx + r * 0.66, cy + r * 0.72), (cx, cy + r * 1.95)], fill=fill)
    d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=fill)
    if hole_fill is not None:
        d.ellipse((cx - hr, cy - hr, cx + hr, cy + hr), fill=hole_fill)
    else:
        # 透明针孔：用「减去」的方式挖空
        mask = Image.new('L', (S * SS, S * SS), 255)
        ImageDraw.Draw(mask).ellipse((cx - hr, cy - hr, cx + hr, cy + hr), fill=0)
        d._image.putalpha(Image.composite(d._image.getchannel('A'), Image.new('L', d._image.size, 0), mask))
    if bars:
        bw = hr * bar_w
        bh = hr * bar_h
        gap = hr * bar_gap
        n = bars
        total = n * bh + (n - 1) * gap
        y0 = cy - total / 2
        for i in range(n):
            top = y0 + i * (bh + gap)
            d.rounded_rectangle((cx - bw / 2, top, cx + bw / 2, top + bh), radius=bh / 2, fill=bars if isinstance(bars, str) else (0, 0, 0, 0) if False else GOLD)
    return d

def rounded_mask(size, radius_frac=0.28, ss=4):
    m = Image.new('L', (size * ss, size * ss), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, size * ss - 1, size * ss - 1), radius=int(size * ss * radius_frac), fill=255)
    return m.resize((size, size), Image.LANCZOS)

def compose(bg, fg, alpha=255):
    out = bg.convert('RGBA').copy()
    if alpha < 255:
        f = fg.copy()
        f.putalpha(f.getchannel('A').point(lambda v: int(v * alpha / 255)))
        fg = f
    out.alpha_composite(fg)
    return out

# ---------- A：深红底 + 白色定位针（针孔里是楼层横条） ----------
def variant_a():
    bg = wheel_gradient(S, RED_LIGHT, RED_DARK)
    fg = new_layer()
    d = ImageDraw.Draw(fg)
    pin(d, 512, 400, 256, WHITE, 0.46, hole_fill=None, bars=3)
    back = new_layer()   # 针孔里的金色楼层要画在针面之上，不能在挖空之后
    db = ImageDraw.Draw(back)
    hr = u(256) * 0.46
    bw, bh, gap = hr * 1.24, hr * 0.13, hr * 0.30
    total = 3 * bh + 2 * gap
    y0 = u(400) - total / 2
    for i in range(3):
        top = y0 + i * (bh + gap)
        db.rounded_rectangle((u(512) - bw / 2, top, u(512) + bw / 2, top + bh), radius=bh / 2, fill=GOLD)
    fg = Image.alpha_composite(fg, back)
    return compose(bg, fg.resize((S, S), Image.LANCZOS))

# ---------- B：深红底 + 白色建筑塔楼 + 金针 ----------
def variant_b():
    bg = vertical_gradient(S, RED_LIGHT, RED_DARK)
    fg = new_layer()
    d = ImageDraw.Draw(fg)
    x0, y0, x1, y1 = u(352), u(236), u(672), u(796)
    d.rounded_rectangle((x0, y0, x1, y1), radius=u(34), fill=WHITE)
    # 窗：透明窗洞让红底透出来
    mask = Image.new('L', (S * SS, S * SS), 255)
    md = ImageDraw.Draw(mask)
    cols, rows = 2, 4
    win_w, win_h = u(74), u(58)
    gap_x, gap_y = u(56), u(56)
    total_w = cols * win_w + (cols - 1) * gap_x
    total_h = rows * win_h + (rows - 1) * gap_y
    sx = u(512) - total_w / 2
    sy = u(272) + (u(560) - total_h) / 2
    for c in range(cols):
        for r in range(rows):
            wx, wy = sx + c * (win_w + gap_x), sy + r * (win_h + gap_y)
            md.rounded_rectangle((wx, wy, wx + win_w, wy + win_h), radius=u(14), fill=0)
    fg.putalpha(Image.composite(fg.getchannel('A'), Image.new('L', fg.size, 0), mask))
    # 金色定位针（右上角）
    pin(ImageDraw.Draw(fg), 726, 300, 118, GOLD, 0.44, hole_fill=None, bars=None)
    hole = new_layer()
    dh = ImageDraw.Draw(hole)
    hr = u(118) * 0.44
    dh.ellipse((u(726) - hr, u(300) - hr, u(726) + hr, u(300) + hr), fill=(0, 0, 0, 0))
    return compose(bg, fg.resize((S, S), Image.LANCZOS))

# ---------- C：浅奶白底 + 深红图形 ----------
def variant_c():
    bg = wheel_gradient(S, (255, 253, 250), CREAM_2, center_frac=0.5)
    # 背后一层淡淡的建筑剪影
    faint = new_layer()
    ImageDraw.Draw(faint).rounded_rectangle((u(376), u(300), u(648), u(792)), radius=u(30), fill=(140, 29, 64, 52))
    fg = new_layer()
    d = ImageDraw.Draw(fg)
    pin(d, 512, 400, 256, RED, 0.46, hole_fill=None, bars=3)
    bars = new_layer()
    db = ImageDraw.Draw(bars)
    hr = u(256) * 0.46
    bw, bh, gap = hr * 1.24, hr * 0.13, hr * 0.30
    total = 3 * bh + 2 * gap
    y0 = u(400) - total / 2
    for i in range(3):
        top = y0 + i * (bh + gap)
        db.rounded_rectangle((u(512) - bw / 2, top, u(512) + bw / 2, top + bh), radius=bh / 2, fill=GOLD)
    fg = Image.alpha_composite(fg, bars)
    return compose(compose(bg, faint.resize((S, S), Image.LANCZOS), 255), fg.resize((S, S), Image.LANCZOS))

def pick_cjk_font(size, bold=True):
    for p in ['/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc',
              '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
              '/usr/share/fonts/opentype/noto/NotoSerifCJK-Bold.ttc']:
        if os.path.exists(p):
            try:
                return ImageFont.truetype(p, size)
            except Exception:
                pass
    return ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf', size)

variants = [('A', '深红底 · 定位针里是楼层', variant_a),
            ('B', '深红底 · 建筑塔楼 + 金针', variant_b),
            ('C', '浅底 · 深红图形', variant_c)]
icons = {}
for key, desc, fn in variants:
    img = fn()
    icons[key] = img
    img.save(f'{OUT}/icon{key}_1024.png')
    img.convert('RGB').resize((256, 256), Image.LANCZOS).save(f'{OUT}/icon{key}_256.png')

# ---------- 预览图：桌面实际观感（圆角蒙层）+ 小尺寸 ----------
cell, pad, lab = 300, 36, 74
sheet_w = pad + 3 * (cell + pad) - pad + pad
sheet_h = pad + lab + 40 + cell + 40 + 150 + 34 + lab + pad
sheet = Image.new('RGB', (sheet_w, sheet_h), (247, 244, 240))
sd = ImageDraw.Draw(sheet)
f_title = pick_cjk_font(32)
f_desc = pick_cjk_font(23)
for i, (key, desc, _) in enumerate(variants):
    x = pad + i * (cell + pad)
    y = pad
    sd.text((x + cell / 2, y + lab / 2), f'方案 {key}', font=f_title, fill=(40, 30, 34), anchor='mm')
    sd.text((x + cell / 2, y + lab - 4), desc, font=f_desc, fill=(126, 110, 116), anchor='mt')
    y2 = y + lab + 40
    sd.rounded_rectangle((x - 8, y2 - 8, x + cell + 8, y2 + cell + 8), radius=20, fill=(255, 255, 255))
    sheet.paste(icons[key].convert('RGB').resize((cell, cell), Image.LANCZOS), (x, y2))
    y3 = y2 + cell + 40
    for size, dx in ((150, 0), (64, 178)):
        tile = icons[key].convert('RGBA').resize((size, size), Image.LANCZOS)
        tile.putalpha(rounded_mask(size, 0.30))
        sheet.paste(tile, (x + dx, y3 + (150 - size)), tile)
    sd.text((x, y3 + 150 + 26), '桌面观感 150 / 64 px', font=f_desc, fill=(140, 125, 130))
sheet.save(f'{OUT}/preview.png')
print('已生成：')
for f in sorted(os.listdir(OUT)):
    print(' ', f, os.path.getsize(f'{OUT}/{f}'), 'bytes')
