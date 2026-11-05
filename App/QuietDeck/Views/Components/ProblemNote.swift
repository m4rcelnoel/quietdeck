import QuietDeckCore
import SwiftUI

/// A short inline note about a failed command, shown next to its control.
struct ProblemNote: View {
    let controller: DeviceController
    let controls: [DeviceController.Control]

    var body: some View {
        if let problem = controller.problem, controls.contains(problem.control) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(message(problem))
                Spacer()
            }
            .font(.callout)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }

    private func message(_ problem: DeviceController.Problem) -> LocalizedStringKey {
        switch (problem.kind, problem.control) {
        case (.notAvailable, _):
            return "Not available on this firmware."
        case (.failed, .connection):
            return "Couldn't connect. Check that the device is on and its Bluetooth is turned on."
        case (.failed, .source):
            return "Couldn't bring audio here. Try again in a moment."
        case (.failed, _):
            return "Couldn't apply that. Your headphones keep their last setting."
        }
    }
}
