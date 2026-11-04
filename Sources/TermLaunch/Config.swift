import Foundation

/// A command that is built into TermLaunch rather than run through the shell.
enum Builtin: String {
    case launcher

    var title: String { "Launcher" }
}

struct CommandBinding: Equatable {
    enum Action: Equatable {
        case run(String)
        case builtin(Builtin)
    }

    /// Single key pressed during the chord window (lowercased).
    let key: String?
    let action: Action
    let cwd: String?
    /// Global hotkey (KeySpec syntax) that shows the Dropdown and opens this command.
    var hotkey: String? = nil
    /// Overrides the Commands menu label and pins the Tab title.
    var name: String? = nil

    init(key: String?, action: Action, cwd: String?, hotkey: String? = nil, name: String? = nil) {
        self.key = key
        self.action = action
        self.cwd = cwd
        self.hotkey = hotkey
        self.name = name
    }

    init(key: String?, run: String, cwd: String?, hotkey: String? = nil, name: String? = nil) {
        self.init(key: key, action: .run(run), cwd: cwd, hotkey: hotkey, name: name)
    }

    /// The shell command line, or nil for a builtin.
    var run: String? {
        if case .run(let run) = action { return run }
        return nil
    }

    /// Menu label and initial Tab title.
    var displayName: String {
        switch action {
        case .run(let run): return name ?? run
        case .builtin(let builtin): return name ?? builtin.title
        }
    }

    /// Identity of the Command Tab; at most one Tab exists per id.
    var id: String {
        if let key { return "key:" + key }
        if let hotkey { return "hotkey:" + hotkey.lowercased() }
        switch action {
        case .run(let run): return "run:" + run
        case .builtin(let builtin): return "builtin:" + builtin.rawValue
        }
    }
}

enum Edge: String {
    case top, bottom, left, right
}

/// A color from `[tabbar]`: literal `#rrggbb` or a slot of the Ghostty palette (`palette:N`).
enum ColorSpec: Equatable {
    case rgb(UInt8, UInt8, UInt8)
    case palette(Int)

    static func parse(_ text: String) -> ColorSpec? {
        if text.hasPrefix("palette:") {
            guard let n = Int(text.dropFirst(8)), (0...255).contains(n) else { return nil }
            return .palette(n)
        }
        guard text.hasPrefix("#"), text.count == 7, let v = UInt32(text.dropFirst(), radix: 16) else { return nil }
        return .rgb(UInt8(v >> 16 & 0xff), UInt8(v >> 8 & 0xff), UInt8(v & 0xff))
    }
}

/// Optional `[tabbar]` overrides; nil means derive from the Ghostty theme.
struct TabBarStyle: Equatable {
    var separator = "┊"
    var background: ColorSpec?
    var activeBackground: ColorSpec?
    var activeForeground: ColorSpec?
    var number: ColorSpec?
    var foreground: ColorSpec?

    static let colorKeys = ["background", "active_background", "active_foreground", "number", "foreground"]
}

/// App-level settings from ~/.config/termlaunch/config.toml. Terminal
/// appearance comes from the user's Ghostty config, not from here.
struct Config: Equatable {
    var activation = "ctrl+`"
    /// Global hotkey that toggles Window mode; nil leaves Window mode unreachable.
    var windowHotkey: String? = nil
    var chordWindowMs = 300
    var fadeMs = 120
    var columns = 120
    var rows = 30
    var edge = Edge.top
    var commands: [CommandBinding] = []
    var tabBar = TabBarStyle()

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
        let known: [String: Set<String>] = [
            "hotkeys": ["dropdown", "window"],
            "dropdown": ["edge", "columns", "rows", "fade_ms", "chord_timeout_ms"],
            "tabbar": Set(["separator"] + TabBarStyle.colorKeys),
        ]
        for key in doc.root.keys.sorted() { warnings.append("unknown key \"\(key)\" (keys belong in a table)") }
        for name in doc.tables.keys.sorted() where known[name] == nil { warnings.append("unknown table [\(name)]") }
        for name in doc.arrays.keys.sorted() where name != "command" { warnings.append("unknown table [[\(name)]]") }
        for (name, keys) in known.sorted(by: { $0.key < $1.key }) {
            for k in (doc.tables[name] ?? [:]).keys.sorted() where !keys.contains(k) {
                warnings.append("[\(name)]: unknown key \"\(k)\"")
            }
        }

        let hotkeys = doc.tables["hotkeys"] ?? [:]
        if let value = hotkeys["dropdown"] {
            if let v = value.string, KeySpec.parse(v) != nil { cfg.activation = v } else { warnings.append("[hotkeys]: bad dropdown") }
        }
        var windowSpec: KeySpec?
        if let value = hotkeys["window"] {
            if let v = value.string, let spec = KeySpec.parse(v) {
                if spec == KeySpec.parse(cfg.activation) {
                    warnings.append("[hotkeys]: window duplicates dropdown")
                } else {
                    cfg.windowHotkey = v
                    windowSpec = spec
                }
            } else { warnings.append("[hotkeys]: bad window") }
        }

        if let table = doc.tables["tabbar"] {
            if let value = table["separator"] {
                if let v = value.string { cfg.tabBar.separator = v } else { warnings.append("[tabbar]: separator must be a string") }
            }
            for k in TabBarStyle.colorKeys {
                guard let value = table[k] else { continue }
                guard let v = value.string, let spec = ColorSpec.parse(v) else {
                    warnings.append("[tabbar]: \(k) must be \"#rrggbb\" or \"palette:N\"")
                    continue
                }
                switch k {
                case "background": cfg.tabBar.background = spec
                case "active_background": cfg.tabBar.activeBackground = spec
                case "active_foreground": cfg.tabBar.activeForeground = spec
                case "number": cfg.tabBar.number = spec
                default: cfg.tabBar.foreground = spec
                }
            }
        }

        let dropdown = doc.tables["dropdown"] ?? [:]
        func int(_ key: String, _ range: ClosedRange<Int>, _ apply: (Int) -> Void) {
            guard let value = dropdown[key] else { return }
            if let v = value.int, range.contains(v) { apply(v) } else {
                warnings.append("[dropdown]: \(key) must be an integer in \(range.lowerBound)...\(range.upperBound)")
            }
        }
        int("chord_timeout_ms", 0...10_000) { cfg.chordWindowMs = $0 }
        int("fade_ms", 0...10_000) { cfg.fadeMs = $0 }
        int("columns", 10...1000) { cfg.columns = $0 }
        int("rows", 3...500) { cfg.rows = $0 }
        if let value = dropdown["edge"] {
            if let v = value.string, let e = Edge(rawValue: v) { cfg.edge = e } else { warnings.append("[dropdown]: bad edge") }
        }

        var seen = Set<String>()
        var seenHotkeys = Set<KeySpec>()
        if let activation = KeySpec.parse(cfg.activation) { seenHotkeys.insert(activation) }
        if let windowSpec { seenHotkeys.insert(windowSpec) }
        for (i, table) in (doc.arrays["command"] ?? []).enumerated() {
            for k in table.keys.sorted() where !["chord", "run", "builtin", "cwd", "hotkey", "name"].contains(k) {
                warnings.append("[[command]] #\(i + 1): unknown key \"\(k)\"")
            }
            let action: CommandBinding.Action
            switch (table["run"], table["builtin"]) {
            case (let run?, nil):
                guard let run = run.string, !run.isEmpty else {
                    warnings.append("[[command]] #\(i + 1): run must be a non-empty string")
                    continue
                }
                action = .run(run)
            case (nil, let builtin?):
                guard let builtin = builtin.string.flatMap(Builtin.init(rawValue:)) else {
                    warnings.append("[[command]] #\(i + 1): builtin must be \"launcher\"")
                    continue
                }
                action = .builtin(builtin)
            case (_?, _?):
                warnings.append("[[command]] #\(i + 1) has both run and builtin")
                continue
            case (nil, nil):
                warnings.append("[[command]] #\(i + 1) needs a run or a builtin")
                continue
            }
            var key: String?
            if let value = table["chord"] {
                guard let k = value.string?.lowercased(), k.count == 1, KeySpec.keyCode(forName: k) != nil else {
                    warnings.append("[[command]] #\(i + 1): chord must be one letter, digit or punctuation mark")
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
                warnings.append("[[command]] #\(i + 1) needs a chord or a hotkey")
                continue
            }
            if let key, seen.contains(key) {
                warnings.append("duplicate command chord \"\(key)\"")
                continue
            }
            let spec = hotkey.flatMap(KeySpec.parse)
            if let spec, seenHotkeys.contains(spec) {
                warnings.append("duplicate hotkey \"\(hotkey ?? "")\" (also the activation key, the window hotkey or another command)")
                continue
            }
            var name: String?
            if let value = table["name"] {
                guard let n = value.string, !n.isEmpty else {
                    warnings.append("[[command]] #\(i + 1): name must be a non-empty string")
                    continue
                }
                name = n
            }
            // Only accepted commands claim their key and hotkey.
            if let key { seen.insert(key) }
            if let spec { seenHotkeys.insert(spec) }
            cfg.commands.append(CommandBinding(key: key, action: action, cwd: table["cwd"]?.string, hotkey: hotkey, name: name))
        }
        return (cfg, warnings)
    }

    static let defaultFile = """
    # TermLaunch config. Terminal appearance comes from your Ghostty config.

    [hotkeys]
    # Global hotkey that shows/hides the Dropdown.
    dropdown = "ctrl+`"
    # Optional global hotkey that toggles between the Dropdown and a normal
    # window with the same Tabs (e.g. "cmd+shift+space"). Unset = no window mode.
    # window = "cmd+shift+space"

    [dropdown]
    # Terminal grid size (limited to the visible screen area) and the edge it
    # hangs from ("top", "bottom", "left", "right").
    columns = 120
    rows = 30
    edge = "top"
    # Fade in/out duration in ms (0 = instant).
    fade_ms = 120
    # After the Dropdown appears, a command chord pressed within this many ms
    # opens its command. Any other key ends the window and goes to the terminal.
    chord_timeout_ms = 300

    # Tab bar. Colors and font come from your Ghostty theme; every key here is
    # optional. Colors are "#rrggbb" or "palette:N" (a Ghostty palette slot).
    # [tabbar]
    # separator = "┊"
    # background = "palette:0"
    # active_background = "palette:5"
    # active_foreground = "#1e1e2e"
    # number = "palette:2"
    # foreground = "#cdd6f4"

    # Commands. Each runs in its own Tab through your login shell; the Tab
    # closes (and the Dropdown hides) on exit 0, otherwise it holds the output.
    # "chord" is pressed right after the dropdown hotkey; "hotkey" is a global
    # shortcut (like the dropdown one, e.g. "f2" or "cmd+shift+g") that works
    # from anywhere. Set either or both.
    #
    # [[command]]
    # chord = "g"
    # hotkey = "f2"
    # run = "lazygit"
    # cwd = "~/src"
    # name = "Git"   # optional label for the Commands menu and the Tab title
    #
    # builtin = "launcher" in place of run opens the built-in app launcher and
    # calculator: Enter opens the app or copies the result, Esc closes it.
    #
    # [[command]]
    # chord = "o"
    # builtin = "launcher"

    """
}
