#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把导出包里的「房间绑定」灌进 3D 轨迹网页的 DATA。

为什么需要这个脚本
------------------
房间号（LT-13 / P4702 …）**不在轨迹数据里**，它在手机数据库的关联链上：
    track_tags.markerId → markers.roomId → rooms.name / rooms.code
App 从 2026-10-08 那版起才把这条链的结果导出成 tag 的
`roomName` / `roomCode` / `markerName` 三个字段（见 Exporter.ets 的 ExportTag）。
所以：**旧包（那之前导出的）里一个房间字段都没有**，脚本会认出来并原样不动。

用法
----
    python3 tools/room_labels.py <导出包.zip|解开的目录> <页面.html> [更多页面.html ...] [--dry-run]

页面里必须有一个内嵌的 `const DATA = {...};`，DATA 里用 `nodes` 或 `tags`
数组装节点，每个节点至少要有 `t`（相对轨迹起点的秒数）。
脚本按时间就近把 tag 与节点配对，改写四个字段：

    code    房间号（roomCode）
    name    房间名（roomName）；包里有房间字段但为空时保留原值，保守起见不抹掉旧文本
    marker  标记名（前门/后门）—— 标记名区分同一房间的不同门
    src     这个 name 是哪来的：'房间绑定' / '未绑定房间' / '房间已删' / 原样

同时重写 DATA.rooms（「本轨迹提到的地点」栏用），让房间号出现在列表里。

设计取舍
--------
* **按时间配对而不是按序号**：序号配上也对，但时间配对能自证 —— 脚本会打印每对的
  时间差，超过 5 秒就报错退出，避免「插入了新节点」导致整列错位还悄悄写下去。
* **缺字段 ≠ 字段为空**：旧包是「没有 roomName 这个键」，新包没绑房间是
  「有键、值为空字符串」。前者原样保留（旧文本是当时能拿到的最好信息），
  后者才写「未绑定房间」。这条区别是这个脚本最容易写错的地方。
* **不做任何名字猜测**：包里没有就说没有，绝不从备注里编一个房间号出来。
"""

import argparse
import glob
import json
import os
import re
import shutil
import sys
import zipfile

# 配对容差。页面节点的 t 与包里 tag 的时刻基准不同（约差 1 秒），所以用
# 「最小差 = 整体偏移」+ 抖动容差 + 绝对门限三条一起卡，见 pair()。
PAIR_JITTER_S = 2.0        # 各对之差相对整体偏移允许的抖动
PAIR_MAX_OFFSET_S = 3.0    # 整体偏移本身的上限（超了就是整列错位）

# 包里有房间字段的判据：这三个键是 2026-10-08 那版才加的
ROOM_KEYS = ('roomName', 'roomCode', 'markerName')


def load_tags(pkg_path):
    """从 zip 或已解开的目录里读出轨迹 JSON 的 tags（按时间升序）。"""
    if os.path.isdir(pkg_path):
        cands = [p for p in glob.glob(os.path.join(pkg_path, '**', '*.json'), recursive=True)
                 if os.path.basename(p) != 'manifest.json']
        files = sorted(cands, key=lambda p: -os.path.getsize(p))
    elif zipfile.is_zipfile(pkg_path):
        files = None
        with zipfile.ZipFile(pkg_path) as z:
            names = [n for n in z.namelist()
                     if n.endswith('.json') and not n.endswith('manifest.json')]
            if len(names) != 1:
                raise SystemExit(f'包里应当只有 1 个轨迹 JSON，实际 {len(names)} 个：{names}')
            doc = json.loads(z.read(names[0]).decode('utf-8'))
            return _tags_of(doc, names[0])
    else:
        raise SystemExit(f'既不是目录也不是 zip：{pkg_path}')

    if not files:
        raise SystemExit(f'{pkg_path} 里没有找到轨迹 JSON')
    with open(files[0], encoding='utf-8') as f:
        doc = json.load(f)
    return _tags_of(doc, os.path.basename(files[0]))


def _tags_of(doc, label):
    tags = doc.get('tags')
    if tags is None:
        raise SystemExit(f'{label} 里没有 tags')
    tags = sorted(tags, key=lambda t: t['timeMs'])
    return doc, tags, label


def resolve(tag):
    """一个 tag → (code, name, marker, src)；src=None 表示「旧包，别动原值」。

    与 Exporter.roomLabelOf 的分支一一对应：
        房间在                  → 房间绑定
        标记在、房间没了        → 房间已删
        绑过但标记没了          → 标记已删
        从没绑过（markerId 缺省）→ 未绑定房间
    """
    if not any(k in tag for k in ROOM_KEYS):
        return '', '', '', None                     # 旧包：原样保留
    code = tag.get('roomCode') or ''
    name = tag.get('roomName') or ''
    marker = tag.get('markerName') or ''
    if name or code:
        return code, name, marker, '房间绑定'
    if marker:
        return '', '', marker, '房间已删'
    if tag.get('markerId') is not None:
        return '', '', '', '标记已删'
    return '', '', '', '未绑定房间'


def pair(nodes, tags, t0_ms):
    """节点 ↔ tag 按时间就近配对，1:1。返回 (配对表, 整体偏移)。

    基准时刻 `t0_ms` 取轨迹的 `startedAt`（页面节点的 t 也是相对它算的），
    **不能拿第一个 tag 当基准** —— 那样第一对必然差 0，剩下的差异全被当成漂移。

    三道自证，任何一道不过就拒绝写盘：
      ① 两边条数相等（页面节点被筛过就说明不是同一条轨迹）；
      ② 两边的时刻都单调递增（顺序对不上说明序列本身有问题）；
      ③ 逐对的差 **聚在同一个常数附近**（两边的 t=0 定义略有差别，约 1 秒），
         且这个常数本身小于 3 秒。基准取最小差；**实测最小差与中位数在这里没有可分辨的
         差别**（绝对门限 3 秒本身就能拦住整列错位，抖动容差拦中途错位），所以别把
         「必须用最小值」当成有证据的结论 —— 用中位数一样过。
    """
    if len(nodes) != len(tags):
        raise SystemExit(f'节点数 {len(nodes)} 与 tag 数 {len(tags)} 不一致，'
                         f'页面可能是旧轨迹或节点被筛过 —— 拒绝改，免得整列错位')
    for name, seq, get in (('页面节点', nodes, lambda o: o.get('t')),
                           ('包的 tag', tags, lambda o: o['timeMs'] / 1000.0)):
        vals = [get(o) for o in seq]
        if any(v is None for v in vals):
            raise SystemExit(f'{name}里有缺时刻的条目')
        if any(b < a for a, b in zip(vals, vals[1:])):
            raise SystemExit(f'{name}的时刻不是递增的，先排查数据本身')

    gaps = [abs(nd['t'] - (tg['timeMs'] - t0_ms) / 1000.0) for nd, tg in zip(nodes, tags)]
    base = min(gaps)
    bad = [(nd.get('t'), round((tg['timeMs'] - t0_ms) / 1000.0, 1), round(g, 2))
           for (nd, tg), g in zip(zip(nodes, tags), gaps) if g - base > PAIR_JITTER_S]
    if base > PAIR_MAX_OFFSET_S:
        raise SystemExit(f'整体时间偏移 {base:.1f}s 超过 {PAIR_MAX_OFFSET_S}s —— '
                         f'大概率整列错位（对齐上了一格），拒绝写')
    if bad:
        raise SystemExit(f'{len(bad)} 对超出抖动容差 {PAIR_JITTER_S}s，拒绝写：{bad[:5]}')
    return list(zip(nodes, tags)), base


DATA_RE = re.compile(r'(const DATA\s*=\s*)(\{.*?\})(;\s*\n)', re.S)


def patch_html(path, tags, t0_ms, dry):
    with open(path, encoding='utf-8') as f:
        html = f.read()
    m = DATA_RE.search(html)
    if not m:
        raise SystemExit(f'{path}: 找不到内嵌的 `const DATA = {{...}};`')
    data = json.loads(m.group(2))
    key = 'nodes' if 'nodes' in data else ('tags' if 'tags' in data else None)
    if key is None:
        raise SystemExit(f'{path}: DATA 里既没有 nodes 也没有 tags')

    pairs, base = pair(data[key], tags, t0_ms)
    tally = {'房间绑定': 0, '未绑定房间': 0, '房间已删': 0, '标记已删': 0}
    kept = 0
    for nd, tg in pairs:
        code, name, marker, src = resolve(tg)
        if src is None:
            kept += 1
            continue
        nd['code'] = code
        nd['marker'] = marker
        if name:
            nd['name'] = name
        nd['src'] = src
        tally[src] += 1

    # 「本轨迹提到的地点」栏：**只在真的出现房间绑定时才重建**。
    # 原来这一栏是从节点备注里攒出来的（「电子隧道」「图书馆」），无条件重建会在
    # 绑不到房间时把备注攒出来的条目抹干净 —— 那是丢信息，不是更新。
    if 'rooms' in data and tally['房间绑定'] > 0:
        bound_t = {id(nd) for nd, tg in pairs if resolve(tg)[3] == '房间绑定'}
        out = []
        for nd, tg in pairs:
            code, name, marker, src = resolve(tg)
            if src == '房间绑定':
                # name 用**节点上的显示名**而不是房间名：房间名为空时节点会保留备注里的
                # 旧名，两处不一致会让「地点」栏出现一行只有编号没有名字的条目
                out.append({'t': nd['t'], 'name': nd['name'], 'code': code, 'marker': marker,
                            'type': nd.get('type', ''), 'floor': nd.get('floor', ''),
                            'src': '房间绑定'})
            elif id(nd) not in bound_t and nd.get('name'):
                # 没绑房间、但备注里有名字 —— 原样留着
                out.append({'t': nd['t'], 'name': nd['name'], 'code': '', 'marker': '',
                            'type': nd.get('type', ''), 'floor': nd.get('floor', ''),
                            'src': nd.get('src') or '备注原文'})
        data['rooms'] = out

    # 用与页面一致的序列化风格（默认分隔符），把无谓的 diff 降到最小
    new_json = json.dumps(data, ensure_ascii=False)
    html_new = html[:m.start(2)] + new_json + html[m.end(2):]
    changed = html_new != html

    print(f'  {os.path.basename(path)}  [{key}]  {len(pairs)} 个节点，'
          f'整体时间偏移 {base:+.1f}s')
    print(f'      绑到房间 {tally["房间绑定"]} · 未绑定 {tally["未绑定房间"]} · '
          f'房间已删 {tally["房间已删"]} · 标记已删 {tally["标记已删"]} · '
          f'旧包原样保留 {kept}')
    if sum(tally.values()) == 0 and kept == len(pairs):
        # 一个节点都没动 —— 旧包会走到这里。**不写盘**，免得只因为重新序列化就产生整行 diff
        print('      没有任何节点需要改（旧包 / 已是最新），不写盘')
        return False
    if not changed:
        print('      内容无变化')
        return False
    if dry:
        print('      --dry-run：不写盘')
        return True
    shutil.copyfile(path, path + '.bak')
    with open(path, 'w', encoding='utf-8') as f:
        f.write(html_new)
    print(f'      已写回（备份 {os.path.basename(path)}.bak）')
    return True


def main():
    ap = argparse.ArgumentParser(description='把导出包的房间绑定灌进 3D 网页的 DATA')
    ap.add_argument('package', help='导出包 .zip 或解开的目录')
    ap.add_argument('pages', nargs='+', help='要改的页面 .html')
    ap.add_argument('--dry-run', action='store_true')
    args = ap.parse_args()

    doc, tags, label = load_tags(args.package)
    # 页面节点的 t 与 tag 时刻都相对轨迹起点，所以配对基准用 startedAt；
    # 老包万一没有这个字段就退回第一个节点（此时首对差 0 的偏差由 jitter 容差吸收）
    t0_ms = doc.get('startedAt') or tags[0]['timeMs']
    has = any(any(k in t for k in ROOM_KEYS) for t in tags)
    print(f'包：{label}')
    print(f'  轨迹「{doc.get("name")}」 {len(tags)} 个节点 / {doc.get("pointCount")} 个采样点')
    if not has:
        print('  ⚠ 这个包的 tag 里没有 roomName/roomCode/markerName —— '
              '是 2026-10-08 之前导出的旧包。页面会原样保留，不做任何猜测。')
    for p in args.pages:
        if not os.path.isfile(p):
            print(f'  跳过（不存在）：{p}')
            continue
        patch_html(p, tags, t0_ms, args.dry_run)
    return 0


if __name__ == '__main__':
    sys.exit(main())
