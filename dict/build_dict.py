#!/usr/bin/env python3
"""把 CC-CEDICT 清洗成鼠须管候选框用的短释义表：dict/cedict.tsv（简体词<TAB>英文）。

只用 Python 标准库。原始词典缓存在 dict/cache/，已经下载过就不再重复下载。
CC-CEDICT 采用 CC BY-SA 4.0 许可，来源 https://www.mdbg.net/chinese/dictionary?page=cc-cedict
"""
import gzip
import re
import sys
import urllib.request
from pathlib import Path

URL = "https://www.mdbg.net/chinese/export/cedict/cedict_1_0_ts_utf-8_mdbg.txt.gz"
HERE = Path(__file__).resolve().parent
CACHE = HERE / "cache" / "cedict.txt.gz"
OUT = HERE / "cedict.tsv"
MAX_LEN = 26          # 候选框里一条英文最多多长（字符）
MAX_SENSES = 2        # 最多显示几个意思

LINE = re.compile(r"^(\S+) (\S+) \[([^\]]*)\] /(.*)/$")
# 释义开头这些标签只是说明语体，去掉
TAGS = re.compile(r"^\((bound form|literary|coll\.|fig\.|loanword|Tw|old|dialect|slang|archaic|formal|polite|onom\.|math\.|chemistry|medicine|Buddhism)\)\s*", re.I)
# 这些开头的释义对学英语没用
USELESS = re.compile(r"^(variant of|old variant|unofficial variant|used in|see |surname |CL:|Taiwan pr\.|also pr\.|also written|abbr\. for|erhua variant|Japanese variant|archaic variant|(also )?(written|pronounced) as)", re.I)
CJK = re.compile(r"[㐀-鿿\[\]|]")


def clean(gloss):
    """一条英文释义 → 短形式；没用就返回 None。"""
    g = gloss.strip()
    while TAGS.match(g):
        g = TAGS.sub("", g)
    if USELESS.match(g):
        return None
    stripped = re.sub(r"\s*\([^()]*\)", "", g).strip()   # 去掉括号里的补充说明
    g = stripped if stripped else g.strip("()")          # 整条都在括号里时只拆掉括号
    if CJK.search(g):                                    # 还夹着汉字/拼音的，是给中文用户看的解释
        return None
    g = g.split(";")[0].strip()                          # "hello; hi" → "hello"
    g = g.split(", ")[0].strip()                         # "Beijing municipality, capital of…" → 逗号前那段
    if g.lower().startswith("to "):                      # "to work overtime" → "work overtime"
        g = g[3:]
    return g or None


def load():
    if not CACHE.exists():
        CACHE.parent.mkdir(parents=True, exist_ok=True)
        print("下载 CC-CEDICT …", file=sys.stderr)
        urllib.request.urlretrieve(URL, CACHE)
    with gzip.open(CACHE, "rt", encoding="utf-8") as f:
        for line in f:
            if line.startswith("#"):
                continue
            m = LINE.match(line.rstrip("\n"))
            if m:
                yield m.group(2), m.group(3), m.group(4).split("/")


def main():
    readings = {}   # 简体 → [(是否专有名词, -有用释义数, 出现顺序, [释义…])]
    for n, (simp, pinyin, glosses) in enumerate(load()):
        senses = []
        for g in glosses:
            c = clean(g)
            if c and c.lower() not in (s.lower() for s in senses):
                senses.append(c)
        if senses:
            proper = pinyin[:1].isupper()                # 拼音首字母大写 = 人名地名品牌
            readings.setdefault(simp, []).append((proper, -len(senses), n, senses))

    rows = 0
    with OUT.open("w", encoding="utf-8") as out:
        for simp, rs in readings.items():
            if any(not r[0] for r in rs):                # 有普通读音时，丢掉专有名词读音
                rs = [r for r in rs if not r[0]]
            rs.sort()                                    # 释义多的读音（通常更常用）排前面
            picked = []
            for i, r in enumerate(rs):                   # 每个读音取第一个意思
                if i > 0 and len(r[3]) < 2:              # 冷门读音（只有一个意思）不显示，比如"的"读 dī 时的"的士"
                    continue
                if r[3][0].lower() not in (p.lower() for p in picked):
                    picked.append(r[3][0])
            if len(picked) < MAX_SENSES:                 # 读音只有一个时，补它的第二个意思
                for s in rs[0][3][1:]:
                    if s.lower() not in (p.lower() for p in picked):
                        picked.append(s)
                        break
            text = picked[0]
            for s in picked[1:MAX_SENSES]:
                if len(text) + 2 + len(s) > MAX_LEN:
                    break
                text += "; " + s
            if len(text) > MAX_LEN:                     # 太长：在单词边界截断，不把单词切成两半
                cut = text[:MAX_LEN - 1]
                if " " in cut and text[MAX_LEN - 1] != " ":
                    cut = cut[:cut.rindex(" ")]
                text = cut.rstrip(" ;,") + "…"
            out.write(f"{simp}\t{text}\n")
            rows += 1
    print(f"写出 {rows} 条 → {OUT}", file=sys.stderr)


if __name__ == "__main__":
    main()
