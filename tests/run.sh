#!/bin/bash
# Runs the macOS implementation (bin/docxcount → JXA) against the shared
# expectations in tests/cases.json, then checks the two behaviours that need a
# real file: --selftest works and a non-docx argument is rejected.
#
#   bash tests/run.sh
#
# The same cases.json drives tests/run-node.mjs, which covers the core that
# docxcount.html ships. Needs python3 to build fixtures and parse JSON.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

python3 "$HERE/make_fixtures.py" "$WORK/fixtures" >/dev/null || {
    echo "无法生成测试样本"
    exit 1
}

python3 - "$ROOT" "$WORK/fixtures" "$HERE/cases.json" <<'PY'
import json
import subprocess
import sys

root, fixtures, cases_path = sys.argv[1], sys.argv[2], sys.argv[3]
cases = json.load(open(cases_path, encoding="utf-8"))
binary = root + "/bin/docxcount"
failures = 0
checks = 0


def run(args):
    return subprocess.run([binary] + args, capture_output=True, text=True)


for case in cases["docx"]:
    path = fixtures + "/" + case["fixture"]
    args = ["--json"] + (["--body-only"] if case["bodyOnly"] else []) + [path]
    result = run(args)
    checks += 1
    label = case["fixture"] + (" (body-only)" if case["bodyOnly"] else "")
    try:
        data = json.loads(result.stdout)["files"][0]
        ok = data.get("ok") and data["cjk"] == case["cjk"] and data["words"] == case["words"]
        for key in ("charsNoSpace", "chars"):
            if key in case and data.get(key) != case[key]:
                ok = False
        detail = "cjk={} words={} charsNoSpace={} chars={}".format(
            data.get("cjk"), data.get("words"), data.get("charsNoSpace"), data.get("chars"))
    except Exception:
        ok = False
        detail = "unparsable output: " + (result.stdout or result.stderr).strip()[:120]
    if ok:
        print("PASS  {:<30} {}".format(label, detail))
    else:
        failures += 1
        print("FAIL  {:<30} want cjk={} words={}, got {}".format(
            label, case["cjk"], case["words"], detail))

for case in cases["text"]:
    result = run(["--text", case["text"], "--json"])
    checks += 1
    label = "text " + json.dumps(case["text"], ensure_ascii=False)
    try:
        data = json.loads(result.stdout)
        ok = data["cjk"] == case["cjk"] and data["words"] == case["words"]
        detail = "cjk={} words={}".format(data["cjk"], data["words"])
    except Exception:
        ok = False
        detail = "unparsable output: " + (result.stdout or result.stderr).strip()[:120]
    if ok:
        print("PASS  {:<30} {}".format(label, detail))
    else:
        failures += 1
        print("FAIL  {:<30} want cjk={} words={}, got {}".format(
            label, case["cjk"], case["words"], detail))

print()
print("{} / {} 项通过".format(checks - failures, checks))
sys.exit(0 if failures == 0 else 1)
PY
failures=$?

if "$ROOT/bin/docxcount" --selftest >/dev/null 2>&1; then
    printf 'PASS  %-30s\n' "--selftest"
else
    printf 'FAIL  %-30s\n' "--selftest"
    failures=$((failures + 1))
fi

# A non-docx argument must fail loudly instead of printing zeroes.
echo "not a docx" > "$WORK/plain.txt"
if "$ROOT/bin/docxcount" "$WORK/plain.txt" >/dev/null 2>&1; then
    printf 'FAIL  %-30s accepted a non-docx?\n' "plain.txt"
    failures=$((failures + 1))
else
    printf 'PASS  %-30s rejected\n' "plain.txt"
fi

[ "$failures" -eq 0 ] && exit 0
exit 1
