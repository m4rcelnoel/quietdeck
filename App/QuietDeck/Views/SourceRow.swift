import QuietDeckCore
import SwiftUI

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
            (isThisMac ? Text("This Mac") : Text(verbatim: source.name))
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
