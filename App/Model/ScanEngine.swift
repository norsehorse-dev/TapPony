import Foundation
import Security
import TapPonyKit

/// What the Scan tab shows after a tag.
struct ScanOutcome: Equatable {
    var profileName: String
    var uid: String
    var chip: String
    var tagType: String
    var randomUid: Bool
    var request: PreparedRequest?
    var result: SendResult?
    var buildError: String?
}

/// The scan pipeline, same shape as Android's ScanEngine: reading -> variables
/// -> request (TapPonyKit) -> send (URLSession).
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

    func context(_ p: Profile, scanTimeMs: Int64, test: Bool = false) -> SendContext {
        SendContext(
            scanTimeMs: scanTimeMs,
            sendTimeMs: Int64(Date().timeIntervalSince1970 * 1000),
            timeZone: TimeZone.current.identifier,
            profileName: p.name,
            profileId: p.id,
            deviceLabel: settings.deviceLabel,
            platform: "ios",
            nonce: Self.nonce(),
            seq: test ? 0 : settings.nextSeq(p.id)
        )
    }

    func run(_ p: Profile, reading: TagReading, scanTimeMs: Int64) async -> ScanOutcome {
        let ctx = context(p, scanTimeMs: scanTimeMs)
        return await send(p, Variables.build(reading, ctx), ctx)
    }

    /// The editor's Test send: clearly fake sample values.
    func test(_ p: Profile) async -> ScanOutcome {
        let ctx = context(p, scanTimeMs: Int64(Date().timeIntervalSince1970 * 1000), test: true)
        return await send(p, Variables.sample(ctx), ctx)
    }

    private func send(_ p: Profile, _ vars: [String: String], _ ctx: SendContext) async -> ScanOutcome {
        let secrets = SecretStore.all()
        var o = ScanOutcome(profileName: p.name, uid: vars["uid"] ?? "", chip: vars["chip"] ?? "", tagType: vars["tag_type"] ?? "",
                            randomUid: vars["random_uid"] == "true", request: nil, result: nil, buildError: nil)
        let req: PreparedRequest
        do {
            req = try RequestBuilder.build(p, variables: vars, secrets: secrets, sendUnix: ctx.sendTimeMs / 1000)
        } catch let e as RequestError {
            o.buildError = e.code
            return o
        } catch {
            o.buildError = "\(error)"
            return o
        }
        o.result = await sender.send(req, allowLocalHttp: p.request.allowLocalHttp)
        o.request = RequestBuilder.masked(req, secrets: secrets)
        return o
    }
}
