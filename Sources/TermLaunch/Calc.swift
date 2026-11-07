import Foundation

/// Calculator expressions: + - * / % ^, unary minus, parentheses, pi, e and
/// the usual functions (sqrt, ln, sin, min, max, …).
enum Calc {
    /// Round to 5 decimal places and trim trailing zeros; -0 is "0".
    static func format(_ n: Double) -> String {
        var rounded = (n * 1e5).rounded() / 1e5
        if rounded == 0 { rounded = 0 }
        var s = String(format: "%.5f", rounded)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s.isEmpty || s == "-" ? "0" : s
    }

    /// The value, or nil on a parse error or a non-finite result.
    static func eval(_ expr: String) -> Double? {
        var parser = Parser(Array(expr))
        guard let v = parser.parse(), v.isFinite else { return nil }
        return v
    }

    /// Whether the query looks like a calculation: it starts with a digit, `.` or `(`.
    static func isCalcQuery(_ q: String) -> Bool {
        guard let c = q.first(where: { !$0.isWhitespace }) else { return false }
        return c.isASCII && c.isNumber || c == "." || c == "("
    }

    private static let constants: [String: Double] = ["pi": .pi, "e": M_E]
    private static let unary: [String: @Sendable (Double) -> Double] = [
        "sqrt": { $0.squareRoot() }, "abs": { Swift.abs($0) }, "exp": { Foundation.exp($0) }, "ln": { Foundation.log($0) },
        "sin": { Foundation.sin($0) }, "cos": { Foundation.cos($0) }, "tan": { Foundation.tan($0) },
        "asin": { Foundation.asin($0) }, "acos": { Foundation.acos($0) }, "atan": { Foundation.atan($0) },
        "sinh": { Foundation.sinh($0) }, "cosh": { Foundation.cosh($0) }, "tanh": { Foundation.tanh($0) },
        "asinh": { Foundation.asinh($0) }, "acosh": { Foundation.acosh($0) }, "atanh": { Foundation.atanh($0) },
        "floor": { $0.rounded(.down) }, "ceil": { $0.rounded(.up) }, "round": { $0.rounded() },
        "signum": { $0.isNaN ? .nan : ($0.sign == .minus ? -1 : 1) },
    ]
    private static let variadic: [String: @Sendable ([Double]) -> Double?] = [
        "min": { $0.min() }, "max": { $0.max() }, "atan2": { $0.count == 2 ? Foundation.atan2($0[0], $0[1]) : nil },
    ]

    /// Recursive descent: expr = term (+|- term)*, term = unary (*|/|% unary)*,
    /// unary = (+|-) unary | power, power = atom (^ unary)?.
    private struct Parser {
        let chars: [Character]
        var pos = 0

        init(_ chars: [Character]) { self.chars = chars }

        mutating func parse() -> Double? {
            guard let v = expr() else { return nil }
            skipSpace()
            return pos == chars.count ? v : nil
        }

        private mutating func skipSpace() {
            while pos < chars.count, chars[pos].isWhitespace { pos += 1 }
        }

        private mutating func eat(_ c: Character) -> Bool {
            skipSpace()
            guard pos < chars.count, chars[pos] == c else { return false }
            pos += 1
            return true
        }

        private mutating func expr() -> Double? {
            guard var v = term() else { return nil }
            while true {
                if eat("+") { guard let r = term() else { return nil }; v += r }
                else if eat("-") { guard let r = term() else { return nil }; v -= r }
                else { return v }
            }
        }

        private mutating func term() -> Double? {
            guard var v = unary() else { return nil }
            while true {
                if eat("*") { guard let r = unary() else { return nil }; v *= r }
                else if eat("/") { guard let r = unary() else { return nil }; v /= r }
                else if eat("%") { guard let r = unary() else { return nil }; v = v.truncatingRemainder(dividingBy: r) }
                else { return v }
            }
        }

        private mutating func unary() -> Double? {
            if eat("-") { return unary().map { -$0 } }
            if eat("+") { return unary() }
            return power()
        }

        private mutating func power() -> Double? {
            guard let base = atom() else { return nil }
            guard eat("^") else { return base }
            guard let exponent = unary() else { return nil }
            return pow(base, exponent)
        }

        private mutating func atom() -> Double? {
            skipSpace()
            guard pos < chars.count else { return nil }
            let c = chars[pos]
            if c == "(" {
                pos += 1
                guard let v = expr(), eat(")") else { return nil }
                return v
            }
            if c.isASCII && c.isNumber || c == "." { return number() }
            guard c.isLetter else { return nil }
            var name = ""
            while pos < chars.count, chars[pos].isLetter || chars[pos].isNumber { name.append(chars[pos]); pos += 1 }
            if eat("(") {
                var args: [Double] = []
                if !eat(")") {
                    repeat {
                        guard let a = expr() else { return nil }
                        args.append(a)
                    } while eat(",")
                    guard eat(")") else { return nil }
                }
                if let f = Calc.unary[name], args.count == 1 { return f(args[0]) }
                if let f = Calc.variadic[name], !args.isEmpty { return f(args) }
                return nil
            }
            return Calc.constants[name]
        }

        private mutating func number() -> Double? {
            let start = pos
            func digits() { while pos < chars.count, chars[pos].isASCII, chars[pos].isNumber { pos += 1 } }
            digits()
            if pos < chars.count, chars[pos] == "." { pos += 1; digits() }
            // Exponent only when digits follow, so "2e" stays a parse error rather than eating e.
            if pos < chars.count, chars[pos] == "e" || chars[pos] == "E" {
                var p = pos + 1
                if p < chars.count, chars[p] == "+" || chars[p] == "-" { p += 1 }
                if p < chars.count, chars[p].isASCII, chars[p].isNumber { pos = p; digits() }
            }
            return Double(String(chars[start..<pos]))
        }
    }
}

/// Answers calculation queries with one `= result` row.
final class CalcProvider: LauncherProvider {
    private let copy: (String) -> Void
    /// Last result while typing a pure-number expression, so an incomplete
    /// `2+3*` keeps showing `= 5` instead of flickering away.
    private var lastResult: String?

    init(copy: @escaping (String) -> Void) { self.copy = copy }

    func results(for query: String) -> [LauncherItem] {
        guard Calc.isCalcQuery(query) else { lastResult = nil; return [] }
        if let v = Calc.eval(query) {
            lastResult = Calc.format(v)
        } else if query.contains(where: \.isLetter) {
            // Letters may mean an app ("1Password"): no stale result above it.
            lastResult = nil
        }
        guard let result = lastResult else { return [] }
        let copy = self.copy
        return [LauncherItem(title: "= " + result, hint: "⏎ copy") { copy(result) }]
    }
}
