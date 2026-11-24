#!/bin/bash
# Builds SelectionCount.app from src/selection-panel.m.
#
#   bash tools/build-selection-panel.sh            → build/SelectionCount.app
#   bash tools/build-selection-panel.sh --verify   → also runs --selftest and --count-stdin
#
# Uses clang from the Xcode Command Line Tools (no Xcode.app needed). The
# resulting .app is ad-hoc signed; macOS identifies it by bundle id and path, so
# install it in a stable place and do not move it after granting Accessibility.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
APP="$ROOT/build/SelectionCount.app"
BINARY="$APP/Contents/MacOS/SelectionCount"
SOURCE="$ROOT/src/selection-panel.m"

command -v clang >/dev/null 2>&1 || { echo "找不到 clang：xcode-select --install" >&2; exit 1; }

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key>
	<string>SelectionCount</string>
	<key>CFBundleDisplayName</key>
	<string>选中字数</string>
	<key>CFBundleIdentifier</key>
	<string>com.docxwordcount.selectionpanel</string>
	<key>CFBundleExecutable</key>
	<string>SelectionCount</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>12.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSHighResolutionCapable</key>
	<true/>
</dict>
</plist>
PLIST

echo "编译中…"
clang -fobjc-arc -O2 -Wall \
    -framework Cocoa -framework ApplicationServices \
    -o "$BINARY" "$SOURCE"

codesign --force --sign - "$APP" >/dev/null 2>&1 || echo "（本地签名跳过，不影响本机使用）"
echo "已生成 $APP"

if [ "${1:-}" = "--verify" ]; then
    echo "--- 自检 ---"
    "$BINARY" --selftest
    echo "--- 标准输入 ---"
    printf '你好 world 42' | "$BINARY" --count-stdin
    echo "--- 权限 ---"
    "$BINARY" --check-access
fi
