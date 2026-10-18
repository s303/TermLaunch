# Embed terminals via GhosttyKit, pinned to a Ghostty commit

TermLaunch is a native Swift/AppKit app that hosts terminal surfaces through Ghostty's full embedding API (the GhosttyKit xcframework, built with Zig), not the terminal-core-only `libghostty-vt`. Ghostty supplies rendering, input, the pty and config parsing for each surface, which the Dropdown's Tabs and the reuse of the user's Ghostty config all depend on.

The API is not stable and its only upstream consumer is Ghostty's own macOS app, so the Ghostty commit is pinned and upgraded deliberately. Each upgrade may break the Swift glue, and building requires the Zig version Ghostty pins.

## Considered Options

- `libghostty-vt`: a more stable API, but TermLaunch would have to write its own renderer, pty handling and input.
