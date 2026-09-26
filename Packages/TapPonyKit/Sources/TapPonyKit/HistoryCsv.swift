import Foundation

/// One history entry as exported. Bodies are never part of it.
public struct HistoryRow: Equatable {
    public var timeMs: Int64
    public var profile: String
    public var uid: String
    public var chip: String
    public var tagType: String
    public var outcome: String
    public var status: Int?
    public var latencyMs: Int64?
    public var error: String

    public init(timeMs: Int64, profile: String, uid: String, chip: String, tagType: String, outcome: String,
                status: Int?, latencyMs: Int64?, error: String) {
        self.timeMs = timeMs; self.profile = profile; self.uid = uid; self.chip = chip; self.tagType = tagType
        self.outcome = outcome; self.status = status; self.latencyMs = latencyMs; self.error = error
    }
}

/// History CSV export, PROFILE_SCHEMA.md section 12. Mirrors com.tappony.core.HistoryCsv.
public enum HistoryCsv {
    public static let ok = "ok"
    public static let httpError = "http_error"
    public static let networkError = "network_error"
    public static let notSent = "not_sent"

    public static let header = ["time", "profile", "uid", "chip", "tag_type", "outcome", "status", "latency_ms", "error"]

    public static func outcome(buildError: String?, status: Int?) -> String {
        if let e = buildError, !e.isEmpty { return notSent }
        guard let s = status else { return networkError }
        return (200...299).contains(s) ? ok : httpError
    }

    public static func field(_ raw: String) -> String {
        var s = raw
        if let f = s.unicodeScalars.first, ["=", "+", "-", "@", "\t", "\r"].contains(f) { s = "'" + s }
        let scalars = s.unicodeScalars
        let special = scalars.contains { $0 == "," || $0 == "\"" || $0 == "\r" || $0 == "\n" }
        let padded = scalars.first == " " || scalars.last == " "
        guard special || padded else { return s }
        return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"", options: .literal) + "\""
    }

    public static func row(_ r: HistoryRow) -> String {
        [Variables.isoUtc(r.timeMs), r.profile, r.uid, r.chip, r.tagType, r.outcome,
         r.status.map { String($0) } ?? "", r.latencyMs.map { String($0) } ?? "", r.error]
            .map(field).joined(separator: ",")
    }

    public static func document(_ rows: [HistoryRow]) -> String {
        ([header.joined(separator: ",")] + rows.map(row)).joined(separator: "\r\n") + "\r\n"
    }
}
