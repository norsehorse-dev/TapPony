import SwiftUI
import TapPonyKit

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var history: HistoryStore
    @State private var names: [String] = []
    @State private var adding = false
    @State private var newName = ""
    @State private var newValue = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Device label", text: $settings.deviceLabel)
                } header: {
                    Text("Device label")
                } footer: {
                    Text("Sent as {device_label} only if a profile uses it. Empty by default, so nothing identifies this phone.")
                }
                Section {
                    ForEach(names, id: \.self) { n in
                        HStack {
                            Text(n).font(.system(.body, design: .monospaced))
                            Spacer()
                            Text(RequestBuilder.mask).foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { idx in
                        idx.map { names[$0] }.forEach { SecretStore.remove($0) }
                        names = SecretStore.names()
                    }
                    Button("Add secret") { adding = true }
                } header: {
                    Text("Secrets")
                } footer: {
                    Text("Tokens and keys for {secret:NAME} and the auth helpers. Kept in the Keychain on this device only, never synced or backed up.")
                }
                Section {
                    Toggle("Each tag once per batch", isOn: $settings.oncePerBatch)
                } header: {
                    Text("Scanning")
                } footer: {
                    Text("In batch mode, a tag already sent in this batch is skipped. Start a new batch to count it again.")
                }
                Section {
                    Picker("Keep history", selection: Binding(
                        get: { settings.historyDays },
                        set: {
                            settings.historyDays = $0
                            history.applyRetention()
                        }
                    )) {
                        ForEach([7, 30, 90, 365], id: \.self) { d in Text("\(d) days").tag(d) }
                        Text("Until 1,000 scans").tag(0)
                    }
                } header: {
                    Text("History")
                } footer: {
                    Text("History stays on this device. It keeps at most 1,000 scans, and older ones are removed after the period you pick.")
                }
                Section("About") {
                    Text("TapPony \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""). Scan a tag, send a request you designed to a server you chose. No account, no cloud, no analytics. Suggested by a tester.")
                        .foregroundStyle(.secondary)
                    Link("Source code", destination: URL(string: "https://github.com/norsehorse-dev/TapPony")!)
                    Link("More from NorseHorse", destination: URL(string: "https://norsehor.se")!)
                }
            }
            .navigationTitle("Settings")
            .onAppear { names = SecretStore.names() }
            .alert("Add secret", isPresented: $adding) {
                TextField("Secret name", text: $newName)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Value", text: $newValue)
                Button("Save") {
                    if SecretStore.isValidName(newName) {
                        SecretStore.put(newName, newValue)
                        names = SecretStore.names()
                    }
                    newName = ""
                    newValue = ""
                }
                Button("Cancel", role: .cancel) {
                    newName = ""
                    newValue = ""
                }
            } message: {
                Text("Names use letters, digits and underscores, like HA_TOKEN.")
            }
        }
    }
}
