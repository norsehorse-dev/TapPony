import Foundation

/// Decides whether a rendered URL may be sent. PROFILE_SCHEMA.md section 7.
/// Mirrors com.tappony.core.HostPolicy; pinned by fixtures/hostpolicy_vectors.json.
///
/// ATS blocks plain HTTP to public host names, but NSAllowsLocalNetworking
/// re-opens IP literals of any kind, so this validator is what keeps plain HTTP
/// off public IPs.
public enum HostPolicy {

    public struct Result: Equatable {
        public let allowed: Bool
        /// Host class when allowed (publicTls, localTls, localPlain), reason when rejected.
        public let detail: String
    }

    private static let url = try! NSRegularExpression(pattern: "^([A-Za-z][A-Za-z0-9+.-]*)://([^/?#]*)(.*)$", options: [.dotMatchesLineSeparators])
    private static let port = Pattern("[0-9]{1,5}")
    private static let v4Octet = Pattern("0|[1-9][0-9]{0,2}")
    private static let host = Pattern("[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)*")
    private static let numericish = Pattern("[0-9a-fx.]+")
    private static let digitsDots = Pattern("[0-9.]+")

    private static func rejected(_ r: String) -> Result { Result(allowed: false, detail: r) }

    public static func check(_ urlString: String, allowLocalHttp: Bool) -> Result {
        guard let m = url.firstMatch(in: urlString, options: [], range: NSRange(urlString.startIndex..., in: urlString)),
              let sr = Range(m.range(at: 1), in: urlString), let ar = Range(m.range(at: 2), in: urlString) else {
            return rejected("malformed")
        }
        let scheme = Encoding.asciiLower(String(urlString[sr]))
        let authority = String(urlString[ar])
        if scheme != "http" && scheme != "https" { return rejected("scheme") }
        if authority.unicodeScalars.contains("@") { return rejected("userinfo") }
        let local: Bool
        if authority.hasPrefix("[") {
            guard let close = authority.firstIndex(of: "]") else { return rejected("malformed") }
            let h = String(authority[authority.index(after: authority.startIndex)..<close])
            let rest = String(authority[authority.index(after: close)...])
            if !rest.isEmpty {
                let p = String(rest.dropFirst())
                guard rest.hasPrefix(":"), port.matches(p), let pv = Int(p), pv <= 65535 else { return rejected("malformed") }
            }
            if h.contains("%") { return rejected("malformed") }
            guard let b = parseIPv6(h) else { return rejected("malformed") }
            local = isV4Mapped(b) ? isLocalV4(Array(b[12..<16])) : isLocalV6(b)
        } else {
            var h: String
            if let c = authority.firstIndex(of: ":") {
                h = String(authority[..<c])
                let p = String(authority[authority.index(after: c)...])
                guard port.matches(p), let pv = Int(p), pv <= 65535 else { return rejected("malformed") }
            } else {
                h = authority
            }
            h = h.lowercased()
            if h.hasSuffix(".") { h.removeLast() }
            if h.isEmpty { return rejected("malformed") }
            if let v4 = parseStrictV4(h) {
                local = isLocalV4(v4)
            } else {
                if numericish.matches(h) && (digitsDots.matches(h) || h.components(separatedBy: ".").contains(where: { $0.hasPrefix("0x") })) {
                    return rejected("numericHost")
                }
                if !host.matches(h) { return rejected("malformed") }
                local = h.hasSuffix(".local") || h.hasSuffix(".home.arpa") || !h.contains(".")
            }
        }
        if scheme == "https" { return Result(allowed: true, detail: local ? "localTls" : "publicTls") }
        if !local { return rejected("plainHttpPublic") }
        if !allowLocalHttp { return rejected("localHttpNotEnabled") }
        return Result(allowed: true, detail: "localPlain")
    }

    /// Save-time rule: scheme and authority must be literal text.
    public static func checkTemplate(_ template: String) -> String {
        // Scalar-level, like Kotlin's indexOf: a delimiter followed by a combining
        // mark must still end the scheme or authority.
        let u = Array(template.unicodeScalars)
        var idx = -1
        if u.count >= 3 {
            for k in 0...(u.count - 3) where u[k] == ":" && u[k + 1] == "/" && u[k + 2] == "/" { idx = k; break }
        }
        if idx < 0 { return "malformed" }
        let scheme = u[..<idx]
        let authority = u[(idx + 3)...].prefix(while: { $0 != "/" && $0 != "?" && $0 != "#" })
        if scheme.contains("{") || authority.contains("{") { return "templatedAuthority" }
        return "ok"
    }

    public static func parseStrictV4(_ h: String) -> [UInt8]? {
        let parts = h.components(separatedBy: ".")
        guard parts.count == 4 else { return nil }
        var out: [UInt8] = []
        for p in parts {
            guard v4Octet.matches(p), let v = Int(p), v <= 255 else { return nil }
            out.append(UInt8(v))
        }
        return out
    }

    /// RFC 4291 text forms with '::' and a trailing dotted IPv4. No zone ids.
    public static func parseIPv6(_ s: String) -> [UInt8]? {
        if s.isEmpty { return nil }
        let dbl = s.range(of: "::")
        if let d = dbl, s[s.index(after: d.lowerBound)...].contains("::") { return nil }
        func groups(_ part: Substring) -> [String]? {
            if part.isEmpty { return [] }
            let g = part.components(separatedBy: ":")
            return g.contains(where: { $0.isEmpty }) ? nil : g
        }
        let head: [String]
        let tail: [String]
        if let d = dbl {
            guard let h = groups(s[..<d.lowerBound]), let t = groups(s[d.upperBound...]) else { return nil }
            head = h; tail = t
        } else {
            guard let h = groups(s[...]) else { return nil }
            head = h; tail = []
        }
        let all = head + tail
        var headWords: [Int] = []
        var tailWords: [Int] = []
        for (idx, g) in all.enumerated() {
            let isLast = idx == all.count - 1
            var words: [Int] = []
            if isLast && g.contains(".") {
                guard let v4 = parseStrictV4(g) else { return nil }
                words = [Int(v4[0]) << 8 | Int(v4[1]), Int(v4[2]) << 8 | Int(v4[3])]
            } else {
                guard g.count <= 4, g.unicodeScalars.allSatisfy({ $0.isASCII && $0.properties.isASCIIHexDigit }),
                      let w = Int(g, radix: 16) else { return nil }
                words = [w]
            }
            if idx < head.count { headWords += words } else { tailWords += words }
        }
        let count = headWords.count + tailWords.count
        var words: [Int]
        if dbl != nil {
            if count > 7 { return nil }
            words = headWords + Array(repeating: 0, count: 8 - count) + tailWords
        } else {
            if count != 8 { return nil }
            words = headWords
        }
        var out: [UInt8] = []
        for w in words { out.append(UInt8(w >> 8)); out.append(UInt8(w & 0xFF)) }
        return out
    }

    private static func isV4Mapped(_ b: [UInt8]) -> Bool {
        b[0..<10].allSatisfy { $0 == 0 } && b[10] == 0xFF && b[11] == 0xFF
    }

    public static func isLocalV4(_ b: [UInt8]) -> Bool {
        let a = b[0], c = b[1]
        return a == 10 || (a == 172 && (16...31).contains(c)) || (a == 192 && c == 168) || (a == 169 && c == 254) || a == 127
    }

    public static func isLocalV6(_ b: [UInt8]) -> Bool {
        let loopback = b[0..<15].allSatisfy { $0 == 0 } && b[15] == 1
        let linkLocal = b[0] == 0xFE && (b[1] & 0xC0) == 0x80
        let ula = (b[0] & 0xFE) == 0xFC
        return loopback || linkLocal || ula
    }
}
