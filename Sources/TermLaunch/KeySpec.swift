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
        "return": 36, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43,
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
}
