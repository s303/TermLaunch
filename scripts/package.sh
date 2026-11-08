#!/usr/bin/env bash
# Builds an arm64-only Release app and packs it into dist/TermLaunch-<version>-arm64.zip.
# Run scripts/setup.sh once first (GhosttyKit + project).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="TermLaunch"
DIST="$ROOT/dist"

# Don't leave build/*.app registered with Launch Services (extra apps in Launchpad/Spotlight).
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
cleanup() {
  for app in "$ROOT"/build/Build/Products/*/"$APP_NAME.app"; do
    [ -d "$app" ] && "$LSREGISTER" -u "$app" 2>/dev/null || true
  done
  rm -rf "$ROOT/build"
}
trap cleanup EXIT

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

# Re-sign with a stable self-signed identity. An ad-hoc signature changes with every
# build, so macOS (TCC) re-asks for Desktop/Documents/App Management after each update;
# a fixed certificate keeps the app's designated requirement, and its grants, stable.
# Create it once in Keychain Access > Certificate Assistant > Create a Certificate
# (Self-Signed Root, Code Signing). Keep the private key: a new one means one more prompt.
SIGN_IDENTITY="${SIGN_IDENTITY:-TermLaunch Signing}"
if ! security find-certificate -c "$SIGN_IDENTITY" >/dev/null 2>&1; then
  echo "error: signing certificate \"$SIGN_IDENTITY\" not found in the keychain" >&2
  exit 1
fi
codesign --force --sign "$SIGN_IDENTITY" --timestamp=none "$BUILT"
codesign --verify --strict "$BUILT"
codesign -d -r- "$BUILT" 2>&1 | grep -qE 'certificate (leaf|root)' \
  || { echo "error: $BUILT is not signed with a certificate" >&2; exit 1; }

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  "$BUILT/Contents/Info.plist" 2>/dev/null || echo 0.1)"
ZIP="$DIST/$APP_NAME-$VERSION-arm64.zip"

mkdir -p "$DIST"
rm -f "$ZIP"
ditto -c -k --keepParent "$BUILT" "$ZIP"
echo "packed $ZIP ($(du -h "$ZIP" | cut -f1))"
