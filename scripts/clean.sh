#!/usr/bin/env bash
# Removes build outputs and unregisters dev TermLaunch.app copies from Launch Services.
# Leaves dist/ (release zips) and /Applications alone.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="TermLaunch"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

if ! xcodebuild -version >/dev/null 2>&1 && [ -d /Applications/Xcode.app ]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

if [ -d "$ROOT/$APP_NAME.xcodeproj" ]; then
  for cfg in Debug Release; do
    xcodebuild -project "$ROOT/$APP_NAME.xcodeproj" -scheme "$APP_NAME" -configuration "$cfg" \
      -derivedDataPath "$ROOT/build" clean >/dev/null 2>&1 || true
  done
fi

for app in "$ROOT"/build/Build/Products/*/"$APP_NAME.app" \
           "$HOME"/Library/Developer/Xcode/DerivedData/"$APP_NAME"-*/Build/Products/*/"$APP_NAME.app"; do
  [ -d "$app" ] && "$LSREGISTER" -u "$app" 2>/dev/null || true
done

rm -rf "$ROOT/build" "$HOME"/Library/Developer/Xcode/DerivedData/"$APP_NAME"-*
echo "cleaned build/ and Xcode DerivedData for $APP_NAME"
