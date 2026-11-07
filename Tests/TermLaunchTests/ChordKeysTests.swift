import AppKit
import XCTest

final class ChordKeysTests: XCTestCase {
    private let f1: UInt16 = 122
    private let y: UInt16 = 16
    private let x: UInt16 = 7

    private func chord(activation: String? = nil) -> ChordKeys {
        var c = ChordKeys()
        c.commandKeys = ["y", "t"]
        c.activationKey = activation.flatMap(KeySpec.parse)
        return c
    }

    func testCommandKeyInChordWindowRunsCommand() {
        var c = chord()
        XCTAssertTrue(c.begin())
        XCTAssertEqual(c.keyDown(keyCode: y, modifiers: []), .command("y"))
        XCTAssertFalse(c.isActive)
    }

    func testKeysOutsideChordWindowPass() {
        var c = chord()
        XCTAssertEqual(c.keyDown(keyCode: y, modifiers: []), .pass)
    }

    func testOtherKeyEndsChordWindowAndPasses() {
        var c = chord()
        _ = c.begin()
        XCTAssertEqual(c.keyDown(keyCode: x, modifiers: []), .pass)
        XCTAssertEqual(c.keyDown(keyCode: y, modifiers: []), .pass)
    }

    func testBlockingModifierPassesCommandKey() {
        var c = chord()
        _ = c.begin()
        XCTAssertEqual(c.keyDown(keyCode: y, modifiers: .command), .pass)
    }

    func testShiftDoesNotBlockCommandKey() {
        var c = chord()
        _ = c.begin()
        XCTAssertEqual(c.keyDown(keyCode: y, modifiers: .shift), .command("y"))
    }

    func testNoCommandKeysNoChordWindow() {
        var c = ChordKeys()
        XCTAssertFalse(c.begin())
    }

    func testCommandKeyRepeatAndKeyUpSwallowed() {
        var c = chord()
        _ = c.begin()
        _ = c.keyDown(keyCode: y, modifiers: [])
        XCTAssertEqual(c.keyDown(keyCode: y, modifiers: []), .swallow) // auto-repeat
        XCTAssertEqual(c.keyUp(keyCode: y), .swallow)
        XCTAssertEqual(c.keyUp(keyCode: y), .pass)
        XCTAssertEqual(c.keyDown(keyCode: y, modifiers: []), .pass)
    }

    func testResetForgetsHeldKeys() {
        var c = chord()
        _ = c.begin()
        _ = c.keyDown(keyCode: y, modifiers: [])
        c.reset()
        XCTAssertEqual(c.keyDown(keyCode: y, modifiers: []), .pass)
    }

    /// Window mode: the app is active, so the Activation key's own keyDown reaches the
    /// Window after the hotkey started the Chord window. It must not end it.
    func testActivationKeyDoesNotEndChordWindow() {
        var c = chord(activation: "f1")
        _ = c.begin()
        XCTAssertEqual(c.keyDown(keyCode: f1, modifiers: .function), .swallow)
        XCTAssertTrue(c.isActive)
        XCTAssertEqual(c.keyDown(keyCode: y, modifiers: []), .command("y"))
    }

    func testActivationKeyWithOtherModifiersIsNotActivation() {
        var c = chord(activation: "f1")
        _ = c.begin()
        XCTAssertEqual(c.keyDown(keyCode: f1, modifiers: [.function, .shift]), .pass)
        XCTAssertFalse(c.isActive)
    }
}
