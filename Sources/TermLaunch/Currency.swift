import Foundation

/// A query of the form `<amount> <FROM> [to|in] <TO>` (see docs/adr/0004).
struct ConversionQuery: Equatable {
    let amount: Double
    /// Uppercased; not yet checked against the rate table.
    let from: String
    /// Uppercased, possibly incomplete; nil means the default targets.
    let to: String?

    /// Case-insensitive. The space before FROM and the `to`/`in` are optional;
    /// the amount is any calculator query (it must start like one).
    static func parse(_ query: String) -> ConversionQuery? {
        let s = Substring(query.trimmingCharacters(in: .whitespaces).lowercased())
        guard let (rest, last) = trailingWord(s) else { return nil }
        // A target needs a space before it.
        if rest.last?.isWhitespace == true {
            let head = trimTrailing(rest)
            if let (before, word) = trailingWord(head), word == "to" || word == "in", before.last?.isWhitespace == true,
               let q = make(trimTrailing(before), to: last) {
                return q
            }
            if let q = make(head, to: last) { return q }
        }
        return make(s, to: nil)
    }

    /// `<amount><FROM>` with an optional target.
    private static func make(_ text: Substring, to: Substring?) -> ConversionQuery? {
        guard let (amountText, from) = trailingWord(text) else { return nil }
        let expr = String(trimTrailing(amountText))
        guard Calc.isCalcQuery(expr), let amount = Calc.eval(expr) else { return nil }
        return ConversionQuery(amount: amount, from: from.uppercased(), to: to?.uppercased())
    }

    /// Splits off the run of ASCII letters at the end.
    private static func trailingWord(_ s: Substring) -> (rest: Substring, word: Substring)? {
        var start = s.endIndex
        while start > s.startIndex {
            let prev = s.index(before: start)
            guard s[prev].isASCII, s[prev].isLetter else { break }
            start = prev
        }
        return start == s.endIndex ? nil : (s[..<start], s[start...])
    }

    private static func trimTrailing(_ s: Substring) -> Substring {
        var end = s.endIndex
        while end > s.startIndex, s[s.index(before: end)].isWhitespace { end = s.index(before: end) }
        return s[..<end]
    }
}

/// Number formatting for conversions: `.` decimal point, `,` grouping on screen.
enum CurrencyFormat {
    /// The bare number copied by Enter: 2 decimals for values ≥ 1, otherwise
    /// 4 significant digits (trailing zeros trimmed down to 2 decimals).
    static func plain(_ v: Double) -> String {
        guard v.isFinite else { return "0" }
        let a = abs(v)
        let decimals = a >= 1 || a == 0 ? 2 : min(Int(-log10(a).rounded(.down)) + 3, 20)
        var s = String(format: "%.*f", decimals, v)
        while s.hasSuffix("0"), let dot = s.firstIndex(of: "."), s.distance(from: dot, to: s.endIndex) > 3 { s.removeLast() }
        if s.hasPrefix("-"), Double(s) == 0 { s.removeFirst() }
        return s
    }

    /// `plain` with grouping separators.
    static func display(_ v: Double) -> String { group(plain(v)) }

    /// Inserts `,` every three digits of the integer part.
    static func group(_ s: String) -> String {
        let negative = s.hasPrefix("-")
        let body = negative ? s.dropFirst() : Substring(s)
        let dot = body.firstIndex(of: ".") ?? body.endIndex
        let digits = Array(body[..<dot])
        var out = ""
        for (i, d) in digits.enumerated() {
            if i > 0, (digits.count - i) % 3 == 0 { out.append(",") }
            out.append(d)
        }
        return (negative ? "-" : "") + out + body[dot...]
    }

    /// `rates 3d old` once the table is more than 2 days old.
    static func age(_ age: TimeInterval?) -> String? {
        guard let age, age > 2 * 86400 else { return nil }
        return "rates \(Int(age / 86400))d old"
    }
}

/// Converts `<amount> <FROM> [to|in] <TO>` with the rate table in a `RateStore`.
/// Synchronous: a missing or stale table triggers a background fetch, and the
/// Launcher re-queries on `RateStore.didChange`.
@MainActor
final class CurrencyProvider: LauncherProvider {
    private let store: RateStore
    private let settings: () -> CurrencySettings
    private let copy: (String) -> Void

    init(store: RateStore, settings: @escaping () -> CurrencySettings, copy: @escaping (String) -> Void) {
        self.store = store
        self.settings = settings
        self.copy = copy
    }

    func results(for query: String) -> [LauncherItem] {
        let settings = settings()
        guard settings.enabled, let q = ConversionQuery.parse(query) else { return [] }
        guard store.hasTable else {
            // Codes can't be checked yet: any 3+ letter word may be one.
            guard q.from.count >= 3 else { return [] }
            store.requestRefreshIfStale()
            let title = store.isFetching || store.lastFailure == nil ? "fetching rates…" : "rates unavailable"
            return [LauncherItem(title: title) {}]
        }
        guard store.knows(code: q.from) else { return [] }
        store.requestRefreshIfStale()

        var targets: [String]
        if let to = q.to, store.knows(code: to) {
            targets = [to]
        } else {
            targets = []
            for code in settings.targets where code != q.from && store.knows(code: code) && !targets.contains(code) {
                targets.append(code)
            }
        }
        var hint = [CurrencyFormat.group(Calc.format(q.amount)) + " " + q.from]
        if let age = CurrencyFormat.age(store.tableAge) { hint.append(age) }
        if store.isFetching { hint.append("updating…") }
        hint.append("⏎ copy")
        let hintText = hint.joined(separator: " · ")
        let copy = self.copy
        return targets.compactMap { code in
            guard let rate = store.rate(from: q.from, to: code) else { return nil }
            let value = q.amount * rate
            let plain = CurrencyFormat.plain(value)
            return LauncherItem(title: CurrencyFormat.display(value) + " " + code, hint: hintText) { copy(plain) }
        }
    }
}
