import QuietDeckCore
import SwiftUI

@main
struct QuietDeckApp: App {
    @State private var app = AppModel()

    init() {
        #if DEBUG
            if TransportDiagnostics.startIfRequested() || SnapshotRenderer.startIfRequested() {
                isRunningDiagnostics = true
            }
        #endif
    }

    private var isRunningDiagnostics = false

    var body: some Scene {
        MenuBarExtra {
            MenuBarPanel(app: app)
        } label: {
            MenuBarLabel(app: app, isRunningDiagnostics: isRunningDiagnostics)
        }
        .menuBarExtraStyle(.window)

        Window("QuietDeck", id: "main") {
            MainWindow(app: app)
                .dockPresence()
        }
        .defaultSize(width: 760, height: 560)
        .windowResizability(.contentMinSize)
        .commands { AppCommands(app: app) }

        Window("Protocol Console", id: "protocol-console") {
            ProtocolConsoleView(model: app.console)
                .dockPresence()
        }
        .defaultSize(width: 900, height: 640)

        Window("Welcome to QuietDeck", id: "onboarding") {
            OnboardingView(app: app)
        }
        .windowResizability(.contentSize)
    }
}

/// Settings and About live in the main window, so the standard menu items open it.
private struct AppCommands: Commands {
    let app: AppModel

    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About QuietDeck") { show(.about) }
        }
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { show(.settings) }
                .keyboardShortcut(",", modifiers: .command)
        }
    }

    private func show(_ section: WindowSection) {
        app.selectedSection = section
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "main")
    }
}

private struct MenuBarLabel: View {
    let app: AppModel
    let isRunningDiagnostics: Bool

    @Environment(\.openWindow) private var openWindow

    private var symbol: String {
        guard app.settings.showModeInMenuBar, let controller = app.controller,
            case .preset(let id) = controller.state.mode,
            let mode = controller.capabilities.listeningModes?.modes.first(where: { $0.id == id })
        else { return "headphones" }
        return mode.kind.symbol
    }

    var body: some View {
        Image(systemName: symbol)
            .symbolVariant(app.phase == .connected ? .none : .slash)
            .task {
                #if DEBUG
                    if await SnapshotRenderer.runDemoIfRequested(app, openMainWindow: { openWindow(id: "main") }) {
                        return
                    }
                    if await SnapshotRenderer.runSceneClickTestIfRequested(app) { return }
                #endif
                guard !isRunningDiagnostics else { return }
                DockPresence.apply(keepIcon: app.settings.keepDockIcon)
                app.activateShortcuts()
                if app.settings.completedOnboarding {
                    await app.start()
                } else {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "onboarding")
                }
            }
    }
}
