#!/bin/bash
# Checks the built selection panel against the shared expectations.
#
#   bash tests/run-panel.sh
#
# Only the text cases apply: the panel counts a selection, it never reads a file.
# Needs build/SelectionCount.app (tools/build-selection-panel.sh) and python3.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
BINARY="$ROOT/build/SelectionCount.app/Contents/MacOS/SelectionCount"

if [ ! -x "$BINARY" ]; then
    echo "先编译：bash tools/build-selection-panel.sh" >&2
    exit 1
fi

python3 - "$BINARY" "$HERE/cases.json" <<'PY'
import json
import subprocess
import sys

binary, cases_path = sys.argv[1], sys.argv[2]
cases = json.load(open(cases_path, encoding="utf-8"))["text"]
failures = 0
checks = 0

for case in cases:
    result = subprocess.run([binary, "--count-stdin"], input=case["text"],
                            capture_output=True, text=True)
    checks += 1
    label = "panel " + json.dumps(case["text"], ensure_ascii=False)
    try:
        data = json.loads(result.stdout)
        ok = data["cjk"] == case["cjk"] and data["words"] == case["words"]
        detail = "cjk={} words={}".format(data["cjk"], data["words"])
    except Exception:
        ok = False
        detail = "输出无法解析: " + (result.stdout or result.stderr).strip()[:120]
    if ok:
        print("PASS  {:<32} {}".format(label, detail))
    else:
        failures += 1
        print("FAIL  {:<32} want cjk={} words={}, got {}".format(
            label, case["cjk"], case["words"], detail))

print()
print("{} / {} 项通过".format(checks - failures, checks))
sys.exit(0 if failures == 0 else 1)
PY
status=$?

if "$BINARY" --selftest >/dev/null 2>&1; then
    printf 'PASS  %-32s\n' "--selftest"
else
    printf 'FAIL  %-32s\n' "--selftest"
    status=1
fi

exit $status
