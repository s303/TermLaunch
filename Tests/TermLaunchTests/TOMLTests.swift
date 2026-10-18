import XCTest

final class TOMLTests: XCTestCase {
    func testCommentsInsideQuotesAreKept() throws {
        let doc = try TOML.parse(#"run = "grep '#' x" # trailing"#)
        XCTAssertEqual(doc.root["run"], .string("grep '#' x"))
    }

    func testArrayOfTablesKeepsOrder() throws {
        let doc = try TOML.parse("[[command]]\nkey = \"a\"\n[[command]]\nkey = \"b\"\n")
        XCTAssertEqual(doc.arrays["command"]?.compactMap { $0["key"]?.string }, ["a", "b"])
    }

    func testScalarTypes() throws {
        let doc = try TOML.parse("a = 1_000\nb = 1.5\nc = true\nd = 'lit\\n'\ne = \"x\\ty\"")
        XCTAssertEqual(doc.root["a"], .int(1000))
        XCTAssertEqual(doc.root["b"], .double(1.5))
        XCTAssertEqual(doc.root["c"], .bool(true))
        XCTAssertEqual(doc.root["d"], .string("lit\\n"))
        XCTAssertEqual(doc.root["e"], .string("x\ty"))
    }

    func testCRLFLinesParse() throws {
        let doc = try TOML.parse("a = 5\r\nb = \"x\"\r\n")
        XCTAssertEqual(doc.root["a"]?.int, 5)
        XCTAssertEqual(doc.root["b"]?.string, "x")
    }

    func testErrorsThrow() {
        XCTAssertThrowsError(try TOML.parse(#"a = "\q""#))
        XCTAssertThrowsError(try TOML.parse(#"a = "open"#))
        XCTAssertThrowsError(try TOML.parse("no equals sign"))
        XCTAssertThrowsError(try TOML.parse("= 3"))
        XCTAssertThrowsError(try TOML.parse("[[bad]"))
    }

    func testIntCoercionNeverTraps() {
        XCTAssertEqual(TOMLValue.double(3).int, 3)
        XCTAssertNil(TOMLValue.double(3.5).int)
        XCTAssertNil(TOMLValue.double(1e30).int)
        XCTAssertNil(TOMLValue.double(.infinity).int)
        XCTAssertNil(TOMLValue.double(.nan).int)
    }

    func testHugeAndInfiniteConfigValuesParseWithoutCrash() throws {
        let doc = try TOML.parse("a = 1e30\nb = inf")
        XCTAssertNil(doc.root["a"]?.int)
        XCTAssertNil(doc.root["b"]?.int)
    }
}
