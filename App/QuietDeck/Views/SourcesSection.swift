import QuietDeckCore
import SwiftUI

struct SourcesSection: View {
    let controller: DeviceController

    @State private var isConfirmingMultipointOff = false

    private var sources: AudioSourceList? {
        controller.state.sources
    }

    var body: some View {
        group("Active", status: .active)
        group("Connected", status: .connected)
        group("Remembered", status: .remembered)
        ProblemNote(controller: controller, controls: [.source, .connection, .multipoint])
        if controller.capabilities.multipoint != nil, let multipoint = controller.state.multipoint {
            DeckGroup {
                DeckRow {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Multipoint")
                        Text("Stay connected to two devices at once.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("Multipoint", isOn: Binding(get: { multipoint }, set: { setMultipoint($0) }))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .confirmationDialog(
                            "Turn off multipoint?",
                            isPresented: $isConfirmingMultipointOff
                        ) {
                            Button("Turn off", role: .destructive) { controller.setMultipoint(false) }
                            Button("Cancel", role: .cancel) {}
                        } message: {
                            Text("Your other device disconnects and won't reconnect by itself.")
                        }
                }
            }
        }
    }

    /// Turning multipoint off drops the other device, and it doesn't come back by itself.
    private func setMultipoint(_ enabled: Bool) {
        if !enabled, sources?.sources(with: .connected).isEmpty == false {
            isConfirmingMultipointOff = true
        } else {
            controller.setMultipoint(enabled)
        }
    }

    @ViewBuilder
    private func group(_ title: LocalizedStringKey, status: AudioSource.Status) -> some View {
        let matching = sources?.sources(with: status) ?? []
        if !matching.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                    .padding(.leading, 4)
                DeckGroup {
                    ForEach(matching) { source in
                        DeckRow {
                            SourceRow(source: source, controller: controller)
                        }
                    }
                }
            }
        }
    }
}
