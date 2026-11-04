import Foundation

/// Launch history shared with the `oa` CLI (rush): app path → score, decaying
/// ~10% per day. Same JSON file and format, so either can record launches.
struct FrecencyStore: Codable, Equatable {
    var scores: [String: Double] = [:]
    var lastUpdated: UInt64 = 0

    enum CodingKeys: String, CodingKey {
        case scores
        case lastUpdated = "last_updated"
    }

    static var defaultPath: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/share/oa/frecency.json")
    }

    /// A missing or unreadable file is an empty store.
    static func load(from url: URL = defaultPath) -> FrecencyStore {
        guard let data = try? Data(contentsOf: url),
              let store = try? JSONDecoder().decode(FrecencyStore.self, from: data) else { return FrecencyStore() }
        return store
    }

    func save(to url: URL = defaultPath) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        if let data = try? encoder.encode(self) { try? data.write(to: url, options: .atomic) }
    }

    /// Ages every score by the time since `lastUpdated`, then marks the store current.
    mutating func applyDecay(now: UInt64 = Self.now()) {
        let hours = Double(now > lastUpdated ? now - lastUpdated : 0) / 3600
        let decay = pow(0.9, hours / 24)
        for key in scores.keys { scores[key]! *= decay }
        lastUpdated = now
    }

    mutating func add(_ path: String) {
        scores[path, default: 0] += 1
    }

    /// Records a launch and writes the store.
    mutating func record(_ path: String, to url: URL = defaultPath) {
        add(path)
        lastUpdated = Self.now()
        save(to: url)
    }

    func score(_ path: String) -> Double { scores[path] ?? 0 }

    static func now() -> UInt64 { UInt64(Date().timeIntervalSince1970) }
}
