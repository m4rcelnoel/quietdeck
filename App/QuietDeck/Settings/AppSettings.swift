import Foundation
import Observation
import ServiceManagement

/// A key combination for a global shortcut. Modifiers use Carbon's values.
struct KeyCombo: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    var display: String
}

enum ShortcutAction: String, CaseIterable, Codable, Identifiable {
    case firstMode, secondMode, thirdMode, fourthMode, cycleMode, bringAudioHere

    var id: String { rawValue }

    /// The mode this action selects, by position in the device's list.
    var modeIndex: Int? {
        switch self {
        case .firstMode: return 0
        case .secondMode: return 1
        case .thirdMode: return 2
        case .fourthMode: return 3
        case .cycleMode, .bringAudioHere: return nil
        }
    }
}

/// Preferences, saved on this Mac.
@MainActor
@Observable
final class AppSettings {
    private enum Key {
        static let keepDockIcon = "keepDockIcon"
        static let showModeInMenuBar = "showModeInMenuBar"
        static let showHUD = "showHUD"
        static let showProtocolConsole = "showProtocolConsole"
        static let notifyLowBattery = "notifyLowBattery"
        static let notifyDisconnect = "notifyDisconnect"
        static let completedOnboarding = "completedOnboarding"
        static let shortcuts = "shortcuts"
    }

    private let defaults: UserDefaults

    var keepDockIcon: Bool {
        didSet { defaults.set(keepDockIcon, forKey: Key.keepDockIcon) }
    }
    var showModeInMenuBar: Bool {
        didSet { defaults.set(showModeInMenuBar, forKey: Key.showModeInMenuBar) }
    }
    var showHUD: Bool {
        didSet { defaults.set(showHUD, forKey: Key.showHUD) }
    }
    var showProtocolConsole: Bool {
        didSet { defaults.set(showProtocolConsole, forKey: Key.showProtocolConsole) }
    }
    var notifyLowBattery: Bool {
        didSet { defaults.set(notifyLowBattery, forKey: Key.notifyLowBattery) }
    }
    var notifyDisconnect: Bool {
        didSet { defaults.set(notifyDisconnect, forKey: Key.notifyDisconnect) }
    }
    var completedOnboarding: Bool {
        didSet { defaults.set(completedOnboarding, forKey: Key.completedOnboarding) }
    }
    var shortcuts: [ShortcutAction: KeyCombo] {
        didSet { defaults.set(try? JSONEncoder().encode(shortcuts), forKey: Key.shortcuts) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [Key.showHUD: true, Key.notifyLowBattery: true])
        keepDockIcon = defaults.bool(forKey: Key.keepDockIcon)
        showModeInMenuBar = defaults.bool(forKey: Key.showModeInMenuBar)
        showHUD = defaults.bool(forKey: Key.showHUD)
        showProtocolConsole = defaults.bool(forKey: Key.showProtocolConsole)
        notifyLowBattery = defaults.bool(forKey: Key.notifyLowBattery)
        notifyDisconnect = defaults.bool(forKey: Key.notifyDisconnect)
        completedOnboarding = defaults.bool(forKey: Key.completedOnboarding)
        shortcuts =
            defaults.data(forKey: Key.shortcuts)
            .flatMap { try? JSONDecoder().decode([ShortcutAction: KeyCombo].self, from: $0) } ?? [:]
    }

    /// Removes everything QuietDeck has stored on this Mac.
    func deleteEverything() {
        try? SMAppService.mainApp.unregister()
        if let domain = Bundle.main.bundleIdentifier {
            defaults.removePersistentDomain(forName: domain)
        }
    }

    /// Whether the app starts at login. The system owns this value, so it isn't stored here.
    var launchesAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                // The toggle reads the system's value, so it shows what really happened.
            }
        }
    }
}
