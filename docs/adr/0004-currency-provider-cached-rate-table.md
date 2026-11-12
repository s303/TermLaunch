# Currency provider reads a cached, lazily fetched rate table

The Launcher Tab gains a currency provider backed by [Frankfurter](https://frankfurter.dev/) v2. Instead of one request per pair, TermLaunch fetches the whole table (`GET https://api.frankfurter.dev/v2/rates`: about 12.7 KB, 200 codes covering fiat, crypto and metals, all quoted against EUR) and works out cross rates locally (USD→RUB = EUR→RUB ÷ EUR→USD). The table lives in a resident `RateStore`, a store owned by the app like `AppIndex`, so it outlives individual Launcher Tabs. The provider reads it synchronously from memory.

That keeps the `LauncherProvider` protocol from [ADR 0003](0003-builtin-launcher-providers.md) synchronous. ADR 0003 expected the first network provider to need async providers. Fetching a whole table into a store makes that unnecessary: the provider triggers a fetch as a fire-and-forget side effect, and when the fetch completes the store posts `RateStore.didChange`, which `LauncherView` observes to re-query, as it already does for `AppIndex.didChange`.

## Fetching and caching

- **Lazy.** No fetch happens at launch, on a timer, or when the Launcher opens. A fetch starts only when a query parses as a conversion: an amount followed by a code known in the cached table. When there is no cache yet, any token of 3 or more letters after an amount counts, since codes can't be checked. A fetch also runs only if the table is older than 6 hours.
- **One fetch at a time.** Keystrokes that come in during a fetch join it. After a failure, at least 1 minute passes before the next attempt.
- **Revalidation.** The stored `ETag` is sent as `If-None-Match`. A `304` only updates the fetch time.
- **Disk.** `~/Library/Caches/TermLaunch/rates.json` holds the raw response, its `ETag` and the fetch time. It is loaded at launch, so the first query after a restart works offline. Deleting it only causes a refetch.
- **Stale is fine.** A stale table answers immediately with `updating…` in the hint while the refresh runs, and the row updates in place. After a failure the stale table is used indefinitely. Its age appears in the hint once the rates are more than 2 days old. With no table at all, the provider shows `fetching rates…`, or `rates unavailable` after a failure.

## Queries and rows

- Syntax: `<amount> <FROM> [to|in] <TO>`, case-insensitive. The space before the code and the `to`/`in` are optional. The amount is any calculator expression (`(20+5)*4 usd to eur`). Only ISO codes are accepted, not symbols or names.
- `<amount> <FROM>` without a target shows one row per default target from the config, leaving out the source currency.
- Codes must be complete; there is no prefix completion. While the target is incomplete, the default targets are shown.
- The row title is `92.31 EUR`, with hint `100 USD · ⏎ copy`. The display uses grouping separators. Decimals scale with magnitude: 2 for values ≥ 1, otherwise enough significant digits to show the value. The decimal point is always `.`.
- Enter copies the bare number (no grouping, no code) and closes the Tab like any other provider action.
- Provider order: calculator, currency, apps. A conversion query never parses as a calculation, so the calculator and currency providers never both answer.

## Config

```toml
[launcher.currency]
enabled = true                    # default true
targets = ["EUR", "RUB", "USD"]   # at most 3
```

`[launcher.<provider>]` is the convention for per-provider settings going forward. Targets are a real TOML array, so the minimal TOML parser gains arrays of strings. More than 3 targets, or entries that aren't strings, produce a config warning and are ignored. Codes that the table doesn't know are skipped when queries run.

## Out of scope

Mixed arithmetic (`100 usd + 20 eur`), symbols and code-first syntax (`$100`, `usd 100`), amount suffixes (`1k`), historical rates, and queries that are only codes (`usd eur`).

## Considered Options

- **Frankfurter v1** (`/v1/latest`): ECB data only, 30 currencies, and no RUB since March 2022.
- **One request per pair, with a cache per pair:** needs async providers, debouncing and network calls while typing, and gets fresher data that the sources don't publish anyway.
- **Fetching on launch, on a timer, or when the Launcher opens:** causes network traffic on days with no conversions.
- **Waiting for fresh rates before showing a result:** more correct, but adds a visible delay to the first query of the day. Daily rate changes are tiny.
- **A comma-separated string for targets:** needs no parser change, but isn't standard TOML.
