import SwiftUI
import TapPonyKit

struct ProfilesView: View {
    @EnvironmentObject private var profiles: ProfileStore
    @EnvironmentObject private var rules: RulesStore
    @State private var picking = false
    @State private var path: [String] = []

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    NavigationLink {
                        RulesView()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Rules").font(.headline)
                            Text(rulesStatus).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
                if profiles.profiles.isEmpty {
                    Text("No profiles yet. Tap + to start from a preset.").foregroundStyle(.secondary)
                }
                ForEach(profiles.profiles) { p in
                    NavigationLink(value: p.id) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(p.name).font(.headline)
                            Text("\(p.request.method) \(p.request.url)")
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
            }
            .navigationTitle("Profiles")
            .navigationDestination(for: String.self) { id in
                ProfileEditorView(profileId: id)
            }
            .toolbar {
                Button { picking = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("New profile")
            }
            .sheet(isPresented: $picking) {
                PresetPicker { profile in
                    profiles.save(profile)
                    picking = false
                    path.append(profile.id)
                }
            }
        }
    }
}

extension ProfilesView {
    fileprivate var rulesStatus: String {
        let set = rules.current
        guard set.enabled else { return String(localized: "Off. Every scan goes to the profile picked on the Scan tab.") }
        return set.rules.count == 1 ? String(localized: "On, 1 rule") : String(localized: "On, \(set.rules.count) rules")
    }
}

struct PresetPicker: View {
    let onPick: (Profile) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Button {
                    onPick(Profile(id: ProfileStore.newId(), name: String(localized: "Blank profile"),
                                   request: RequestSpec(url: "https://", body: BodySpec(type: .json, template: "{\"uid\":\"{uid}\"}"))))
                } label: {
                    Text("Blank profile")
                }
                ForEach(Presets.all, id: \.key) { preset in
                    Button {
                        onPick(preset.create(ProfileStore.newId()))
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(PresetText.title(preset.key)).foregroundStyle(.primary)
                            Text(PresetText.explainer(preset.key)).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("New profile")
            .toolbar { Button("Cancel") { dismiss() } }
        }
    }
}

/// Localized preset titles and explainers, keyed like the Android string resources.
enum PresetText {
    static func title(_ key: String) -> String {
        switch key {
        case "ha_webhook": return String(localized: "Home Assistant webhook")
        case "ha_tag_scanned": return String(localized: "Home Assistant tag")
        case "node_red": return String(localized: "Node-RED")
        case "n8n": return String(localized: "n8n")
        case "zapier": return String(localized: "Zapier")
        case "make": return String(localized: "Make")
        case "ifttt": return String(localized: "IFTTT")
        case "ntfy": return String(localized: "ntfy")
        case "discord": return String(localized: "Discord")
        case "slack": return String(localized: "Slack")
        case "google_sheets": return String(localized: "Google Sheets")
        case "php_csv": return String(localized: "PHP CSV receiver")
        case "generic_json": return String(localized: "JSON POST")
        case "generic_form": return String(localized: "Form POST")
        case "generic_get": return String(localized: "GET with query")
        default: return key
        }
    }

    static func explainer(_ key: String) -> String {
        switch key {
        case "ha_webhook": return String(localized: "In Home Assistant, create an automation with a Webhook trigger, copy its webhook ID into the URL, and use trigger.json.uid in the actions.")
        case "ha_tag_scanned": return String(localized: "Fires a tag_scanned event with the card's UID as tag_id, so an existing badge works as a Home Assistant tag. Save a long-lived access token as the secret HA_TOKEN.")
        case "node_red": return String(localized: "Add an http in node (POST) and put its path in the URL.")
        case "n8n": return String(localized: "Use the production URL of a Webhook node set to POST.")
        case "zapier": return String(localized: "Paste the URL from a Catch Hook trigger.")
        case "make": return String(localized: "Paste the URL from a Custom webhook module.")
        case "ifttt": return String(localized: "Put your event name in the URL and save your Webhooks key as the secret IFTTT_KEY.")
        case "ntfy": return String(localized: "Posts a plain-text notification to an ntfy topic. Pick a topic name nobody will guess, or use your own ntfy server.")
        case "discord": return String(localized: "Paste a channel webhook URL from the channel's Integrations settings.")
        case "slack": return String(localized: "Paste an incoming webhook URL from your Slack app.")
        case "google_sheets": return String(localized: "Deploy an Apps Script web app whose doPost appends a row, and paste its /exec URL.")
        case "php_csv": return String(localized: "For your own server: a ten-line PHP script that appends each scan to a CSV file. The script is on tappony.app.")
        case "generic_json": return String(localized: "Posts the tag details as JSON to any endpoint.")
        case "generic_form": return String(localized: "Posts uid, payload and timestamp as a web form.")
        case "generic_get": return String(localized: "Sends the UID and time in the query string. Handy for simple logging endpoints.")
        default: return ""
        }
    }
}
