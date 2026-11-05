import Foundation
import Observation
import Sparkle
import SwiftUI

/// Finds and installs new versions. It only goes online when the user asks, or after
/// the user has turned automatic checks on.
@MainActor
@Observable
final class AppUpdater {
    private let controller: SPUStandardUpdaterController
    private let reminders = UpdateReminders()
    private var observation: NSKeyValueObservation?

    private(set) var canCheckForUpdates = false

    var checksAutomatically: Bool {
        didSet { controller.updater.automaticallyChecksForUpdates = checksAutomatically }
    }

    init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: false, updaterDelegate: nil, userDriverDelegate: reminders)
        checksAutomatically = controller.updater.automaticallyChecksForUpdates
    }

    /// Diagnostics and demo runs never call this, so they can't show an update window.
    func start() {
        guard observation == nil else { return }
        controller.startUpdater()
        let updater = controller.updater
        observation = updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor in self?.canCheckForUpdates = updater.canCheckForUpdates }
        }
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}

/// A menu bar app is rarely active, so a scheduled check must not take focus from
/// whatever the user is doing.
private final class UpdateReminders: NSObject, SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }
}

/// A view, so that menus follow the updater's state.
struct CheckForUpdatesButton: View {
    let updater: AppUpdater

    var body: some View {
        Button("Check for Updates…") { updater.checkForUpdates() }
            .disabled(!updater.canCheckForUpdates)
    }
}
