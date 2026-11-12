import XCTest

/// Answers rate fetches from a script, recording the ETag of each request.
private actor FakeServer {
    private var responses: [Result<RateStore.FetchResult, Error>]
    private(set) var etags: [String?] = []

    init(_ responses: [Result<RateStore.FetchResult, Error>]) { self.responses = responses }

    func respond(_ etag: String?) throws -> RateStore.FetchResult {
        etags.append(etag)
        guard !responses.isEmpty else { throw URLError(.notConnectedToInternet) }
        return try responses.removeFirst().get()
    }
}

private final class Clock {
    var date = Date(timeIntervalSince1970: 1_800_000_000)
    func advance(_ seconds: TimeInterval) { date += seconds }
}

/// 1 EUR = 1.25 USD = 100 RUB = 160 JPY = 0.00001 BTC.
private let table = Data("""
[{"date":"2026-11-12","base":"EUR","quote":"USD","rate":1.25},
 {"date":"2026-11-12","base":"EUR","quote":"RUB","rate":100},
 {"date":"2026-11-12","base":"EUR","quote":"JPY","rate":160},
 {"date":"2026-11-11","base":"EUR","quote":"BTC","rate":0.00001}]
""".utf8)

final class ConversionQueryTests: XCTestCase {
    func testParse() {
        XCTAssertEqual(ConversionQuery.parse("100 usd to eur"), ConversionQuery(amount: 100, from: "USD", to: "EUR"))
        XCTAssertEqual(ConversionQuery.parse("(20+5)*4 USD in Rub"), ConversionQuery(amount: 100, from: "USD", to: "RUB"))
        XCTAssertEqual(ConversionQuery.parse("100usd eur"), ConversionQuery(amount: 100, from: "USD", to: "EUR"))
        XCTAssertEqual(ConversionQuery.parse(" 2.5 btc "), ConversionQuery(amount: 2.5, from: "BTC", to: nil))
        XCTAssertEqual(ConversionQuery.parse("100usd"), ConversionQuery(amount: 100, from: "USD", to: nil))
        XCTAssertEqual(ConversionQuery.parse("1e3 jpy"), ConversionQuery(amount: 1000, from: "JPY", to: nil))
        // Incomplete targets: the provider falls back to the defaults.
        XCTAssertEqual(ConversionQuery.parse("100 usd to"), ConversionQuery(amount: 100, from: "USD", to: "TO"))
        XCTAssertEqual(ConversionQuery.parse("100 usd to e"), ConversionQuery(amount: 100, from: "USD", to: "E"))
    }

    func testNotConversions() {
        for q in ["", "100", "usd", "usd eur", "2+2", "safari", "100 usd + 20 eur", "$100", "usd 100", "100 to eur usd x1"] {
            XCTAssertNil(ConversionQuery.parse(q), q)
        }
    }
}

final class CurrencyFormatTests: XCTestCase {
    func testPlain() {
        XCTAssertEqual(CurrencyFormat.plain(92.3077), "92.31")
        XCTAssertEqual(CurrencyFormat.plain(1), "1.00")
        XCTAssertEqual(CurrencyFormat.plain(0), "0.00")
        XCTAssertEqual(CurrencyFormat.plain(0.5), "0.50")
        XCTAssertEqual(CurrencyFormat.plain(0.012346), "0.01235")
        XCTAssertEqual(CurrencyFormat.plain(1.5006e-5), "0.00001501")
        XCTAssertEqual(CurrencyFormat.plain(0.9999999), "1.00")
        XCTAssertEqual(CurrencyFormat.plain(-1234.5), "-1234.50")
        XCTAssertEqual(CurrencyFormat.plain(-0.0000000001), "-0.0000000001")
    }

    func testDisplayGroups() {
        XCTAssertEqual(CurrencyFormat.display(1_234_567.891), "1,234,567.89")
        XCTAssertEqual(CurrencyFormat.display(999.999), "1,000.00")
        XCTAssertEqual(CurrencyFormat.display(-1234.5), "-1,234.50")
        XCTAssertEqual(CurrencyFormat.display(123), "123.00")
        XCTAssertEqual(CurrencyFormat.group("1000000"), "1,000,000")
    }

    func testAge() {
        XCTAssertNil(CurrencyFormat.age(nil))
        XCTAssertNil(CurrencyFormat.age(2 * 86400))
        XCTAssertEqual(CurrencyFormat.age(3.5 * 86400), "rates 3d old")
    }
}

@MainActor
final class RateStoreTests: XCTestCase {
    private var dir: URL!
    private var clock: Clock!

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("termlaunch-rates-\(UUID().uuidString)")
        clock = Clock()
    }

    override func tearDown() async throws { try? FileManager.default.removeItem(at: dir) }

    private func makeStore(_ server: FakeServer) -> RateStore {
        let clock = self.clock!
        return RateStore(fetch: { try await server.respond($0) }, now: { clock.date },
                         cacheURL: dir.appendingPathComponent("rates.json"))
    }

    func testCrossRatesThroughEUR() async throws {
        let store = makeStore(FakeServer([.success(.ok(table, etag: "\"v1\""))]))
        await store.requestRefreshIfStale()?.value
        XCTAssertTrue(store.hasTable)
        XCTAssertEqual(try XCTUnwrap(store.rate(from: "USD", to: "RUB")), 80, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(store.rate(from: "eur", to: "usd")), 1.25, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(store.rate(from: "USD", to: "EUR")), 0.8, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(store.rate(from: "EUR", to: "EUR")), 1)
        XCTAssertNil(store.rate(from: "USD", to: "XYZ"))
        XCTAssertTrue(store.knows(code: "btc"))
        XCTAssertFalse(store.knows(code: "XYZ"))
    }

    func testOneFetchInFlightAndPostsChange() async throws {
        let server = FakeServer([.success(.ok(table, etag: nil))])
        let store = makeStore(server)
        XCTAssertFalse(store.hasTable)
        let changed = expectation(forNotification: RateStore.didChange, object: store)
        let first = try XCTUnwrap(store.requestRefreshIfStale())
        XCTAssertTrue(store.isFetching)
        XCTAssertEqual(store.requestRefreshIfStale(), first)
        await first.value
        await fulfillment(of: [changed], timeout: 1)
        XCTAssertFalse(store.isFetching)
        let etags = await server.etags
        XCTAssertEqual(etags.count, 1)
    }

    func testFreshForSixHoursThenRevalidatesWithETag() async throws {
        let server = FakeServer([.success(.ok(table, etag: "\"v1\"")), .success(.notModified)])
        let store = makeStore(server)
        await store.requestRefreshIfStale()?.value
        let fetched = clock.date
        clock.advance(6 * 3600 - 1)
        XCTAssertNil(store.requestRefreshIfStale())
        clock.advance(1)
        await store.requestRefreshIfStale()?.value
        let etags = await server.etags
        XCTAssertEqual(etags, [nil, "\"v1\""])
        // A 304 keeps the table and only moves the fetch time.
        XCTAssertNotEqual(store.fetchedAt, fetched)
        XCTAssertEqual(store.fetchedAt, clock.date)
        XCTAssertEqual(store.tableAge, 0)
        XCTAssertEqual(try XCTUnwrap(store.rate(from: "USD", to: "RUB")), 80, accuracy: 1e-9)
    }

    func testWaitsAMinuteAfterFailure() async throws {
        let server = FakeServer([.failure(URLError(.timedOut)), .success(.ok(Data("nope".utf8), etag: nil)),
                                 .success(.ok(table, etag: nil))])
        let store = makeStore(server)
        await store.requestRefreshIfStale()?.value
        XCTAssertFalse(store.hasTable)
        XCTAssertEqual(store.lastFailure, clock.date)
        clock.advance(59)
        XCTAssertNil(store.requestRefreshIfStale())
        clock.advance(1)
        // An unparseable body counts as a failure too.
        await store.requestRefreshIfStale()?.value
        XCTAssertFalse(store.hasTable)
        XCTAssertNil(store.requestRefreshIfStale())
        clock.advance(60)
        await store.requestRefreshIfStale()?.value
        XCTAssertTrue(store.hasTable)
        XCTAssertNil(store.lastFailure)
    }

    func testStaleTableSurvivesFailure() async throws {
        let store = makeStore(FakeServer([.success(.ok(table, etag: nil)), .failure(URLError(.timedOut))]))
        await store.requestRefreshIfStale()?.value
        clock.advance(7 * 3600)
        await store.requestRefreshIfStale()?.value
        XCTAssertNotNil(store.lastFailure)
        XCTAssertTrue(store.hasTable)
        XCTAssertEqual(store.tableAge, 7 * 3600)
    }

    func testCacheOnDisk() async throws {
        let server = FakeServer([.success(.ok(table, etag: "\"v1\""))])
        let first = makeStore(server)
        await first.requestRefreshIfStale()?.value
        clock.advance(3600)

        let second = FakeServer([.success(.notModified)])
        let store = makeStore(second)
        XCTAssertTrue(store.hasTable)
        XCTAssertEqual(store.tableAge, 3600)
        XCTAssertNil(store.requestRefreshIfStale())
        clock.advance(5 * 3600)
        await store.requestRefreshIfStale()?.value
        let etags = await second.etags
        XCTAssertEqual(etags, ["\"v1\""])
        XCTAssertNil(store.lastFailure)
    }
}

@MainActor
final class CurrencyProviderTests: XCTestCase {
    private var dir: URL!
    private var clock: Clock!
    private var settings = CurrencySettings()
    private var copied: [String] = []

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("termlaunch-rates-\(UUID().uuidString)")
        clock = Clock()
        settings = CurrencySettings()
        copied = []
    }

    override func tearDown() async throws { try? FileManager.default.removeItem(at: dir) }

    private func make(_ responses: [Result<RateStore.FetchResult, Error>], loaded: Bool = true) async -> (RateStore, CurrencyProvider) {
        let clock = self.clock!
        let server = FakeServer(responses)
        let store = RateStore(fetch: { try await server.respond($0) }, now: { clock.date },
                              cacheURL: dir.appendingPathComponent("rates.json"))
        if loaded { await store.requestRefreshIfStale()?.value }
        let provider = CurrencyProvider(store: store, settings: { [unowned self] in self.settings },
                                        copy: { [unowned self] in self.copied.append($0) })
        return (store, provider)
    }

    private func rows(_ provider: CurrencyProvider, _ query: String) -> [String] {
        provider.results(for: query).map { $0.title + " | " + ($0.hint ?? "") }
    }

    func testConversionRows() async {
        let (_, provider) = await make([.success(.ok(table, etag: nil))])
        XCTAssertEqual(rows(provider, "100 usd to eur"), ["80.00 EUR | 100 USD · ⏎ copy"])
        XCTAssertEqual(rows(provider, "100usd in RUB"), ["8,000.00 RUB | 100 USD · ⏎ copy"])
        XCTAssertEqual(rows(provider, "1000000 jpy usd"), ["7,812.50 USD | 1,000,000 JPY · ⏎ copy"])
        XCTAssertEqual(rows(provider, "1 rub to btc"), ["0.0000001 BTC | 1 RUB · ⏎ copy"])
        // Bare and incomplete targets show the defaults, leaving out the source.
        XCTAssertEqual(rows(provider, "100 eur"), ["125.00 USD | 100 EUR · ⏎ copy"])
        XCTAssertEqual(rows(provider, "100 rub"), ["1.25 USD | 100 RUB · ⏎ copy", "1.00 EUR | 100 RUB · ⏎ copy"])
        XCTAssertEqual(rows(provider, "100 rub to"), rows(provider, "100 rub"))
        XCTAssertEqual(rows(provider, "100 rub to u"), rows(provider, "100 rub"))
        XCTAssertEqual(rows(provider, "100 rub xyz"), rows(provider, "100 rub"))
    }

    func testEnterCopiesBareNumber() async {
        let (_, provider) = await make([.success(.ok(table, etag: nil))])
        provider.results(for: "1000000 jpy to usd").first?.run()
        XCTAssertEqual(copied, ["7812.50"])
    }

    func testNoAnswer() async {
        let (_, provider) = await make([.success(.ok(table, etag: nil))])
        for q in ["", "2+2", "safari", "100 xyz", "100 xyz to eur", "100"] {
            XCTAssertEqual(rows(provider, q), [], q)
        }
        settings.enabled = false
        XCTAssertEqual(rows(provider, "100 usd to eur"), [])
    }

    func testConfiguredTargets() async {
        let (_, provider) = await make([.success(.ok(table, etag: nil))])
        settings.targets = ["RUB", "XYZ", "JPY"]
        XCTAssertEqual(provider.results(for: "1 usd").map(\.title), ["80.00 RUB", "128.00 JPY"])
    }

    func testStaleTableAnswersWhileUpdating() async throws {
        let (store, provider) = await make([.success(.ok(table, etag: "\"v1\"")), .failure(URLError(.timedOut))])
        clock.advance(3 * 86400)
        XCTAssertEqual(rows(provider, "100 usd to eur"), ["80.00 EUR | 100 USD · rates 3d old · updating… · ⏎ copy"])
        XCTAssertTrue(store.isFetching)
        await store.requestRefreshIfStale()?.value
        XCTAssertEqual(rows(provider, "100 usd to eur"), ["80.00 EUR | 100 USD · rates 3d old · ⏎ copy"])
    }

    func testNoTable() async throws {
        let (store, provider) = await make([.failure(URLError(.timedOut))], loaded: false)
        // Too short to be a code: no fetch.
        XCTAssertEqual(rows(provider, "100 us"), [])
        XCTAssertFalse(store.isFetching)
        XCTAssertEqual(provider.results(for: "100 abc").map(\.title), ["fetching rates…"])
        XCTAssertTrue(store.isFetching)
        await store.requestRefreshIfStale()?.value
        XCTAssertEqual(provider.results(for: "100 usd").map(\.title), ["rates unavailable"])
        XCTAssertFalse(store.isFetching)
    }
}
