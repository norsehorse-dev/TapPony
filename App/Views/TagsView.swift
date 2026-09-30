import SwiftUI
import TapPonyKit

/// Tags: write your own tags, and name the ones you use (PROFILE_SCHEMA.md section 16).
struct TagsView: View {
    @EnvironmentObject private var tags: TagsStore
    @EnvironmentObject private var profiles: ProfileStore
    @EnvironmentObject private var history: HistoryStore

    private enum Kind: String, CaseIterable, Hashable { case launch, url, text, mirror }

    @State private var kind: Kind = .launch
    @State private var content = "https://"
    @State private var launchLabel = ""
    @State private var launchProfile: String?
    @State private var lock = false
    @State private var confirmLock = false
    @State private var writing = false
    @State private var result: String?
    @State private var resultOk = true
    @State private var editing: TagEntry?
    @State private var writer = TagWriter()

    private var lastUid: String? { history.entries.first { !$0.uid.isEmpty }?.uid }

    private var canWrite: Bool {
        switch kind {
        case .url: let t = content.trimmingCharacters(in: .whitespaces); return t.contains(":") && t.count > 3 && URL(string: t) != nil
        case .text: return !content.isEmpty
        default: return true
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Record", selection: $kind) {
                        Text("Launch link").tag(Kind.launch)
                        Text("Link").tag(Kind.url)
                        Text("Text").tag(Kind.text)
                        Text("Mirror UID").tag(Kind.mirror)
                    }
                    .pickerStyle(.segmented)
                    Text(help(kind)).font(.footnote).foregroundStyle(.secondary)
                    switch kind {
                    case .url:
                        TextField("Link", text: $content)
                            .font(.system(.body, design: .monospaced))
                            .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    case .text:
                        TextField("Text", text: $content, axis: .vertical)
                    case .launch:
                        TextField("Name", text: Binding(get: { launchLabel }, set: { launchLabel = String($0.prefix(64)) }))
                        if Entitlements.tagDefaults { profilePicker($launchProfile) }
                    case .mirror:
                        EmptyView()
                    }
                    Toggle("Lock after writing", isOn: $lock)
                    if lock {
                        Text("Makes the tag read-only for good. Nobody can change it afterwards, including you.")
                            .font(.footnote).foregroundStyle(Palette.warn)
                    }
                    Button(writing ? String(localized: "Writing…") : (lock ? String(localized: "Write and lock") : String(localized: "Write"))) {
                        if lock { confirmLock = true } else { startWrite() }
                    }
                    .disabled(writing || !canWrite)
                    if let r = result {
                        Text(r).foregroundStyle(resultOk ? Palette.ok : Palette.fail)
                    }
                } header: {
                    Text("Write a tag")
                }

                Section {
                    if tags.current.tags.isEmpty {
                        Text("No named tags yet. Launch links you write show up here.").foregroundStyle(.secondary)
                    }
                    ForEach(tags.current.tags) { t in
                        Button { editing = t } label: { row(t) }
                            .buttonStyle(.plain)
                    }
                    if let last = lastUid, !tags.current.tags.contains(where: { $0.uid == Tags.normUid(last) }),
                       Entitlements.canAddTag(count: tags.current.tags.count) {
                        Button("Name last scanned tag (\(last))") { editing = TagEntry(uid: Tags.normUid(last), label: "") }
                    }
                } header: {
                    Text("Your tags")
                } footer: {
                    Text("Name a tag to use {tag_label} and name rules, or give it its own profile. The name stays on this phone.")
                }
            }
            .navigationTitle("Tags")
            .confirmationDialog("Lock this tag for good?", isPresented: $confirmLock, titleVisibility: .visible) {
                Button("Write and lock", role: .destructive) { startWrite() }
            } message: {
                Text("After this write the tag can never be changed or erased. There is no undo.")
            }
            .sheet(item: $editing) { t in
                TagEditor(original: t, isNew: !tags.current.tags.contains(t))
            }
        }
    }

    private func row(_ t: TagEntry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(t.label.isEmpty ? String(localized: "Untitled") : t.label).font(.headline)
            if !t.uid.isEmpty { Text(t.uid).font(.system(.footnote, design: .monospaced)).foregroundStyle(.secondary) }
            if !t.token.isEmpty { Text("Has a TapPony launch link").font(.footnote).foregroundStyle(Palette.blueLight) }
            if let id = t.profile {
                Text("Sends to \(profiles.profile(id)?.name ?? String(localized: "a deleted profile"))")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }

    private func profilePicker(_ selection: Binding<String?>) -> some View {
        Picker("Send to", selection: selection) {
            Text("Usual profile").tag(String?.none)
            ForEach(profiles.profiles) { p in Text(p.name).tag(String?.some(p.id)) }
        }
    }

    private func help(_ k: Kind) -> String {
        switch k {
        case .launch: return String(localized: "Tapping this tag opens TapPony and sends it, even when the app is closed. Only this phone knows the tag, so it sends nothing on anyone else's.")
        case .url: return String(localized: "Any phone that taps this tag opens the link.")
        case .text: return String(localized: "Plain text, readable by any NFC app and by {ndef_text} in TapPony.")
        case .mirror: return String(localized: "Writes the tag's own UID as text, so apps that only read NDEF can see it.")
        }
    }

    private func startWrite() {
        if kind == .launch && !Entitlements.canAddTag(count: tags.current.tags.count) { return }
        let job: WriteJob
        switch kind {
        case .url: job = .url(content.trimmingCharacters(in: .whitespaces))
        case .text: job = .text(content)
        case .mirror: job = .mirrorUid
        case .launch: job = .launch(token: Tags.newToken(), label: launchLabel.trimmingCharacters(in: .whitespaces), profileId: launchProfile)
        }
        let locking = lock
        writing = true
        result = nil
        Task {
            defer { writing = false }
            do {
                let uid = try await writer.write(job, lock: locking)
                register(job, uid: uid)
                resultOk = true
                result = locking ? String(localized: "Written and locked") : String(localized: "Written")
                if !uid.isEmpty { result! += " · \(uid)" }
            } catch let e as WriteError {
                if e.code == "cancelled" || e.code == "timeout" { return }
                // The link is on the tag even though locking failed, so the registry must know its token.
                if e.code == "lockFailed", let uid = e.uid { register(job, uid: uid) }
                resultOk = false
                result = Self.errorText(e.code)
            } catch {
                resultOk = false
                result = Self.errorText("failed")
            }
        }
    }

    /// A written launch link names its tag in the registry.
    private func register(_ job: WriteJob, uid: String) {
        guard case .launch(let token, let label, let profileId) = job else { return }
        let existing = uid.isEmpty ? nil : tags.current.tags.first { $0.uid == uid }
        let entry = TagEntry(uid: uid, label: label.isEmpty ? (existing?.label ?? "") : label,
                             notes: existing?.notes ?? "", profile: profileId, token: token)
        tags.upsert(entry, replacing: existing)
    }

    static func errorText(_ code: String) -> String {
        switch code {
        case "readOnly": return String(localized: "This tag is locked, so it can't be written.")
        case "tooSmall": return String(localized: "This tag doesn't have room for that. Try something shorter or a bigger tag.")
        case "notNdef": return String(localized: "This tag can't hold NDEF content, so it can't be written here.")
        case "randomUid": return String(localized: "This tag shows a random ID each time, so there's no fixed UID to copy.")
        case "lockFailed": return String(localized: "Written, but locking failed. The tag is still writable.")
        case "unavailable": return String(localized: "NFC reading isn't available right now.")
        case "moved": return String(localized: "The tag moved away before the write finished. Hold it still and try again.")
        default: return String(localized: "The write failed. Try again.")
        }
    }
}

private struct TagEditor: View {
    let original: TagEntry
    let isNew: Bool

    @EnvironmentObject private var tags: TagsStore
    @EnvironmentObject private var profiles: ProfileStore
    @Environment(\.dismiss) private var dismiss
    @State private var t: TagEntry

    init(original: TagEntry, isNew: Bool) {
        self.original = original
        self.isNew = isNew
        _t = State(initialValue: original)
    }

    var body: some View {
        NavigationStack {
            Form {
                if !t.uid.isEmpty {
                    Text(t.uid).font(.system(.body, design: .monospaced)).foregroundStyle(.secondary)
                }
                if !t.token.isEmpty {
                    Text("Has a TapPony launch link").foregroundStyle(Palette.blueLight)
                }
                TextField("Name", text: Binding(get: { t.label }, set: { t.label = String($0.prefix(64)) }))
                if Entitlements.tagDefaults {
                    TextField("Notes", text: Binding(get: { t.notes }, set: { t.notes = String($0.prefix(500)) }), axis: .vertical)
                    Picker("Send to", selection: $t.profile) {
                        Text("Usual profile").tag(String?.none)
                        ForEach(profiles.profiles) { p in Text(p.name).tag(String?.some(p.id)) }
                    }
                }
                if !isNew {
                    Button("Forget this tag", role: .destructive) {
                        tags.remove(original)
                        dismiss()
                    }
                }
            }
            .navigationTitle(isNew ? String(localized: "Name a tag") : String(localized: "Edit tag"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        tags.upsert(t, replacing: isNew ? nil : original)
                        dismiss()
                    }
                }
            }
        }
    }
}
