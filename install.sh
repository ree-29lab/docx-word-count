#!/bin/bash
# Installs docx-word-count for the current user:
#   - the terminal command docxcount
#   - two quick actions (whole .docx in Finder, selected text in any app)
#   - SelectionCount.app, the floating panel that counts selected text live
#
#   bash install.sh              install (or upgrade)
#   bash install.sh --dry-run    show what would be done, touch nothing
#   bash install.sh --help       this text
#
# Installed locations:
#   ~/Library/Application Support/DocxWordCount/     program + command wrapper
#   ~/Library/Services/DocxWordCount.workflow        Finder: 统计字数
#   ~/Library/Services/CountSelection.workflow       服务: 统计选中字数
#   ~/Applications/SelectionCount.app                选中即计数的浮窗
#   /usr/local/bin/docxcount (or ~/bin/docxcount)    terminal command
# Remove it all with uninstall.sh.

set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUPPORT_DIR="$HOME/Library/Application Support/DocxWordCount"
SERVICES_DIR="$HOME/Library/Services"
AGENTS_DIR="$HOME/Library/LaunchAgents"
APPS_DIR="$HOME/Applications"
WORKFLOWS=(DocxWordCount.workflow CountSelection.workflow)
LINK_RECORD="$SUPPORT_DIR/cli-link.txt"
PANEL_LABEL="com.docxwordcount.selectionpanel"
PANEL_PLIST="$AGENTS_DIR/$PANEL_LABEL.plist"
PANEL_APP="$APPS_DIR/SelectionCount.app"
PANEL_SRC="$SRC_DIR/build/SelectionCount.app"
LOG_FILE="$HOME/Library/Logs/DocxWordCount.log"

DRY_RUN=0
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        -h|--help) sed -n '2,18p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
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
for workflow in "${WORKFLOWS[@]}"; do
    [ -d "$SRC_DIR/quickaction/$workflow" ] || { echo "quickaction/$workflow missing next to this installer" >&2; exit 1; }
done

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

# ---------- quick actions ----------
say "安装两个快速操作：选中文件 › 统计字数；选中文字 › 统计选中字数"
act mkdir -p "$SERVICES_DIR"
for workflow in "${WORKFLOWS[@]}"; do
    act rm -rf "$SERVICES_DIR/$workflow"
    act cp -R "$SRC_DIR/quickaction/$workflow" "$SERVICES_DIR/$workflow"
    act touch "$SERVICES_DIR/$workflow"
    printf '    %s\n' "$SERVICES_DIR/$workflow"
done

if [ "$DRY_RUN" = 0 ]; then
    # Finder caches the services menu; restarting it is the reliable refresh.
    killall Finder >/dev/null 2>&1 || true
fi

# ---------- selection panel ----------
say "安装选中即计数的浮窗 SelectionCount"
panel_ready=1
if [ "$DRY_RUN" = 0 ] && [ ! -d "$PANEL_SRC" ]; then
    if command -v clang >/dev/null 2>&1; then
        echo "    首次安装，正在编译…"
        if ! bash "$SRC_DIR/tools/build-selection-panel.sh" >/dev/null 2>&1; then
            echo "    编译失败，跳过浮窗（其它功能不受影响）"
            panel_ready=0
        fi
    else
        echo "    没有 clang，跳过浮窗（xcode-select --install 之后重跑本脚本）"
        panel_ready=0
    fi
fi

if [ "$panel_ready" = 1 ] && [ "$DRY_RUN" = 1 ] && [ ! -d "$PANEL_SRC" ]; then
    printf '    [dry-run] 会先编译 build/SelectionCount.app\n'
fi

if [ "$panel_ready" = 1 ]; then
    act mkdir -p "$APPS_DIR"
    act rm -rf "$PANEL_APP"
    if [ "$DRY_RUN" = 1 ]; then
        printf '    [dry-run] cp -R %s %s\n' "$PANEL_SRC" "$PANEL_APP"
        printf '    [dry-run] 写启动项 %s\n' "$PANEL_PLIST"
    else
        cp -R "$PANEL_SRC" "$PANEL_APP"
        mkdir -p "$AGENTS_DIR"
        cat > "$PANEL_PLIST" <<PLIST_END
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$PANEL_LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$PANEL_APP/Contents/MacOS/SelectionCount</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>LimitLoadToSessionType</key>
    <string>Aqua</string>
    <key>StandardOutPath</key>
    <string>$LOG_FILE</string>
    <key>StandardErrorPath</key>
    <string>$LOG_FILE</string>
</dict>
</plist>
PLIST_END
        chmod 644 "$PANEL_PLIST"
        echo "    $PANEL_APP"
        launchctl bootout "gui/$(id -u)/$PANEL_LABEL" 2>/dev/null || true
        if ! launchctl bootstrap "gui/$(id -u)" "$PANEL_PLIST"; then
            echo "    启动项加载失败，改用 launchctl load 重试" >&2
            launchctl unload "$PANEL_PLIST" 2>/dev/null || true
            launchctl load -w "$PANEL_PLIST" || true
        fi
        if launchctl print "gui/$(id -u)/$PANEL_LABEL" >/dev/null 2>&1; then
            echo "    启动项已加载"
        else
            echo "    启动项没起来，看日志：$LOG_FILE" >&2
        fi
    fi
fi

# ---------- self test ----------
if [ "$DRY_RUN" = 0 ]; then
    say "自检"
    if "$SUPPORT_DIR/wordcount" --selftest >/dev/null 2>&1; then
        echo "    计数逻辑正常（docx / 选中文字）"
    else
        echo "    自检失败，看：$SUPPORT_DIR/wordcount --selftest" >&2
    fi
    if [ "$panel_ready" = 1 ] && [ -x "$PANEL_APP/Contents/MacOS/SelectionCount" ]; then
        rm -f "$SUPPORT_DIR/panel-status.txt"
        launchctl kickstart -k "gui/$(id -u)/$PANEL_LABEL" >/dev/null 2>&1 || true
        panel_status=""
        for _ in 1 2 3 4 5 6; do
            sleep 0.7
            panel_status="$(cat "$SUPPORT_DIR/panel-status.txt" 2>/dev/null || true)"
            [ -n "$panel_status" ] && break
        done
        case "$panel_status" in
            ok) echo "    浮窗已获辅助功能权限" ;;
            *) echo "    浮窗还差权限：系统设置 › 隐私与安全性 › 辅助功能 → 勾选 SelectionCount" ;;
        esac
    fi
fi

echo
echo "完成。四种用法："
echo "  1) 任何 app 里选中文字 → 右下角自动跳字数（SelectionCount 浮窗）"
echo "  2) 任何 app 里选中文字 › 右键 › 服务 › 统计选中字数（弹窗，不需要权限）"
echo "  3) Finder 里选中 .docx › 右键 › 快速操作 › 统计字数（整篇）"
echo "  4) 终端：docxcount 文件.docx（--body-only 只数正文）"
echo "  程序目录：${SUPPORT_DIR}"
echo "  卸载：bash \"$SRC_DIR/uninstall.sh\""
