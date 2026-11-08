---
name: release
description: Cut a TermLaunch release - run tests, bump version, package, push to both remotes, publish the GitHub release, update the Homebrew tap cask, and audit/install it. Use when the user says "release", "bump the version", "ship 0.xx", or "update the tap".
---

# TermLaunch release

Personal app: **no code signing or notarization** (deliberate). Run from the repo root. Stop at the first failure and report it.

## Facts

- Version lives in one place: `MARKETING_VERSION` in `project.yml` (target `TermLaunch` settings). `CFBundleShortVersionString` and `CFBundleVersion` both reference it, so they always equal the release version (e.g. `"0.29"`). Keep two-digit minors (0.28, 0.29, 0.30) so component-wise comparison stays correct.
- Default bump: +0.01 (0.28 -> 0.29). If the user gives a number, use it.
- Remotes: `github` (git@github.com:s303/TermLaunch.git) and `origin` (git@s303.ru:summon.git). Push `main` to both.
- Tap: `/opt/homebrew/Library/Taps/s303/homebrew-tap`, cask `Casks/termlaunch.rb`, remote `https://github.com/s303/homebrew-tap`.
- `dist/` is gitignored. `scripts/package.sh` writes `dist/TermLaunch-<version>-arm64.zip` (arm64 only).

## Steps

1. **Tests.** Must be all green before anything changes:
   ```bash
   xcodebuild -project TermLaunch.xcodeproj -scheme TermLaunch -destination 'platform=macOS' test 2>&1 | grep -E "Executed|error:|FAILED|TEST (SUCCEEDED|FAILED)" | tail -5
   ```
2. **Bump** `MARKETING_VERSION` in `project.yml` (Edit tool); nothing else to change.
3. **Package:** `scripts/package.sh`. Confirm it prints `packed .../TermLaunch-<version>-arm64.zip`.
4. **Commit** `project.yml` only, message `Version <version>`. Only after packaging succeeded.
5. **Push** to both: `git push github main` and `git push origin main`.
6. **GitHub release** (publishes publicly - confirm with the user first unless they already said to release):
   ```bash
   gh release create v<version> dist/TermLaunch-<version>-arm64.zip -R s303/TermLaunch --target main --title "TermLaunch <version>" --notes "<notes>"
   ```
   Notes: summarize `git log --oneline v<previous>..HEAD` (excluding the version commit) in a line or two.
7. **Checksum.** Compute from the *uploaded* asset and compare to the local zip; they must match:
   ```bash
   shasum -a 256 dist/TermLaunch-<version>-arm64.zip
   curl -sL https://github.com/s303/TermLaunch/releases/download/v<version>/TermLaunch-<version>-arm64.zip | shasum -a 256
   ```
8. **Tap.** In the tap repo set `version` and `sha256` in `Casks/termlaunch.rb` (nothing else), commit `termlaunch <version>`, `git push origin main`.
9. **Cask checks and install:**
   ```bash
   brew update
   brew audit --cask --online s303/tap/termlaunch
   brew upgrade --cask s303/tap/termlaunch   # or `brew install --cask` if not installed
   ```
   Then verify: `/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' /Applications/TermLaunch.app/Contents/Info.plist` equals the new version. Audit must report no errors. The upgrade replaces the installed app, so if TermLaunch is running, tell the user it will need a relaunch.

## Report

End with: version, commit hash, release URL, tap commit hash, audit result, installed version. Say plainly anything skipped or failed.
