import CryptoKit
import Foundation

/// HMAC-SHA256 request signing. PROFILE_SCHEMA.md section 6.
public enum Signing {
    public static let timestampHeader = "X-TapPony-Timestamp"
    public static let nonceHeader = "X-TapPony-Nonce"
    public static let signatureHeader = "X-TapPony-Signature"

    public static func signature(key: String, timestamp: String, body: String) -> String {
        // Same empty-key handling as Android: HMAC zero-pads keys, so an empty
        // key and a single 0x00 byte are identical.
        var k = Array(key.utf8)
        if k.isEmpty { k = [0] }
        let mac = HMAC<SHA256>.authenticationCode(for: Data((timestamp + "." + body).utf8), using: SymmetricKey(data: k))
        return "sha256=" + Encoding.hexLower(Array(mac))
    }
}
