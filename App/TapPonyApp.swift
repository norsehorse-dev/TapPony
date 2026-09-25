import SwiftUI
import TapPonyKit

enum Palette {
    static let charcoal = Color(red: 0x15 / 255, green: 0x18 / 255, blue: 0x1D / 255)
    static let surface = Color(red: 0x1E / 255, green: 0x22 / 255, blue: 0x29 / 255)
    static let blue = Color(red: 0x2F / 255, green: 0x7B / 255, blue: 0xFF / 255)
    static let blueLight = Color(red: 0x7F / 255, green: 0xB0 / 255, blue: 0xFF / 255)
    static let ok = Color(red: 0x46 / 255, green: 0xD1 / 255, blue: 0x7F / 255)
    static let fail = Color(red: 0xF0 / 255, green: 0x57 / 255, blue: 0x5D / 255)
    static let warn = Color(red: 0xE2 / 255, green: 0xA5 / 255, blue: 0x4A / 255)
}

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    let profiles = ProfileStore()
    let settings = AppSettings()
    lazy var engine = ScanEngine(settings: settings)

    var activeProfile: Profile? {
        profiles.profiles.first { $0.id == settings.activeProfileId } ?? profiles.profiles.first
    }
}

@main
struct TapPonyApp: App {
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        WindowGroup {
            TabView {
                ScanView()
                    .tabItem { Label("Scan", systemImage: "wave.3.right") }
                ProfilesView()
                    .tabItem { Label("Profiles", systemImage: "slider.horizontal.3") }
                SettingsView()
                    .tabItem { Label("Settings", systemImage: "gearshape") }
            }
            .environmentObject(model)
            .environmentObject(model.profiles)
            .environmentObject(model.settings)
            .tint(Palette.blue)
            .preferredColorScheme(.dark)
        }
    }
}
