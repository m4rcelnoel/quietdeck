import SwiftUI

/// A full-size message for when there's nothing to control.
struct UnavailableContent: View {
    let app: AppModel

    var body: some View {
        switch app.availability {
        case .checking:
            ProgressView()
        case .bluetoothOff:
            message(
                "Bluetooth is off",
                systemImage: "exclamationmark.triangle",
                detail: "Turn on Bluetooth to use your headphones.",
                settingsPane: "Open Bluetooth Settings"
            )
        case .noDevice:
            message(
                "No supported headphones found",
                systemImage: "headphones",
                detail: "Pair your headphones in System Settings first.",
                settingsPane: "Open Bluetooth Settings"
            )
        case .ready:
            ContentUnavailableView {
                Label("Couldn't connect", systemImage: "headphones")
            } description: {
                Text("Check that your headphones are on and that no other app is using them.")
            } actions: {
                Button("Try again") { Task { await app.retry() } }
            }
        }
    }

    private func message(
        _ title: LocalizedStringKey,
        systemImage: String,
        detail: LocalizedStringKey,
        settingsPane: LocalizedStringKey
    ) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(detail)
        } actions: {
            Button(settingsPane) {
                if let url = URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings") {
                    NSWorkspace.shared.open(url)
                }
            }
            Button("Check again") { Task { await app.retry() } }
        }
    }
}
