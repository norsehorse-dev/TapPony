import Foundation

/// An ordered JSON value. Objects keep their key order so profile documents
/// round-trip exactly and match the Android core's writer.
public enum JSONValue: Equatable {
    case null
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([JSONMember])

    public subscript(key: String) -> JSONValue? {
        if case .object(let members) = self {
            return members.first(where: { $0.key == key })?.value
        }
        return nil
    }

    public var string: String? { if case .string(let s) = self { return s }; return nil }
    public var bool: Bool? { if case .bool(let b) = self { return b }; return nil }
    public var int: Int? {
        switch self {
        case .int(let i): return Int(exactly: i)
        case .double(let d): return d.isFinite && d == d.rounded() && abs(d) < 1e15 ? Int(d) : nil
        default: return nil
        }
    }
    public var array: [JSONValue]? { if case .array(let a) = self { return a }; return nil }
    public var isNull: Bool { if case .null = self { return true }; return false }
}

public struct JSONMember: Equatable {
    public let key: String
    public let value: JSONValue
    public init(_ key: String, _ value: JSONValue) { self.key = key; self.value = value }
}

/// Strict RFC 8259 reader and compact writer. Mirrors com.tappony.core.Json.
public enum JSON {

    public struct ParseError: Error, CustomStringConvertible {
        public let description: String
    }

    public static func parse(_ text: String) throws -> JSONValue {
        var p = Parser(Array(text.utf16))
        p.skipWS()
        let v = try p.value(depth: 0)
        p.skipWS()
        if p.i != p.s.count { throw ParseError(description: "trailing content at \(p.i)") }
        return v
    }

    public static func isValid(_ text: String) -> Bool {
        (try? parse(text)) != nil
    }

    /// JSON string escaping, PROFILE_SCHEMA.md section 5, without surrounding quotes.
    public static func escape(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.utf8.count + 8)
        for u in s.unicodeScalars {
            switch u {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if u.value < 0x20 {
                    out += "\\u00" + Encoding.hex2(Int(u.value))
                } else {
                    out.unicodeScalars.append(u)
                }
            }
        }
        return out
    }

    public static func write(_ v: JSONValue) -> String {
        var out = ""
        writeTo(&out, v)
        return out
    }

    private static func writeTo(_ out: inout String, _ v: JSONValue) {
        switch v {
        case .null: out += "null"
        case .bool(let b): out += b ? "true" : "false"
        case .int(let i): out += String(i)
        case .double(let d):
            if d == d.rounded() && abs(d) < 1e15 { out += String(Int64(d)) } else { out += String(d) }
        case .string(let s): out += "\"" + escape(s) + "\""
        case .array(let a):
            out += "["
            for (idx, item) in a.enumerated() {
                if idx > 0 { out += "," }
                writeTo(&out, item)
            }
            out += "]"
        case .object(let members):
            out += "{"
            for (idx, m) in members.enumerated() {
                if idx > 0 { out += "," }
                out += "\"" + escape(m.key) + "\":"
                writeTo(&out, m.value)
            }
            out += "}"
        }
    }

    private struct Parser {
        let s: [UInt16]
        var i = 0
        init(_ s: [UInt16]) { self.s = s }

        func fail(_ msg: String) -> ParseError { ParseError(description: "\(msg) at \(i)") }

        mutating func skipWS() {
            while i < s.count, s[i] == 0x20 || s[i] == 0x09 || s[i] == 0x0A || s[i] == 0x0D { i += 1 }
        }

        mutating func value(depth: Int) throws -> JSONValue {
            if depth > 128 { throw fail("too deep") }
            guard i < s.count else { throw fail("unexpected end") }
            switch s[i] {
            case 0x7B: return try object(depth: depth)
            case 0x5B: return try array(depth: depth)
            case 0x22: return .string(try string())
            case 0x74: try literal("true"); return .bool(true)
            case 0x66: try literal("false"); return .bool(false)
            case 0x6E: try literal("null"); return .null
            default: return try number()
            }
        }

        mutating func literal(_ word: String) throws {
            let w = Array(word.utf16)
            guard i + w.count <= s.count, Array(s[i..<(i + w.count)]) == w else { throw fail("bad literal") }
            i += w.count
        }

        mutating func object(depth: Int) throws -> JSONValue {
            i += 1
            var members: [JSONMember] = []
            skipWS()
            if i < s.count, s[i] == 0x7D { i += 1; return .object(members) }
            while true {
                skipWS()
                guard i < s.count, s[i] == 0x22 else { throw fail("expected key") }
                let k = try string()
                skipWS()
                guard i < s.count, s[i] == 0x3A else { throw fail("expected colon") }
                i += 1
                skipWS()
                let v = try value(depth: depth + 1)
                if let idx = members.firstIndex(where: { $0.key == k }) {
                    members[idx] = JSONMember(k, v)
                } else {
                    members.append(JSONMember(k, v))
                }
                skipWS()
                guard i < s.count else { throw fail("unexpected end") }
                if s[i] == 0x2C { i += 1; continue }
                if s[i] == 0x7D { i += 1; return .object(members) }
                throw fail("expected , or }")
            }
        }

        mutating func array(depth: Int) throws -> JSONValue {
            i += 1
            var items: [JSONValue] = []
            skipWS()
            if i < s.count, s[i] == 0x5D { i += 1; return .array(items) }
            while true {
                skipWS()
                items.append(try value(depth: depth + 1))
                skipWS()
                guard i < s.count else { throw fail("unexpected end") }
                if s[i] == 0x2C { i += 1; continue }
                if s[i] == 0x5D { i += 1; return .array(items) }
                throw fail("expected , or ]")
            }
        }

        mutating func string() throws -> String {
            i += 1
            var units: [UInt16] = []
            while true {
                guard i < s.count else { throw fail("unterminated string") }
                let c = s[i]
                if c == 0x22 { i += 1; return String(decoding: units, as: UTF16.self) }
                if c == 0x5C {
                    guard i + 1 < s.count else { throw fail("bad escape") }
                    let e = s[i + 1]
                    i += 2
                    switch e {
                    case 0x22: units.append(0x22)
                    case 0x5C: units.append(0x5C)
                    case 0x2F: units.append(0x2F)
                    case 0x62: units.append(0x08)
                    case 0x66: units.append(0x0C)
                    case 0x6E: units.append(0x0A)
                    case 0x72: units.append(0x0D)
                    case 0x74: units.append(0x09)
                    case 0x75:
                        guard i + 4 <= s.count else { throw fail("bad unicode escape") }
                        var v: UInt16 = 0
                        for k in 0..<4 {
                            let h = s[i + k]
                            let d: UInt16
                            switch h {
                            case 0x30...0x39: d = h - 0x30
                            case 0x61...0x66: d = h - 0x61 + 10
                            case 0x41...0x46: d = h - 0x41 + 10
                            default: throw fail("bad unicode escape")
                            }
                            v = v << 4 | d
                        }
                        units.append(v)
                        i += 4
                    default: throw fail("bad escape")
                    }
                    continue
                }
                if c < 0x20 { throw fail("control character in string") }
                units.append(c)
                i += 1
            }
        }

        mutating func number() throws -> JSONValue {
            let start = i
            func digit(_ k: Int) -> Bool { k < s.count && s[k] >= 0x30 && s[k] <= 0x39 }
            if i < s.count, s[i] == 0x2D { i += 1 }
            guard i < s.count else { throw fail("bad number") }
            if s[i] == 0x30 {
                i += 1
            } else if s[i] >= 0x31 && s[i] <= 0x39 {
                while digit(i) { i += 1 }
            } else {
                throw fail("bad number")
            }
            var isInt = true
            if i < s.count, s[i] == 0x2E {
                isInt = false
                i += 1
                guard digit(i) else { throw fail("bad fraction") }
                while digit(i) { i += 1 }
            }
            if i < s.count, s[i] == 0x65 || s[i] == 0x45 {
                isInt = false
                i += 1
                if i < s.count, s[i] == 0x2B || s[i] == 0x2D { i += 1 }
                guard digit(i) else { throw fail("bad exponent") }
                while digit(i) { i += 1 }
            }
            let t = String(decoding: s[start..<i], as: UTF16.self)
            if isInt, let v = Int64(t) { return .int(v) }
            return .double(Double(t) ?? 0)
        }
    }
}
