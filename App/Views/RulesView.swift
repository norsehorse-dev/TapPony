import SwiftUI
import TapPonyKit

/// Rules: route each tag to the right profiles (PROFILE_SCHEMA.md section 14).
struct RulesView: View {
    @EnvironmentObject private var rules: RulesStore
    @EnvironmentObject private var profiles: ProfileStore
    @EnvironmentObject private var history: HistoryStore

    @State private var editing: Rule?

    private var lastUid: String? { history.entries.first { !$0.uid.isEmpty }?.uid }

    var body: some View {
        let set = rules.current
        List {
            Section {
                Toggle("Use rules", isOn: Binding(get: { set.enabled }, set: { on in update { $0.enabled = on } }))
            } footer: {
                Text("Pick the profile by the tag itself, so the garage sticker and the office badge can go to different places without switching.")
            }
            Section("When no rule matches") {
                Picker("When no rule matches", selection: Binding(get: { set.unmatched }, set: { v in update { $0.unmatched = v } })) {
                    Text("Use the Scan tab profile").tag(RuleSet.unmatchedActive)
                    Text("Send nothing").tag(RuleSet.unmatchedIgnore)
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
            Section {
                if set.rules.isEmpty {
                    Text("No rules yet.").foregroundStyle(.secondary)
                }
                ForEach(set.rules) { r in
                    Button { editing = r } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(r.name.isEmpty ? String(localized: "Untitled") : r.name).font(.headline)
                                Spacer()
                                if !r.enabled { Text("Off").foregroundStyle(.secondary) }
                            }
                            Text(RuleText.describe(r, profiles.profiles)).font(.footnote).foregroundStyle(.secondary)
                            if let e = RuleText.liveError(r, profiles.profiles) {
                                Text(RuleText.error(e)).font(.footnote).foregroundStyle(Palette.warn)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                .onMove { from, to in update { $0.rules.move(fromOffsets: from, toOffset: to) } }
                .onDelete { idx in update { $0.rules.remove(atOffsets: idx) } }
                Button("Add rule") {
                    editing = Rule(id: "R-" + ProfileStore.newId(), name: "",
                                   match: RuleMatch(field: "uid", op: "equals", value: lastUid ?? ""), profiles: [])
                }
            } header: {
                Text("Rules")
            } footer: {
                Text("Checked from the top. The first match decides, and every profile it lists gets the scan.")
            }
        }
        .navigationTitle("Rules")
        .toolbar { EditButton() }
        .sheet(item: $editing) { r in
            RuleEditor(original: r, isNew: !set.rules.contains { $0.id == r.id }, lastUid: lastUid) { result in
                switch result {
                case .save(let rule):
                    update { s in
                        if let i = s.rules.firstIndex(where: { $0.id == rule.id }) { s.rules[i] = rule } else { s.rules.append(rule) }
                    }
                case .delete(let id):
                    update { $0.rules.removeAll { $0.id == id } }
                }
                editing = nil
            }
        }
    }

    private func update(_ change: (inout RuleSet) -> Void) {
        var s = rules.current
        change(&s)
        rules.save(s)
    }
}

private enum RuleEditResult {
    case save(Rule)
    case delete(String)
}

private struct RuleEditor: View {
    let isNew: Bool
    let lastUid: String?
    let onDone: (RuleEditResult) -> Void

    @EnvironmentObject private var profiles: ProfileStore
    @Environment(\.dismiss) private var dismiss
    @State private var r: Rule

    init(original: Rule, isNew: Bool, lastUid: String?, onDone: @escaping (RuleEditResult) -> Void) {
        self.isNew = isNew
        self.lastUid = lastUid
        self.onDone = onDone
        _r = State(initialValue: original)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: Binding(get: { r.name }, set: { r.name = String($0.prefix(64)) }))
                }
                Section("When") {
                    Picker("Field", selection: $r.match.field) {
                        ForEach(Rules.fields, id: \.self) { Text(RuleText.field($0)).tag($0) }
                    }
                    Picker("Test", selection: $r.match.op) {
                        ForEach(Rules.ops, id: \.self) { Text(RuleText.op($0)).tag($0) }
                    }
                    TextField("Value", text: $r.match.value)
                        .font(.system(.body, design: .monospaced))
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    if r.match.field == "uid", let last = lastUid {
                        Button("Use last scanned tag (\(last))") { r.match.value = last }
                    }
                }
                Section("Send to") {
                    ForEach(profiles.profiles) { p in
                        Toggle(p.name, isOn: Binding(
                            get: { r.profiles.contains(p.id) },
                            set: { on in
                                if on { if !r.profiles.contains(p.id) { r.profiles.append(p.id) } } else { r.profiles.removeAll { $0 == p.id } }
                            }
                        ))
                    }
                }
                Section {
                    Toggle("Rule is on", isOn: $r.enabled)
                    if let e = RuleText.liveError(r, profiles.profiles) {
                        Text(RuleText.error(e)).foregroundStyle(Palette.warn)
                    }
                }
                if !isNew {
                    Section {
                        Button("Delete rule", role: .destructive) { onDone(.delete(r.id)) }
                    }
                }
            }
            .navigationTitle(isNew ? String(localized: "Add rule") : String(localized: "Edit rule"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { onDone(.save(r)) } }
            }
        }
    }
}

enum RuleText {
    /// Rules.error, counting only profiles that still exist.
    static func liveError(_ r: Rule, _ profiles: [Profile]) -> String? {
        var live = r
        live.profiles = r.profiles.filter { id in profiles.contains { $0.id == id } }
        return Rules.error(live)
    }

    static func describe(_ r: Rule, _ profiles: [Profile]) -> String {
        let names = r.profiles.compactMap { id in profiles.first { $0.id == id }?.name }
        let target = names.isEmpty ? String(localized: "no profiles") : names.joined(separator: ", ")
        return "\(field(r.match.field)) \(op(r.match.op)) \"\(r.match.value)\" → \(target)"
    }

    static func field(_ f: String) -> String {
        switch f {
        case "uid": return String(localized: "UID")
        case "tag_type": return String(localized: "Tag type")
        case "chip": return String(localized: "Chip")
        case "manufacturer": return String(localized: "Maker")
        case "payload": return String(localized: "Content")
        case "ndef_text": return String(localized: "NDEF text")
        case "ndef_uri": return String(localized: "NDEF link")
        case "tag_label": return String(localized: "Tag name")
        default: return f
        }
    }

    static func op(_ o: String) -> String {
        switch o {
        case "equals": return String(localized: "is")
        case "prefix": return String(localized: "starts with")
        case "contains": return String(localized: "contains")
        case "regex": return String(localized: "matches pattern")
        default: return o
        }
    }

    static func error(_ code: String) -> String {
        switch code {
        case "badRegex": return String(localized: "The pattern isn't valid, so this rule never matches.")
        case "noProfiles": return String(localized: "Pick at least one profile to send to.")
        default: return String(localized: "This rule can't be used.")
        }
    }
}
