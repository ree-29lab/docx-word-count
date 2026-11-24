#!/bin/bash
# Runs the counter against the fixture documents and checks every number.
#
#   bash tests/run.sh
#
# Needs python3 (for building fixtures and for asserting on JSON) and nothing else.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

python3 "$HERE/make_fixtures.py" "$WORK/fixtures" >/dev/null || {
    echo "无法生成测试样本"
    exit 1
}

failures=0
checks=0

# name, flags, expected cjk, expected words
check() {
    local name="$1" flags="$2" wantCjk="$3" wantWords="$4"
    local out
    out="$("$ROOT/bin/docxcount" --json $flags "$WORK/fixtures/$name" 2>/dev/null)"
    checks=$((checks + 1))
    local got
    got="$(printf '%s' "$out" | python3 -c '
import json, sys
data = json.load(sys.stdin)
f = data["files"][0]
print(("ok" if f["ok"] else "fail"), f.get("cjk", 0), f.get("words", 0))
')"
    if [ "$got" = "ok $wantCjk $wantWords" ]; then
        printf 'PASS  %-24s cjk=%-4s words=%s\n' "$name" "$wantCjk" "$wantWords"
    else
        printf 'FAIL  %-24s want "ok %s %s", got "%s"\n' "$name" "$wantCjk" "$wantWords" "$got"
        failures=$((failures + 1))
    fi
}

check simple.docx          ""              2 2
check split-runs.docx      ""              2 2
check tracked-deletion.docx ""             4 0
check tab-and-break.docx   ""              0 3
check with-header.docx     ""              4 0
check with-header.docx     "--body-only"   2 0
check field-code.docx      ""              4 0

# Selected-text mode: the pipeline the "统计选中字数" service uses.
check_text() {
    local label="$1" text="$2" wantCjk="$3" wantWords="$4"
    local got
    got="$(printf '%s' "$text" | "$ROOT/bin/docxcount" --stdin --json 2>/dev/null | python3 -c '
import json, sys
d = json.load(sys.stdin)
print(d["cjk"], d["words"])
')"
    checks=$((checks + 1))
    if [ "$got" = "$wantCjk $wantWords" ]; then
        printf 'PASS  %-24s cjk=%-4s words=%s\n' "$label" "$wantCjk" "$wantWords"
    else
        printf 'FAIL  %-24s want "%s %s", got "%s"\n' "$label" "$wantCjk" "$wantWords" "$got"
        failures=$((failures + 1))
    fi
}

check_text "stdin 中英混排" "你好 world 42" 2 2
check_text "stdin 整段中文" "今天天气不错，我去跑步了。" 11 0
check_text "stdin 空输入" "" 0 0

# The same logic lives in --selftest, which runs without any file.
checks=$((checks + 1))
if "$ROOT/bin/docxcount" --selftest >/dev/null 2>&1; then
    printf 'PASS  %-24s\n' "--selftest"
else
    printf 'FAIL  %-24s\n' "--selftest"
    failures=$((failures + 1))
fi

# A non-docx argument must fail loudly instead of printing zeroes.
checks=$((checks + 1))
echo "not a docx" > "$WORK/plain.txt"
if "$ROOT/bin/docxcount" "$WORK/plain.txt" >/dev/null 2>&1; then
    printf 'FAIL  %-24s rejected a non-docx?\n' "plain.txt"
    failures=$((failures + 1))
else
    printf 'PASS  %-24s rejected\n' "plain.txt"
fi

echo
if [ "$failures" -eq 0 ]; then
    echo "全部 $checks 项通过"
    exit 0
fi
echo "$failures / $checks 项失败"
exit 1
