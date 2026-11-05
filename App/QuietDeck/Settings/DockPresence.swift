import AppKit
import SwiftUI

/// Shows the Dock icon while a window is open, unless the user wants it to stay.
@MainActor
enum DockPresence {
    private static var openWindows = 0

    static func windowOpened() {
        openWindows += 1
        show()
    }

    /// The icon is set after the Dock tile exists: an app that starts without one shows
    /// the generic icon, and changing the activation policy resets anything set earlier.
    private static func show() {
        NSApp.setActivationPolicy(.regular)
        DispatchQueue.main.async {
            if let icon = NSImage(named: "AppIcon") {
                NSApp.applicationIconImage = icon
            }
            NSApp.dockTile.display()
        }
    }

    static func windowClosed(keepIcon: Bool) {
        openWindows = max(0, openWindows - 1)
        if openWindows == 0, !keepIcon {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    static func apply(keepIcon: Bool) {
        if keepIcon || openWindows > 0 {
            show()
        } else {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

private struct DockPresenceModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .onAppear { DockPresence.windowOpened() }
            .onDisappear {
                DockPresence.windowClosed(keepIcon: UserDefaults.standard.bool(forKey: AppSettings.Key.keepDockIcon))
            }
    }
}

extension View {
    func dockPresence() -> some View {
        modifier(DockPresenceModifier())
    }
}
