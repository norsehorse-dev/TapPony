import Foundation

/// A request ready for URLSession. Body is nil when none is sent.
public struct PreparedRequest: Equatable {
    public var method: String
    public var url: String
    public var headers: [(String, String)]
    public var body: String?
    public var timeoutSeconds: Int
    public var followRedirects: Bool

    public static func == (a: PreparedRequest, b: PreparedRequest) -> Bool {
        a.method == b.method && a.url == b.url && a.body == b.body && a.timeoutSeconds == b.timeoutSeconds &&
            a.followRedirects == b.followRedirects && a.headers.count == b.headers.count &&
            zip(a.headers, b.headers).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 }
    }
}

public struct RequestError: Error, Equatable, CustomStringConvertible {
    public let code: String
    public init(_ code: String) { self.code = code }
    public var description: String { code }
}

/// Request assembly, PROFILE_SCHEMA.md section 9. Mirrors com.tappony.core.RequestBuilder;
/// pinned by fixtures/request_vectors.json.
public enum RequestBuilder {

    public static let mask = "••••"
    private static let token = Pattern("[!#$%&'*+\\-.^_`|~0-9A-Za-z]+")
    private static let defaultContentType: [BodyType: String] = [
        .json: "application/json",
        .form: "application/x-www-form-urlencoded",
        .raw: "text/plain; charset=utf-8",
    ]

    public static func build(_ profile: Profile, variables: [String: String], secrets: [String: String], sendUnix: Int64) throws -> PreparedRequest {
        let req = profile.request
        guard Profile.methods.contains(req.method) else { throw RequestError("badMethod") }
        let tpl = HostPolicy.checkTemplate(req.url)
        guard tpl == "ok" else { throw RequestError("urlTemplate:\(tpl)") }
        let url = try render(req.url, .url, variables, secrets)
        let policy = HostPolicy.check(url, allowLocalHttp: req.allowLocalHttp)
        guard policy.allowed else { throw RequestError("hostPolicy:\(policy.detail)") }

        var headers: [(String, String)] = []
        for h in req.headers {
            guard token.matches(h.name) else { throw RequestError("badHeaderName") }
            headers.append((h.name, try render(h.value, .header, variables, secrets)))
        }
        func secret(_ name: String) throws -> String {
            guard let v = secrets[name] else { throw RequestError("template:unknownSecret") }
            return v
        }
        switch profile.auth {
        case .none: break
        case .bearer(let s): headers.append(("Authorization", "Bearer " + (try secret(s))))
        case .basic(let u, let ps):
            headers.append(("Authorization", "Basic " + Encoding.base64(Array((u + ":" + (try secret(ps))).utf8))))
        case .apiKey(let h, let s):
            guard token.matches(h) else { throw RequestError("badHeaderName") }
            headers.append((h, try secret(s)))
        }
        headers = headers.map { ($0.0, Template.stripHeader($0.1)) }

        var body: String? = nil
        let spec = req.body
        if req.method != "GET" && req.method != "DELETE" && spec.type != .none {
            switch spec.type {
            case .json: body = try render(spec.template, .json, variables, secrets)
            case .raw: body = try render(spec.template, .raw, variables, secrets)
            case .form:
                body = try spec.fields.map { try render($0.name, .form, variables, secrets) + "=" + render($0.value, .form, variables, secrets) }
                    .joined(separator: "&")
            case .none: body = nil
            }
            if !headers.contains(where: { $0.0.lowercased() == "content-type" }) {
                headers.append(("Content-Type", spec.contentType ?? defaultContentType[spec.type]!))
            }
        }
        if profile.signing.enabled {
            guard let name = profile.signing.secret else { throw RequestError("template:unknownSecret") }
            let key = try secret(name)
            let ts = String(sendUnix)
            headers.append((Signing.timestampHeader, ts))
            headers.append((Signing.nonceHeader, variables["nonce"] ?? ""))
            headers.append((Signing.signatureHeader, Signing.signature(key: key, timestamp: ts, body: body ?? "")))
        }
        return PreparedRequest(method: req.method, url: url, headers: headers, body: body,
                               timeoutSeconds: req.timeoutSeconds, followRedirects: req.followRedirects)
    }

    private static func render(_ t: String, _ c: TemplateContext, _ v: [String: String], _ s: [String: String]) throws -> String {
        do {
            return try Template.render(t, context: c, variables: v, secrets: s)
        } catch let e as TemplateError {
            throw RequestError("template:\(e.code)")
        }
    }

    public static func requiredSecrets(_ profile: Profile) -> Set<String> {
        var out = Set<String>()
        func scan(_ t: String) { if let s = try? Template.referencedSecrets(t) { out.formUnion(s) } }
        scan(profile.request.url)
        profile.request.headers.forEach { scan($0.value) }
        scan(profile.request.body.template)
        profile.request.body.fields.forEach { scan($0.name); scan($0.value) }
        switch profile.auth {
        case .bearer(let s): out.insert(s)
        case .basic(_, let ps): out.insert(ps)
        case .apiKey(_, let s): out.insert(s)
        case .none: break
        }
        if profile.signing.enabled, let s = profile.signing.secret { out.insert(s) }
        return out
    }

    /// Secrets replaced for the Test view and history.
    public static func masked(_ r: PreparedRequest, secrets: [String: String]) -> PreparedRequest {
        // Longest first by UTF-16 length (Kotlin's String.length); exact-code-unit
        // replacement like Kotlin's String.replace.
        let values = secrets.values.filter { !$0.isEmpty }.sorted { $0.utf16.count > $1.utf16.count }
        func maskString(_ s: String) -> String {
            var out = s
            for v in values { out = out.replacingOccurrences(of: v, with: mask, options: .literal) }
            for v in values { out = out.replacingOccurrences(of: Encoding.percent(v), with: mask, options: .literal) }
            return out
        }
        var copy = r
        copy.url = maskString(r.url)
        copy.headers = r.headers.map { n, v in
            if n.lowercased() == "authorization" {
                let scheme = v.unicodeScalars.firstIndex(of: " ").map { String(String.UnicodeScalarView(v.unicodeScalars[..<$0])) } ?? v
                return (n, scheme + " " + mask)
            }
            return (n, maskString(v))
        }
        copy.body = r.body.map { maskString($0) }
        return copy
    }
}
