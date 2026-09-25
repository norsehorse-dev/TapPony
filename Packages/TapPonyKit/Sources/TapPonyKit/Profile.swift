import Foundation

/// The profile document, schema version 1. PROFILE_SCHEMA.md section 1.
/// Read and written with the kit's own ordered JSON codec so the file shape is
/// identical to the Android core's.
public struct Profile: Equatable, Identifiable {
    public static let schemaVersion = 1
    public static let methods = ["GET", "POST", "PUT", "PATCH", "DELETE"]

    public var schema: Int = Profile.schemaVersion
    public var id: String
    public var name: String
    public var request: RequestSpec = RequestSpec()
    public var auth: Auth = .none
    public var signing: SigningSpec = SigningSpec()
    public var tag: TagSpec = TagSpec()
    public var after: AfterSpec = AfterSpec()

    public init(id: String, name: String, request: RequestSpec = RequestSpec(), auth: Auth = .none,
                signing: SigningSpec = SigningSpec(), tag: TagSpec = TagSpec(), after: AfterSpec = AfterSpec()) {
        self.id = id; self.name = name; self.request = request; self.auth = auth
        self.signing = signing; self.tag = tag; self.after = after
    }
}

public struct Header: Equatable, Hashable {
    public var name: String
    public var value: String
    public var secret: Bool
    public init(_ name: String, _ value: String, secret: Bool = false) { self.name = name; self.value = value; self.secret = secret }
}

public struct FormField: Equatable, Hashable {
    public var name: String
    public var value: String
    public init(_ name: String, _ value: String) { self.name = name; self.value = value }
}

public enum BodyType: String, CaseIterable {
    case json, form, raw, none
}

public struct BodySpec: Equatable {
    public var type: BodyType = .json
    public var template: String = ""
    public var contentType: String? = nil
    public var fields: [FormField] = []
    public init(type: BodyType = .json, template: String = "", contentType: String? = nil, fields: [FormField] = []) {
        self.type = type; self.template = template; self.contentType = contentType; self.fields = fields
    }
}

public struct RequestSpec: Equatable {
    public var method: String = "POST"
    public var url: String = ""
    public var headers: [Header] = []
    public var body: BodySpec = BodySpec()
    public var timeoutSeconds: Int = 15
    public var followRedirects: Bool = false
    public var allowLocalHttp: Bool = false
    public init(method: String = "POST", url: String = "", headers: [Header] = [], body: BodySpec = BodySpec(),
                timeoutSeconds: Int = 15, followRedirects: Bool = false, allowLocalHttp: Bool = false) {
        self.method = method; self.url = url; self.headers = headers; self.body = body
        self.timeoutSeconds = timeoutSeconds; self.followRedirects = followRedirects; self.allowLocalHttp = allowLocalHttp
    }
}

public enum Auth: Equatable {
    case none
    case bearer(secret: String)
    case basic(username: String, passwordSecret: String)
    case apiKey(header: String, secret: String)
}

public struct SigningSpec: Equatable {
    public var enabled: Bool = false
    public var secret: String? = nil
    public init(enabled: Bool = false, secret: String? = nil) { self.enabled = enabled; self.secret = secret }
}

public struct TagSpec: Equatable {
    public var technologies: [String] = ["iso14443", "iso15693", "felica"]
    public var extendedReads: Bool = true
    public var requireNdef: Bool = false
    public init(technologies: [String] = ["iso14443", "iso15693", "felica"], extendedReads: Bool = true, requireNdef: Bool = false) {
        self.technologies = technologies; self.extendedReads = extendedReads; self.requireNdef = requireNdef
    }
}

public struct AfterSpec: Equatable {
    public var messageField: String? = nil
    public var keepBodies: Bool = false
    public var sound: Bool = true
    public var haptic: Bool = true
    public init(messageField: String? = nil, keepBodies: Bool = false, sound: Bool = true, haptic: Bool = true) {
        self.messageField = messageField; self.keepBodies = keepBodies; self.sound = sound; self.haptic = haptic
    }
}

public struct ProfileError: Error, Equatable {
    public let code: String
    public init(_ code: String) { self.code = code }
}

public enum ProfileCodec {

    public static func decode(_ text: String) throws -> Profile {
        let root: JSONValue
        do { root = try JSON.parse(text) } catch { throw ProfileError("invalidJson") }
        return try fromJSON(root)
    }

    /// Kotlin's `(x as? Number)?.toInt()`: any JSON number, Long narrowed by
    /// truncating bits, Double truncated toward zero and saturated, NaN as 0.
    private static func numberToInt(_ v: JSONValue?) -> Int? {
        switch v {
        case .int(let i)?: return Int(Int32(truncatingIfNeeded: i))
        case .double(let d)?:
            if d.isNaN { return 0 }
            if d >= 2147483647 { return Int(Int32.max) }
            if d <= -2147483648 { return Int(Int32.min) }
            return Int(d)
        default: return nil
        }
    }

    public static func fromJSON(_ m: JSONValue) throws -> Profile {
        guard case .object = m else { throw ProfileError("notAnObject") }
        guard let schema = numberToInt(m["schema"]) else { throw ProfileError("missingSchema") }
        if schema > Profile.schemaVersion { throw ProfileError("newerSchema") }
        guard let id = m["id"]?.string else { throw ProfileError("missingId") }
        guard let name = m["name"]?.string else { throw ProfileError("missingName") }
        let r = m["request"] ?? .object([])
        let b = r["body"] ?? .object([])
        let method = r["method"]?.string ?? "POST"
        if !Profile.methods.contains(method) { throw ProfileError("badMethod") }
        guard let bodyType = BodyType(rawValue: b["type"]?.string ?? "none") else { throw ProfileError("badBodyType") }
        let request = RequestSpec(
            method: method,
            url: r["url"]?.string ?? "",
            headers: (r["headers"]?.array ?? []).map { Header($0["name"]?.string ?? "", $0["value"]?.string ?? "", secret: $0["secret"]?.bool ?? false) },
            body: BodySpec(
                type: bodyType,
                template: b["template"]?.string ?? "",
                contentType: b["contentType"]?.string,
                fields: (b["fields"]?.array ?? []).map { FormField($0["name"]?.string ?? "", $0["value"]?.string ?? "") }
            ),
            timeoutSeconds: min(max(numberToInt(r["timeoutSeconds"]) ?? 15, 1), 120),
            followRedirects: r["followRedirects"]?.bool ?? false,
            allowLocalHttp: r["allowLocalHttp"]?.bool ?? false
        )
        let a = m["auth"]
        let auth: Auth
        switch a?["type"]?.string ?? "none" {
        case "none": auth = .none
        case "bearer":
            guard let s = a?["secret"]?.string else { throw ProfileError("badAuth") }
            auth = .bearer(secret: s)
        case "basic":
            guard let u = a?["username"]?.string, let p = a?["passwordSecret"]?.string else { throw ProfileError("badAuth") }
            auth = .basic(username: u, passwordSecret: p)
        case "apiKey":
            guard let h = a?["header"]?.string, let s = a?["secret"]?.string else { throw ProfileError("badAuth") }
            auth = .apiKey(header: h, secret: s)
        default: throw ProfileError("badAuth")
        }
        let s = m["signing"], t = m["tag"], af = m["after"]
        var p = Profile(
            id: id, name: name, request: request, auth: auth,
            signing: SigningSpec(enabled: s?["enabled"]?.bool ?? false, secret: s?["secret"]?.string),
            tag: TagSpec(
                technologies: t?["technologies"]?.array?.compactMap { $0.string } ?? TagSpec().technologies,
                extendedReads: t?["extendedReads"]?.bool ?? true,
                requireNdef: t?["requireNdef"]?.bool ?? false
            ),
            after: AfterSpec(
                messageField: af?["messageField"]?.string,
                keepBodies: af?["keepBodies"]?.bool ?? false,
                sound: af?["sound"]?.bool ?? true,
                haptic: af?["haptic"]?.bool ?? true
            )
        )
        p.schema = schema
        return p
    }

    private static func str(_ s: String?) -> JSONValue { s.map { .string($0) } ?? .null }

    public static func toJSON(_ p: Profile) -> JSONValue {
        let authValue: JSONValue
        switch p.auth {
        case .none: authValue = .object([JSONMember("type", .string("none"))])
        case .bearer(let s): authValue = .object([JSONMember("type", .string("bearer")), JSONMember("secret", .string(s))])
        case .basic(let u, let ps):
            authValue = .object([JSONMember("type", .string("basic")), JSONMember("username", .string(u)), JSONMember("passwordSecret", .string(ps))])
        case .apiKey(let h, let s):
            authValue = .object([JSONMember("type", .string("apiKey")), JSONMember("header", .string(h)), JSONMember("secret", .string(s))])
        }
        return .object([
            JSONMember("schema", .int(Int64(p.schema))),
            JSONMember("id", .string(p.id)),
            JSONMember("name", .string(p.name)),
            JSONMember("request", .object([
                JSONMember("method", .string(p.request.method)),
                JSONMember("url", .string(p.request.url)),
                JSONMember("headers", .array(p.request.headers.map {
                    .object([JSONMember("name", .string($0.name)), JSONMember("value", .string($0.value)), JSONMember("secret", .bool($0.secret))])
                })),
                JSONMember("body", .object([
                    JSONMember("type", .string(p.request.body.type.rawValue)),
                    JSONMember("template", .string(p.request.body.template)),
                    JSONMember("contentType", str(p.request.body.contentType)),
                    JSONMember("fields", .array(p.request.body.fields.map {
                        .object([JSONMember("name", .string($0.name)), JSONMember("value", .string($0.value))])
                    })),
                ])),
                JSONMember("timeoutSeconds", .int(Int64(p.request.timeoutSeconds))),
                JSONMember("followRedirects", .bool(p.request.followRedirects)),
                JSONMember("allowLocalHttp", .bool(p.request.allowLocalHttp)),
            ])),
            JSONMember("auth", authValue),
            JSONMember("signing", .object([JSONMember("enabled", .bool(p.signing.enabled)), JSONMember("secret", str(p.signing.secret))])),
            JSONMember("tag", .object([
                JSONMember("technologies", .array(p.tag.technologies.map { .string($0) })),
                JSONMember("extendedReads", .bool(p.tag.extendedReads)),
                JSONMember("requireNdef", .bool(p.tag.requireNdef)),
            ])),
            JSONMember("after", .object([
                JSONMember("messageField", str(p.after.messageField)),
                JSONMember("keepBodies", .bool(p.after.keepBodies)),
                JSONMember("sound", .bool(p.after.sound)),
                JSONMember("haptic", .bool(p.after.haptic)),
            ])),
        ])
    }

    public static func encode(_ p: Profile) -> String { JSON.write(toJSON(p)) }
}
