# Built-in launcher as a native Tab fed by compiled-in providers

TermLaunch replaces the external `oa` picker (`run = "~/.cargo/bin/oa"`) with a built-in Launcher Tab: a native AppKit view (search field at the bottom, results growing upward), not a ghostty surface. It is bound like any command, with `builtin = "launcher"` in place of `run`, and follows the Command Tab rules: running a result's action closes the Tab and hides the Dropdown, as does Esc. The resident app keeps the app index warm, so there is no login shell, `mdfind` run or TUI startup per use. Frecency stays in `~/.local/share/oa/frecency.json` so history carries over and the CLI `oa` keeps working.

Results come from providers behind one Swift protocol: an app provider (Spotlight index, fuzzy × frecency) and a calculator provider. Providers are compiled in and private to TermLaunch; there is no plugin loading, manifest or IPC. Adding one is a Swift file plus an entry in the provider list.

```swift
protocol Provider {
    var id: String { get }
    func results(for query: String) -> [LauncherItem]   // [] = no answer
}
struct LauncherItem { title, subtitle, icon, action }
```

- Every provider sees every query and decides for itself whether it applies; returning `[]` means no answer.
- Results are grouped by provider in a fixed order in code, calculator first, then apps. The calculator only answers when the whole query parses, so when it answers it is almost always the intent. Each provider orders its own items.
- One action per item: apps launch, calculator copies the result to the clipboard. Every action closes the Tab.
- Providers are synchronous and run on the main thread on each keystroke; both current providers are in-memory and sub-millisecond.

## Future work

- Keyword triggers: a provider may declare a prefix (`f `, `?`) and run only when it is typed, with the prefix stripped. Add when a slow or noisy provider appears; until then all providers run on every query.
- Async providers: `results(for:) async` with cancellation on each keystroke and stable merging of late results, needed by the first provider that touches disk or network. Only internal providers implement the protocol, so the change is local.
- Cross-provider ranking: a priority hint for exact/intent-clear results, or frecency tracked per item across providers, if fixed provider order stops being enough.
- Alternate actions (⌘⏎ reveal in Finder, ⌥⏎ copy path) by making the action a list.

## Considered Options

- Keep `oa` as an external command, or bundle the binary in the app: no work, but keeps the per-use shell spawn and cold start.
- Link the Rust core (scorer, frecency, calc) as a static library: keeps nucleo's ranking, but adds a Rust toolchain to the build next to the pinned GhosttyKit for ~500 lines of logic.
- External plugins (executables speaking JSON lines, Alfred script-filter style): rejected, providers are for TermLaunch only and there is no plan to make them extensible.
- One shared score across providers: rejected, scores from different providers are not comparable.
