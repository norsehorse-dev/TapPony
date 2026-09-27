import Foundation

/// One tag the user has named. PROFILE_SCHEMA.md section 16.
public struct TagEntry: Equatable, Hashable, Identifiable {
    /// Stable for lists: the token when there is one, else the UID.
    public var id: String { token.isEmpty ? "uid:" + uid : "k:" + token }
    public var uid: String
    public var label: String
    public var notes: String
    public var profile: String?
    public var token: String
    public init(uid: String, label: String, notes: String = "", profile: String? = nil, token: String = "") {
        self.uid = uid; self.label = label; self.notes = notes; self.profile = profile; self.token = token
    }
}

public struct TagRegistry: Equatable {
    public var schema: Int = 1
    public var tags: [TagEntry] = []
    public init(schema: Int = 1, tags: [TagEntry] = []) { self.schema = schema; self.tags = tags }
}

/// The tags registry and launch links, pinned by fixtures/tags_vectors.json.
/// Mirrors com.tappony.core.Tags.
public enum Tags {

    public static let launchPrefix = "https://tappony.app/t/?k="

    public static func normUid(_ s: String) -> String {
        Encoding.asciiUpper(String(String.UnicodeScalarView(s.unicodeScalars.filter { $0 != ":" && $0 != "-" && $0 != " " })))
    }

    /// Base64url of 16 random bytes, no padding: 22 characters.
    public static func token(_ raw16: [UInt8]) -> String {
        precondition(raw16.count == 16)
        return Data(raw16).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// A fresh token from the system's secure random source.
    public static func newToken() -> String {
        var g = SystemRandomNumberGenerator()
        return token((0..<16).map { _ in UInt8.random(in: 0...255, using: &g) })
    }

    public static func link(_ token: String) -> String { launchPrefix + token }

    public static func isToken(_ s: String) -> Bool {
        let n = s.unicodeScalars.count
        guard n >= 16, n <= 64 else { return false }
        return s.unicodeScalars.allSatisfy {
            ($0.value >= 0x30 && $0.value <= 0x39) || ($0.value >= 0x41 && $0.value <= 0x5A) ||
                ($0.value >= 0x61 && $0.value <= 0x7A) || $0 == "_" || $0 == "-"
        }
    }

    /// Token first (it names the tag even when the UID can't), then the UID unless it's random or empty.
    public static func find(_ reg: TagRegistry, uid: String, token: String, randomUid: Bool) -> TagEntry? {
        if !token.isEmpty, let t = reg.tags.first(where: { !$0.token.isEmpty && $0.token == token }) { return t }
        let u = normUid(uid)
        if !u.isEmpty, !randomUid, let t = reg.tags.first(where: { !$0.uid.isEmpty && $0.uid == u }) { return t }
        return nil
    }

    /// The registry entry for a scan's variables.
    public static func find(_ reg: TagRegistry, variables v: [String: String]) -> TagEntry? {
        find(reg, uid: v["uid"] ?? "", token: v["token"] ?? "", randomUid: v["random_uid"] == "true")
    }

    public static func decode(_ text: String) throws -> TagRegistry {
        let root: JSONValue
        do { root = try JSON.parse(text) } catch { throw ProfileError("invalidJson") }
        guard case .object = root else { throw ProfileError("notAnObject") }
        return try fromJSON(root)
    }

    public static func fromJSON(_ m: JSONValue) throws -> TagRegistry {
        let schema = ProfileCodec.numberToInt(m["schema"]) ?? 1
        if schema > 1 { throw ProfileError("newerSchema") }
        let tags: [TagEntry] = (m["tags"]?.array ?? []).compactMap { t in
            guard case .object = t else { return nil }
            let p = t["profile"]?.string
            return TagEntry(uid: normUid(t["uid"]?.string ?? ""), label: t["label"]?.string ?? "", notes: t["notes"]?.string ?? "",
                            profile: (p?.isEmpty ?? true) ? nil : p, token: t["token"]?.string ?? "")
        }
        return TagRegistry(tags: tags)
    }

    public static func toJSON(_ r: TagRegistry) -> JSONValue {
        .object([
            JSONMember("schema", .int(1)),
            JSONMember("tags", .array(r.tags.map { t in
                .object([
                    JSONMember("uid", .string(t.uid)),
                    JSONMember("label", .string(t.label)),
                    JSONMember("notes", .string(t.notes)),
                    JSONMember("profile", t.profile.map { JSONValue.string($0) } ?? JSONValue.null),
                    JSONMember("token", .string(t.token)),
                ])
            })),
        ])
    }

    public static func encode(_ r: TagRegistry) -> String { JSON.write(toJSON(r)) }

    /// The reading for a launch that arrived without a tag read (section 10):
    /// no identifier, tag type launch_link, and the delivered NDEF records, or
    /// one URI record holding the link when only the URL arrived.
    public static func launchReading(link: String, records: [NdefRecord] = []) -> TagReading {
        var r = TagReading(family: .mifare, tagType: "launch_link", identifier: [])
        r.ndef = records.isEmpty ? [Ndef.uriRecord(link)] : records
        return r
    }
}
