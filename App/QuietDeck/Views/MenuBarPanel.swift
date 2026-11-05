import QuietDeckCore
import SwiftUI

struct MenuBarPanel: View {
    let app: AppModel

    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss

    /// Hidden unless the Option key is held, a setting enables it, or this is a debug build.
    private var showsDeveloperTools: Bool {
        #if DEBUG
            true
        #else
            NSEvent.modifierFlags.contains(.option) || app.settings.showProtocolConsole
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let controller = app.controller, app.availability == .ready {
                PanelContent(controller: controller, app: app) {
                    app.selectedSection = .device(.sources)
                    open("main")
                }
            } else {
                UnavailableContent(app: app)
                    .frame(minHeight: 200)
            }
            footer
        }
        .padding(12)
        .frame(width: 320)
        .task { await app.panelOpened() }
        .onExitCommand { NSApp.keyWindow?.close() }
    }

    /// Opens a window and closes this panel, which would otherwise stay on top of it.
    private func open(_ window: String) {
        dismiss()
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: window)
    }

    private var footer: some View {
        VStack(spacing: 8) {
            Divider()
            HStack {
                Button("Open QuietDeck") {
                    open("main")
                }
                Spacer()
                if showsDeveloperTools {
                    Button {
                        open("protocol-console")
                    } label: {
                        Image(systemName: "terminal")
                    }
                    .accessibilityLabel("Protocol Console")
                }
                Button {
                    app.selectedSection = .settings
                    open("main")
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Settings")
                Button {
                    NSApp.terminate(nil)
                } label: {
                    Image(systemName: "power")
                }
                .accessibilityLabel("Quit QuietDeck")
            }
            .buttonStyle(.borderless)
        }
    }
}

private struct PanelContent: View {
    let controller: DeviceController
    let app: AppModel
    let showAllSources: () -> Void

    private static let sourceLimit = 4

    var body: some View {
        header
        if controller.phase == .connectionFailed || controller.phase == .disconnected {
            Button("Connect") { Task { await app.retry() } }
        }
        Group {
            if controller.capabilities.listeningModes != nil {
                ModeTiles(controller: controller, style: .inline, columns: 2)
                ProblemNote(controller: controller, controls: [.mode])
            }
            if let noise = controller.capabilities.noiseControl, let level = controller.state.noiseLevel {
                HStack(spacing: 10) {
                    Image(systemName: "waveform")
                        .foregroundStyle(.secondary)
                    NoiseLevelControl(controller: controller, level: level, range: noise.range)
                }
                ProblemNote(controller: controller, controls: [.noiseLevel])
            }
            if controller.capabilities.audioSources != nil, let sources = controller.state.sources {
                sourceList(sources)
            }
        }
        .disabled(controller.phase != .connected)
        .opacity(controller.phase == .connected ? 1 : 0.5)
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(controller.displayName)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(controller.statusText)
                    if controller.phase == .connected {
                        Text("·")
                        Text(controller.modeTitle)
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if controller.capabilities.battery != nil {
                BatteryRing(battery: controller.state.battery)
            }
        }
    }

    private func sourceList(_ sources: AudioSourceList) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Audio source")
                .font(.callout)
                .foregroundStyle(.secondary)
            ForEach(sources.byStatus.prefix(Self.sourceLimit)) { source in
                SourceRow(source: source, controller: controller)
            }
            if sources.sources.count > Self.sourceLimit {
                Button("All sources…", action: showAllSources)
                    .buttonStyle(.link)
            }
            ProblemNote(controller: controller, controls: [.source, .connection])
        }
    }
}
