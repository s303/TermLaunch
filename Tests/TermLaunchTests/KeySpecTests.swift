import Carbon.HIToolbox
import XCTest

final class KeySpecTests: XCTestCase {
    func testParseModifiersAndKey() {
        XCTAssertEqual(KeySpec.parse("ctrl+`"), KeySpec(keyCode: 50, modifiers: controlKey))
        XCTAssertEqual(KeySpec.parse("Cmd+Shift+Space"), KeySpec(keyCode: 49, modifiers: cmdKey | shiftKey))
        XCTAssertEqual(KeySpec.parse("opt+f12")?.keyCode, 111)
    }

    func testEnterIsAnAliasForReturn() {
        XCTAssertEqual(KeySpec.parse("cmd+enter"), KeySpec.parse("cmd+return"))
        XCTAssertEqual(KeySpec.parse("cmd+enter")?.keyCode, 36)
    }

    func testParseRejectsInvalid() {
        XCTAssertNil(KeySpec.parse("a+b"))
        XCTAssertNil(KeySpec.parse("ctrl+"))
        XCTAssertNil(KeySpec.parse(""))
        XCTAssertNil(KeySpec.parse("ctrl+nope"))
    }

    func testKnownKeyCodes() {
        XCTAssertEqual(KeySpec.keyCode(forName: "5"), 23)
        XCTAssertEqual(KeySpec.keyCode(forName: "6"), 22)
        XCTAssertEqual(KeySpec.name(forKeyCode: 5), "g")
    }

    func testSingleCharacterNamesRoundTrip() {
        let singles = "abcdefghijklmnopqrstuvwxyz0123456789=-[]';\\,/.`"
        for ch in singles {
            let name = String(ch)
            let code = KeySpec.keyCode(forName: name)
            XCTAssertNotNil(code, name)
            XCTAssertEqual(KeySpec.name(forKeyCode: UInt16(code ?? -1)), name)
        }
    }
}
