import SwiftUI

/// Who made the app, what it does with data, and how to remove that data.
struct AboutPage: View {
    private static let license = URL(string: "https://www.apache.org/licenses/LICENSE-2.0")!

    let app: AppModel

    @State private var isConfirmingDelete = false

    private var version: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "") (\(info?["CFBundleVersion"] as? String ?? ""))"
    }

    var body: some View {
        VStack(spacing: 6) {
            Image(nsImage: NSImage(named: "AppIcon") ?? NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)
            Text(verbatim: "QuietDeck")
                .font(.title2.weight(.semibold))
            Text("Version \(version)")
                .foregroundStyle(.secondary)
            Text("Developed by m4rcelnoel")
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)

        DeckGroup {
            DeckRow {
                Text(
                    "QuietDeck is an independent, unofficial project. It is not affiliated with or endorsed by any headphone manufacturer. Product names are used only to describe compatibility."
                )
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            DeckRow {
                Text(
                    "Bose and QuietComfort are trademarks of their respective owner. QuietDeck is provided as is, without warranty, and you use it at your own risk."
                )
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            DeckRow {
                Text("License")
                Spacer()
                Link(destination: Self.license) {
                    Text(verbatim: "Apache License 2.0")
                }
            }
        }

        VStack(alignment: .leading, spacing: 6) {
            Text("Privacy")
                .font(.headline)
                .padding(.leading, 4)
            DeckGroup {
                DeckRow {
                    Text(
                        "QuietDeck works on this Mac. There is no account, no analytics and no tracking. The only server it contacts is GitHub, when you check for updates, and GitHub then sees your IP address."
                    )
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                DeckRow {
                    Text(
                        "Device names and Bluetooth addresses are only used on this Mac to show your devices. Settings and presets are stored locally."
                    )
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                DeckRow {
                    Text("Delete all QuietDeck data on this Mac")
                    Spacer()
                    Button("Delete…", role: .destructive) { isConfirmingDelete = true }
                        .confirmationDialog("Delete all data?", isPresented: $isConfirmingDelete) {
                            Button("Delete and quit", role: .destructive) { app.deleteAllData() }
                            Button("Cancel", role: .cancel) {}
                        } message: {
                            Text("Your settings, presets and shortcuts are removed, and QuietDeck quits.")
                        }
                }
            }
        }
    }
}
