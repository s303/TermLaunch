# TermLaunch

macOS-only resident terminal: a global hotkey fades in a borderless Dropdown with Tabs. See [CONTEXT.md](CONTEXT.md) for the language and [docs/adr](docs/adr) for decisions.

## Build

Needs full Xcode (not just Command Line Tools) and Homebrew.

```bash
scripts/setup.sh   # builds GhosttyKit (pinned), generates TermLaunch.xcodeproj
xcodebuild -project TermLaunch.xcodeproj -scheme TermLaunch build
```

Default hotkey: Ctrl+` (`activation` in the config).

## Install

```bash
scripts/install.sh   # builds Release, copies to /Applications, launches it
```

The installed copy turns on launch at login the first time it starts (toggle in the menu-bar item). macOS may ask you to approve it once in System Settings > General > Login Items.

## Config

`~/.config/termlaunch/config.toml` (created on first run, reloaded automatically; menu-bar item has Open/Reload). Holds the activation hotkey, optional `window_hotkey` (toggle normal window mode), chord window, fade, size, edge and `[[command]]` bindings. Terminal appearance comes from your Ghostty config.
