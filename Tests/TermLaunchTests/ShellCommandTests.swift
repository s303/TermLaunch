import XCTest

final class ShellCommandTests: XCTestCase {
    private func exitCode(forRun run: String) throws -> String {
        let exitFile = NSTemporaryDirectory() + "termlaunch-test-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: exitFile) }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", ShellCommand.wrapper(run: run, exitFile: exitFile, shell: "/bin/sh")]
        try p.run()
        p.waitUntilExit()
        return try String(contentsOfFile: exitFile, encoding: .utf8)
    }

    func testQuoteEscapesSingleQuotes() {
        XCTAssertEqual(ShellCommand.quote("it's"), "'it'\\''s'")
    }

    func testExitCodeIsRecorded() throws {
        XCTAssertEqual(try exitCode(forRun: "exit 0"), "0")
        XCTAssertEqual(try exitCode(forRun: "exit 3"), "3")
    }

    func testQuotesInRunSurvive() throws {
        XCTAssertEqual(try exitCode(forRun: "test \"$(echo 'a b')\" = 'a b' && exit 7"), "7")
    }

    func testPathsWithSpacesAndDollar() throws {
        let tricky = NSTemporaryDirectory() + "term launch $x \(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: tricky) }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", ShellCommand.wrapper(run: "exit 2", exitFile: tricky, shell: "/bin/sh")]
        try p.run()
        p.waitUntilExit()
        XCTAssertEqual(try String(contentsOfFile: tricky, encoding: .utf8), "2")
    }
}
