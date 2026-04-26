#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

swift build -c release

APP="$ROOT/dist/SyncCloud.app"
BINARY="$ROOT/.build/release/SyncCloud"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BINARY" "$APP/Contents/MacOS/SyncCloud"
chmod +x "$APP/Contents/MacOS/SyncCloud"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

if [[ -f "$ROOT/SyncCloud.entitlements" ]]; then
  codesign --force --deep --sign - --entitlements "$ROOT/SyncCloud.entitlements" "$APP" 2>/dev/null || \
    codesign --force --deep --sign - "$APP"
fi

echo "Uygulama paketi: $APP"
if [[ "${SKIP_OPEN:-}" != "1" ]]; then
  open "$APP"
fi
