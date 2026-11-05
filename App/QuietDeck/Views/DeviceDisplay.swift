import QuietDeckCore
import SwiftUI

// How device values appear in the interface.

extension ListeningMode.Kind {
    var symbol: String {
        switch self {
        case .quiet: return "moon.fill"
        case .aware: return "ear"
        case .immersion: return "sparkles"
        case .cinema: return "film"
        case .other: return "slider.horizontal.3"
        }
    }

    var summary: LocalizedStringKey {
        switch self {
        case .quiet: return "Full noise cancellation"
        case .aware: return "Hear the world around you"
        case .immersion: return "Spatial sound that follows you"
        case .cinema: return "Wide sound for film"
        case .other: return "A mode from your headphones"
        }
    }
}

extension AudioSource.Kind {
    var symbol: String {
        switch self {
        case .computer: return "laptopcomputer"
        case .phone: return "iphone"
        case .tablet: return "ipad"
        case .auxiliary: return "cable.connector"
        case .unknown: return "dot.radiowaves.left.and.right"
        }
    }
}

extension DeviceController {
    var displayName: String {
        state.name ?? String(localized: "Headphones")
    }

    var statusText: LocalizedStringKey {
        switch phase {
        case .connected: return "Connected"
        case .connecting: return "Connecting…"
        case .disconnected: return "Not connected"
        case .connectionFailed: return "Couldn't connect"
        }
    }

    var modeTitle: LocalizedStringKey {
        modeName.map { LocalizedStringKey($0) } ?? "Custom"
    }

    var modeName: String? {
        switch state.mode {
        case .preset(let id):
            return capabilities.listeningModes?.modes.first { $0.id == id }?.name
        case .custom, nil:
            return nil
        }
    }
}
