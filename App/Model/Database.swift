import Foundation
import SQLite3

/// SQLite's "copy this string now" destructor, which the C header exposes as a macro Swift can't see.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// A small SQLite wrapper for history and the offline queue: one file in
/// Application Support, used from the main actor only. Same tables and
/// columns as Android's Room database, so the two stay easy to compare.
@MainActor
final class Database {
    static let shared = Database()

    private var db: OpaquePointer?

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let url = base.appendingPathComponent("history.sqlite")
        if sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) != SQLITE_OK {
            sqlite3_close(db)
            db = nil
            return
        }
        try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
        exec("PRAGMA journal_mode=WAL")
        migrate()
    }

    private func migrate() {
        let version = queryInt("PRAGMA user_version") ?? 0
        if version < 1 {
            exec("""
                CREATE TABLE IF NOT EXISTS history (
                    id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                    timeMs INTEGER NOT NULL,
                    profileId TEXT NOT NULL,
                    profileName TEXT NOT NULL,
                    uid TEXT NOT NULL,
                    chip TEXT NOT NULL,
                    tagType TEXT NOT NULL,
                    outcome TEXT NOT NULL,
                    status INTEGER,
                    latencyMs INTEGER,
                    error TEXT NOT NULL,
                    message TEXT,
                    request TEXT NOT NULL,
                    requestBody TEXT,
                    responseBody TEXT)
                """)
            exec("""
                CREATE TABLE IF NOT EXISTS queue (
                    id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                    scanTimeMs INTEGER NOT NULL,
                    profileId TEXT NOT NULL,
                    profileName TEXT NOT NULL,
                    variablesJson TEXT NOT NULL,
                    attempts INTEGER NOT NULL,
                    lastError TEXT NOT NULL)
                """)
            exec("PRAGMA user_version = 1")
        }
    }

    // MARK: primitives

    enum Value {
        case int(Int64)
        case text(String)
        case null

        static func optInt(_ v: Int?) -> Value { v.map { .int(Int64($0)) } ?? .null }
        static func optText(_ v: String?) -> Value { v.map { .text($0) } ?? .null }
    }

    /// A row as returned by `query`: columns by index.
    struct Row {
        fileprivate let values: [Value]
        func int(_ i: Int) -> Int64? { if case .int(let v) = values[i] { return v }; return nil }
        func text(_ i: Int) -> String? { if case .text(let v) = values[i] { return v }; return nil }
    }

    @discardableResult
    func exec(_ sql: String, _ args: [Value] = []) -> Bool {
        guard let stmt = prepare(sql, args) else { return false }
        defer { sqlite3_finalize(stmt) }
        let rc = sqlite3_step(stmt)
        return rc == SQLITE_DONE || rc == SQLITE_ROW
    }

    func query(_ sql: String, _ args: [Value] = []) -> [Row] {
        guard let stmt = prepare(sql, args) else { return [] }
        defer { sqlite3_finalize(stmt) }
        var rows: [Row] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            var values: [Value] = []
            for i in 0..<sqlite3_column_count(stmt) {
                switch sqlite3_column_type(stmt, i) {
                case SQLITE_INTEGER:
                    values.append(.int(sqlite3_column_int64(stmt, i)))
                case SQLITE_NULL:
                    values.append(.null)
                default:
                    if let c = sqlite3_column_text(stmt, i) {
                        values.append(.text(String(cString: c)))
                    } else {
                        values.append(.null)
                    }
                }
            }
            rows.append(Row(values: values))
        }
        return rows
    }

    func queryInt(_ sql: String, _ args: [Value] = []) -> Int? {
        query(sql, args).first?.int(0).map { Int($0) }
    }

    /// Runs `body` in one transaction; rolls back if it returns false. True if committed.
    @discardableResult
    func transaction(_ body: () -> Bool) -> Bool {
        guard exec("BEGIN IMMEDIATE") else { return false }
        if body(), exec("COMMIT") { return true }
        exec("ROLLBACK")
        return false
    }

    private func prepare(_ sql: String, _ args: [Value]) -> OpaquePointer? {
        guard let db else { return nil }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return nil }
        for (i, a) in args.enumerated() {
            let idx = Int32(i + 1)
            switch a {
            case .int(let v): sqlite3_bind_int64(stmt, idx, v)
            case .text(let v): sqlite3_bind_text(stmt, idx, v, -1, SQLITE_TRANSIENT)
            case .null: sqlite3_bind_null(stmt, idx)
            }
        }
        return stmt
    }
}
