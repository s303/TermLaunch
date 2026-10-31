#!/usr/bin/env bash
# Builds an arm64-only Release app and packs it into dist/TermLaunch-<version>-arm64.zip.
# Run scripts/setup.sh once first (GhosttyKit + project).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="TermLaunch"
DIST="$ROOT/dist"

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

ARCHS_FOUND="$(lipo -archs "$BUILT/Contents/MacOS/$APP_NAME")"
[ "$ARCHS_FOUND" = "arm64" ] || { echo "error: expected arm64 only, got: $ARCHS_FOUND" >&2; exit 1; }

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  "$BUILT/Contents/Info.plist" 2>/dev/null || echo 0.1)"
ZIP="$DIST/$APP_NAME-$VERSION-arm64.zip"

mkdir -p "$DIST"
rm -f "$ZIP"
ditto -c -k --keepParent "$BUILT" "$ZIP"
echo "packed $ZIP ($(du -h "$ZIP" | cut -f1))"
