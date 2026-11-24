#!/usr/bin/env python3
"""Builds docxcount.html: the single-file page with the shared core inlined.

    python3 tools/build-page.py

The page must stay self-contained (no external script, style or font), because it
is meant to be opened by double-clicking from any folder, on any OS, offline.
"""

import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
CORE = ROOT / "src" / "count-core.cjs"
PAGE = ROOT / "src" / "page.html"
OUTPUT = ROOT / "docxcount.html"
MARKER = "/* ==== CORE (injected by tools/build-page.py from src/count-core.cjs) ==== */"


def main() -> int:
    core = CORE.read_text(encoding="utf-8")
    page = PAGE.read_text(encoding="utf-8")

    if MARKER not in page:
        print("page.html 里找不到注入点：" + MARKER, file=sys.stderr)
        return 1
    if "</script" in core.lower():
        print("count-core.cjs 里出现了 </script，会把页面截断，先改写这一行", file=sys.stderr)
        return 1

    built = page.replace(MARKER, MARKER + "\n" + core, 1)
    OUTPUT.write_text(built, encoding="utf-8")
    print("写出 " + str(OUTPUT.relative_to(ROOT)) + "（" + str(len(built.encode("utf-8"))) + " 字节）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
