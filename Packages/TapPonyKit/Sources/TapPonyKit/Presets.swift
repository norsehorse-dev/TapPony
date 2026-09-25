import Foundation

/// Starting points for common receivers. Mirrors com.tappony.core.Presets so a
/// preset makes the same profile on both platforms. Titles and explainers are
/// localized in the app under preset_<key>_title and preset_<key>_explainer.
/// REPLACE_ME segments are literal text the user swaps for their own value.
public enum Presets {

    public struct Preset {
        public let key: String
        public let create: (String) -> Profile
    }

    private static let standardJSON =
        "{\"uid\":\"{uid}\",\"chip\":\"{chip}\",\"tag_type\":\"{tag_type}\",\"payload\":\"{payload}\",\"timestamp\":\"{timestamp}\",\"device\":\"{device_label}\",\"seq\":{seq}}"

    private static func json(_ id: String, _ name: String, _ url: String, template: String = standardJSON,
                             local: Bool = false, auth: Auth = .none) -> Profile {
        Profile(id: id, name: name,
                request: RequestSpec(method: "POST", url: url, body: BodySpec(type: .json, template: template), allowLocalHttp: local),
                auth: auth)
    }

    public static let all: [Preset] = [
        Preset(key: "ha_webhook") { json($0, "Home Assistant webhook", "http://homeassistant.local:8123/api/webhook/REPLACE_ME", local: true) },
        Preset(key: "ha_tag_scanned") {
            json($0, "Home Assistant tag", "http://homeassistant.local:8123/api/events/tag_scanned",
                 template: "{\"tag_id\":\"{uid}\",\"device_id\":\"{device_label|default:tappony}\"}",
                 local: true, auth: .bearer(secret: "HA_TOKEN"))
        },
        Preset(key: "node_red") { json($0, "Node-RED", "http://nodered.local:1880/REPLACE_ME", local: true) },
        Preset(key: "n8n") { json($0, "n8n", "https://n8n.example.com/webhook/REPLACE_ME") },
        Preset(key: "zapier") { json($0, "Zapier", "https://hooks.zapier.com/hooks/catch/REPLACE_ME/") },
        Preset(key: "make") { json($0, "Make", "https://hook.eu1.make.com/REPLACE_ME") },
        Preset(key: "ifttt") { json($0, "IFTTT", "https://maker.ifttt.com/trigger/REPLACE_ME/json/with/key/{secret:IFTTT_KEY}") },
        Preset(key: "ntfy") {
            Profile(id: $0, name: "ntfy", request: RequestSpec(
                method: "POST", url: "https://ntfy.sh/REPLACE_ME",
                headers: [Header("Title", "TapPony: {tag_label|default:tag scanned}")],
                body: BodySpec(type: .raw, template: "{uid} {chip} {payload}")))
        },
        Preset(key: "discord") { json($0, "Discord", "https://discord.com/api/webhooks/REPLACE_ME", template: "{\"content\":\"Tag {uid} scanned: {payload}\"}") },
        Preset(key: "slack") { json($0, "Slack", "https://hooks.slack.com/services/REPLACE_ME", template: "{\"text\":\"Tag {uid} scanned: {payload}\"}") },
        Preset(key: "google_sheets") { json($0, "Google Sheets (Apps Script)", "https://script.google.com/macros/s/REPLACE_ME/exec") },
        Preset(key: "php_csv") { json($0, "PHP CSV receiver", "https://example.com/tappony.php") },
        Preset(key: "generic_json") { json($0, "JSON POST", "https://example.com/REPLACE_ME") },
        Preset(key: "generic_form") {
            Profile(id: $0, name: "Form POST", request: RequestSpec(
                method: "POST", url: "https://example.com/REPLACE_ME",
                body: BodySpec(type: .form, fields: [FormField("uid", "{uid}"), FormField("payload", "{payload}"), FormField("timestamp", "{timestamp}")])))
        },
        Preset(key: "generic_get") {
            Profile(id: $0, name: "GET with query", request: RequestSpec(
                method: "GET", url: "https://example.com/REPLACE_ME?uid={uid}&t={timestamp}", body: BodySpec(type: .none)))
        },
    ]

    public static func byKey(_ key: String) -> Preset? { all.first { $0.key == key } }
}
