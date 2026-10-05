import StoreKit
import SwiftUI
import UIKit

/// Support, the rest of the Pony family, and About, at the bottom of Settings.
private enum SettingsLink {
    static let docs = URL(string: "https://tappony.app/docs")!
    static let privacy = URL(string: "https://tappony.app/privacy")!
    static let source = URL(string: "https://github.com/norsehorse-dev/TapPony")!
    static let family = URL(string: "https://pony.norsehor.se")!
    static let apache = URL(string: "https://www.apache.org/licenses/LICENSE-2.0")!
    static let feedbackEmail = "NorseHorse@norsehor.se"

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    /// App and OS version only; nothing that identifies the phone.
    static var feedback: URL {
        var c = URLComponents()
        c.scheme = "mailto"
        c.path = feedbackEmail
        c.queryItems = [
            URLQueryItem(name: "subject", value: "TapPony feedback"),
            URLQueryItem(name: "body", value: "\n\n\nTapPony \(appVersion), iOS \(UIDevice.current.systemVersion)"),
        ]
        return c.url ?? URL(string: "mailto:\(feedbackEmail)")!
    }
}

private struct LinkRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let url: URL

    var body: some View {
        Link(destination: url) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: title).foregroundStyle(.primary)
                    Text(verbatim: subtitle).font(.caption).foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: systemImage).foregroundStyle(Palette.blueLight)
            }
        }
    }
}

struct SupportSection: View {
    @Environment(\.requestReview) private var requestReview

    var body: some View {
        Section("Support") {
            LinkRow(title: String(localized: "Help and receiver docs"),
                    subtitle: String(localized: "Setting up a receiver, at tappony.app/docs"),
                    systemImage: "questionmark.circle.fill", url: SettingsLink.docs)
            LinkRow(title: String(localized: "Send feedback"), subtitle: SettingsLink.feedbackEmail,
                    systemImage: "envelope.fill", url: SettingsLink.feedback)
            LinkRow(title: String(localized: "Privacy policy"), subtitle: String(localized: "At tappony.app/privacy"),
                    systemImage: "hand.raised.fill", url: SettingsLink.privacy)
            Button {
                requestReview()
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Rate TapPony").foregroundStyle(.primary)
                        Text("Leave a rating on the App Store").font(.caption).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "star.fill").foregroundStyle(Palette.warn)
                }
            }
        }
    }
}

struct FamilySection: View {
    /// The rest of the Pony family; TapPony itself is left out. Names are brands and stay untranslated.
    private var apps: [(String, String, String, String)] {
        [
            ("PGPony", String(localized: "OpenPGP encryption for messages, files and keys"), "key.horizontal.fill", "https://pgpony.app"),
            ("AgePony", String(localized: "File encryption with the age format"), "lock.fill", "https://agepony.com"),
            ("QuorumPony", String(localized: "Split a secret into cards. Any few rebuild it."), "person.3.fill", "https://quorumpony.com"),
            ("CarrierPony", String(localized: "Private messaging and file transfer, sealed end to end"), "bubble.left.and.bubble.right.fill", "https://carrierpony.com"),
            ("BurnPony", String(localized: "Send a secret. Encrypted on your phone, burned after reading"), "flame.fill", "https://burnpony.app"),
            ("VaultPony", String(localized: "VeraCrypt-compatible encrypted vaults, entirely on your device"), "lock.rectangle.stack.fill", "https://vaultpony.app"),
            ("PassPony", String(localized: "A password manager for pass and passage stores"), "key.fill", "https://passpony.app"),
            ("RelayPony", String(localized: "Encrypted file transfer, phone to phone"), "paperplane.fill", "https://relaypony.app"),
            ("ScrubPony", String(localized: "Strip identifying metadata from images. No pixel moves."), "eraser.fill", "https://scrubpony.app"),
        ]
    }

    var body: some View {
        Section {
            ForEach(apps, id: \.0) { app in
                LinkRow(title: app.0, subtitle: app.1, systemImage: app.2, url: URL(string: app.3)!)
            }
            LinkRow(title: String(localized: "All Pony apps"), subtitle: String(localized: "The whole family at pony.norsehor.se"),
                    systemImage: "square.grid.2x2.fill", url: SettingsLink.family)
        } header: {
            Text("More from NorseHorse")
        } footer: {
            Text("Other apps from the same developer.")
        }
    }
}

struct AboutSection: View {
    var body: some View {
        Section("About") {
            LabeledContent("Version", value: SettingsLink.appVersion)
            Text("Scan a tag, send a request you designed to a server you chose. No account, no cloud, no analytics. Suggested by a tester.")
                .foregroundStyle(.secondary)
            LinkRow(title: String(localized: "Source code"), subtitle: String(localized: "TapPony for iOS on GitHub"),
                    systemImage: "chevron.left.forwardslash.chevron.right", url: SettingsLink.source)
            NavigationLink("Licenses") { LicensesView() }
        }
    }
}

private struct LicensesView: View {
    var body: some View {
        Form {
            Section {
                Text("TapPony is open source under the Apache License 2.0.")
                Text("It uses no third-party code, only Apple's frameworks.").foregroundStyle(.secondary)
                Link("Read the Apache License 2.0", destination: SettingsLink.apache)
            }
        }
        .navigationTitle("Licenses")
        .navigationBarTitleDisplayMode(.inline)
    }
}
