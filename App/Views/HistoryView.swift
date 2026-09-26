import SwiftUI
import TapPonyKit
import UIKit

struct HistoryView: View {
    @EnvironmentObject private var history: HistoryStore

    private enum Filter: Hashable { case all, ok, failed }

    @State private var filter: Filter = .all
    @State private var selected: HistoryEntry?
    @State private var confirmClear = false
    @State private var export: ExportFile?

    private var shown: [HistoryEntry] {
        switch filter {
        case .all: return history.entries
        case .ok: return history.entries.filter { $0.outcome == HistoryCsv.ok }
        case .failed: return history.entries.filter { $0.outcome != HistoryCsv.ok }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Picker("Show", selection: $filter) {
                    Text("All").tag(Filter.all)
                    Text("OK").tag(Filter.ok)
                    Text("Failed").tag(Filter.failed)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)

                if shown.isEmpty {
                    Text("No scans yet. Each scan you send shows up here. Test sends don't.")
                        .foregroundStyle(.secondary)
                }
                ForEach(shown) { e in
                    Button { selected = e } label: { HistoryRowView(entry: e) }
                        .buttonStyle(.plain)
                }
            }
            .navigationTitle("History")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Export CSV") { exportCsv() }
                        .disabled(history.entries.isEmpty)
                    Button("Clear", role: .destructive) { confirmClear = true }
                        .disabled(history.entries.isEmpty)
                }
            }
            .sheet(item: $selected) { e in HistoryDetail(entry: e) }
            .sheet(item: $export) { f in ActivityView(items: [f.url]) }
            .confirmationDialog("Clear all history on this device?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Clear", role: .destructive) { history.clear() }
            }
        }
    }

    /// Writes the CSV to a temporary file and hands it to the share sheet.
    private func exportCsv() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("exports", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("tappony-history-\(Int64(Date().timeIntervalSince1970 * 1000)).csv")
        do {
            try Data(HistoryCsv.document(history.exportRows()).utf8).write(to: url, options: .atomic)
            export = ExportFile(url: url)
        } catch {
            export = nil
        }
    }
}

private struct ExportFile: Identifiable {
    let url: URL
    var id: URL { url }
}

struct HistoryRowView: View {
    let entry: HistoryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(HistoryText.outcome(entry)).foregroundStyle(HistoryText.color(entry))
                Spacer()
                Text(HistoryText.time(entry.timeMs)).font(.caption).foregroundStyle(.secondary)
            }
            Text(entry.profileName)
            if !entry.uid.isEmpty {
                Text(entry.uid).font(.system(.footnote, design: .monospaced)).foregroundStyle(.secondary)
            }
            if let m = entry.message { Text(m).lineLimit(1) }
        }
        .contentShape(Rectangle())
    }
}

struct HistoryDetail: View {
    let entry: HistoryEntry
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text(HistoryText.time(entry.timeMs)).foregroundStyle(.secondary)
                    Text(HistoryText.outcome(entry)).foregroundStyle(HistoryText.color(entry))
                    if let m = entry.message { Text(m).font(.title3) }
                    if !entry.uid.isEmpty { Text(entry.uid).font(.system(.body, design: .monospaced)) }
                    let detail = [entry.chip, entry.tagType].filter { !$0.isEmpty }.joined(separator: " · ")
                    if !detail.isEmpty { Text(detail).foregroundStyle(.secondary) }
                    if !entry.error.isEmpty { Text(ErrorText.explain(entry.error)).foregroundStyle(Palette.fail) }
                    if !entry.request.isEmpty { mono(entry.request) }
                    if let b = entry.requestBody {
                        Text("Request body").font(.caption.weight(.semibold))
                        mono(b)
                    }
                    if let b = entry.responseBody {
                        Text("Response body").font(.caption.weight(.semibold))
                        mono(b)
                    }
                    if entry.requestBody == nil && entry.responseBody == nil {
                        Text("Bodies aren't kept for this profile. Turn on \"Keep request and response bodies\" in the profile to see them here.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .navigationTitle(entry.profileName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Close") { dismiss() } }
        }
    }

    private func mono(_ s: String) -> some View {
        Text(s).font(.system(.footnote, design: .monospaced)).foregroundStyle(.secondary)
    }
}

enum HistoryText {
    static func outcome(_ e: HistoryEntry) -> String {
        switch e.outcome {
        case HistoryCsv.ok, HistoryCsv.httpError:
            let head = "HTTP \(e.status.map { String($0) } ?? "")".trimmingCharacters(in: .whitespaces)
            return head + (e.latencyMs.map { " · \($0) ms" } ?? "")
        case HistoryCsv.networkError:
            return String(localized: "Network error")
        default:
            return String(localized: "Not sent")
        }
    }

    static func color(_ e: HistoryEntry) -> Color {
        e.outcome == HistoryCsv.ok ? Palette.ok : Palette.fail
    }

    static func time(_ ms: Int64) -> String {
        Date(timeIntervalSince1970: TimeInterval(ms) / 1000).formatted(date: .numeric, time: .standard)
    }
}

/// The system share sheet for a file.
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
