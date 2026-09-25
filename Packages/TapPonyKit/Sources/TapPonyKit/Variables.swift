import Foundation

/// Everything a scan produced, platform-neutral. The Core NFC layer fills it in.
public struct TagReading: Equatable {
    public var family: TagFamily
    public var tagType: String
    public var identifier: [UInt8]
    public var chip: String = ""
    public var signature: [UInt8]? = nil
    public var counter: Int? = nil
    public var atqa: [UInt8]? = nil
    public var sak: [UInt8]? = nil
    public var dsfid: [UInt8]? = nil
    public var afi: [UInt8]? = nil
    public var blockSize: Int? = nil
    public var blockCount: Int? = nil
    public var pmm: [UInt8]? = nil
    public var systemCode: [UInt8]? = nil
    public var historicalBytes: [UInt8]? = nil
    public var applicationData: [UInt8]? = nil
    public var ndef: [NdefRecord] = []

    public init(family: TagFamily, tagType: String, identifier: [UInt8]) {
        self.family = family
        self.tagType = tagType
        self.identifier = identifier
    }
}

/// Non-tag inputs to one send. Times are epoch milliseconds.
public struct SendContext: Equatable {
    public var scanTimeMs: Int64
    public var sendTimeMs: Int64
    public var timeZone: String
    public var profileName: String
    public var profileId: String
    public var deviceLabel: String
    public var platform: String
    public var nonce: String
    public var seq: Int64
    public var tagLabel: String

    public init(scanTimeMs: Int64, sendTimeMs: Int64, timeZone: String, profileName: String, profileId: String,
                deviceLabel: String, platform: String, nonce: String, seq: Int64, tagLabel: String = "") {
        self.scanTimeMs = scanTimeMs; self.sendTimeMs = sendTimeMs; self.timeZone = timeZone
        self.profileName = profileName; self.profileId = profileId; self.deviceLabel = deviceLabel
        self.platform = platform; self.nonce = nonce; self.seq = seq; self.tagLabel = tagLabel
    }
}

/// Builds the variable map for a scan. Mirrors com.tappony.core.Variables.
public enum Variables {

    public static let all: Set<String> = [
        "uid", "uid_colon", "uid_dec", "uid_rev", "uid_len", "tag_type", "chip", "manufacturer", "signature",
        "counter", "random_uid", "atqa", "sak", "dsfid", "afi", "block_size", "block_count", "idm", "pmm",
        "system_code", "pupi", "historical_bytes", "application_data", "tag_label",
        "payload", "ndef_text", "ndef_uri", "ndef_json", "ndef_raw", "ndef_count", "token",
        "timestamp", "timestamp_local", "unix", "tz", "sent_at", "profile", "profile_id", "device_label",
        "platform", "nonce", "seq",
    ]

    private static let token = try! NSRegularExpression(pattern: "^https://tappony\\.app/t/[^?#]*\\?(?:[^#]*&)?k=([A-Za-z0-9_-]+)")

    private static func pad(_ v: Int, _ width: Int) -> String {
        let s = String(v)
        return String(repeating: "0", count: max(0, width - s.count)) + s
    }

    private static func floorDiv(_ a: Int64, _ b: Int64) -> Int64 { a >= 0 ? a / b : -((-a + b - 1) / b) }

    private static func format(epochSeconds: Int64, millis: Int64) -> String {
        let days = floorDiv(epochSeconds, 86400)
        let secs = Int(epochSeconds - days * 86400)
        let (y, m, d) = Civil.civilFromDays(days)
        return "\(pad(y, 4))-\(pad(m, 2))-\(pad(d, 2))T\(pad(secs / 3600, 2)):\(pad(secs / 60 % 60, 2)):\(pad(secs % 60, 2)).\(pad(Int(millis), 3))"
    }

    public static func isoUtc(_ ms: Int64) -> String {
        let s = floorDiv(ms, 1000)
        return format(epochSeconds: s, millis: ms - s * 1000) + "Z"
    }

    public static func isoLocal(_ ms: Int64, zone: String) -> String {
        let s = floorDiv(ms, 1000)
        let tz = TimeZone(identifier: zone) ?? TimeZone(secondsFromGMT: 0)!
        let offset = tz.secondsFromGMT(for: Date(timeIntervalSince1970: TimeInterval(s)))
        let total = offset / 60
        let sign = total >= 0 ? "+" : "-"
        let a = abs(total)
        return format(epochSeconds: s + Int64(offset), millis: ms - s * 1000) + sign + pad(a / 60, 2) + ":" + pad(a % 60, 2)
    }

    public static func launchToken(_ uri: String) -> String {
        guard let m = token.firstMatch(in: uri, options: [], range: NSRange(uri.startIndex..., in: uri)),
              let r = Range(m.range(at: 1), in: uri) else { return "" }
        return String(uri[r])
    }

    private static func hex(_ b: [UInt8]?) -> String { b.map { Encoding.hexUpper($0) } ?? "" }

    public static func build(_ reading: TagReading, _ ctx: SendContext) -> [String: String] {
        var out = Uid.variables(reading.family, reading.identifier)
        let uid = out["uid"] ?? ""
        out["tag_type"] = reading.tagType
        out["chip"] = reading.chip
        out["signature"] = hex(reading.signature)
        out["counter"] = reading.counter.map { String($0) } ?? ""
        out["atqa"] = hex(reading.atqa)
        out["sak"] = hex(reading.sak)
        out["dsfid"] = hex(reading.dsfid)
        out["afi"] = hex(reading.afi)
        out["block_size"] = reading.blockSize.map { String($0) } ?? ""
        out["block_count"] = reading.blockCount.map { String($0) } ?? ""
        out["idm"] = reading.family == .felica ? uid : ""
        out["pmm"] = hex(reading.pmm)
        out["system_code"] = hex(reading.systemCode)
        out["pupi"] = reading.family == .iso7816B ? uid : ""
        out["historical_bytes"] = hex(reading.historicalBytes)
        out["application_data"] = hex(reading.applicationData)
        out["tag_label"] = ctx.tagLabel
        let nv = Ndef.variables(reading.ndef)
        out.merge(nv) { _, new in new }
        out["token"] = launchToken(nv["ndef_uri"] ?? "")
        out["timestamp"] = isoUtc(ctx.scanTimeMs)
        out["timestamp_local"] = isoLocal(ctx.scanTimeMs, zone: ctx.timeZone)
        out["unix"] = String(floorDiv(ctx.scanTimeMs, 1000))
        out["tz"] = ctx.timeZone
        out["sent_at"] = isoUtc(ctx.sendTimeMs)
        out["profile"] = ctx.profileName
        out["profile_id"] = ctx.profileId
        out["device_label"] = ctx.deviceLabel
        out["platform"] = ctx.platform
        out["nonce"] = ctx.nonce
        out["seq"] = String(ctx.seq)
        return out
    }

    /// Clearly fake values for the editor's Test send.
    public static func sample(_ ctx: SendContext) -> [String: String] {
        var r = TagReading(family: .mifare, tagType: "mifare_ultralight", identifier: [0x04, 0, 0, 0, 0, 0, 0x01])
        r.chip = "NTAG215"
        r.ndef = [NdefRecord(tnf: 1, type: [0x54], id: [], payload: [0x02] + Array("en".utf8) + Array("TapPony test".utf8))]
        return build(r, ctx)
    }
}
