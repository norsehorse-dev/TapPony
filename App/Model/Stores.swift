import Foundation
import Security
import TapPonyKit

/// Profiles as JSON files in Application Support, one per profile. The file is
/// the export format and the cross-platform format (PROFILE_SCHEMA.md).
@MainActor
final class ProfileStore: ObservableObject {
    @Published private(set) var profiles: [Profile] = []
    private let dir: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        dir = base.appendingPathComponent("profiles", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        reload()
    }

    func reload() {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        profiles = files.filter { $0.pathExtension == "json" }
            .compactMap { try? ProfileCodec.decode(String(decoding: Data(contentsOf: $0), as: UTF8.self)) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func profile(_ id: String) -> Profile? { profiles.first { $0.id == id } }

    func save(_ p: Profile) {
        let url = dir.appendingPathComponent("\(p.id).json")
        try? Data(ProfileCodec.encode(p).utf8).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        reload()
    }

    func delete(_ id: String) {
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("\(id).json"))
        reload()
    }

    static func newId() -> String { UUID().uuidString.uppercased() }
}

/// Named secrets in the Keychain: this device only, after first unlock, never
/// synced to iCloud Keychain or included in backups.
enum SecretStore {
    private static let service = "com.tappony.app.secrets"
    static let namePattern = try! NSRegularExpression(pattern: "^[A-Za-z0-9_]+$")

    static func isValidName(_ n: String) -> Bool {
        namePattern.firstMatch(in: n, range: NSRange(n.startIndex..., in: n)) != nil
    }

    static func names() -> [String] {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let items = out as? [[String: Any]] else { return [] }
        return items.compactMap { $0[kSecAttrAccount as String] as? String }.sorted()
    }

    static func all() -> [String: String] {
        var m: [String: String] = [:]
        for n in names() { if let v = get(n) { m[n] = v } }
        return m
    }

    static func get(_ name: String) -> String? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: name,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(decoding: d, as: UTF8.self)
    }

    static func put(_ name: String, _ value: String) {
        remove(name)
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: name,
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecAttrSynchronizable as String: false,
        ]
        SecItemAdd(q as CFDictionary, nil)
    }

    static func remove(_ name: String) {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: name,
        ]
        SecItemDelete(q as CFDictionary)
    }
}

/// Per-device settings and the per-profile {seq} counters.
@MainActor
final class AppSettings: ObservableObject {
    private let d = UserDefaults.standard

    @Published var deviceLabel: String {
        didSet { d.set(deviceLabel, forKey: "device_label") }
    }
    @Published var activeProfileId: String? {
        didSet { d.set(activeProfileId, forKey: "active_profile") }
    }

    init() {
        deviceLabel = d.string(forKey: "device_label") ?? ""
        activeProfileId = d.string(forKey: "active_profile")
    }

    func nextSeq(_ profileId: String) -> Int64 {
        let k = "seq_\(profileId)"
        let n = Int64(d.integer(forKey: k)) + 1
        d.set(Int(n), forKey: k)
        return n
    }
}
