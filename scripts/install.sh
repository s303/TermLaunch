#!/usr/bin/env bash
# Builds the Release app and installs it to /Applications, replacing any
# previous copy. Run scripts/setup.sh once first (GhosttyKit + project).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="TermLaunch"
DEST="/Applications/$APP_NAME.app"

# Full Xcode is needed; use it even when xcode-select points at the CLT.
if ! xcodebuild -version >/dev/null 2>&1 && [ -d /Applications/Xcode.app ]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

if [ ! -d "$ROOT/Frameworks/GhosttyKit.xcframework" ]; then
  echo "error: GhosttyKit not built; run scripts/setup.sh first" >&2
  exit 1
fi

(cd "$ROOT" && xcodegen generate >/dev/null && xcodebuild \
  -project "$APP_NAME.xcodeproj" -scheme "$APP_NAME" -configuration Release \
  -derivedDataPath build ARCHS=arm64 ONLY_ACTIVE_ARCH=NO build | tail -1)

BUILT="$ROOT/build/Build/Products/Release/$APP_NAME.app"
[ -d "$BUILT" ] || { echo "error: build did not produce $BUILT" >&2; exit 1; }

# Quit the running copy so the files can be replaced.
if pgrep -x "$APP_NAME" >/dev/null; then
  pkill -x "$APP_NAME"
  for _ in $(seq 25); do
    pgrep -x "$APP_NAME" >/dev/null || break
    sleep 0.2
  done
  pkill -9 -x "$APP_NAME" 2>/dev/null || true
fi

# Copy beside the old install first so a failed copy never leaves no app.
rm -rf "$DEST.new"
cp -R "$BUILT" "$DEST.new"
rm -rf "$DEST"
mv "$DEST.new" "$DEST"
open "$DEST"
echo "installed $DEST"
