#!/usr/bin/env python3
"""Lay two texts out as level, hard-wrapped columns for a code fence.

Why this exists: "side by side" means parallel columns where corresponding
lines sit level and you read across (~/.claude/CLAUDE.md, "Side-by-side means
columns"). Done by hand, Claude drifts: a long line wraps on one side and every
line after it is one row out, or words get trimmed so a line fits. This script
does the alignment and wrapping mechanically, so both sides stay verbatim and
level.

How: lines are matched with difflib, so an unchanged line sits level with its
twin even when lines were added or removed above it. Each line is wrapped to
the column width, and the shorter side of a pair is padded with blank rows so
the next pair starts level. The 3-column gutter marks each row:

    " | "  same on both sides
    " * "  changed
    " < "  only on the left
    " > "  only on the right

Nothing is dropped. A wrap breaks at the last space that fits, or mid-word if
there is none; tabs become spaces; wide characters (CJK, most emoji) count as
two columns.

Usage: side-by-side.py LEFT RIGHT [--width 99] [--left-label A] [--right-label B]
"""
import argparse
import difflib
import sys
import unicodedata


def cwidth(ch):
    if unicodedata.combining(ch):
        return 0
    return 2 if unicodedata.east_asian_width(ch) in ("W", "F") else 1


def swidth(s):
    return sum(cwidth(c) for c in s)


def wrap(line, width):
    """Split one line into pieces no wider than width, losing no characters
    other than the single space a break is taken at."""
    line = line.expandtabs(4)
    if line == "":
        return [""]
    out = []
    while swidth(line) > width:
        used, cut = 0, 0
        for i, ch in enumerate(line):
            w = cwidth(ch)
            if used + w > width:
                break
            used += w
            cut = i + 1
        space = line.rfind(" ", 0, cut + 1)
        if space > 0:
            out.append(line[:space])
            line = line[space + 1:]
        else:
            out.append(line[:cut])
            line = line[cut:]
    out.append(line)
    return out


def pad(s, width):
    return s + " " * (width - swidth(s))


def rows(left, right, width, mark):
    lw, rw = [], []
    for l in left:
        lw.extend(wrap(l, width))
    for r in right:
        rw.extend(wrap(r, width))
    n = max(len(lw), len(rw))
    lw += [""] * (n - len(lw))
    rw += [""] * (n - len(rw))
    return [pad(a, width) + mark + b for a, b in zip(lw, rw)]


def main():
    p = argparse.ArgumentParser()
    p.add_argument("left")
    p.add_argument("right")
    p.add_argument("--width", type=int, default=99)
    p.add_argument("--left-label")
    p.add_argument("--right-label")
    a = p.parse_args()
    col = (a.width - 3) // 2
    if col < 10:
        sys.exit("--width is too small for two columns")

    def read(path):
        # One trailing newline ends the last line; it is not an extra line.
        with open(path, encoding="utf-8") as f:
            text = f.read()
        if text.endswith("\n"):
            text = text[:-1]
        return text.replace("\r\n", "\n").split("\n")

    left, right = read(a.left), read(a.right)
    out = []
    if a.left_label or a.right_label:
        out += rows([a.left_label or ""], [a.right_label or ""], col, "   ")
        out.append("-" * col + "   " + "-" * col)
    sm = difflib.SequenceMatcher(None, left, right, autojunk=False)
    for op, i1, i2, j1, j2 in sm.get_opcodes():
        if op == "equal":
            for l, r in zip(left[i1:i2], right[j1:j2]):
                out += rows([l], [r], col, " | ")
        elif op == "delete":
            for l in left[i1:i2]:
                out += rows([l], [], col, " < ")
        elif op == "insert":
            for r in right[j1:j2]:
                out += rows([], [r], col, " > ")
        else:
            ls, rs = left[i1:i2], right[j1:j2]
            for k in range(max(len(ls), len(rs))):
                l = [ls[k]] if k < len(ls) else []
                r = [rs[k]] if k < len(rs) else []
                m = " * " if l and r else (" < " if l else " > ")
                out += rows(l, r, col, m)
    sys.stdout.write("\n".join(x.rstrip() for x in out) + "\n")


if __name__ == "__main__":
    main()
