import XCTest

final class CalcTests: XCTestCase {
    func testFormat() {
        XCTAssertEqual(Calc.format(2), "2")
        XCTAssertEqual(Calc.format(1.5), "1.5")
        XCTAssertEqual(Calc.format(1.234567890), "1.23457")
        XCTAssertEqual(Calc.format(-0.0), "0")
        XCTAssertEqual(Calc.format(0.000001), "0")
        XCTAssertEqual(Calc.format(-1.5), "-1.5")
    }

    func testEval() throws {
        XCTAssertEqual(Calc.eval("2+3"), 5)
        XCTAssertEqual(Calc.eval("2+3*4"), 14)
        XCTAssertEqual(try XCTUnwrap(Calc.eval("sqrt(2)")), 2.0.squareRoot(), accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(Calc.eval("pi")), .pi, accuracy: 1e-9)
        XCTAssertEqual(Calc.eval("  2 + 3  "), 5)
        XCTAssertEqual(Calc.eval("(2+3)*4"), 20)
        XCTAssertEqual(Calc.eval("2^3^2"), 512)
        XCTAssertEqual(Calc.eval("-2^2"), -4)
        XCTAssertEqual(Calc.eval("2^-1"), 0.5)
        XCTAssertEqual(Calc.eval("7 % 3"), 1)
        XCTAssertEqual(Calc.eval(".5*2"), 1)
        XCTAssertEqual(Calc.eval("1e3"), 1000)
        XCTAssertEqual(Calc.eval("max(1, 5, 3)"), 5)
        XCTAssertEqual(Calc.eval("--2"), 2)
    }

    func testEvalFailures() {
        XCTAssertNil(Calc.eval("2+"))
        XCTAssertNil(Calc.eval("1/0"))
        XCTAssertNil(Calc.eval("(1"))
        XCTAssertNil(Calc.eval("2e"))
        XCTAssertNil(Calc.eval("1password"))
        XCTAssertNil(Calc.eval("nope(2)"))
        XCTAssertNil(Calc.eval("sqrt(1, 2)"))
        XCTAssertNil(Calc.eval(""))
    }

    func testIsCalcQuery() {
        for q in ["5", "5+3", "42*pi", ".5", "(2+3)*4", "  5+3"] { XCTAssertTrue(Calc.isCalcQuery(q), q) }
        for q in ["", "   ", "safari", "s5"] { XCTAssertFalse(Calc.isCalcQuery(q), q) }
    }

    func testProviderKeepsLastResultOnlyForPureNumbers() {
        var copied: [String] = []
        let p = CalcProvider { copied.append($0) }
        XCTAssertEqual(p.results(for: "safari").map(\.title), [])
        XCTAssertEqual(p.results(for: "2+3").map(\.title), ["= 5"])
        XCTAssertEqual(p.results(for: "2+3*").map(\.title), ["= 5"])
        XCTAssertEqual(p.results(for: "2+3*2").map(\.title), ["= 8"])
        p.results(for: "2+3*2").first?.run()
        XCTAssertEqual(copied, ["8"])

        XCTAssertEqual(p.results(for: "1").map(\.title), ["= 1"])
        XCTAssertEqual(p.results(for: "1p").map(\.title), [])
        XCTAssertEqual(p.results(for: "1password").map(\.title), [])
    }
}

final class FrecencyTests: XCTestCase {
    func testScores() {
        var store = FrecencyStore()
        XCTAssertEqual(store.score("/Applications/Unknown.app"), 0)
        store.add("/Applications/NewApp.app")
        XCTAssertEqual(store.score("/Applications/NewApp.app"), 1)
        store.scores["/Applications/Safari.app"] = 5
        store.add("/Applications/Safari.app")
        XCTAssertEqual(store.score("/Applications/Safari.app"), 6)
    }

    func testDecay() {
        let now = FrecencyStore.now()
        var store = FrecencyStore(scores: ["a": 100], lastUpdated: now - 86_400)
        store.applyDecay(now: now)
        XCTAssertEqual(store.score("a"), 90, accuracy: 0.001)
        XCTAssertEqual(store.lastUpdated, now)
        store.applyDecay(now: now)
        XCTAssertEqual(store.score("a"), 90, accuracy: 0.001)
    }

    /// The file rush's `oa` writes (serde: floats, snake_case) loads, and a saved store reloads.
    func testRushFileRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("frecency-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try #"{"scores": {"/Applications/Safari.app": 2.5, "/Applications/Xcode.app": 1}, "last_updated": 1760000000}"#
            .write(to: url, atomically: true, encoding: .utf8)
        var store = FrecencyStore.load(from: url)
        XCTAssertEqual(store.score("/Applications/Safari.app"), 2.5)
        XCTAssertEqual(store.lastUpdated, 1_760_000_000)
        store.record("/Applications/Xcode.app", to: url)
        XCTAssertEqual(FrecencyStore.load(from: url).score("/Applications/Xcode.app"), 2)
        XCTAssertEqual(FrecencyStore.load(from: url.appendingPathExtension("missing")), FrecencyStore())
    }
}

final class FuzzyScorerTests: XCTestCase {
    private func apps(_ names: [String]) -> [AppEntry] { names.map { AppEntry(path: "/Applications/\($0).app") } }

    func testAppEntryName() {
        XCTAssertEqual(AppEntry(path: "/Applications/Utilities/Terminal.app").name, "Terminal")
    }

    func testMatching() {
        XCTAssertNotNil(FuzzyScorer.score("xco", in: "Xcode"))
        XCTAssertNotNil(FuzzyScorer.score("sfr", in: "Safari"))
        XCTAssertNotNil(FuzzyScorer.score("aktivit", in: "Aktivitätsanzeige"))
        XCTAssertNotNil(FuzzyScorer.score("sys set", in: "System Settings"))
        XCTAssertNil(FuzzyScorer.score("xz", in: "Xcode"))
        XCTAssertNil(FuzzyScorer.score("sys zz", in: "System Settings"))
        XCTAssertNil(FuzzyScorer.score("safarii", in: "Safari"))
    }

    func testBoundariesBeatScatteredMatches() throws {
        // "vsc": word starts in "Visual Studio Code" vs. scattered letters in "Visscher".
        let boundary = try XCTUnwrap(FuzzyScorer.score("vsc", in: "Visual Studio Code"))
        let scattered = try XCTUnwrap(FuzzyScorer.score("vsc", in: "Visscher"))
        XCTAssertGreaterThan(boundary, scattered)
        let prefix = try XCTUnwrap(FuzzyScorer.score("term", in: "Terminal"))
        let inner = try XCTUnwrap(FuzzyScorer.score("term", in: "Determinator"))
        XCTAssertGreaterThan(prefix, inner)
    }

    func testEmptyQuerySortsByFrecency() {
        var store = FrecencyStore()
        store.add("/Applications/Xcode.app")
        store.add("/Applications/Xcode.app")
        store.add("/Applications/Terminal.app")
        let ranked = AppRanker.rank(apps(["Safari", "Xcode", "Terminal", "Books"]), query: "", frecency: store)
        XCTAssertEqual(ranked.map(\.name), ["Xcode", "Terminal", "Books", "Safari"])
    }

    func testQueryRanksBestMatchFirst() {
        let ranked = AppRanker.rank(apps(["Safari", "Xcode", "Terminal"]), query: "xco", frecency: FrecencyStore())
        XCTAssertEqual(ranked.map(\.name), ["Xcode"])
    }

    func testFrecencyBoostsFuzzyMatch() {
        var store = FrecencyStore()
        for _ in 0..<10 { store.add("/Applications/Safar2.app") }
        let ranked = AppRanker.rank(apps(["Safari", "Safar2"]), query: "saf", frecency: store)
        XCTAssertEqual(ranked.first?.name, "Safar2")
    }
}

final class LauncherModelTests: XCTestCase {
    private final class Fixed: LauncherProvider {
        let rows: [String: [String]]
        init(_ rows: [String: [String]]) { self.rows = rows }
        func results(for query: String) -> [LauncherItem] {
            (rows[query] ?? []).map { LauncherItem(title: $0) {} }
        }
    }

    func testProvidersInOrderAndSelection() {
        let model = LauncherModel(providers: [Fixed(["q": ["calc"]]), Fixed(["q": ["a", "b"], "x": ["c"]])])
        model.setQuery("q")
        XCTAssertEqual(model.items.map(\.title), ["calc", "a", "b"])
        XCTAssertEqual(model.selectedItem?.title, "calc")
        model.moveUp(); model.moveUp(); model.moveUp()
        XCTAssertEqual(model.selectedItem?.title, "b")
        model.moveDown()
        XCTAssertEqual(model.selectedItem?.title, "a")
        model.setQuery("x")
        XCTAssertEqual(model.items.map(\.title), ["c"])
        XCTAssertEqual(model.selected, 0)
        model.setQuery("none")
        XCTAssertNil(model.selectedItem)
        model.moveUp()
        XCTAssertEqual(model.selected, 0)
    }
}
