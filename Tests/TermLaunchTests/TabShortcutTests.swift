import AppKit
import XCTest
@testable import TermLaunch

final class TabShortcutTests: XCTestCase {
    private func shortcut(_ chars: String, keyCode: UInt16, _ flags: NSEvent.ModifierFlags) -> TabShortcut? {
        let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0,
            context: nil, characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: keyCode)!
        return TabShortcut.from(event)
    }

    func testNewAndClose() {
        guard case .new? = shortcut("t", keyCode: 17, .command) else { return XCTFail("⌘T") }
        guard case .close? = shortcut("w", keyCode: 13, .command) else { return XCTFail("⌘W") }
    }

    func testCycle() {
        guard case .previous? = shortcut("[", keyCode: 33, [.command, .shift]) else { return XCTFail("⌘⇧[") }
        guard case .next? = shortcut("]", keyCode: 30, [.command, .shift]) else { return XCTFail("⌘⇧]") }
    }

    func testDigitsSelectByKeyCode() {
        let codes: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25]
        for (slot, code) in codes.enumerated() {
            guard case .select(let i)? = shortcut(String(slot + 1), keyCode: code, .command) else {
                return XCTFail("⌘\(slot + 1)")
            }
            XCTAssertEqual(i, slot)
        }
    }

    func testOtherCombinationsAreNotShortcuts() {
        XCTAssertNil(shortcut("t", keyCode: 17, []))
        XCTAssertNil(shortcut("t", keyCode: 17, [.command, .control]))
        XCTAssertNil(shortcut("t", keyCode: 17, [.command, .option]))
        XCTAssertNil(shortcut("c", keyCode: 8, .command))
    }
}
