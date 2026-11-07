import AppKit
import XCTest

/// Synthesised key events, as AppKit would deliver them.
private func key(_ chars: String, _ keyCode: UInt16, _ flags: NSEvent.ModifierFlags = [],
                 type: NSEvent.EventType = .keyDown) -> NSEvent {
    NSEvent.keyEvent(
        with: type, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0,
        context: nil, characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: keyCode)!
}

final class KeySpecMatchTests: XCTestCase {
    func testWindowHotkeyMatchesExactModifiers() {
        let spec = KeySpec.parse("cmd+enter")!
        XCTAssertTrue(spec.matches(key("\r", 36, .command)))
        XCTAssertFalse(spec.matches(key("\r", 36)))
        XCTAssertFalse(spec.matches(key("\r", 36, [.command, .shift])))
        XCTAssertFalse(spec.matches(key("\r", 36, [.command, .option])))
        XCTAssertFalse(spec.matches(key("a", 0, .command)))
    }

    func testFunctionAndCapsLockIgnored() {
        let f1 = KeySpec.parse("f1")!
        XCTAssertTrue(f1.matches(keyCode: 122, modifiers: .function))
        XCTAssertTrue(f1.matches(keyCode: 122, modifiers: [.function, .capsLock]))
        XCTAssertFalse(f1.matches(keyCode: 122, modifiers: [.function, .control]))
    }
}

final class LauncherKeyTests: XCTestCase {
    private let none = #selector(NSResponder.insertTab(_:))

    func testCtrlBindings() {
        let expected: [(String, UInt16, LauncherKey)] = [
            ("j", 38, .down), ("n", 45, .down), ("k", 40, .up), ("p", 35, .up),
            ("h", 4, .left), ("l", 37, .right), ("w", 13, .deleteWordBackward),
            ("u", 32, .deleteToLineStart), ("c", 8, .cancel),
        ]
        for (chars, code, result) in expected {
            XCTAssertEqual(LauncherKey.from(key(chars, code, .control), selector: none), result, "ctrl+\(chars)")
        }
    }

    /// Ctrl-K is Cocoa's deleteToEndOfLine; rush's binding must win.
    func testCtrlBindingBeatsCocoaSelector() {
        let event = key("k", 40, .control)
        XCTAssertEqual(LauncherKey.from(event, selector: #selector(NSResponder.deleteToEndOfLine(_:))), .up)
    }

    func testCtrlBindingsUsePhysicalKey() {
        // Ctrl + the key at US "j" position, whatever the layout types there.
        XCTAssertEqual(LauncherKey.from(key("о", 38, .control), selector: none), .down)
    }

    func testCtrlWithOtherModifiersFallsBackToSelector() {
        XCTAssertNil(LauncherKey.from(key("j", 38, [.control, .command]), selector: none))
        XCTAssertNil(LauncherKey.from(key("j", 38, [.control, .option]), selector: none))
        XCTAssertEqual(LauncherKey.from(key("j", 38, [.control, .shift]), selector: none), .down)
    }

    func testStandardSelectors() {
        XCTAssertEqual(LauncherKey.from(nil, selector: #selector(NSResponder.moveUp(_:))), .up)
        XCTAssertEqual(LauncherKey.from(nil, selector: #selector(NSResponder.moveDown(_:))), .down)
        XCTAssertEqual(LauncherKey.from(nil, selector: #selector(NSResponder.insertNewline(_:))), .run)
        XCTAssertEqual(LauncherKey.from(nil, selector: #selector(NSResponder.cancelOperation(_:))), .cancel)
        XCTAssertNil(LauncherKey.from(nil, selector: #selector(NSResponder.moveLeft(_:))))
    }

    func testUnboundCtrlKeyLeftToCocoa() {
        XCTAssertNil(LauncherKey.from(key("a", 0, .control), selector: #selector(NSResponder.moveToBeginningOfLine(_:))))
    }
}

final class EditKeyTests: XCTestCase {
    func testCommandEditKeys() {
        XCTAssertEqual(EditKey.from(key("c", 8, .command)), .copy)
        XCTAssertEqual(EditKey.from(key("v", 9, .command)), .paste)
        XCTAssertEqual(EditKey.from(key("x", 7, .command)), .cut)
        XCTAssertEqual(EditKey.from(key("a", 0, .command)), .selectAll)
        XCTAssertEqual(EditKey.from(key("z", 6, .command)), .undo)
        XCTAssertEqual(EditKey.from(key("z", 6, [.command, .shift])), .redo)
    }

    func testOtherCombinationsAreNotEditKeys() {
        XCTAssertNil(EditKey.from(key("c", 8)))
        XCTAssertNil(EditKey.from(key("c", 8, .control)))
        XCTAssertNil(EditKey.from(key("c", 8, [.command, .option])))
        XCTAssertNil(EditKey.from(key("t", 17, .command))) // left to the Tab shortcuts
    }
}

final class TerminalShortcutTests: XCTestCase {
    func testActions() {
        XCTAssertEqual(TerminalShortcut.action(for: key("c", 8, .command)), "copy_to_clipboard")
        XCTAssertEqual(TerminalShortcut.action(for: key("v", 9, .command)), "paste_from_clipboard")
        XCTAssertEqual(TerminalShortcut.action(for: key("a", 0, .command)), "select_all")
        XCTAssertEqual(TerminalShortcut.action(for: key("k", 40, .command)), "clear_screen")
        XCTAssertEqual(TerminalShortcut.action(for: key("0", 29, .command)), "reset_font_size")
    }

    func testFontSizeWithOrWithoutShift() {
        XCTAssertEqual(TerminalShortcut.action(for: key("=", 24, .command)), "increase_font_size:1")
        XCTAssertEqual(TerminalShortcut.action(for: key("+", 24, [.command, .shift])), "increase_font_size:1")
        XCTAssertEqual(TerminalShortcut.action(for: key("-", 27, .command)), "decrease_font_size:1")
    }

    func testNotShortcuts() {
        XCTAssertNil(TerminalShortcut.action(for: key("c", 8)))
        XCTAssertNil(TerminalShortcut.action(for: key("c", 8, [.command, .shift])))
        XCTAssertNil(TerminalShortcut.action(for: key("c", 8, [.command, .control])))
        XCTAssertNil(TerminalShortcut.action(for: key("c", 8, [.command, .option])))
        XCTAssertNil(TerminalShortcut.action(for: key("c", 8, .command, type: .keyUp)))
        XCTAssertNil(TerminalShortcut.action(for: key("t", 17, .command))) // a Tab shortcut
    }
}
