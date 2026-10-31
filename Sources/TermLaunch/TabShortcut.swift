import AppKit

/// Tab keyboard shortcuts shared by the Dropdown and Window mode.
enum TabShortcut {
    case new, close, next, previous, select(Int)

    /// kVK_ANSI_1 … kVK_ANSI_9, in digit order.
    private static let digitKeyCodes = [18, 19, 20, 21, 23, 22, 26, 28, 25]

    /// ⌘T new, ⌘W close, ⌘⇧[ / ⌘⇧] cycle, ⌘1–9 jump.
    static func from(_ event: NSEvent) -> TabShortcut? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command), !flags.contains(.control), !flags.contains(.option),
              let chars = event.charactersIgnoringModifiers else { return nil }
        let shift = flags.contains(.shift)
        // Digit keys by physical key code, so non-US layouts (digits behind shift) work.
        if !shift, let slot = digitKeyCodes.firstIndex(of: Int(event.keyCode)) { return .select(slot) }
        switch (chars, shift) {
        case ("t", false): return .new
        case ("w", false): return .close
        case ("[", _), ("{", _): return .previous
        case ("]", _), ("}", _): return .next
        default: return nil
        }
    }
}
