import Foundation
import Security
import TapPonyKit

/// What the Scan tab shows after a tag.
struct ScanOutcome: Equatable, Identifiable {
    let id = UUID()
    var scanTimeMs: Int64
    var profileId: String
    var profileName: String
    var uid: String
    var chip: String
    var tagType: String
    var randomUid: Bool
    var request: PreparedRequest?
    var result: SendResult?
    var buildError: String?
    /// The piece of the reply picked by the profile's messageField, if any.
    var message: String? = nil
    /// Got no response and went into the offline queue instead of history.
    var queued: Bool = false
    /// The profile's success or failure text, rendered (PROFILE_SCHEMA.md section 15).
    var resultText: String? = nil

    var outcome: String { HistoryCsv.outcome(buildError: buildError, status: result?.status) }

    /// Built and sent, but no HTTP response came back (a transport failure, not a bad URL or header).
    var isNoResponse: Bool {
        buildError == nil && result != nil && result?.status == nil && result?.transportFailure == true
    }

    /// History entry; bodies only when the profile keeps them, and never secrets (the request is already masked).
    func historyEntry(keepBodies: Bool) -> HistoryEntry {
        HistoryEntry(
            timeMs: scanTimeMs,
            profileId: profileId,
            profileName: profileName,
            uid: uid,
            chip: chip,
            tagType: tagType,
            outcome: outcome,
            status: result?.status,
            latencyMs: result?.latencyMs,
            error: buildError ?? result?.error ?? "",
            message: message,
            request: request.map { "\($0.method) \($0.url)" } ?? "",
            requestBody: keepBodies ? request?.body.map { String($0.prefix(HistoryStore.keptBodyChars)) } : nil,
            responseBody: keepBodies ? result?.responseBody.map { String($0.prefix(HistoryStore.keptBodyChars)) } : nil
        )
    }

    static func == (a: ScanOutcome, b: ScanOutcome) -> Bool { a.id == b.id }
}

/// The scan pipeline, same shape as Android's ScanEngine: reading -> variables
/// -> request (TapPonyKit) -> send (URLSession). The network call never runs
/// inside the NFC read; the read finishes first.
@MainActor
final class ScanEngine {
    let settings: AppSettings
    private let sender = Sender()

    init(settings: AppSettings) { self.settings = settings }

    static func nonce() -> String {
        var b = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, b.count, &b)
        return Encoding.hexLower(b)
    }

    static func nowMs() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

    func context(_ p: Profile, scanTimeMs: Int64, test: Bool = false, tagLabel: String = "") -> SendContext {
        SendContext(
            scanTimeMs: scanTimeMs,
            sendTimeMs: Self.nowMs(),
            timeZone: TimeZone.current.identifier,
            profileName: p.name,
            profileId: p.id,
            deviceLabel: settings.deviceLabel,
            platform: "ios",
            nonce: Self.nonce(),
            seq: test ? 0 : settings.nextSeq(p.id),
            tagLabel: tagLabel
        )
    }

    /// A real scan: send, then either queue it (no response, profile opted in)
    /// or record it in history.
    func run(_ p: Profile, reading: TagReading, scanTimeMs: Int64, history: HistoryStore?, queue: OfflineQueue?,
             tagLabel: String = "") async -> ScanOutcome {
        let ctx = context(p, scanTimeMs: scanTimeMs, tagLabel: tagLabel)
        let vars = Variables.build(reading, ctx)
        var outcome = await send(p, vars, scanTimeMs: ctx.scanTimeMs, sendTimeMs: ctx.sendTimeMs)
        if let queue, p.after.queueOffline, Entitlements.offlineQueue, outcome.isNoResponse,
           queue.enqueue(p, scanTimeMs: scanTimeMs, variables: vars, error: outcome.result?.error ?? "") {
            outcome.queued = true
            outcome.resultText = nil
            return outcome
        }
        history?.record(outcome.historyEntry(keepBodies: p.after.keepBodies))
        if outcome.result?.status != nil { queue?.kick() }
        return outcome
    }

    /// Sends a queued scan again (PROFILE_SCHEMA.md section 13): the stored
    /// variables with {sent_at} set to now, rebuilt against the current profile
    /// and secrets, signed with the real send time.
    func resend(_ p: Profile, storedVariables: [String: String], scanTimeMs: Int64) async -> ScanOutcome {
        let now = Self.nowMs()
        var vars = storedVariables
        vars["sent_at"] = Variables.isoUtc(now)
        return await send(p, vars, scanTimeMs: scanTimeMs, sendTimeMs: now)
    }

    /// The editor's Test send: clearly fake sample values, never a real tag.
    func test(_ p: Profile) async -> ScanOutcome {
        let ctx = context(p, scanTimeMs: Self.nowMs(), test: true)
        return await send(p, Variables.sample(ctx), scanTimeMs: ctx.scanTimeMs, sendTimeMs: ctx.sendTimeMs)
    }

    private func send(_ p: Profile, _ vars: [String: String], scanTimeMs: Int64, sendTimeMs: Int64) async -> ScanOutcome {
        let secrets = SecretStore.all()
        var o = ScanOutcome(scanTimeMs: scanTimeMs, profileId: p.id, profileName: p.name,
                            uid: vars["uid"] ?? "", chip: vars["chip"] ?? "", tagType: vars["tag_type"] ?? "",
                            randomUid: vars["random_uid"] == "true", request: nil, result: nil, buildError: nil)
        let req: PreparedRequest
        do {
            req = try RequestBuilder.build(p, variables: vars, secrets: secrets, sendUnix: sendTimeMs / 1000)
        } catch let e as RequestError {
            o.buildError = e.code
            o.resultText = Entitlements.responseRules
                ? ResultText.render(p.after.failureText, status: nil, message: nil, uid: o.uid, profile: p.name) : nil
            return o
        } catch {
            o.buildError = "\(error)"
            o.resultText = Entitlements.responseRules
                ? ResultText.render(p.after.failureText, status: nil, message: nil, uid: o.uid, profile: p.name) : nil
            return o
        }
        let raw = await sender.send(req, allowLocalHttp: p.request.allowLocalHttp)
        // A server that echoes a secret back must not get it onto the screen or into kept history.
        let values = secrets.values.filter { !$0.isEmpty }.sorted { $0.utf16.count > $1.utf16.count }
        // Literal, then percent- and form-encoded, so a URL or form echo is caught too.
        func mask(_ text: String) -> String {
            var out = text
            for v in values { out = out.replacingOccurrences(of: v, with: RequestBuilder.mask, options: .literal) }
            for v in values { out = out.replacingOccurrences(of: Encoding.percent(v), with: RequestBuilder.mask, options: .literal) }
            for v in values { out = out.replacingOccurrences(of: Encoding.form(v), with: RequestBuilder.mask, options: .literal) }
            return out
        }
        var result = raw
        result.responseBody = raw.responseBody.map(mask)
        result.error = raw.error.map(mask)
        let headers = raw.responseHeaders.map { ($0.name, mask($0.value)) }
        let message = Entitlements.responseRules
            ? ResponseMessage.extract(field: p.after.messageField, headers: headers, body: result.responseBody) : nil
        let template = Entitlements.responseRules ? (result.ok ? p.after.successText : p.after.failureText) : nil
        o.request = RequestBuilder.masked(req, secrets: secrets)
        o.result = result
        o.message = message
        o.resultText = ResultText.render(template, status: result.status, message: message, uid: o.uid, profile: p.name).map(mask)
        return o
    }
}
