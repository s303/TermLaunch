# TermLaunch

macOS-only resident terminal: a global hotkey fades in a borderless Dropdown with Tabs. See [CONTEXT.md](CONTEXT.md) for the language and [docs/adr](docs/adr) for decisions.

## Build

Needs full Xcode (not just Command Line Tools) and Homebrew.

```bash
scripts/setup.sh   # builds GhosttyKit (pinned), generates TermLaunch.xcodeproj
xcodebuild -project TermLaunch.xcodeproj -scheme TermLaunch build
```

Default hotkey: Ctrl+` (`dropdown` under `[hotkeys]` in the config).

## Install

```bash
brew install --cask s303/tap/termlaunch
```

To build the release zip yourself, run `scripts/package.sh` (output in `dist/`).

The installed copy turns on launch at login the first time it starts (toggle in the menu-bar item). macOS may ask you to approve it once in System Settings > General > Login Items.

## Config

`~/.config/termlaunch/config.toml` (created on first run, reloaded automatically; menu-bar item has Open/Reload). Tables: `[hotkeys]` (`dropdown`, optional `window` to toggle normal window mode), `[dropdown]` (`columns`, `rows`, `edge`, `fade_ms`, `chord_timeout_ms`), optional `[tabbar]`, and `[[command]]` bindings (`chord` and/or `hotkey`, `run`, optional `cwd` and `name` for its menu label and Tab title). Terminal appearance comes from your Ghostty config.

## Licenses

TermLaunch embeds [Ghostty](https://ghostty.org) (MIT) and its bundled components. Notices are in [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md) and ship inside the app bundle.
