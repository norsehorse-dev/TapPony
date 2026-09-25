import Foundation

/// Tag families as the core sees them; raw values match the fixtures.
public enum TagFamily: String, CaseIterable {
    case mifare              // ISO 14443-A (NTAG, Ultralight, DESFire, Plus)
    case iso15693            // NFC-V
    case felica              // NFC-F
    case iso7816A = "iso7816_a"
    case iso7816B = "iso7816_b"
}

/// UID canonicalization, formats, manufacturer and chip identification.
/// PROFILE_SCHEMA.md section 8. Mirrors com.tappony.core.Uid.
public enum Uid {

    private static let manufacturers: [UInt8: String] = [
        0x01: "Motorola", 0x02: "STMicroelectronics", 0x03: "Hitachi", 0x04: "NXP",
        0x05: "Infineon", 0x06: "Cylink", 0x07: "Texas Instruments", 0x08: "Fujitsu",
        0x09: "Matsushita", 0x0A: "NEC", 0x0B: "Oki", 0x0C: "Toshiba", 0x0D: "Mitsubishi",
        0x0E: "Samsung", 0x0F: "Hynix", 0x10: "LG", 0x11: "Emosyn-EM", 0x12: "INSIDE Technology",
        0x13: "ORGA", 0x14: "Sharp", 0x15: "Atmel", 0x16: "EM Microelectronic",
    ]

    public static func canonical(_ family: TagFamily, _ raw: [UInt8]) -> [UInt8] {
        if family == .iso15693, raw.count > 1, raw[0] != 0xE0, raw[raw.count - 1] == 0xE0 {
            return Array(raw.reversed())
        }
        return raw
    }

    public static func manufacturer(_ family: TagFamily, _ c: [UInt8]) -> String {
        switch family {
        case .felica: return "Sony"
        case .iso15693: return c.count >= 2 && c[0] == 0xE0 ? manufacturers[c[1]] ?? "" : ""
        case .mifare, .iso7816A: return c.count == 7 ? manufacturers[c[0]] ?? "" : ""
        case .iso7816B: return ""
        }
    }

    public static func isRandom(_ family: TagFamily, _ c: [UInt8]) -> Bool {
        (family == .mifare || family == .iso7816A) && c.count == 4 && c[0] == 0x08
    }

    public static func variables(_ family: TagFamily, _ raw: [UInt8]) -> [String: String] {
        let b = canonical(family, raw)
        return [
            "uid": Encoding.hexUpper(b),
            "uid_colon": Encoding.colon(b),
            "uid_dec": Encoding.decimal(b),
            "uid_rev": Encoding.hexUpper(Array(b.reversed())),
            "uid_len": String(b.count),
            "random_uid": isRandom(family, b) ? "true" : "false",
            "manufacturer": manufacturer(family, b),
        ]
    }

    /// NTAG21x / Ultralight EV1 GET_VERSION (0x60) response.
    public static func chipFromGetVersion(_ r: [UInt8]) -> String {
        guard r.count == 8, r[1] == 0x04 else { return "" }
        if r[2] == 0x04 && r[3] == 0x02 {
            switch r[6] { case 0x0F: return "NTAG213"; case 0x11: return "NTAG215"; case 0x13: return "NTAG216"; default: return "" }
        }
        if r[2] == 0x03 && r[3] == 0x01 {
            switch r[6] { case 0x0B, 0x0E: return "Ultralight EV1"; default: return "" }
        }
        return ""
    }

    /// DESFire GetVersion first frame. Confirm on hardware in the spike.
    public static func chipFromDesfireVersion(_ hw: [UInt8]) -> String {
        guard hw.count >= 4, hw[0] == 0x04, hw[1] == 0x01 else { return "" }
        switch hw[3] {
        case 0x00: return "DESFire"
        case 0x01: return "DESFire EV1"
        case 0x12: return "DESFire EV2"
        case 0x33: return "DESFire EV3"
        default: return ""
        }
    }
}
