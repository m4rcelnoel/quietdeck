import QuietDeckCore
import SwiftUI

/// Preferences, shown as a page of the main window.
struct SettingsPage: View {
    let app: AppModel

    @State private var notificationsDenied = false

    var body: some View {
        @Bindable var settings = app.settings
        section("General") {
            DeckGroup {
                DeckRow {
                    Toggle(
                        "Launch at login",
                        isOn: Binding(
                            get: { settings.launchesAtLogin },
                            set: { settings.launchesAtLogin = $0 }
                        )
                    )
                    .toggleRow()
                }
                DeckRow { Toggle("Keep the Dock icon", isOn: $settings.keepDockIcon).toggleRow() }
                DeckRow {
                    Toggle("Show the current mode in the menu bar", isOn: $settings.showModeInMenuBar).toggleRow()
                }
                DeckRow { Toggle("Show a note when a shortcut is used", isOn: $settings.showHUD).toggleRow() }
            }
        }
        .onChange(of: settings.keepDockIcon) { DockPresence.apply(keepIcon: settings.keepDockIcon) }

        section("Notifications") {
            DeckGroup {
                DeckRow {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Low battery")
                        Text("At 20 % and 10 %.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("Low battery", isOn: $settings.notifyLowBattery)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                DeckRow {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Connection lost")
                        Text("When your headphones stay away for more than 10 seconds.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("Connection lost", isOn: $settings.notifyDisconnect)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                if notificationsDenied {
                    DeckRow {
                        Text("Notifications are turned off in System Settings.")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Open System Settings") {
                            if let url = URL(
                                string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")
                            {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                }
            }
        }
        .task(id: settings.notifyLowBattery || settings.notifyDisconnect) {
            await app.notifier.requestPermissionIfNeeded()
            // The demo mode has no permission, and shouldn't show a warning in screenshots.
            let isDemo = ProcessInfo.processInfo.arguments.contains("--demo")
            notificationsDenied = await app.notifier.isDenied && !isDemo
        }

        section("Shortcuts") {
            DeckGroup {
                ForEach(ShortcutAction.allCases) { action in
                    if let title = title(for: action) {
                        DeckRow {
                            Text(title)
                            Spacer()
                            ShortcutRecorder(combo: binding(for: action))
                        }
                    }
                }
            }
        }

        section("Advanced") {
            DeckGroup {
                DeckRow {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Show Protocol Console")
                        Text("For developers. Raw frames can change device state.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("Show Protocol Console", isOn: $settings.showProtocolConsole)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }
        }
    }

    private func section(_ title: LocalizedStringKey, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
                .padding(.leading, 4)
            content()
        }
    }

    private func title(for action: ShortcutAction) -> LocalizedStringKey? {
        if let index = action.modeIndex {
            let modes = app.controller?.capabilities.listeningModes?.modes ?? []
            return index < modes.count ? LocalizedStringKey(modes[index].name) : nil
        }
        return action == .cycleMode ? "Next mode" : "Bring audio here"
    }

    private func binding(for action: ShortcutAction) -> Binding<KeyCombo?> {
        Binding(
            get: { app.settings.shortcuts[action] },
            set: { combo in
                app.settings.shortcuts[action] = combo
                GlobalShortcuts.shared.register(app.settings.shortcuts)
            }
        )
    }
}

extension Toggle {
    /// A full-width row with the switch on the trailing edge.
    func toggleRow() -> some View {
        toggleStyle(.switch)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(TrailingSwitch())
    }
}

private struct TrailingSwitch: ViewModifier {
    func body(content: Content) -> some View {
        LabeledContent {
            EmptyView()
        } label: {
            content
        }
    }
}

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
                        "QuietDeck works entirely on this Mac. There is no account, no analytics and no tracking, and nothing is sent to a server."
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

/// Shows the Dock icon while a window is open, unless the user wants it to stay.
@MainActor
enum DockPresence {
    private static var openWindows = 0

    static func windowOpened() {
        openWindows += 1
        show()
    }

    /// The icon is set after the Dock tile exists: an app that starts without one shows
    /// the generic icon, and changing the activation policy resets anything set earlier.
    private static func show() {
        NSApp.setActivationPolicy(.regular)
        DispatchQueue.main.async {
            if let icon = NSImage(named: "AppIcon") {
                NSApp.applicationIconImage = icon
            }
            NSApp.dockTile.display()
        }
    }

    static func windowClosed(keepIcon: Bool) {
        openWindows = max(0, openWindows - 1)
        if openWindows == 0, !keepIcon {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    static func apply(keepIcon: Bool) {
        if keepIcon || openWindows > 0 {
            show()
        } else {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

private struct DockPresenceModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .onAppear { DockPresence.windowOpened() }
            .onDisappear {
                DockPresence.windowClosed(keepIcon: UserDefaults.standard.bool(forKey: "keepDockIcon"))
            }
    }
}

extension View {
    func dockPresence() -> some View {
        modifier(DockPresenceModifier())
    }
}
