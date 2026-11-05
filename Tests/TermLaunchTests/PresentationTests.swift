import XCTest

final class PresentationTests: XCTestCase {
    private func state(window: Bool = false, console: Bool = false, key: Bool = false) -> Presentation.State {
        .init(windowMode: window, consoleShown: console, windowIsKey: key)
    }

    func testActivationInDropdownMode() {
        XCTAssertEqual(Presentation.activation(state()), .showConsole)
        XCTAssertEqual(Presentation.activation(state(console: true)), .hideConsole)
    }

    func testActivationInWindowMode() {
        XCTAssertEqual(Presentation.activation(state(window: true, key: true)), .windowChord)
        XCTAssertEqual(Presentation.activation(state(window: true)), .showConsole)
        XCTAssertEqual(Presentation.activation(state(window: true, console: true)), .hideConsole)
    }

    func testCommandHotkey() {
        XCTAssertEqual(Presentation.commandHotkey(state(), commandTabActive: false), .showConsole)
        XCTAssertEqual(Presentation.commandHotkey(state(console: true), commandTabActive: true), .hideConsole)
        XCTAssertEqual(Presentation.commandHotkey(state(console: true), commandTabActive: false), .showConsole)
        XCTAssertEqual(Presentation.commandHotkey(state(window: true, key: true), commandTabActive: true), .useWindow)
        XCTAssertEqual(Presentation.commandHotkey(state(window: true), commandTabActive: false), .showConsole)
        XCTAssertEqual(Presentation.commandHotkey(state(window: true, console: true), commandTabActive: true), .hideConsole)
    }

    func testWindowHotkeyToggles() {
        XCTAssertEqual(Presentation.windowHotkey(state(console: true)), .enterWindowMode)
        XCTAssertEqual(Presentation.windowHotkey(state(window: true, key: true)), .leaveWindowMode)
        XCTAssertEqual(Presentation.windowHotkey(state(window: true, console: true)), .leaveWindowMode)
    }

    func testWindowHotkeyIgnoredWhenNothingInFront() {
        XCTAssertEqual(Presentation.windowHotkey(state()), .ignore)
        XCTAssertEqual(Presentation.windowHotkey(state(window: true)), .ignore)
    }
}
