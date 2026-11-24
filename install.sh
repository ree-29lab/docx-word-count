#!/bin/bash
# Installs docx-word-count: a Finder quick action plus a terminal command.
#
#   bash install.sh              install (or upgrade) for the current user
#   bash install.sh --dry-run    show what would be done, touch nothing
#   bash install.sh --help       this text
#
# Installed locations:
#   ~/Library/Application Support/DocxWordCount/   program + command wrapper
#   ~/Library/Services/DocxWordCount.workflow      the Finder quick action
#   /usr/local/bin/docxcount (or ~/bin/docxcount)  the terminal command
# Remove it all with uninstall.sh.

set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUPPORT_DIR="$HOME/Library/Application Support/DocxWordCount"
SERVICES_DIR="$HOME/Library/Services"
WORKFLOW_NAME="DocxWordCount.workflow"
WORKFLOW_SRC="$SRC_DIR/quickaction/$WORKFLOW_NAME"
WORKFLOW_DST="$SERVICES_DIR/$WORKFLOW_NAME"
LINK_RECORD="$SUPPORT_DIR/cli-link.txt"

DRY_RUN=0
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        -h|--help) sed -n '2,16p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
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

# ---------- checks ----------
if [ "$(uname -s)" != "Darwin" ]; then
    echo "This tool only runs on macOS." >&2
    exit 1
fi
for required in /usr/bin/osascript /usr/bin/unzip /usr/bin/zip; do
    [ -x "$required" ] || { echo "missing $required" >&2; exit 1; }
done
[ -f "$SRC_DIR/src/wordcount.js" ] || { echo "src/wordcount.js not found next to this installer" >&2; exit 1; }
[ -d "$WORKFLOW_SRC" ] || { echo "quickaction/ not found next to this installer" >&2; exit 1; }

# ---------- program ----------
say "安装程序到 ${SUPPORT_DIR}"
act mkdir -p "$SUPPORT_DIR"
act cp "$SRC_DIR/src/wordcount.js" "$SUPPORT_DIR/wordcount.js"
act chmod 644 "$SUPPORT_DIR/wordcount.js"
act cp "$SRC_DIR/bin/docxcount" "$SUPPORT_DIR/wordcount"
act chmod 755 "$SUPPORT_DIR/wordcount"

# ---------- terminal command ----------
say "安装终端命令 docxcount"
link_dir=""
for candidate in /usr/local/bin "$HOME/bin"; do
    if [ "$DRY_RUN" = 1 ]; then
        link_dir="$candidate"
        break
    fi
    if mkdir -p "$candidate" 2>/dev/null && [ -w "$candidate" ]; then
        link_dir="$candidate"
        break
    fi
done
if [ -z "$link_dir" ]; then
    say "没有可写的命令目录，跳过 docxcount 命令（程序本体已装好）"
elif [ "$DRY_RUN" = 1 ]; then
    printf '    [dry-run] ln -sf %s %s/docxcount\n' "$SUPPORT_DIR/wordcount" "$link_dir"
else
    ln -sf "$SUPPORT_DIR/wordcount" "$link_dir/docxcount"
    printf '%s\n' "$link_dir/docxcount" > "$LINK_RECORD"
    echo "    $link_dir/docxcount"
    case ":$PATH:" in
        *":$link_dir:"*) ;;
        *) echo "    注意：$link_dir 不在 PATH 里，需要把下面这行加到 ~/.zshrc："
           echo "    export PATH=\"$link_dir:\$PATH\"" ;;
    esac
fi

# ---------- quick action ----------
say "安装 Finder 快速操作：右键 › 快速操作 › 统计字数"
act mkdir -p "$SERVICES_DIR"
act rm -rf "$WORKFLOW_DST"
act cp -R "$WORKFLOW_SRC" "$WORKFLOW_DST"
act touch "$WORKFLOW_DST"

if [ "$DRY_RUN" = 0 ]; then
    # Finder caches the services menu; restarting it is the reliable refresh.
    killall Finder >/dev/null 2>&1 || true
fi

# ---------- self test ----------
if [ "$DRY_RUN" = 0 ]; then
    say "自检"
    if "$SUPPORT_DIR/wordcount" --selftest >/dev/null 2>&1; then
        echo "    计数逻辑正常"
    else
        echo "    自检失败，看：$SUPPORT_DIR/wordcount --selftest" >&2
    fi
fi

echo
echo "完成。两种用法："
echo "  1) Finder 里选中一个 .docx › 右键 › 快速操作 › 统计字数"
echo "  2) 终端：docxcount 文件.docx（多个文件也行；--body-only 只数正文）"
echo "  程序目录：${SUPPORT_DIR}"
echo "  卸载：bash \"$SRC_DIR/uninstall.sh\""
