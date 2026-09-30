import Foundation

/// The one gate for Plus features (PLANNING_1_0_0.md sections 8 and 9).
///
/// TapPony 1.0 is free with every feature on, so `plus` is always true. The
/// gate exists so a future App Store unlock only changes this type.
enum Entitlements {
    static var plus: Bool { true }

    static let freeProfiles = 3
    static let freeTags = 25

    static func canAddProfile(count: Int) -> Bool { plus || count < freeProfiles }

    /// Named tags in the registry beyond the free 25.
    static func canAddTag(count: Int) -> Bool { plus || count < freeTags }

    /// Routing rules, fan-out and ignoring unmatched tags.
    static var rules: Bool { plus }

    /// Batch mode with its running list and once-per-batch dedupe.
    static var batch: Bool { plus }

    /// Holding scans that got no response and sending them later.
    static var offlineQueue: Bool { plus }

    /// Reply message field, custom result text and spoken confirmation.
    static var responseRules: Bool { plus }

    /// Notes and a default profile on a named tag.
    static var tagDefaults: Bool { plus }
}
