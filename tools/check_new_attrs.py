#!/usr/bin/env python3
"""找出「本轮新出现的画布/组件属性名」—— 专抓 ArkUI 属性名拼错这类只有真机编译能发现的问题。

为什么需要它（2026-10-08 的真实翻车）：
    我在这句上写了 `.textDecoration({ type: TextDecorationType.Underline })`（CSS 的习惯写法），
    而 **ArkUI 里没有这个属性**，真机编译报 10505001，提示 "Did you mean 'decoration'?"。
    这类错误的共同特征：**UI 文件（带 @Component / build()）tsc 解析不了**，所以
    「镜像 tsc 0 错」根本管不到；而每次真机编译都要人在 DevEco 里跑一轮，代价很高。

判据（简单但有效）：**与上一次真机验证过的版本（git HEAD）相比，第一次出现的属性名就是可疑的**。
    已经出现在 HEAD 里的属性名，说明那段代码在真机上编译过 —— 这就是我们唯一的权威基线。
    新增一个从没用过的属性名时，先去看官方文档确认它存在、参数形状也对，再编译。

怎么区分「属性」与「方法调用」：属性在 ArkUI 里永远是**链式**写法（跟在 `组件(...)` 或前一个属性后面），
    所以只认「前面是 `)` 或 `]`（可以隔换行）的 `.名字(`」；`this.foo()` / `rec.bar()` /
    `atManager.baz()` 这类方法调用前面是标识符，天然被排除。
    —— 一开始我用的是「行首 .名字(」，结果**负向验证没失败**：往链中间插一行能测出来，
    但把属性写在行内（`.padding(18).textDecoration(...)`）就漏了。**负向验证不失败 = 判据没守住东西。**

用法（在工程根目录，即 RoomMarkerHarmony/ 下）：
    python3 tools/check_new_attrs.py            # 对比工作区与 HEAD
    python3 tools/check_new_attrs.py <基准提交>  # 换一个基准（默认 HEAD）
    python3 tools/check_new_attrs.py --list     # 顺便列出基线里的全部属性名
"""
import os
import re
import subprocess
import sys

ROOT = os.path.join('entry', 'src', 'main', 'ets')
# 链式属性：前面是 ) 或 ]，中间可以有空白/换行，然后是 .名字(
CHAINED = re.compile(r'[)\]]\s*\.\s*([a-zA-Z_]\w*)\s*\(')


def strip_comments(text):
    """
    去掉注释，但**保留行数**：块注释换成等量的空行。

    ⚠️ 这个细节踩过一次：原来把块注释整个换成空串，于是它内部那些换行没了，
    报出来的行号比真实位置小（实测偏了 10 行）。而块注释在本工程里到处都是
    （每个方法前面都有一段 `/** ... */`），行号也就全错。
    """
    text = re.sub(r'/\*.*?\*/', lambda m: '\n' * m.group(0).count('\n'), text, flags=re.S)
    return re.sub(r'//[^\n]*', '', text)


def attrs_of(text):
    """这一份源码里用到的属性名"""
    return set(m.group(1) for m in CHAINED.finditer(strip_comments(text)))


def attr_lines(text, name):
    """某个属性名出现的行号，给人工核查用。

    用 m.end()（匹配末尾，也就是 `.名字(` 那一行）而不是 m.start()（前一个 `)` 所在的行）：
    链式写法里前一个 `)` 往往在**上一行**，用 start 会稳定少报一行（实测 105 → 报 104）。
    """
    t = strip_comments(text)
    out = []
    for m in re.finditer(r'[)\]]\s*\.\s*' + name + r'\s*\(', t):
        out.append(t.count('\n', 0, m.end()) + 1)
    return out


def ets_files():
    out = []
    for dirpath, _, filenames in os.walk(ROOT):
        for fn in filenames:
            if fn.endswith('.ets'):
                out.append(os.path.join(dirpath, fn).replace('\\', '/'))
    return out


def baseline_attrs(rev):
    """基准版本里所有属性名的并集"""
    out = set()
    for path in ets_files():
        blob = subprocess.run(['git', 'show', f'{rev}:{path}'],
                              capture_output=True, text=True).stdout
        if blob:
            out |= attrs_of(blob)
    return out


def changed_files():
    diff = subprocess.run(['git', 'diff', '--name-only'], capture_output=True, text=True).stdout.split()
    others = subprocess.run(['git', 'ls-files', '--others', '--exclude-standard'],
                            capture_output=True, text=True).stdout.split()
    return [f for f in diff + others if f.endswith('.ets')]


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    rev = args[0] if args else 'HEAD'
    base = baseline_attrs(rev)
    files = changed_files()
    fresh = set()
    for f in files:
        fresh |= attrs_of(open(f, encoding='utf-8').read())
    fresh -= base

    if '--list' in sys.argv:
        print(f'基线（{rev}）里的属性名 {len(base)} 个：')
        for a in sorted(base):
            print(f'  .{a}()')

    print(f'基线（{rev}）属性名 {len(base)} 个 · 检查 {len(files)} 个改动过的 .ets')
    if not fresh:
        print('没有新出现的属性名 —— 用到的属性全都在真机编译过的代码里出现过。')
        return 0
    print(f'\n⚠️ 新出现 {len(fresh)} 个属性名，编译前先核一下文档（真机只认它自己的那套名字）：')
    for a in sorted(fresh):
        where = []
        for f in files:
            for i in attr_lines(open(f, encoding='utf-8').read(), a):
                where.append(f'{os.path.basename(f)}:{i}')
        print(f'  .{a}()  ← {", ".join(where[:4])}')
    return 1


if __name__ == '__main__':
    sys.exit(main())
