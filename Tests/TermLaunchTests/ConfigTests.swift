import XCTest

final class ConfigTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("termlaunch-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    private func load(_ text: String) throws -> (config: Config?, warnings: [String]) {
        let url = dir.appendingPathComponent("config.toml")
        try text.write(to: url, atomically: true, encoding: .utf8)
        return Config.load(from: url)
    }

    func testMissingFileWritesCleanDefault() {
        let url = dir.appendingPathComponent("sub/config.toml")
        let result = Config.load(from: url)
        XCTAssertEqual(result.config, Config())
        XCTAssertEqual(result.warnings, [])
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testGarbageYieldsNilConfigSoCallersKeepTheirs() throws {
        let result = try load("this is not toml")
        XCTAssertNil(result.config)
        XCTAssertEqual(result.warnings.count, 1)
    }

    func testValidValuesApply() throws {
        let result = try load("""
        activation = "cmd+space"
        chord_window_ms = 500
        fade_ms = 0
        columns = 80
        rows = 20
        edge = "bottom"
        """)
        XCTAssertEqual(result.warnings, [])
        let c = try XCTUnwrap(result.config)
        XCTAssertEqual(c.activation, "cmd+space")
        XCTAssertEqual(c.chordWindowMs, 500)
        XCTAssertEqual(c.fadeMs, 0)
        XCTAssertEqual(c.columns, 80)
        XCTAssertEqual(c.rows, 20)
        XCTAssertEqual(c.edge, .bottom)
    }

    func testBadValuesFallBackWithWarnings() throws {
        let result = try load("""
        activation = "a+b"
        columns = 5
        rows = "tall"
        fade_ms = -1
        chord_window_ms = 1e30
        edge = "middle"
        """)
        XCTAssertEqual(result.config, Config())
        XCTAssertEqual(result.warnings.count, 6)
    }

    func testUnknownKeysWarn() throws {
        let result = try load("chord_window = 1\n[extra]\nx = 1\n")
        XCTAssertEqual(result.config, Config())
        XCTAssertEqual(result.warnings.count, 2)
    }

    func testCommandBindings() throws {
        let result = try load("""
        [[command]]
        key = "G"
        run = "lazygit"
        cwd = "~/src"
        [[command]]
        key = "g"
        run = "dup"
        [[command]]
        key = "gg"
        run = "long"
        [[command]]
        key = "x"
        [[command]]
        key = "y"
        run = "ok"
        cmd = "typo"
        """)
        let c = try XCTUnwrap(result.config)
        XCTAssertEqual(c.commands, [
            CommandBinding(key: "g", run: "lazygit", cwd: "~/src"),
            CommandBinding(key: "y", run: "ok", cwd: nil),
        ])
        XCTAssertEqual(result.warnings.count, 4) // duplicate, multi-char key, missing run, unknown key
    }

    func testCommandHotkeys() throws {
        let result = try load("""
        activation = "ctrl+`"
        [[command]]
        hotkey = "F2"
        run = "o"
        [[command]]
        key = "g"
        hotkey = "cmd+shift+g"
        run = "lazygit"
        [[command]]
        hotkey = "f2"
        run = "dup"
        [[command]]
        hotkey = "ctrl+`"
        run = "clash"
        [[command]]
        hotkey = "bogus"
        run = "bad"
        [[command]]
        run = "nokeys"
        """)
        let c = try XCTUnwrap(result.config)
        XCTAssertEqual(c.commands, [
            CommandBinding(key: nil, run: "o", cwd: nil, hotkey: "F2"),
            CommandBinding(key: "g", run: "lazygit", cwd: nil, hotkey: "cmd+shift+g"),
        ])
        XCTAssertEqual(c.commands.map(\.id), ["hotkey:f2", "key:g"])
        XCTAssertEqual(result.warnings.count, 4)
    }

    func testRejectedCommandDoesNotClaimItsKey() throws {
        let result = try load("""
        [[command]]
        hotkey = "f2"
        run = "a"
        [[command]]
        key = "g"
        hotkey = "f2"
        run = "dup hotkey"
        [[command]]
        key = "g"
        run = "reuses key"
        [[command]]
        key = "h"
        hotkey = "h"
        run = "ids differ"
        """)
        let c = try XCTUnwrap(result.config)
        XCTAssertEqual(c.commands.map(\.run), ["a", "reuses key", "ids differ"])
        XCTAssertEqual(Set(c.commands.map(\.id)).count, 3)
        XCTAssertEqual(result.warnings.count, 1)
    }
}
