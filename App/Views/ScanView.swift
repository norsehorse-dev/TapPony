import SwiftUI
import TapPonyKit

struct ScanView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var profiles: ProfileStore
    @EnvironmentObject private var settings: AppSettings

    @State private var busy = false
    @State private var outcome: ScanOutcome?
    @State private var readError: TagReadError?

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
                    Button(action: scan) {
                        VStack(spacing: 14) {
                            if busy {
                                ProgressView().controlSize(.large)
                            } else {
                                Image(systemName: "wave.3.right.circle.fill").font(.system(size: 88)).foregroundStyle(Palette.blue)
                            }
                            Text(busy ? "Working…" : "Scan a tag").font(.title3.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                    .disabled(busy || model.activeProfile == nil || !TagReaders.isAvailable)

                    if let e = readError, let text = message(for: e) {
                        Notice(text: text)
                    }
                    if let o = outcome {
                        ResultCard(outcome: o)
                    }
                }
                .padding()
            }
            .background(Palette.charcoal)
            .navigationTitle("TapPony")
        }
    }

    private var profilePicker: some View {
        Menu {
            ForEach(profiles.profiles) { p in
                Button(p.name) { settings.activeProfileId = p.id }
            }
        } label: {
            HStack {
                Text(model.activeProfile?.name ?? String(localized: "No profile"))
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
            }
            .padding()
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))
        }
        .disabled(profiles.profiles.isEmpty)
    }

    private func scan() {
        guard let p = model.activeProfile else { return }
        busy = true
        readError = nil
        Task {
            defer { busy = false }
            do {
                let reading = try await TagReaders.default().read(
                    technologies: p.tag.technologies, extendedReads: p.tag.extendedReads,
                    alert: String(localized: "Hold near the tag"))
                let scanTime = Int64(Date().timeIntervalSince1970 * 1000)
                if p.tag.requireNdef && reading.ndef.isEmpty {
                    readError = .other("noNdef")
                    return
                }
                outcome = await model.engine.run(p, reading: reading, scanTimeMs: scanTime)
            } catch let e as TagReadError {
                readError = e
            } catch {
                readError = .other(error.localizedDescription)
            }
        }
    }

    private func message(for e: TagReadError) -> String? {
        switch e {
        case .cancelled, .timeout: return nil
        case .unavailable: return String(localized: "NFC reading isn't available right now.")
        case .systemBusy: return String(localized: "The system is busy with another NFC session. Try again in a moment.")
        case .moved: return String(localized: "The tag moved away before it was fully read. Hold it still and try again.")
        case .unsupported: return String(localized: "This tag type isn't supported. iPhone can't read MIFARE Classic badges.")
        case .other(let s) where s == "noNdef": return String(localized: "This profile needs a tag with NDEF content, and this tag has none.")
        case .other(let s): return s
        }
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
        let color: Color = outcome.buildError != nil ? Palette.fail : (r == nil ? .secondary : (r!.ok ? Palette.ok : Palette.fail))
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(headline).font(.headline).foregroundStyle(color)
                Spacer()
                if let ms = r?.latencyMs { Text("\(ms) ms").foregroundStyle(.secondary) }
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
