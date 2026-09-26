import Network
import SwiftUI
import TapPonyKit
import UIKit

enum Palette {
    static let charcoal = Color(red: 0x15 / 255, green: 0x18 / 255, blue: 0x1D / 255)
    static let surface = Color(red: 0x1E / 255, green: 0x22 / 255, blue: 0x29 / 255)
    static let blue = Color(red: 0x2F / 255, green: 0x7B / 255, blue: 0xFF / 255)
    static let blueLight = Color(red: 0x7F / 255, green: 0xB0 / 255, blue: 0xFF / 255)
    static let ok = Color(red: 0x46 / 255, green: 0xD1 / 255, blue: 0x7F / 255)
    static let fail = Color(red: 0xF0 / 255, green: 0x57 / 255, blue: 0x5D / 255)
    static let warn = Color(red: 0xE2 / 255, green: 0xA5 / 255, blue: 0x4A / 255)
}

enum AppTab: Hashable {
    case scan, profiles, history, settings
}

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    let profiles = ProfileStore()
    let settings = AppSettings()
    let rules = RulesStore()
    let feedback = Feedback()
    let engine: ScanEngine
    let history: HistoryStore
    let queue: OfflineQueue
    lazy var scanner = ScanController(model: self)

    @Published var tab: AppTab = .scan

    private let pathMonitor = NWPathMonitor()

    private init() {
        engine = ScanEngine(settings: settings)
        history = HistoryStore(db: Database.shared, settings: settings)
        queue = OfflineQueue(db: Database.shared, history: history, profiles: profiles)
        queue.engine = engine
        // Flush the queue whenever the network comes back while the app is running.
        pathMonitor.pathUpdateHandler = { path in
            guard path.status == .satisfied else { return }
            Task { @MainActor in AppModel.shared.queue.kick() }
        }
        pathMonitor.start(queue: DispatchQueue(label: "com.tappony.app.path"))
    }

    var activeProfile: Profile? {
        profiles.profiles.first { $0.id == settings.activeProfileId } ?? profiles.profiles.first
    }

    /// tappony://scan[?profile=<id>]: select that profile if it exists, show the
    /// Scan tab and start a read. Used by the Control Center control, widgets,
    /// Home Screen shortcuts and other apps.
    func open(_ url: URL) {
        guard url.scheme?.lowercased() == "tappony", url.host?.lowercased() == "scan" else { return }
        // A read already running keeps its profile; the link then only brings up the Scan tab.
        guard !scanner.reading, !scanner.batchOn else {
            tab = .scan
            return
        }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if let id = items.first(where: { $0.name == "profile" })?.value, profiles.profile(id) != nil {
            settings.activeProfileId = id
        }
        tab = .scan
        pendingScan = true
        if UIApplication.shared.applicationState == .active { runPendingScan() }
    }

    /// Core NFC only starts once the app is active, so a link that arrives
    /// during launch waits for the scene to become active.
    private var pendingScan = false

    func runPendingScan() {
        guard pendingScan else { return }
        pendingScan = false
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard let self, !self.scanner.batchOn else { return }
            self.scanner.scan()
        }
    }
}

@main
struct TapPonyApp: App {
    @StateObject private var model = AppModel.shared
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            TabView(selection: $model.tab) {
                ScanView()
                    .tabItem { Label("Scan", systemImage: "wave.3.right") }
                    .tag(AppTab.scan)
                ProfilesView()
                    .tabItem { Label("Profiles", systemImage: "slider.horizontal.3") }
                    .tag(AppTab.profiles)
                HistoryView()
                    .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                    .tag(AppTab.history)
                SettingsView()
                    .tabItem { Label("Settings", systemImage: "gearshape") }
                    .tag(AppTab.settings)
            }
            .environmentObject(model)
            .environmentObject(model.profiles)
            .environmentObject(model.settings)
            .environmentObject(model.history)
            .environmentObject(model.queue)
            .environmentObject(model.rules)
            .environmentObject(model.scanner)
            .tint(Palette.blue)
            .preferredColorScheme(.dark)
            .onOpenURL { model.open($0) }
        }
        .onChange(of: phase) { _, now in
            if now == .active {
                model.queue.kick()
                model.runPendingScan()
            }
            if now == .background, model.scanner.batchOn { model.scanner.setBatch(false) }
        }
    }
}
