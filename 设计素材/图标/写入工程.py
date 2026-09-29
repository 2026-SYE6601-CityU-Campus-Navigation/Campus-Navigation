# -*- coding: utf-8 -*-
"""把选定的方案 C（浅底 + 深红图形）按 HarmonyOS 分层图标规范写进工程：
AppScope/resources/base/media/{foreground.png, background.png, layered_image.json} + 平面兜底 app_icon.png"""
import sys, os, json
sys.path.insert(0, '/tmp/icons')
import gen                      # 复用草稿脚本里的渐变色/定位针等原语（顺带重生成草稿，无妨）
from PIL import Image, ImageDraw

S, SS, u = gen.S, gen.SS, gen.u
RED, CREAM_2 = gen.RED, gen.CREAM_2
PROJ = '/sessions/nifty-exciting-tesla/mnt/RoomMarkerHarmony'

# ---------- 背景层：奶白径向渐变 + 淡淡的建筑剪影 ----------
bg = gen.wheel_gradient(S, (255, 253, 250), CREAM_2, center_frac=0.5)
faint = gen.new_layer()
ImageDraw.Draw(faint).rounded_rectangle((u(376), u(300), u(648), u(792)), radius=u(30), fill=(140, 29, 64, 52))
bg = gen.compose(bg, faint.resize((S, S), Image.LANCZOS))

# ---------- 前景层：深红定位针，针孔里 3 条金色楼层 ----------
fg = gen.new_layer()
gen.pin(ImageDraw.Draw(fg), 512, 400, 256, RED, 0.46, hole_fill=None, bars=3)
fg = fg.resize((S, S), Image.LANCZOS)

# ---------- 合成为平面图标（能力图标 / 兜底用）----------
flat = Image.alpha_composite(bg.copy(), fg).convert('RGB')

media_app = f'{PROJ}/AppScope/resources/base/media'
media_entry = f'{PROJ}/entry/src/main/resources/base/media'
fg.save(f'{media_app}/foreground.png')
bg.convert('RGB').save(f'{media_app}/background.png')
with open(f'{media_app}/layered_image.json', 'w', encoding='utf-8') as f:
    json.dump({'layered-image': {'background': '$media:background', 'foreground': '$media:foreground'}},
              f, indent=2, ensure_ascii=False)
    f.write('\n')
flat.resize((512, 512), Image.LANCZOS).save(f'{media_app}/app_icon.png')
flat.resize((512, 512), Image.LANCZOS).save(f'{media_entry}/app_icon.png')
for p in ['foreground.png', 'background.png', 'app_icon.png']:
    im = Image.open(f'{media_app}/{p}')
    print(f'AppScope/{p}: {im.size[0]}x{im.size[1]} mode={im.mode} {os.path.getsize(f"{media_app}/{p}")} bytes')
print('layered_image.json:', open(f'{media_app}/layered_image.json', encoding='utf-8').read().replace('\n', ' '))
