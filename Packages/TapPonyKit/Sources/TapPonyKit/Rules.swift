import Foundation

public struct RuleMatch: Equatable {
    public var field: String
    public var op: String
    public var value: String
    public init(field: String, op: String, value: String) { self.field = field; self.op = op; self.value = value }
}

public struct Rule: Equatable, Identifiable {
    public var id: String
    public var name: String
    public var enabled: Bool
    public var match: RuleMatch
    public var profiles: [String]
    public init(id: String, name: String, enabled: Bool = true, match: RuleMatch, profiles: [String]) {
        self.id = id; self.name = name; self.enabled = enabled; self.match = match; self.profiles = profiles
    }
}

public struct RuleSet: Equatable {
    public static let unmatchedActive = "active"
    public static let unmatchedIgnore = "ignore"

    public var schema: Int = 1
    public var enabled: Bool = false
    public var unmatched: String = RuleSet.unmatchedActive
    public var rules: [Rule] = []
    public init(schema: Int = 1, enabled: Bool = false, unmatched: String = RuleSet.unmatchedActive, rules: [Rule] = []) {
        self.schema = schema; self.enabled = enabled; self.unmatched = unmatched; self.rules = rules
    }
}

/// Where a scan goes. `ruleId` nil means no rule decided.
public struct Route: Equatable {
    public var profileIds: [String]
    public var ruleId: String?
}

/// The rules engine, PROFILE_SCHEMA.md section 14. Mirrors com.tappony.core.Rules.
public enum Rules {

    public static let fields = ["uid", "tag_type", "chip", "manufacturer", "payload", "ndef_text", "ndef_uri"]
    public static let ops = ["equals", "prefix", "contains", "regex"]

    public static func error(_ rule: Rule) -> String? {
        if !fields.contains(rule.match.field) { return "unknownField" }
        if !ops.contains(rule.match.op) { return "unknownOp" }
        if rule.match.op == "regex" && compile(rule.match.value) == nil { return "badRegex" }
        if rule.profiles.isEmpty { return "noProfiles" }
        return nil
    }

    /// Only \n ends a line, as with java.util.regex UNIX_LINES. ICU refuses an
    /// empty pattern, which java.util.regex accepts, so "" becomes an empty group.
    private static func compile(_ p: String) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: p.isEmpty ? "(?:)" : p, options: [.useUnixLineSeparators])
    }

    private static func normUid(_ s: String) -> String {
        Encoding.asciiUpper(String(String.UnicodeScalarView(s.unicodeScalars.filter { $0 != ":" && $0 != "-" && $0 != " " })))
    }

    public static func matches(_ rule: Rule, _ variables: [String: String]) -> Bool {
        guard rule.enabled, error(rule) == nil else { return false }
        let m = rule.match
        let have = variables[m.field] ?? ""
        if m.op == "regex" {
            guard let re = compile(m.value) else { return false }
            return re.firstMatch(in: have, range: NSRange(have.startIndex..., in: have)) != nil
        }
        let h: String
        let w: String
        if m.field == "uid" {
            h = normUid(have); w = normUid(m.value)
        } else {
            h = Encoding.asciiLower(have); w = Encoding.asciiLower(m.value)
        }
        let hu = Array(h.unicodeScalars), wu = Array(w.unicodeScalars)
        switch m.op {
        case "equals": return hu == wu
        case "prefix": return hu.starts(with: wu)
        default:
            if wu.isEmpty { return true }
            if wu.count > hu.count { return false }
            for i in 0...(hu.count - wu.count) where Array(hu[i..<(i + wu.count)]) == wu { return true }
            return false
        }
    }

    public static func route(_ set: RuleSet, variables: [String: String], activeProfileId: String?) -> Route {
        let fallback = activeProfileId.map { [$0] } ?? []
        guard set.enabled else { return Route(profileIds: fallback, ruleId: nil) }
        for r in set.rules where matches(r, variables) {
            var seen = Set<String>()
            return Route(profileIds: r.profiles.filter { seen.insert($0).inserted }, ruleId: r.id)
        }
        if set.unmatched == RuleSet.unmatchedIgnore { return Route(profileIds: [], ruleId: nil) }
        return Route(profileIds: fallback, ruleId: nil)
    }

    // MARK: codec

    public static func decode(_ text: String) throws -> RuleSet {
        let root: JSONValue
        do { root = try JSON.parse(text) } catch { throw ProfileError("invalidJson") }
        guard case .object = root else { throw ProfileError("notAnObject") }
        return try fromJSON(root)
    }

    public static func fromJSON(_ m: JSONValue) throws -> RuleSet {
        let schema = ProfileCodec.numberToInt(m["schema"]) ?? 1
        if schema > 1 { throw ProfileError("newerSchema") }
        let rules: [Rule] = (m["rules"]?.array ?? []).compactMap { r in
            guard case .object = r, let id = r["id"]?.string else { return nil }
            let mm = r["match"]
            return Rule(id: id, name: r["name"]?.string ?? "", enabled: r["enabled"]?.bool ?? true,
                        match: RuleMatch(field: mm?["field"]?.string ?? "", op: mm?["op"]?.string ?? "", value: mm?["value"]?.string ?? ""),
                        profiles: (r["profiles"]?.array ?? []).compactMap { $0.string })
        }
        return RuleSet(schema: schema, enabled: m["enabled"]?.bool ?? false,
                       unmatched: m["unmatched"]?.string ?? RuleSet.unmatchedActive, rules: rules)
    }

    public static func toJSON(_ s: RuleSet) -> JSONValue {
        .object([
            JSONMember("schema", .int(Int64(s.schema))),
            JSONMember("enabled", .bool(s.enabled)),
            JSONMember("unmatched", .string(s.unmatched)),
            JSONMember("rules", .array(s.rules.map { r in
                .object([
                    JSONMember("id", .string(r.id)),
                    JSONMember("name", .string(r.name)),
                    JSONMember("enabled", .bool(r.enabled)),
                    JSONMember("match", .object([
                        JSONMember("field", .string(r.match.field)),
                        JSONMember("op", .string(r.match.op)),
                        JSONMember("value", .string(r.match.value)),
                    ])),
                    JSONMember("profiles", .array(r.profiles.map { .string($0) })),
                ])
            })),
        ])
    }

    public static func encode(_ s: RuleSet) -> String { JSON.write(toJSON(s)) }
}
