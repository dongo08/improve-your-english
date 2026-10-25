#!/usr/bin/env python3
"""把根目录的 3000 词 xlsx 解析成 assets/wordbook_source.json。

输出结构（供 Godot 侧的 tools/build_wordbook.gd 合并进词库）：

{
  "source": "xxx.xlsx",
  "generated_unix": 1234567890,
  "words": [
    {
      "english": "abandon",
      "aliases": ["abandons"],          # 括号里的另一种拼写，可为空
      "level": "ADVANCED",              # PRIMARY / INTERMEDIATE / ADVANCED
      "meanings": [{"type": "VT", "meaning": "舍弃"}]
    }
  ]
}

词性标记统一成 EnglishMeaning.Type 的枚举名，解析不了的一律 NONE。
"""

from __future__ import annotations

import json
import re
import sys
import time
from pathlib import Path

import openpyxl

ROOT = Path(__file__).resolve().parent.parent
OUT_PATH = ROOT / "assets" / "wordbook_source.json"

COL_ENGLISH = 1
COL_TYPE = 2
COL_MEANING = 6

LEVEL_BY_TYPE = {
    "初中": "PRIMARY",
    "*": "INTERMEDIATE",
    "**": "ADVANCED",
}
LEVEL_ORDER = {"PRIMARY": 0, "INTERMEDIATE": 1, "ADVANCED": 2}

POS_ALIASES = {
    "n": "N",
    "v": "V",
    "vt": "VT",
    "vi": "VI",
    "adj": "ADJ",
    "a": "ADJ",
    "adv": "ADV",
    "ad": "ADV",
    "prep": "PREP",
    "pron": "PRON",
    "conj": "CONJ",
    "num": "NUM",
    "art": "ART",
    "int": "INT",
    "interj": "INT",
    "abbr": "ABBR",
    "aux": "AUX",
}

# 少数词条里词性标记和单词粘在一起，先拆开
GLUED_FIXES = [
    ("modalv.", "v."),
    ("vn.", "v.n."),
    ("vad.", "v.ad."),
    ("vnum.", "v.num."),
]
# ≥3 个字母 + 词性标记，例如 "advertisementn."
GLUED_LONG_RE = re.compile(r"([A-Za-z]{3,})(n|v|vt|vi|adj|adv)\.")
MARKER_RE = re.compile(
    r"(?<![A-Za-z])(n|vt|vi|v|adj|adv|ad|a|prep|pron|conj|num|art|int|interj|abbr|aux)\s*\.",
    re.IGNORECASE,
)
SPLIT_CHARS = set(";；,，、/")
OPEN_BRACKETS = set("（(【[")
CLOSE_BRACKETS = set("）)】]")
PUA_RE = re.compile(r"[\ue000-\uf8ff]")
SPACE_RE = re.compile(r"\s+")
CJK_RE = re.compile(r"[\u4e00-\u9fff]")


def split_glosses(text: str) -> list[str]:
    """按分隔符切词义，但不切括号里的内容（"一（个、件……）" 要保持完整）。"""
    parts: list[str] = []
    buffer: list[str] = []
    depth = 0
    for char in text:
        if char in OPEN_BRACKETS:
            depth += 1
        elif char in CLOSE_BRACKETS:
            depth = max(0, depth - 1)
        if char in SPLIT_CHARS and depth == 0:
            parts.append("".join(buffer))
            buffer = []
            continue
        buffer.append(char)
    parts.append("".join(buffer))
    return [part.strip(" .;，,、·。") for part in parts if part.strip(" .;，,、·。")]



def normalize(text: str) -> str:
    text = str(text or "")
    text = text.replace("\u00a0", " ")
    text = PUA_RE.sub("", text)
    text = text.replace("．", ".").replace("；", ";").replace("，", ",").replace("＆", "&")
    text = SPACE_RE.sub(" ", text).strip()
    text = text.replace("modal v.", "v.")
    # "&vi 雕刻" 这种漏了点号的合并词性，统一补上
    text = re.sub(r"&\s*(vt|vi|v|n|adj|adv|ad|a|conj|prep|pron|num|art)\b\.?",
                  r"& \1.", text)
    for old, new in GLUED_FIXES:
        text = text.replace(old, new)
    text = GLUED_LONG_RE.sub(r"\1 \2.", text)
    # 释义里偶尔带脚注星号
    return text.strip("* ").strip()


def parse_meaning(text: str) -> list[dict]:
    """把 "vi.作弊；舞弊vt.欺骗 n.骗子" 拆成 [{type, meaning}, ...]。"""
    text = normalize(text)
    if not text:
        return []

    matches = list(MARKER_RE.finditer(text))
    if not matches:
        # 没有词性标记：整段当中文释义
        return [{"type": "NONE", "meaning": part} for part in split_glosses(text)]

    # 先按词性标记切成 (词性, 释义片段)，空片段稍后用下一段的释义补上（处理 "vi.vt.博斗"）
    segments: list[tuple[str, str]] = []
    for index, match in enumerate(matches):
        start = match.end()
        end = matches[index + 1].start() if index + 1 < len(matches) else len(text)
        segments.append((POS_ALIASES.get(match.group(1).lower(), "NONE"), text[start:end]))

    result: list[dict] = []
    seen: set[tuple[str, str]] = set()
    for index, (type_name, body) in enumerate(segments):
        glosses = [gloss for gloss in split_glosses(body) if _useful_gloss(gloss)]
        if not glosses:
            # "vi.vt.博斗" 这类空片段：借用后面第一段有内容的释义
            for _next_type, next_body in segments[index + 1:]:
                glosses = [gloss for gloss in split_glosses(next_body) if _useful_gloss(gloss)]
                if glosses:
                    break
        for gloss in glosses:
            if (type_name, gloss) in seen:
                continue
            seen.add((type_name, gloss))
            result.append({"type": type_name, "meaning": gloss})
    return result


def _useful_gloss(gloss: str) -> bool:
    """过滤掉只有 "&"、"." 这种碎片。"""
    return bool(CJK_RE.search(gloss)) or len(gloss) > 2


def split_aliases(english: str) -> tuple[str, list[str]]:
    """'criticise(criticize)' -> ('criticise', ['criticize'])"""
    english = SPACE_RE.sub(" ", english).strip()
    aliases: list[str] = []
    primary = english
    match = re.match(r"^(.*?)\s*[\(（]([^)）]+)[\)）]\s*$", english)
    if match:
        primary = match.group(1).strip()
        alias_text = match.group(2).strip()
        if alias_text and alias_text.lower() != primary.lower():
            aliases.append(alias_text)
    return primary, aliases


def cell_text(value) -> str:
    if value is None:
        return ""
    if isinstance(value, bool):
        # Excel 会把 false 自动存成布尔值
        return "true" if value else "false"
    return str(value)


def main() -> int:
    xlsx_path = Path(sys.argv[1]) if len(sys.argv) > 1 else next(ROOT.glob("*.xlsx"))
    workbook = openpyxl.load_workbook(xlsx_path, read_only=True, data_only=True)
    sheet = workbook.worksheets[0]

    words: dict[str, dict] = {}
    seen_rows = 0
    skipped_rows: list[str] = []
    merged_duplicates = 0

    for row in sheet.iter_rows(min_row=2, values_only=True):
        english_raw = cell_text(row[COL_ENGLISH] if len(row) > COL_ENGLISH else "")
        type_raw = cell_text(row[COL_TYPE] if len(row) > COL_TYPE else "").strip()
        meaning_raw = cell_text(row[COL_MEANING] if len(row) > COL_MEANING else "")
        if not english_raw.strip():
            continue
        seen_rows += 1

        english, aliases = split_aliases(english_raw)
        if not english:
            skipped_rows.append(f"空单词：{english_raw!r}")
            continue

        level = LEVEL_BY_TYPE.get(type_raw)
        if level is None:
            skipped_rows.append(f"{english}: 未知类型 {type_raw!r}，按高级处理")
            level = "ADVANCED"

        meanings = parse_meaning(meaning_raw)
        if not meanings:
            skipped_rows.append(f"{english}: 没有解析出释义")
            continue

        key = english.lower()
        entry = words.get(key)
        if entry is None:
            words[key] = {
                "english": english,
                "aliases": aliases,
                "level": level,
                "meanings": meanings,
            }
        else:
            merged_duplicates += 1
            # 同一个词的重复行：合并词义，取更基础的等级
            if LEVEL_ORDER[level] < LEVEL_ORDER[entry["level"]]:
                entry["level"] = level
            for alias in aliases:
                if alias not in entry["aliases"]:
                    entry["aliases"].append(alias)
            existing = {(m["type"], m["meaning"]) for m in entry["meanings"]}
            for meaning in meanings:
                if (meaning["type"], meaning["meaning"]) not in existing:
                    entry["meanings"].append(meaning)

    # 有的词条释义只有一个英文拼写（如 analyse 的释义写成 analyze），
    # 这种当不了中文选项，只有在没有别的释义时才保留。
    for entry in words.values():
        with_cjk = [m for m in entry["meanings"] if CJK_RE.search(m["meaning"])]
        if with_cjk:
            entry["meanings"] = with_cjk

    word_list = sorted(words.values(), key=lambda item: item["english"].lower())
    level_counts: dict[str, int] = {}
    meaning_count = 0
    for entry in word_list:
        level_counts[entry["level"]] = level_counts.get(entry["level"], 0) + 1
        meaning_count += len(entry["meanings"])

    payload = {
        "source": xlsx_path.name,
        "generated_unix": int(time.time()),
        "words": word_list,
    }
    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUT_PATH.write_text(json.dumps(payload, ensure_ascii=False, indent=1), encoding="utf-8")

    print(f"读取 {seen_rows} 行，去重后 {len(word_list)} 个词，{meaning_count} 条词义")
    print(f"等级分布: {level_counts}")
    print(f"合并重复行 {merged_duplicates} 条")
    if skipped_rows:
        print(f"跳过/警告 {len(skipped_rows)} 条:")
        for line in skipped_rows[:20]:
            print("  -", line)
    print(f"已写入 {OUT_PATH.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
