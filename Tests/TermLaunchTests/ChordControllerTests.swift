import AppKit
import XCTest

@MainActor
final class ChordControllerTests: XCTestCase {
    private let y: UInt16 = 16
    private let x: UInt16 = 7
    private var fires: [() -> Void] = []
    private var cancelled = 0

    private func make(activation: String? = nil) -> ChordController {
        let c = ChordController { [unowned self] _, fire in
            self.fires.append(fire)
            return { self.cancelled += 1 }
        }
        c.apply(commandKeys: ["y"], activationKey: activation.flatMap(KeySpec.parse), chordWindow: 0.3)
        return c
    }

    func testCommandKeyRunsThenKeyUpSwallowed() {
        let c = make()
        c.begin()
        XCTAssertEqual(c.handle(type: .keyDown, keyCode: y, modifiers: []), .command("y"))
        XCTAssertFalse(c.isActive)
        XCTAssertEqual(c.handle(type: .keyDown, keyCode: y, modifiers: []), .swallow)
        XCTAssertEqual(c.handle(type: .keyUp, keyCode: y, modifiers: []), .swallow)
        XCTAssertEqual(c.handle(type: .keyUp, keyCode: y, modifiers: []), .pass)
    }

    func testLostKeyUpAfterResetDoesNotEatNextPress() {
        let c = make()
        c.begin()
        XCTAssertEqual(c.handle(type: .keyDown, keyCode: y, modifiers: []), .command("y"))
        c.reset() // window resigned key; keyUp never arrives
        XCTAssertEqual(c.handle(type: .keyDown, keyCode: y, modifiers: []), .pass)
        XCTAssertEqual(c.handle(type: .keyUp, keyCode: y, modifiers: []), .pass)
    }

    func testLostKeyUpWithoutResetEatsNextPress() {
        let c = make()
        c.begin()
        _ = c.handle(type: .keyDown, keyCode: y, modifiers: [])
        XCTAssertEqual(c.handle(type: .keyDown, keyCode: y, modifiers: []), .swallow)
    }

    func testBeginCancelsPriorTimer() {
        let c = make()
        c.begin()
        c.begin()
        XCTAssertEqual(cancelled, 1)
        XCTAssertTrue(c.isActive)
    }

    func testTimerFiringEndsWindow() {
        let c = make()
        c.begin()
        fires.last?()
        XCTAssertFalse(c.isActive)
        XCTAssertEqual(c.handle(type: .keyDown, keyCode: y, modifiers: []), .pass)
    }

    func testOtherKeyEndsWindowAndCancelsTimer() {
        let c = make()
        c.begin()
        XCTAssertEqual(c.handle(type: .keyDown, keyCode: x, modifiers: []), .pass)
        XCTAssertEqual(cancelled, 1)
        XCTAssertFalse(c.isActive)
    }

    func testActivationKeyDownSwallowedWithoutEndingWindow() {
        let c = make(activation: "f1")
        c.begin()
        XCTAssertEqual(c.handle(type: .keyDown, keyCode: 122, modifiers: []), .swallow)
        XCTAssertTrue(c.isActive)
    }

    /// Reading `keyCode` off a mouse event raises; the window's sendEvent would drop it
    /// (no edge-drag resize, no clicks).
    func testMouseEventPassesWithoutTouchingWindow() throws {
        let c = make()
        c.begin()
        let mouse = try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        XCTAssertEqual(c.handle(mouse), .pass)
        XCTAssertTrue(c.isActive)
    }

    func testNoWindowWithoutCommandKeysOrDuration() {
        let c = make()
        c.apply(commandKeys: [], activationKey: nil, chordWindow: 0.3)
        c.begin()
        XCTAssertFalse(c.isActive)
        c.apply(commandKeys: ["y"], activationKey: nil, chordWindow: 0)
        c.begin()
        XCTAssertFalse(c.isActive)
    }
}
