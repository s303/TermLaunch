import AppKit

/// Keys in the Launcher Tab's search field. Pure, so the bindings are tested.
enum LauncherKey: Equatable {
    case down, up, left, right, deleteWordBackward, deleteToLineStart, run, cancel

    /// rush's Ctrl bindings first (several collide with Cocoa's emacs defaults, e.g.
    /// Ctrl-K, Ctrl-H, Ctrl-J), then the standard selectors. Ctrl keys match the
    /// physical key, like the chord, so they work in any keyboard layout.
    static func from(_ event: NSEvent?, selector: Selector) -> LauncherKey? {
        if let event, event.type == .keyDown,
           event.modifierFlags.intersection([.control, .command, .option]) == .control {
            switch KeySpec.name(forKeyCode: event.keyCode) {
            case "j", "n": return .down
            case "k", "p": return .up
            case "h": return .left
            case "l": return .right
            case "w": return .deleteWordBackward
            case "u": return .deleteToLineStart
            case "c": return .cancel
            default: break
            }
        }
        switch selector {
        case #selector(NSResponder.moveUp(_:)): return .up
        case #selector(NSResponder.moveDown(_:)): return .down
        case #selector(NSResponder.insertNewline(_:)): return .run
        case #selector(NSResponder.cancelOperation(_:)): return .cancel
        default: return nil
        }
    }
}

/// ⌘C/V/X/A/Z in the search field, handled by the field itself since the
/// Dropdown has no Edit menu to route them.
enum EditKey: Equatable {
    case copy, paste, cut, selectAll, undo, redo

    static func from(_ event: NSEvent) -> EditKey? {
        guard event.modifierFlags.intersection([.command, .control, .option]) == .command else { return nil }
        switch KeySpec.name(forKeyCode: event.keyCode) {
        case "c": return .copy
        case "v": return .paste
        case "x": return .cut
        case "a": return .selectAll
        case "z": return event.modifierFlags.contains(.shift) ? .redo : .undo
        default: return nil
        }
    }
}
