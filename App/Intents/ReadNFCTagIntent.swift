import AppIntents
import Foundation
import TapPonyKit

/// What "Read NFC Tag" hands back to Shortcuts: the tag's identity and content
/// as named properties any later action can use.
struct TagReadingEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "NFC Tag Reading"
    static var defaultQuery = TagReadingQuery()

    var id: String

    @Property(title: "UID")
    var uid: String
    @Property(title: "UID with colons")
    var uidColon: String
    @Property(title: "Tag type")
    var tagType: String
    @Property(title: "Chip")
    var chip: String
    @Property(title: "Manufacturer")
    var manufacturer: String
    @Property(title: "NDEF text")
    var ndefText: String
    @Property(title: "NDEF URI")
    var ndefURI: String
    @Property(title: "Payload")
    var payload: String
    @Property(title: "Originality signature")
    var signature: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(uid)", subtitle: "\(chip.isEmpty ? tagType : chip)")
    }

    init(variables v: [String: String]) {
        id = UUID().uuidString
        uid = v["uid"] ?? ""
        uidColon = v["uid_colon"] ?? ""
        tagType = v["tag_type"] ?? ""
        chip = v["chip"] ?? ""
        manufacturer = v["manufacturer"] ?? ""
        ndefText = v["ndef_text"] ?? ""
        ndefURI = v["ndef_uri"] ?? ""
        payload = v["payload"] ?? ""
        signature = v["signature"] ?? ""
    }
}

/// Readings are transient; there is nothing to look up later.
struct TagReadingQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [TagReadingEntity] { [] }
}

/// The free Shortcuts action that Shortcuts' own NFC trigger lacks: scan any
/// tag and get its UID and content back as values. Core NFC needs the app in
/// the foreground, so the intent opens TapPony, shows the system sheet, and
/// returns to the shortcut when the read finishes.
struct ReadNFCTagIntent: AppIntent {
    static var title: LocalizedStringResource = "Read NFC Tag"
    static var description = IntentDescription("Scans one NFC tag and returns its UID, chip, and NDEF content. Nothing is sent anywhere.")
    static var openAppWhenRun = true

    @Parameter(title: "Read chip details", default: true)
    var extendedReads: Bool

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<TagReadingEntity> {
        let reading = try await TagReaders.default().read(
            technologies: ["iso14443", "iso15693", "felica"],
            extendedReads: extendedReads,
            alert: String(localized: "Hold near the tag"))
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let ctx = SendContext(scanTimeMs: now, sendTimeMs: now, timeZone: TimeZone.current.identifier, profileName: "",
                              profileId: "", deviceLabel: "", platform: "ios", nonce: "", seq: 0)
        return .result(value: TagReadingEntity(variables: Variables.build(reading, ctx)))
    }
}

struct TapPonyShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ScanAndSendIntent(),
            phrases: ["Scan and send with \(.applicationName)", "Scan a tag with \(.applicationName)"],
            shortTitle: "Scan and Send",
            systemImageName: "paperplane"
        )
        AppShortcut(
            intent: ReadNFCTagIntent(),
            phrases: ["Read an NFC tag with \(.applicationName)"],
            shortTitle: "Read NFC Tag",
            systemImageName: "wave.3.right"
        )
    }
}
