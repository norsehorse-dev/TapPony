import Foundation

/// Byte and text encodings. Mirrors com.tappony.core.Encoding.
public enum Encoding {

    private static let lower = Array("0123456789abcdef".utf8)
    private static let upper = Array("0123456789ABCDEF".utf8)

    static func hex2(_ v: Int) -> String {
        String(decoding: [lower[(v >> 4) & 0xF], lower[v & 0xF]], as: UTF8.self)
    }

    public static func hexUpper(_ b: [UInt8]) -> String {
        var out: [UInt8] = []
        out.reserveCapacity(b.count * 2)
        for x in b {
            out.append(upper[Int(x >> 4)])
            out.append(upper[Int(x & 0xF)])
        }
        return String(decoding: out, as: UTF8.self)
    }

    public static func hexLower(_ b: [UInt8]) -> String { hexUpper(b).lowercased() }

    private static func nibble(_ c: UInt8) -> UInt8? {
        switch c {
        case 0x30...0x39: return c - 0x30
        case 0x61...0x66: return c - 0x61 + 10
        case 0x41...0x46: return c - 0x41 + 10
        default: return nil
        }
    }

    /// Strict hex, no separators. Nil when not an even count of ASCII hex digits.
    public static func parseHex(_ s: String) -> [UInt8]? {
        let u = Array(s.utf8)
        guard u.count % 2 == 0 else { return nil }
        var out = [UInt8]()
        out.reserveCapacity(u.count / 2)
        var i = 0
        while i < u.count {
            guard let hi = nibble(u[i]), let lo = nibble(u[i + 1]) else { return nil }
            out.append(hi << 4 | lo)
            i += 2
        }
        return out
    }

    /// Hex with optional ':', '-' or ' ' separators; non-empty and even. Nil otherwise.
    public static func parseLooseHex(_ s: String) -> [UInt8]? {
        let t = String(s.unicodeScalars.filter { $0 != ":" && $0 != "-" && $0 != " " })
        guard !t.isEmpty else { return nil }
        return parseHex(t)
    }

    public static func colon(_ b: [UInt8]) -> String { b.map { hexUpper([$0]) }.joined(separator: ":") }

    /// Unsigned big-endian bytes as a decimal string, any length.
    public static func decimal(_ b: [UInt8]) -> String {
        if b.isEmpty { return "" }
        var num = b.drop(while: { $0 == 0 }).map { $0 }
        if num.isEmpty { return "0" }
        var digits: [UInt8] = []
        while !num.isEmpty {
            var rem = 0
            var next: [UInt8] = []
            next.reserveCapacity(num.count)
            for byte in num {
                let cur = rem * 256 + Int(byte)
                let q = cur / 10
                rem = cur % 10
                if !(next.isEmpty && q == 0) { next.append(UInt8(q)) }
            }
            digits.append(UInt8(rem) + 0x30)
            num = next
        }
        return String(decoding: digits.reversed(), as: UTF8.self)
    }

    public static func base64(_ b: [UInt8]) -> String { Data(b).base64EncodedString() }

    private static func isUnreserved(_ v: UInt8) -> Bool {
        (v >= 0x41 && v <= 0x5A) || (v >= 0x61 && v <= 0x7A) || (v >= 0x30 && v <= 0x39) ||
            v == 0x2D || v == 0x2E || v == 0x5F || v == 0x7E
    }

    /// Percent-encode everything but RFC 3986 unreserved, over UTF-8, uppercase hex.
    public static func percent(_ s: String) -> String {
        var out: [UInt8] = []
        for v in s.utf8 {
            if isUnreserved(v) { out.append(v) } else {
                out.append(0x25); out.append(upper[Int(v >> 4)]); out.append(upper[Int(v & 0xF)])
            }
        }
        return String(decoding: out, as: UTF8.self)
    }

    /// application/x-www-form-urlencoded.
    public static func form(_ s: String) -> String {
        var out: [UInt8] = []
        for v in s.utf8 {
            if isUnreserved(v) { out.append(v) } else if v == 0x20 { out.append(0x2B) } else {
                out.append(0x25); out.append(upper[Int(v >> 4)]); out.append(upper[Int(v & 0xF)])
            }
        }
        return String(decoding: out, as: UTF8.self)
    }

    public static func asciiLower(_ s: String) -> String {
        String(String.UnicodeScalarView(s.unicodeScalars.map { ($0.value >= 0x41 && $0.value <= 0x5A) ? Unicode.Scalar($0.value + 32)! : $0 }))
    }

    public static func asciiUpper(_ s: String) -> String {
        String(String.UnicodeScalarView(s.unicodeScalars.map { ($0.value >= 0x61 && $0.value <= 0x7A) ? Unicode.Scalar($0.value - 32)! : $0 }))
    }

    public static func trimTemplateWS(_ s: String) -> String {
        let ws: Set<Unicode.Scalar> = [" ", "\t", "\r", "\n"]
        let scalars = Array(s.unicodeScalars)
        var a = 0
        var b = scalars.count
        while a < b, ws.contains(scalars[a]) { a += 1 }
        while b > a, ws.contains(scalars[b - 1]) { b -= 1 }
        return String(String.UnicodeScalarView(scalars[a..<b]))
    }

    /// Substring by Unicode code point indices, clamped.
    public static func sliceCodePoints(_ s: String, from: Int, to: Int?) -> String {
        let scalars = Array(s.unicodeScalars)
        let n = scalars.count
        let a = min(max(from, 0), n)
        let b = min(max(to ?? n, a), n)
        return String(String.UnicodeScalarView(scalars[a..<b]))
    }

    public static func capCodePoints(_ s: String, _ max: Int) -> String {
        if s.unicodeScalars.count <= max { return s }
        return String(String.UnicodeScalarView(s.unicodeScalars.prefix(max)))
    }

    /// Bytes of a string as UTF-8.
    static func utf8(_ s: String) -> [UInt8] { Array(s.utf8) }
}
