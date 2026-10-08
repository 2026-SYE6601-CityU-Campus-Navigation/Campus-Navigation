#!/usr/bin/env python3
"""抓「ArkTS 保留字被当成标识符用」—— 又一类 **tsc 完全看不见、只有真机编译会报** 的错。

为什么需要它（2026-10-08 的真实翻车，第二次同类）：
    我在 `common/PlaceMatch.ets` 里写了 `const struct: string[] = [];`，
    真机报一串 10505001，**根因只有一个**：
        'struct' is not allowed as a variable declaration name.  (PlaceMatch.ets:243)
    后面 7 条（`'{' expected`、`Cannot find name 'push'`、`'string' only refers to a type`……）
    全是它引起的解析级联。

**为什么镜像 tsc 与离线单测全绿也没用**：`struct` 是 **ArkTS 独有的保留字**
（`@Component struct Foo {}` 就是拿它声明的），**TypeScript 不保留它**，
所以 tsc 把 `const struct` 当普通变量名收下，单测照跑不误 —— 和在两个地方都绿着的情况下，
真机上却编译不过。**「离线全绿」与「真机能编」之间隔着的就是这一类规则。**

同类前科：`.textDecoration(...)`（见 tools/check_new_attrs.py）—— 也是「没用过的 ArkUI 名字，
没去核就写」。那一次抓的是**属性名**，这一次抓的是**标识符名**，两者互补：
    · 属性名 → check_new_attrs.py（与 HEAD 对比，只查改动过的文件）
    · 标识符名 → 本脚本（**扫全部 .ets**，因为保留字写在哪年哪月都是错的）

判据（分两档，因为证据强度不同）：

  档 1（**确定会挂**，退出码 1）：`struct`
      判法：找出全部 `struct` 这个词。**合法的用法只有一种** —— `struct 名字 {`
      （组件声明，可以带泛型）。凡是不长这样的 `struct`（`const struct`、`f(struct: x)`）
      都是把保留字当了标识符。这样写既不误伤 `@Component struct FooDialog {`，
      也不需要知道它前面到底是 `const` 还是参数位。

  档 2（**可疑，默认只提示**，`--strict` 才计为失败）：其余 ArkTS 保留字里
      **TS 不拦的那些**：as asserts declare from get global infer is keyof module namespace
      of readonly require set type unique
      —— 这些词在 TS 里当变量名大多合法，所以 tsc 不报；在 ArkTS 里是保留字。
      **我把它们放在档 2 而不是档 1，是因为我没有在真机上逐个验过**。
      本项目的纪律是「没有证据的规则不硬留」（见记忆里那条「多写的规则没有证据支持就要删」），
      所以先只提示；等哪个真在 DevEco 上报了 10505001，就把它提到档 1 并在此处注明。

扫之前先剥注释与字符串字面量（**保留行号**）——这两个地方出现 `struct`/`type` 很正常
（本文件上面就有一堆），不剥会满屏误报。剥法沿用 check_new_attrs.py 踩出来的写法：
块注释/字符串换成**等量空行**，否则行号会偏小。

用法（在工程根目录，即 RoomMarkerHarmony/ 下）：
    python3 tools/check_reserved_names.py             # 档 1 失败即退出 1
    python3 tools/check_reserved_names.py --strict    # 档 2 也算失败
    python3 tools/check_reserved_names.py --verbose   # 列出扫了多少文件、列出了档 2 的全部位置
"""
import os
import re
import sys

ROOT = os.path.join('entry', 'src', 'main', 'ets')

# 档 1：已确认真机会挂（有本次报错记录）
TIER1 = ['struct']
# 档 2：TS 不拦、ArkTS 保留 —— 未逐个在真机验过，只提示
TIER2 = ['as', 'asserts', 'declare', 'from', 'get', 'global', 'infer', 'is', 'keyof',
         'module', 'namespace', 'of', 'readonly', 'require', 'set', 'type', 'unique']

# 合法用法：struct 名字 {（可带泛型），名字必须是标识符
LEGAL_STRUCT = re.compile(r'\bstruct\s+[A-Za-z_$][\w$]*\s*(<[^>{}]*>)?\s*\{')


def strip_code(text):
    """剥掉注释与字符串/模板字面量，**保留行数**（换成等量空行）。

    行号准确性靠这一点：把块注释整个换成空串会吞掉它内部的换行，
    报出来的行号会比真实位置小（check_new_attrs.py 实测偏了 10 行）。
    """
    def blank(m):
        return '\n' * m.group(0).count('\n')

    text = re.sub(r'/\*.*?\*/', blank, text, flags=re.S)          # 块注释
    text = re.sub(r'//[^\n]*', '', text)                          # 行注释
    text = re.sub(r'`(?:\\.|[^`\\])*`', blank, text, flags=re.S)  # 模板字面量
    text = re.sub(r"'(?:\\.|[^'\\\n])*'", blank, text)            # 单引号串
    text = re.sub(r'"(?:\\.|[^"\\\n])*"', blank, text)            # 双引号串
    return text


def line_of(text, pos):
    return text.count('\n', 0, pos) + 1


def ets_files():
    out = []
    for dirpath, _, filenames in os.walk(ROOT):
        for fn in filenames:
            if fn.endswith('.ets'):
                out.append(os.path.join(dirpath, fn).replace('\\', '/'))
    return sorted(out)


def scan_struct(text):
    """档 1：所有不是「struct 名字 {」的 struct 出现位置"""
    hits = []
    for m in re.finditer(r'\bstruct\b', text):
        # 看这个词往后是否构成合法声明
        tail = text[m.end():m.end() + 80]
        if LEGAL_STRUCT.match('struct' + tail):
            continue
        hits.append(line_of(text, m.start()))
    return hits


def scan_tier2(text):
    """档 2：保留字出现在**声明位**（const/let/var/function/class/... 或成员声明）上"""
    hits = {}
    for w in TIER2:
        # 声明位：const|let|var|function|class|interface|enum|type|namespace|abstract 后面
        pat = re.compile(r'\b(?:const|let|var|function|class|interface|enum|type|namespace'
                         r'|abstract|declare)\s+' + w + r'\b')
        for m in pat.finditer(text):
            hits.setdefault(w, []).append(line_of(text, m.start()))
    return hits


def main():
    strict = '--strict' in sys.argv
    verbose = '--verbose' in sys.argv
    files = ets_files()
    tier1_hits = {}
    tier2_hits = {}
    for f in files:
        text = strip_code(open(f, encoding='utf-8').read())
        h = scan_struct(text)
        if h:
            tier1_hits[f] = h
        t2 = scan_tier2(text)
        for w, lines in t2.items():
            tier2_hits.setdefault(w, []).extend(f'{os.path.basename(f)}:{ln}' for ln in lines)

    n1 = sum(len(v) for v in tier1_hits.values())
    n2 = sum(len(v) for v in tier2_hits.values())
    print(f'扫了 {len(files)} 个 .ets 文件') if verbose else None
    print(f'档1（确定会挂）{n1} 处 · 档2（可疑）{n2} 处')

    if n1:
        print('\n⚠️ ArkTS 保留字被当标识符用 —— 真机编译必挂（tsc 不报）：')
        for f, lines in sorted(tier1_hits.items()):
            print(f'  {f}: {", ".join("第 %d 行" % ln for ln in lines)}')
        print('  改法：换个名字。`struct` 在 ArkTS 里是声明组件的关键字，不能拿来当变量。')

    if n2:
        head = '⚠️' if strict else '（提示，未在真机验过，--strict 可升级为失败）'
        print(f'\n{head} 这些保留字出现在声明位上，核一下是不是非用不可：')
        for w in sorted(tier2_hits):
            print(f'  {w}  ← {", ".join(tier2_hits[w][:4])}')

    sys.exit(1 if (n1 or (strict and n2)) else 0)


if __name__ == '__main__':
    main()
