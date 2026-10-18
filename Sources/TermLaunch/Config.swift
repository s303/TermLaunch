import Foundation

struct CommandBinding: Equatable {
    /// Single key pressed during the chord window (lowercased).
    let key: String
    let run: String
    let cwd: String?
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
    static func load() -> (config: Config?, warnings: [String]) {
        var warnings: [String] = []
        let url = path
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
        if let v = doc.root["activation"]?.string {
            if KeySpec.parse(v) != nil { cfg.activation = v } else { warnings.append("bad activation \"\(v)\"") }
        }
        if let v = doc.root["chord_window_ms"]?.int, v >= 0 { cfg.chordWindowMs = v }
        if let v = doc.root["fade_ms"]?.int, v >= 0 { cfg.fadeMs = v }
        if let v = doc.root["columns"]?.int {
            if (10...1000).contains(v) { cfg.columns = v } else { warnings.append("columns must be 10...1000") }
        }
        if let v = doc.root["rows"]?.int {
            if (3...500).contains(v) { cfg.rows = v } else { warnings.append("rows must be 3...500") }
        }
        if doc.root["size"] != nil { warnings.append("size is replaced by columns and rows") }
        if let v = doc.root["edge"]?.string {
            if let e = Edge(rawValue: v) { cfg.edge = e } else { warnings.append("bad edge \"\(v)\"") }
        }

        var seen = Set<String>()
        for (i, table) in (doc.arrays["command"] ?? []).enumerated() {
            guard let key = table["key"]?.string?.lowercased(), key.count == 1,
                  KeySpec.keyCode(forName: key) != nil,
                  let run = table["run"]?.string, !run.isEmpty else {
                warnings.append("[[command]] #\(i + 1) needs a key (one letter, digit or punctuation mark) and a run")
                continue
            }
            guard seen.insert(key).inserted else {
                warnings.append("duplicate command key \"\(key)\"")
                continue
            }
            cfg.commands.append(CommandBinding(key: key, run: run, cwd: table["cwd"]?.string))
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

    # Command keys. Each runs in its own Tab through your login shell; the Tab
    # closes (and the Dropdown hides) on exit 0, otherwise it holds the output.
    #
    # [[command]]
    # key = "g"
    # run = "lazygit"
    # cwd = "~/src"

    """
}
