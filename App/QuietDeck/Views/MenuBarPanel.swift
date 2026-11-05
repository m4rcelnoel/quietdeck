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
                PanelContent(controller: controller, app: app)
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
                    LevelSlider(value: level, range: noise.range, label: "Noise control") {
                        controller.setNoiseLevel($0)
                    }
                    Text("\(level)")
                        .monospacedDigit()
                        .frame(width: 22, alignment: .trailing)
                }
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
                Text(controller.state.name ?? String(localized: "Headphones"))
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
            ForEach(sources.sources.prefix(4)) { source in
                SourceRow(source: source, controller: controller)
            }
            ProblemNote(controller: controller, controls: [.source, .connection])
        }
    }
}

/// One audio source with its single action.
struct SourceRow: View {
    let source: AudioSource
    let controller: DeviceController

    @State private var isConfirmingConnect = false

    private var isThisMac: Bool {
        source.id == controller.localSourceID
    }

    /// The device that loses its place, because the headphones hold two connections.
    private var deviceToBeDropped: AudioSource? {
        let connected = (controller.state.sources?.sources ?? []).filter { $0.status != .remembered }
        guard connected.count >= 2 else { return nil }
        return connected.first { $0.id != controller.localSourceID && $0.status != .active }
            ?? connected.first { $0.id != controller.localSourceID }
    }

    private func connect() {
        if deviceToBeDropped != nil {
            isConfirmingConnect = true
        } else {
            Task { await controller.connectSource(source.id) }
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: source.kind.symbol)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Text(isThisMac ? "This Mac" : LocalizedStringKey(source.name))
                .lineLimit(1)
            Spacer()
            switch source.status {
            case .active:
                Image(systemName: "checkmark")
                    .foregroundStyle(.tint)
                    .accessibilityLabel("Active")
            case .connected:
                if controller.switchingSource == source.id {
                    ProgressView()
                        .controlSize(.small)
                } else if isThisMac, controller.localStream != nil {
                    Button("Bring audio here") {
                        Task { await controller.bringAudioHere() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            case .remembered:
                if controller.connectingSource == source.id {
                    ProgressView()
                        .controlSize(.small)
                } else if controller.capabilities.audioSources?.canConnect == true {
                    Button("Connect", action: connect)
                        .controlSize(.small)
                        .disabled(controller.connectingSource != nil)
                        .confirmationDialog(
                            "Connect \(source.name)?",
                            isPresented: $isConfirmingConnect
                        ) {
                            Button("Connect") {
                                Task { await controller.connectSource(source.id) }
                            }
                            Button("Cancel", role: .cancel) {}
                        } message: {
                            Text(
                                "Your headphones hold two connections, so \(deviceToBeDropped?.name ?? "another device") disconnects."
                            )
                        }
                } else {
                    Text("Not connected")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(minHeight: 28)
    }
}
