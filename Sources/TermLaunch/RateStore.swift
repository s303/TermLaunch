import Foundation

/// Exchange rates for the whole app session: Frankfurter's table of rates
/// against EUR, cached on disk and refreshed lazily when a conversion is typed
/// (see docs/adr/0004). Reads are synchronous; fetches run in the background.
@MainActor
final class RateStore {
    /// Posted on the main queue when a fetch finishes (new data, revalidated, or failed).
    static let didChange = Notification.Name("TermLaunchRateStoreDidChange")

    enum FetchResult: Sendable, Equatable {
        case ok(Data, etag: String?)
        case notModified
    }
    /// GETs the table, sending `etag` as If-None-Match when given.
    typealias Fetch = @Sendable (_ etag: String?) async throws -> FetchResult

    nonisolated static let endpoint = URL(string: "https://api.frankfurter.dev/v2/rates")!
    static let maxAge: TimeInterval = 6 * 3600
    static let retryDelay: TimeInterval = 60

    /// Units of each code per 1 EUR; empty until a table is loaded.
    private(set) var rates: [String: Double] = [:]
    private(set) var fetchedAt: Date?
    private(set) var lastFailure: Date?
    private var etag: String?
    private var body: Data?
    private var inFlight: Task<Void, Never>?

    private let fetch: Fetch
    private let now: () -> Date
    private let cacheURL: URL

    init(fetch: @escaping Fetch = RateStore.download, now: @escaping () -> Date = Date.init,
         cacheURL: URL = RateStore.defaultCacheURL) {
        self.fetch = fetch
        self.now = now
        self.cacheURL = cacheURL
        loadCache()
    }

    nonisolated static var defaultCacheURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/TermLaunch/rates.json")
    }

    var hasTable: Bool { !rates.isEmpty }
    var isFetching: Bool { inFlight != nil }
    /// Time since the table was fetched or revalidated; nil without a table.
    var tableAge: TimeInterval? { hasTable ? fetchedAt.map { now().timeIntervalSince($0) } : nil }
    var isStale: Bool { (tableAge ?? .infinity) >= Self.maxAge }

    func knows(code: String) -> Bool { rates[code.uppercased()] != nil }

    /// How many `to` one `from` buys, crossing through EUR.
    func rate(from: String, to: String) -> Double? {
        guard let f = rates[from.uppercased()], let t = rates[to.uppercased()], f != 0 else { return nil }
        return t / f
    }

    /// Starts a fetch if the table is missing or stale, unless one is running
    /// (it is returned instead) or the last failure was under a minute ago.
    @discardableResult
    func requestRefreshIfStale() -> Task<Void, Never>? {
        if let inFlight { return inFlight }
        guard isStale else { return nil }
        if let lastFailure, now().timeIntervalSince(lastFailure) < Self.retryDelay { return nil }
        let fetch = self.fetch
        let etag = hasTable ? self.etag : nil
        let task = Task { [weak self] in
            let result: FetchResult?
            do { result = try await fetch(etag) } catch {
                NSLog("TermLaunch: rate fetch failed: %@", error.localizedDescription)
                result = nil
            }
            self?.finish(result)
        }
        inFlight = task
        return task
    }

    private func finish(_ result: FetchResult?) {
        inFlight = nil
        switch result {
        case .ok(let data, let etag)?:
            if let table = Self.parse(data) {
                rates = table
                body = data
                self.etag = etag
                fetchedAt = now()
                lastFailure = nil
                saveCache()
            } else {
                NSLog("TermLaunch: rate table did not parse")
                lastFailure = now()
            }
        case .notModified? where hasTable:
            fetchedAt = now()
            lastFailure = nil
            saveCache()
        default:
            lastFailure = now()
        }
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }

    // MARK: Table

    private struct Entry: Decodable {
        let quote: String
        let rate: Double
    }

    /// The API's `[{"date","base":"EUR","quote","rate"}]`; nil if it doesn't decode.
    nonisolated static func parse(_ data: Data) -> [String: Double]? {
        guard let entries = try? JSONDecoder().decode([Entry].self, from: data), !entries.isEmpty else { return nil }
        var table = ["EUR": 1.0]
        for e in entries where e.rate.isFinite && e.rate > 0 { table[e.quote.uppercased()] = e.rate }
        return table
    }

    // MARK: Disk

    /// The raw response with its ETag and fetch time.
    private struct CacheFile: Codable {
        var body: String
        var etag: String?
        var fetchedAt: Double
    }

    private func loadCache() {
        guard let data = try? Data(contentsOf: cacheURL),
              let file = try? JSONDecoder().decode(CacheFile.self, from: data),
              let raw = file.body.data(using: .utf8), let table = Self.parse(raw) else { return }
        rates = table
        body = raw
        etag = file.etag
        fetchedAt = Date(timeIntervalSince1970: file.fetchedAt)
    }

    private func saveCache() {
        guard let body, let fetchedAt else { return }
        let file = CacheFile(body: String(decoding: body, as: UTF8.self), etag: etag,
                             fetchedAt: fetchedAt.timeIntervalSince1970)
        do {
            try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(file).write(to: cacheURL, options: .atomic)
        } catch {
            NSLog("TermLaunch: cannot write %@: %@", cacheURL.path, error.localizedDescription)
        }
    }

    // MARK: Network

    private struct HTTPError: LocalizedError {
        let status: Int
        var errorDescription: String? { "HTTP \(status)" }
    }

    /// The real fetch: no URL cache, so a 304 reaches us rather than being answered from it.
    nonisolated static let download: Fetch = { etag in
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }
        var request = URLRequest(url: endpoint, timeoutInterval: 15)
        if let etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200: return .ok(data, etag: (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "ETag"))
        case 304: return .notModified
        default: throw HTTPError(status: status)
        }
    }
}
