import Foundation

/// Minimal TOML subset: comments, `key = value`, `[table]`, `[[array.of.tables]]`,
/// basic/literal strings, integers, floats, booleans and single-line arrays of
/// those. Enough for config.toml.
enum TOMLValue: Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([TOMLValue])

    var string: String? { if case .string(let s) = self { return s }; return nil }
    var int: Int? {
        switch self {
        case .int(let i): return i
        case .double(let d): return d.isFinite && d == d.rounded() && abs(d) < 9e18 ? Int(d) : nil
        default: return nil
        }
    }
    var double: Double? {
        switch self {
        case .double(let d): return d
        case .int(let i): return Double(i)
        default: return nil
        }
    }
    var bool: Bool? { if case .bool(let b) = self { return b }; return nil }
    var array: [TOMLValue]? { if case .array(let a) = self { return a }; return nil }
}

struct TOMLDocument {
    /// Top-level keys.
    var root: [String: TOMLValue] = [:]
    /// `[name]` tables.
    var tables: [String: [String: TOMLValue]] = [:]
    /// `[[name]]` arrays of tables, in file order.
    var arrays: [String: [[String: TOMLValue]]] = [:]
}

struct TOMLError: Error, CustomStringConvertible {
    let line: Int
    let message: String
    var description: String { "line \(line): \(message)" }
}

enum TOML {
    static func parse(_ text: String) throws -> TOMLDocument {
        var doc = TOMLDocument()
        enum Target { case root, table(String), array(String) }
        var target = Target.root

        for (index, rawLine) in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).enumerated() {
            let lineNo = index + 1
            let line = stripComment(String(rawLine)).trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }

            if line.hasPrefix("[[") {
                guard line.hasSuffix("]]"), line.count > 4 else { throw TOMLError(line: lineNo, message: "bad array header") }
                let name = String(line.dropFirst(2).dropLast(2)).trimmingCharacters(in: .whitespaces)
                doc.arrays[name, default: []].append([:])
                target = .array(name)
            } else if line.hasPrefix("[") {
                guard line.hasSuffix("]"), line.count > 2 else { throw TOMLError(line: lineNo, message: "bad table header") }
                let name = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                doc.tables[name, default: [:]] = doc.tables[name] ?? [:]
                target = .table(name)
            } else {
                guard let eq = line.firstIndex(of: "=") else { throw TOMLError(line: lineNo, message: "expected key = value") }
                let key = line[..<eq].trimmingCharacters(in: .whitespaces)
                let valueText = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
                guard !key.isEmpty else { throw TOMLError(line: lineNo, message: "empty key") }
                let value = try parseValue(valueText, line: lineNo)
                switch target {
                case .root: doc.root[key] = value
                case .table(let name): doc.tables[name, default: [:]][key] = value
                case .array(let name): doc.arrays[name]![doc.arrays[name]!.count - 1][key] = value
                }
            }
        }
        return doc
    }

    /// Removes a trailing `# comment`, ignoring `#` inside quoted strings.
    private static func stripComment(_ line: String) -> String {
        var quote: Character?
        var escaped = false
        for (i, ch) in line.enumerated() {
            if let q = quote {
                if escaped { escaped = false }
                else if ch == "\\", q == "\"" { escaped = true }
                else if ch == q { quote = nil }
            } else if ch == "\"" || ch == "'" {
                quote = ch
            } else if ch == "#" {
                return String(line.prefix(i))
            }
        }
        return line
    }

    private static func parseValue(_ text: String, line: Int) throws -> TOMLValue {
        if text.hasPrefix("[") {
            guard text.hasSuffix("]") else { throw TOMLError(line: line, message: "unterminated array") }
            return .array(try parseArray(String(text.dropFirst().dropLast()), line: line))
        }
        if text == "true" { return .bool(true) }
        if text == "false" { return .bool(false) }
        if text.hasPrefix("\"") {
            guard text.count >= 2, text.hasSuffix("\"") else { throw TOMLError(line: line, message: "unterminated string") }
            return .string(try unescape(String(text.dropFirst().dropLast()), line: line))
        }
        if text.hasPrefix("'") {
            guard text.count >= 2, text.hasSuffix("'") else { throw TOMLError(line: line, message: "unterminated string") }
            return .string(String(text.dropFirst().dropLast()))
        }
        let cleaned = text.replacingOccurrences(of: "_", with: "")
        if let i = Int(cleaned) { return .int(i) }
        if let d = Double(cleaned) { return .double(d) }
        throw TOMLError(line: line, message: "unrecognised value \(text)")
    }

    /// The inside of `[a, b, ]`: scalars split on commas outside quotes; a trailing comma is allowed.
    private static func parseArray(_ text: String, line: Int) throws -> [TOMLValue] {
        var parts: [String] = []
        var current = ""
        var quote: Character?
        var escaped = false
        for ch in text {
            if let q = quote {
                if escaped { escaped = false }
                else if ch == "\\", q == "\"" { escaped = true }
                else if ch == q { quote = nil }
                current.append(ch)
            } else if ch == "\"" || ch == "'" {
                quote = ch
                current.append(ch)
            } else if ch == "[" || ch == "]" {
                throw TOMLError(line: line, message: "nested arrays are not supported")
            } else if ch == "," {
                parts.append(current)
                current = ""
            } else {
                current.append(ch)
            }
        }
        let last = current.trimmingCharacters(in: .whitespaces)
        if !last.isEmpty { parts.append(last) }
        return try parts.map {
            let item = $0.trimmingCharacters(in: .whitespaces)
            guard !item.isEmpty else { throw TOMLError(line: line, message: "empty array element") }
            return try parseValue(item, line: line)
        }
    }

    private static func unescape(_ s: String, line: Int) throws -> String {
        var out = ""
        var it = s.makeIterator()
        while let ch = it.next() {
            guard ch == "\\" else { out.append(ch); continue }
            guard let next = it.next() else { throw TOMLError(line: line, message: "dangling escape") }
            switch next {
            case "n": out.append("\n")
            case "t": out.append("\t")
            case "r": out.append("\r")
            case "\"": out.append("\"")
            case "\\": out.append("\\")
            default: throw TOMLError(line: line, message: "unsupported escape \\\(next)")
            }
        }
        return out
    }
}
