import Foundation
import TapPonyKit

/// One scan in local history: identity and outcome always, bodies only when the
/// profile opted in to keeping them. Never leaves the device except as the CSV
/// export, which excludes bodies (PROFILE_SCHEMA.md section 12).
struct HistoryEntry: Identifiable, Equatable {
    var id: Int64 = 0
    var timeMs: Int64
    var profileId: String
    var profileName: String
    var uid: String
    var chip: String
    var tagType: String
    var outcome: String
    var status: Int?
    var latencyMs: Int?
    var error: String
    var message: String?
    var request: String
    var requestBody: String?
    var responseBody: String?

    var row: HistoryRow {
        HistoryRow(timeMs: timeMs, profile: profileName, uid: uid, chip: chip, tagType: tagType, outcome: outcome,
                   status: status, latencyMs: latencyMs.map { Int64($0) }, error: error)
    }
}

/// History with the retention rule applied on every write: at most
/// `maxEntries`, none older than the setting.
@MainActor
final class HistoryStore: ObservableObject {
    static let maxEntries = 1000
    nonisolated static let keptBodyChars = 4096
    private static let dayMs: Int64 = 24 * 60 * 60 * 1000

    @Published private(set) var entries: [HistoryEntry] = []

    private let db: Database
    private let settings: AppSettings

    init(db: Database, settings: AppSettings) {
        self.db = db
        self.settings = settings
        prune()
        reload()
    }

    func reload() {
        entries = db.query("SELECT * FROM history ORDER BY timeMs DESC, id DESC LIMIT ?", [.int(Int64(Self.maxEntries))]).map { Self.entry($0) }
    }

    func record(_ e: HistoryEntry) {
        insert(e)
        prune()
        reload()
    }

    /// Insert only; the caller reloads. Used inside the queue's transaction.
    @discardableResult
    func insert(_ e: HistoryEntry) -> Bool {
        db.exec("""
            INSERT INTO history (timeMs, profileId, profileName, uid, chip, tagType, outcome, status, latencyMs, error, message, request, requestBody, responseBody)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, [
                .int(e.timeMs), .text(e.profileId), .text(e.profileName), .text(e.uid), .text(e.chip), .text(e.tagType),
                .text(e.outcome), .optInt(e.status), .optInt(e.latencyMs), .text(e.error), .optText(e.message),
                .text(e.request), .optText(e.requestBody), .optText(e.responseBody),
            ])
    }

    func prune() {
        let days = settings.historyDays
        if days > 0 {
            let cutoff = Int64(Date().timeIntervalSince1970 * 1000) - Int64(days) * Self.dayMs
            db.exec("DELETE FROM history WHERE timeMs < ?", [.int(cutoff)])
        }
        db.exec("DELETE FROM history WHERE id NOT IN (SELECT id FROM history ORDER BY timeMs DESC, id DESC LIMIT ?)",
                [.int(Int64(Self.maxEntries))])
    }

    func applyRetention() {
        prune()
        reload()
    }

    func clear() {
        db.exec("DELETE FROM history")
        reload()
    }

    func exportRows() -> [HistoryRow] {
        db.query("SELECT * FROM history ORDER BY timeMs ASC, id ASC").map { Self.entry($0).row }
    }

    /// Columns in table order, as created in Database.migrate.
    private static func entry(_ r: Database.Row) -> HistoryEntry {
        HistoryEntry(
            id: r.int(0) ?? 0,
            timeMs: r.int(1) ?? 0,
            profileId: r.text(2) ?? "",
            profileName: r.text(3) ?? "",
            uid: r.text(4) ?? "",
            chip: r.text(5) ?? "",
            tagType: r.text(6) ?? "",
            outcome: r.text(7) ?? "",
            status: r.int(8).map { Int($0) },
            latencyMs: r.int(9).map { Int($0) },
            error: r.text(10) ?? "",
            message: r.text(11),
            request: r.text(12) ?? "",
            requestBody: r.text(13),
            responseBody: r.text(14)
        )
    }
}

/// A scan waiting for a connection (PROFILE_SCHEMA.md section 13). Holds the
/// scan's variables as JSON, never the rendered request, so no secret is stored.
struct QueuedScan {
    var id: Int64
    var scanTimeMs: Int64
    var profileId: String
    var profileName: String
    var variablesJson: String
    var attempts: Int
    var lastError: String
}

/// Scans that got no response, waiting for a connection. Flushed when the app
/// comes to the foreground, when the network comes back while it is open, after
/// any send that got a response, and by Send now. Same rules as Android's
/// OfflineQueue: oldest first, stop at the first scan that still gets no
/// response, drop after 24 hours into history as a network error.
@MainActor
final class OfflineQueue: ObservableObject {
    enum Flush { case empty, stopped }

    static let maxAgeMs: Int64 = 24 * 60 * 60 * 1000

    @Published private(set) var count = 0
    @Published private(set) var flushing = false

    private let db: Database
    private let history: HistoryStore
    private let profiles: ProfileStore
    /// Set after init; the engine and the queue refer to each other.
    weak var engine: ScanEngine?

    init(db: Database, history: HistoryStore, profiles: ProfileStore) {
        self.db = db
        self.history = history
        self.profiles = profiles
        refreshCount()
    }

    /// Stores the scan; false if it couldn't be written, so the caller records it as a failure instead.
    func enqueue(_ profile: Profile, scanTimeMs: Int64, variables: [String: String], error: String) -> Bool {
        let ok = db.exec("INSERT INTO queue (scanTimeMs, profileId, profileName, variablesJson, attempts, lastError) VALUES (?, ?, ?, ?, 1, ?)",
                         [.int(scanTimeMs), .text(profile.id), .text(profile.name), .text(Self.encode(variables)), .text(error)])
        refreshCount()
        if ok { scheduleRetry() }
        return ok
    }

    /// Flush soon; cheap when empty. A kick during a flush runs another flush after it.
    func kick() {
        guard count > 0 else { return }
        if flushing {
            kickPending = true
            return
        }
        Task { await flush() }
    }

    private var kickPending = false
    private var retryTask: Task<Void, Never>?
    private var retryDelay: UInt64 = 30

    /// While the app is open, retry with backoff (30 s doubling to 10 minutes),
    /// like Android's WorkManager backoff. The network coming back, the app
    /// becoming active and Send now all flush sooner.
    private func scheduleRetry() {
        guard retryTask == nil, count > 0 else { return }
        let delay = retryDelay
        retryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
            guard let self, !Task.isCancelled else { return }
            self.retryTask = nil
            self.retryDelay = min(self.retryDelay * 2, 600)
            self.kick()
        }
    }

    /// Sends queued scans oldest first; stops at the first one that still gets
    /// no response. Re-reads the head each time, so a scan queued meanwhile is
    /// picked up too. A second call while one runs returns at once.
    @discardableResult
    func flush() async -> Flush {
        guard !flushing else {
            kickPending = true
            return .stopped
        }
        flushing = true
        let result = await drain()
        flushing = false
        refreshCount()
        if result == .empty {
            retryTask?.cancel()
            retryTask = nil
            retryDelay = 30
        } else {
            scheduleRetry()
        }
        if kickPending {
            kickPending = false
            kick()
        }
        return result
    }

    private func drain() async -> Flush {
        while let item = oldest() {
            let now = Int64(Date().timeIntervalSince1970 * 1000)
            if now - item.scanTimeMs > Self.maxAgeMs {
                guard finish(item, entry(item, outcome: HistoryCsv.networkError, error: item.lastError)) else { return .stopped }
                continue
            }
            guard let profile = profiles.profile(item.profileId) else {
                guard finish(item, entry(item, outcome: HistoryCsv.notSent, error: "profileDeleted")) else { return .stopped }
                continue
            }
            guard let engine else { return .stopped }
            let outcome = await engine.resend(profile, storedVariables: Self.decode(item.variablesJson), scanTimeMs: item.scanTimeMs)
            if outcome.isNoResponse {
                db.exec("UPDATE queue SET attempts = attempts + 1, lastError = ? WHERE id = ?",
                        [.text(outcome.result?.error ?? ""), .int(item.id)])
                return .stopped
            }
            // If this write fails the scan stays queued and may go out twice; better than losing it.
            guard finish(item, outcome.historyEntry(keepBodies: profile.after.keepBodies)) else { return .stopped }
        }
        return .empty
    }

    private func oldest() -> QueuedScan? {
        guard let r = db.query("SELECT id, scanTimeMs, profileId, profileName, variablesJson, attempts, lastError FROM queue ORDER BY scanTimeMs ASC, id ASC LIMIT 1").first,
              let id = r.int(0) else { return nil }
        return QueuedScan(id: id, scanTimeMs: r.int(1) ?? 0, profileId: r.text(2) ?? "", profileName: r.text(3) ?? "",
                          variablesJson: r.text(4) ?? "{}", attempts: Int(r.int(5) ?? 0), lastError: r.text(6) ?? "")
    }

    /// Removes the item and writes its history entry together, so neither is lost or doubled.
    private func finish(_ item: QueuedScan, _ e: HistoryEntry) -> Bool {
        let ok = db.transaction {
            let deleted = db.exec("DELETE FROM queue WHERE id = ?", [.int(item.id)])
            return deleted && history.insert(e)
        }
        history.applyRetention()
        refreshCount()
        return ok
    }

    private func entry(_ item: QueuedScan, outcome: String, error: String) -> HistoryEntry {
        let vars = Self.decode(item.variablesJson)
        return HistoryEntry(timeMs: item.scanTimeMs, profileId: item.profileId, profileName: item.profileName,
                            uid: vars["uid"] ?? "", chip: vars["chip"] ?? "", tagType: vars["tag_type"] ?? "",
                            outcome: outcome, status: nil, latencyMs: nil, error: error, message: nil,
                            request: "", requestBody: nil, responseBody: nil)
    }

    private func refreshCount() {
        count = db.queryInt("SELECT COUNT(*) FROM queue") ?? 0
    }

    static func encode(_ vars: [String: String]) -> String {
        JSON.write(.object(vars.keys.sorted().map { JSONMember($0, .string(vars[$0] ?? "")) }))
    }

    static func decode(_ json: String) -> [String: String] {
        guard case .object(let members)? = try? JSON.parse(json) else { return [:] }
        var out: [String: String] = [:]
        for m in members { out[m.key] = m.value.string ?? "" }
        return out
    }
}
