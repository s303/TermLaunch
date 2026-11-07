import AppKit
import Carbon.HIToolbox

/// A parsed hotkey such as "ctrl+`" or "cmd+shift+space".
struct KeySpec: Hashable {
    let keyCode: Int
    let modifiers: Int // Carbon flags

    private static let keys: [String: Int] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
        "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
        "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26,
        "-": 27, "8": 28, "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35,
        "return": 36, "enter": 36, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43,
        "/": 44, "n": 45, "m": 46, ".": 47, "tab": 48, "space": 49, "`": 50,
        "delete": 51, "escape": 53,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97,
        "f7": 98, "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111,
    ]

    static func keyCode(forName name: String) -> Int? { keys[name] }

    private static let namesByCode: [Int: String] = Dictionary(
        uniqueKeysWithValues: keys.filter { $0.key.count == 1 }.map { ($0.value, $0.key) })

    /// The single-character key name for a physical key, independent of the
    /// current keyboard layout (like the Activation key).
    static func name(forKeyCode code: UInt16) -> String? { namesByCode[Int(code)] }

    static func parse(_ text: String) -> KeySpec? {
        var mods = 0
        var key: Int?
        for part in text.lowercased().split(separator: "+", omittingEmptySubsequences: true) {
            switch part {
            case "ctrl", "control": mods |= controlKey
            case "alt", "opt", "option": mods |= optionKey
            case "cmd", "command", "super": mods |= cmdKey
            case "shift": mods |= shiftKey
            default:
                guard key == nil, let code = keys[String(part)] else { return nil }
                key = code
            }
        }
        guard let key else { return nil }
        return KeySpec(keyCode: key, modifiers: mods)
    }

    // MARK: Menu display

    private static let namesForDisplay: [Int: String] = Dictionary(
        keys.map { ($0.value, $0.key) }, uniquingKeysWith: { a, b in a.count >= b.count ? a : b })

    var nsModifiers: NSEvent.ModifierFlags {
        var m: NSEvent.ModifierFlags = []
        if modifiers & controlKey != 0 { m.insert(.control) }
        if modifiers & optionKey != 0 { m.insert(.option) }
        if modifiers & shiftKey != 0 { m.insert(.shift) }
        if modifiers & cmdKey != 0 { m.insert(.command) }
        return m
    }

    /// Whether a key event is this key with exactly these modifiers (fn and Caps Lock ignored).
    func matches(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Bool {
        Int(keyCode) == self.keyCode
            && modifiers.intersection([.command, .option, .control, .shift]) == nsModifiers
    }

    func matches(_ event: NSEvent) -> Bool { matches(keyCode: event.keyCode, modifiers: event.modifierFlags) }

    /// The `keyEquivalent` string an NSMenuItem needs for this key.
    var menuKeyEquivalent: String? {
        let fkeys: [Int: Int] = [
            122: NSF1FunctionKey, 120: NSF2FunctionKey, 99: NSF3FunctionKey, 118: NSF4FunctionKey,
            96: NSF5FunctionKey, 97: NSF6FunctionKey, 98: NSF7FunctionKey, 100: NSF8FunctionKey,
            101: NSF9FunctionKey, 109: NSF10FunctionKey, 103: NSF11FunctionKey, 111: NSF12FunctionKey,
        ]
        if let f = fkeys[keyCode], let scalar = UnicodeScalar(f) { return String(Character(scalar)) }
        switch keyCode {
        case 36: return "\r"
        case 48: return "\t"
        case 49: return " "
        case 51: return "\u{8}"
        case 53: return "\u{1b}"
        default: return Self.namesForDisplay[keyCode].flatMap { $0.count == 1 ? $0 : nil }
        }
    }

    /// Glyph form such as "⌃`" or "⌘⇧Space".
    var displayString: String {
        var s = ""
        if modifiers & controlKey != 0 { s += "⌃" }
        if modifiers & optionKey != 0 { s += "⌥" }
        if modifiers & shiftKey != 0 { s += "⇧" }
        if modifiers & cmdKey != 0 { s += "⌘" }
        let name = Self.namesForDisplay[keyCode] ?? "?"
        s += name.count == 1 ? name.uppercased() : name.capitalized
        return s
    }
}
