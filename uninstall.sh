#!/bin/bash
# Removes docx-word-count: the quick action and the terminal command.
#
#   bash uninstall.sh              remove everything
#   bash uninstall.sh --dry-run    show what would be done, touch nothing

set -euo pipefail

SUPPORT_DIR="$HOME/Library/Application Support/DocxWordCount"
SERVICES_DIR="$HOME/Library/Services"
WORKFLOWS=(DocxWordCount.workflow CountSelection.workflow)
LINK_RECORD="$SUPPORT_DIR/cli-link.txt"

DRY_RUN=0
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        -h|--help) sed -n '2,7p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

say() { printf '==> %s\n' "$*"; }
act() {
    if [ "$DRY_RUN" = 1 ]; then
        printf '    [dry-run] %s\n' "$*"
    else
        "$@"
    fi
}

if [ -f "$LINK_RECORD" ]; then
    link="$(cat "$LINK_RECORD")"
    say "删除终端命令 ${link}"
    act rm -f "$link"
fi

for workflow in "${WORKFLOWS[@]}"; do
    say "删除快速操作 ${SERVICES_DIR}/${workflow}"
    act rm -rf "$SERVICES_DIR/$workflow"
done

say "删除程序目录 ${SUPPORT_DIR}"
act rm -rf "$SUPPORT_DIR"

if [ "$DRY_RUN" = 0 ]; then
    killall Finder >/dev/null 2>&1 || true
fi

echo
echo "已卸载。备忘录和 .docx 文件都没有被改动。"
