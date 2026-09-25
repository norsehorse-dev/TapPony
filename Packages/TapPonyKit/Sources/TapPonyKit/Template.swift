import Foundation

/// Where a template sits, which decides escaping. PROFILE_SCHEMA.md section 5.
public enum TemplateContext: String, CaseIterable {
    case url, header, form, json, raw
}

public struct TemplateError: Error, Equatable, CustomStringConvertible {
    public let code: String
    public init(_ code: String) { self.code = code }
    public var description: String { code }
}

/// Anchored whole-string regex match on UTF-16, the same engine family as the
/// Android side (ICU vs java.util.regex) for the ASCII-only patterns used here.
/// \A and \z, not ^ and $: ICU's $ also matches before a final line terminator,
/// which Kotlin's matches/matchEntire do not allow.
struct Pattern {
    let re: NSRegularExpression
    init(_ p: String) { re = try! NSRegularExpression(pattern: "\\A(?:" + p + ")\\z", options: []) }
    func matches(_ s: String) -> Bool {
        re.firstMatch(in: s, options: [], range: NSRange(s.startIndex..., in: s)) != nil
    }
    func groups(_ s: String) -> [String]? {
        guard let m = re.firstMatch(in: s, options: [], range: NSRange(s.startIndex..., in: s)) else { return nil }
        return (0..<m.numberOfRanges).map { idx in
            let r = m.range(at: idx)
            guard r.location != NSNotFound, let rr = Range(r, in: s) else { return "" }
            return String(s[rr])
        }
    }
}

/// The TapPony template engine. Mirrors com.tappony.core.Template; pinned by
/// fixtures/template_vectors.json.
public enum Template {

    public enum Ref: Equatable {
        case variable(String)
        case secret(String)
    }

    public struct Modifier: Equatable {
        public let name: String
        public let args: [String]
    }

    public enum Token: Equatable {
        case literal(String)
        case placeholder(Ref, [Modifier])
    }

    private static let name = Pattern("[a-z_]+")
    private static let secret = Pattern("secret:([A-Za-z0-9_]+)")
    private static let digits = Pattern("[0-9]+")
    private static let jsonNumber = Pattern("-?(0|[1-9][0-9]*)(\\.[0-9]+)?([eE][+-]?[0-9]+)?")
    private static let timestamp = Pattern("([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2}):([0-9]{2})(\\.[0-9]{1,9})?Z")
    private static let noArgMods: Set<String> = ["lower", "upper", "trim", "b64", "url", "colon", "rev", "dec", "unix", "raw"]

    public static func parse(_ template: String) throws -> [Token] {
        let u = Array(template.utf16)
        var out: [Token] = []
        var buf: [UInt16] = []
        var i = 0
        let n = u.count
        func flush() {
            if !buf.isEmpty { out.append(.literal(String(decoding: buf, as: UTF16.self))); buf.removeAll() }
        }
        while i < n {
            let c = u[i]
            if c == 0x7B {
                if i + 1 < n, u[i + 1] == 0x7B { buf.append(0x7B); i += 2; continue }
                if i + 1 < n, (u[i + 1] >= 0x61 && u[i + 1] <= 0x7A) || u[i + 1] == 0x5F {
                    var j = i + 1
                    while j < n, u[j] != 0x7B, u[j] != 0x7D { j += 1 }
                    if j >= n || u[j] != 0x7D { throw TemplateError("unterminated") }
                    flush()
                    out.append(try parsePlaceholder(String(decoding: u[(i + 1)..<j], as: UTF16.self)))
                    i = j + 1
                    continue
                }
            }
            buf.append(c)
            i += 1
        }
        flush()
        return out
    }

    /// Split on a scalar, keeping empty pieces, like Kotlin's String.split. Not
    /// Character-based, so a separator followed by a combining mark still splits.
    private static func splitScalars(_ s: String, _ sep: Unicode.Scalar) -> [String] {
        s.unicodeScalars.split(separator: sep, omittingEmptySubsequences: false).map { String(String.UnicodeScalarView($0)) }
    }

    private static func parsePlaceholder(_ body: String) throws -> Token {
        let parts = splitScalars(body, "|")
        let head = parts[0]
        let ref: Ref
        if let g = secret.groups(head) {
            ref = .secret(g[1])
        } else if name.matches(head) {
            ref = .variable(head)
        } else {
            throw TemplateError("badName")
        }
        var mods: [Modifier] = []
        for m in parts.dropFirst() {
            let modName: String
            let rest: String?
            let us = m.unicodeScalars
            if let c = us.firstIndex(of: ":") {
                modName = String(String.UnicodeScalarView(us[..<c]))
                rest = String(String.UnicodeScalarView(us[us.index(after: c)...]))
            } else {
                modName = m
                rest = nil
            }
            if modName == "default" {
                guard let rest else { throw TemplateError("badModifierArgs") }
                mods.append(Modifier(name: modName, args: [rest]))
                continue
            }
            let args = rest.map { splitScalars($0, ":") } ?? []
            if noArgMods.contains(modName) {
                if !args.isEmpty { throw TemplateError("badModifierArgs") }
            } else if modName == "slice" {
                if !(1...2).contains(args.count) || !args.allSatisfy({ digits.matches($0) }) { throw TemplateError("badModifierArgs") }
            } else {
                throw TemplateError("unknownModifier")
            }
            mods.append(Modifier(name: modName, args: args))
        }
        return .placeholder(ref, mods)
    }

    public static func referencedVariables(_ template: String) throws -> Set<String> {
        Set(try parse(template).compactMap { (t: Token) -> String? in if case .placeholder(.variable(let n), _) = t { return n }; return nil })
    }

    public static func referencedSecrets(_ template: String) throws -> Set<String> {
        Set(try parse(template).compactMap { (t: Token) -> String? in if case .placeholder(.secret(let n), _) = t { return n }; return nil })
    }

    public static func render(_ template: String, context: TemplateContext, variables: [String: String], secrets: [String: String] = [:]) throws -> String {
        let tokens = try parse(template)
        let inString = context == .json ? jsonStringFlags(tokens) : []
        var out = ""
        var pi = 0
        for t in tokens {
            switch t {
            case .literal(let text):
                out += context == .form ? Encoding.form(text) : text
            case .placeholder(let ref, let mods):
                var v: String
                switch ref {
                case .secret(let n):
                    guard let s = secrets[n] else { throw TemplateError("unknownSecret") }
                    v = s
                case .variable(let n):
                    guard let s = variables[n] else { throw TemplateError("unknownVariable") }
                    v = s
                }
                for m in mods { v = apply(v, m) }
                let skip = mods.contains { $0.name == "url" || $0.name == "raw" }
                switch context {
                case .header: v = stripHeader(v)
                case _ where context == .raw || skip: break
                case .url: v = Encoding.percent(v)
                case .form: v = Encoding.form(v)
                case .json: v = jsonValue(v, inString: inString[pi])
                case .raw: break
                }
                pi += 1
                out += v
            }
        }
        if context == .json && !JSON.isValid(out) { throw TemplateError("invalidJsonBody") }
        return out
    }

    public static func stripHeader(_ v: String) -> String {
        String(v.unicodeScalars.filter { $0 != "\r" && $0 != "\n" && $0 != "\u{0}" })
    }

    private static func jsonValue(_ v: String, inString: Bool) -> String {
        if inString { return JSON.escape(v) }
        if v.isEmpty { return "null" }
        if jsonNumber.matches(v) || v == "true" || v == "false" || v == "null" { return v }
        return "\"" + JSON.escape(v) + "\""
    }

    private static func jsonStringFlags(_ tokens: [Token]) -> [Bool] {
        var flags: [Bool] = []
        var inStr = false
        var esc = false
        for t in tokens {
            switch t {
            case .placeholder: flags.append(inStr)
            case .literal(let text):
                for ch in text.utf16 {
                    if inStr {
                        if esc { esc = false } else if ch == 0x5C { esc = true } else if ch == 0x22 { inStr = false }
                    } else if ch == 0x22 {
                        inStr = true
                    }
                }
            }
        }
        return flags
    }

    private static func apply(_ v: String, _ m: Modifier) -> String {
        switch m.name {
        case "lower": return Encoding.asciiLower(v)
        case "upper": return Encoding.asciiUpper(v)
        case "trim": return Encoding.trimTemplateWS(v)
        case "b64": return Encoding.base64(Array(v.utf8))
        case "url": return Encoding.percent(v)
        case "colon": return Encoding.parseLooseHex(v).map { Encoding.colon($0) } ?? v
        case "rev": return Encoding.parseLooseHex(v).map { Encoding.hexUpper(Array($0.reversed())) } ?? v
        case "dec": return Encoding.parseLooseHex(v).map { Encoding.decimal($0) } ?? v
        case "unix": return unix(v) ?? v
        case "slice": return Encoding.sliceCodePoints(v, from: clampInt(m.args[0]), to: m.args.count > 1 ? clampInt(m.args[1]) : nil)
        case "default": return v.isEmpty ? m.args[0] : v
        default: return v
        }
    }

    private static func clampInt(_ s: String) -> Int { s.count > 9 ? Int(Int32.max) : Int(s)! }

    private static func unix(_ v: String) -> String? {
        guard let g = timestamp.groups(v) else { return nil }
        guard let y = Int(g[1]), let mo = Int(g[2]), let d = Int(g[3]),
              let h = Int(g[4]), let mi = Int(g[5]), let s = Int(g[6]) else { return nil }
        guard y >= 1, (1...12).contains(mo), d >= 1, d <= Civil.daysInMonth(y, mo),
              h <= 23, mi <= 59, s <= 59 else { return nil }
        let days = Civil.daysFromCivil(y, mo, d)
        return String(days * 86400 + Int64(h * 3600 + mi * 60 + s))
    }
}

/// Proleptic Gregorian date arithmetic (Howard Hinnant's algorithms), no Foundation calendars.
enum Civil {
    static func isLeap(_ y: Int) -> Bool { (y % 4 == 0 && y % 100 != 0) || y % 400 == 0 }

    static func daysInMonth(_ y: Int, _ m: Int) -> Int {
        switch m {
        case 2: return isLeap(y) ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }

    static func daysFromCivil(_ y0: Int, _ m: Int, _ d: Int) -> Int64 {
        let y = Int64(m <= 2 ? y0 - 1 : y0)
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = Int64((m + 9) % 12)
        let doy = (153 * mp + 2) / 5 + Int64(d) - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146097 + doe - 719468
    }

    static func civilFromDays(_ z0: Int64) -> (Int, Int, Int) {
        let z = z0 + 719468
        let era = (z >= 0 ? z : z - 146096) / 146097
        let doe = z - era * 146097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
        let y = yoe + era * 400
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        return (Int(m <= 2 ? y + 1 : y), Int(m), Int(d))
    }
}
