import AppIntents
import SwiftUI
import WidgetKit

private let scanURL = URL(string: "tappony://scan")!
private let blue = Color(red: 0x2F / 255, green: 0x7B / 255, blue: 0xFF / 255)
private let charcoal = Color(red: 0x15 / 255, green: 0x18 / 255, blue: 0x1D / 255)

@main
struct TapPonyWidgets: WidgetBundle {
    var body: some Widget {
        ScanControl()
        ScanWidget()
    }
}

/// Opens TapPony on the Scan tab and starts a read with the active profile.
/// Core NFC only reads from the foreground app, so every entry point ends here.
struct OpenScanIntent: AppIntent {
    static var title: LocalizedStringResource = "Scan with TapPony"
    static var description = IntentDescription("Opens TapPony and starts a scan with the active profile.")
    static var isDiscoverable = false

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(scanURL))
    }
}

/// Control Center, Lock Screen and Action button control.
struct ScanControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.tappony.app.scan-control") {
            ControlWidgetButton(action: OpenScanIntent()) {
                Label("Scan a Tag", systemImage: "wave.3.right")
            }
        }
        .displayName("Scan a Tag")
        .description("Opens TapPony and starts a scan with the active profile.")
    }
}

struct ScanEntry: TimelineEntry {
    let date: Date
}

struct ScanProvider: TimelineProvider {
    func placeholder(in context: Context) -> ScanEntry { ScanEntry(date: .now) }

    func getSnapshot(in context: Context, completion: @escaping (ScanEntry) -> Void) {
        completion(ScanEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ScanEntry>) -> Void) {
        completion(Timeline(entries: [ScanEntry(date: .now)], policy: .never))
    }
}

/// Home Screen and Lock Screen button. Tapping it opens the Scan tab and starts a read.
struct ScanWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.tappony.app.scan-widget", provider: ScanProvider()) { _ in
            ScanWidgetView()
        }
        .configurationDisplayName("Scan a Tag")
        .description("Opens TapPony and starts a scan with the active profile.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

struct ScanWidgetView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: "wave.3.right").font(.title2)
                }
            default:
                VStack(spacing: 10) {
                    Image(systemName: "wave.3.right.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(blue)
                    Text("Scan a Tag")
                        .font(.headline)
                        .foregroundStyle(.white)
                }
            }
        }
        .containerBackground(charcoal, for: .widget)
        .widgetURL(scanURL)
    }
}
