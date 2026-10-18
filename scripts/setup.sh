#!/usr/bin/env bash
# Builds GhosttyKit.xcframework from a pinned Ghostty commit (see docs/adr/0001).
# Needs full Xcode (Metal toolchain + xcodebuild) and Homebrew.
set -euo pipefail

GHOSTTY_COMMIT="d2865b8f578fa4e85e2f2b85ef97f5ef69de951f"
GHOSTTY_REPO="https://github.com/ghostty-org/ghostty.git"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/vendor/ghostty"
STAMP="$ROOT/Frameworks/.ghostty-build-stamp"

if ! xcodebuild -version >/dev/null 2>&1; then
  echo "error: full Xcode is required (xcode-select -p must point at Xcode.app)" >&2
  exit 1
fi
if ! xcrun -f metal >/dev/null 2>&1; then
  echo "error: Metal toolchain missing; run: xcodebuild -downloadComponent MetalToolchain" >&2
  exit 1
fi

# Ghostty pins its Zig version (minimum_zig_version in build.zig.zon); resolve
# the keg-only formula by prefix instead of relying on PATH.
brew list zig@0.16 >/dev/null 2>&1 || brew install zig@0.16
brew list xcodegen >/dev/null 2>&1 || brew install xcodegen
ZIG="$(brew --prefix zig@0.16)/bin/zig"

mkdir -p "$ROOT/vendor" "$ROOT/Frameworks"
if [ ! -d "$SRC/.git" ]; then
  git init -q "$SRC"
  git -C "$SRC" remote add origin "$GHOSTTY_REPO"
fi
if [ "$(git -C "$SRC" rev-parse HEAD 2>/dev/null || true)" != "$GHOSTTY_COMMIT" ]; then
  git -C "$SRC" fetch --depth 1 origin "$GHOSTTY_COMMIT"
  git -C "$SRC" checkout -q --force FETCH_HEAD
fi

# Rebuild when the pin changes or the output is missing; checking only for the
# xcframework directory would miss a bumped pin.
if [ -f "$STAMP" ] && [ "$(cat "$STAMP")" = "$GHOSTTY_COMMIT" ] \
   && [ -d "$ROOT/Frameworks/GhosttyKit.xcframework" ]; then
  echo "GhosttyKit is up to date ($GHOSTTY_COMMIT)"
else
  (cd "$SRC" && "$ZIG" build \
    -Doptimize=ReleaseFast \
    -Demit-xcframework=true \
    -Dxcframework-target=native \
    -Demit-macos-app=false)

  rm -rf "$ROOT/Frameworks/GhosttyKit.xcframework"
  cp -R "$SRC/macos/GhosttyKit.xcframework" "$ROOT/Frameworks/"

  # Runtime resources: shell integration + themes under ghostty/, terminfo
  # as its sibling (xterm-ghostty lookups depend on this layout).
  RES="$ROOT/Resources"
  rm -rf "$RES/ghostty" "$RES/terminfo"
  mkdir -p "$RES"
  cp -R "$SRC/zig-out/share/ghostty" "$RES/ghostty"
  cp -R "$SRC/zig-out/share/terminfo" "$RES/terminfo"

  echo "$GHOSTTY_COMMIT" > "$STAMP"
fi

(cd "$ROOT" && xcodegen generate)
echo "done: open TermLaunch.xcodeproj"
