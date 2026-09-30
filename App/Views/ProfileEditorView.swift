import SwiftUI
import UIKit
import TapPonyKit

struct ProfileEditorView: View {
    let profileId: String
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var profiles: ProfileStore
    @Environment(\.dismiss) private var dismiss

    @State private var p: Profile?
    @State private var testing = false
    @State private var testOutcome: ScanOutcome?
    @State private var confirmDelete = false
    @State private var secretNames: Set<String> = []

    var body: some View {
        Group {
            if let binding = Binding($p) {
                form(binding)
            } else {
                ProgressView()
            }
        }
        .onAppear {
            if p == nil { p = profiles.profile(profileId) }
            secretNames = Set(SecretStore.names())
        }
    }

    @ViewBuilder
    private func form(_ p: Binding<Profile>) -> some View {
        Form {
            Section {
                TextField("Name", text: p.name)
            }
            Section("Request") {
                Picker("Method", selection: p.request.method) {
                    ForEach(Profile.methods, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.segmented)
                TextField("URL", text: p.request.url, axis: .vertical)
                    .font(.system(.body, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                if p.wrappedValue.request.url.lowercased().hasPrefix("http://") {
                    Toggle("Allow plain HTTP on the local network", isOn: p.request.allowLocalHttp)
                    Text("Anyone on the same Wi-Fi can read a plain HTTP request, including any secrets in it.")
                        .font(.footnote).foregroundStyle(Palette.warn)
                }
                Toggle("Follow redirects (same host only)", isOn: p.request.followRedirects)
            }
            Section("Headers") {
                ForEach(p.request.headers.indices, id: \.self) { i in
                    VStack(alignment: .leading) {
                        TextField("Header", text: p.request.headers[i].name)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                        TextField("Value", text: p.request.headers[i].value)
                            .font(.system(.body, design: .monospaced))
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                        Toggle("Secret (masked everywhere)", isOn: p.request.headers[i].secret)
                    }
                }
                .onDelete { p.wrappedValue.request.headers.remove(atOffsets: $0) }
                Button("Add header") { p.wrappedValue.request.headers.append(Header("", "")) }
            }
            Section("Authentication") {
                Picker("Type", selection: authKind(p)) {
                    Text("None").tag("none")
                    Text("Bearer").tag("bearer")
                    Text("Basic").tag("basic")
                    Text("API key").tag("apiKey")
                }
                authFields(p)
            }
            Section("Body") {
                Picker("Type", selection: p.request.body.type) {
                    ForEach(BodyType.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                switch p.wrappedValue.request.body.type {
                case .json, .raw:
                    TextEditor(text: p.request.body.template)
                        .font(.system(.footnote, design: .monospaced))
                        .frame(minHeight: 120)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                case .form:
                    ForEach(p.request.body.fields.indices, id: \.self) { i in
                        HStack {
                            TextField("Field", text: p.request.body.fields[i].name)
                            TextField("Value", text: p.request.body.fields[i].value).font(.system(.body, design: .monospaced))
                        }
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                    .onDelete { p.wrappedValue.request.body.fields.remove(atOffsets: $0) }
                    Button("Add field") { p.wrappedValue.request.body.fields.append(FormField("", "")) }
                case .none:
                    EmptyView()
                }
                if p.wrappedValue.request.body.type != .none {
                    TextField("Content-Type (optional)", text: Binding(
                        get: { p.wrappedValue.request.body.contentType ?? "" },
                        set: { p.wrappedValue.request.body.contentType = $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
                    ))
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                }
            }
            Section("Signing") {
                Toggle("Sign requests with HMAC-SHA256", isOn: Binding(
                    get: { p.wrappedValue.signing.enabled },
                    set: {
                        p.wrappedValue.signing.enabled = $0
                        if p.wrappedValue.signing.secret == nil { p.wrappedValue.signing.secret = "HMAC_KEY" }
                    }
                ))
                if p.wrappedValue.signing.enabled {
                    SecretNameField(value: Binding(get: { p.wrappedValue.signing.secret ?? "" }, set: { p.wrappedValue.signing.secret = $0 }))
                }
            }
            Section("Tag") {
                Toggle("Read chip details (model, signature, counter)", isOn: p.tag.extendedReads)
                Toggle("Only send when the tag has NDEF content", isOn: p.tag.requireNdef)
            }
            Section {
                if Entitlements.responseRules {
                    VStack(alignment: .leading, spacing: 2) {
                        TextField("Show from the reply", text: optional(p.after.messageField))
                            .font(.system(.body, design: .monospaced))
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                        Text("json:path.to.field or header:Name. Shown on the Scan tab after each tap.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        TextField("Text on success (optional)", text: optional(p.after.successText))
                        TextField("Text on failure (optional)", text: optional(p.after.failureText))
                        Text("Shown big after a scan. Can use {message}, {status}, {uid} and {profile}.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Toggle("Say the result out loud", isOn: p.after.speak)
                }
                Toggle("Keep request and response bodies in history", isOn: p.after.keepBodies)
                if Entitlements.offlineQueue {
                    Toggle("Save and send later when offline", isOn: p.after.queueOffline)
                    if p.wrappedValue.after.queueOffline {
                        Text("If a scan gets no response, it waits on this phone and goes out in order once there's a connection, for up to 24 hours. Receivers can spot a repeat by its {nonce}. Leave this off for things like door locks, where a late request would be wrong.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Toggle("Sound after each scan", isOn: p.after.sound)
                Toggle("Vibrate with the result", isOn: p.after.haptic)
            } header: {
                Text("After sending")
            }
            let problems = validate(p.wrappedValue)
            if !problems.isEmpty {
                Section("Needs attention") {
                    ForEach(problems, id: \.self) { Text($0).foregroundStyle(Palette.warn) }
                }
            }
            Section {
                Button(testing ? "Testing…" : "Test") {
                    testing = true
                    let snapshot = p.wrappedValue
                    Task {
                        testOutcome = await model.engine.test(snapshot)
                        testing = false
                    }
                }
                .disabled(testing)
                ShareLink("Export", item: ProfileCodec.encode(p.wrappedValue))
                Button("Copy scan link") {
                    UIPasteboard.general.string = "tappony://scan?profile=\(p.wrappedValue.id)"
                }
            } footer: {
                Text("Test sends sample values from a pretend NTAG215, not a real tag. The scan link opens TapPony and starts a scan with this profile, from Shortcuts, a bookmark, or another app.")
            }
            if let o = testOutcome {
                Section("Test result") {
                    ResultCard(outcome: o).listRowInsets(EdgeInsets())
                    if let r = o.request {
                        Text(([ "\(r.method) \(r.url)" ] + r.headers.map { "\($0.0): \($0.1)" } + [r.body].compactMap { $0 }).joined(separator: "\n"))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                Button("Delete profile", role: .destructive) { confirmDelete = true }
            }
        }
        .navigationTitle(p.wrappedValue.name.isEmpty ? String(localized: "Untitled") : p.wrappedValue.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("Save") {
                profiles.save(p.wrappedValue)
                dismiss()
            }
        }
        .confirmationDialog("Delete \(p.wrappedValue.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete profile", role: .destructive) {
                profiles.delete(p.wrappedValue.id)
                dismiss()
            }
        }
    }

    /// An optional text field: empty means nil.
    private func optional(_ b: Binding<String?>) -> Binding<String> {
        Binding(get: { b.wrappedValue ?? "" }, set: { b.wrappedValue = $0.isEmpty ? nil : $0 })
    }

    private func authKind(_ p: Binding<Profile>) -> Binding<String> {
        Binding(
            get: {
                switch p.wrappedValue.auth {
                case .none: return "none"
                case .bearer: return "bearer"
                case .basic: return "basic"
                case .apiKey: return "apiKey"
                }
            },
            set: { kind in
                switch kind {
                case "bearer": p.wrappedValue.auth = .bearer(secret: "TOKEN")
                case "basic": p.wrappedValue.auth = .basic(username: "", passwordSecret: "PASSWORD")
                case "apiKey": p.wrappedValue.auth = .apiKey(header: "X-API-Key", secret: "API_KEY")
                default: p.wrappedValue.auth = .none
                }
            }
        )
    }

    @ViewBuilder
    private func authFields(_ p: Binding<Profile>) -> some View {
        switch p.wrappedValue.auth {
        case .none:
            EmptyView()
        case .bearer(let s):
            SecretNameField(value: Binding(get: { s }, set: { p.wrappedValue.auth = .bearer(secret: $0) }))
        case .basic(let u, let ps):
            TextField("Username", text: Binding(get: { u }, set: { p.wrappedValue.auth = .basic(username: $0, passwordSecret: ps) }))
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            SecretNameField(value: Binding(get: { ps }, set: { p.wrappedValue.auth = .basic(username: u, passwordSecret: $0) }))
        case .apiKey(let h, let s):
            TextField("Header", text: Binding(get: { h }, set: { p.wrappedValue.auth = .apiKey(header: $0, secret: s) }))
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            SecretNameField(value: Binding(get: { s }, set: { p.wrappedValue.auth = .apiKey(header: h, secret: $0) }))
        }
    }

    private func validate(_ p: Profile) -> [String] {
        var out: [String] = []
        switch HostPolicy.checkTemplate(p.request.url) {
        case "templatedAuthority": out.append(String(localized: "The scheme and host of the URL must be typed out, not built from variables."))
        case "malformed": out.append(ErrorText.explain("urlTemplate:malformed"))
        default: break
        }
        let templates = [p.request.url] + p.request.headers.map(\.value) + [p.request.body.template] +
            p.request.body.fields.flatMap { [$0.name, $0.value] }
        var unknown = Set<String>()
        var parseError: String?
        for t in templates {
            do { unknown.formUnion(try Template.referencedVariables(t).subtracting(Variables.all)) } catch let e as TemplateError { parseError = e.code } catch {}
        }
        if let e = parseError { out.append(ErrorText.explain("template:\(e)")) }
        if !unknown.isEmpty { out.append(String(localized: "Unknown variables: \(unknown.sorted().joined(separator: ", "))")) }
        let missing = RequestBuilder.requiredSecrets(p).subtracting(secretNames)
        if !missing.isEmpty { out.append(String(localized: "Secrets not saved on this device yet: \(missing.sorted().joined(separator: ", "))")) }
        if p.request.headers.contains(where: { $0.name.trimmingCharacters(in: .whitespaces).isEmpty }) {
            out.append(ErrorText.explain("badHeaderName"))
        }
        if let f = p.after.messageField, !f.hasPrefix("json:"), !f.hasPrefix("header:") {
            out.append(String(localized: "\"Show from the reply\" must start with json: or header:."))
        }
        return out
    }
}

struct SecretNameField: View {
    @Binding var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            TextField("Secret name", text: Binding(
                get: { value },
                set: { value = String($0.unicodeScalars.filter { $0.isASCII && (CharacterSet.alphanumerics.contains($0) || $0 == "_") }) }
            ))
            .font(.system(.body, design: .monospaced))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            Text("Saved in Settings. The value never appears in the profile, history or exports.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
