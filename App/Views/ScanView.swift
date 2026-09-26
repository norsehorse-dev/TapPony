import SwiftUI
import TapPonyKit

struct ScanView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var profiles: ProfileStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var rules: RulesStore
    @EnvironmentObject private var queue: OfflineQueue
    @EnvironmentObject private var scanner: ScanController

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    profilePicker
                    if !TagReaders.isAvailable {
                        Notice(text: String(localized: "This device can't read NFC tags. iPhone 7 or later is needed, and iPad has no NFC reader."))
                    } else if profiles.profiles.isEmpty {
                        Notice(text: String(localized: "Create a profile first. A profile says where each scan gets sent."))
                    }
                    batchBar
                    if queue.count > 0 {
                        HStack {
                            Text("\(queue.count) waiting to send").foregroundStyle(Palette.warn)
                            Spacer()
                            Button(queue.flushing ? String(localized: "Sending…") : String(localized: "Send now")) {
                                scanner.sendQueuedNow()
                            }
                            .disabled(queue.flushing)
                        }
                        .padding()
                        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))
                    }
                    Button(action: tapScan) {
                        VStack(spacing: 14) {
                            if busy {
                                ProgressView().controlSize(.large)
                            } else {
                                Image(systemName: scanner.batchOn ? "stop.circle.fill" : "wave.3.right.circle.fill")
                                    .font(.system(size: 88)).foregroundStyle(Palette.blue)
                            }
                            Text(buttonTitle).font(.title3.weight(.semibold))
                            if scanner.batchOn && scanner.skippedRepeats > 0 {
                                Text("\(scanner.skippedRepeats) repeat taps skipped").foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                    .disabled(!scanner.batchOn && (scanner.reading || !scanner.canScan))

                    if case .failed(let e) = scanner.state, let text = message(for: e) {
                        Notice(text: text)
                    }
                    if scanner.batchOn || !scanner.batchResults.isEmpty {
                        ForEach(scanner.batchResults) { BatchRow(outcome: $0) }
                    } else if case .done(let outcomes) = scanner.state {
                        ForEach(outcomes) { ResultCard(outcome: $0) }
                    }
                }
                .padding()
            }
            .background(Palette.charcoal)
            .navigationTitle("TapPony")
        }
    }

    private var busy: Bool {
        if scanner.batchOn { return false }
        if scanner.reading { return true }
        if case .sending = scanner.state { return true }
        return false
    }

    private var buttonTitle: String {
        if scanner.batchOn { return String(localized: "Stop batch") }
        if busy { return String(localized: "Working…") }
        return String(localized: "Scan a tag")
    }

    private func tapScan() {
        if scanner.batchOn { scanner.setBatch(false) } else { scanner.scan() }
    }

    private var batchBar: some View {
        HStack {
            Toggle("Batch", isOn: Binding(get: { scanner.batchOn }, set: { scanner.setBatch($0) }))
                .toggleStyle(.button)
                .disabled(!scanner.batchOn && (scanner.reading || !scanner.canScan))
            if scanner.batchOn || scanner.batchCount > 0 {
                Text("\(scanner.batchCount) scanned").foregroundStyle(.secondary)
                Spacer()
                Button("New batch") { scanner.newBatch() }
            } else {
                Spacer()
            }
        }
    }

    private var profilePicker: some View {
        Menu {
            ForEach(profiles.profiles) { p in
                Button(p.name) { settings.activeProfileId = p.id }
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.activeProfile?.name ?? String(localized: "No profile"))
                    if rules.current.enabled {
                        Text("Rules on: the tag picks the profile").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
            }
            .padding()
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))
        }
        .disabled(profiles.profiles.isEmpty)
    }

    private func message(for e: TagReadError) -> String? {
        switch e {
        case .cancelled, .timeout: return nil
        case .unavailable: return String(localized: "NFC reading isn't available right now.")
        case .systemBusy: return String(localized: "The system is busy with another NFC session. Try again in a moment.")
        case .moved: return String(localized: "The tag moved away before it was fully read. Hold it still and try again.")
        case .unsupported: return String(localized: "This tag type isn't supported. iPhone can't read MIFARE Classic badges.")
        case .other(let s):
            if let f = ScanFailure(rawValue: s) { return ScanController.failureText(f) }
            return s
        }
    }
}

struct BatchRow: View {
    let outcome: ScanOutcome

    var body: some View {
        HStack {
            Text(outcome.uid.isEmpty ? "?" : outcome.uid).font(.system(.body, design: .monospaced))
            Spacer()
            if let t = outcome.resultText ?? outcome.message {
                Text(t).foregroundStyle(.secondary).lineLimit(1)
            }
            Text(label).foregroundStyle(color)
        }
        .padding(.horizontal)
    }

    private var label: String {
        if outcome.queued { return String(localized: "Queued") }
        if outcome.buildError != nil { return String(localized: "Not sent") }
        if let s = outcome.result?.status { return "HTTP \(s)" }
        return String(localized: "Network error")
    }

    private var color: Color {
        if outcome.queued { return Palette.warn }
        return outcome.result?.ok == true ? Palette.ok : Palette.fail
    }
}

struct Notice: View {
    let text: String
    var body: some View {
        Text(text)
            .foregroundStyle(Palette.warn)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct ResultCard: View {
    let outcome: ScanOutcome

    var body: some View {
        let r = outcome.result
        let color: Color = outcome.queued ? Palette.warn
            : outcome.buildError != nil ? Palette.fail
            : (r == nil ? .secondary : (r!.ok ? Palette.ok : Palette.fail))
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(headline).font(.headline).foregroundStyle(color)
                Spacer()
                if let ms = r?.latencyMs { Text("\(ms) ms").foregroundStyle(.secondary) }
            }
            if let t = outcome.resultText {
                Text(t).font(.title2.weight(.semibold)).foregroundStyle(color)
            }
            if let m = outcome.message, m != outcome.resultText {
                Text(m).font(.title3)
            }
            Text(outcome.profileName).foregroundStyle(.secondary)
            if !outcome.uid.isEmpty { Text(outcome.uid).font(.system(.body, design: .monospaced)) }
            let detail = [outcome.chip, outcome.tagType].filter { !$0.isEmpty }.joined(separator: " · ")
            if !detail.isEmpty { Text(detail).foregroundStyle(.secondary) }
            if outcome.randomUid {
                Text("This tag shows a random ID each time, so its UID can't identify it. Use NDEF content or a TapPony launch link instead.")
                    .foregroundStyle(Palette.warn)
            }
            if let e = outcome.buildError { Text(ErrorText.explain(e)).foregroundStyle(Palette.fail) }
            if let e = r?.error { Text(e).font(.system(.footnote, design: .monospaced)).foregroundStyle(Palette.fail) }
            if let b = r?.responseBody, !b.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(String(b.prefix(600))).font(.system(.footnote, design: .monospaced)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))
    }

    private var headline: String {
        if outcome.queued { return String(localized: "Saved, sends when back online") }
        if outcome.buildError != nil { return String(localized: "Not sent") }
        if let s = outcome.result?.status { return "HTTP \(s)" }
        return String(localized: "Network error")
    }
}

enum ErrorText {
    static func explain(_ code: String) -> String {
        switch code {
        case "hostPolicy:localHttpNotEnabled":
            return String(localized: "This profile sends plain HTTP to a local address. Turn on \"Allow plain HTTP on the local network\" in the profile to send it.")
        case "hostPolicy:plainHttpPublic":
            return String(localized: "Plain HTTP only goes to local network addresses. Use https:// for anything on the internet.")
        case "hostPolicy:numericHost":
            return String(localized: "That host looks like a number written in an unusual form. Write IP addresses as four plain numbers, like 192.168.1.10.")
        case "hostPolicy:userinfo":
            return String(localized: "Put credentials in a header or the auth section, not in the URL.")
        case "template:unknownSecret":
            return String(localized: "The profile uses a secret that isn't saved on this device. Add it in Settings.")
        case "template:invalidJsonBody":
            return String(localized: "The JSON body isn't valid JSON after filling in the variables.")
        case "badHeaderName":
            return String(localized: "Header names can only use letters, digits and - _ . characters.")
        default:
            if code.hasPrefix("hostPolicy:") || code.hasPrefix("urlTemplate:") {
                return String(localized: "The URL isn't valid. It needs to start with https:// or http:// and the host can't contain variables.")
            }
            if code.hasPrefix("template:") {
                return String(localized: "Template problem: \(String(code.dropFirst("template:".count)))")
            }
            return code
        }
    }
}
