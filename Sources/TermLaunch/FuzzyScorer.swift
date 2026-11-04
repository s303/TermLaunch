import Foundation

/// fzf-style fuzzy matching: every query word must match the text as a
/// subsequence; matches at word starts, camelCase humps and consecutive runs
/// score higher, gaps cost. Case and diacritics are ignored.
enum FuzzyScorer {
    private static let match = 16
    private static let gapStart = -3
    private static let gapExtension = -1
    private static let boundary = match / 2
    private static let boundaryWhite = boundary + 2
    private static let boundaryDelimiter = boundary + 1
    private static let nonWord = boundary
    private static let camel = boundary + gapExtension
    private static let consecutive = -(gapStart + gapExtension)
    private static let firstCharMultiplier = 2

    private enum CharClass { case white, delimiter, nonWord, lower, upper, number }

    private static func charClass(_ c: Character) -> CharClass {
        if c.isWhitespace { return .white }
        if "/,:;|-_.".contains(c) { return .delimiter }
        if c.isNumber { return .number }
        if c.isUppercase { return .upper }
        if c.isLetter { return .lower }
        return .nonWord
    }

    private static func bonus(_ prev: CharClass, _ cur: CharClass) -> Int {
        switch cur {
        case .lower, .upper, .number:
            switch prev {
            case .white: return boundaryWhite
            case .delimiter: return boundaryDelimiter
            case .nonWord: return boundary
            default: break
            }
            if prev == .lower && cur == .upper || prev != .number && cur == .number { return camel }
            return 0
        case .white: return boundaryWhite
        case .delimiter, .nonWord: return nonWord
        }
    }

    private static func fold(_ c: Character) -> Character {
        String(c).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).first ?? c
    }

    /// Score of `query` against `text`, or nil when some query word doesn't match.
    static func score(_ query: String, in text: String) -> Int? {
        let words = query.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return 0 }
        let chars = Array(text)
        let folded = chars.map(fold)
        var bonuses: [Int] = []
        var prev = CharClass.white
        for c in chars {
            let cls = charClass(c)
            bonuses.append(bonus(prev, cls))
            prev = cls
        }
        var total = 0
        for word in words {
            guard let s = score(pattern: word.map(fold), text: folded, bonuses: bonuses) else { return nil }
            total += s
        }
        return total
    }

    /// Smith-Waterman-style alignment: best score with every pattern char matched in order.
    private static func score(pattern: [Character], text: [Character], bonuses: [Int]) -> Int? {
        let n = text.count
        guard pattern.count <= n else { return nil }
        let none = Int.min / 2
        // h[j]: best score with the current pattern char matched at text[j];
        // run[j]: the bonus carried by the consecutive run ending at j.
        var h = [Int](repeating: none, count: n)
        var run = [Int](repeating: 0, count: n)
        for (i, p) in pattern.enumerated() {
            var nh = [Int](repeating: none, count: n)
            var nrun = [Int](repeating: 0, count: n)
            var gap = none // best h[k] plus the gap penalty up to j, for k < j - 1
            for j in 0..<n {
                if i > 0, j >= 2, h[j - 2] > none {
                    gap = max(gap + gapExtension, h[j - 2] + gapStart)
                } else if gap > none {
                    gap += gapExtension
                }
                guard text[j] == p else { continue }
                let b = bonuses[j]
                if i == 0 {
                    nh[j] = match + b * firstCharMultiplier
                    nrun[j] = b
                    continue
                }
                if j >= 1, h[j - 1] > none {
                    var carried = max(run[j - 1], consecutive, b)
                    if b >= boundary && b > carried { carried = b }
                    nh[j] = h[j - 1] + match + carried
                    nrun[j] = carried
                }
                if gap > none, gap + match + b > nh[j] {
                    nh[j] = gap + match + b
                    nrun[j] = b
                }
            }
            h = nh
            run = nrun
        }
        let best = h.max() ?? none
        return best > none ? best : nil
    }
}

struct AppEntry: Equatable {
    let name: String
    let path: String

    init(path: String) {
        self.path = path
        name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
    }
}

enum AppRanker {
    /// Fuzzy score weighted by frecency, best first. An empty query sorts by frecency alone.
    static func rank(_ apps: [AppEntry], query: String, frecency: FrecencyStore) -> [AppEntry] {
        let empty = query.allSatisfy(\.isWhitespace)
        let scored: [(app: AppEntry, score: Double)] = apps.compactMap { app in
            let f = frecency.score(app.path)
            if empty { return (app, f) }
            guard let fuzzy = FuzzyScorer.score(query, in: app.name) else { return nil }
            return (app, Double(fuzzy) * (1 + log(1 + f)))
        }
        return scored.sorted { a, b in
            if a.score != b.score { return a.score > b.score }
            if !empty, a.app.name.count != b.app.name.count { return a.app.name.count < b.app.name.count }
            return a.app.name.localizedCaseInsensitiveCompare(b.app.name) == .orderedAscending
        }.map(\.app)
    }
}
