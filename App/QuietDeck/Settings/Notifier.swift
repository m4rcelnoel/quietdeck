import AppKit
import QuietDeckCore
@preconcurrency import UserNotifications

/// Local notifications. Nothing here leaves this Mac.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    private static let disconnectGrace = Duration.seconds(10)

    private let settings: AppSettings
    private var battery = BatteryAlertMonitor()
    private var disconnectTask: Task<Void, Never>?

    private var center: UNUserNotificationCenter {
        .current()
    }

    init(settings: AppSettings) {
        self.settings = settings
        super.init()
        center.delegate = self
    }

    /// Asks for permission the first time it's needed. Does nothing if already answered.
    func requestPermissionIfNeeded() async {
        guard settings.notifyLowBattery || settings.notifyDisconnect else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    var isDenied: Bool {
        get async {
            await center.notificationSettings().authorizationStatus == .denied
        }
    }

    func batteryChanged(percent: Int) {
        guard battery.update(percent: percent) != nil, settings.notifyLowBattery else { return }
        post(
            title: String(localized: "Low battery"),
            body: String(localized: "Your headphones are at \(percent) %.")
        )
    }

    func phaseChanged(_ phase: DeviceController.Phase) {
        disconnectTask?.cancel()
        guard phase != .connected, settings.notifyDisconnect else { return }
        // Short drops and reconnections aren't worth a notification.
        disconnectTask = Task { [weak self] in
            try? await Task.sleep(for: Self.disconnectGrace)
            guard !Task.isCancelled else { return }
            self?.post(
                title: String(localized: "Connection lost"),
                body: String(localized: "Your headphones are no longer connected.")
            )
        }
    }

    /// Each notification gets its own ID: one reusing an ID still in Notification Center
    /// can replace it silently, without a banner.
    func post(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    /// Without this, nothing appears while the app counts as active.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
