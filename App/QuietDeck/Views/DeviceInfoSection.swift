import QuietDeckCore
import SwiftUI

struct DeviceInfoSection: View {
    let controller: DeviceController

    private var state: DeviceState {
        controller.state
    }

    var body: some View {
        HStack(spacing: 14) {
            if controller.capabilities.battery != nil {
                BatteryRing(battery: state.battery, size: 56)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(controller.displayName)
                    .font(.title2.weight(.semibold))
                Text(controller.statusText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .glassSurface(cornerRadius: 14)

        DeckGroup {
            if let firmware = state.firmwareVersion {
                DeckRow {
                    Text("Firmware")
                    Spacer()
                    Text(firmware)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            DeckRow {
                Text("Connection")
                Spacer()
                Text("Bluetooth")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
