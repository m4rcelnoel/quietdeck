import AppKit
import SwiftUI

/// Records one key combination. Escape cancels.
struct ShortcutRecorder: View {
    @Binding var combo: KeyCombo?

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 6) {
            Button {
                isRecording ? stop() : start()
            } label: {
                if isRecording {
                    Text("Press keys…")
                } else if let combo {
                    Text(verbatim: combo.display)
                } else {
                    Text("Record")
                }
            }
            .frame(minWidth: 96)
            if combo != nil {
                Button {
                    combo = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Remove shortcut")
            }
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                stop()
            } else if let recorded = KeyCombo(event: event) {
                combo = recorded
                stop()
            }
            return nil
        }
    }

    private func stop() {
        isRecording = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }
}
