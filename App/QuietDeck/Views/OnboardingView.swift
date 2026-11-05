import QuietDeckCore
import SwiftUI

/// First launch, one idea per step.
struct OnboardingView: View {
    private enum Step: Int, CaseIterable {
        case welcome, bluetooth, device, finish
    }

    let app: AppModel

    @State private var step = Step.welcome
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            content
            Spacer()
            footer
        }
        .padding(28)
        .frame(width: 520, height: 440)
        .dockPresence()
        // The system's Bluetooth dialog takes focus and can leave this window behind others.
        .onChange(of: app.availability) { bringToFront() }
        .onChange(of: app.phase) { bringToFront() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            if step == .device, app.phase != .connected {
                bringToFront()
            }
        }
    }

    private func bringToFront() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first { $0.identifier?.rawValue.contains("onboarding") == true }?.orderFrontRegardless()
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome:
            page(
                symbol: "headphones",
                title: "Welcome to QuietDeck",
                detail:
                    "Control your headphones from the menu bar, without the manufacturer's app. QuietDeck is an independent, unofficial project."
            )
        case .bluetooth:
            page(
                symbol: "dot.radiowaves.left.and.right",
                title: "Allow Bluetooth",
                detail:
                    "QuietDeck talks to your headphones over Bluetooth. When you continue, your Mac may ask for permission."
            )
        case .device:
            deviceStep
        case .finish:
            VStack(spacing: 14) {
                page(
                    symbol: "menubar.arrow.up.rectangle",
                    title: "You're all set",
                    detail: "QuietDeck lives in the menu bar. Click the headphones icon at the top of your screen."
                )
                Toggle(
                    "Launch at login",
                    isOn: Binding(
                        get: { app.settings.launchesAtLogin },
                        set: { app.settings.setLaunchesAtLogin($0) }
                    )
                )
                .toggleStyle(.switch)
            }
        }
    }

    @ViewBuilder
    private var deviceStep: some View {
        switch app.availability {
        case .checking:
            ProgressView("Looking for headphones…")
        case .ready:
            if let controller = app.controller, app.phase == .connected {
                page(
                    symbol: "checkmark.circle",
                    title: "Connected",
                    detail: "Found \(controller.state.name ?? String(localized: "your headphones"))."
                )
            } else if app.phase == .connectionFailed {
                UnavailableContent(app: app)
            } else {
                ProgressView("Connecting…")
            }
        case .bluetoothOff, .noDevice:
            UnavailableContent(app: app)
        }
    }

    private func page(symbol: String, title: LocalizedStringKey, detail: LocalizedStringKey) -> some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 52))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(title)
                .font(.title.weight(.semibold))
            Text(detail)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 400)
        }
    }

    private var footer: some View {
        HStack {
            if step == .device {
                Button("Skip") { advance() }
            }
            Spacer()
            Button(step == .finish ? "Done" : "Continue") { advance() }
                .keyboardShortcut(.defaultAction)
                .disabled(step == .device && app.phase != .connected)
        }
    }

    private func advance() {
        switch step {
        case .welcome:
            step = .bluetooth
        case .bluetooth:
            step = .device
            Task { await app.start() }
        case .device:
            step = .finish
        case .finish:
            app.settings.completedOnboarding = true
            dismissWindow(id: "onboarding")
        }
    }
}
