import Foundation

struct CommandBinding: Equatable {
    /// Single key pressed during the chord window (lowercased).
    let key: String?
    let run: String
    let cwd: String?
    /// Global hotkey (KeySpec syntax) that shows the Dropdown and opens this command.
    var hotkey: String? = nil

    /// Identity of the Command Tab; at most one Tab exists per id.
    var id: String {
        if let key { return "key:" + key }
        if let hotkey { return "hotkey:" + hotkey.lowercased() }
        return "run:" + run
    }
}

enum Edge: String {
    case top, bottom, left, right
}

/// App-level settings from ~/.config/termlaunch/config.toml. Terminal
/// appearance comes from the user's Ghostty config, not from here.
struct Config: Equatable {
    var activation = "ctrl+`"
    var chordWindowMs = 300
    var fadeMs = 120
    var columns = 120
    var rows = 30
    var edge = Edge.top
    var commands: [CommandBinding] = []

    static var path: URL {
        if let override = ProcessInfo.processInfo.environment["TERMLAUNCH_CONFIG"] {
            return URL(fileURLWithPath: override)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/termlaunch/config.toml")
    }

    /// Loads the file, writing a commented default if it doesn't exist.
    /// Bad values fall back to defaults with a warning. An unreadable or
    /// unparseable file yields a nil config, so callers keep their current one
    /// (a half-saved edit must not wipe the hotkey and commands).
    static func load() -> (config: Config?, warnings: [String]) { load(from: path) }

    static func load(from url: URL) -> (config: Config?, warnings: [String]) {
        var warnings: [String] = []
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? defaultFile.write(to: url, atomically: true, encoding: .utf8)
        }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return (nil, ["cannot read \(url.path)"])
        }
        let doc: TOMLDocument
        do { doc = try TOML.parse(text) } catch {
            return (nil, ["config parse error: \(error); keeping previous settings"])
        }

        var cfg = Config()
        if let value = doc.root["activation"] {
            if let v = value.string, KeySpec.parse(v) != nil { cfg.activation = v } else { warnings.append("bad activation") }
        }
        let known: Set<String> = ["activation", "chord_window_ms", "fade_ms", "columns", "rows", "edge", "size"]
        for key in doc.root.keys.sorted() where !known.contains(key) { warnings.append("unknown key \"\(key)\"") }
        for name in doc.tables.keys.sorted() { warnings.append("unknown table [\(name)]") }
        for name in doc.arrays.keys.sorted() where name != "command" { warnings.append("unknown table [[\(name)]]") }

        func int(_ key: String, _ range: ClosedRange<Int>, _ apply: (Int) -> Void) {
            guard let value = doc.root[key] else { return }
            if let v = value.int, range.contains(v) { apply(v) } else {
                warnings.append("\(key) must be an integer in \(range.lowerBound)...\(range.upperBound)")
            }
        }
        int("chord_window_ms", 0...10_000) { cfg.chordWindowMs = $0 }
        int("fade_ms", 0...10_000) { cfg.fadeMs = $0 }
        int("columns", 10...1000) { cfg.columns = $0 }
        int("rows", 3...500) { cfg.rows = $0 }
        if doc.root["size"] != nil { warnings.append("size is replaced by columns and rows") }
        if let value = doc.root["edge"] {
            if let v = value.string, let e = Edge(rawValue: v) { cfg.edge = e } else { warnings.append("bad edge") }
        }

        var seen = Set<String>()
        var seenHotkeys = Set<KeySpec>()
        if let activation = KeySpec.parse(cfg.activation) { seenHotkeys.insert(activation) }
        for (i, table) in (doc.arrays["command"] ?? []).enumerated() {
            for k in table.keys.sorted() where !["key", "run", "cwd", "hotkey"].contains(k) {
                warnings.append("[[command]] #\(i + 1): unknown key \"\(k)\"")
            }
            guard let run = table["run"]?.string, !run.isEmpty else {
                warnings.append("[[command]] #\(i + 1) needs a run")
                continue
            }
            var key: String?
            if let value = table["key"] {
                guard let k = value.string?.lowercased(), k.count == 1, KeySpec.keyCode(forName: k) != nil else {
                    warnings.append("[[command]] #\(i + 1): key must be one letter, digit or punctuation mark")
                    continue
                }
                key = k
            }
            var hotkey: String?
            if let value = table["hotkey"] {
                guard let h = value.string, KeySpec.parse(h) != nil else {
                    warnings.append("[[command]] #\(i + 1): bad hotkey")
                    continue
                }
                hotkey = h
            }
            guard key != nil || hotkey != nil else {
                warnings.append("[[command]] #\(i + 1) needs a key or a hotkey")
                continue
            }
            if let key, seen.contains(key) {
                warnings.append("duplicate command key \"\(key)\"")
                continue
            }
            let spec = hotkey.flatMap(KeySpec.parse)
            if let spec, seenHotkeys.contains(spec) {
                warnings.append("duplicate hotkey \"\(hotkey ?? "")\" (also the activation key or another command)")
                continue
            }
            // Only accepted commands claim their key and hotkey.
            if let key { seen.insert(key) }
            if let spec { seenHotkeys.insert(spec) }
            cfg.commands.append(CommandBinding(key: key, run: run, cwd: table["cwd"]?.string, hotkey: hotkey))
        }
        return (cfg, warnings)
    }

    static let defaultFile = """
    # TermLaunch config. Terminal appearance comes from your Ghostty config.

    # Global hotkey that shows/hides the Dropdown.
    activation = "ctrl+`"

    # After the Dropdown appears, a Command key pressed within this many ms
    # opens its command. Any other key ends the window and goes to the terminal.
    chord_window_ms = 300

    # Fade in/out duration in ms (0 = instant).
    fade_ms = 120

    # Terminal grid size of the Dropdown (limited to the visible screen area),
    # and the edge it hangs from ("top", "bottom", "left", "right").
    columns = 120
    rows = 30
    edge = "top"

    # Commands. Each runs in its own Tab through your login shell; the Tab
    # closes (and the Dropdown hides) on exit 0, otherwise it holds the output.
    # "key" is pressed right after the Activation key; "hotkey" is a global
    # shortcut (like activation, e.g. "f2" or "cmd+shift+g") that works from
    # anywhere. Set either or both.
    #
    # [[command]]
    # key = "g"
    # hotkey = "f2"
    # run = "lazygit"
    # cwd = "~/src"

    """
}
