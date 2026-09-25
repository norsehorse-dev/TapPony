import Foundation

/// One NDEF record in platform-neutral form. The Core NFC layer converts
/// NFCNDEFPayload into this.
public struct NdefRecord: Equatable {
    public let tnf: Int
    public let type: [UInt8]
    public let id: [UInt8]
    public let payload: [UInt8]
    public init(tnf: Int, type: [UInt8], id: [UInt8], payload: [UInt8]) {
        self.tnf = tnf; self.type = type; self.id = id; self.payload = payload
    }
}

/// NDEF decoding and re-encoding for the content variables. PROFILE_SCHEMA.md
/// section 10. Mirrors com.tappony.core.Ndef.
public enum Ndef {

    public static let contentCap = 8192

    private static let uriPrefixes = [
        "", "http://www.", "https://www.", "http://", "https://", "tel:", "mailto:",
        "ftp://anonymous:anonymous@", "ftp://ftp.", "ftps://", "sftp://", "smb://", "nfs://", "ftp://",
        "dav://", "news:", "telnet://", "imap:", "rtsp://", "urn:", "pop:", "sip:", "sips:", "tftp:",
        "btspp://", "btl2cap://", "btgoep://", "tcpobex://", "irdaobex://", "file://", "urn:epc:id:",
        "urn:epc:tag:", "urn:epc:pat:", "urn:epc:raw:", "urn:epc:", "urn:nfc:",
    ]

    /// NFC Forum NDEF 1.0 message encoding. Core NFC does not expose raw
    /// message bytes, so both platforms build them here for {ndef_raw}.
    public static func encode(_ records: [NdefRecord]) -> [UInt8] {
        var out: [UInt8] = []
        for (i, r) in records.enumerated() {
            let sr = r.payload.count < 256
            let il = !r.id.isEmpty
            var h = UInt8(r.tnf & 0x07)
            if i == 0 { h |= 0x80 }
            if i == records.count - 1 { h |= 0x40 }
            if sr { h |= 0x10 }
            if il { h |= 0x08 }
            out.append(h)
            out.append(UInt8(r.type.count & 0xFF))
            if sr {
                out.append(UInt8(r.payload.count))
            } else {
                let n = UInt32(r.payload.count)
                out += [UInt8(n >> 24 & 0xFF), UInt8(n >> 16 & 0xFF), UInt8(n >> 8 & 0xFF), UInt8(n & 0xFF)]
            }
            if il { out.append(UInt8(r.id.count & 0xFF)) }
            out += r.type
            out += r.id
            out += r.payload
        }
        return out
    }

    public static func text(of r: NdefRecord) -> String? {
        guard r.tnf == 1, r.type == [0x54], !r.payload.isEmpty else { return nil }
        let status = r.payload[0]
        let langLen = Int(status & 0x3F)
        let start = min(1 + langLen, r.payload.count)
        let body = Array(r.payload[start...])
        if status & 0x80 != 0 {
            if body.count >= 2, body[0] == 0xFF, body[1] == 0xFE { return utf16(Array(body[2...]), bigEndian: false) }
            if body.count >= 2, body[0] == 0xFE, body[1] == 0xFF { return utf16(Array(body[2...]), bigEndian: true) }
            return utf16(body, bigEndian: true)
        }
        return String(decoding: body, as: UTF8.self)
    }

    private static func utf16(_ b: [UInt8], bigEndian: Bool) -> String {
        var units: [UInt16] = []
        var i = 0
        while i + 1 < b.count {
            units.append(bigEndian ? UInt16(b[i]) << 8 | UInt16(b[i + 1]) : UInt16(b[i + 1]) << 8 | UInt16(b[i]))
            i += 2
        }
        var s = String(decoding: units, as: UTF16.self)
        if b.count % 2 == 1 { s += "\u{FFFD}" }
        return s
    }

    public static func uri(of r: NdefRecord) -> String? {
        if r.tnf == 1, r.type == [0x55], !r.payload.isEmpty {
            let code = Int(r.payload[0])
            let prefix = code < uriPrefixes.count ? uriPrefixes[code] : ""
            return prefix + String(decoding: r.payload[1...], as: UTF8.self)
        }
        if r.tnf == 3 { return String(decoding: r.type, as: UTF8.self) }
        return nil
    }

    private static func latin1(_ b: [UInt8]) -> String {
        String(String.UnicodeScalarView(b.map { Unicode.Scalar($0) }))
    }

    public static func variables(_ records: [NdefRecord]) -> [String: String] {
        guard let first = records.first else {
            return ["payload": "", "ndef_text": "", "ndef_uri": "", "ndef_json": "[]", "ndef_raw": "", "ndef_count": "0"]
        }
        let payload = text(of: first) ?? uri(of: first) ?? Encoding.base64(first.payload)
        let firstText = records.lazy.compactMap { text(of: $0) }.first ?? ""
        let firstUri = records.lazy.compactMap { uri(of: $0) }.first ?? ""
        var json = "["
        for (i, r) in records.enumerated() {
            if i > 0 { json += "," }
            json += "{\"tnf\":\(r.tnf)"
            json += ",\"type\":\"" + JSON.escape(latin1(r.type)) + "\""
            json += ",\"id\":\"" + Encoding.base64(r.id) + "\""
            json += ",\"payload\":\"" + Encoding.base64(r.payload) + "\""
            if let t = text(of: r) { json += ",\"text\":\"" + JSON.escape(t) + "\"" }
            if let u = uri(of: r) { json += ",\"uri\":\"" + JSON.escape(u) + "\"" }
            json += "}"
        }
        json += "]"
        func cap(_ s: String) -> String { Encoding.capCodePoints(s, contentCap) }
        return [
            "payload": cap(payload),
            "ndef_text": cap(firstText),
            "ndef_uri": cap(firstUri),
            "ndef_json": cap(json),
            "ndef_raw": cap(Encoding.base64(encode(records))),
            "ndef_count": String(records.count),
        ]
    }
}
