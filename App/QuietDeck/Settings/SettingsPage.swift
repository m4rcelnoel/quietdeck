import QuietDeckCore
import SwiftUI

/// Preferences, shown as a page of the main window.
struct SettingsPage: View {
    let app: AppModel

    @State private var notificationsDenied = false

    var body: some View {
        @Bindable var settings = app.settings
        @Bindable var updater = app.updater
        section("General") {
            DeckGroup {
                SwitchRow(
                    title: "Launch at login",
                    isOn: Binding(
                        get: { settings.launchesAtLogin },
                        set: { settings.setLaunchesAtLogin($0) }
                    )
                )
                SwitchRow(title: "Keep the Dock icon", isOn: $settings.keepDockIcon)
                SwitchRow(title: "Show the current mode in the menu bar", isOn: $settings.showModeInMenuBar)
                SwitchRow(title: "Show a note when a shortcut is used", isOn: $settings.showHUD)
            }
        }
        .onAppear { settings.reloadLaunchAtLogin() }
        .onChange(of: settings.keepDockIcon) { DockPresence.apply(keepIcon: settings.keepDockIcon) }

        section("Notifications") {
            DeckGroup {
                SwitchRow(title: "Low battery", detail: "At 20 % and 10 %.", isOn: $settings.notifyLowBattery)
                SwitchRow(
                    title: "Connection lost",
                    detail: "When your headphones stay away for more than 10 seconds.",
                    isOn: $settings.notifyDisconnect
                )
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

        section("Updates") {
            DeckGroup {
                SwitchRow(
                    title: "Check for updates automatically",
                    detail: "Off by default. QuietDeck asks GitHub once a day, and GitHub sees your IP address.",
                    isOn: $updater.checksAutomatically
                )
                DeckRow {
                    Spacer()
                    CheckForUpdatesButton(updater: app.updater)
                }
            }
        }

        section("Advanced") {
            DeckGroup {
                SwitchRow(
                    title: "Show Protocol Console",
                    detail: "For developers. Raw frames can change device state.",
                    isOn: $settings.showProtocolConsole
                )
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
