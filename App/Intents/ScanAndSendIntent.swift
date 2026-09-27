import AppIntents
import Foundation
import TapPonyKit

/// A profile as Shortcuts sees it: name only. The profile document itself
/// never leaves the app.
struct ProfileEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "TapPony Profile"
    static var defaultQuery = ProfileEntityQuery()

    var id: String
    var name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct ProfileEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [ProfileEntity] {
        ProfileStore.load().filter { identifiers.contains($0.id) }.map { ProfileEntity(id: $0.id, name: $0.name) }
    }

    func suggestedEntities() async throws -> [ProfileEntity] {
        ProfileStore.load().map { ProfileEntity(id: $0.id, name: $0.name) }
    }
}

/// What Scan and Send hands back: how the send went, for the next action.
struct ScanResultEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "TapPony Scan Result"
    static var defaultQuery = ScanResultQuery()

    var id: String

    /// True only when the server answered with a 2xx. A queued scan has Queued set instead.
    @Property(title: "Sent")
    var ok: Bool
    @Property(title: "HTTP status")
    var status: Int
    @Property(title: "Message")
    var message: String
    @Property(title: "Result text")
    var resultText: String
    @Property(title: "UID")
    var uid: String
    @Property(title: "Profile")
    var profile: String
    @Property(title: "Queued")
    var queued: Bool

    /// The one-line result the Scan tab would show.
    var summary: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(summary)", subtitle: "\(profile)")
    }

    init(_ o: ScanOutcome) {
        summary = ScanController.shortResult(o)
        id = o.id.uuidString
        ok = o.result?.ok == true
        status = o.result?.status ?? 0
        message = o.message ?? ""
        resultText = o.resultText ?? ""
        uid = o.uid
        profile = o.profileName
        queued = o.queued
    }
}

/// Results are transient; there is nothing to look up later.
struct ScanResultQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [ScanResultEntity] { [] }
}

/// Scan one tag and send it, from Shortcuts, the Action button or Siri. With a
/// profile chosen it goes to that profile only; without one it goes wherever a
/// scan on the Scan tab would (rules, then the active profile). History, the
/// offline queue, sound and speech all behave as on the Scan tab.
struct ScanAndSendIntent: AppIntent {
    static var title: LocalizedStringResource = "Scan and Send"
    static var description = IntentDescription("Scans one NFC tag and sends it with a TapPony profile. Returns whether it was sent, the HTTP status and the server's message.")
    static var openAppWhenRun = true

    @Parameter(title: "Profile")
    var profile: ProfileEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Scan and send with \(\.$profile)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[ScanResultEntity]> {
        let model = AppModel.shared
        let forced = profile.flatMap { model.profiles.profile($0.id) }
        if profile != nil && forced == nil {
            throw IntentFailure.message(String(localized: "That profile no longer exists."))
        }
        let spec: (technologies: [String], extended: Bool)
        if let forced {
            spec = (forced.tag.technologies, forced.tag.extendedReads)
        } else if let active = model.activeProfile {
            // Same as ScanController.readSpec: rules or a tag's own profile can pick any profile.
            let anyCandidate = model.rules.current.enabled || model.tags.current.tags.contains { $0.profile != nil }
            let all = anyCandidate ? model.profiles.profiles : [active]
            var tech: [String] = []
            for p in all { for t in p.tag.technologies where !tech.contains(t) { tech.append(t) } }
            spec = (tech, all.contains { $0.tag.extendedReads })
        } else {
            throw IntentFailure.message(ScanController.failureText(.noProfile))
        }
        guard model.scanner.claimReader() else {
            throw IntentFailure.message(String(localized: "TapPony is already reading a tag. Try again in a moment."))
        }
        defer { model.scanner.releaseReader() }
        let reading: TagReading
        do {
            reading = try await TagReaders.default().read(technologies: spec.technologies, extendedReads: spec.extended,
                                                          alert: String(localized: "Hold near the tag"))
        } catch let e as TagReadError {
            throw IntentFailure.message(Self.explain(e))
        }
        let scanTime = ScanEngine.nowMs()
        switch model.scanner.targets(for: reading, scanTimeMs: scanTime, forced: forced) {
        case .failure(let f):
            throw IntentFailure.message(ScanController.failureText(f))
        case .success(let routed):
            let outcomes = await model.scanner.send(routed, reading: reading, scanTimeMs: scanTime)
            return .result(value: outcomes.map { ScanResultEntity($0) })
        }
    }
}

extension ScanAndSendIntent {
    static func explain(_ e: TagReadError) -> String {
        switch e {
        case .cancelled: return String(localized: "The scan was cancelled.")
        case .timeout: return String(localized: "No tag was read before the scan timed out.")
        case .unavailable: return String(localized: "NFC reading isn't available right now.")
        case .systemBusy: return String(localized: "The system is busy with another NFC session. Try again in a moment.")
        case .moved: return String(localized: "The tag moved away before it was fully read. Hold it still and try again.")
        case .unsupported: return String(localized: "This tag type isn't supported. iPhone can't read MIFARE Classic badges.")
        case .other(let s): return s
        }
    }
}

/// An error Shortcuts shows as a plain sentence.
enum IntentFailure: Error, CustomLocalizedStringResourceConvertible {
    case message(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .message(let s): return "\(s)"
        }
    }
}
