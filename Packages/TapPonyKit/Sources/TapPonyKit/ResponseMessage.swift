import Foundation

/// Picks the piece of a server reply shown after a scan. PROFILE_SCHEMA.md
/// section 11. Mirrors com.tappony.core.ResponseMessage.
public enum ResponseMessage {

    public static let cap = 200

    public static func extract(field: String?, headers: [(String, String)], body: String?) -> String? {
        guard let field, !field.isEmpty else { return nil }
        if field.hasPrefix("header:") {
            let name = String(field.dropFirst("header:".count)).lowercased()
            guard let v = headers.first(where: { $0.0.lowercased() == name })?.1 else { return nil }
            return Encoding.capCodePoints(v, cap)
        }
        guard field.hasPrefix("json:"), let body else { return nil }
        let path = String(field.dropFirst("json:".count))
        guard var cur = try? JSON.parse(body) else { return nil }
        if !path.isEmpty {
            for seg in path.components(separatedBy: ".") {
                switch cur {
                case .object(let members):
                    guard let m = members.first(where: { $0.key == seg }) else { return nil }
                    cur = m.value
                case .array(let items):
                    guard isIndex(seg), seg.count < 10, let i = Int(seg), i < items.count else { return nil }
                    cur = items[i]
                default:
                    return nil
                }
            }
        }
        let text: String
        switch cur {
        case .null: return nil
        case .string(let s): text = s
        case .bool(let b): text = b ? "true" : "false"
        case .int(let i): text = String(i)
        case .double(let d): text = (d == d.rounded() && abs(d) < 1e15) ? String(Int64(d)) : String(d)
        case .array, .object: text = JSON.write(cur)
        }
        return Encoding.capCodePoints(text, cap)
    }

    private static func isIndex(_ s: String) -> Bool {
        guard let first = s.unicodeScalars.first, !s.isEmpty else { return false }
        if !s.unicodeScalars.allSatisfy({ $0.value >= 0x30 && $0.value <= 0x39 }) { return false }
        return !(first == "0" && s.unicodeScalars.count > 1)
    }
}
