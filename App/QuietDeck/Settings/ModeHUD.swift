import AppKit
import SwiftUI

/// A short on-screen note after a shortcut, such as the new mode.
@MainActor
final class ModeHUD {
    static let shared = ModeHUD()

    private static let size = NSSize(width: 200, height: 160)

    private var panel: NSPanel?
    private var content: NSHostingView<HUDContent>?
    private var hideTask: Task<Void, Never>?

    func show(title: String, symbol: String) {
        let panel = panel ?? makePanel()
        self.panel = panel
        let view = HUDContent(title: title, symbol: symbol)
        if let content {
            content.rootView = view
        } else {
            let content = NSHostingView(rootView: view)
            panel.contentView = content
            self.content = content
        }
        if let screen = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: screen.midX - Self.size.width / 2, y: screen.minY + screen.height * 0.18))
        }
        panel.orderFrontRegardless()

        hideTask?.cancel()
        hideTask = Task { [weak panel] in
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            panel?.orderOut(nil)
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .transient]
        return panel
    }
}

private struct HUDContent: View {
    let title: String
    let symbol: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 44))
            Text(LocalizedStringKey(title))
                .font(.title3.weight(.medium))
        }
        .frame(width: 200, height: 160)
        .glassSurface(cornerRadius: 24)
        .accessibilityElement(children: .combine)
    }
}
