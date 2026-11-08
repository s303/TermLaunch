import AppKit
import Carbon.HIToolbox

/// ⌘ shortcuts a terminal Tab handles itself, as libghostty binding action names.
enum TerminalShortcut {
    static func action(for event: NSEvent) -> String? {
        guard event.type == .keyDown else { return nil }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command), !flags.contains(.control), !flags.contains(.option),
              let key = event.charactersIgnoringModifiers?.lowercased() else { return nil }
        switch (key, flags.contains(.shift)) {
        case ("c", false): return "copy_to_clipboard"
        case ("v", false): return "paste_from_clipboard"
        case ("a", false): return "select_all"
        case ("k", false): return "clear_screen"
        case ("=", _), ("+", _): return "increase_font_size:1"
        case ("-", _): return "decrease_font_size:1"
        case ("0", false): return "reset_font_size"
        default: return nil
        }
    }

    /// Page Up / Page Down (fn+↑ / fn+↓ on a Mac keyboard) page the scrollback, like
    /// Terminal.app. With shift they go to the program (less, vim) as usual.
    static func scrollAction(for event: NSEvent) -> String? {
        guard event.type == .keyDown || event.type == .keyUp else { return nil }
        let flags = event.modifierFlags.intersection([.shift, .control, .option, .command])
        guard flags.isEmpty else { return nil }
        switch Int(event.keyCode) {
        case kVK_PageUp: return "scroll_page_up"
        case kVK_PageDown: return "scroll_page_down"
        default: return nil
        }
    }
}
